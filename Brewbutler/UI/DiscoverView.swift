import SwiftUI

/// 规范 §4.4：发现（搜索结果页）。
///
/// 发现页只是搜索结果页——没有「快捷筛选」之类的伪分类（UX 方案 O-10）。
/// 所有入口（工具栏搜索、命令面板、资料库空态、包详情依赖行）都复用
/// `AppState.discover` 这一份状态；返回统一走 `closeDiscover()`。
///
/// 没有搜索词时显示「最近搜索」（只存本地、可清除、不进诊断包）和一句
/// 「已安装的包也可以在资料库中找到」。
struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var resultsFocused: Bool
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedIndex = 0

    private var query: String { appState.discover.query.trimmed }
    private var results: [BrewSearchResult] { appState.discover.results }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                serviceNotice
                content
            }
            .pagePadding()
        }
        .onAppear {
            // 入口可能只预填了关键词（依赖行的「在 Homebrew 中搜索」），
            // 这里补一次搜索，保证任何入口进来都看到结果而不是空页。
            if !query.isEmpty, !appState.discover.hasSearched, !appState.discover.isSearching {
                appState.searchDiscover()
            }
        }
        .onChange(of: appState.discover.query) { _, _ in
            scheduleSearch()
        }
        .onChange(of: appState.discover.kind) { _, _ in
            // 结果类型 scope 切换：重新搜索，而不是本地过滤掉一半结果。
            appState.searchDiscover()
        }
        .onChange(of: appState.discover.results.count) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: appState.discover.isSearching) { _, isSearching in
            // O-10：最近搜索只在搜索真正跑完后记录，避免把防抖中的半截关键词存进去。
            guard !isSearching else { return }
            let finishedQuery = query
            guard !finishedQuery.isEmpty else { return }
            appState.settings.recordRecentSearch(finishedQuery)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                appState.closeDiscover()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .glassSecondaryButton()
            .help("返回 ⌘[")
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text(heroTitle)
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(heroSubtitle)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 12)

            GlassScopeBar(
                options: scopeOptions,
                selection: scopeSelection,
                accessibilityLabel: "结果类型"
            )
        }
    }

    private var heroTitle: String {
        query.isEmpty ? "在 Homebrew 中搜索" : "在 Homebrew 中搜索 “\(query)”"
    }

    private var heroSubtitle: String {
        if query.isEmpty {
            return "在工具栏搜索框输入关键词，在 formulae.brew.sh 上搜索全部 formula 与 cask。"
        }
        if appState.discover.isSearching {
            return "正在搜索…"
        }
        guard appState.discover.hasSearched else {
            return appState.discover.error ?? "准备搜索…"
        }
        let installed = results.filter { appState.isInstalled($0) }.count
        let source = appState.discover.usingCache ? "本地缓存" : "formulae.brew.sh"
        return "\(source) · \(results.count) 个结果 · \(installed) 个已安装"
    }

    private var scopeOptions: [GlassScopeOption] {
        let hasCounts = !results.isEmpty
        let formulaCount = results.filter { $0.kind == .formula }.count
        let caskCount = results.filter { $0.kind == .cask }.count
        return [
            GlassScopeOption(id: "all", title: "全部", count: hasCounts ? results.count : nil),
            GlassScopeOption(id: "formula", title: "formula", count: hasCounts ? formulaCount : nil),
            GlassScopeOption(id: "cask", title: "cask", count: hasCounts ? caskCount : nil)
        ]
    }

    private var scopeSelection: Binding<String> {
        Binding(
            get: { appState.discover.kind?.rawValue ?? "all" },
            set: { newValue in
                appState.discover.kind = newValue == "all" ? nil : PackageSnapshot.Kind(rawValue: newValue)
            }
        )
    }

    // MARK: - Cache / error notice

    @ViewBuilder
    private var serviceNotice: some View {
        if appState.discover.usingCache {
            GlassNotice(
                level: appState.discover.cacheIsLocalOnly || appState.discover.cacheIsStale ? .warning : .info,
                message: cacheNoticeMessage,
                actionTitle: "刷新",
                action: { appState.searchDiscover(forceRefresh: true) }
            )
            .accessibilityLabel("离线提示：\(cacheNoticeMessage)")
        } else if let error = appState.discover.error {
            GlassNotice(
                level: .warning,
                title: "搜索失败",
                message: error,
                actionTitle: "重试",
                action: { appState.searchDiscover(forceRefresh: true) }
            )
        }
    }

    private var cacheNoticeMessage: String {
        if appState.discover.cacheIsLocalOnly {
            return "网络不可用，仅显示本地已安装的包；联网后可搜索全部 formula 与 cask。"
        }
        if let cachedAt = appState.discover.cacheDate {
            return "使用 \(cachedAt.relativeText)的本地缓存，结果可能不是最新。"
        }
        return "网络不可用，当前显示本地缓存，结果可能不是最新。"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            emptyQueryContent
        } else if results.isEmpty {
            if appState.discover.isSearching {
                searchingSkeleton
            } else if appState.discover.hasSearched {
                noResultsState
            } else {
                searchingSkeleton
            }
        } else {
            resultsSection
        }
    }

    // MARK: No query（O-10：最近搜索，不伪造分类）

    private var emptyQueryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            recentSearchesCard

            HStack(spacing: 10) {
                Text("已安装的包也可以在资料库中找到。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                Spacer(minLength: 8)
                Button("打开资料库") {
                    appState.openSection(.library)
                }
                .glassSecondaryButton()
                .help("返回资料库 ⌘3")
            }
        }
    }

    private var recentSearchesCard: some View {
        let recents = appState.settings.recentSearches
        return SectionCard(
            title: "最近搜索",
            subtitle: nil,
            accessory: recents.isEmpty ? nil : AnyView(clearRecentSearchesButton)
        ) {
            if recents.isEmpty {
                Text("还没有搜索记录。在工具栏搜索框输入关键词，回车即可在 Homebrew 中搜索。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.enumerated()), id: \.element) { index, recent in
                        recentSearchRow(recent)
                        if index < recents.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private var clearRecentSearchesButton: some View {
        Button("清除") {
            appState.settings.clearRecentSearches()
        }
        .buttonStyle(.plain)
        .font(AppTheme.caption())
        .foregroundStyle(AppTheme.text2)
        .help("清除最近搜索（只存在本机）")
        .accessibilityLabel("清除最近搜索")
    }

    private func recentSearchRow(_ recent: String) -> some View {
        Button {
            // 只写 query，交给统一的防抖搜索；避免一次点击触发两次 brew search。
            appState.discover.query = recent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.text3)
                Text(recent)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("再次搜索“\(recent)”")
        .accessibilityLabel("再次搜索 \(recent)")
    }

    // MARK: Searching skeleton

    private var searchingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppTheme.text3.opacity(0.20))
                            .frame(width: index.isMultiple(of: 2) ? 128 : 96, height: 11)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppTheme.text3.opacity(0.12))
                            .frame(width: 220, height: 9)
                    }
                    Spacer(minLength: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.text3.opacity(0.12))
                        .frame(width: 48, height: 9)
                }
                .padding(.horizontal, 12)
                .frame(height: 52)

                if index < 4 {
                    Hairline()
                }
            }
        }
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在搜索 \(query)")
    }

    // MARK: No results

    private var noResultsState: some View {
        VStack(spacing: 8) {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "没有找到匹配的包",
                message: "换个关键词试试，或检查网络连接；离线时只能搜索本地缓存。"
            )
            HStack(spacing: 8) {
                if !query.isEmpty {
                    Button("清除关键词") {
                        appState.discover.query = ""
                    }
                    .glassSecondaryButton()
                }
                Button("重试搜索") {
                    appState.searchDiscover(forceRefresh: true)
                }
                .glassPrimaryButton()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            resultsCard

            HStack {
                Spacer()
                Text("↑↓ 选择 · ↵ 打开或安装")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .accessibilityHidden(true)
            }
        }
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                DiscoverRowView(result: result, isSelected: index == selectedIndex)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = index
                        resultsFocused = true
                    }
                if result.id != results.last?.id {
                    Hairline().padding(.leading, 12)
                }
            }
        }
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        // D-22：↑↓ 在结果间移动，↵ 打开详情 / 安装；焦点离开时清除高亮。
        .focusable()
        .focused($resultsFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(1) }
        .onKeyPress(.upArrow) { moveSelection(-1) }
        .onKeyPress(.return) { activateSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("搜索结果")
    }

    // MARK: - Interaction

    private func scheduleSearch() {
        // Debounce to avoid spawning a brew process per keystroke; the newest
        // call cancels both the pending debounce and any in-flight search.
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            appState.searchDiscover()
        }
    }

    private func moveSelection(_ delta: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .ignored }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
        return .handled
    }

    private func activateSelection() -> KeyPress.Result {
        guard results.indices.contains(selectedIndex) else { return .ignored }
        activate(results[selectedIndex])
        return .handled
    }

    private func activate(_ result: BrewSearchResult) {
        if appState.isInstalled(result) {
            if let package = appState.index.package(named: result.name, kind: result.kind) {
                appState.selectPackage(package)
            }
        } else {
            // formula 直接入队；cask 由 requestInstall 换成安装确认弹层。
            appState.requestInstall(name: result.name, kind: result.kind)
        }
    }
}

