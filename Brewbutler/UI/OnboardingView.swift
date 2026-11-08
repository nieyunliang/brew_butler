import AppKit
import SwiftUI

/// 规范 v2.0.2 §4.12 / UX 方案 O-11：首启引导 3 步。
///
/// ① 检测 Homebrew（欢迎语并入第 1 步顶部；多候选单选；失败给手动路径与安装指引）
/// ② 隐私与安全承诺
/// ③ 完成（⌘K / ⌘R + 可选的「现在运行一次安全扫描」，默认不勾选）
///
/// 检测成功后已安装包索引已在后台进行（AppState.bootstrap），这一步只显示
/// 「正在后台载入」的说明，不阻塞「下一步」。Esc 等同「跳过」：写入完成标记，
/// 下次不再弹。
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var manualPath = ""
    @State private var applyingPath: String?
    @State private var runScan = false
    /// A-16：路径输入聚焦时，Return 应提交该字段而不是触发默认按钮。
    @FocusState private var isPathFocused: Bool

    private let stepCount = 3

    /// A-05：官方安装命令，只用于展示/复制；Brewbutler 不代执行、不代输密码。
    private static let installCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                stepContent
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(minHeight: 280, maxHeight: .infinity)

            footer
        }
        // A-15：宽 520–620、高 380–470 随内容伸缩，长文案滚动而不是被裁切。
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 620,
               minHeight: 380, idealHeight: 410, maxHeight: 470)
        // 引导在系统 sheet 中呈现；玻璃材质与主窗口分层，按钮组用玻璃按钮。
        .background(.regularMaterial)
        // §4.12：Esc 等同跳过，写完成标记，不会下次重弹。
        .onExitCommand { skip() }
        .task {
            // 只读探测多 brew 候选；已在加载时跳过，避免重复执行 brew --version。
            if appState.brewCandidates.isEmpty {
                await appState.loadBrewCandidates()
            }
        }
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch appState.onboardingStep {
        case 0: detectStep
        case 1: privacyStep
        default: doneStep
        }
    }

    /// ① 检测 Homebrew：欢迎语 + 探测状态 + 候选单选 / 失败安装指引。
    private var detectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                title: "检测 Homebrew",
                subtitle: "Brewbutler 帮你看清本机 Homebrew 装了什么、能否安全更新。"
            )

            if appState.isLocatingBrew {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在检测 Homebrew…")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let installation = appState.installation {
                candidateList(current: installation)
                Text("可以继续下一步；之后随时可在「设置 → Homebrew」中更改路径或手动指定。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                backgroundLoadingLine
                if let error = appState.brewPathError {
                    InlineNotice(
                        level: .danger,
                        title: "无法使用该路径",
                        message: error
                    )
                }
            } else {
                installGuidance
            }
        }
    }

    /// ② 隐私与安全：三条承诺，都是可被 VoiceOver 直接朗读的完整句子。
    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(
                title: "隐私与安全",
                subtitle: "在开始之前，你需要知道这三件事。"
            )

            privacyPoint(
                icon: "hand.raised.fill",
                color: AppTheme.accent,
                title: "不需要账号，不上传任何东西",
                detail: "包列表、命令输出和环境信息都只留在这台 Mac 上。"
            )
            privacyPoint(
                icon: "exclamationmark.triangle.fill",
                color: AppTheme.warning,
                title: "危险操作一定会先问你",
                detail: "卸载、清理、重新安装、服务启停都需要二次确认，默认焦点在「取消」。"
            )
            privacyPoint(
                icon: "key.fill",
                color: AppTheme.success,
                title: "永远不会索要管理员密码",
                detail: "需要管理员权限的操作会给出终端命令，由你自己执行；Brewbutler 不代输密码。"
            )
        }
    }

    /// ③ 完成：快捷键提示 + 可选扫描（默认不勾选）。
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            let loadedCount = appState.index.packages.count
            heading(
                title: "准备好了",
                subtitle: loadedCount > 0
                    ? "已安装的 \(loadedCount) 个包已载入。两个快捷键就够你开始："
                    : "两个快捷键就够你开始："
            )

            shortcutRow(keys: "⌘K", title: "命令面板", detail: "跳转页面、找包、执行操作。")
            shortcutRow(keys: "⌘R", title: "检查更新", detail: "先同步 Homebrew 索引，再检查哪些包可以更新。")

            Toggle(isOn: $runScan) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("现在运行一次安全扫描（约 30 秒）")
                    Text("默认不扫描；勾选后会在关闭引导后开始，进度显示在概览安全卡。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 4)
            .accessibilityLabel("现在运行一次安全扫描，约 30 秒，默认不勾选")
        }
    }

    // MARK: - 检测状态子视图

    /// 多候选列表单选。选中项由当前 installation / 自定义路径推导，不另存一份状态，
    /// 切换失败时界面会自动回到真实生效的 brew。
    private func candidateList(current: BrewInstallation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isLoadingBrewCandidates {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在扫描本机安装…")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                }
            }
            ForEach(appState.brewCandidates) { candidate in
                candidateRow(candidate)
            }
            if appState.brewCandidates.isEmpty {
                currentInstallLine(current)
            }
        }
    }

    private func candidateRow(_ candidate: BrewCandidate) -> some View {
        let isSelected = isCurrentCandidate(candidate)
        let isApplying = applyingPath == candidate.path
        return Button {
            guard candidate.isExecutable, !isSelected else { return }
            apply(candidate: candidate)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.text3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.path)
                        .font(AppTheme.mono(12, weight: .semibold))
                        .foregroundStyle(AppTheme.text1)
                    Text(candidate.versionText ?? "版本未知")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                Spacer(minLength: 8)
                if isApplying {
                    ProgressView().controlSize(.small)
                } else if !candidate.isExecutable {
                    Badge(text: "不可用", color: AppTheme.danger)
                } else if candidate.versionText == nil {
                    Badge(text: "版本未知", color: AppTheme.warning)
                } else {
                    Badge(text: "可用", color: AppTheme.success, systemImage: "checkmark")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AppTheme.accentSoft : AppTheme.surface3,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.7) : AppTheme.separator,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!candidate.isExecutable || applyingPath != nil)
        .accessibilityLabel("\(candidate.path)，\(candidate.versionText ?? "版本未知")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .help(candidate.isExecutable ? "使用这个 brew 路径" : "该文件存在但不可执行（可能缺少执行权限或安装已损坏）。")
    }

    /// 单安装时不用列表，只显示一行当前状态。
    private func currentInstallLine(_ installation: BrewInstallation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(installation.executablePath)
                    .font(AppTheme.mono(12, weight: .semibold))
                    .foregroundStyle(AppTheme.text1)
                    .textSelection(.enabled)
                Text(installation.versionText)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            Spacer(minLength: 0)
            Badge(text: "可用", color: AppTheme.success, systemImage: "checkmark")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(installation.executablePath)，\(installation.versionText)，可用")
    }

    /// O-11：索引在后台进行，本步不等待；只给一句进度说明。
    @ViewBuilder
    private var backgroundLoadingLine: some View {
        if appState.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在后台载入已安装的包…你可以继续下一步。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在后台载入已安装的包，你可以继续下一步")
        }
    }

    /// 失败：手动路径 + 官方安装指引（复制命令，不代安装）。
    private var installGuidance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appState.brewError ?? "未找到 Homebrew。")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("安装 Homebrew")
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
                Text("打开官网按说明安装，或复制命令到终端执行；装好后回到这里重新检测。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.installCommand)
                    .font(AppTheme.mono(10.5))
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Button {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("打开 brew.sh", systemImage: "safari")
                    }
                    .glassSecondaryButton()
                    .help("在浏览器打开 https://brew.sh")

                    Button {
                        copyInstallCommand()
                    } label: {
                        Label("复制安装命令", systemImage: "doc.on.doc")
                    }
                    .glassSecondaryButton()
                    .help("复制官方安装脚本命令，需自行在终端执行")

                    Button("安装后重新检测") {
                        Task { await appState.locateBrew(override: appState.settings.brewPathOverride.nilIfEmpty) }
                    }
                    .glassSecondaryButton()
                    .disabled(appState.isLocatingBrew)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                TextField("已安装但未检测到？指定 brew 路径", text: $manualPath)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTheme.mono(11.5))
                    .frame(width: 250)
                    .focused($isPathFocused)
                    // A-16：回车提交本字段，而不是跳到「下一步」。
                    .onSubmit { applyManualPath() }
                    .help("例如 /opt/homebrew/bin/brew，按回车直接应用")
                    .accessibilityLabel("brew 可执行文件路径")
                Button("使用") { applyManualPath() }
                    .glassSecondaryButton()
                    .disabled(manualPath.trimmed.isEmpty || applyingPath != nil)
                    .help(manualPath.trimmed.isEmpty ? "请先填写 brew 可执行文件路径" : "使用该路径")
                if applyingPath != nil {
                    ProgressView().controlSize(.small)
                }
            }
            if let error = appState.brewPathError {
                Text(error)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Brewbutler 不会自动安装 Homebrew，也不会代你输入管理员密码；检测失败不会阻断浏览现有缓存。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 页脚

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == appState.onboardingStep ? AppTheme.accent : AppTheme.surface3)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("第 \(index + 1) 步，共 \(stepCount) 步")
                    .accessibilityAddTraits(index == appState.onboardingStep ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("引导进度")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            stepDots
            Spacer(minLength: 12)
            Button("跳过") { skip() }
                .glassSecondaryButton()
                .help("不看完引导，直接进入主界面（也可按 Esc）")

            if appState.onboardingStep > 0 {
                Button("上一步") { appState.onboardingStep -= 1 }
                    .glassSecondaryButton()
            }

            Button(primaryTitle) { primaryAction() }
                .glassPrimaryButton()
                .modifier(DefaultActionUnlessTextEditing(isTextEditing: isPathFocused))
                .disabled(isPrimaryDisabled)
                .help(primaryHelp)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private var primaryTitle: String {
        if appState.onboardingStep == stepCount - 1 { return "开始使用" }
        // §4.12：找不到 brew 时也可「稍后设置」继续，下一步不能变成死路。
        if appState.onboardingStep == 0,
           appState.installation == nil,
           !appState.isLocatingBrew {
            return "稍后设置"
        }
        return "下一步"
    }

    private var isPrimaryDisabled: Bool {
        appState.onboardingStep == 0 && appState.isLocatingBrew
    }

    private var primaryHelp: String {
        if appState.onboardingStep == stepCount - 1 { return "完成引导并进入主界面" }
        if appState.onboardingStep == 0 && appState.isLocatingBrew { return "正在检测 Homebrew，请稍候；也可以点「跳过」" }
        if appState.onboardingStep == 0 && appState.installation == nil { return "暂不配置 Homebrew，先进入下一步（之后可在设置中指定路径）" }
        return "进入下一步"
    }

    // MARK: - 动作

    private func primaryAction() {
        guard appState.onboardingStep < stepCount - 1 else {
            // 勾选扫描时，扫描在关闭引导后开始（§4.12）。
            appState.completeOnboarding(runScan: runScan)
            dismiss()
            return
        }
        if isPathFocused { isPathFocused = false }
        appState.onboardingStep += 1
    }

    private func skip() {
        // Esc 与「跳过」同一个出口：写完成标记，下次不再弹。
        appState.dismissOnboarding()
        dismiss()
    }

    /// A-16：路径输入的唯一起点——「使用」按钮与 Return 都走这里，
    /// 保证手动路径不会因为默认动作先跳页而被悄悄跳过。
    private func applyManualPath() {
        let trimmed = manualPath.trimmed
        guard !trimmed.isEmpty, applyingPath == nil else { return }
        isPathFocused = false
        applyPath(trimmed)
    }

    private func apply(candidate: BrewCandidate) {
        applyPath(candidate.path)
    }

    private func applyPath(_ path: String) {
        applyingPath = path
        Task {
            _ = await appState.applyBrewPath(path)
            applyingPath = nil
        }
    }

    private func isCurrentCandidate(_ candidate: BrewCandidate) -> Bool {
        let override = appState.settings.brewPathOverride.nilIfEmpty
        if let override { return override == candidate.path }
        return appState.installation?.executablePath == candidate.path
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
        appState.showToast("安装命令已复制", kind: .success)
    }

    // MARK: - 局部组件

    private func heading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.display())
                .foregroundStyle(AppTheme.text1)
            Text(subtitle)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyPoint(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
                Text(detail)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(detail)")
    }

    private func shortcutRow(keys: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.text2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.headline())
                    .foregroundStyle(AppTheme.text1)
                Text(detail)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(keys)，\(title)。\(detail)")
    }
}

/// A-16：文本编辑期间不注册默认动作，否则 TextField 里的 Return 会同时触发「下一步」，
/// 把用户刚输入的路径跳过。非编辑时恢复 Return = 主按钮的标准行为。
private struct DefaultActionUnlessTextEditing: ViewModifier {
    let isTextEditing: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isTextEditing {
            content
        } else {
            content.keyboardShortcut(.defaultAction)
        }
    }
}
