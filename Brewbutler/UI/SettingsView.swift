import SwiftUI
import UserNotifications

/// 规范 v2.0.2 §4.11：设置回到系统 `Settings` scene，内部用原生 `TabView`
/// 六个 tab（macOS 27 工具栏 tab 为玻璃，由系统绘制，这里不自绘侧栏）。
///
/// 内容层一律 `Form(.grouped)`，保持原生 macOS 设置观感：分组、行内开关、
/// 右侧控件都由系统排版。权限/状态一类「原因 + 下一步」的提示才用
/// `InlineNotice`，不把整页做成卡片瀑布。
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            HomebrewSettingsTab()
                .tabItem { Label("Homebrew", systemImage: "mug") }
            NetworkSettingsTab()
                .tabItem { Label("网络", systemImage: "network") }
            NotificationSettingsTab()
                .tabItem { Label("通知", systemImage: "bell") }
            PrivacySettingsTab()
                .tabItem { Label("隐私", systemImage: "hand.raised") }
            AboutSettingsTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        // P0-08：诊断导出的唯一入口在「隐私」；sheet 挂在 TabView 外层，
        // 切换 tab 不会把正在导出的预览关掉。
        .sheet(item: diagnosticsPlan) { plan in
            DiagnosticsSheet(plan: plan)
        }
    }

    private var diagnosticsPlan: Binding<DiagnosticsExportPlan?> {
        Binding(
            get: { appState.pendingDiagnosticsExport },
            set: { appState.pendingDiagnosticsExport = $0 }
        )
    }
}

// MARK: - 通用