// MARK: - Row

/// 发现结果行：内容层实底（规范 §1.2：列表行不用玻璃）。
struct DiscoverRowView: View {
    @Environment(AppState.self) private var appState
    var result: BrewSearchResult
    var isSelected = false

    private var installedPackage: PackageSnapshot? {
        appState.index.package(named: result.name, kind: result.kind)
    }

    private var isInstalled: Bool { installedPackage != nil }

    /// D-17：同一包的排队中/运行中任务必须行内可见，按钮也要禁用，
    /// 否则用户会反复点击并收到「已有任务在运行」的 toast。
    private var activeTask: TaskRecord? {
        appState.activeTask(for: result.name, kind: result.kind)
    }

    private var summaryText: String {
        result.summary.isEmpty ? "暂无描述" : result.summary
    }

    /// 规范 §7：行朗读「包名，类型，已安装/未安装，描述，版本」。
    private var accessibilityText: String {
        var parts = [result.name, result.kind.rawValue, isInstalled ? "已安装" : "未安装"]
        if let version = installedPackage?.displayVersion {
            parts.append("版本 \(version)")
        }
        if !result.summary.isEmpty {
            parts.append(result.summary)
        }
        return parts.joined(separator: "，")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(AppTheme.headline())
                        .foregroundStyle(AppTheme.text1)
                        .lineLimit(1)
                    KindBadge(kind: result.kind)
                    if isInstalled {
                        Badge(text: "已安装", color: AppTheme.success, systemImage: "checkmark")
                    }
                }
                Text(summaryText)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)

            Spacer(minLength: 8)

            // 远端搜索结果没有版本字段；只有已安装的包能从索引拿到版本，
            // 拿不到就不编造，整个版本列省略。
            if let version = installedPackage?.displayVersion {
                Text(version)
                    .font(AppTheme.mono(11))
                    .foregroundStyle(AppTheme.text2)
                    .lineLimit(1)
            }

            trailingAction
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(isSelected ? AppTheme.accentSoft : Color.clear)
        // 文字块合并朗读，详情/安装按钮保持可单独聚焦。
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if let activeTask {
            // 同一包也可能在升级/重装；标题里没有「安装」时用「处理中」，
            // 避免把升级任务误标成「安装中」。
            let verb = activeTask.title.contains("安装") ? "安装" : "处理"
            let stateText = activeTask.status == .running ? "\(verb)中" : "排队中"
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(stateText)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(result.name) \(stateText)")
        } else if isInstalled {
            Button("详情") {
                if let installedPackage {
                    appState.selectPackage(installedPackage)
                }
            }
            .glassSecondaryButton()
            .accessibilityLabel("查看 \(result.name) 详情")
        } else {
            Button("安装") {
                appState.requestInstall(name: result.name, kind: result.kind)
            }
            // 列表行内操作是次要动作，用玻璃按钮；页头/空态才用主操作。
            .glassSecondaryButton()
            .disabled(appState.isReadOnly)
            .help(appState.isReadOnly ? "只读模式：当前 Homebrew 版本低于支持范围，安装已禁用。" : "安装 \(result.name)")
            .accessibilityLabel("安装 \(result.name)，\(result.kind.rawValue)")
        }
    }
}
