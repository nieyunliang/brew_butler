import SwiftUI

/// 规范 §4.9：命令面板（⌘K）。
///
/// 结构：窗口顶部 1/5 居中、宽 640 的玻璃面板（圆角 24），背后内容加 0.08
/// 黑色暗化；分组固定为「页面 / 包 / 操作 / 远端」，空查询时先给最近任务与
/// 最近搜索（保留 v1 的「回到刚才的工作」入口）。
///
/// 键盘：Esc 关闭、↑↓ 选择、↵ 打开；焦点留在输入框（Tab 也回到输入框），
/// 面板内不出现第二个可 Tab 到的控件岛，避免焦点逃出浮层。
struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var highlighted = 0
    @State private var hoveredID: String?
    @FocusState private var fieldFocused: Bool

    private enum Metrics {
        static let panelWidth: CGFloat = 640
        static let headerHeight: CGFloat = 52
        static let footerHeight: CGFloat = 32
        static let rowHeight: CGFloat = 32
        static let groupHeaderHeight: CGFloat = 23
        static let groupPadding: CGFloat = 8
        static let outerPadding: CGFloat = 8
        static let groupSpacing: CGFloat = 2
        static let cornerRadius = AppTheme.glassRadius // 24
        static let topFraction: CGFloat = 0.2
    }

    // MARK: - Item model

    private struct PaletteItem: Identifiable {
        enum Group: String {
            case recentTask = "最近任务"
            case recentSearch = "最近搜索"
            case page = "页面"
            case package = "包"
            case action = "操作"
            case remote = "远端"

            /// 显示顺序固定（§4.9）：最近任务/最近搜索在前，远端入口永远在最后。
            static let displayOrder: [Group] = [.recentTask, .recentSearch, .page, .package, .action, .remote]
        }

        var id: String
        var group: Group
        var title: String
        var detail: String?
        var shortcut: String?
        var symbol: String
        var severity: VulnSeverity?
        var isDangerous = false
        var run: @MainActor () -> Void

        var accessibilityLabel: String {
            var parts = [title]
            if let detail { parts.append(detail) }
            if let shortcut { parts.append("快捷键 \(shortcut)") }
            if isDangerous { parts.append("需要确认") }
            return parts.joined(separator: "，")
        }
    }

    /// 一个分组在扁平列表里的起点，供 ↑↓ 选择使用。
    private struct PaletteGroup: Identifiable {
        var id: String { header }
        var header: String
        var items: [PaletteItem]
        var startIndex: Int
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let panelCap = max(300, proxy.size.height * 0.72)
            let scrollCap = max(120, panelCap - Metrics.headerHeight - Metrics.footerHeight - 2)
            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)

                panel(scrollHeight: min(estimatedContentHeight, scrollCap))
                    .padding(.top, max(24, proxy.size.height * Metrics.topFraction))
            }
        }
        .onAppear {
            fieldFocused = true
            highlighted = 0
        }
        .onChange(of: query) { _, _ in
            highlighted = 0
            hoveredID = nil
        }
    }

    private func panel(scrollHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            searchHeader
            Hairline()
            resultsList
                .frame(height: scrollHeight)
            Hairline()
            footerBar
        }
        .frame(width: Metrics.panelWidth)
        .glassPanel(cornerRadius: Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.28), radius: 40, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("命令面板")
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { activateHighlighted(); return .handled }
        .onKeyPress(.tab) { fieldFocused = true; return .handled }
        .onExitCommand { close() }
    }

    // MARK: - Header

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.text3)

            TextField("页面、包或操作…", text: $query)
                .textFieldStyle(.plain)
                .font(AppTheme.body(15))
                .foregroundStyle(AppTheme.text1)
                .focused($fieldFocused)
                // 焦点在 NSTextField 内时上下键/回车先被文本编辑器处理，
                // 所以监听必须挂在输入框本身（v1 E-18 的同一个坑）。
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.return) { activateHighlighted(); return .handled }
                .onKeyPress(.tab) { fieldFocused = true; return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                .accessibilityLabel("搜索页面、包或操作")

            Text("esc")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .frame(height: Metrics.headerHeight)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(renderedGroups) { group in
                        VStack(alignment: .leading, spacing: Metrics.groupSpacing) {
                            Text(group.header)
                                .font(AppTheme.caption())
                                .captionTracking()
                                .foregroundStyle(AppTheme.text3)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 3)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { offset, item in
                                row(item, index: group.startIndex + offset)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, Metrics.groupPadding)
                        .padding(.vertical, 4)
                    }

                    if renderedGroups.isEmpty {
                        Text("没有匹配结果")
                            .font(AppTheme.body())
                            .foregroundStyle(AppTheme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.vertical, Metrics.outerPadding)
            }
            .onChange(of: highlighted) { _, newValue in
                let items = flatItems
                guard items.indices.contains(newValue) else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo(items[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func row(_ item: PaletteItem, index: Int) -> some View {
        let isHighlighted = index == highlighted
        let isHovered = hoveredID == item.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            activate(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHighlighted
                                     ? AppTheme.onAccent
                                     : (item.isDangerous ? AppTheme.danger : AppTheme.text2))
                    .frame(width: 18)

                Text(item.title)
                    .font(AppTheme.body(13))
                    .foregroundStyle(isHighlighted ? AppTheme.onAccent : AppTheme.text1)
                    .lineLimit(1)

                if let severity = item.severity {
                    severityChip(severity, highlighted: isHighlighted)
                }

                if let detail = item.detail {
                    Text(detail)
                        .font(AppTheme.mono(11))
                        .foregroundStyle(isHighlighted ? AppTheme.onAccent.opacity(0.82) : AppTheme.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let shortcut = item.shortcut {
                    shortcutKey(shortcut, highlighted: isHighlighted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.rowHeight)
            .background { rowBackground(highlighted: isHighlighted, hovered: isHovered, shape: shape) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = item.id
            } else if hoveredID == item.id {
                hoveredID = nil
            }
        }
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }

    @ViewBuilder
    private func rowBackground(highlighted: Bool, hovered: Bool, shape: RoundedRectangle) -> some View {
        if highlighted {
            shape.fill(AppTheme.accentFill)
        } else if hovered {
            shape.fill(Color.primary.opacity(0.06))
        } else {
            shape.fill(Color.clear)
        }
    }

    @ViewBuilder
    private func severityChip(_ severity: VulnSeverity, highlighted: Bool) -> some View {
        if highlighted {
            Text(severity.label)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(AppTheme.onAccent.opacity(0.18), in: Capsule())
        } else {
            SeverityBadge(severity: severity, compact: true)
        }
    }

    private func shortcutKey(_ shortcut: String, highlighted: Bool) -> some View {
        Text(shortcut)
            .font(AppTheme.caption())
            .foregroundStyle(highlighted ? AppTheme.onAccent.opacity(0.85) : AppTheme.text3)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                highlighted ? AppTheme.onAccent.opacity(0.16) : AppTheme.surface3,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            Text("↑↓ 选择")
            Text("↵ 打开")
            Text("esc 关闭")
            Spacer(minLength: 0)
        }
        .font(AppTheme.caption())
        .foregroundStyle(AppTheme.text3)
        .padding(.horizontal, 18)
        .frame(height: Metrics.footerHeight)
        .accessibilityHidden(true)
    }

    // MARK: - Flat data

    private var renderedGroups: [PaletteGroup] {
        let all = buildItems()
        var groups: [PaletteGroup] = []
        var flatIndex = 0
        for group in PaletteItem.Group.displayOrder {
            let items = all.filter { $0.group == group }
            guard !items.isEmpty else { continue }
            groups.append(PaletteGroup(header: group.rawValue, items: items, startIndex: flatIndex))
            flatIndex += items.count
        }
        return groups
    }

    private var flatItems: [PaletteItem] {
        renderedGroups.flatMap(\.items)
    }

    /// 行数 × 行高 + 分组头/内边距，用于让面板在结果少时收缩、
    /// 结果多时封顶后滚动（固定 maxHeight 会让两行结果的面板也占满整屏）。
    private var estimatedContentHeight: CGFloat {
        var height = Metrics.outerPadding * 2
        for group in renderedGroups {
            height += Metrics.groupHeaderHeight + 8
            height += CGFloat(group.items.count) * Metrics.rowHeight
            height += CGFloat(max(0, group.items.count - 1)) * Metrics.groupSpacing
        }
        return max(height, 96)
    }

    // MARK: - Items

    private func buildItems() -> [PaletteItem] {
        let needle = query.trimmed.lowercased()
        var result: [PaletteItem] = []

        // 空查询：最近任务（保留 v1 行为），让 ⌘K 也能回到刚才的工作。
        if needle.isEmpty {
            for record in appState.tasks.records.suffix(5).reversed() {
                let timeText = (record.finishedAt ?? record.startedAt ?? record.createdAt).relativeText
                let isRunning = record.status == .running || record.status == .cancelling
                result.append(PaletteItem(
                    id: "recent-task-\(record.id.uuidString)",
                    group: .recentTask,
                    title: record.title,
                    detail: "\(record.status.label) · \(timeText)",
                    shortcut: nil,
                    symbol: isRunning ? "hourglass" : "clock.arrow.circlepath",
                    severity: nil
                ) {
                    appState.tasks.openHistoryRecord(record.id)
                })
            }

            // 空查询也给最近搜索：发现页的最近搜索只存本地，这里直接复用。
            let recentSearches = appState.settings.recentSearches
            for recent in recentSearches.prefix(5) {
                result.append(PaletteItem(
                    id: "recent-search-\(recent)",
                    group: .recentSearch,
                    title: "“\(recent)”",
                    detail: "在 Homebrew 中搜索",
                    shortcut: nil,
                    symbol: "clock.arrow.circlepath",
                    severity: nil
                ) {
                    appState.settings.recordRecentSearch(recent)
                    appState.openDiscover(query: recent)
                })
            }
        }

        // 页面（⌘1–⌘5）。
        for section in AppSection.allCases
        where needle.isEmpty || section.title.lowercased().contains(needle) {
            result.append(PaletteItem(
                id: "page-\(section.rawValue)",
                group: .page,
                title: section.title,
                detail: nil,
                shortcut: section.shortcut,
                symbol: section.symbol,
                severity: nil
            ) {
                appState.openSection(section)
            })
        }

        // 包（已安装索引）：搜索词命中包名或描述，行内给版本变化/严重度。
        if !needle.isEmpty {
            let matches = appState.index.packages.filter { package in
                package.name.lowercased().contains(needle)
                    || package.displayName.lowercased().contains(needle)
                    || (package.desc?.lowercased().contains(needle) ?? false)
            }
            for package in matches.prefix(10) {
                result.append(PaletteItem(
                    id: "package-\(package.id)",
                    group: .package,
                    title: package.displayName,
                    detail: package.outdated
                        ? "\(package.installedVersion ?? "—") → \(package.stableVersion ?? "—")"
                        : package.displayVersion,
                    shortcut: nil,
                    symbol: package.kind == .cask ? "app.badge" : "shippingbox",
                    severity: package.vulnerabilitySeverity
                ) {
                    appState.selectPackage(package)
                })
            }
            // 结果被截断时给出出路，避免让人以为只有 10 个匹配（v1 E-07）。
            if matches.count > 10 {
                result.append(PaletteItem(
                    id: "package-more",
                    group: .package,
                    title: "共 \(matches.count) 个结果 · 在发现页查看全部",
                    detail: nil,
                    shortcut: nil,
                    symbol: "magnifyingglass",
                    severity: nil
                ) {
                    appState.settings.recordRecentSearch(query.trimmed)
                    appState.openDiscover(query: query.trimmed)
                })
            }
        }

        // 操作：每个动作只有一个家（UX 方案 O-05）；「清理…」带省略号，
        // 一定进入确认弹层，不直接执行。
        let actions: [(title: String, detail: String?, shortcut: String, symbol: String, dangerous: Bool, keywords: String, run: @MainActor () -> Void)] = [
            ("检查更新", "先同步 Homebrew 索引", "⌘R", "arrow.triangle.2.circlepath", false, "check update refresh 同步",
             { Task { await appState.checkUpdates() } }),
            ("运行安全扫描", "约 30 秒", "⇧⌘V", "checkmark.shield", false, "scan vulns 漏洞",
             { appState.scanVulnerabilities() }),
            ("清理…", "先预览，需二次确认", "⇧⌘K", "sparkles", true, "cleanup 缓存",
             { Task { await appState.previewCleanup(presentSheet: true) } }),
            ("运行 brew doctor", "结果在维护页显示", "⇧⌘D", "stethoscope", false, "doctor 诊断",
             {
                 appState.openSection(.maintenance)
                 Task { await appState.runDoctor() }
             }),
            ("展开任务岛", "查看进度、日志与队列", "⌥⌘L", "rectangle.bottomthird.inset.filled", false, "task log 日志",
             { appState.tasks.showDrawer = true }),
            ("打开设置", "外观、Homebrew、通知、隐私", "⌘,", "gearshape", false, "settings 偏好",
             { openSettings() })
        ]
        for action in actions where needle.isEmpty || matchesQuery(needle, action.title, action.keywords) {
            result.append(PaletteItem(
                id: "action-\(action.title)",
                group: .action,
                title: action.title,
                detail: action.detail,
                shortcut: action.shortcut,
                symbol: action.symbol,
                severity: nil,
                isDangerous: action.dangerous,
                run: action.run
            ))
        }

        // 远端：始终在最后，作为「去 Homebrew 搜」的唯一出口（§3.3）。
        let remoteQuery = query.trimmed
        result.append(PaletteItem(
            id: "remote-search",
            group: .remote,
            title: remoteQuery.isEmpty ? "打开发现页" : "在 Homebrew 中搜索 “\(remoteQuery)”",
            detail: remoteQuery.isEmpty ? nil : "formulae.brew.sh",
            shortcut: "↵",
            symbol: "magnifyingglass",
            severity: nil
        ) {
            if !remoteQuery.isEmpty {
                appState.settings.recordRecentSearch(remoteQuery)
                appState.openDiscover(query: remoteQuery)
            } else {
                appState.openDiscover(search: false)
            }
        })

        return result
    }

    private func matchesQuery(_ needle: String, _ title: String, _ keywords: String) -> Bool {
        // 中英文都走同一条 contains（页面/操作标题本身是中文，关键词是英文别名）。
        title.lowercased().contains(needle) || keywords.lowercased().contains(needle)
    }

    // MARK: - Interaction

    private func move(_ delta: Int) {
        let count = flatItems.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func activateHighlighted() {
        let items = flatItems
        guard items.indices.contains(highlighted) else { return }
        activate(items[highlighted])
    }

    private func activate(_ item: PaletteItem) {
        // 先关面板再执行：否则「清理…」弹出的确认弹层会被浮层盖住。
        close()
        item.run()
    }

    private func close() {
        appState.showCommandPalette = false
    }
}
