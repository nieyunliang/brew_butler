import Foundation
import Observation

@MainActor
struct ChangeTask: Identifiable {
    enum Kind: String {
        case install
        case uninstall
        case upgrade
        case upgradeAll
        case upgradeDryRun
        case pin
        case unpin
        case reinstall
        case cleanup
        case autoremove
        case service
        case bundleInstall
        case updateIndex
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var commandText: String
    var packageID: String?
    var packageName: String?
    var packageKind: PackageSnapshot.Kind?
    var isDangerous = false
    var verifyOutdated = false
    /// Tasks sharing a batch id are aggregated into one TaskBatchSummary.
    var batchID: UUID?
    /// Optional key that prevents duplicate aggregate tasks (全部更新 / 索引更新).
    var dedupKey: String?
    /// When non-empty, verification only requires these packages to disappear
    /// from `outdated` (used by the security-only `--vulnerable` path).
    var verifyNames: [String] = []
    /// Rows for the progress panel on aggregate tasks (全部更新 / 更新安全项).
    /// Per-package tasks derive their row from packageName instead.
    var progressTargets: [ProgressTarget] = []
    /// Display-only version texts for the progress row (from → to).
    var fromVersionText: String?
    var toVersionText: String?
    var run: (BrewClient, @escaping @Sendable (ProcessEvent) -> Void) async throws -> ProcessResult

    struct ProgressTarget: Equatable {
        var name: String
        var kind: String?
        var fromVersion: String?
        var toVersion: String?
    }
}

/// One row in the update progress panel. Stage/attribution comes from
/// `BrewProgressParser` and is display-only; success/failure still comes from
/// exit codes and outdated verification via the owning TaskRecord.
struct PackageProgressItem: Identifiable, Equatable {
    enum State: Equatable {
        case pending
        case running
        case succeeded
        /// P1-9: brew 成功退出，但随后的 `brew outdated` 校验失败——既不能算
        /// 成功，也不能算失败；必须单独展示，否则批次面板会把 30 个未确认
        /// 包全画成绿色。
        case unverified
        case failed
        case cancelled
        /// The aggregate task stopped before reaching this row.
        case skipped

