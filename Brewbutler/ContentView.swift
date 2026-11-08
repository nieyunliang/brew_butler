import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    /// A-06 横幅只在本次会话内可被关闭，不写进设置。
    @State private var capabilityNoticeDismissed = false
    /// P1-2：当前真正呈现的外壳弹层 id；关闭时据此只清对应来源。
    @State private var presentedShellSheetID: String?
    /// 规范 §3.3：工具栏搜索（⌘F）。
    @FocusState private var searchFocused: Bool
    /// 任务岛实测高度：用 overlay 定位 + 等高的底部 safeAreaInset，
    /// 让页面内容精确让位（safeAreaBar 在多栏 + 展开面板下会把面板顶出窗口）。
    @State private var islandHeight: CGFloat = 0

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.canvas)
                .navigationTitle(appState.windowTitle)
                // 规范 §3.3：工具栏搜索（⌘F）。回车进入发现结果页。
                .searchable(text: $state.searchText, placement: .toolbar, prompt: "搜索包或命令…")
                .searchFocused($searchFocused)
                .searchSuggestions { searchSuggestions }
                .onSubmit(of: .search) { submitSearch() }
                .onChange(of: appState.searchFocusRequest) { _, _ in
                    searchFocused = true
                }
                .toolbar { toolbarContent }
                // 规范 §4.8：任务岛取代 v1 的日志抽屉 + toast + 状态栏，
                // 用 safeAreaBar 让页面内容自动让位（不再手写 padding）。
                // 任务岛：overlay 贴内容列底部，同时用等高的 safeAreaInset 让页面内容让位。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: islandHeight)
                }
                .overlay(alignment: .bottom) {
                    TaskIslandView()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if abs(height - islandHeight) > 0.5 { islandHeight = height }
                        }
                }
                // O-05：v1 → v2 快捷键调整的一次性提示（只出现一次）。浮在内容层上方，
                // 不挤压页面布局；顶部留出玻璃工具栏高度。
                .overlay(alignment: .top) {
                    if appState.shouldShowShortcutTip {
                        GlassNotice(
                            level: .info,
                            title: "快捷键已调整",
                            message: "⌘2 现在是更新，⌘3 是资料库。按 ⌘K 可打开命令面板查看全部快捷键。",
                            actionTitle: "知道了",
                            action: { appState.dismissShortcutTip() },
                            onDismiss: { appState.dismissShortcutTip() }
                        )
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 24)
                        .padding(.top, 56)
                    }
                }
        }
        .overlay {
            if appState.showCommandPalette {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.showCommandPalette)
        // E-17：所有弹层收敛到一个 `.sheet(item:)`。此前 9 个 sheet 修饰符各自
        // 监听一个状态，两个状态同时非空时 SwiftUI 只呈现一个、另一个悄悄残留，
        // 关掉当前弹层后又会立刻弹出。现在同一时刻只可能有一个「外壳弹层」。
        .sheet(item: shellSheet) { sheet in
            Group {
                switch sheet {
                case .onboarding:
                    OnboardingView()
                case .uninstall(let package):
                    UninstallSheet(package: package)
                case .install(let target):
                    InstallConfirmSheet(target: target)
                case .cleanup(let request):
                    CleanupSheet(request: request)
                case .autoremove(let request):
                    AutoremoveSheet(request: request)
                case .reinstall(let package):
                    ReinstallSheet(package: package)
                case .retry(let record):
                    RetryConfirmSheet(record: record)
                case .batchUpdate(let plan):
                    BatchUpdateSheet(plan: plan)
                case .brewfile(let url):
                    BrewfileImportSheet(url: url)
                }
            }
            // 规范 §9：弹层按内容自适应尺寸。
            .presentationSizing(.fitted)
            // 记录当前真正呈现的是哪个来源：关闭时只清这一个，不能因为
            // SwiftUI 写入 nil 就把「下一个待呈现的弹层」也清掉（P1-2）。
            .onAppear { presentedShellSheetID = sheet.id }
        }
    }

    /// E-17：弹层来源状态的唯一入口。`get` 按固定优先级取一个非空来源；
    /// P1-2：`set(nil)` 只清掉当前呈现的那个来源——后台刚产生的批次汇总
    /// 不能被别的弹层关闭动作连带吞掉，已打开的确认面板也不能被结果面板顶替。
    /// batchSummary 故意排在最后：它是异步产物，应等其他弹层关掉后再出现。
    private var shellSheet: Binding<ShellSheet?> {
        @Bindable var state = appState
        return Binding(
            get: {
                if state.showOnboarding { return .onboarding }
                if let package = state.uninstallTarget { return .uninstall(package) }
                if let target = state.installTarget { return .install(target) }
                if let request = state.cleanupRequest { return .cleanup(request) }
                if let request = state.autoremoveRequest { return .autoremove(request) }
                if let package = state.reinstallTarget { return .reinstall(package) }
                if let record = state.pendingRetry { return .retry(record) }
                if let plan = state.pendingBatchUpdate { return .batchUpdate(plan) }
                if let url = state.brewfileImportURL { return .brewfile(url) }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                // 用呈现过的那一条来源做精确清理；若 SwiftUI 在 onAppear 之前
                // 就写了 nil，退回按优先级清理当前第一条。
                let presentedID = presentedShellSheetID
                presentedShellSheetID = nil
                if let presentedID {
                    if presentedID == "onboarding" { state.dismissOnboarding() }
                    else if presentedID.hasPrefix("uninstall:") { state.uninstallTarget = nil }
                    else if presentedID.hasPrefix("install:") { state.installTarget = nil }
                    else if presentedID.hasPrefix("cleanup:") { state.cleanupRequest = nil }
                    else if presentedID.hasPrefix("autoremove:") { state.autoremoveRequest = nil }
                    else if presentedID.hasPrefix("reinstall:") { state.reinstallTarget = nil }
                    else if presentedID.hasPrefix("retry:") { state.pendingRetry = nil }
                    else if presentedID.hasPrefix("batchUpdate:") { state.pendingBatchUpdate = nil }
                    else if presentedID.hasPrefix("brewfile:") { state.brewfileImportURL = nil }
                    return
                }
                if state.showOnboarding {
                    // 走 dismissOnboarding 才会写完成标记，Esc 关闭不会下次重弹。
                    state.dismissOnboarding()
                    return
                }
                if state.uninstallTarget != nil { state.uninstallTarget = nil; return }
                if state.installTarget != nil { state.installTarget = nil; return }
                if state.cleanupRequest != nil { state.cleanupRequest = nil; return }
                if state.autoremoveRequest != nil { state.autoremoveRequest = nil; return }
                if state.reinstallTarget != nil { state.reinstallTarget = nil; return }
                if state.pendingRetry != nil { state.pendingRetry = nil; return }
                if state.pendingBatchUpdate != nil { state.pendingBatchUpdate = nil; return }
                if state.brewfileImportURL != nil { state.brewfileImportURL = nil; return }
            }
        )
    }

    @ViewBuilder
    private var detailColumn: some View {
        VStack(spacing: 0) {

            // M2 A-06：只读 / 能力降级的统一说明。之前只在个别按钮的禁用上
            // 体现，用户不知道「为什么点不动」。可关闭，只在本次会话生效。
            if !capabilityNoticeDismissed, let notice = appState.capabilityNotice {
                InlineNotice(
                    level: .warning,
                    title: "部分功能不可用",
                    message: notice,
                    actionTitle: "知道了"
                ) {
                    capabilityNoticeDismissed = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityLabel("能力降级提示：\(notice)")
            }
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        // M2 A-03：首次探测期间显示占位，而不是 0 值的仪表盘（用户会误以为
        // 本机什么都没装）。探测完成后再按是否找到 brew 分流。
        if appState.isLocatingBrew {
            BrewLocatingView()
        } else if appState.installation == nil {
            // M2 A-04：brew 缺失时不再锁死所有入口——设置窗口（⌘, / 侧边栏
            // 底部状态卡）仍可打开，用来手动指定路径或重新检测。
            BrewMissingView()
        } else if let package = appState.selectedPackage {
            PackageDetailView(package: package)
                .id(package.id)
        } else if appState.isDiscoverPresented {
            // 规范 §3.2：发现不是一级导航，而是覆盖在分区之上的搜索结果页。
            DiscoverView()
        } else {
            switch appState.section {
            case .overview: DashboardView()
            case .updates: UpdatesView()
            case .library: InstalledView()
            case .services: ServicesView()
            case .maintenance: MaintenanceView()
            }
        }
    }

    /// 规范 §3.3：工具栏搜索建议的第一行固定为「在 Homebrew 中搜索」，其余为
    /// 已安装包的直接命中；概览 / 维护页输入时只给建议（不逐页过滤）。
    @ViewBuilder
    private var searchSuggestions: some View {
        let query = appState.searchText.trimmed
        if !query.isEmpty {
            Button {
                submitSearch()
            } label: {
                Label("在 Homebrew 中搜索“\(query)”", systemImage: "magnifyingglass.circle")
            }
            .accessibilityLabel("在 Homebrew 中搜索 \(query)，打开发现结果页")

            ForEach(appState.installedSearchSuggestions(for: query)) { package in
                Button {
                    appState.selectPackage(package)
                } label: {
                    Label("\(package.displayName) · \(package.kind.label)", systemImage: package.kind == .formula ? "terminal" : "app.dashed")
                }
                .accessibilityLabel("\(package.displayName)，\(package.kind.label)，打开详情")
            }
        }
    }

    /// 规范 §3.3：工具栏搜索回车进入发现结果页；远端搜索由发现页发起。
    private func submitSearch() {
        let query = appState.searchText.trimmed
        guard !query.isEmpty else { return }
        appState.openDiscover(query: query)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 规范 §3.1：工具栏分组 ①导航（返回）②搜索（.searchable）③页面动作 ④检查器。
        ToolbarItem(placement: .navigation) {
            Button {
                appState.navigateBack()
            } label: {
                Label("返回", systemImage: "chevron.left")
            }
            .disabled(!appState.canNavigateBack)
            .help("返回 ⌘[")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.checkUpdates() }
            } label: {
                Label("检查更新", systemImage: "arrow.clockwise")
            }
            .help("检查更新 ⌘R")

            Button {
                appState.scanVulnerabilities()
            } label: {
                Label("运行安全扫描", systemImage: "checkmark.shield")
            }
            .disabled(appState.isScanning)
            .help("运行安全扫描 ⇧⌘V")

            Button {
                appState.showCommandPalette = true
            } label: {
                Label("命令面板", systemImage: "command")
            }
            .help("命令面板 ⌘K")
        }

        if appState.selectedPackage != nil {
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showInspector.toggle()
                } label: {
                    Label("检查器", systemImage: "sidebar.trailing")
                }
                .help("显示 / 隐藏检查器")
            }
        }
    }
}

