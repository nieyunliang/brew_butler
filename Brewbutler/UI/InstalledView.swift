import SwiftUI

/// 批量卸载请求。沿用 v1 机制：弹层（Sheets.swift `BatchUninstallSheet`）负责逐包执行、
/// 跳过被依赖的包，并明确「永不删除关联文件」与 formula / cask 分组入队。
struct BatchUninstallRequest: Identifiable {
    let id = UUID()
    var packages: [PackageSnapshot]
}

/// 资料库（ui-design v2.0.2 §4.3，UX 方案 O-05 / O-06）。
///
/// 结构：hero（标题 + 计数副标题 + 唯一页头操作「导出 Brewfile」）→ 玻璃 scope 栏
/// （5 项单选）+「筛选 ⌄」玻璃菜单 + 排序 → 生效筛选的 token 行 → 实底表格卡片。
/// 筛选组合交给 `appState.libraryPackages(options:query:)`，排序在视图侧完成。
struct InstalledView: View {
    @Environment(AppState.self) private var appState

    // O-06：scope 单选；附加条件走「筛选」菜单，可与 scope 取交集。
    @State private var scope: InstalledFilter = .all
    @State private var filter = LibraryFilterSelection()
    @State private var sort: PackageSort = .name
    @State private var sortDescending = false

    @State private var selection: Set<String> = []
    @State private var cursorID: String?
    @State private var batchUninstall: BatchUninstallRequest?
    @State private var pinConfirm: PinConfirmRequest?

    /// 内容列宽度。< 900（约等于窗口 1100 − 侧边栏）时隐藏「体积 / 安装时间」，
    /// 与 §4.3「窄窗 <1100 隐藏两列」的截图口径一致。
    @State private var contentWidth: CGFloat = 0
    private let compactWidthThreshold: CGFloat = 900

    @FocusState private var tableFocused: Bool

    // MARK: - 数据

    private var filterOptions: LibraryFilterOptions {
        filter.options(scope: scope)
    }

    /// 组合筛选（scope + 筛选菜单 + 工具栏搜索词）后，按视图侧排序输出。
    private var displayedPackages: [PackageSnapshot] {
        sortPackages(appState.libraryPackages(options: filterOptions, query: appState.searchText))
    }

    private var visibleIDs: [String] { displayedPackages.map(\.id) }
    private var compactColumns: Bool { contentWidth > 0 && contentWidth < compactWidthThreshold }
    private var query: String { appState.searchText.trimmed }

    /// 「筛选」菜单的 tap 子菜单：名称来自 AppState.availableTapNames，计数按当前索引统计。
    private var tapOptions: [LibraryTapOption] {
        appState.availableTapNames.map { tap in
            LibraryTapOption(tap: tap, count: appState.index.packages.filter { $0.tap == tap }.count)
        }
    }

    private var selectedPackages: [PackageSnapshot] {
        displayedPackages.filter { selection.contains($0.id) }
    }

    private var selectedOutdatedPackages: [PackageSnapshot] { selectedPackages.filter(\.outdated) }
    private var unpinnedSelected: [PackageSnapshot] { selectedPackages.filter { !$0.pinned } }
    private var pinnedSelected: [PackageSnapshot] { selectedPackages.filter(\.pinned) }

    /// 被反向依赖的包不允许批量卸载：入口按钮直接禁用，避免打开面板后才发现全是跳过。
    private var batchRemovableTargets: [PackageSnapshot] {
        selectedPackages.filter { appState.index.dependents(of: $0.name).isEmpty }
    }

    private var batchUninstallHelp: String {
        if appState.isReadOnly { return "只读模式下不能卸载" }
        if selectedPackages.isEmpty { return "先勾选要卸载的包" }
        if batchRemovableTargets.isEmpty { return "所选包均被其他包依赖" }
        return "卸载所选包（不会删除关联文件）"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 14)

