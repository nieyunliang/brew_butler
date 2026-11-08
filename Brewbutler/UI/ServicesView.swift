import SwiftUI

// MARK: - 服务（ui-design.md v2.0.2 §4.6）
//
// hero + 玻璃 notice（控制层）+ 内容层实底列表卡。服务五类动作全部二次确认、
// 默认焦点「取消」；系统级服务不代理 sudo，只给复制命令。

struct ServicesView: View {
    @Environment(AppState.self) private var appState

    private var runningCount: Int {
        appState.services.filter { $0.lifecycle == .running }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero

                GlassNotice(
                    level: .info,
                    message: "「启动 / 停止」会修改 ~/Library/LaunchAgents 中的 plist，并影响登录自启。所有操作都需要确认。"
                )

                if let error = appState.servicesError {
                    GlassNotice(
                        level: .danger,
                        title: "加载服务失败",
                        message: error,
                        actionTitle: "重试",
                        action: { Task { await appState.loadServices() } }
                    )
                }

                content
            }
            .pagePadding()
        }
        .task {
            if !appState.servicesLoaded {
                await appState.loadServices()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("服务")
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                Text(subtitle)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                Task { await appState.loadServices() }
            } label: {
                Label(appState.servicesLoading ? "刷新中…" : "刷新", systemImage: "arrow.triangle.2.circlepath")
            }
            .glassSecondaryButton()
            .disabled(appState.servicesLoading)
            .help("重新读取 brew services 列表")
        }
    }

    private var subtitle: String {
        if !appState.servicesLoaded {
            return appState.servicesLoading ? "正在读取服务列表…" : "尚未读取服务列表"
        }
        return "\(appState.services.count) 个服务 · \(runningCount) 个运行中 · 由 launchd 托管"
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if appState.servicesLoading && appState.services.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取 brew services…")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
        } else if appState.services.isEmpty {
            EmptyStateView(
                systemImage: "gearshape.2",
                title: "还没有注册任何服务",
                message: "安装带服务的 formula 后会出现在这里。"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(appState.services) { service in
                    ServiceRowView(service: service)
                    if service.id != appState.services.last?.id {
                        Hairline().padding(.leading, 16)
                    }
                }
            }
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
        }
    }
}

// MARK: - 服务行

struct ServiceRowView: View {
    @Environment(AppState.self) private var appState
    var service: BrewService

    /// 五种状态变更动作共享一个确认弹层；PRD F8 要求每个动作都二次确认。
    @State private var pendingAction: ServiceAction?

    private var isBusy: Bool {
        appState.tasks.records.contains { $0.packageName == service.name && !$0.status.isTerminal }
    }

    private var isSystemLevel: Bool {
        appState.isSystemLevelService(service)
    }

    private var logPaths: ServiceLogPaths {
        appState.serviceLogPaths(for: service)
    }

