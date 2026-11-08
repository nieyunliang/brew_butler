import SwiftUI

@main
struct MyApp: App {
    /// P0-10：退出守卫。NSApplicationDelegate 由 AppKit 在启动时创建，
    /// 但 AppState 由本 App 持有，需要从视图层注入（见下方两处 onAppear）。
    @NSApplicationDelegateAdaptor(QuitGuard.self) private var quitGuard
    @State private var settings: SettingsStore
    @State private var tasks: TaskQueueStore
    @State private var appState: AppState

    init() {
        let settings = SettingsStore()
        let tasks = TaskQueueStore()
        let appState = AppState(settings: settings, tasks: tasks)
        _settings = State(initialValue: settings)
        _tasks = State(initialValue: tasks)
        _appState = State(initialValue: appState)
        // §4.8：任务完成通知的点击路由（只在 App 不在前台时会有通知）。
        NotificationRouter.install(appState: appState)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(settings.appearance.colorScheme)
                .frame(minWidth: 980, idealWidth: 1280, minHeight: 640, idealHeight: 820)
                .task {
                    await appState.bootstrap()
                }
                .onAppear { quitGuard.appState = appState }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appState: appState)
        }

        // 规范 §3.2 / §4.11：设置回到系统 Settings 窗口（⌘, 由系统提供），
        // SettingsView 内部使用原生 TabView 六个 tab。
        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(settings.appearance.colorScheme)
                .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
        }

        MenuBarExtra(
            isInserted: Binding(
                get: { settings.showMenuBarExtra },
                set: { settings.showMenuBarExtra = $0 }
            )
        ) {
            MenuBarView()
                .environment(appState)
                // E-16：菜单栏弹层是独立窗口，不继承主窗口的 colorScheme。
                .preferredColorScheme(settings.appearance.colorScheme)
                // 菜单栏冷启动（窗口未出现）时也要注入，否则退出守卫拿不到状态。
                .onAppear { quitGuard.appState = appState }
        } label: {
            // E-04：有更新时在菜单栏图标旁显示数量，与仪表盘/更新页同源。
            let updateCount = appState.index.outdated.count
            HStack(spacing: 3) {
                Image(systemName: "mug")
                if updateCount > 0 {
                    Text("\(updateCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(updateCount > 0 ? "Brewbutler，\(updateCount) 个可更新" : "Brewbutler")
        }
        .menuBarExtraStyle(.window)
    }
}

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandMenu("导航") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                // E-09：快捷键由 keyboardShortcut 自动渲染，标题里不再手写「⌘N」。
                Button(section.title) {
                    appState.openSection(section)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            // 规范 §3.4：⌘[ 返回二级视图（包详情 / 发现结果页）。
            Button("返回") {
                appState.navigateBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!appState.canNavigateBack)

            // 规范 §3.4 / §3.3：⌘F 聚焦工具栏搜索；⌘K 命令面板。
            Button("搜索…") {
                appState.focusToolbarSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            // E-19：面板已开时再按 ⌘K 应关闭，而不是保持打开。
            Button(appState.showCommandPalette ? "关闭命令面板" : "命令面板") {
                appState.showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("操作") {
            // O-01：⌘R 先同步 Homebrew 索引（变更队列），完成后自动只读检查。
            Button("检查更新") {
                Task { await appState.checkUpdates() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("运行安全扫描") { appState.scanVulnerabilities() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(appState.isScanning)

            Button("运行 brew doctor") {
                Task { await appState.runDoctor() }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(appState.maintenance.doctorLoading)

            Button("清理缓存…") {
                Task { await appState.previewCleanup(presentSheet: true) }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(appState.isReadOnly || appState.maintenance.cleanupLoading)

            Divider()

            Button(appState.tasks.showDrawer ? "收起任务岛" : "展开任务岛") {
                appState.tasks.showDrawer.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            // 规范 §3.4：⌘. 取消当前任务（任务岛展开时可见）。
            Button("取消当前任务") { appState.tasks.cancelCurrent() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.tasks.isRunning)
        }
    }
}
