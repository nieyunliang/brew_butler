import SwiftUI

/// 规范 §4.2 / UX 方案 O-01 · O-04 · O-07：更新页。
///
/// 结构：hero（双时间戳 + 一个随 scope 变化的主按钮）→ 玻璃 scope 栏 →
/// 单条提示（离线 / 同步失败 / 缓存）→ 安全分组（置顶、按严重度排序、覆盖率常驻）
/// → 常规更新分组。待更新 / 排队 / 运行 / 完成 / 失败都在同一列表的行内表达，
/// 状态圆点替代复选框；有选中时主操作让位给底部 `FloatingActionBar`。
struct UpdatesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scopeID: String = UpdateFilter.all.rawValue
    @State private var query = ""
    @State private var selection: Set<String> = []
    /// 已从 outdated 消失但仍带在途进度的安全行：记住名字，避免更新成功的
    /// 安全行在索引刷新后掉进「常规更新」分组。
    @State private var knownSecurityNames: Set<String> = []
    /// C-08：检查更新耗时反馈（brew update-if-needed / outdated 可能等网络 / 锁）。
    @State private var refreshStartedAt: Date?
    /// 离线 / 同步失败提示的「关闭」只对当前这一条生效。
    @State private var dismissedNoticeKey: String?
    @FocusState private var searchFocused: Bool

    private var filter: UpdateFilter { UpdateFilter(rawValue: scopeID) ?? .all }

    // MARK: - List model

    /// 单一列表：仍在 outdated 的条目 + 已从 outdated 消失但仍带批次进度的行。
    private var rows: [UpdateListRow] {
        let entries = appState.filteredUpdates(filter: filter, query: query)
        var used = Set<UUID>()
        var noticedRecords = Set<UUID>()
        var result: [UpdateListRow] = []

        for entry in entries {
            let matched = appState.tasks.progressItems.first { item in
                !used.contains(item.id) && Self.matchesProgressName(item.name, entry.name)
            }
            if let matched { used.insert(matched.id) }
            result.append(
                UpdateListRow(
                    id: entry.id,
                    entry: entry,
                    progress: matched,
                    cancelledNotice: cancelledNotice(for: matched, noticed: &noticedRecords),
                    isSecurity: entry.isSecurityUpdate,
                    summary: appState.index.package(named: entry.name, kind: entry.kind)?.desc
                )
            )
        }

        let needle = query.trimmed
        for item in appState.tasks.progressItems where !used.contains(item.id) {
            if !needle.isEmpty, !item.name.localizedCaseInsensitiveContains(needle) { continue }
            switch filter {
            case .all:
                break
            // 进度行不携带安全标记；安全 scope 只认当前仍能匹配到 finding 的条目。
            case .security:
                continue
            case .formula:
                if item.kind != PackageSnapshot.Kind.formula.rawValue { continue }
            case .cask:
                if item.kind != PackageSnapshot.Kind.cask.rawValue { continue }
            }
            result.append(
                UpdateListRow(
                    id: "progress-\(item.id.uuidString)",
                    entry: nil,
                    progress: item,
                    cancelledNotice: cancelledNotice(for: item, noticed: &noticedRecords),
                    isSecurity: knownSecurityNames.contains(Self.shortName(item.name)),
                    summary: nil
                )
            )
        }
        return result
    }

    private var securityRows: [UpdateListRow] {
        rows.filter(\.isSecurity).sorted { lhs, rhs in
            let l = lhs.entry?.severity?.rank ?? 0
            let r = rhs.entry?.severity?.rank ?? 0
            if l != r { return l > r }
            return (lhs.entry?.name ?? lhs.progress?.name ?? "") < (rhs.entry?.name ?? rhs.progress?.name ?? "")
        }
    }

    private var regularRows: [UpdateListRow] { rows.filter { !$0.isSecurity } }

    private var showsSecurityGroup: Bool {
        switch filter {
        case .all, .security: return true
        case .formula, .cask: return !securityRows.isEmpty
        }
    }

    private var showsRegularGroup: Bool { filter != .security }

    // MARK: - Selection

    /// 可勾选集合 = 当前列表里仍待更新、且未锁定的包（有进度的行不可再勾选）。
    private var selectableEntries: [OutdatedEntry] {
        rows.compactMap { $0.progress == nil ? $0.entry : nil }.filter { !$0.pinned }
    }

    private var selectableEntryIDs: [String] { selectableEntries.map(\.id) }

    /// 真正会交给确认面板的集合。
    private var selectedTargets: [OutdatedEntry] {
        selectableEntries.filter { selection.contains($0.id) }
    }

    private var allVisibleSelected: Bool {
        !selectableEntryIDs.isEmpty && selectableEntryIDs.allSatisfy(selection.contains)
    }

    private func toggleSelection(_ entry: OutdatedEntry) {
        if selection.contains(entry.id) {
            selection.remove(entry.id)
        } else {
            selection.insert(entry.id)
        }
    }

    private func toggleSelectAllVisible() {
        if allVisibleSelected {
            selection.subtract(selectableEntryIDs)
        } else {
            selection.formUnion(selectableEntryIDs)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            scopeRow
            noticeArea
            listContent
        }
        // 规范 §5 / Lead 约定：内层页面 bar 叠在任务岛上方，不要用 overlay + 手写 padding。
        .safeAreaBar(edge: .bottom) {
            if !selection.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    floatingBar
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .animation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration)
                           : .spring(duration: 0.32, bounce: 0.12),
                           value: selection.isEmpty)
            }
        }
        .background(hiddenShortcuts)
        // 任务真正开始后清空选择：取消批量确认时保留勾选，便于重新确认。
        // 「检查更新」随身同步上游是一个变更任务，但它不改包，不能顺手清掉勾选。
        .onChange(of: appState.tasks.isRunning) { _, running in
            guard running,
                  let action = appState.tasks.runningRecord?.action,
                  action != ChangeTask.Kind.updateIndex.rawValue
            else { return }
            selection.removeAll()
        }
        // C-08：记录检查起始时间，供页头显示已用时间与 >10s 提示。
        .onChange(of: appState.isRefreshing || appState.isSyncingUpstream) { _, checking in
            refreshStartedAt = checking ? Date() : nil
        }
        // C-10：范围 / 搜索变化后，选中集只保留当前可见的可更新包。
        .onChange(of: selectableEntryIDs) { _, visible in
            selection.formIntersection(Set(visible))
        }
        // 记住「曾经是安全行」的包名，供批次进度行在更新成功后仍留在安全分组。
        .onAppear { rememberSecurityNames() }
        .onChange(of: appState.index.securityUpdates.map(\.name)) { _, _ in rememberSecurityNames() }
        // C-11：只读 dry-run 预览。
        .sheet(isPresented: previewPresented) { previewSheet }
    }

    /// 相对时间：60 秒内一律写「刚刚」，避免 RelativeDateTimeFormatter 对
    /// 刚写入的时间戳输出「0 秒后 / 0 秒前」这类难以理解的文案。
    private func timeText(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "刚刚" }
        return date.relativeText
    }

    private func rememberSecurityNames() {
        knownSecurityNames.formUnion(appState.index.securityUpdates.map(\.name))
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text("更新")
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                Spacer(minLength: 12)
                checkUpdatesButton
                mainActionButton
            }

            HStack(spacing: 8) {
                Text(heroSubtitle)
                    .font(AppTheme.callout())
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text2)
                    .lineLimit(2)
                if appState.greedyUpgrades {
                    greedyBadge
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            autoCheckCaption
            checkingProgressLine
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 14)
    }

    /// O-01：两个时间分开写，不合并成「已是最新」。
    private var heroSubtitle: String {
        var parts: [String] = []
        parts.append("\(appState.index.outdated.count) 个可用更新")
        parts.append("\(appState.index.securityUpdates.count) 个安全更新")
        if appState.isSyncingUpstream {
            parts.append("正在同步上游索引…")
        } else if appState.upstreamSyncError != nil {
            parts.append("上游同步失败")
        } else if let last = appState.lastUpstreamSyncAt {
            parts.append("上游同步于 \(timeText(last))")
        } else {
            parts.append("尚未同步上游")
        }
        parts.append(localCheckText)
        return parts.joined(separator: " · ")
    }

    private var localCheckText: String {
        if appState.isRefreshing { return "正在检查本机…" }
        if let fetched = appState.outdatedFetchedAt ?? appState.lastRefreshAt {
            return "本机检查于 \(timeText(fetched))"
        }
        return "本机尚未检查"
    }

    /// O-04：贪婪模式不在页头，只在副标题留一枚可点击的徽章，点击打开设置。
    private var greedyBadge: some View {
        Button {
            openSettings()
        } label: {
            Badge(text: "含自动更新的 cask", color: AppTheme.info, systemImage: "bolt.fill")
        }
        .buttonStyle(.plain)
        .help("贪婪模式已开启：同时检查 auto_updates / :latest 的 cask。点击打开设置。")
        .accessibilityLabel("含自动更新的 cask，贪婪模式已开启，点击打开设置")
        .accessibilityAddTraits(.isButton)
    }

    /// C-12：自动检查是静默的，失败不能显示成「刚刚检查过」。
    @ViewBuilder
    private var autoCheckCaption: some View {
        if let failed = appState.lastAutoCheckFailedAt,
           appState.lastAutoCheckAt.map({ failed > $0 }) ?? true {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.warning)
                Text(appState.lastAutoCheckAt == nil
                     ? "上次自动检查失败 \(timeText(failed)) · 尚无成功记录"
                     : "上次自动检查失败 \(timeText(failed)) · 当前显示的是上次成功结果")
                    .font(AppTheme.caption())
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.warning)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// C-08：检查更新可能持续数秒到数分钟（先同步上游），必须有进度感。
    @ViewBuilder
    private var checkingProgressLine: some View {
        if (appState.isRefreshing || appState.isSyncingUpstream), let started = refreshStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(started))
                HStack(spacing: 8) {
                    LoadingBar()
                        .frame(width: 90, height: 2)
                        .accessibilityHidden(true)
                    Text(Self.elapsedText(elapsed))
                        .font(AppTheme.caption())
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text3)
                    Text(appState.isSyncingUpstream
                         ? "正在同步 Homebrew 索引，完成后自动检查本机可更新项"
                         : (elapsed >= 10 ? "仍在检查：可能在等待网络或 Homebrew 锁。" : "正在检查本机可更新项"))
                        .font(AppTheme.caption())
                        .foregroundStyle(elapsed >= 10 ? AppTheme.warning : AppTheme.text3)
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(appState.isSyncingUpstream ? "正在同步 Homebrew 索引" : "正在检查可更新项")
        }
    }

    private var checkUpdatesButton: some View {
        Button {
            Task { await appState.checkUpdates() }
        } label: {
            HStack(spacing: 5) {
                if appState.isRefreshing || appState.isSyncingUpstream {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(appState.isSyncingUpstream ? "同步中…" : (appState.isRefreshing ? "检查中…" : "检查更新"))
            }
        }
        .glassSecondaryButton()
        .disabled(appState.isRefreshing || appState.isSyncingUpstream)
        .help("先同步 Homebrew 索引（进入变更队列），再检查本机可更新项（⌘R）")
        .accessibilityLabel("检查更新")
    }

    // MARK: - Main action (O-04)

    private var mainActionTitle: String {
        switch filter {
        case .all:
            return "全部更新 \(appState.index.outdated.count)"
        case .security:
            return "更新 \(appState.index.securityUpdates.count) 个安全项"
        case .formula:
            return "更新 \(formulaUpdateCount) 个 formula"
        case .cask:
            return "更新 \(caskUpdateCount) 个 cask"
        }
    }

    private var formulaUpdateCount: Int {
        appState.index.outdated.filter { $0.kind == .formula }.count
    }

    private var caskUpdateCount: Int {
        appState.index.outdated.filter { $0.kind == .cask }.count
    }

    /// 主按钮对应的批量范围（数量取完整 scope，不受搜索框影响）。
    private var mainActionBatchCount: Int {
        switch filter {
        case .all: return appState.index.outdated.count
        case .security: return appState.index.securityUpdates.count
        case .formula: return formulaUpdateCount
        case .cask: return caskUpdateCount
        }
    }

    private var mainActionDisabled: Bool {
        mainActionBatchCount == 0 || appState.isReadOnly || appState.isUpgradeAllActive
    }

    @ViewBuilder
    private var mainActionButton: some View {
        if selection.isEmpty {
            Button(action: performMainAction) {
                Text(mainActionTitle)
            }
            .glassPrimaryButton()
            .disabled(mainActionDisabled)
            .help(mainActionHelp)
            .accessibilityLabel(mainActionTitle)
        } else {
            // 规范 §4.2：有选中项时页头主按钮让位给浮动操作栏的「更新所选」。
            Button(action: performMainAction) {
                Text(mainActionTitle)
            }
            .glassSecondaryButton()
            .disabled(mainActionDisabled)
            .help("已有选中项：主操作已让位给底部操作栏的「更新所选」。点此仍按当前范围批量更新。")
            .accessibilityLabel("\(mainActionTitle)，已有选中项，主操作在底部操作栏")
        }
    }

    private var mainActionHelp: String {
        if appState.isReadOnly { return "只读模式：Homebrew 版本过低，无法执行更新" }
        if appState.isUpgradeAllActive { return "已有更新批次在队列中" }
        if mainActionBatchCount == 0 { return "当前范围没有可更新的包" }
        return "确认后串行更新 \(mainActionBatchCount) 个包"
    }

    /// O-04：所有路径仍先进入批量更新确认（P0-07），不直接入队。
    private func performMainAction() {
        switch filter {
        case .all:
            appState.requestBatchUpdate(.all)
        case .security:
            appState.requestBatchUpdate(.vulnerable)
        case .formula:
            appState.requestBatchUpdate(.selected(formulaUpdateIDs))
        case .cask:
            appState.requestBatchUpdate(.selected(caskUpdateIDs))
        }
    }

    private var formulaUpdateIDs: [String] {
        appState.index.outdated.filter { $0.kind == .formula }.map(\.id)
    }

    private var caskUpdateIDs: [String] {
        appState.index.outdated.filter { $0.kind == .cask }.map(\.id)
    }

    // MARK: - Scope bar

    private var scopeOptions: [GlassScopeOption] {
        [
            GlassScopeOption(id: UpdateFilter.all.rawValue,
                             title: "全部",
                             count: appState.index.outdated.count,
                             help: "全部可更新包"),
            GlassScopeOption(id: UpdateFilter.security.rawValue,
                             title: "安全",
                             count: appState.index.securityUpdates.count,
                             help: appState.vulnReport == nil
                                 ? "尚未扫描：安全筛选要等一次漏洞扫描后才有结果"
                                 : "只看与已知漏洞相关的更新"),
            GlassScopeOption(id: UpdateFilter.formula.rawValue,
                             title: "formula",
                             count: formulaUpdateCount),
            GlassScopeOption(id: UpdateFilter.cask.rawValue,
                             title: "cask",
                             count: caskUpdateCount)
        ]
    }

    private var scopeRow: some View {
        HStack(spacing: 10) {
            GlassScopeBar(options: scopeOptions, selection: $scopeID, accessibilityLabel: "更新范围")
            Spacer(minLength: 8)
            SearchField(placeholder: "搜索可更新包", text: $query, width: 150, focus: $searchFocused)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 10)
    }

    // MARK: - Notice（离线 / 同步失败 / 缓存；同屏只一条）

    private var noticeKey: String {
        if let error = appState.outdatedRefreshError { return "check:\(error)" }
        if let error = appState.upstreamSyncError { return "sync:\(error)" }
        if appState.outdatedIsCached { return "cache:\(appState.outdatedFetchedAt?.timeIntervalSince1970 ?? 0)" }
        return ""
    }

    private var noticeVisible: Bool { !noticeKey.isEmpty && dismissedNoticeKey != noticeKey }

    @ViewBuilder
    private var noticeArea: some View {
        if noticeVisible {
            if let error = appState.outdatedRefreshError {
                GlassNotice(
                    level: .danger,
                    title: "未能检查更新",
                    message: "\(error)。当前显示的是\(cachedTimeText)的结果。",
                    actionTitle: "重试",
                    action: { Task { await appState.checkUpdates() } },
                    onDismiss: { dismissedNoticeKey = noticeKey }
                )
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
            } else if appState.upstreamSyncError != nil {
                GlassNotice(
                    level: .warning,
                    title: "未能同步上游",
                    message: "未能同步上游，结果基于\(upstreamTimeText)的本地索引。",
                    actionTitle: "重试",
                    action: { Task { await appState.checkUpdates() } },
                    onDismiss: { dismissedNoticeKey = noticeKey }
                )
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
            } else if appState.outdatedIsCached {
                GlassNotice(
                    level: .info,
                    message: "需要网络，当前显示\(cachedTimeText)的缓存。",
                    actionTitle: "重试",
                    action: { Task { await appState.checkUpdates() } },
                    onDismiss: { dismissedNoticeKey = noticeKey }
                )
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
            }
        }
    }

    private var cachedTimeText: String {
        (appState.outdatedFetchedAt ?? appState.lastRefreshAt).map(timeText) ?? "上次成功检查"
    }

    private var upstreamTimeText: String {
        appState.lastUpstreamSyncAt.map(timeText) ?? "上次成功同步"
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if rows.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showsSecurityGroup { securityGroup }
                    if showsRegularGroup { regularGroup }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var upToDateMessage: String {
        if appState.isRefreshing || appState.isSyncingUpstream { return "正在检查可更新项…" }
        if let fetched = appState.outdatedFetchedAt ?? appState.lastRefreshAt {
            return "本机检查于 \(timeText(fetched))，点击可重新检查。"
        }
        return "点击可检查一次。"
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.index.outdated.isEmpty,
           appState.tasks.progressItems.isEmpty,
           let error = appState.outdatedRefreshError {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "无法检查更新",
                message: error,
                actionTitle: "重试"
            ) {
                Task { await appState.checkUpdates() }
            }
        } else if appState.index.outdated.isEmpty, appState.tasks.progressItems.isEmpty {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "所有包都是最新版本",
                message: upToDateMessage,
                actionTitle: "检查更新"
            ) {
                Task { await appState.checkUpdates() }
            }
        } else if filter == .security, appState.vulnReport != nil {
            // 诚实口径：只写「本次扫描未发现」+ 覆盖率，不写「无漏洞」。
            EmptyStateView(
                systemImage: "checkmark.shield",
                title: "没有可更新的安全项",
                message: "本次扫描未发现可更新的安全项（\(appState.vulnerabilityCoverageText)）。",
                actionTitle: "查看全部更新"
            ) {
                scopeID = UpdateFilter.all.rawValue
            }
        } else {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "当前筛选没有结果",
                message: "换个范围或关键词试试。",
                actionTitle: "清除筛选"
            ) {
                query = ""
                scopeID = UpdateFilter.all.rawValue
            }
        }
    }

    // MARK: 安全分组（置顶）

    private var securityGroup: some View {
        UpdateGroupCard {
            securityHeader
        } rows: {
            if securityRows.isEmpty {
                securityEmptyRow
            } else {
                rowList(securityRows)
            }
        }
    }

    private var securityHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.text2)
                    .accessibilityHidden(true)
                Text("安全更新")
                    .font(AppTheme.headline(12))
                    .foregroundStyle(AppTheme.text1)
                    .accessibilityAddTraits(.isHeader)
                Text("\(securityRows.count)")
                    .font(AppTheme.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text3)
                Spacer(minLength: 10)
                securityHeaderStatus
            }
            if appState.scanIsStale {
                staleScanNotice
            }
        }
        .contextMenu {
            Button("全选当前列表") { toggleSelectAllVisible() }
                .disabled(selectableEntryIDs.isEmpty)
            Button("清除选择") { selection.removeAll() }
                .disabled(selection.isEmpty)
        }
    }

    /// 覆盖率与扫描时间常驻（P0-09：没有安全行也不能让用户误读成「扫描过且没发现」）。
    @ViewBuilder
    private var securityHeaderStatus: some View {
        if appState.isScanning {
            HStack(spacing: 6) {
                LoadingBar(height: 4)
                    .frame(width: 64)
                    .accessibilityHidden(true)
                Text(scanProgressText)
                    .font(AppTheme.caption())
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text3)
            }
        } else if let report = appState.vulnReport {
            HStack(spacing: 6) {
                if !report.complete {
                    Badge(text: "部分覆盖", color: AppTheme.warning, systemImage: "exclamationmark.triangle")
                }
                Text("\(appState.vulnerabilityCoverageText) · 本次扫描于 \(timeText(report.scannedAt))\(appState.vulnReportIsCached ? "（缓存）" : "")")
                    .font(AppTheme.caption())
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            HStack(spacing: 6) {
                Text("扫描未知 · 尚未扫描")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                Button("开始扫描") { appState.scanVulnerabilities() }
                    .glassSecondaryButton()
                    .controlSize(.small)
                    .disabled(appState.isScanning)
                    .help("运行一次漏洞扫描（约 30 秒），结果是部分覆盖")
            }
        }
    }

    private var scanProgressText: String {
        guard let progress = appState.scanProgress else { return "正在扫描…" }
        return "正在扫描 \(progress.checked)/\(progress.total) 个 formula"
    }

    /// O-07：上次扫描后已安装快照变化 → 只提示，不自动扫描。
    private var staleScanNotice: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.warning)
            Text("已安装的包有变化，扫描结果可能已过时。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.warning)
            Button("重新扫描") { appState.scanVulnerabilities() }
                .buttonStyle(.plain)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.accent)
                .disabled(appState.isScanning)
                .accessibilityLabel("重新扫描漏洞")
            Spacer(minLength: 0)
        }
    }

    private var securityEmptyRow: some View {
        Text(appState.vulnReport == nil
             ? "扫描未知 · 尚未扫描，无法判断哪些更新与已知漏洞相关。"
             : "本次扫描未发现可更新的安全项（\(appState.vulnerabilityCoverageText)）。")
            .font(AppTheme.callout())
            .foregroundStyle(AppTheme.text3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 常规分组

    private var regularGroup: some View {
        UpdateGroupCard {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.text2)
                    .accessibilityHidden(true)
                Text("常规更新")
                    .font(AppTheme.headline(12))
                    .foregroundStyle(AppTheme.text1)
                    .accessibilityAddTraits(.isHeader)
                Text("\(regularRows.count)")
                    .font(AppTheme.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text3)
                Spacer(minLength: 10)
                if let batchText = recentBatchProgressText {
                    Text(batchText)
                        .font(AppTheme.caption())
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text3)
                }
            }
            .contextMenu {
                Button("全选当前列表") { toggleSelectAllVisible() }
                    .disabled(selectableEntryIDs.isEmpty)
                Button("清除选择") { selection.removeAll() }
                    .disabled(selection.isEmpty)
            }
        } rows: {
            if regularRows.isEmpty {
                Text("当前范围没有常规更新。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                rowList(regularRows)
            }
        }
    }

    /// 批次进度只表达「当前 / 刚结束」的批次：完成 5 分钟后不再常驻，
    /// 避免打开更新页时把上周的批次当成正在发生的事。
    private var recentBatchProgressText: String? {
        guard appState.tasks.hasProgressPanel else { return nil }
        if let finishedAt = appState.tasks.progressFinishedAt,
           Date().timeIntervalSince(finishedAt) > 5 * 60 {
            return nil
        }
        let processed = appState.tasks.progressProcessedCount
        let total = appState.tasks.progressItems.count
        return "批次 \(processed)/\(total) 已完成"
    }

    // MARK: Row list

    @ViewBuilder
    private func rowList(_ list: [UpdateListRow]) -> some View {
        ForEach(list) { row in
            updateRow(row)
            if row.id != list.last?.id {
                Hairline()
                    .padding(.leading, 40)
                    .padding(.trailing, 14)
            }
        }
    }

    private func updateRow(_ row: UpdateListRow) -> some View {
        let entry = row.entry
        let progress = row.progress
        let record = record(for: row)
        let isSelected = entry.map { selection.contains($0.id) } == true
        return UpdateRowView(
            entry: entry,
            progress: progress,
            record: record,
            cancelledNotice: row.cancelledNotice,
            queuePosition: progress.flatMap { item -> Int? in
                // 聚合任务（全部更新）只有一条 record，逐行显示「第 1 位」会误导。
                guard let record, !Self.isAggregateAction(record.action) else { return nil }
                return appState.tasks.queuePosition(for: item.recordID)
            },
            summary: row.summary,
            isSelected: isSelected,
            isReadOnly: appState.isReadOnly,
            onToggleSelection: { if let entry { toggleSelection(entry) } },
            onOpen: { openDetail(row) },
            onUpdate: { if let entry { appState.upgrade(entry) } },
            onPreview: { if let entry { appState.previewUpgrade(entry) } },
            onViewLog: {
                if let id = progress?.recordID { appState.tasks.openHistoryRecord(id) }
            },
            onCopyCommand: { copyCommand(for: row, record: record) },
            onRetry: { retry(row, record: record) },
            canRetry: canRetry(row, record: record),
            retryHint: retryHint(row, record: record)
        )
    }

    // MARK: - Floating action bar (O-04)

    @ViewBuilder
    private var floatingBar: some View {
        FloatingActionBar(selectionCount: selection.count) {
            Button("更新所选") {
                appState.requestBatchUpdate(.selected(selectedTargets.map(\.id)))
            }
            .glassPrimaryButton()
            .disabled(selectedTargets.isEmpty || appState.isReadOnly)
            .help(selectedTargets.isEmpty
                  ? "所选包已锁定或已进入批次，没有可更新的项"
                  : "确认后串行更新这 \(selectedTargets.count) 个包")

            previewControl

            Button("取消选择") {
                selection.removeAll()
            }
            .glassSecondaryButton()
            .help("取消勾选，不改变任何包")
        }
    }

    /// dry-run 一次只能预览一个包（只读 API 是单包）；多选时给一个包名菜单。
    @ViewBuilder
    private var previewControl: some View {
        let targets = selectedTargets
        if targets.count == 1 {
            Button("预览") { appState.previewUpgrade(targets[0]) }
                .glassSecondaryButton()
                .disabled(appState.isReadOnly)
                .help("只读预览 \(targets[0].name) 的更新（不修改本机）")
        } else {
            Menu {
                if targets.isEmpty {
                    Text("没有可预览的包")
                } else {
                    ForEach(targets) { entry in
                        Button("预览 \(entry.name)") { appState.previewUpgrade(entry) }
                    }
                }
            } label: {
                Text("预览")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .fixedSize()
            .disabled(targets.isEmpty || appState.isReadOnly)
            .help("选择要 dry-run 预览的包（一次预览一个，不修改本机）")
        }
    }

    // MARK: - Dry-run preview (C-11)

    private var previewPresented: Binding<Bool> {
        Binding(
            get: { appState.upgradePreview != nil },
            set: { shown in
                if !shown { appState.cancelUpgradePreview() }
            }
        )
    }

    @ViewBuilder
    private var previewSheet: some View {
        if let preview = appState.upgradePreview {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("预览更新 \(preview.name)")
                        .font(AppTheme.subheading())
                        .foregroundStyle(AppTheme.text1)
                    Badge(text: "dry-run · 只读", color: AppTheme.text2)
                    Spacer()
                    if preview.isRunning {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("只读预览：不修改本机；真实执行结果可能因依赖解析或 auto_updates 而不同。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                if let error = preview.error {
                    Text(error)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.danger)
                        .textSelection(.enabled)
                }
                ScrollView {
                    Text(preview.output.isEmpty
                         ? (preview.isRunning ? "正在运行只读预览…" : "没有输出")
                         : preview.output)
                        .font(AppTheme.mono())
                        .foregroundStyle(AppTheme.consoleText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 220, maxHeight: 320)
                .background(AppTheme.consoleBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )
                HStack {
                    Spacer()
                    if preview.isRunning {
                        Button("取消预览") { appState.cancelUpgradePreview() }
                            .glassSecondaryButton()
                    }
                    Button("关闭") { appState.cancelUpgradePreview() }
                        .glassPrimaryButton()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 600)
            .background(AppTheme.canvas)
        }
    }

    // MARK: - Row actions / helpers

    private func openDetail(_ row: UpdateListRow) {
        guard let name = row.entry?.name ?? row.progress?.name else { return }
        let kind = row.entry?.kind
        if let package = appState.index.package(named: name, kind: kind) {
            appState.selectPackage(package)
        }
    }

    private static func matchesProgressName(_ progressName: String, _ entryName: String) -> Bool {
        if progressName == entryName { return true }
        if let last = entryName.split(separator: "/").last, String(last) == progressName { return true }
        return false
    }

    private static func shortName(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private func record(for row: UpdateListRow) -> TaskRecord? {
        guard let id = row.progress?.recordID else { return nil }
        return appState.tasks.records.first { $0.id == id }
    }

    private func cancelledNotice(for progress: PackageProgressItem?, noticed: inout Set<UUID>) -> String? {
        guard let progress, progress.state == .cancelled, !noticed.contains(progress.recordID),
              let record = appState.tasks.records.first(where: { $0.id == progress.recordID }),
              let message = record.message, !message.isEmpty
        else { return nil }
        noticed.insert(progress.recordID)
        return message
    }

    /// 聚合任务只有一条命令，无法按包重放；行内重试退化为对该包执行一次单包更新。
    private static func isAggregateAction(_ action: String) -> Bool {
        action == ChangeTask.Kind.upgradeAll.rawValue
    }

    private func canRetry(_ row: UpdateListRow, record: TaskRecord?) -> Bool {
        guard let record, !appState.isReadOnly else { return false }
        if Self.isAggregateAction(record.action) {
            return row.entry != nil && row.entry?.pinned != true
        }
        return appState.tasks.canRetry(recordID: record.id)
    }

    private func retryHint(_ row: UpdateListRow, record: TaskRecord?) -> String? {
        guard let record else { return "该行没有可重试的任务记录" }
        if appState.isReadOnly { return "Homebrew 版本过低，当前为只读模式" }
        if Self.isAggregateAction(record.action) {
            if row.entry == nil { return "该包已不在可更新列表，请刷新后重试" }
            if row.entry?.pinned == true { return "已锁定，请先在详情页解锁" }
            return "对该包重新执行一次单包更新"
        }
        if !appState.tasks.canRetry(recordID: record.id) {
            return "历史任务无法在应用内重试；可复制命令在终端执行"
        }
        return "重新执行同一命令"
    }

    private func retry(_ row: UpdateListRow, record: TaskRecord?) {
        guard let record else { return }
        if Self.isAggregateAction(record.action) {
            guard let entry = row.entry, entry.pinned != true else {
                appState.showToast("该包已不可更新或已锁定，请刷新后重试", kind: .info)
                return
            }
            appState.upgrade(entry)
            return
        }
        guard appState.tasks.canRetry(recordID: record.id) else {
            appState.showToast("该任务来自上次会话，无法在应用内重试；可复制命令在终端执行", kind: .info)
            return
        }
        appState.retryTask(recordID: record.id)
    }

    private func copyCommand(for row: UpdateListRow, record: TaskRecord?) {
        let command = commandText(for: row, record: record)
        guard !command.isEmpty else {
            appState.showToast("没有可复制的命令", kind: .info)
            return
        }
        copyToPasteboard(command)
        appState.showToast("命令已复制", kind: .success)
    }

    private func commandText(for row: UpdateListRow, record: TaskRecord?) -> String {
        if let record, !Self.isAggregateAction(record.action), !record.commandText.isEmpty {
            return record.commandText
        }
        let name = row.entry?.name ?? row.progress?.name ?? ""
        guard !name.isEmpty else { return record?.commandText ?? "" }
        let isCask = row.entry?.kind == .cask || row.progress?.kind == PackageSnapshot.Kind.cask.rawValue
        return "brew upgrade \(isCask ? "--cask " : "")\(name)"
    }

    private static func elapsedText(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "已用 %d:%02d", total / 60, total % 60)
    }

    // MARK: - Keyboard

    private var hiddenShortcuts: some View {
        Group {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { toggleSelectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
            Button("") { performMainAction() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(mainActionDisabled)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - List row model

/// 更新页单一列表的行：仍在 outdated 的条目，或已从 outdated 消失但仍有批次
/// 进度（完成 / 失败 / 未执行）的包。
struct UpdateListRow: Identifiable {
    let id: String
    let entry: OutdatedEntry?
    let progress: PackageProgressItem?
    /// 取消批次时的一次性提示（「已取消，剩余 N 个未执行」）。
    var cancelledNotice: String? = nil
    /// 安全分组归属：条目自己带 finding，或曾经是安全行（更新成功后仍留在安全组）。
    var isSecurity = false
    /// 包描述（来自已安装索引），用于行内说明。
    var summary: String?
}

// MARK: - Group card

/// 内容层实底卡片：分组头 + 行。玻璃只用于控制层，卡片本身不透明（规范 §1.2）。
private struct UpdateGroupCard<Header: View, Rows: View>: View {
    private let header: Header
    private let rowsContent: Rows

    init(@ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows) {
        self.header = header()
        self.rowsContent = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.surface2)
            Hairline()
            rowsContent
        }
        .background(AppTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }
}

// MARK: - Update row

/// 规范 §5 PackageTableRow：状态圆点替代复选框（有批次进度时），行内只留
/// 「更新」按钮；dry-run 预览在 hover / 右键菜单 / VoiceOver 自定义动作里。
/// 失败行保留「查看日志 / 重试…」闭环（O-02：失败常驻，不做 2.6s toast）。
struct UpdateRowView: View {
    var entry: OutdatedEntry?
    var progress: PackageProgressItem?
    var record: TaskRecord?
    var cancelledNotice: String?
    var queuePosition: Int?
    var summary: String?
    var isSelected: Bool
    var isReadOnly: Bool
    var onToggleSelection: () -> Void
    var onOpen: () -> Void
    var onUpdate: () -> Void
    var onPreview: () -> Void
    var onViewLog: () -> Void
    var onCopyCommand: () -> Void
    var onRetry: () -> Void
    var canRetry = false
    var retryHint: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var name: String { entry?.name ?? progress?.name ?? "" }
    private var kindText: String? { entry?.kind.rawValue ?? progress?.kind }
    private var installedText: String {
        if let entry { return entry.installedText }
        return progress?.fromVersion ?? ""
    }
    private var targetVersionText: String {
        if let entry { return entry.currentVersion }
        return progress?.toVersion ?? "—"
    }
    private var isPinned: Bool { entry?.pinned == true }

    private var severity: VulnSeverity? {
        entry?.severity ?? entry?.finding?.worstSeverity
    }

    private var canUpdate: Bool {
        entry != nil && progress == nil && !isPinned && !isReadOnly
    }

    private var updateButtonHelp: String {
        if isPinned { return "已锁定的包不会被更新，可在详情中解锁" }
        if isReadOnly { return "只读模式：Homebrew 版本过低，无法执行更新" }
        if progress != nil { return "该包已在当前批次中" }
        return "更新 \(name) 到 \(targetVersionText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                leadingControl
                    .frame(width: 16)

                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        nameLine
                        detailLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("打开详情")

                versionColumn
                    .frame(minWidth: 118, alignment: .trailing)

                trailingControl
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)

            stateDetail
        }
        .background(rowBackground)
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuContent }
        // 行内 hover 才出现的预览必须同时有右键菜单与 VoiceOver 动作（规范 §7）。
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("预览更新（dry-run）")) {
            if entry != nil, !isPinned, !isReadOnly { onPreview() }
        }
        .accessibilityAction(named: Text("更新 \(name)")) {
            if canUpdate { onUpdate() }
        }
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.accentSoft.opacity(0.45) }
        if isHovering { return AppTheme.surface3.opacity(0.55) }
        return Color.clear
    }

    // MARK: Leading control

    @ViewBuilder
    private var leadingControl: some View {
        if let progress {
            PackageStateDot(state: progress.state)
        } else {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.text3)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(isPinned)
            .help(isPinned ? "已锁定的包不会被更新，可在详情中解锁" : "选择 \(name)")
            .accessibilityLabel("选择 \(name)")
            .accessibilityValue(isSelected ? "已选中" : "未选中")
        }
    }

    // MARK: Name / detail

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(AppTheme.headline())
                .foregroundStyle(AppTheme.text1)
                .lineLimit(1)
            if severity != nil, !isSecurityRow {
                SeverityBadge(severity: severity ?? .unknown, compact: true)
            }
            if kindText == PackageSnapshot.Kind.cask.rawValue {
                KindBadge(kind: .cask)
            }
            if isPinned {
                Badge(text: "已锁定", color: AppTheme.text2, systemImage: "pin.fill")
            }
        }
    }

    private var isSecurityRow: Bool { entry?.isSecurityUpdate == true }

    @ViewBuilder
    private var detailLine: some View {
        if let progress {
            progressDetailLine(progress)
        } else if let entry, let finding = entry.finding {
            securityDetailLine(entry: entry, finding: finding)
        } else {
            Text(summary?.nilIfEmpty ?? kindText ?? "")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .lineLimit(1)
        }
    }

    private func securityDetailLine(entry: OutdatedEntry, finding: VulnerabilityFinding) -> some View {
        HStack(spacing: 6) {
            SeverityBadge(severity: entry.severity ?? finding.worstSeverity, compact: true)
            if let first = finding.vulnerabilities.first {
                Text(first.id)
                    .font(AppTheme.mono(11))
                    .foregroundStyle(AppTheme.text2)
                    .lineLimit(1)
                if finding.vulnerabilities.count > 1 {
                    Text("等 \(finding.vulnerabilities.count) 条")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
            if finding.hasFix {
                if let fixVersion = finding.vulnerabilities.first(where: { !$0.fixedVersions.isEmpty })?.fixedVersions.first {
                    Text("修复于 \(fixVersion)")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)
                } else {
                    Text("修复可用")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.success)
                }
            } else {
                Text("上游暂无修复版本")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .lineLimit(1)
    }

    private func progressDetailLine(_ progress: PackageProgressItem) -> some View {
        HStack(spacing: 6) {
            switch progress.state {
            case .running:
                Text(progress.stage?.label ?? "运行中")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.accent)
                LoadingBar(height: 4)
                    .frame(width: 120)
                    .accessibilityHidden(true)
            case .succeeded:
                Text("完成")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.success)
            case .unverified:
                Text("未确认 · 版本未核实")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.warning)
            case .failed:
                Text("失败")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
            case .pending:
                Text(queuePosition.map { "排队中 · 第 \($0) 位" } ?? "排队中")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            case .cancelled:
                Text("已取消")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            case .skipped:
                Text("未执行")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Version

    private var versionColumn: some View {
        HStack(spacing: 5) {
            Text(installedText.isEmpty ? "—" : installedText)
                .font(AppTheme.mono())
                .foregroundStyle(AppTheme.text3)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.text3)
                .accessibilityHidden(true)
            Text(targetVersionText)
                .font(AppTheme.mono(11.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(installedText.isEmpty
                            ? "可更新到 \(targetVersionText)"
                            : "\(installedText) 可更新到 \(targetVersionText)")
    }

    // MARK: Trailing

    @ViewBuilder
    private var trailingControl: some View {
        if let progress {
            if progress.state == .failed {
                HStack(spacing: 6) {
                    if record != nil {
                        Button("日志") { onViewLog() }
                            .glassSecondaryButton()
                            .controlSize(.small)
                            .help("打开任务岛查看这条命令的输出")
                    }
                    Button("重试…") { onRetry() }
                        .glassSecondaryButton()
                        .controlSize(.small)
                        .disabled(!canRetry)
                        .help(retryHint ?? "重新执行该任务")
                }
            }
        } else if entry != nil {
            HStack(spacing: 6) {
                if isHovering {
                    Button(action: onPreview) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.text2)
                    .disabled(isPinned || isReadOnly)
                    .help(isPinned ? "已锁定，预览前请先解锁" : "预览更新（dry-run，不修改本机）")
                    .accessibilityLabel("预览 \(name) 的更新")
                    .transition(.opacity)
                }
                Button("更新") { onUpdate() }
                    .glassSecondaryButton()
                    .controlSize(.small)
                    .disabled(!canUpdate)
                    .help(updateButtonHelp)
                    .accessibilityLabel("更新 \(name) 到 \(targetVersionText)")
            }
            .animation(reduceMotion ? .easeInOut(duration: AppMaterial.reducedMotionDuration) : .easeInOut(duration: 0.12), value: isHovering)
        }
    }

    // MARK: State detail (失败 / 取消)

    @ViewBuilder
    private var stateDetail: some View {
        if progress?.state == .failed {
            failureDetail
        } else if let cancelledNotice {
            Text(cancelledNotice)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.warning)
                .lineLimit(2)
                .padding(.leading, detailInset)
                .padding(.trailing, 14)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var failureDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let exitCode = record?.exitCode {
                    Badge(text: "退出码 \(exitCode)", color: AppTheme.danger)
                }
                Text(failureMessage)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if let suggestion = record?.suggestion, !suggestion.isEmpty {
                Text(suggestion)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text2)
                    .lineLimit(2)
            }
            if let note = record?.verificationNote, !note.isEmpty {
                Text(note)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.warning)
                    .lineLimit(2)
            }
        }
        .padding(.leading, detailInset)
        .padding(.trailing, 14)
        .padding(.bottom, 8)
    }

    private var failureMessage: String {
        if let message = record?.message, !message.isEmpty { return message }
        return progress?.errorMessage ?? "任务失败"
    }

    /// 与包名左缘对齐：行内边距 14 + 状态圆点 16 + 间距 10。
    private var detailInset: CGFloat { 40 }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if let entry, progress == nil {
            Button("更新 \(entry.name)") { onUpdate() }
                .disabled(!canUpdate)
            Button("预览更新（dry-run）") { onPreview() }
                .disabled(isPinned || isReadOnly)
            Divider()
            Button("打开详情") { onOpen() }
            Button("复制更新命令") { onCopyCommand() }
        } else if progress != nil {
            Button("打开任务岛查看日志") { onViewLog() }
            Button("复制命令") { onCopyCommand() }
            Divider()
            Button("打开详情") { onOpen() }
            Button("重试…") { onRetry() }
                .disabled(!canRetry)
        }
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        var parts = [name]
        if let kindText { parts.append(kindText) }
        if isPinned { parts.append("已锁定") }
        if let severity, entry?.isSecurityUpdate == true {
            parts.append("有已知漏洞，\(severity.label)")
            if let finding = entry?.finding {
                if let first = finding.vulnerabilities.first {
                    parts.append(first.id)
                }
                parts.append(finding.hasFix ? "修复可用" : "上游暂无修复版本")
            }
        }
        if !installedText.isEmpty {
            parts.append("\(installedText) 可更新到 \(targetVersionText)")
        }
        if let progress {
            if progress.state == .running, let stage = progress.stage {
                parts.append(stage.label)
            } else {
                parts.append(progress.state.label)
            }
            if progress.state == .failed {
                parts.append(failureMessage)
                if let exitCode = record?.exitCode { parts.append("退出码 \(exitCode)") }
            }
        }
        if let queuePosition { parts.append("排队中，第 \(queuePosition) 位") }
        return parts.joined(separator: "，")
    }
}