    private var isRunningLike: Bool {
        service.lifecycle == .running || service.lifecycle == .scheduled
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ServiceStatusPill(lifecycle: service.lifecycle)
                .frame(minWidth: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .font(AppTheme.headline())
                        .foregroundStyle(AppTheme.text1)
                    if isSystemLevel {
                        Badge(text: "系统级", color: AppTheme.warning, systemImage: "lock.shield")
                    }
                }
                secondaryLine
                if isSystemLevel {
                    Text("系统级服务需要在终端中执行")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.warning)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isBusy {
                ProgressView().controlSize(.small)
            } else if isSystemLevel {
                systemLevelActions
            } else {
                normalActions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingAction?.label ?? "确认", role: destructiveRole) {
                if let action = pendingAction {
                    appState.serviceAction(action, service: service)
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    /// 用户 / plist 路径；异常时优先说明上次退出码（§4.6 行结构）。
    @ViewBuilder
    private var secondaryLine: some View {
        HStack(spacing: 6) {
            if service.lifecycle == .error, let exitCode = service.exitCode {
                Text("上次退出码 \(exitCode)")
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.danger)
            }
            if let user = service.user, !user.isEmpty {
                Text("用户 \(user)")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            Text(service.file ?? "plist 路径未知")
                .font(AppTheme.mono())
                .foregroundStyle(AppTheme.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var destructiveRole: ButtonRole? {
        switch pendingAction {
        case .stop, .kill: return .destructive
        default: return nil
        }
    }

    private var confirmTitle: String {
        switch pendingAction {
        case .kill:
            return "停止进程但保留注册：\(service.name)？"
        default:
            return "\(pendingAction?.label ?? "操作")服务 \(service.name)？"
        }
    }

    private var confirmMessage: String {
        switch pendingAction {
        case .stop:
            return "停止后相关应用可能无法连接该服务；launchd 注册也会被移除，登录不再自启。"
        case .start:
            return "启动会写入 ~/Library/LaunchAgents 并注册登录自启。"
        case .restart:
            return "重启会先停止再启动该服务；期间相关应用可能无法连接。"
        case .run:
            return "仅本次前台运行该服务，不注册开机自启。"
        case .kill:
            return "只停止当前进程，保留 launchd 注册：下次登录仍会自启，可随时再次启动。与「停止」不同，「停止」会移除注册、不再自启。"
        case nil:
            return "该操作会改变服务的运行状态。"
        }
    }

    // MARK: 普通服务的操作

    @ViewBuilder
    private var normalActions: some View {
        HStack(spacing: 6) {
            if service.lifecycle == .error, logPaths.hasAny {
                Button("查看日志") { openFirstLog() }
                    .glassSecondaryButton()
                    .help("打开该服务的 StandardOutPath / StandardErrorPath 日志")
            }
            Button(isRunningLike ? "停止…" : "启动…") {
                pendingAction = isRunningLike ? .stop : .start
            }
            .glassSecondaryButton()
            .accessibilityLabel("\(isRunningLike ? "停止" : "启动")服务 \(service.name)")
            .help(isRunningLike ? "停止并移除登录自启（需确认）" : "启动并注册登录自启（需确认）")
            optionsMenu(actionsEnabled: true)
        }
    }

    // MARK: 系统级服务（不代理 sudo）

    @ViewBuilder
    private var systemLevelActions: some View {
        HStack(spacing: 6) {
            Button(isRunningLike ? "停止" : "启动") {}
                .glassSecondaryButton()
                .disabled(true)
                .help("系统级服务需要在终端中执行；Brewbutler 不代理 sudo。")
            Button("复制命令") {
                copy(appState.systemServiceCommand(for: service), toast: "已复制需要 sudo 的命令")
            }
            .glassSecondaryButton()
            .help("复制在终端中执行的等价命令；Brewbutler 不会请求管理员密码。")
            optionsMenu(actionsEnabled: false)
        }
    }

    private func optionsMenu(actionsEnabled: Bool) -> some View {
        Menu {
            Button("重启…") { pendingAction = .restart }
                .disabled(!actionsEnabled)
            Button("仅运行一次…") { pendingAction = .run }
                .disabled(!actionsEnabled)
            Button("强制结束…") { pendingAction = .kill }
                .disabled(!actionsEnabled)
            Divider()
            Menu("打开日志") {
                if let out = logPaths.standardOut {
                    Button("标准输出日志") { appState.openServiceLog(path: out) }
                }
                if let err = logPaths.standardError {
                    Button("错误日志") { appState.openServiceLog(path: err) }
                }
            }
            .disabled(!logPaths.hasAny)
            Button("复制 plist 路径") { copyPlistPath() }
                .disabled(service.file == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.text2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 27)
        .help(actionsEnabled ? "更多服务操作" : "系统级服务需要在终端中执行，这里只保留只读操作")
        .accessibilityLabel("更多服务操作 \(service.name)")
    }

    private func openFirstLog() {
        if let out = logPaths.standardOut {
            appState.openServiceLog(path: out)
        } else if let err = logPaths.standardError {
            appState.openServiceLog(path: err)
        }
    }

    private func copyPlistPath() {
        guard let file = service.file else {
            appState.showToast("该服务没有可复制的 plist 路径", kind: .info)
            return
        }
        copy(file, toast: "plist 路径已复制")
    }

    private func copy(_ text: String, toast: String) {
        copyToPasteboard(text)
        appState.showToast(toast, kind: .success)
    }
}
