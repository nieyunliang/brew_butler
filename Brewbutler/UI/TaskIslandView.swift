import AppKit
import SwiftUI

/// 规范 §4.8 / §5 TaskIsland：取代 v1 的日志抽屉 + toast + 状态栏。
///
/// 三种形态：
/// - 空闲：无任务、无 toast、无结果时完全隐藏（`EmptyView`，不占高度）。
/// - 折叠态：44pt 玻璃胶囊，最多 520 宽；运行 / 结果 / toast 都走这里。
/// - 展开态：760×360 玻璃面板，4 个 tab（进度 / 日志 / 队列 / 历史）。
///
/// 行为约束（O-02，用户已决策）：
/// - 任务开始不自动展开；只由用户点击、⌥⌘L 或「查看日志」触发。
/// - 批次结束不弹模态汇总；失败结果常驻，全成功 5s 后淡出。
/// - 失败不再走 toast；任务完成通知只在 App 不在前台时发送（在 AppState 中）。
struct TaskIslandView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var tab: IslandTab = .progress
    /// 已处理过的结果 id：点开查看后不再回到折叠态。
    @State private var dismissedSummaryIDs: Set<UUID> = []
    @State private var dismissedRecordIDs: Set<UUID> = []
    /// 全成功批次 5s 淡出后的标记（避免清掉 AppState 里的数据也能隐藏）。
    @State private var expiredSummaryIDs: Set<UUID> = []
    @State private var followTail = true
    @State private var showSummary = false

    private enum IslandTab: String, CaseIterable, Identifiable {
        case progress
        case logs
        case queue
        case history

        var id: String { rawValue }
        var title: String {
            switch self {
            case .progress: return "进度"
            case .logs: return "日志"
            case .queue: return "队列"
            case .history: return "历史"
            }
        }
        var symbol: String {
            switch self {
            case .progress: return "chart.bar"
            case .logs: return "terminal"
            case .queue: return "list.bullet"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    // MARK: Derived state

    private var tasks: TaskQueueStore { appState.tasks }
    private var isExpanded: Bool { tasks.showDrawer }
    private var runningRecord: TaskRecord? { tasks.runningRecord }
    private var pendingCount: Int { tasks.pendingCount }
    private var summary: TaskBatchSummary? {
        guard let summary = appState.batchSummary else { return nil }
        guard !dismissedSummaryIDs.contains(summary.id), !expiredSummaryIDs.contains(summary.id) else { return nil }
        return summary
    }

    /// 空闲时展示「最近一次任务结果」：失败/未确认常驻，成功 5 秒淡出。
    private var idleResultRecord: TaskRecord? {
        guard runningRecord == nil else { return nil }
        guard let record = tasks.records.first, record.status.isTerminal else { return nil }
        guard !dismissedRecordIDs.contains(record.id) else { return nil }
        guard let finishedAt = record.finishedAt else { return nil }
        let age = Date().timeIntervalSince(finishedAt)
        switch record.status {
        case .failed, .unverified:
            return record
        case .interrupted:
            return record
        case .cancelled:
            return age < 5 * 60 ? record : nil
        case .succeeded:
            return age < 5 * 60 ? record : nil
        default:
            return nil
        }
    }

    private var hasCollapsedBar: Bool {
        runningRecord != nil || pendingCount > 0 || summary != nil || idleResultRecord != nil
    }

    private var isIdleAndEmpty: Bool {
        !isExpanded && !hasCollapsedBar && appState.toast == nil
    }

    var body: some View {
        if isIdleAndEmpty {
            // 完全隐藏：不占 safeAreaBar 高度，也不留底部间距。
            EmptyView()
        } else {
            islandContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("任务岛")
        }
    }

    @ViewBuilder
    private var islandContent: some View {
        GlassEffectContainer(spacing: 12) {
            if isExpanded {
                expandedPanel
                    .transition(panelTransition)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    // 规范 §4.8：toast 作为岛左侧的小胶囊出现，靠近时与岛融合。
                    if let toast = appState.toast {
                        GlassToastPill(
                            toast: toast,
                            queuedCount: appState.toastQueueCount,
                            onOpen: toast.kind == .failure ? { appState.openLogDrawerFromToast() } : { appState.dismissToast() }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if hasCollapsedBar {
                        collapsedBar
                            .frame(maxWidth: 520)
                            .transition(collapsedTransition)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration)
                                : .spring(duration: 0.35, bounce: 0.15),
                   value: isExpanded)
        .animation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration)
                                : .spring(duration: 0.3, bounce: 0.1),
                   value: hasCollapsedBar)
        .onExitCommand {
            if isExpanded { tasks.closeDrawer() }
        }
        // 任务结束时如果用户正看着面板，不自动收起（§4.8）。
        .task(id: autoDismissID) {
            await autoDismissResultsIfNeeded()
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
    }

    private var collapsedTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsedBar: some View {
        if let summary {
            resultBar(
                icon: summary.hasFailures ? "xmark.circle.fill" : "checkmark.circle.fill",
                color: summary.hasFailures ? AppTheme.danger : AppTheme.success,
                text: summaryText(summary),
                detail: summary.hasFailures ? "查看失败详情" : nil
            ) {
                openSummary(summary)
            }
        } else if let record = idleResultRecord {
            resultBar(
                icon: record.status == .failed ? "xmark.circle.fill" : (record.status == .unverified ? "questionmark.circle.fill" : "checkmark.circle.fill"),
                color: record.status.displayColor,
                text: idleResultText(record),
                detail: record.status == .failed ? "查看日志" : nil
            ) {
                openRecordResult(record)
            }
        } else if let record = runningRecord {
            runningBar(record)
        } else {
            queueOnlyBar
        }
    }

    private func runningBar(_ record: TaskRecord) -> some View {
        HStack(spacing: 8) {
            PulsingTaskSymbol()
            VStack(alignment: .leading, spacing: 1) {
                // O-01：同步索引期间用「正在同步 Homebrew 索引…」而不是内部任务标题。
                Text(record.action == ChangeTask.Kind.updateIndex.rawValue ? "正在同步 Homebrew 索引…" : record.title)
                    .font(AppTheme.callout(12))
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if tasks.hasProgressPanel {
                        Text("\(tasks.progressProcessedCount)/\(tasks.progressItems.count)")
                            .monospacedDigit()
                    }
                    if pendingCount > 0 {
                        Text("排队 \(pendingCount)")
                            .monospacedDigit()
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedText(record, at: context.date))
                            .monospacedDigit()
                    }
                }
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            }
            Spacer(minLength: 4)

            if tasks.isPaused {
                islandIconButton("play.fill", help: "继续队列") { tasks.resumeQueue() }
            } else if pendingCount > 0 {
                islandIconButton("pause.fill", help: "暂停队列") { tasks.pauseQueue() }
            }
            islandIconButton("xmark", help: "取消当前任务 ⌘.") { tasks.cancelCurrent() }
            islandIconButton("chevron.up", help: "展开任务岛 ⌥⌘L") { expand() }
        }
        .padding(.horizontal, 14)
        .frame(height: AppTheme.glassBarHeight)
        .glassCapsule()
        .contentShape(Capsule())
        .onTapGesture { expand() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在\(record.title)，\(elapsedText(record, at: Date()))")
        .accessibilityAddTraits(.isButton)
    }

    private var queueOnlyBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.text2)
            Text("\(pendingCount) 个任务排队中\(tasks.isPaused ? " · 已暂停" : "")")
                .font(AppTheme.callout(12))
                .foregroundStyle(AppTheme.text1)
            Spacer(minLength: 4)
            if tasks.isPaused {
                islandIconButton("play.fill", help: "继续队列") { tasks.resumeQueue() }
            } else {
                islandIconButton("pause.fill", help: "暂停队列") { tasks.pauseQueue() }
            }
            islandIconButton("chevron.up", help: "展开任务岛") { expand() }
        }
        .padding(.horizontal, 14)
        .frame(height: AppTheme.glassBarHeight)
        .glassCapsule()
        .contentShape(Capsule())
        .onTapGesture { expand() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pendingCount) 个任务排队中")
    }

    private func resultBar(icon: String, color: Color, text: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(text)
                    .font(AppTheme.callout(12))
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.horizontal, 14)
            .frame(height: AppTheme.glassBarHeight)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text)\(detail.map { "，\($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }

    private func islandIconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.text2)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            expandedHeader
            if !showSummary {
                tabStrip
            }
            Group {
                if showSummary, let summary = appState.batchSummary {
                    TaskIslandSummaryView(summary: summary) {
                        showSummary = false
                        tasks.closeDrawer()
                    }
                } else {
                    switch tab {
                    case .progress:
                        progressTab
                    case .logs:
                        logsTab
                    case .queue:
                        queueTab
                    case .history:
                        historyTab
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            // 列表比面板高时最后一行会在面板底缘被硬切；用底部渐隐把裁切线
            // 变成「还有更多可滚动」的暗示，而不是看起来像溢出到面板外。
            .mask {
                if showSummary {
                    Color.black
                } else {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(maxWidth: 760)
        .frame(height: 360)
        .glassPanel(cornerRadius: AppTheme.glassRadius)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.glassRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.glassRadius, style: .continuous))
        .mask(RoundedRectangle(cornerRadius: AppTheme.glassRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            if showSummary, let summary = appState.batchSummary {
                Text("批次结果")
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
                Text("\(summary.title) · \(summary.total) 个包")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
            } else if let record = tasks.displayedRecord {
                if tasks.isShowingHistory {
                    Badge(text: "历史", color: AppTheme.text2, systemImage: "clock")
                }
                Text(panelTitle(for: record))
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(headerProgressText(record, at: context.date))
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .monospacedDigit()
                }
            } else {
                Text("任务岛")
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
            }
            Spacer(minLength: 8)

            if !tasks.isShowingHistory, tasks.isRunning {
                if tasks.isPaused {
                    Button("继续队列") { tasks.resumeQueue() }
                        .glassSecondaryButton()
                } else {
                    Button("暂停") { tasks.pauseQueue() }
                        .glassSecondaryButton()
                }
                Button("取消") { tasks.cancelCurrent() }
                    .glassSecondaryButton()
                    .keyboardShortcut(".", modifiers: .command)
            }
            islandIconButton("chevron.down", help: "收起任务岛 Esc") { collapse() }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(IslandTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .spring(duration: 0.3, bounce: 0.1)) {
                        tab = item
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 10, weight: .semibold))
                        Text(item.title)
                            .font(AppTheme.callout(12))
                        if item == .queue, pendingCount > 0 {
                            Text("\(pendingCount)")
                                .font(AppTheme.mono(10))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(tab == item ? AppTheme.text1 : AppTheme.text3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tab == item ? AppTheme.surface3 : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
            if tab == .logs, !tasks.isShowingHistory {
                Button {
                    followTail.toggle()
                } label: {
                    Image(systemName: followTail ? "arrow.down.to.line" : "arrow.down.to.line.compact")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(followTail ? AppTheme.accent : AppTheme.text3)
                }
                .buttonStyle(.plain)
                .help(followTail ? "正在跟随日志尾部，点击暂停" : "点击跟随日志尾部")
            }
            if tab == .logs, let record = tasks.displayedRecord {
                Button {
                    copyToPasteboard(tasks.logText(for: record))
                    appState.showToast("已复制任务日志", kind: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.text2)
                }
                .buttonStyle(.plain)
                .help("复制日志")
            }
            if tasks.isShowingHistory {
                Button("返回实时") { tasks.followLatestRecord() }
                    .glassSecondaryButton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: Tabs

    private var progressTab: some View {
        Group {
            if tasks.hasProgressPanel {
                VStack(spacing: 0) {
                    batchProgressHeader
                        .fixedSize(horizontal: false, vertical: true)
                    // 更新页可见时逐包行已在主列表，这里只给批次总进度，避免两份。
                    if !(appState.section == .updates && appState.selectedPackage == nil) {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(tasks.progressItems) { item in
                                    TaskIslandProgressRow(item: item)
                                    Hairline().padding(.leading, 28)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            } else if let record = tasks.displayedRecord {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatusPill(text: record.status.label, color: record.status.displayColor)
                            Text(record.commandText)
                                .font(AppTheme.mono())
                                .foregroundStyle(AppTheme.text3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        if let message = record.message {
                            Text(message)
                                .font(AppTheme.callout())
                                .foregroundStyle(record.status == .failed ? AppTheme.danger : AppTheme.text2)
                        }
                        if let suggestion = record.suggestion {
                            Text(suggestion)
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                        if !tasks.isShowingHistory, tasks.isRunning {
                            Text("正在执行…展开「日志」查看实时输出。")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "没有正在运行的任务",
                    message: "批量更新与安装任务会在这里显示进度。",
                    compact: true
                )
            }
        }
    }

    private var batchProgressHeader: some View {
        let total = tasks.progressItems.count
        let processed = tasks.progressProcessedCount
        let ratio = total == 0 ? 0 : Double(processed) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(processed)/\(total) 已处理")
                    .font(AppTheme.headline(12.5))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text1)
                Text("完成 \(tasks.progressDoneCount) · 失败 \(tasks.progressFailedCount)")
                    .font(AppTheme.caption())
                    .monospacedDigit()
                    .foregroundStyle(tasks.progressFailedCount > 0 ? AppTheme.danger : AppTheme.text3)
                if let started = tasks.progressStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let end = tasks.progressFinishedAt ?? context.date
                        Text(Self.elapsedText(max(0, end.timeIntervalSince(started))))
                            .font(AppTheme.caption())
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.text3)
                    }
                }
                Spacer(minLength: 0)
                Text("进度只按实际完成数推进")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99).fill(AppTheme.surface3)
                    RoundedRectangle(cornerRadius: 99)
                        .fill(tasks.progressFinished
                              ? (tasks.progressFailedCount > 0 ? AppTheme.danger : AppTheme.success)
                              : AppTheme.accent)
                        .frame(width: max(4, proxy.size.width * ratio))
                        .animation(.easeOut(duration: 0.35), value: processed)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("总进度：已处理 \(processed) / \(total)")
    }

    private var logsTab: some View {
        // 规范 §4.8：日志 tab 是玻璃面板里唯一的实底控制台。
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if tasks.displayedLogsTruncated {
                        HStack(spacing: 8) {
                            Text("…早期输出已截断…")
                                .font(AppTheme.mono())
                                .foregroundStyle(AppTheme.consoleMuted)
                            if let record = tasks.displayedRecord {
                                Button("打开完整日志") { openLogFile(record) }
                                    .buttonStyle(.plain)
                                    .font(AppTheme.caption())
                                    .foregroundStyle(AppTheme.accent)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if tasks.displayedLogLines.isEmpty {
                        Text(tasks.isShowingHistory ? "该任务没有日志文件，或日志已被清理。" : "等待 brew 输出…")
                            .font(AppTheme.mono())
                            .foregroundStyle(AppTheme.consoleMuted)
                    }
                    ForEach(tasks.displayedLogLines) { line in
                        Text(line.text)
                            .font(AppTheme.mono(11.5, weight: .regular))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                    if tasks.isRunning, !tasks.isShowingHistory, followTail {
                        Text("▍")
                            .font(AppTheme.mono(11.5, weight: .regular))
                            .foregroundStyle(AppTheme.accent)
                            .id("cursor")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(AppTheme.consoleBackground)
            .onChange(of: tasks.displayedLogLines.count) { _, _ in
                guard followTail, !tasks.isShowingHistory else { return }
                if let last = tasks.displayedLogLines.last {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var queueTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("排队中 \(pendingCount)")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .monospacedDigit()
                if tasks.isPaused {
                    Badge(text: "已暂停", color: AppTheme.warning, systemImage: "pause.fill")
                }
                Spacer(minLength: 8)
                Text("取消运行中任务后不会自动继续")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if tasks.pendingRecords.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet",
                    title: "队列为空",
                    message: "批量更新、安装会依次进入队列，同一时刻只执行一个变更任务。",
                    compact: true
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tasks.pendingRecords) { task in
                            HStack(spacing: 10) {
                                Text("\(task.position)")
                                    .font(AppTheme.mono())
                                    .foregroundStyle(AppTheme.text3)
                                    .frame(width: 18, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(AppTheme.headline())
                                        .foregroundStyle(AppTheme.text2)
                                        .lineLimit(1)
                                    Text(task.commandText)
                                        .font(AppTheme.mono())
                                        .foregroundStyle(AppTheme.text3)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    tasks.removePending(id: task.id)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppTheme.text3)
                                .help("从队列移除（不会执行）")
                                .accessibilityLabel("移除排队任务 \(task.title)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            Hairline().padding(.leading, 28)
                        }
                    }
                }
            }
        }
    }

    private var historyTab: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tasks.records.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "还没有任务记录",
                        message: "执行过的安装、更新、清理会保存在本机。",
                        compact: true
                    )
                }
                ForEach(tasks.records.prefix(20)) { record in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(record.status.displayColor)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title)
                                .font(AppTheme.headline())
                                .foregroundStyle(AppTheme.text1)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(record.status.label)
                                    .foregroundStyle(record.status.displayColor)
                                if let finishedAt = record.finishedAt {
                                    Text(finishedAt.relativeText)
                                }
                                if let duration = record.duration {
                                    Text("· \(Self.durationText(duration))")
                                }
                                if let exitCode = record.exitCode, record.status == .failed {
                                    Text("· 退出码 \(exitCode)")
                                        .foregroundStyle(AppTheme.danger)
                                }
                            }
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                        }
                        Spacer(minLength: 8)
                        Button("日志") { tasks.openHistoryRecord(record.id) }
                            .glassSecondaryButton()
                        if tasks.canRetry(recordID: record.id) {
                            Button("重试…") { appState.retryTask(recordID: record.id) }
                                .glassSecondaryButton()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Hairline().padding(.leading, 28)
                }
            }
        }
    }

    // MARK: - Actions

    private func expand() {
        tab = .progress
        showSummary = false
        withAnimation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .spring(duration: 0.35, bounce: 0.15)) {
            tasks.showDrawer = true
        }
    }

    private func collapse() {
        if showSummary, let summary = appState.batchSummary {
            markSummarySeen(summary)
        }
        showSummary = false
        withAnimation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .spring(duration: 0.35, bounce: 0.15)) {
            tasks.closeDrawer()
        }
    }

    private func openSummary(_ summary: TaskBatchSummary) {
        dismissedSummaryIDs.insert(summary.id)
        showSummary = true
        tab = .progress
        withAnimation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .spring(duration: 0.35, bounce: 0.15)) {
            tasks.showDrawer = true
        }
    }

    private func openRecordResult(_ record: TaskRecord) {
        dismissedRecordIDs.insert(record.id)
        tasks.openHistoryRecord(record.id)
        tab = .logs
        withAnimation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .spring(duration: 0.35, bounce: 0.15)) {
            tasks.showDrawer = true
        }
    }

    private func markSummarySeen(_ summary: TaskBatchSummary) {
        dismissedSummaryIDs.insert(summary.id)
        appState.clearBatchSummary()
    }

    // MARK: - Auto dismiss

    private var autoDismissID: String {
        if let summary = appState.batchSummary {
            return "summary-\(summary.id.uuidString)-\(summary.hasFailures)"
        }
        return "record-\(tasks.records.first?.id.uuidString ?? "none")"
    }

    @MainActor
    private func autoDismissResultsIfNeeded() async {
        try? await Task.sleep(for: .milliseconds(300))
        if let summary = appState.batchSummary, !summary.hasFailures, !expiredSummaryIDs.contains(summary.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, appState.batchSummary?.id == summary.id else { return }
            expiredSummaryIDs.insert(summary.id)
            appState.clearBatchSummary()
        }
        if let record = tasks.records.first, record.status == .succeeded,
           !dismissedRecordIDs.contains(record.id) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, tasks.records.first?.id == record.id else { return }
            dismissedRecordIDs.insert(record.id)
        }
    }

    // MARK: - Helpers

    private func summaryText(_ summary: TaskBatchSummary) -> String {
        let processed = summary.succeeded + summary.failed + summary.unverified + summary.cancelled
        if summary.hasFailures {
            return "\(processed) 个包已处理 · \(summary.failed + summary.unverified) 个失败"
        }
        if summary.cancelled > 0 {
            return "\(processed) 个包已处理 · \(summary.cancelled) 个已取消"
        }
        return "\(processed) 个包已处理"
    }

    private func idleResultText(_ record: TaskRecord) -> String {
        switch record.status {
        case .failed:
            return "\(record.title)失败" + (record.exitCode.map { " · 退出码 \($0)" } ?? "")
        case .unverified:
            return "\(record.title) · 版本未确认"
        case .cancelled:
            return "\(record.title)已取消"
        default:
            return "\(record.title)完成" + (record.duration.map { " · \(Self.durationText($0))" } ?? "")
        }
    }

    private func panelTitle(for record: TaskRecord) -> String {
        if !tasks.isShowingHistory, tasks.hasProgressPanel, let title = tasks.progressTitle, !title.isEmpty {
            return title
        }
        return record.title
    }

    private func headerProgressText(_ record: TaskRecord, at date: Date) -> String {
        var parts: [String] = []
        if tasks.hasProgressPanel {
            parts.append("\(tasks.progressProcessedCount)/\(tasks.progressItems.count) 已完成")
        }
        if record.startedAt != nil, !record.status.isTerminal {
            parts.append(elapsedText(record, at: date))
        } else if record.status == .failed, let exitCode = record.exitCode {
            parts.append("退出码 \(exitCode)")
        }
        return parts.joined(separator: " · ")
    }

    private func elapsedText(_ record: TaskRecord, at date: Date) -> String {
        guard let started = record.startedAt else { return "" }
        return Self.elapsedText(max(0, date.timeIntervalSince(started)))
    }

    private static func elapsedText(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "已用 %d:%02d", total / 60, total % 60)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func color(for kind: LogLine.Kind) -> Color {
        switch kind {
        case .normal: return AppTheme.consoleText
        case .stage: return AppTheme.accent
        case .warning: return AppTheme.warning
        case .error: return AppTheme.danger
        case .success: return AppTheme.success
        }
    }

    private func openLogFile(_ record: TaskRecord) {
        guard let url = tasks.logFileURL(for: record) else {
            appState.showToast("该任务没有日志文件", kind: .info)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - 折叠态脉冲符号

private struct PulsingTaskSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
    }
}