// MARK: - Shell sheet

/// E-17：外壳弹层的唯一标识。视图仍由状态驱动（各 `AppState` 属性是唯一事实来源），
/// 这里只决定「当前该呈现哪一个」。
private enum ShellSheet: Identifiable {
    case onboarding
    case uninstall(PackageSnapshot)
    case install(InstallTarget)
    case cleanup(CleanupRequest)
    case autoremove(AutoremoveRequest)
    case retry(TaskRecord)
    case batchUpdate(BatchUpdatePlan)
    case brewfile(URL)
    case reinstall(PackageSnapshot)

    var id: String {
        switch self {
        case .onboarding: return "onboarding"
        case .uninstall(let package): return "uninstall:\(package.id)"
        case .install(let target): return "install:\(target.id)"
        case .cleanup(let request): return "cleanup:\(request.id.uuidString)"
        case .autoremove(let request): return "autoremove:\(request.id.uuidString)"
        case .retry(let record): return "retry:\(record.id.uuidString)"
        case .batchUpdate(let plan): return "batchUpdate:\(plan.id.uuidString)"
        case .brewfile(let url): return "brewfile:\(url.path)"
        case .reinstall(let package): return "reinstall:\(package.id)"
        }
    }
}

// MARK: - Brew locating

/// M2 A-03：首次探测 brew 时的占位。之前这里会直接渲染仪表盘，所有数字都是 0，
/// 用户看到「0 个已安装、0 个可更新」会以为数据丢失，而不是「还没检测完」。
struct BrewLocatingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在检测 Homebrew…")
                .font(AppTheme.headline())
                .foregroundStyle(AppTheme.text1)
            Text("通常在几秒内完成。检测完成后会载入本机已安装的包。")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在检测 Homebrew，请稍候")
    }
}