/// §4.11 通用：外观（从工具栏移来，UX 方案 O-05）、菜单栏常驻、自动检查更新
/// （只读本地索引，不同步上游）。设置项各只有这一个家。
private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                LabeledContent("外观") {
                    Picker("外观", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityLabel("外观")
                    .accessibilityValue(settings.appearance.label)
                }
                LabeledContent("强调色") {
                    Text("跟随系统设置（系统设置 › 外观）")
                        .foregroundStyle(AppTheme.text2)
                }
            } header: {
                Text("界面")
            } footer: {
                Text("外观与强调色都跟系统走；Brewbutler 不额外覆盖用户选择的强调色。")
            }

            Section {
                Toggle("在菜单栏显示 Brewbutler", isOn: $settings.showMenuBarExtra)
                    .accessibilityLabel("在菜单栏显示 Brewbutler")
            } header: {
                Text("菜单栏")
            } footer: {
                Text("菜单栏常驻项显示可更新数量，点击打开快捷面板；关闭后主窗口与通知不受影响。")
            }

            Section {
                Toggle("自动检查更新", isOn: Binding(
                    get: { appState.settings.autoCheckUpdates },
                    set: { newValue in
                        appState.settings.autoCheckUpdates = newValue
                        // P1-10：开关变化立即重建定时器，不必等下次启动。
                        appState.applyAutoCheckPreference()
                    }
                ))
                .accessibilityLabel("自动检查更新")

                LabeledContent("上次自动检查") {
                    Text(appState.lastAutoCheckAt?.shortDateTimeText ?? "尚未检查")
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text2)
                }
            } header: {
                Text("更新检查")
            } footer: {
                Text("只读：每 24 小时用本地索引检查一次可更新项，不同步上游、不安装任何东西。关闭后仍可随时手动「检查更新」（⌘R）。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Homebrew

/// §4.11 Homebrew：路径（自动探测候选 + 手动）、版本 / 前缀、贪婪模式
/// （从更新页页头移来，UX 方案 O-04）、安装后不清理、环境提示。
private struct HomebrewSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var pathDraft = ""
    @State private var pathEditing = false

    /// 只读操作：brew 缺失时本 tab 仍然完整可用（路径、重新检测、手动指定都可用）。
    var body: some View {
        Form {
            installationSection
            detectedCandidatesSection
            manualPathSection

            Section {
                Toggle("贪婪模式", isOn: greedyBinding)
                    .help("「检查更新」与「全部更新」包含自带自动更新的 cask")
                Toggle("更新后不自动清理旧版本", isOn: Binding(
                    get: { appState.settings.noInstallCleanup },
                    set: { newValue in
                        appState.settings.noInstallCleanup = newValue
                        appState.applyEnvironmentSettings()
                    }
                ))
                LabeledContent("上次同步上游") {
                    Text(appState.settings.lastUpstreamSyncAt?.shortDateTimeText ?? "本次会话尚未同步")
                        .foregroundStyle(AppTheme.text2)
                }
            } header: {
                Text("更新行为")
            } footer: {
                // O-01：把「手动检查更新会先同步索引」与「自动检查只读本地」讲清楚，
                // 这两件事在更新页会以双时间戳呈现。
                Text("手动「检查更新」（⌘R）会先同步 Homebrew 索引再检查可更新项；每 24 小时的自动检查只读本地索引，不同步上游。贪婪模式开启后，更新页副标题会显示「含自动更新的 cask」。")
            }

            Section {
                Toggle("读取操作不自动更新索引", isOn: Binding(
                    get: { appState.settings.injectNoAutoUpdateForReads },
                    set: { newValue in
                        appState.settings.injectNoAutoUpdateForReads = newValue
                        appState.applyEnvironmentSettings()
                    }
                ))
                Toggle("抑制 brew 环境变量提示", isOn: Binding(
                    get: { appState.settings.suppressEnvHints },
                    set: { newValue in
                        appState.settings.suppressEnvHints = newValue
                        appState.applyEnvironmentSettings()
                    }
                ))
            } header: {
                Text("环境变量")
            } footer: {
                Text("只注入 Brewbutler 启动的 brew 进程，不修改系统环境。读取操作不自动更新索引可避免只读查询偷偷触发 brew update；抑制提示只隐藏 brew 的文案，不影响命令结果。")
            }

            // D-21：把原本只在代码里存在的危险 HOMEBREW_* 开关保留在设置里，
            // 每项写明作用域与风险；默认值保持安全（allow* 关闭）。
            Section {
                dangerousToggle(
                    title: "系统级服务不要求 sudo",
                    isOn: Binding(
                        get: { appState.settings.allowNoSudo },
                        set: { newValue in
                            appState.settings.allowNoSudo = newValue
                            appState.applyEnvironmentSettings()
                        }
                    ),
                    detail: "危险：会让需要管理员权限的 brew 命令直接失败，而不是提示 sudo。Brewbutler 永不代输密码。默认关闭。"
                )
                dangerousToggle(
                    title: "跳过 cask 沙箱",
                    isOn: Binding(
                        get: { appState.settings.allowNoSandboxCask },
                        set: { newValue in
                            appState.settings.allowNoSandboxCask = newValue
                            appState.applyEnvironmentSettings()
                        }
                    ),
                    detail: "危险：降低 cask 安装隔离；仅在明确知道后果时开启。默认关闭。"
                )
                dangerousToggle(
                    title: "跳过 App 管理权限提示",
                    isOn: Binding(
                        get: { appState.settings.allowNoAppManagementPrompt },
                        set: { newValue in
                            appState.settings.allowNoAppManagementPrompt = newValue
                            appState.applyEnvironmentSettings()
                        }
                    ),
                    detail: "危险：可能让 cask 安装缺少必要授权而失败。默认关闭。"
                )
            } header: {
                Text("高级（危险）")
            } footer: {
                Text("以上变量同样只注入 Brewbutler 启动的 brew 进程；导出的诊断包会列出实际注入清单。")
            }

            tapTrustSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pathDraft = appState.settings.brewPathOverride
        }
        .task {
            // 只读探测（brew --version），用于列出多安装候选；失败不影响设置窗。
            if appState.brewCandidates.isEmpty {
                await appState.loadBrewCandidates()
            }
        }
    }

    // MARK: 安装

    private var installationSection: some View {
        Section {
            LabeledContent("当前 brew") {
                pathValueText(appState.installation?.executablePath ?? "未检测到 Homebrew")
            }
            if let installation = appState.installation {
                LabeledContent("版本") {
                    Text(installation.version?.raw ?? installation.versionText)
                        .foregroundStyle(AppTheme.text2)
                }
                LabeledContent("prefix") {
                    Text(installation.prefix)
                        .font(AppTheme.mono(12))
                        .foregroundStyle(AppTheme.text2)
                        .textSelection(.enabled)
                }
                if installation.capabilities.isDegraded {
                    ForEach(installation.capabilities.degradedReasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                if installation.isReadOnly {
                    Label("Homebrew 版本低于支持范围，当前为只读模式：只能查看与检查，不能执行变更。", systemImage: "lock")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button(appState.isLocatingBrew ? "正在检测…" : "重新检测") {
                    Task { await appState.locateBrew(override: appState.settings.brewPathOverride.nilIfEmpty) }
                }
                .buttonStyle(.bordered)
                .disabled(appState.isLocatingBrew)
                .help("重新探测当前配置的 brew 路径")

                if appState.settings.brewPathOverride.nilIfEmpty != nil {
                    Button("改回自动探测") {
                        Task {
                            let success = await appState.applyBrewPath("")
                            if success { pathDraft = "" }
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("清空自定义路径，改回自动探测")
                }
            }
        } header: {
            Text("Homebrew 安装")
        } footer: {
            if appState.installation == nil {
                // §4.14 口径：没装 Homebrew 时设置窗照常可用，只给下一步。
                Text("未检测到可用的 Homebrew。可在下方手动指定 brew 路径，或先安装 Homebrew（brew.sh）再点「重新检测」；Brewbutler 不会自动安装，也不会代输管理员密码。")
            } else {
                Text("版本与 prefix 来自 brew 的只读输出；手动指定的路径优先于自动探测。")
            }
        }
    }

    @ViewBuilder
    private var detectedCandidatesSection: some View {
        Section {
            if appState.isLoadingBrewCandidates {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在扫描本机安装…")
                        .foregroundStyle(AppTheme.text2)
                }
            } else if appState.brewCandidates.isEmpty {
                Text("未发现其他安装。")
                    .foregroundStyle(AppTheme.text2)
            } else {
                ForEach(appState.brewCandidates) { candidate in
                    candidateRow(candidate)
                }
            }
            HStack(spacing: 8) {
                Button("扫描本机安装") {
                    Task { await appState.loadBrewCandidates() }
                }
                .buttonStyle(.bordered)
                .disabled(appState.isLoadingBrewCandidates)
                if !appState.brewCandidates.isEmpty {
                    Text("共 \(appState.brewCandidates.count) 个")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
        } header: {
            Text("检测到的安装")
        } footer: {
            Text("只读扫描常见路径与登录 shell，不会修改系统。点选候选即切换 brew；留空表示自动探测。")
        }
    }

    /// A-19：多 brew 安装（Apple Silicon / Intel / 自定义）只读列出，用户点选即应用。
    private func candidateRow(_ candidate: BrewCandidate) -> some View {
        let isSelected = isCurrentCandidate(candidate)
        return Button {
            pathDraft = candidate.path
            pathEditing = false
            Task { await appState.applyBrewPath(candidate.path) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.text3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.path)
                        .font(AppTheme.mono(12))
                        .foregroundStyle(AppTheme.text1)
                    Text(candidate.versionText ?? "版本未知")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                Spacer(minLength: 8)
                if !candidate.isExecutable {
                    Badge(text: "不可执行", color: AppTheme.danger)
                } else if candidate.versionText == nil {
                    // P1-12：可执行但取不到版本，说明安装已损坏，不能装作可用。
                    Badge(text: "版本未知", color: AppTheme.warning)
                } else if isSelected {
                    Badge(text: "使用中", color: AppTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!candidate.isExecutable)
        .help(candidate.isExecutable ? "使用这个 brew 路径" : "该文件存在但不可执行（可能缺少执行权限或安装已损坏）。")
        .accessibilityLabel("\(candidate.path)，\(candidate.versionText ?? "版本未知")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func isCurrentCandidate(_ candidate: BrewCandidate) -> Bool {
        let override = appState.settings.brewPathOverride.nilIfEmpty
        if let override { return override == candidate.path }
        return appState.installation?.executablePath == candidate.path
    }

    private var manualPathSection: some View {
        Section {
            LabeledContent("路径") {
                TextField("路径", text: $pathDraft, prompt: Text("自动探测，或填写完整路径"))
                    .textFieldStyle(.roundedBorder)
                    .font(AppTheme.mono(12))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 300)
                    .labelsHidden()
                    .onSubmit { applyPath() }
                    .onChange(of: pathDraft) { _, newValue in
                        pathEditing = newValue != appState.settings.brewPathOverride
                    }
                    .accessibilityLabel("brew 可执行文件路径")
            }
            HStack(spacing: 8) {
                Spacer()
                Button(pathEditing ? "应用路径" : "重新检测") {
                    if pathEditing {
                        applyPath()
                    } else {
                        Task { await appState.locateBrew(override: appState.settings.brewPathOverride.nilIfEmpty) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .help(pathEditing ? "使用输入的路径重新探测 Homebrew；留空表示自动探测；失败会保留原配置。" : "重新探测当前配置的 Homebrew 路径。")
            }
            if let error = appState.brewPathError {
                InlineNotice(
                    level: .danger,
                    title: "无法使用该路径",
                    message: error,
                    actionTitle: "重试应用"
                ) {
                    applyPath()
                }
            }
        } header: {
            Text("手动指定路径")
        } footer: {
            Text("按回车或点「应用」生效；路径会经过输入校验。应用失败会保留原配置，不会把坏路径持久化。")
        }
    }

    private func applyPath() {
        Task {
            let success = await appState.applyBrewPath(pathDraft)
            if success {
                pathEditing = false
            }
        }
    }

    // MARK: 更新行为

    /// 贪婪模式走 `AppState.greedyUpgrades`：切换后要重新读取 outdated，
    /// 直接写 SettingsStore 会让更新页停留在旧结果。
    private var greedyBinding: Binding<Bool> {
        Binding(
            get: { appState.greedyUpgrades },
            set: { appState.greedyUpgrades = $0 }
        )
    }

    // MARK: tap 信任

    private var trustCapabilityText: String {
        appState.installation?.capabilities.trust == true
            ? "当前 brew 支持（只读展示）"
            : "当前 brew 版本不提供机器可读信任状态"
    }

    /// D-20：tap 信任只读展示；Brewbutler 不提供写入信任的高危操作。
    private var tapTrustSection: some View {
        Section {
            LabeledContent("brew trust") {
                Text(trustCapabilityText)
                    .foregroundStyle(AppTheme.text2)
            }
            if appState.vulnReport == nil {
                Text("尚未完成安全扫描；运行一次安全扫描后，这里会列出因未受信任 tap 而跳过的包。")
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.untrustedTapNames.isEmpty {
                Text("本次扫描未发现因未受信任 tap 而跳过的包。")
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("本次扫描跳过：\(appState.untrustedTapNames.joined(separator: "、"))")
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("复制 brew trust --json=v1") {
                    copyToPasteboard("brew trust --json=v1")
                }
                .buttonStyle(.bordered)
                Text("brew tap-info 的机器可读字段需技术验证。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        } header: {
            Text("tap 信任状态（只读）")
        } footer: {
            Text("信任状态来自 brew 的只读输出，可能滞后；未受信任的 tap 会影响漏洞扫描覆盖与安装行为。Brewbutler 不提供信任/取消信任操作，如确需处理请在终端自行确认来源后执行。")
        }
    }

    @ViewBuilder
    private func dangerousToggle(title: String, isOn: Binding<Bool>, detail: String) -> some View {
        Toggle(title, isOn: isOn)
            .accessibilityLabel(title)
        Text(detail)
            .font(AppTheme.caption())
            .foregroundStyle(AppTheme.text3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pathValueText(_ value: String) -> some View {
        Text(value)
            .font(AppTheme.mono(12))
            .foregroundStyle(appState.installation == nil ? AppTheme.danger : AppTheme.text2)
            .textSelection(.enabled)
    }
}

// MARK: - 网络

/// §4.11 网络：代理、API 域名、Bottle 域名。校验规则与 v1 相同（http(s) 白名单），
/// 只有点「应用网络设置」或回车才写入并影响后续 brew 调用。
private struct NetworkSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var proxyDraft = ""
    @State private var apiDraft = ""
    @State private var bottleDraft = ""
    @State private var proxyError: String?
    @State private var apiError: String?
    @State private var bottleError: String?
    @State private var environmentApplied = false

    var body: some View {
        Form {
            Section {
                networkRow(
                    label: "代理",
                    placeholder: "例如 http://127.0.0.1:7890",
                    text: $proxyDraft,
                    error: proxyError
                )
                networkRow(
                    label: "API 域名",
                    placeholder: "HOMEBREW_API_DOMAIN，例如 https://mirrors.example.com/api",
                    text: $apiDraft,
                    error: apiError
                )
                networkRow(
                    label: "Bottle 域名",
                    placeholder: "HOMEBREW_BOTTLE_DOMAIN，例如 https://mirrors.example.com/bottles",
                    text: $bottleDraft,
                    error: bottleError
                )
                HStack(spacing: 8) {
                    Spacer()
                    Button("应用网络设置") { applyNetwork() }
                        .buttonStyle(.borderedProminent)
                }
                if environmentApplied {
                    InlineNotice(
                        level: .success,
                        title: "网络设置已应用",
                        message: "后续 brew 调用会使用新的代理与镜像。建议重新检查更新以验证连通性。",
                        actionTitle: "重新检查更新"
                    ) {
                        Task { await appState.checkUpdates() }
                    }
                }
            } header: {
                Text("代理与镜像")
            } footer: {
                Text("仅影响 Brewbutler 启动的 brew 进程；留空表示使用默认值。修改后需点「应用网络设置」或按回车才生效。代理只接受 http(s) 地址，镜像只接受 http(s) 开头的合法 URL。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            proxyDraft = appState.settings.proxyURL
            apiDraft = appState.settings.apiDomain
            bottleDraft = appState.settings.bottleDomain
        }
    }

    @ViewBuilder
    private func networkRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        error: String?
    ) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .font(AppTheme.mono(12))
                .multilineTextAlignment(.trailing)
                .frame(width: 280)
                .labelsHidden()
                .onSubmit { applyNetwork() }
                .accessibilityLabel(label)
        }
        if let error {
            Text(error)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyNetwork() {
        proxyError = Self.validateProxy(proxyDraft)
        apiError = Self.validateDomain(apiDraft, label: "API 域名")
        bottleError = Self.validateDomain(bottleDraft, label: "Bottle 域名")
        guard proxyError == nil, apiError == nil, bottleError == nil else {
            environmentApplied = false
            return
        }
        appState.settings.proxyURL = proxyDraft.trimmed
        appState.settings.apiDomain = apiDraft.trimmed
        appState.settings.bottleDomain = bottleDraft.trimmed
        appState.applyEnvironmentSettings()
        environmentApplied = true
    }

    private static func validateProxy(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return "代理地址需为 http(s)://host[:port]，例如 http://127.0.0.1:7890。"
        }
        return nil
    }

    private static func validateDomain(_ raw: String, label: String) -> String? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }
        guard BrewArgumentValidator.isSafeWebURL(trimmed) else {
            return "\(label)需为 http(s):// 开头的合法地址，例如 https://mirrors.example.com/api。"
        }
        return nil
    }
}

// MARK: - 通知

/// §4.11 通知：任务完成 / 可更新 / 漏洞三个开关 + 系统授权状态与跳转。
private struct NotificationSettingsTab: View {
    @Environment(AppState.self) private var appState

    private var authorization: UNAuthorizationStatus { appState.notificationAuthorization }
    private var isDenied: Bool { authorization == .denied }

    private var statusTitle: String {
        switch authorization {
        case .authorized: return "系统通知已授权"
        case .provisional: return "系统通知为临时授权"
        case .denied: return "系统通知已被拒绝"
        case .notDetermined: return "尚未请求通知授权"
        @unknown default: return "通知授权状态未知"
        }
    }

    private var statusMessage: String {
        switch authorization {
        case .authorized:
            return "任务完成、可更新项与安全更新会由 macOS 通知中心送达。"
        case .provisional:
            return "通知会安静地送到通知中心，不播放提醒音。"
        case .denied:
            return "下面的开关不会生效。请在系统设置 → 通知 → Brewbutler 中允许通知后重试。"
        case .notDetermined:
            return "Brewbutler 只会在你同意后发送本地通知，不会上传任何内容。"
        @unknown default:
            return "无法读取通知授权状态。"
        }
    }

    private var statusColor: Color {
        switch authorization {
        case .authorized: return AppTheme.success
        case .provisional: return AppTheme.info
        case .denied: return AppTheme.danger
        default: return AppTheme.text3
        }
    }

    private var primaryActionTitle: String? {
        switch authorization {
        case .denied: return "打开系统设置"
        case .notDetermined: return "请求通知授权"
        case .authorized, .provisional: return "重新检查授权状态"
        default: return nil
        }
    }

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                // D-18：授权状态必须是可见状态，而不是只靠一个「检查授权」按钮。
                LabeledContent("系统授权") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(statusTitle)
                            .foregroundStyle(AppTheme.text2)
                    }
                }
                if let actionTitle = primaryActionTitle {
                    HStack(spacing: 8) {
                        Spacer()
                        Button(actionTitle) {
                            switch authorization {
                            case .denied:
                                appState.openNotificationSettings()
                            case .notDetermined:
                                appState.requestNotificationPermission()
                            default:
                                Task { await appState.refreshNotificationAuthorization() }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("通知")
            } footer: {
                Text(statusMessage)
            }

            Section {
                Toggle("任务完成或失败时通知", isOn: $settings.notifyOnTaskCompletion)
                    .disabled(isDenied)
                Toggle("发现可更新项时通知", isOn: $settings.notifyOnUpdates)
                    .disabled(isDenied)
                Toggle("扫描发现安全更新时通知", isOn: $settings.notifyOnVulnerabilities)
                    .disabled(isDenied)
            } header: {
                Text("通知类型")
            } footer: {
                Text("通知由 macOS 发送；Brewbutler 不代理系统授权，也不会重复弹窗。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await appState.refreshNotificationAuthorization() }
    }
}

// MARK: - 隐私

/// §4.11 隐私：一句隐私声明、本地统计（查看 / 清除）、缓存与日志位置、
/// 清除缓存、日志保留天数、诊断导出。设置项与 v1「高级」里的日志/诊断合并到这里，
/// 不再保留重复分区。
private struct PrivacySettingsTab: View {
    @Environment(AppState.self) private var appState

    private static let cachePath = "~/Library/Application Support/Brewbutler/Cache"
    private static let logPath = "~/Library/Application Support/Brewbutler/Logs"

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                Text("Brewbutler 不需要账号，也没有自建后端；不上传包列表、命令输出、主机名或本机路径。诊断导出前可预览并选择是否包含包名与路径，默认都不含。")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("隐私")
            } footer: {
                Text("无遥测：任务日志、缓存与统计都只存放在这台 Mac 的 Application Support 目录。")
            }

            Section {
                valueRow("任务次数", "\(appState.settings.localTaskCount)", mono: true)
                valueRow("扫描次数", "\(appState.settings.localScanCount)", mono: true)
                LabeledContent("最近扫描") {
                    Text(appState.settings.localLastScanAt?.shortDateTimeText ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text2)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("清除本地统计") { appState.settings.clearLocalStatistics() }
                        .buttonStyle(.bordered)
                        .help("清零任务次数、扫描次数与最近扫描时间，不影响任务历史")
                }
            } header: {
                Text("本地统计")
            } footer: {
                Text("只记录本机完成的任务与扫描次数，用于展示；清除后不可恢复。")
            }

            Section {
                valueRow("缓存位置", Self.cachePath, mono: true)
                valueRow("日志位置", Self.logPath, mono: true)
                Stepper(
                    "日志保留 \(settings.logRetentionDays) 天",
                    value: $settings.logRetentionDays,
                    in: 1...90
                )
                .onChange(of: appState.settings.logRetentionDays) { _, _ in
                    appState.pruneTaskLogs(announce: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("清除全部本地缓存") { appState.clearCaches() }
                        .buttonStyle(.bordered)
                        .help("删除索引、漏洞结果与能力检测缓存；不删除任务日志与历史")
                }
            } header: {
                Text("缓存与日志")
            } footer: {
                Text("路径中的 ~ 为用户主目录。清除缓存只删除索引、漏洞结果与能力检测缓存，不会删除任务日志与历史；日志按保留天数在启动与修改设置时清理。")
            }

            Section {
                HStack(spacing: 8) {
                    Spacer()
                    Button("导出诊断包…") { appState.presentDiagnosticsExport() }
                        .buttonStyle(.bordered)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("导出内容只含应用版本、Homebrew 路径/版本与能力、环境变量注入清单。导出前可预览并选择是否包含包名与本机路径；默认均不含，也不含命令输出、用户名或代理凭据。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func valueRow(_ label: String, _ value: String, mono: Bool) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(mono ? AppTheme.mono(12) : AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 关于

/// §4.11 关于：版本、分发与签名说明（ad-hoc、未公证）、重新显示首次启动引导。
private struct AboutSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "mug.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Brewbutler \(AppState.appVersionText)")
                            .font(AppTheme.headline(16))
                            .foregroundStyle(AppTheme.text1)
                        Text("原生 macOS Homebrew 管理器 · 包可见性与安全更新")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text2)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Brewbutler \(AppState.appVersionText)，原生 macOS Homebrew 管理器")
            }

            Section {
                Text("不提供 Mac App Store 版本：MAS 沙盒无法执行 brew、无法写入 /opt/homebrew，也无法读写 launchd plist。当前构建为 ad-hoc 签名、未公证，首次打开可能被 Gatekeeper 拦截，安装与校验方式见发布说明。")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("分发与签名")
            } footer: {
                Text("Homebrew 是 Homebrew 项目团队的商标；Brewbutler 为独立的第三方客户端。")
            }

            Section {
                LabeledContent("首次启动引导") {
                    Button("重新显示") { appState.restartOnboarding() }
                        .buttonStyle(.bordered)
                        .help("重新打开 3 步引导；不会清除设置、缓存或历史")
                }
            } footer: {
                Text("重新显示引导不会清除设置、缓存或任务历史。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