// MARK: - 逐包进度行

private struct TaskIslandProgressRow: View {
    let item: PackageProgressItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                PackageStateDot(state: item.state)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(item.name)
                            .font(AppTheme.headline(12.5))
                            .foregroundStyle(AppTheme.text1)
                            .lineLimit(1)
                        if let kind = item.kind {
                            Text(kind)
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                    }
                    if let from = item.fromVersion, let to = item.toVersion, !to.isEmpty {
                        HStack(spacing: 4) {
                            Text(from).font(AppTheme.mono()).foregroundStyle(AppTheme.text3)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppTheme.text3)
                            Text(to).font(AppTheme.mono(11.5, weight: .semibold)).foregroundStyle(AppTheme.accent)
                        }
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                ProgressStateTrailing(state: item.state, stage: item.stage)
            }
            if item.state == .failed, let message = item.errorMessage, !message.isEmpty {
                Text(message)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 25)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(hovering ? AppTheme.surface3.opacity(0.35) : Color.clear)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)，\(item.state.label)")
    }
}

// MARK: - 批次结果汇总（取代 v1 的 BatchSummarySheet）

struct TaskIslandSummaryView: View {
    @Environment(AppState.self) private var appState
    let summary: TaskBatchSummary
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: summary.hasFailures ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(summary.hasFailures ? AppTheme.danger : AppTheme.success)
                    Text(summary.hasFailures ? "\(summary.title) · 有失败项" : "\(summary.title) · 已完成")
                        .font(AppTheme.headline())
                        .foregroundStyle(AppTheme.text1)
                    Spacer(minLength: 0)
                    if let remaining = summary.remainingOutdated {
                        Text("仍有 \(remaining) 个可更新")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                }