            if let note = appState.indexSourceNote {
                GlassNotice(level: .info, message: note)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 8)
            }

            controlRow
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 12)

            if filter.activeCount > 0 {
                LibraryFilterTokenRow(selection: $filter)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 8)
            }

            tableCard
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
        // 多选浮动操作栏：内容为空时 safeAreaBar 不占位；任务岛在外层，页面 bar 叠在它上方。
        .safeAreaBar(edge: .bottom) {
            if !selection.isEmpty {
                batchBar
                    .padding(.bottom, 8)
            }
        }
        .sheet(item: $batchUninstall) { request in
            BatchUninstallSheet(packages: request.packages)
        }
        .sheet(item: $pinConfirm) { request in
            PinConfirmSheet(request: request)
        }
        .onAppear { consumePendingScope() }
        .onChange(of: appState.pendingLibraryScope) { _, _ in
            consumePendingScope()
        }
        .onChange(of: visibleIDs) { _, ids in
            // 选择集跟随当前可见集合：不可见的包不能继续参与批量执行。
            let visible = Set(ids)
            if !selection.isSubset(of: visible) {
                selection.formIntersection(visible)
            }
            if let cursorID, !visible.contains(cursorID) {
                self.cursorID = ids.first
            }
        }
        .onChange(of: appState.index.casks.count) { _, count in
            // cask 数为 0 时 scope 栏隐藏 cask；若当前正停在 cask scope，回到「全部」。
            if count == 0, scope == .cask {
                scope = .all
            }
        }
        .background(hiddenShortcuts)
    }

    // MARK: - Hero（§4.3：页头只有「导出 Brewfile」）

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("资料库")
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                Text(heroSummary)
                    .font(AppTheme.callout())
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 12)
            Button("导出 Brewfile") { appState.exportBrewfile() }
                .glassSecondaryButton()
                .help("把已安装的 formula、cask 与 tap 导出为 Brewfile")
        }
    }

    private var heroSummary: String {
        "\(appState.index.packages.count) 个包 · \(appState.index.formulae.count) formula · "
            + "\(appState.index.casks.count) cask · \(appState.index.outdated.count) 个可更新"
    }

    // MARK: - Scope 栏 + 筛选菜单 + 排序

    private var controlRow: some View {
        HStack(alignment: .center, spacing: 10) {
            GlassScopeBar(options: scopeOptions, selection: scopeBinding, accessibilityLabel: "资料库范围")
            LibraryFilterMenuButton(
                selection: $filter,
                pinnedCount: appState.libraryScopeCount(.pinned),
                manualCount: appState.libraryScopeCount(.manual),
                kegOnlyCount: appState.libraryScopeCount(.kegOnly),
                taps: tapOptions
            )
            Spacer(minLength: 12)
            sortMenu
        }
    }

    /// 5 项单选：全部 / formula / cask / 可更新 / 有已知漏洞；无 cask 时隐藏 cask，
    /// 未扫描时「有已知漏洞」禁用并提示「尚未扫描」。
    private var scopeOptions: [GlassScopeOption] {
        var options: [GlassScopeOption] = [
            GlassScopeOption(
                id: InstalledFilter.all.rawValue,
                title: "全部",
                count: appState.libraryScopeCount(.all)
            ),
            GlassScopeOption(
                id: InstalledFilter.formula.rawValue,
                title: "formula",
                count: appState.libraryScopeCount(.formula)
            )
        ]
        let caskCount = appState.libraryScopeCount(.cask)
        if caskCount > 0 {
            options.append(
                GlassScopeOption(id: InstalledFilter.cask.rawValue, title: "cask", count: caskCount)
            )
        }
        options.append(
            GlassScopeOption(
                id: InstalledFilter.outdated.rawValue,
                title: "可更新",
                count: appState.libraryScopeCount(.outdated)
            )
        )
        let scanned = appState.vulnReport != nil
        options.append(
            GlassScopeOption(
                id: InstalledFilter.vulnerable.rawValue,
                title: "有已知漏洞",
                count: appState.libraryScopeCount(.vulnerable),
                isEnabled: scanned,
                help: scanned ? nil : "尚未扫描"
            )
        )
        return options
    }

    /// GlassScopeBar 用字符串回写选中项，这里与 InstalledFilter 互转。
    private var scopeBinding: Binding<String> {
        Binding(
            get: { scope.rawValue },
            set: { scope = InstalledFilter(rawValue: $0) ?? .all }
        )
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PackageSort.allCases) { option in
                Button {
                    applySort(option)
                } label: {
                    if sort == option {
                        Label(sortTitle(option), systemImage: "checkmark")
                    } else {
                        Text(sortTitle(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("排序：\(sortTitle(sort))")
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(AppTheme.callout(12))
            .foregroundStyle(AppTheme.text3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("排序：\(sortTitle(sort))（\(sortDescending ? "降序" : "升序")）；点列头可切换方向")
        .accessibilityLabel("排序方式")
        .accessibilityValue("\(sortTitle(sort))，\(sortDescending ? "降序" : "升序")")
    }

    // MARK: - 表格卡片（内容层实底，不上玻璃）
    //
    // 这里用自定义行代替系统 `Table`（为了 mockup 的复选框列 / 行内多徽章 / hover ⋯），
    // 因此手工补齐了系统 Table 的行为，以下四项是验收项：
    // 1. ⌘A 全选当前可见包（hiddenShortcuts，列表聚焦时生效）；
    // 2. 空格切换「键盘光标行」的批量选中；
    // 3. ↑/↓ 移动键盘光标、↵ 打开详情（鼠标双击同效）；
    // 4. VoiceOver 行朗读「包名，类型，已安装版本，状态（可更新到 X / 已是最新），
    //    有已知漏洞 + 严重度，已锁定，keg-only」，并暴露「打开详情」默认动作。

    private var tableCard: some View {
        VStack(spacing: 0) {
            tableHeader
            Hairline()

            if displayedPackages.isEmpty {
                emptyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedPackages) { package in
                                LibraryPackageRow(
                                    package: package,
                                    isSelected: selection.contains(package.id),
                                    isCursor: cursorID == package.id,
                                    showsSizeAndTime: !compactColumns,
                                    diskUsageText: diskUsageText(for: package),
                                    diskUsageHelp: diskUsageHelp(for: package),
                                    isReadOnly: appState.isReadOnly,
                                    dependentsCount: appState.index.dependents(of: package.name).count,
                                    onToggleSelection: {
                                        cursorID = package.id
                                        tableFocused = true
                                        toggleSelection(package)
                                    },
                                    onSelect: {
                                        cursorID = package.id
                                        tableFocused = true
                                    },
                                    onOpen: {
                                        cursorID = package.id
                                        tableFocused = true
                                        appState.selectPackage(package)
                                    },
                                    onUpgrade: { appState.upgrade(package: package) },
                                    onTogglePin: { requestPin([package], pinned: !package.pinned) },
                                    onRevealInFinder: {
                                        Task { await appState.revealPackageInstallPath(package) }
                                    },
                                    onUninstall: { appState.requestUninstall(package) },
                                    onCopyCommand: { copyCommand($0) }
                                )
                                .id(package.id)
                                .contextMenu { rowContextMenu(package) }
                                Hairline().padding(.leading, 37)
                            }
                        }
                    }
                    .focusable()
                    .focused($tableFocused)
                    .onKeyPress(.upArrow) {
                        moveCursor(-1, proxy: proxy)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveCursor(1, proxy: proxy)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        openCursorPackage()
                        return .handled
                    }
                    .onKeyPress(.space) {
                        toggleCursorSelection()
                        return .handled
                    }
                    .accessibilityLabel("资料库包列表")
                    .accessibilityHint("用上下方向键移动，回车打开详情，空格勾选")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            AppTheme.raised,
            in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 16, height: 1)
            sortHeader("包", option: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("类型")
                .frame(width: 76, alignment: .leading)
            Text("已安装")
                .frame(width: 96, alignment: .trailing)
            sortHeader("最新", option: .status, width: 96, alignment: .trailing)
            if !compactColumns {
                sizeColumnHeader
                sortHeader("安装时间", option: .installedAt, width: 100, alignment: .trailing)
            }
            // 与行尾「⋯」菜单同宽，保证列对齐。
            Color.clear.frame(width: 22, height: 1)
        }
        .font(AppTheme.caption())
        .captionTracking()
        .foregroundStyle(AppTheme.text3)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .accessibilityAddTraits(.isHeader)
    }

    private func sortHeader(
        _ title: String,
        option: PackageSort,
        width: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        Button {
            applySort(option)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort == option {
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sort == option ? AppTheme.text1 : AppTheme.text3)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sort == option ? "再点一次切换升降序" : "按\(title)排序")
        .accessibilityLabel("按\(title)排序")
        .accessibilityValue(sort == option ? (sortDescending ? "降序" : "升序") : "")
        .accessibilityAddTraits(sort == option ? .isSelected : [])
    }

    /// 体积列三态：未计算 → 列头给「计算体积」入口；计算中 → 列头显示 done/total；
    /// 完成后列头才变成可排序的表头。
    @ViewBuilder
    private var sizeColumnHeader: some View {
        switch appState.packageDiskUsageState {
        case .idle:
            Button("计算体积") { appState.computePackageDiskUsage() }
                .buttonStyle(.plain)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 92, alignment: .trailing)
                .disabled(appState.index.packages.isEmpty)
                .help("后台串行计算每个包的磁盘占用，可能需要一会儿")
                .accessibilityLabel("计算体积")
        case .computing(let done, let total):
            Text("计算中 \(done)/\(total)")
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)
                .help("正在计算体积，已完成 \(done) 个，共 \(total) 个")
                .accessibilityLabel("正在计算体积，已完成 \(done) 个，共 \(total) 个")
        case .finished:
            sortHeader("体积", option: .size, width: 92, alignment: .trailing)
        }
    }

    // MARK: - 空态

    @ViewBuilder
    private var emptyContent: some View {
        if appState.index.packages.isEmpty {
            ContentUnavailableView {
                Label("还没有已安装的包", systemImage: "shippingbox")
            } description: {
                Text("索引加载完成后会列出本机通过 Homebrew 安装的包。")
            } actions: {
                Button("检查更新") {
                    Task { await appState.checkUpdates() }
                }
                .glassSecondaryButton()
            }
        } else {
            ContentUnavailableView {
                Label("没有匹配的包", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("试试更换关键词或筛选条件。")
            } actions: {
                HStack(spacing: 8) {
                    Button("清除筛选") { clearFilters() }
                        .glassSecondaryButton()
                    Button(discoverButtonTitle) { openDiscoverSearch() }
                        .glassSecondaryButton()
                }
            }
        }
    }

    private var discoverButtonTitle: String {
        query.isEmpty ? "在 Homebrew 中搜索" : "在 Homebrew 中搜索 “\(query)”"
    }

    // MARK: - 浮动操作栏（§5 FloatingActionBar：计数 + 1 主操作 + 次操作）

    private var batchBar: some View {
        FloatingActionBar(
            selectionCount: selection.count,
            accessibilityLabel: "已选 \(selection.count) 个包的操作栏"
        ) {
            Button("更新") {
                // 与更新页同一入口：进 BatchUpdateSheet 确认；非 outdated 的包由计划过滤，
                // 空计划由 AppState 现有 toast 说明原因（§4.10）。
                appState.requestBatchUpdate(.selected(selectedPackages.map(\.id)))
                if appState.pendingBatchUpdate != nil {
                    selection.removeAll()
                }
            }
            .glassPrimaryButton()
            .disabled(appState.isReadOnly || selection.isEmpty)
            .help(
                appState.isReadOnly
                    ? "只读模式下不能更新"
                    : "更新所选的 \(selectedOutdatedPackages.count) 个可更新包；不在可更新列表中的会跳过"
            )

            Button("锁定") {
                requestPin(unpinnedSelected, pinned: true)
            }
            .glassSecondaryButton()
            .disabled(appState.isReadOnly || unpinnedSelected.isEmpty)
            .help(
                appState.isReadOnly
                    ? "只读模式下不能锁定"
                    : (unpinnedSelected.isEmpty
                        ? "所选包均已锁定"
                        : "锁定所选包；依赖新版本的包可能无法安装或运行")
            )

            if !pinnedSelected.isEmpty {
                Button("解锁") {
                    requestPin(pinnedSelected, pinned: false)
                }
                .glassSecondaryButton()
                .disabled(appState.isReadOnly)
                .help("解除所选包的锁定，重新纳入更新检查")
            }

            Button("卸载…") { requestBatchUninstall() }
                .glassSecondaryButton()
                .disabled(appState.isReadOnly || batchRemovableTargets.isEmpty)
                .help(batchUninstallHelp)

            Button("取消选择") { clearSelection() }
                .glassSecondaryButton()
        }
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func rowContextMenu(_ package: PackageSnapshot) -> some View {
        Button("打开详情") { appState.selectPackage(package) }
        if package.outdated {
            Button("更新到 \(package.stableVersion ?? "最新版本")") {
                appState.upgrade(package: package)
            }
            .disabled(package.pinned || appState.isReadOnly)
        }
        Button(package.pinned ? "解锁" : "锁定") {
            requestPin([package], pinned: !package.pinned)
        }
        .disabled(appState.isReadOnly)
        .help(pinHelp(for: package))

        Button("在 Finder 中显示") {
            // 路径由 AppState 解析（brew 记录的真实安装路径，失败只 toast 不猜路径）。
            Task { await appState.revealPackageInstallPath(package) }
        }

        Divider()
        Button("复制安装命令") { copyCommand(package.installCommand) }
        Button("复制卸载命令") { copyCommand(package.uninstallCommand) }

        Divider()
        let dependents = appState.index.dependents(of: package.name)
        Button(dependents.isEmpty ? "卸载…" : "卸载…（被 \(dependents.count) 个包依赖）") {
            appState.requestUninstall(package)
        }
        .disabled(!dependents.isEmpty || appState.isReadOnly)
        .help(
            dependents.isEmpty
                ? "删除该包（不会删除关联文件；不可恢复）"
                : "有 \(dependents.count) 个包依赖它，需先处理依赖方"
        )
    }

    // MARK: - 快捷操作

    private func toggleSelection(_ package: PackageSnapshot) {
        if selection.contains(package.id) {
            selection.remove(package.id)
        } else {
            selection.insert(package.id)
        }
    }

    private func clearSelection() {
        selection.removeAll()
    }

    private func selectAllVisible() {
        selection = Set(displayedPackages.map(\.id))
    }

    private func clearFilters() {
        scope = .all
        filter.clear()
        appState.searchText = ""
    }

    private func requestPin(_ packages: [PackageSnapshot], pinned: Bool) {
        guard !packages.isEmpty else { return }
        pinConfirm = PinConfirmRequest(packages: packages, pinned: pinned)
    }

    private func pinHelp(for package: PackageSnapshot) -> String {
        if package.pinned { return "解除锁定后重新纳入更新" }
        if package.kind == .cask, package.autoUpdates == true {
            return "锁定后更新会跳过该 cask；它启用了自动更新，可能绕过 Homebrew 自行更新"
        }
        return "锁定后更新会跳过该包"
    }

    private func requestBatchUninstall() {
        guard !batchRemovableTargets.isEmpty else {
            appState.showToast(batchUninstallHelp, kind: .info)
            return
        }
        batchUninstall = BatchUninstallRequest(packages: selectedPackages)
    }

    private func copyCommand(_ command: String) {
        copyToPasteboard(command)
        appState.showToast("已复制命令", kind: .success)
    }

    /// 空态跳到发现页并带上当前关键词与类型筛选，避免用户再手抄一遍。
    private func openDiscoverSearch() {
        let kind: PackageSnapshot.Kind?
        switch scope {
        case .formula: kind = .formula
        case .cask: kind = .cask
        default: kind = nil
        }
        if query.isEmpty {
            appState.openDiscover(kind: kind, search: false)
        } else {
            appState.openDiscover(query: query, kind: kind, search: true)
        }
    }

    /// 概览页指标环通过 `appState.openLibrary(scope:)` 请求资料库 scope（跨页约定）。
    /// 消费后立即清空，避免下次进入资料库又被同一个请求覆盖；不在 scope 栏的条件忽略。
    private func consumePendingScope() {
        guard let requested = appState.pendingLibraryScope else { return }
        appState.pendingLibraryScope = nil
        switch requested {
        case .all, .formula, .cask, .outdated, .vulnerable:
            scope = requested
            filter.clear()
            cursorID = nil
        case .pinned, .manual, .kegOnly:
            break
        }
    }

    // MARK: - 快捷键（⌘F 由工具栏搜索承担，这里只保留列表内快捷键）

    private var hiddenShortcuts: some View {
        Group {
            Button("") { selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(!tableFocused)
            Button("") { requestBatchUninstall() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!tableFocused)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - 键盘导航

    private func moveCursor(_ delta: Int, proxy: ScrollViewProxy) {
        guard !displayedPackages.isEmpty else { return }
        let current = cursorID.flatMap { id in displayedPackages.firstIndex { $0.id == id } }
        let next: Int
        if let current {
            next = min(max(current + delta, 0), displayedPackages.count - 1)
        } else {
            next = delta > 0 ? 0 : displayedPackages.count - 1
        }
        let package = displayedPackages[next]
        cursorID = package.id
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(package.id, anchor: .center)
        }
    }

    private func openCursorPackage() {
        guard let package = displayedPackages.first(where: { $0.id == cursorID }) else { return }
        appState.selectPackage(package)
    }

    private func toggleCursorSelection() {
        guard let package = displayedPackages.first(where: { $0.id == cursorID }) else { return }
        toggleSelection(package)
    }

    // MARK: - 排序（视图侧）

    private func applySort(_ option: PackageSort) {
        if sort == option {
            sortDescending.toggle()
        } else {
            sort = option
            sortDescending = option != .name
        }
    }

    private func sortTitle(_ option: PackageSort) -> String {
        switch option {
        case .name: return "名称"
        case .size: return "体积"
        case .installedAt: return "安装时间"
        case .status: return "状态"
        }
    }

    private func sortPackages(_ list: [PackageSnapshot]) -> [PackageSnapshot] {
        switch sort {
        case .name:
            return list.sorted { lhs, rhs in
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if order == .orderedSame { return lhs.id < rhs.id }
                return sortDescending ? order == .orderedDescending : order == .orderedAscending
            }
        case .size:
            return list.sorted { lhs, rhs in
                let left = diskUsageBytes(for: lhs)
                let right = diskUsageBytes(for: rhs)
                switch (left, right) {
                case let (l?, r?):
                    if l == r { return nameTieBreak(lhs, rhs) }
                    return sortDescending ? l > r : l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return nameTieBreak(lhs, rhs)
                }
            }
        case .installedAt:
            return list.sorted { lhs, rhs in
                switch (lhs.installedAt, rhs.installedAt) {
                case let (l?, r?):
                    if l == r { return nameTieBreak(lhs, rhs) }
                    return sortDescending ? l > r : l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return nameTieBreak(lhs, rhs)
                }
            }
        case .status:
            return list.sorted { lhs, rhs in
                let left = statusRank(lhs)
                let right = statusRank(rhs)
                if left == right { return nameTieBreak(lhs, rhs) }
                return sortDescending ? left > right : left < right
            }
        }
    }

    /// 状态序：可更新 > 有已知漏洞 > 已是最新；默认降序即「最需要处理的在前」。
    private func statusRank(_ package: PackageSnapshot) -> Int {
        if package.outdated { return 2 }
        if package.hasVulnerability { return 1 }
        return 0
    }

    private func nameTieBreak(_ lhs: PackageSnapshot, _ rhs: PackageSnapshot) -> Bool {
        let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if order == .orderedSame { return lhs.id < rhs.id }
        return order == .orderedAscending
    }

    // MARK: - 逐包体积（§4.3：三态 + 首次「计算体积」）

    private enum DiskUsageDisplay {
        case value(Int64)
        case computing
        case unavailable
    }

    /// 逐包体积：优先 AppState 的后台逐包结果，退回快照里已有的值。
    private func diskUsageBytes(for package: PackageSnapshot) -> Int64? {
        appState.diskUsage(for: package) ?? package.diskUsageBytes
    }

    private func diskUsageDisplay(for package: PackageSnapshot) -> DiskUsageDisplay {
        if let bytes = diskUsageBytes(for: package) { return .value(bytes) }
        switch appState.packageDiskUsageState {
        case .computing:
            return .computing
        case .idle, .finished:
            return .unavailable
        }
    }

    private func diskUsageText(for package: PackageSnapshot) -> String {
        switch diskUsageDisplay(for: package) {
        case .value(let bytes):
            return bytes.byteCountText
        case .computing:
            return "计算中"
        case .unavailable:
            return "—"
        }
    }

    private func diskUsageHelp(for package: PackageSnapshot) -> String {
        switch diskUsageDisplay(for: package) {
        case .value:
            return "体积来自 brew 路径的磁盘占用（du）"
        case .computing:
            return "正在后台计算该包体积…"
        case .unavailable:
            if appState.packageDiskUsageState == .idle {
                return "体积尚未计算；点列头「计算体积」开始计算"
            }
            return "不可计算：没有权限或路径不存在；打开详情可重试"
        }
    }

}

// MARK: - 表格行（内容层实底）

private struct LibraryPackageRow: View {
    /// 资料库行是单行内容（无第二行说明），比 v1 的 46pt 双行行高更紧凑，
    /// 对齐 §2.3「单行 24 / 双行 40」与 v2 截图的密度；4pt 栅格取 36。
    private let libraryRowHeight: CGFloat = 36

    var package: PackageSnapshot
    var isSelected: Bool
    var isCursor: Bool
    /// 窄窗时隐藏「体积 / 安装时间」，与表头保持一致。
    var showsSizeAndTime: Bool
    var diskUsageText: String
    var diskUsageHelp: String
    var isReadOnly: Bool
    var dependentsCount: Int
    var onToggleSelection: () -> Void
    /// 单击行：只移动键盘光标（不改变多选）；双击 / ↵ 才进详情（§4.3）。
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onUpgrade: () -> Void
    var onTogglePin: () -> Void
    var onRevealInFinder: () -> Void
    var onUninstall: () -> Void
    var onCopyCommand: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.text3)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择 \(package.displayName)")
            .accessibilityValue(isSelected ? "已选中" : "未选中")
            .accessibilityHint("加入或移出批量操作选择")

            rowContent

            rowMenu
        }
        .padding(.horizontal, 14)
        .frame(height: libraryRowHeight)
        .background(rowBackground)
        .overlay {
            // 键盘光标：2pt accent 描边，与勾选底色区分开。
            if isCursor {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
                    .padding(.horizontal, 1)
            }
        }
        .onHover { isHovering = $0 }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            nameCell
            KindBadge(kind: package.kind)
                .frame(width: 76, alignment: .leading)
            Text(package.installedVersion ?? "—")
                .font(AppTheme.mono())
                .foregroundStyle(AppTheme.text2)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
            latestCell
                .frame(width: 96, alignment: .trailing)
            if showsSizeAndTime {
                Text(diskUsageText)
                    .font(AppTheme.mono())
                    .foregroundStyle(diskUsageText == "—" ? AppTheme.text3 : AppTheme.text2)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
                    .help(diskUsageHelp)
                Text(installedAtText)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("按下回车打开详情")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var nameCell: some View {
        HStack(spacing: 6) {
            Text(package.displayName)
                .font(AppTheme.headline())
                .foregroundStyle(AppTheme.text1)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            badges
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 状态徽章：符号 + 文字 + 颜色，不只靠颜色（§7）。状态词固定（§6）。
    private var badges: some View {
        HStack(spacing: 5) {
            if package.pinned {
                Badge(text: "已锁定", color: AppTheme.text2, systemImage: "pin.fill")
            }
            if let severity = package.vulnerabilitySeverity {
                Badge(
                    text: "有已知漏洞",
                    color: AppTheme.severity(severity),
                    background: AppTheme.severitySoft(severity),
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            if package.kegOnly {
                Badge(text: "keg-only", color: AppTheme.text3)
            }
            if package.isDeprecatedOrDisabled {
                Badge(text: "已废弃", color: AppTheme.danger)
            }
        }
    }

    @ViewBuilder
    private var latestCell: some View {
        if package.outdated, let stable = package.stableVersion {
            Text(stable)
                .font(AppTheme.mono(11.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        } else if package.outdated {
            // outdated 为真但 stableVersion 缺失时不能显示「已是最新」。
            Text("版本未知")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.warning)
        } else {
            Text("已是最新")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text3)
        }
    }

    private var installedAtText: String {
        guard let installedAt = package.installedAt else { return "—" }
        return installedAt.formatted(.dateTime.month(.defaultDigits).day())
    }

    /// 行尾常显菜单：与右键菜单共用动作，鼠标与键盘都可达。
    private var rowMenu: some View {
        Menu {
            Button("打开详情") { onOpen() }
            if package.outdated {
                Button("更新到 \(package.stableVersion ?? "最新版本")") { onUpgrade() }
                    .disabled(package.pinned || isReadOnly)
            }
            Button(package.pinned ? "解锁" : "锁定") { onTogglePin() }
                .disabled(isReadOnly)
            Button("在 Finder 中显示") { onRevealInFinder() }
            Divider()
            Button("复制安装命令") { onCopyCommand(package.installCommand) }
            Button("复制卸载命令") { onCopyCommand(package.uninstallCommand) }
            Divider()
            Button(dependentsCount == 0 ? "卸载…" : "卸载…（被 \(dependentsCount) 个包依赖）") {
                onUninstall()
            }
            .disabled(isReadOnly || dependentsCount > 0)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.text3)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .opacity(isHovering || isCursor ? 1 : 0)
        .help("更新、锁定、复制命令或卸载")
        .accessibilityLabel("对 \(package.displayName) 的操作")
    }

    private var rowBackground: Color {
        if isCursor { return AppTheme.accentSoft }
        if isSelected { return AppTheme.accentSoft.opacity(0.5) }
        if isHovering { return AppTheme.surface3.opacity(0.5) }
        return .clear
    }

    /// 行朗读：包名 / 类型 / 状态（§7）。
    private var accessibilityText: String {
        var parts = [package.displayName, package.kind.rawValue, "已安装 \(package.installedVersion ?? "未知版本")"]
        if package.outdated {
            parts.append(package.stableVersion.map { "可更新到 \($0)" } ?? "有可更新版本，但版本未知")
        } else {
            parts.append("已是最新")
        }
        if let severity = package.vulnerabilitySeverity {
            parts.append("有已知漏洞，\(severity.label)")
        }
        if package.pinned { parts.append("已锁定") }
        if package.kegOnly { parts.append("keg-only") }
        return parts.joined(separator: "，")
    }
}