// MARK: - Brew missing

struct BrewMissingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var manualPath = ""

    /// 官方安装脚本（brew.sh 现行写法），只用于复制，不代执行。
    private static let installCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.warning)
            Text("找不到 Homebrew")
                .font(AppTheme.display())
                .foregroundStyle(AppTheme.text1)
            Text(appState.brewError ?? "请安装 Homebrew，或在下方指定 brew 可执行文件的路径。")
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 8) {
                TextField("例如 /opt/homebrew/bin/brew", text: $manualPath)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTheme.mono(12))
                    .frame(width: 280)
                Button("使用该路径") {
                    Task { await appState.applyBrewPath(manualPath) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(manualPath.trimmed.isEmpty)
            }

            HStack(spacing: 10) {
                Button("重新检测") {
                    Task { await appState.locateBrew(override: nil) }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("打开设置") {
                    openSettings()
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            // M2 A-05：错误页也要给出下一步，而不是只说「找不到」。不承诺自动
            // 安装、不代输管理员密码——只给官方入口和可复制的命令。
            VStack(spacing: 8) {
                Hairline().frame(maxWidth: 420)
                Text("还没有安装 Homebrew？")
                    .font(AppTheme.headline(12))
                    .foregroundStyle(AppTheme.text1)
                HStack(spacing: 8) {
                    Link("打开 brew.sh 安装说明", destination: URL(string: "https://brew.sh")!)
                        .font(AppTheme.callout())
                    Button("复制安装命令") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.installCommand, forType: .string)
                        appState.showToast("已复制 Homebrew 安装命令", kind: .success)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Text("按说明安装后，回到这里点「重新检测」。Brewbutler 不会自动安装，也不会代输管理员密码。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