                HStack(spacing: 10) {
                    summaryCount("成功", summary.succeeded, AppTheme.success)
                    summaryCount("失败", summary.failed, AppTheme.danger)
                    if summary.unverified > 0 { summaryCount("未确认", summary.unverified, AppTheme.warning) }
                    if summary.cancelled > 0 { summaryCount("已取消", summary.cancelled, AppTheme.text2) }
                    if summary.skipped > 0 { summaryCount("跳过", summary.skipped, AppTheme.text3) }
                    Spacer(minLength: 0)
                }

                if !summary.failedTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("失败项")
                            .font(AppTheme.headline(12))
                            .foregroundStyle(AppTheme.text2)
                        ForEach(Array(summary.failedTitles.prefix(6)), id: \.self) { title in
                            HStack(spacing: 6) {
                                Circle().fill(AppTheme.danger).frame(width: 5, height: 5)
                                Text(title)
                                    .font(AppTheme.callout())
                                    .foregroundStyle(AppTheme.text2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if summary.hasFailures {
                    Text("失败不自动重试、不自动回滚；可展开「日志」查看退出码与首行错误。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("查看日志") { appState.tasks.showDrawer = true }
                        .glassSecondaryButton()
                    if let id = summary.failedRecordIDs.first, appState.tasks.canRetry(recordID: id) {
                        Button("重试…") { appState.retryTask(recordID: id) }
                            .glassSecondaryButton()
                    }
                    if summary.hasFailures || appState.scanIsStale {
                        Button("重新扫描") { appState.scanVulnerabilities() }
                            .glassSecondaryButton()
                    }
                    Spacer(minLength: 0)
                    Button("完成") { onDone() }
                        .glassPrimaryButton()
                }
            }
            .padding(16)
        }
    }

    private func summaryCount(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(AppTheme.statValue(18))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}