        var isTerminal: Bool {
            switch self {
            case .succeeded, .unverified, .failed, .cancelled, .skipped: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .pending: return "排队中"
            case .running: return "运行中"
            case .succeeded: return "完成"
            case .unverified: return "未确认"
            case .failed: return "失败"
            case .cancelled: return "已取消"
            case .skipped: return "未执行"
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: String?
    var fromVersion: String?
    var toVersion: String?
    var stage: BrewProgressStage?
    var state: State
    var errorMessage: String?
    /// TaskRecord that owns this row. Multiple rows can share one recordID on
    /// aggregate tasks; per-package tasks have a 1:1 mapping.
    var recordID: UUID
}

/// Read-only snapshot of one task waiting in the serial change queue.
///
/// `pending` is the queue's private source of truth; this observable snapshot
/// exists so the drawer can list queued items and the updates rows can show
/// their queue position. It is rebuilt after every pending mutation.
struct QueuedTask: Identifiable, Equatable {
    var id: UUID
    var title: String
    var commandText: String
    var packageName: String?
    var packageKind: String?
    /// 1-based position in the queue (1 = next to run).
    var position: Int
}

@MainActor
@Observable
final class TaskQueueStore {
    private(set) var records: [TaskRecord] = []
    private(set) var logs: [LogLine] = []
    private(set) var currentRecordID: UUID?
    private(set) var currentPID: Int32?
    private(set) var isPaused = false
    private(set) var logsTruncated = false
    private(set) var progressItems: [PackageProgressItem] = []
    private(set) var progressTitle: String?
    private(set) var progressSkippedCount = 0
    /// C-15/C-17: batch clock. Reset when a new panel starts, frozen when the
    /// last row reaches a terminal state so 已用时间 stays readable afterwards.
    private(set) var progressStartedAt: Date?
    private(set) var progressFinishedAt: Date?
    /// C-15: last moment brew wrote a line, used for 「等待 brew 输出…」.
    private(set) var lastOutputAt: Date?
    /// Observable snapshot of `pending` for the drawer's 排队中 section and for
    /// per-row queue positions (the queue itself must stay private so views
    /// cannot mutate it directly).
    private(set) var queuedTasks: [QueuedTask] = []
    /// Non-nil while the drawer shows a historical record instead of the live
    /// task. Cleared by `followLatestRecord()`.
    private(set) var selectedRecordID: UUID?
    /// Log lines of the record selected via `openHistoryRecord`.
    private(set) var historyLogLines: [LogLine] = []
    private(set) var historyLogsTruncated = false
    /// 任务岛是否展开（v2 取代日志抽屉；O-02：任务开始不自动展开，只由用户触发）。
    var showDrawer = false
    var drawerPinned = false

    @ObservationIgnored private var pending: [ChangeTask] = []
    @ObservationIgnored private var taskByID: [UUID: ChangeTask] = [:]
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var executionTask: Task<Void, Never>?
    @ObservationIgnored private let logStore = TaskLogStore()
    @ObservationIgnored private let historyStore = TaskHistoryStore()

    private struct ActiveBatch {
        var id: UUID
        var title: String
        var taskIDs: [UUID] = []
        var skipped: Int
        var startedAt: Date
        var remainingOutdated: Int?
    }

    @ObservationIgnored private var batches: [UUID: ActiveBatch] = [:]

    @ObservationIgnored var client: BrewClient?
    @ObservationIgnored var onMutationFinished: (() async -> Void)?
    @ObservationIgnored var onTaskFinished: ((TaskRecord) -> Void)?
    @ObservationIgnored var onBatchFinished: ((TaskBatchSummary) -> Void)?

    init() {
        loadHistory()
    }

    var runningRecord: TaskRecord? {
        currentRecordID.flatMap { id in records.first { $0.id == id } }
    }

    var latestRecord: TaskRecord? { runningRecord ?? records.first }

    var pendingCount: Int { queuedTasks.count }

    /// Snapshot for the drawer's 排队中 list; also exposed for the command
    /// palette / tests via fix-plan §3 (`pendingRecords`).
    var pendingRecords: [QueuedTask] { queuedTasks }

    /// The record the drawer should render: the explicitly selected history
    /// record, otherwise the live/latest task.
    var displayedRecord: TaskRecord? {
        if let selectedRecordID {
            // A selected record can disappear through 清除已完成 while the
            // drawer is open; fall back to the live record instead of blank.
            if let selected = records.first(where: { $0.id == selectedRecordID }) {
                return selected
            }
        }
        return latestRecord
    }

    var isShowingHistory: Bool { selectedRecordID != nil }

    /// Log lines backing the console: live lines or the selected history log.
    var displayedLogLines: [LogLine] { isShowingHistory ? historyLogLines : logs }
    var displayedLogsTruncated: Bool { isShowingHistory ? historyLogsTruncated : logsTruncated }

    var isRunning: Bool { currentRecordID != nil }

    /// 1-based queue position for an unstarted task, nil when it is already
    /// running or no longer queued.
    func queuePosition(for recordID: UUID) -> Int? {
        queuedTasks.first(where: { $0.id == recordID })?.position
    }

    /// True when the retry closure is still in memory. Records loaded from
    /// disk after a relaunch cannot be replayed; the UI then offers
    /// 「复制命令」 instead (C-07).
    func canRetry(recordID: UUID) -> Bool {
        taskByID[recordID] != nil
    }

    // MARK: - Progress panel

    var progressDoneCount: Int { progressItems.filter { $0.state == .succeeded }.count }
    var progressFailedCount: Int { progressItems.filter { $0.state == .failed }.count }
    var progressUnverifiedCount: Int { progressItems.filter { $0.state == .unverified }.count }
    var progressCancelledCount: Int { progressItems.filter { $0.state == .cancelled }.count }
    /// C-15: 失败 / 取消 / 未执行都算「已处理」，避免失败批次永远停在 0/N。
    var progressProcessedCount: Int { progressItems.filter { $0.state.isTerminal }.count }
    var hasProgressPanel: Bool { !progressItems.isEmpty }
    var progressFinished: Bool { !progressItems.isEmpty && progressItems.allSatisfy { $0.state.isTerminal } }

    // MARK: - Batches

    /// Start a logical batch (全部更新 / 更新所选). The summary is emitted once
    /// every task belonging to the batch reaches a terminal state.
    func beginBatch(title: String, skipped: Int = 0) -> UUID {
        let id = UUID()
        batches[id] = ActiveBatch(id: id, title: title, skipped: skipped, startedAt: Date())
        return id
    }

    /// True when a task with this dedup key is queued or running. Used to keep
    /// the user from queueing a second 全部更新 while one is still active.
    func hasActiveDedupKey(_ key: String) -> Bool {
        let activeIDs = Set(records.filter { !$0.status.isTerminal }.map(\.id))
        return taskByID.contains { id, task in
            activeIDs.contains(id) && task.dedupKey == key
        }
    }

    // MARK: - Enqueue

    /// C-17: drop rows that belong to a previous, already-finished task so a new
    /// batch never inherits stale rows / elapsed time / skip counts. Rows of the
    /// task currently executing are kept — they are still live.
    private func prepareProgressPanel(for task: ChangeTask) {
        let liveRecordIDs = Set(records.filter { !$0.status.isTerminal }.map(\.id))
        let runningRecordIDs = Set(records.filter { $0.status == .running || $0.status == .cancelling }.map(\.id))
        let staleExists = progressItems.contains { item in
            item.recordID != task.id && !liveRecordIDs.contains(item.recordID)
        }
        // 新批次不得继承另一批（或已完成单任务）的行；只有正在运行的任务的
        // 行是活的进度来源，其余混进同一面板会让「已处理 x/y」失真。
        let rowBatchID: UUID? = progressItems.lazy.compactMap { self.taskByID[$0.recordID]?.batchID }.first
        let startsOtherBatch = task.batchID != nil
            && !progressItems.isEmpty
            && runningRecordIDs.isEmpty
            && rowBatchID != task.batchID
        if startsOtherBatch {
            progressItems.removeAll()
        } else if progressFinished || staleExists {
            progressItems.removeAll { item in
                item.recordID != task.id && !liveRecordIDs.contains(item.recordID)
            }
        }
        if progressItems.isEmpty {
            progressSkippedCount = 0
            progressStartedAt = Date()
            progressFinishedAt = nil
        }
        lastOutputAt = Date()
    }

    func enqueue(_ task: ChangeTask) {
        // C-17: reset a previous batch's terminal rows / clock before the new
        // task's rows are appended. Live rows (the task currently executing)
        // stay visible — they are the only place that task's progress exists.
        prepareProgressPanel(for: task)
        if let batchID = task.batchID, let batch = batches[batchID] {
            progressSkippedCount = batch.skipped
            progressTitle = batch.title
        } else if !task.progressTargets.isEmpty {
            progressTitle = task.title
        } else if progressTitle == nil, task.packageName != nil {
            progressTitle = task.title
        }
        if !task.progressTargets.isEmpty {
            progressItems.append(
                contentsOf: task.progressTargets.map { target in
                    PackageProgressItem(
                        name: target.name,
                        kind: target.kind,
                        fromVersion: target.fromVersion,
                        toVersion: target.toVersion,
                        state: .pending,
                        recordID: task.id
                    )
                }
            )
        } else if let name = task.packageName {
            progressItems.append(
                PackageProgressItem(
                    name: name,
                    kind: task.packageKind?.rawValue,
                    fromVersion: task.fromVersionText,
                    toVersion: task.toVersionText,
                    state: .pending,
                    recordID: task.id
                )
            )
        }
        pending.append(task)
        refreshQueueSnapshot()
        taskByID[task.id] = task
        if let batchID = task.batchID, batches[batchID] != nil {
            batches[batchID]?.taskIDs.append(task.id)
        }
        let record = TaskRecord(
            id: task.id,
            title: task.title,
            commandText: task.commandText,
            action: task.kind.rawValue,
            packageID: task.packageID,
            packageName: task.packageName,
            packageKind: task.packageKind?.rawValue,
            status: .pending,
            createdAt: Date()
        )
        records.insert(record, at: 0)
        persist()
        startIfNeeded()
    }

    func cancelCurrent() {
        guard let currentRecordID, let index = records.firstIndex(where: { $0.id == currentRecordID }) else { return }
        // F4.4 / C-03: after a cancel the queue must not silently continue with
        // the next task. Pause first (before the cancellation is observed by
        // the loop) and let the user decide: 继续队列 or remove queued items.
        if !pending.isEmpty {
            isPaused = true
        }
        records[index].status = .cancelling
        executionTask?.cancel()
    }

    /// Removes one queued (not yet started) task. The record is kept as
    /// cancelled so batch accounting and history still see it.
    func removePending(id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let task = pending.remove(at: index)
        if let recordIndex = records.firstIndex(where: { $0.id == id }) {
            records[recordIndex].status = .cancelled
            records[recordIndex].finishedAt = Date()
            records[recordIndex].message = "已从队列移除，未执行。"
            records[recordIndex].suggestion = "如需执行，请重新选择更新。"
        }
        applyProgressStatus(recordID: task.id, status: .cancelled, message: nil)
        refreshQueueSnapshot()
        if pending.isEmpty && !isRunning {
            isPaused = false
        }
        persist()
        finishBatchIfComplete(recordID: task.id)
    }

    func pauseQueue() {
        isPaused = true
    }

    func resumeQueue() {
        guard isPaused else { return }
        isPaused = false
        startIfNeeded()
    }

    func clearFinished() {
        records.removeAll { $0.status.isTerminal }
        if let selectedRecordID, !records.contains(where: { $0.id == selectedRecordID }) {
            followLatestRecord()
        }
        if progressFinished {
            progressItems = []
            progressTitle = nil
            progressSkippedCount = 0
            progressStartedAt = nil
            progressFinishedAt = nil
            lastOutputAt = nil
        }
        // Clearing finished records must not leave a half-visible batch behind;
        // drop the cleared task ids and forget batches that become empty.
        let remainingIDs = Set(records.map(\.id))
        for key in batches.keys {
            batches[key]?.taskIDs.removeAll { !remainingIDs.contains($0) }
            if batches[key]?.taskIDs.isEmpty == true {
                batches.removeValue(forKey: key)
            }
        }
        persist()
    }

    /// True when a task for this package is queued or running.
    func hasActivePackage(packageID: String) -> Bool {
        records.contains { $0.packageID == packageID && !$0.status.isTerminal }
    }

    enum RetryResult {
        case started
        case duplicate
        /// The task is dangerous (卸载 / 清理 / autoremove) and must pass a
        /// second-confirmation sheet before it can be re-enqueued.
        case needsConfirmation
        /// The task was loaded from persisted history, so its executable closure
        /// is gone; it cannot be replayed from memory.
        case unavailable
    }

    /// Re-runs a finished task. Refuses when the same package (or the same
    /// dedup key, for aggregate tasks) already has an active task, and requires
    /// an explicit confirmation for dangerous tasks so a retry cannot bypass
    /// the guards that the original submission went through.
    @discardableResult
    func retry(recordID: UUID, confirmDangerous: Bool = false) -> RetryResult {
        guard let original = taskByID[recordID] else { return .unavailable }
        if let key = original.dedupKey, hasActiveDedupKey(key) {
            return .duplicate
        }
        if let packageID = original.packageID,
           records.contains(where: { $0.packageID == packageID && !$0.status.isTerminal }) {
            return .duplicate
        }
        if original.isDangerous && !confirmDangerous {
            return .needsConfirmation
        }
        let copy = ChangeTask(
            kind: original.kind,
            title: "重试：" + original.title,
            commandText: original.commandText,
            packageID: original.packageID,
            packageName: original.packageName,
            packageKind: original.packageKind,
            isDangerous: original.isDangerous,
            verifyOutdated: original.verifyOutdated,
            dedupKey: original.dedupKey,
            verifyNames: original.verifyNames,
            progressTargets: original.progressTargets,
            fromVersionText: original.fromVersionText,
            toVersionText: original.toVersionText,
            run: original.run
        )
        enqueue(copy)
        return .started
    }

    func closeDrawer() {
        showDrawer = false
    }

    func logText(for record: TaskRecord) -> String {
        guard let fileName = record.logFileName else { return "" }
        return logStore.text(for: fileName)
    }

    /// C-13: file location for 「打开完整日志」 — the console truncates at 4000
    /// lines while the file keeps everything.
    func logFileURL(for record: TaskRecord) -> URL? {
        guard let fileName = record.logFileName else { return nil }
        return logStore.fileURL(for: fileName)
    }

    // MARK: - Queue snapshot

    /// Rebuilds the observable queue snapshot. Called after every mutation of
    /// `pending` so `queuedTasks` can never drift from the real order.
    private func refreshQueueSnapshot() {
        queuedTasks = pending.enumerated().map { index, task in
            QueuedTask(
                id: task.id,
                title: task.title,
                commandText: task.commandText,
                packageName: task.packageName,
                packageKind: task.packageKind?.rawValue,
                position: index + 1
            )
        }
    }

    /// Marks the not-yet-started tasks of a batch as cancelled and drops them
    /// from the queue. Used when the running task of that batch is cancelled
    /// (F4.4: the rest must not start after a cancel).
    private func cancelQueuedBatchRemainder(batchID: UUID) {
        let remainder = pending.filter { $0.batchID == batchID }
        guard !remainder.isEmpty else { return }
        pending.removeAll { $0.batchID == batchID }
        for task in remainder {
            if let index = records.firstIndex(where: { $0.id == task.id }) {
                records[index].status = .cancelled
                records[index].finishedAt = Date()
                records[index].message = "已取消，未执行。"
                records[index].suggestion = "重新勾选该包即可重新加入更新。"
            }
            applyProgressStatus(recordID: task.id, status: .cancelled, message: nil)
        }
        refreshQueueSnapshot()
    }

    // MARK: - Loop

    private func startIfNeeded() {
        guard loopTask == nil, !pending.isEmpty, !isPaused else { return }
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
            self.loopTask = nil
            if !self.pending.isEmpty && !self.isPaused {
                self.startIfNeeded()
            }
        }
    }

    private func processQueue() async {
        while !pending.isEmpty && !isPaused {
            let task = pending.removeFirst()
            refreshQueueSnapshot()
            await execute(task)
        }
    }

    private func execute(_ task: ChangeTask) async {
        guard let client else {
            markFailed(task: task, message: "Homebrew 尚未就绪，无法执行任务。", suggestion: "请先在设置中确认 brew 路径。")
            return
        }
        guard let index = records.firstIndex(where: { $0.id == task.id }) else { return }

        records[index].status = .running
        records[index].startedAt = Date()
        currentRecordID = task.id
        currentPID = nil
        applyProgressStatus(recordID: task.id, status: .running, message: nil)
        logs = []
        logsTruncated = false
        lastOutputAt = Date()
        // P1-1：新任务开始时必须回到实时日志。若保留用户此前选中的历史记录，
        // 失败 toast 的「查看」会打开旧记录，用户看不到本次失败原因。
        selectedRecordID = nil
        // O-02（用户决策）：任务开始不再自动展开任务岛，只以折叠胶囊出现；
        // 展开只由用户点击、⌥⌘L 或「查看日志」触发。
        let logName = logStore.begin(recordID: task.id)
        records[index].logFileName = logName
        persist()

        let execution = Task { [weak self] () -> Void in
            guard let self else { return }
            // Output events are funneled through one stream consumed by a single
            // pump task: spawning a detached Task per event gives no ordering
            // guarantee on the main actor, which scrambled log lines and the
            // progress-row state machine.
            let (events, eventContinuation) = AsyncStream<ProcessEvent>.makeStream(bufferingPolicy: .unbounded)
            let pump = Task { [weak self] in
                for await event in events {
                    self?.handle(event: event, recordID: task.id)
                }
            }
            // 显式保留引用，避免编译器把任务视为未使用；任务由 stream 生命周期驱动。
            _ = pump
            defer { eventContinuation.finish() }
            do {
                let result = try await task.run(client) { event in
                    eventContinuation.yield(event)
                }
                if result.timedOut {
                    self.finish(
                        recordID: task.id,
                        status: .failed,
                        exitCode: result.exitCode,
                        message: "超时：命令超过时间限制被终止",
                        suggestion: BrewFailureKind.timedOut.suggestion
                    )
                    return
                }
                if result.cancelled || Task.isCancelled {
                    self.finishCancelled(task: task, exitCode: result.exitCode)
                    return
                }
                guard task.verifyOutdated else {
                    self.finish(
                        recordID: task.id,
                        status: .succeeded,
                        exitCode: result.exitCode,
                        message: nil,
                        suggestion: nil
                    )
                    return
                }

                let verification = await self.verifyOutdated(task: task, client: client)
                // Cancellation can arrive while the verification command runs;
                // never let it be overwritten with 成功.
                if Task.isCancelled {
                    self.finishCancelled(task: task, exitCode: result.exitCode)
                    return
                }
                switch verification {
                case .passed:
                    if task.verifyNames.isEmpty { self.recordBatchRemaining(0, for: task) }
                    self.finish(
                        recordID: task.id,
                        status: .succeeded,
                        exitCode: result.exitCode,
                        message: nil,
                        suggestion: nil,
                        verification: "版本复核通过"
                    )
                case .stillOutdated(let remaining, let names):
                    if task.verifyNames.isEmpty { self.recordBatchRemaining(remaining, for: task) }
                    let detail = names.isEmpty
                        ? ""
                        : "：\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? " 等" : "")"
                    self.finish(
                        recordID: task.id,
                        status: .failed,
                        exitCode: result.exitCode,
                        message: "版本复核未通过：仍有 \(remaining) 个可更新项\(detail)",
                        suggestion: "brew 返回成功但版本未变化。请在终端复查该包，或稍后重新检查更新。",
                        verification: "版本复核：仍有 \(remaining) 个待更新项"
                    )
                case .unavailable(let reason):
                    self.finish(
                        recordID: task.id,
                        status: .unverified,
                        exitCode: result.exitCode,
                        message: "版本未确认：无法读取 outdated（\(reason)）",
                        suggestion: "命令已退出 0，但无法复核版本。可稍后点击「检查更新」复查，或查看日志。",
                        verification: "版本复核：无法读取 outdated，结果未确认"
                    )
                }
            } catch is CancellationError {
                self.finish(recordID: task.id, status: .cancelled, exitCode: nil, message: "任务已取消。", suggestion: nil)
            } catch let error as BrewCommandError {
                self.finish(
                    recordID: task.id,
                    status: .failed,
                    exitCode: error.exitCode,
                    message: "\(error.kind.label)：\(error.firstErrorLine ?? error.localizedDescription)",
                    suggestion: error.kind.suggestion
                )
            } catch {
                self.finish(
                    recordID: task.id,
                    status: .failed,
                    exitCode: nil,
                    message: error.localizedDescription,
                    suggestion: "查看日志以获取完整输出；可在终端中手动执行同一命令。"
                )
            }
        }
        executionTask = execution
        await execution.value
        executionTask = nil
    }

    private func finishCancelled(task: ChangeTask, exitCode: Int32?) {
        finish(
            recordID: task.id,
            status: .cancelled,
            exitCode: exitCode,
            message: "任务已取消。若操作可能已部分完成，请复查该包状态。",
            suggestion: "Brewbutler 不会自动回滚。可在终端重新执行同一命令。"
        )
    }

    private func handle(event: ProcessEvent, recordID: UUID) {
        switch event {
        case .started(let pid):
            currentPID = pid
        case .line(let line):
            if line.text.isEmpty { return }
            lastOutputAt = Date()
            var log = LogLine(text: line.text)
            if let last = logs.last,
               last.kind == .stage,
               log.kind == .stage,
               Self.stageKey(last.text) == Self.stageKey(log.text) {
                logs[logs.count - 1] = log
            } else {
                logs.append(log)
            }
            if logs.count > 4000 {
                logs.removeFirst(500)
                logsTruncated = true
            }
            logStore.append(log.text, recordID: recordID)
            if let event = BrewProgressParser.event(forLine: line.text) {
                applyProgressEvent(event, recordID: recordID)
            }
        case .finished(let result):
            if let index = records.firstIndex(where: { $0.id == recordID }), records[index].exitCode == nil {
                records[index].exitCode = result.exitCode
            }
        }
    }

    private enum OutdatedVerification {
        case passed
        case stillOutdated(remaining: Int, names: [String])
        case unavailable(String)
    }

    private func verifyOutdated(task: ChangeTask, client: BrewClient) async -> OutdatedVerification {
        guard let outdated = try? await client.outdated() else {
            return .unavailable("outdated 读取失败")
        }
        if let name = task.packageName, let kind = task.packageKind {
            if kind == .formula {
                if let row = outdated.formulae.first(where: { Self.matches(rowName: $0.name, taskName: name) }) {
                    return row.pinned == true ? .passed : .stillOutdated(remaining: 1, names: [name])
                }
                return .passed
            }
            if let row = outdated.casks.first(where: { Self.matches(rowName: $0.token, taskName: name) }) {
                return row.pinned == true ? .passed : .stillOutdated(remaining: 1, names: [name])
            }
            return .passed
        }
        if !task.verifyNames.isEmpty {
            // Security-only upgrade: unrelated updates are expected to remain and
            // must not turn a successful `--vulnerable` run into a failure.
            let still = task.verifyNames.filter { name in
                outdated.formulae.contains { Self.matches(rowName: $0.name, taskName: name) && $0.pinned != true }
                    || outdated.casks.contains { Self.matches(rowName: $0.token, taskName: name) && $0.pinned != true }
            }
            return still.isEmpty ? .passed : .stillOutdated(remaining: still.count, names: still)
        }
        // Batch/all verification: pinned packages are intentionally skipped by
        // brew, so they must not turn a successful upgrade into a failure.
        let remainingFormulae = outdated.formulae.filter { $0.pinned != true }
        let remainingCasks = outdated.casks.filter { $0.pinned != true }
        let remaining = remainingFormulae.count + remainingCasks.count
        if remaining == 0 { return .passed }
        let names = Array((remainingFormulae.map(\.name) + remainingCasks.map(\.token)).prefix(5))
        return .stillOutdated(remaining: remaining, names: names)
    }

    private static func matches(rowName: String, taskName: String) -> Bool {
        if rowName == taskName { return true }
        if let last = rowName.split(separator: "/").last, String(last) == taskName { return true }
        return false
    }

    private func recordBatchRemaining(_ remaining: Int, for task: ChangeTask) {
        guard let batchID = task.batchID, batches[batchID] != nil else { return }
        batches[batchID]?.remainingOutdated = remaining
    }

    // MARK: - Progress panel updates

    /// Mirrors a TaskRecord status transition onto its progress rows. Rows
    /// sharing one recordID are an aggregate task (全部更新): success marks
    /// every row, failure blames only the running row and the rest become
    /// 未执行 — brew works sequentially, so pending rows never ran.
    private func applyProgressStatus(recordID: UUID, status: TaskRecord.Status, message: String?) {
        let indices = progressItems.indices.filter { progressItems[$0].recordID == recordID }
        guard !indices.isEmpty else { return }
        let isGroup = indices.count > 1
        switch status {
        case .running:
            for i in indices where progressItems[i].state == .pending {
                // Aggregate rows stay pending until parsing attributes the
                // process to a specific package; per-package rows start now.
                if !isGroup {
                    progressItems[i].state = .running
                }
            }
        case .succeeded:
            for i in indices where progressItems[i].state != .succeeded {
                progressItems[i].state = .succeeded
                progressItems[i].stage = nil
            }
        case .unverified:
            // P1-9：只把还没定论的行标成「未确认」，已经失败的行保持失败。
            // 已按逐包解析成 .succeeded 的行也要改回未确认——最终校验失败时
            // 之前的「完成」不再可信。
            for i in indices where progressItems[i].state != .failed {
                progressItems[i].state = .unverified
                progressItems[i].stage = nil
            }
        case .failed:
            for i in indices {
                switch progressItems[i].state {
                case .running:
                    progressItems[i].state = .failed
                    progressItems[i].errorMessage = message
                    progressItems[i].stage = nil
                case .pending:
                    progressItems[i].state = isGroup ? .skipped : .failed
                    if !isGroup { progressItems[i].errorMessage = message }
                    progressItems[i].stage = nil
                default:
                    break
                }
            }
        case .cancelled, .cancelling:
            for i in indices {
                switch progressItems[i].state {
                case .running:
                    progressItems[i].state = .cancelled
                    progressItems[i].stage = nil
                case .pending:
                    // C-14: a row that never started is 未执行, not 已取消.
                    // Only the row that was actually running may claim to have
                    // been cancelled (and thus possibly partially applied).
                    progressItems[i].state = .skipped
                    progressItems[i].stage = nil
                default:
                    break
                }
            }
        case .pending, .interrupted:
            break
        }
        if progressFinished, progressFinishedAt == nil {
            progressFinishedAt = Date()
        }
    }

    private func applyProgressEvent(_ event: BrewProgressEvent, recordID: UUID) {
        switch event {
        case .stage(let stage):
            if let idx = progressItems.firstIndex(where: { $0.recordID == recordID && $0.state == .running }) {
                progressItems[idx].stage = stage
            } else if let idx = progressItems.firstIndex(where: { $0.recordID == recordID && $0.state == .pending }) {
                // Fallback (需技术验证): when no per-package line is parsed we
                // still promote the first pending row so the panel stays alive.
                progressItems[idx].state = .running
                progressItems[idx].stage = stage
            }
        case .packageStarted(let name):
            guard let matched = progressItems.firstIndex(where: {
                $0.recordID == recordID && Self.matchesProgressName($0.name, name)
            }) else { return }
            if let running = progressItems.firstIndex(where: { $0.recordID == recordID && $0.state == .running }),
               running != matched {
                // brew works sequentially: starting the next package completes
                // the previous one.
                progressItems[running].state = .succeeded
                progressItems[running].stage = nil
            }
            progressItems[matched].state = .running
            progressItems[matched].stage = nil
        }
    }

    private static func matchesProgressName(_ itemName: String, _ brewName: String) -> Bool {
        if itemName == brewName { return true }
        if let last = brewName.split(separator: "/").last, String(last) == itemName { return true }
        return false
    }

    private func finish(
        recordID: UUID,
        status: TaskRecord.Status,
        exitCode: Int32?,
        message: String?,
        suggestion: String?,
        verification: String? = nil
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        // A cancel that lands late must never be overwritten by 成功.
        let finalStatus: TaskRecord.Status = (records[index].status == .cancelling && status == .succeeded)
            ? .cancelled
            : status

        // C-03: a cancelled task must not silently hand over to the rest of its
        // batch. Count the unexecuted targets (aggregate rows + queued
        // per-package tasks), mark them cancelled and say how many did not run.
        var finalMessage = message
        var cancelledRemainder = 0
        if finalStatus == .cancelled {
            let pendingRows = progressItems.filter { $0.recordID == recordID && $0.state == .pending }.count
            var queuedInBatch = 0
            if let batchID = taskByID[recordID]?.batchID {
                queuedInBatch = pending.filter { $0.batchID == batchID }.count
                cancelQueuedBatchRemainder(batchID: batchID)
            }
            cancelledRemainder = pendingRows + queuedInBatch
            if cancelledRemainder > 0 {
                finalMessage = "已取消，剩余 \(cancelledRemainder) 个未执行，可重新选择。若操作可能已部分完成，请复查该包状态。"
            }
        }

        records[index].status = finalStatus
        records[index].finishedAt = Date()
        records[index].exitCode = exitCode
        records[index].message = finalMessage
        records[index].suggestion = suggestion
        records[index].verificationNote = verification
        applyProgressStatus(recordID: recordID, status: finalStatus, message: finalMessage)
        if finalStatus == .cancelled {
            // No queued task is left: leaving the queue paused would require a
            // second, unexplained 「继续队列」 click for the next batch.
            if pending.isEmpty {
                isPaused = false
            }
            refreshQueueSnapshot()
        }
        switch finalStatus {
        case .succeeded:
            logs.append(LogLine(text: "✔ 任务完成（退出码 \(exitCode ?? 0)）"))
        case .unverified:
            logs.append(LogLine(text: "⚠ 任务已结束但版本未确认：\(message ?? "无法读取 outdated")"))
        case .cancelled:
            logs.append(LogLine(text: "任务已取消"))
        default:
            logs.append(LogLine(text: message ?? "任务失败"))
        }
        logStore.end(recordID: recordID)
        currentRecordID = nil
        currentPID = nil
        persist()
        logStore.prune(records: records)
        if let record = records.first(where: { $0.id == recordID }) {
            onTaskFinished?(record)
        }
        if finalStatus == .succeeded || finalStatus == .unverified {
            Task { [weak self] in
                await self?.onMutationFinished?()
            }
        }
        finishBatchIfComplete(recordID: recordID)
    }

    private func finishBatchIfComplete(recordID: UUID) {
        guard let task = taskByID[recordID],
              let batchID = task.batchID,
              let batch = batches[batchID] else { return }
        let batchRecords = batch.taskIDs.compactMap { id in records.first { $0.id == id } }
        guard batchRecords.count == batch.taskIDs.count,
              batchRecords.allSatisfy({ $0.status.isTerminal }) else { return }

        // An aggregate task (全部更新 / 更新安全项) is ONE record but N package
        // rows. Counting records would report "成功 1" for a 30-package run, so
        // this case counts the progress rows instead. The record ID stays the
        // retry unit because brew exposes no per-package retry for `upgrade`.
        // Multi-task batches (更新所选) keep 1 task = 1 package and therefore
        // keep the record-based counting.
        let aggregateRows: [PackageProgressItem] = {
            guard batch.taskIDs.count == 1, !task.progressTargets.isEmpty else { return [] }
            return progressItems.filter { $0.recordID == recordID }
        }()

        let summary: TaskBatchSummary
        if !aggregateRows.isEmpty {
            let failedRows = aggregateRows.filter { $0.state == .failed }
            // P1-9：未确认是独立状态，不再挪用 record 状态把全部行算成「成功 0」。
            summary = TaskBatchSummary(
                title: batch.title,
                succeeded: aggregateRows.filter { $0.state == .succeeded }.count,
                failed: failedRows.count,
                cancelled: aggregateRows.filter { $0.state == .cancelled }.count,
                unverified: aggregateRows.filter { $0.state == .unverified }.count,
                skipped: batch.skipped + aggregateRows.filter { $0.state == .skipped }.count,
                failedTaskCount: failedRows.isEmpty ? 0 : 1,
                failedRecordIDs: failedRows.isEmpty ? [] : [recordID],
                failedTitles: failedRows.map(\.name),
                startedAt: batch.startedAt,
                finishedAt: Date(),
                remainingOutdated: batch.remainingOutdated
            )
        } else {
            let failedRecords = batchRecords.filter { $0.status == .failed || $0.status == .unverified }
            summary = TaskBatchSummary(
                title: batch.title,
                succeeded: batchRecords.filter { $0.status == .succeeded }.count,
                failed: batchRecords.filter { $0.status == .failed }.count,
                cancelled: batchRecords.filter { $0.status == .cancelled }.count,
                unverified: batchRecords.filter { $0.status == .unverified }.count,
                skipped: batch.skipped,
                failedTaskCount: failedRecords.count,
                failedRecordIDs: failedRecords.map(\.id),
                failedTitles: failedRecords.map(\.title),
                startedAt: batch.startedAt,
                finishedAt: Date(),
                remainingOutdated: batch.remainingOutdated
            )
        }
        batches.removeValue(forKey: batchID)
        onBatchFinished?(summary)
    }

    private func markFailed(task: ChangeTask, message: String, suggestion: String?) {
        // enqueue() already inserted a pending record; update it in place so the
        // same UUID never appears twice in the history/ForEach ids.
        if let index = records.firstIndex(where: { $0.id == task.id }) {
            records[index].status = .failed
            records[index].startedAt = records[index].startedAt ?? Date()
            records[index].finishedAt = Date()
            records[index].message = message
            records[index].suggestion = suggestion
        } else {
            records.insert(
                TaskRecord(
                    id: task.id,
                    title: task.title,
                    commandText: task.commandText,
                    action: task.kind.rawValue,
                    packageID: task.packageID,
                    packageName: task.packageName,
                    packageKind: task.packageKind?.rawValue,
                    status: .failed,
                    createdAt: Date(),
                    startedAt: Date(),
                    finishedAt: Date(),
                    message: message,
                    suggestion: suggestion
                ),
                at: 0
            )
        }
        applyProgressStatus(recordID: task.id, status: .failed, message: message)
        logStore.end(recordID: task.id)
        persist()
        if let record = records.first(where: { $0.id == task.id }) {
            onTaskFinished?(record)
        }
        finishBatchIfComplete(recordID: task.id)
    }

    // MARK: - History

    /// Loads persisted records and reconciles records that never finished.
    /// Returns the reconciled list so callers (command palette, tests) can read
    /// the same data without reaching into `records` timing.
    @discardableResult
    func loadHistory() -> [TaskRecord] {
        var loaded = historyStore.load()
        for index in loaded.indices where !loaded[index].status.isTerminal {
            loaded[index].status = .interrupted
            loaded[index].message = "Brewbutler 上次退出时任务尚未完成。未自动重跑，请复查该包状态。"
            loaded[index].suggestion = "查看日志确认 brew 输出，必要时重新执行升级或安装。"
        }
        records = loaded
        return loaded
    }

    /// Shows one record in the log drawer (dashboard 最近操作 / drawer history
    /// picker / command palette). A running record just brings the live task
    /// back into view.
    func openHistoryRecord(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        guard record.status.isTerminal else {
            followLatestRecord()
            showDrawer = true
            return
        }
        selectedRecordID = id
        historyLogLines = []
        historyLogsTruncated = false
        showDrawer = true
        loadHistoryLog(for: record)
    }

    /// Leaves history mode and returns the drawer to the live/latest task.
    func followLatestRecord() {
        selectedRecordID = nil
        historyLogLines = []
        historyLogsTruncated = false
    }

    private func loadHistoryLog(for record: TaskRecord) {
        guard let fileName = record.logFileName else { return }
        let store = logStore
        let recordID = record.id
        Task { [weak self] in
            // Log files can be a few MB after a long brew run; parse them off
            // the main actor so opening history never stalls the UI.
            let text = await Task.detached(priority: .userInitiated) {
                store.text(for: fileName)
            }.value
            guard let self, self.selectedRecordID == recordID else { return }
            var lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { LogLine(text: String($0)) }
            if lines.count > 4000 {
                lines.removeFirst(lines.count - 4000)
                self.historyLogsTruncated = true
            }
            self.historyLogLines = lines
        }
    }

    private func persist() {
        historyStore.save(records)
    }

    private static func stageKey(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let range = trimmed.range(of: ":") {
            return String(trimmed[..<range.lowerBound])
        }
        return trimmed.split(separator: " ").prefix(3).joined(separator: " ")
    }
}
