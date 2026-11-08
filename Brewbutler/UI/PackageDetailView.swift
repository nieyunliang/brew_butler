import SwiftUI

// MARK: - 包详情（ui-design v2.0.2 §4.5）
//
// 结构：返回条 → hero（图标 / 名称 / 徽章行 / 副标题 / 页头主操作）→ 页级提示
// → 分段 tab（系统玻璃 Picker）→ tab 内容；右侧检查器（Form(.grouped)）。
//
// 硬约束（与规范 / UX 方案保持一致）：
// - 内容层一律实底卡片（SectionCard），玻璃只用在返回条、页头主操作、⋯ 菜单与提示条。
// - 「更新」只有两处入口（O-05）：页头主按钮 + 检查器操作区。漏洞提示条里的
//   「更新到修复版本」是文字链接，只做滚动定位，不新增按钮。
// - 「重新安装…」必须经确认（O-03）：统一走 appState.requestReinstall（外壳单 sheet）。
// - 危险色只出现在确认弹层与漏洞严重度；页面内的卸载入口用中性色。
// - 漏洞口径：任何位置都不写「无漏洞」，只写「本次扫描未发现」+ 覆盖率。

struct PackageDetailView: View {
    @Environment(AppState.self) private var appState
    var package: PackageSnapshot

    @State private var caveatsExpanded = false
    /// 锁定/解锁确认（B-19）：锁定前说明 F5.1 风险，批量由 InstalledView 复用同一 sheet。
    @State private var pinConfirm: PinConfirmRequest?
    /// 漏洞条的「更新到修复版本」文字链接：滚动到页头主按钮并短暂高亮。
    @State private var headerUpdateHighlighted = false
    @State private var headerUpdateFlashTask: Task<Void, Never>?

    private var detail: PackageDetailState { appState.detail }
    private var dependents: [String] { appState.index.dependents(of: package.name) }

    private static let headerUpdateAnchor = "detail.headerUpdateAction"
    private static let tabsAnchor = "detail.tabs"

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            backBar
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        pageNotices

                        Picker("详情标签页", selection: $state.detailTab) {
                            ForEach(DetailTab.allCases) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("详情标签页")
                        .id(Self.tabsAnchor)

                        tabContent(proxy: proxy)
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, AppTheme.pageTopPadding)
                    .padding(.bottom, AppTheme.pagePadding)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .inspector(isPresented: $state.showInspector) {
            PackageInspectorView(package: package)
                .inspectorColumnWidth(min: 280, ideal: 300, max: 340)
        }
        .sheet(item: $pinConfirm) { request in
            PinConfirmSheet(request: request)
        }
        .onDisappear {
            headerUpdateFlashTask?.cancel()
            headerUpdateFlashTask = nil
        }
    }

    // MARK: - Back bar

    private var backBar: some View {
        Button {
            appState.closeDetail()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(appState.section.title)
                    .font(AppTheme.callout())
            }
        }
        .glassSecondaryButton()
        .help("返回 \(appState.section.title)（⌘[）")
        .accessibilityLabel("返回 \(appState.section.title)")
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            packageIcon

            VStack(alignment: .leading, spacing: 6) {
                Text(package.displayName)
                    .font(AppTheme.packageTitle())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .textSelection(.enabled)

                badgeRow

                Text(subtitleText)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                if let metaLine {
                    Text(metaLine)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }

            Spacer(minLength: 12)

            headerActions
        }
        .padding(.top, 2)
    }

    /// 规范 §4.5：formula 用 `terminal`、cask 用 `app.dashed` 的系统符号。
    /// 底色取系统强调色渐变，不引入品牌色。
    private var packageIcon: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.72), AppTheme.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: package.kind == .formula ? "terminal" : "app.dashed")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(AppTheme.onAccent)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: AppTheme.accent.opacity(0.28), radius: 10, y: 4)
            .accessibilityHidden(true)
    }

    private var badgeRow: some View {
        HStack(spacing: 6) {
            KindBadge(kind: package.kind)
            if package.outdated {
                Badge(text: "可更新", color: AppTheme.accent, systemImage: "arrow.up.circle.fill")
            }
            if let severity = package.vulnerabilitySeverity {
                SeverityBadge(severity: severity)
            }
            if package.kegOnly {
                Badge(text: "keg-only", color: AppTheme.text2, systemImage: "link.badge.plus")
            }
            if package.pinned {
                Badge(text: "已锁定", color: AppTheme.text2, systemImage: "pin.fill")
            }
            // disabled 通常同时带 deprecated 标记：只显示更严重的那一个，避免徽章行溢出。
            if package.disabled {
                Badge(text: "已禁用", color: AppTheme.neutral, systemImage: "nosign")
            } else if package.deprecated {
                Badge(text: "已废弃", color: AppTheme.warning, systemImage: "archivebox")
            }
        }
    }

    private var subtitleText: String {
        let description = package.desc?.trimmed.nilIfEmpty ?? "无描述"
        return "\(description) · \(package.tap ?? "未知 tap")"
    }

    private var metaLine: String? {
        var parts: [String] = []
        if detail.packageID == package.id, let size = detail.sizeBytes, size > 0 {
            parts.append(size.byteCountText)
        }
        if let installedAt = package.installedAt {
            parts.append("安装于 \(installedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))")
        }
        if !package.allDependencies.isEmpty {
            parts.append("\(package.allDependencies.count) 个依赖")
        }
        if !dependents.isEmpty {
            parts.append("被 \(dependents.count) 个包依赖")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 规范 §4.5 / O-05：页头主操作只有「更新到 X」+「⋯」。
    private var headerActions: some View {
        HStack(spacing: 8) {
            if package.outdated, let stable = package.stableVersion {
                Button("更新到 \(stable)") {
                    appState.upgrade(package: package)
                }
                .glassPrimaryButton()
                .disabled(package.pinned || appState.isReadOnly)
                .help(headerUpdateHelp(stable: stable))
                .keyboardShortcut("u", modifiers: .command)
                .id(Self.headerUpdateAnchor)
                // 文字链接定位后给一圈外扩的强调色光环，避免用户找不到页头按钮。
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.9), lineWidth: headerUpdateHighlighted ? 2 : 0)
                        .padding(-3)
                        .shadow(
                            color: AppTheme.accent.opacity(headerUpdateHighlighted ? 0.45 : 0),
                            radius: headerUpdateHighlighted ? 8 : 0
                        )
                )
            }

            moreMenu
        }
    }

    private func headerUpdateHelp(stable: String) -> String {
        if package.pinned { return "已锁定，请先解锁" }
        if appState.isReadOnly { return "只读模式（Homebrew 版本低于 7.0 或尚未探测）下不能更新" }
        return "更新到 \(stable)（⌘U）"
    }

    private var moreMenu: some View {
        Menu {
            Button("复制安装命令") { copy(package.installCommand) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("复制卸载命令") { copy(package.uninstallCommand) }
            if let homepage = package.homepage {
                Button("打开主页") { appState.openHomepage(homepage) }
            }
            if let path = installedPath {
                Button("在 Finder 中显示") { appState.revealInFinder(path: path) }
            }
            Divider()
            Button(package.pinned ? "解锁…" : "锁定…") { requestPinToggle() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(appState.isReadOnly)
                .help(pinHelp)
            // O-03：带「…」的重新安装必须先确认，不能直接入队。
            Button("重新安装…") { appState.requestReinstall(package) }
                .disabled(appState.isReadOnly)
                .help(appState.isReadOnly ? "只读模式下不能重新安装" : "会重新下载并覆盖当前版本的文件，不改变版本号")
            Button(dependents.isEmpty ? "卸载…" : "卸载…（被 \(dependents.count) 个包依赖）") {
                appState.requestUninstall(package)
            }
            .disabled(appState.isReadOnly || !dependents.isEmpty)
            .help(uninstallHelp)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.text1)
                .frame(width: 30, height: 24)
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .glassCapsule(interactive: true)
        .help("更多操作")
        .accessibilityLabel("更多操作")
    }

    private var installedPath: String? {
        guard detail.packageID == package.id, let path = detail.path else { return nil }
        return path
    }

    private var uninstallHelp: String {
        if appState.isReadOnly { return "只读模式下不能卸载" }
        if !dependents.isEmpty { return "有 \(dependents.count) 个包依赖它，需先处理依赖方" }
        return "删除该包（不可恢复），会先进入确认弹层"
    }

    // MARK: - Page notices

    @ViewBuilder
    private var pageNotices: some View {
        if package.isDeprecatedOrDisabled {
            GlassNotice(
                level: .warning,
                title: package.disabled ? "该包已被禁用" : "该包已废弃",
                message: package.statusNote?.trimmed.nilIfEmpty ?? "上游不再维护该包，建议寻找替代品。"
            )
        }

        if appState.isReadOnly {
            GlassNotice(
                level: .info,
                title: "只读模式",
                message: "当前 Homebrew 版本低于 7.0 或尚未完成探测，本会话内安装、更新、卸载与锁定都不可用；升级 Homebrew 或重新检测后可恢复。"
            )
        }

        if package.kind == .cask, package.autoUpdates == true {
            GlassNotice(
                level: .warning,
                title: "该 cask 启用了自动更新",
                message: "应用可能绕过 Homebrew 自行更新；锁定版本不会阻止其自我更新，更新页也可能显示为已是最新。"
            )
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(proxy: ScrollViewProxy) -> some View {
        switch appState.detailTab {
        case .overview:
            overviewTab(proxy: proxy)
        case .security:
            securityTab
        case .dependencies:
            dependenciesTab
        case .dependents:
            dependentsTab
        case .files:
            filesTab
        case .history:
            historyTab
        }
    }

    // MARK: - Overview

    private func overviewTab(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            vulnerabilityStrip(proxy: proxy)
            aboutCard
            caveatsCard
            installCommandCard
        }
    }

    /// 规范 §4.5 / O-05：漏洞提示条里只给文字链接「更新到修复版本」，
    /// 点击滚动定位到页头主按钮；没有修复版本时不给假按钮。
    @ViewBuilder
    private func vulnerabilityStrip(proxy: ScrollViewProxy) -> some View {
        if let finding = package.vulnerabilityFinding {
            let fixedVersion = finding.vulnerabilities.compactMap { $0.fixedVersions.first }.first
            let count = finding.vulnerabilities.count
            let firstID = finding.vulnerabilities.first?.id
            let message: String = {
                let fixText = fixedVersion.map { "修复版本 \($0) 可用" } ?? "上游暂无修复版本"
                return count > 1 ? "共 \(count) 条记录 · \(fixText)" : fixText
            }()

            DetailNotice(
                level: noticeLevel(for: finding.worstSeverity),
                title: "\(finding.worstSeverity.label) · \(firstID ?? "已知漏洞")",
                message: message,
                linkTitle: package.outdated && fixedVersion != nil ? "更新到修复版本" : nil,
                linkAction: { revealHeaderUpdate(proxy: proxy) },
                secondaryLinkTitle: "查看安全详情",
                secondaryLinkAction: {
                    appState.detailTab = .security
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(Self.tabsAnchor, anchor: .top)
                    }
                }
            )
        }
    }

    private func noticeLevel(for severity: VulnSeverity) -> DetailNotice.Level {
        switch severity {
        case .critical, .high: return .danger
        case .medium: return .warning
        case .low, .unknown: return .info
        }
    }

    /// 只做定位，不执行更新；滚动后把页头按钮短暂高亮，避免用户找不到。
    private func revealHeaderUpdate(proxy: ScrollViewProxy) {
        guard package.outdated, package.stableVersion != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(Self.headerUpdateAnchor, anchor: .center)
        }
        withAnimation(.easeOut(duration: 0.15)) {
            headerUpdateHighlighted = true
        }
        headerUpdateFlashTask?.cancel()
        headerUpdateFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                headerUpdateHighlighted = false
            }
        }
    }

    private var aboutCard: some View {
        SectionCard(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("版本")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text3)
                        .frame(width: 88, alignment: .leading)
                    VersionChangeText(
                        installed: package.installedVersion,
                        latest: package.stableVersion,
                        outdated: package.outdated
                    )
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "tap", value: package.tap ?? "—", mono: true)
                        InfoRow(label: "体积", value: sizeText, mono: true)
                        InfoRow(label: "依赖", value: dependenciesSummary)
                        InfoRow(label: "安装方式", value: package.installedOnRequest == true ? "手动安装" : "作为依赖")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "许可", value: package.license ?? "—")
                        InfoRow(label: "安装于", value: installedAtText)
                        InfoRow(label: "被依赖", value: "\(dependents.count) 个包")
                        InfoRow(label: "服务", value: package.hasService ? "包含 launchd 服务" : "无")
                        if package.kind == .cask {
                            InfoRow(
                                label: "自动更新",
                                value: package.autoUpdates == true ? "已开启（可能绕过 Homebrew）" : "未开启"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let homepage = package.homepage {
                    HStack(spacing: 10) {
                        Text("主页")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text3)
                            .frame(width: 88, alignment: .leading)
                        Text(homepage)
                            .font(AppTheme.mono())
                            .foregroundStyle(AppTheme.text2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        TextLinkButton(title: "打开", systemImage: "arrow.up.right.square", help: "在浏览器中打开 \(homepage)") {
                            appState.openHomepage(homepage)
                        }
                    }
                }
            }
        }
    }

    private var sizeText: String {
        guard detail.packageID == package.id else { return "…" }
        guard let bytes = detail.sizeBytes, bytes > 0 else { return "—" }
        return bytes.byteCountText
    }

    private var installedAtText: String {
        guard let installedAt = package.installedAt else { return "—" }
        return installedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private var dependenciesSummary: String {
        let names = package.allDependencies
        guard !names.isEmpty else { return "无" }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) 等 \(names.count) 个" : shown
    }

    @ViewBuilder
    private var caveatsCard: some View {
        let caveats = package.caveats?.trimmed.nilIfEmpty
        if caveats != nil || package.kegOnly {
            SectionCard(title: "CAVEATS", subtitle: package.kegOnly ? "keg-only" : nil) {
                VStack(alignment: .leading, spacing: 8) {
                    if package.kegOnly {
                        Text(kegOnlyExplanation)
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let caveats {
                        let isLong = caveats.components(separatedBy: "\n").count > 6
                        Text(caveats)
                            .font(AppTheme.mono())
                            .foregroundStyle(AppTheme.text2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(isLong && !caveatsExpanded ? 6 : nil)
                        HStack(spacing: 8) {
                            if isLong {
                                Button(caveatsExpanded ? "收起" : "展开全文") {
                                    caveatsExpanded.toggle()
                                }
                                .glassSecondaryButton()
                                .accessibilityLabel(caveatsExpanded ? "收起 CAVEATS 全文" : "展开 CAVEATS 全文")
                            }
                            Button("复制 CAVEATS") { copy(caveats) }
                                .glassSecondaryButton()
                                .help("复制 CAVEATS 全文到剪贴板")
                                .accessibilityLabel("复制 CAVEATS 全文")
                        }
                    }
                }
            }
        }
    }

    private var kegOnlyExplanation: String {
        if let reason = package.kegOnlyReason?.trimmed.nilIfEmpty { return reason }
        let prefix = appState.installation?.prefix ?? "/opt/homebrew"
        return "该包不会链接到 \(prefix)/bin，避免与系统库冲突。"
    }

    private var installCommandCard: some View {
        SectionCard(title: "安装命令") {
            HStack(spacing: 10) {
                Text(package.installCommand)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("安装命令 \(package.installCommand)")
                Button("复制") { copy(package.installCommand) }
                    .glassSecondaryButton()
                    .help("复制安装命令到剪贴板")
            }
        }
    }

    // MARK: - Security

    private var securityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let finding = package.vulnerabilityFinding {
                SectionCard(
                    title: "已知漏洞",
                    subtitle: finding.vulnerabilities.count > 1 ? "\(finding.vulnerabilities.count) 条记录" : nil
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(finding.vulnerabilities.enumerated()), id: \.element.id) { index, vulnerability in
                            vulnerabilityRow(vulnerability, affectedVersion: finding.version)
                            if index < finding.vulnerabilities.count - 1 {
                                Hairline()
                            }
                        }
                    }
                }
            } else {
                SectionCard(title: "已知漏洞") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(noFindingText)
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(appState.vulnerabilityCoverageText)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            scanMetaCard
        }
    }

    private var noFindingText: String {
        packageNoFindingText(for: package, vulnReport: appState.vulnReport)
    }

    private func vulnerabilityRow(_ vulnerability: Vulnerability, affectedVersion: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SeverityBadge(severity: vulnerability.severity, compact: true)
                Text(vulnerability.id)
                    .font(AppTheme.mono(12, weight: .semibold))
                    .foregroundStyle(AppTheme.text1)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                TextLinkButton(
                    title: "在 OSV 查看",
                    systemImage: "arrow.up.right.square",
                    help: "在 osv.dev 查看 \(vulnerability.id)"
                ) {
                    appState.openOSV(vulnerability)
                }
            }

            if let summary = vulnerability.summary?.trimmed.nilIfEmpty {
                Text(summary)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                if let affectedVersion {
                    Text("影响版本 \(affectedVersion)")
                        .font(AppTheme.mono())
                        .foregroundStyle(AppTheme.text3)
                }
                Text(
                    vulnerability.fixedVersions.isEmpty
                        ? "修复版本：上游暂无修复版本"
                        : "修复版本：\(vulnerability.fixedVersions.joined(separator: ", "))"
                )
                .font(AppTheme.mono())
                .foregroundStyle(vulnerability.fixedVersions.isEmpty ? AppTheme.warning : AppTheme.success)
                Spacer(minLength: 0)
            }

            if !vulnerability.aliases.isEmpty {
                Text("别名：\(vulnerability.aliases.joined(separator: " · "))")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
        .padding(.vertical, 10)
    }

    private var scanMetaCard: some View {
        SectionCard(title: "本次扫描") {
            VStack(alignment: .leading, spacing: 8) {
                if let report = appState.vulnReport {
                    InfoRow(
                        label: "扫描时间",
                        value: "\(report.scannedAt.shortDateTimeText)（\(report.scannedAt.relativeText)）"
                    )
                    InfoRow(label: "覆盖", value: coverageDetail)
                    if !report.skippedFormulae.isEmpty {
                        InfoRow(label: "跳过", value: "\(report.skippedFormulae.count) 个 formula 不在 OSV 映射范围")
                    }
                    if !report.unscannedFormulae.isEmpty {
                        InfoRow(label: "未覆盖", value: unscannedSummary)
                    }
                    InfoRow(
                        label: "退出码",
                        value: "\(report.exitCode)\(report.exitCode == 1 ? "（发现漏洞，属预期）" : "")",
                        mono: true
                    )
                    if report.exitCode == 1 {
                        Text("退出码 1 表示 brew vulns 发现了漏洞，不属于扫描失败。")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if appState.scanIsStale {
                        InlineWarningRow(message: "已安装的包有变化，扫描结果可能已过时。")
                    }
                } else {
                    Text("尚无扫描记录。")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                    Text("本次扫描范围尚未建立，不能据此判断该包的漏洞状态。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if appState.isScanning {
                            ProgressView().controlSize(.small)
                            Text("正在扫描…")
                                .font(AppTheme.callout())
                                .foregroundStyle(AppTheme.text2)
                        } else {
                            Button("运行安全扫描") { appState.scanVulnerabilities() }
                                .glassSecondaryButton()
                                .help("运行 brew vulns 并更新覆盖率")
                        }
                    }
                }
            }
        }
    }

    private var coverageDetail: String {
        guard let report = appState.vulnReport else { return "扫描未知" }
        let total = appState.scannableFormulaCount
        guard total > 0 else { return "未安装可扫描的 formula" }
        let checked = min(max(report.checked, 0), total)
        return "\(checked)/\(total) 个 formula\(report.complete ? "" : "（部分覆盖）")"
    }

    private var unscannedSummary: String {
        guard let report = appState.vulnReport else { return "—" }
        let labels = report.unscannedFormulae.values.map(unscannedReasonLabel)
        let counts = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
        let parts = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) 个" }
        return "\(report.unscannedFormulae.count) 个（\(parts.joined(separator: " · "))）"
    }

    /// 只翻译已知原因；未知原因原样呈现，不臆造语义。
    private func unscannedReasonLabel(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("untrusted") { return "未受信任的 tap" }
        if raw.localizedCaseInsensitiveContains("metadata") { return "缺少元数据" }
        if raw.localizedCaseInsensitiveContains("network") { return "网络失败" }
        return raw
    }

    // MARK: - Dependencies

    private var runtimeDependencyNames: [String] {
        package.runtimeDependencies.map(\.fullName)
    }

    /// `dependencies` 是声明的依赖（含构建依赖），`runtimeDependencies` 是已安装
    /// keg 的运行时依赖；两者按短名去重后，剩余的就是「只在构建时需要」的依赖。
    private var buildOnlyDependencyNames: [String] {
        let runtimeShortNames = Set(runtimeDependencyNames.map(shortName))
        return package.dependencies.filter { !runtimeShortNames.contains(shortName($0)) }
    }

    private func shortName(_ fullName: String) -> String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }

    @ViewBuilder
    private var dependenciesTab: some View {
        if package.kind == .cask {
            SectionCard(title: "依赖") {
                Text("cask 的依赖信息当前未从 brew info 解析；安装或更新时由 Homebrew 处理。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if runtimeDependencyNames.isEmpty {
            if package.dependencies.isEmpty {
                SectionCard(title: "依赖") {
                    Text("该包没有声明依赖。")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                }
            } else {
                // 运行时依赖元数据缺失时不做假分组，统一按「依赖」列出。
                dependencySection(title: "依赖", names: package.dependencies, note: nil)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                dependencySection(title: "运行依赖", names: runtimeDependencyNames, note: nil)
                if !buildOnlyDependencyNames.isEmpty {
                    dependencySection(
                        title: "构建依赖",
                        names: buildOnlyDependencyNames,
                        note: "只在从源码构建时需要，不影响使用。"
                    )
                }
            }
        }
    }

    private func dependencySection(title: String, names: [String], note: String?) -> some View {
        SectionCard(title: title, subtitle: "\(names.count) 个") {
            VStack(alignment: .leading, spacing: 8) {
                if let note {
                    Text(note)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                VStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        dependencyRow(name)
                        if index < names.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private func dependencyRow(_ name: String) -> some View {
        let installed = appState.index.package(named: name, kind: .formula)
        let display = shortName(name)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let installed {
                        // 已安装依赖是文字链接，可点进详情。
                        TextLinkButton(
                            title: display,
                            font: AppTheme.mono(11.5),
                            help: "打开 \(display) 的详情"
                        ) {
                            appState.selectPackage(installed)
                        }
                        Badge(text: "已安装", color: AppTheme.success, systemImage: "checkmark")
                    } else {
                        Text(display)
                            .font(AppTheme.mono(11.5))
                            .foregroundStyle(AppTheme.text2)
                        Badge(text: "未安装", color: AppTheme.neutral)
                    }
                }
                if let description = installed?.desc?.trimmed.nilIfEmpty {
                    Text(description)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let installed {
                Text(installed.installedVersion ?? "")
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text3)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.text3)
            } else {
                // O-03：不提供永久禁用的「安装」按钮，改成进入发现页并预填包名。
                TextLinkButton(
                    title: "在 Homebrew 中搜索 \(display) ›",
                    help: "进入发现页搜索 \(display)；安装仍走发现页的确认"
                ) {
                    appState.openDiscover(query: display, kind: .formula)
                }
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: - Dependents

    private var dependentsTab: some View {
        SectionCard(title: "被依赖", subtitle: dependents.isEmpty ? "无" : "\(dependents.count) 个包依赖它") {
            if dependents.isEmpty {
                Text("本次已安装快照中未发现依赖方；卸载后仍可能影响未安装的工具、脚本或外部配置。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    InlineWarningRow(message: "卸载该包后，以下 \(dependents.count) 个包可能无法运行。")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(dependents, id: \.self) { name in
                            DependentNameChip(name: name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Files

    private var filesTab: some View {
        SectionCard(
            title: "文件",
            subtitle: detail.packageID == package.id
                ? (detail.files.isEmpty ? nil : "\(detail.files.count) 项")
                : nil
        ) {
            if detail.isLoading || detail.packageID != package.id {
                loadingRow("正在读取文件列表…")
            } else if package.kind == .cask {
                Text("cask 不提供文件级列表；可用「在 Finder 中显示」查看 Caskroom。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if detail.files.isEmpty {
                Text(detail.error ?? "没有可见文件。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if detail.files.count > 500 {
                        Text("仅显示前 500 项（共 \(detail.files.count) 项）；完整列表可在「在 Finder 中显示」中查看。")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                    ForEach(detail.files.prefix(500), id: \.self) { file in
                        Text(file)
                            .font(AppTheme.mono())
                            .foregroundStyle(AppTheme.text2)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - History

    private var historyTab: some View {
        SectionCard(title: "更新历史") {
            if detail.isLoading || detail.packageID != package.id {
                loadingRow("正在读取…")
            } else if let log = detail.changeLog, !log.isEmpty {
                Text(log)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    package.kind == .cask
                        ? "cask 没有可用的更新历史。"
                        : "该包没有可用的更新历史（brew log 不可用或无提交）。"
                )
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
        }
    }

    // MARK: - Actions

    /// Homebrew 7 的 pin/unpin 已支持 cask（状态层按 kind 传 --cask），不再按类型禁用。
    private var pinHelp: String {
        if appState.isReadOnly { return "只读模式下不能锁定或解锁" }
        if package.pinned { return "解除锁定后该包会重新纳入更新" }
        if package.kind == .cask, package.autoUpdates == true {
            return "锁定后更新会跳过该 cask；但它启用了自动更新（auto_updates），可能绕过 Homebrew 自行更新"
        }
        return "锁定后更新会跳过该包（需要新版本时先解锁）"
    }

    private func requestPinToggle() {
        pinConfirm = PinConfirmRequest(packages: [package], pinned: !package.pinned)
    }

    private func copy(_ text: String) {
        copyToPasteboard(text)
        appState.showToast("已复制", kind: .success)
    }
}

// MARK: - Inspector

/// 检查器（ui-design v2.0.2 §4.5 / O-08）：`Form(.grouped)` 分区，不套玻璃卡；
/// 危险区「卸载…」在最底部。开关状态由 `AppState.showInspector`（SettingsStore 持久化）
/// 记忆，打开另一个包时不强制弹出。
struct PackageInspectorView: View {
    @Environment(AppState.self) private var appState
    var package: PackageSnapshot

    @State private var pinConfirm: PinConfirmRequest?

    private var detail: PackageDetailState { appState.detail }
    private var dependents: [String] { appState.index.dependents(of: package.name) }

    var body: some View {
        Form {
            Section {
                actionRows
            } header: {
                Text("操作")
            }

            Section {
                summaryRows
            } header: {
                Text("概要")
            }

            Section {
                healthRows
            } header: {
                Text("健康")
            }

            Section {
                dependentsRows
            } header: {
                Text(dependents.isEmpty ? "被依赖" : "被依赖 · \(dependents.count)")
            }

            Section {
                dangerRows
            } header: {
                Text("危险区")
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("包详情检查器")
        .sheet(item: $pinConfirm) { request in
            PinConfirmSheet(request: request)
        }
    }

    private var installedPath: String? {
        guard detail.packageID == package.id, let path = detail.path else { return nil }
        return path
    }

    // MARK: Actions

    @ViewBuilder
    private var actionRows: some View {
        if appState.isReadOnly {
            Text("只读模式：Homebrew 版本低于 7.0 或尚未完成探测，以下操作不可用。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }

        if package.outdated, let stable = package.stableVersion {
            inspectorActionRow(
                "更新到 \(stable)",
                systemImage: "arrow.up.circle",
                emphasis: true,
                isEnabled: !package.pinned && !appState.isReadOnly,
                help: updateHelp(stable: stable)
            ) {
                appState.upgrade(package: package)
            }
        }

        inspectorActionRow(
            package.pinned ? "解锁…" : "锁定…",
            systemImage: package.pinned ? "pin.slash" : "pin",
            isEnabled: !appState.isReadOnly,
            help: inspectorPinHelp
        ) {
            requestPinToggle()
        }

        // O-03：同一入口，先进确认弹层再入队。
        inspectorActionRow(
            "重新安装…",
            systemImage: "arrow.triangle.2.circlepath",
            isEnabled: !appState.isReadOnly,
            help: appState.isReadOnly ? "只读模式下不能重新安装" : "会重新下载并覆盖当前版本的文件，不改变版本号"
        ) {
            appState.requestReinstall(package)
        }

        inspectorActionRow("复制安装命令", systemImage: "doc.on.doc", help: "复制到剪贴板") {
            copyToPasteboard(package.installCommand)
            appState.showToast("已复制安装命令", kind: .success)
        }

        if let path = installedPath {
            inspectorActionRow("在 Finder 中显示", systemImage: "folder", help: path) {
                appState.revealInFinder(path: path)
            }
        }
    }

    private func updateHelp(stable: String) -> String {
        if package.pinned { return "已锁定，请先解锁" }
        if appState.isReadOnly { return "只读模式下不能更新" }
        return "更新到 \(stable)"
    }

    private var inspectorPinHelp: String {
        if appState.isReadOnly { return "只读模式下不能锁定或解锁" }
        if package.pinned { return "解除锁定后重新纳入更新" }
        if package.kind == .cask, package.autoUpdates == true {
            return "锁定后更新会跳过该 cask；但它启用了自动更新，可能绕过 Homebrew 自行更新"
        }
        return "锁定后更新会跳过该包；依赖新版本的其他包可能无法安装或运行"
    }

    private func requestPinToggle() {
        pinConfirm = PinConfirmRequest(packages: [package], pinned: !package.pinned)
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryRows: some View {
        inspectorValueRow("类型", value: package.kind.rawValue)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("版本")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            Spacer(minLength: 8)
            VersionChangeText(
                installed: package.installedVersion,
                latest: package.stableVersion,
                outdated: package.outdated
            )
        }
        .accessibilityElement(children: .combine)

        inspectorValueRow("体积", value: sizeText, mono: true)
        inspectorValueRow("tap", value: package.tap ?? "—", mono: true)

        if let path = installedPath {
            VStack(alignment: .leading, spacing: 3) {
                Text("路径")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                Text(path)
                    .font(AppTheme.mono(10.5))
                    .foregroundStyle(AppTheme.text2)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private var sizeText: String {
        guard detail.packageID == package.id else { return "…" }
        guard let bytes = detail.sizeBytes, bytes > 0 else { return "—" }
        return bytes.byteCountText
    }

    // MARK: Health

    @ViewBuilder
    private var healthRows: some View {
        if let finding = package.vulnerabilityFinding {
            HStack(spacing: 8) {
                Text("漏洞")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                Spacer(minLength: 8)
                SeverityBadge(severity: finding.worstSeverity, compact: true)
            }
            HStack(spacing: 8) {
                Text("修复")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                Spacer(minLength: 8)
                Text(finding.hasFix ? "修复可用" : "上游暂无修复版本")
                    .font(AppTheme.caption())
                    .foregroundStyle(finding.hasFix ? AppTheme.success : AppTheme.warning)
            }
        } else {
            Text(packageNoFindingText(for: package, vulnReport: appState.vulnReport))
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("本次扫描")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            Spacer(minLength: 8)
            Text(scanSummaryText)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
        }

        if appState.scanIsStale {
            Text("已安装的包有变化，扫描结果可能已过时。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

        TextLinkButton(title: "查看安全详情", help: "切换到安全 tab") {
            appState.detailTab = .security
        }
    }

    private var scanSummaryText: String {
        guard let report = appState.vulnReport else { return "扫描未知" }
        let total = appState.scannableFormulaCount
        guard total > 0 else { return "扫描未知" }
        let checked = min(max(report.checked, 0), total)
        return "\(checked)/\(total) · \(report.scannedAt.relativeText)"
    }

    // MARK: Dependents

    @ViewBuilder
    private var dependentsRows: some View {
        if dependents.isEmpty {
            Text("本次已安装快照中未发现依赖方。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(dependents.prefix(8), id: \.self) { name in
                    DependentNameChip(name: name)
                }
                if dependents.count > 8 {
                    Text("+\(dependents.count - 8)")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            TextLinkButton(title: "查看全部 \(dependents.count) 个", help: "切换到被依赖 tab") {
                appState.detailTab = .dependents
            }
        }
    }

    // MARK: Danger

    @ViewBuilder
    private var dangerRows: some View {
        if !dependents.isEmpty {
            Text("被 \(dependents.count) 个包依赖，无法在此卸载；请先更新或卸载依赖方。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button {
            appState.requestUninstall(package)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.text2)
                    .frame(width: 16)
                Text(
                    dependents.isEmpty
                        ? "卸载 \(package.displayName)…"
                        : "卸载 \(package.displayName)…（被 \(dependents.count) 个包依赖）"
                )
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appState.isReadOnly || !dependents.isEmpty)
        .opacity(appState.isReadOnly || !dependents.isEmpty ? 0.45 : 1)
        .help(dangerHelp)
        .accessibilityLabel("卸载 \(package.displayName)…，将打开确认弹层")
    }

    private var dangerHelp: String {
        if appState.isReadOnly { return "只读模式下不能卸载" }
        if !dependents.isEmpty { return "有 \(dependents.count) 个包依赖它，需先处理依赖方" }
        return "删除该包（不可恢复）"
    }

    // MARK: Row helpers

    private func inspectorActionRow(
        _ title: String,
        systemImage: String,
        emphasis: Bool = false,
        isEnabled: Bool = true,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(emphasis ? AppTheme.accent : AppTheme.text2)
                    .frame(width: 16)
                Text(title)
                    .font(AppTheme.callout())
                    .foregroundStyle(emphasis ? AppTheme.accent : AppTheme.text1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(title)
    }

    private func inspectorValueRow(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? AppTheme.mono(11.5) : AppTheme.callout(12))
                .foregroundStyle(AppTheme.text1)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

// MARK: - Shared small views

/// 单包漏洞状态的诚实文案：未扫描 / 未覆盖 / 不在映射范围 / 已扫描未发现。
/// 「安全」tab 与检查器健康区共用同一函数，避免两处口径不一致。
fileprivate func packageNoFindingText(for package: PackageSnapshot, vulnReport: VulnReport?) -> String {
    guard let report = vulnReport else {
        return "尚未运行安全扫描，无法判断该包是否有已知漏洞。"
    }
    if package.kind == .cask {
        return "cask 不在 brew vulns 的 OSV 映射范围内，无法判断其漏洞状态。"
    }
    if let reason = report.unscannedFormulae[package.name] {
        return "本次扫描未覆盖该包（\(reason)），不能据此认为安全；请查看仪表盘的扫描覆盖率。"
    }
    if report.skippedFormulae.contains(package.name) {
        return "该包不在 brew vulns 的 OSV 映射范围，本次扫描未覆盖，不能据此认为安全。"
    }
    if !report.complete {
        return "本次扫描仅部分覆盖，已扫描范围内未发现该包的漏洞记录；不能据此认为该包安全。"
    }
    return "本次扫描未发现该包的漏洞记录。"
}

/// 版本变化（规范 §5 VersionChange）：旧版本删除线语义用弱化色，新版本 accent 加粗 mono。
private struct VersionChangeText: View {
    var installed: String?
    var latest: String?
    var outdated: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(installed ?? "—")
                .font(AppTheme.mono(12))
                .foregroundStyle(outdated ? AppTheme.text3 : AppTheme.text1)
            if outdated, let latest {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.text3)
                Text(latest)
                    .font(AppTheme.mono(12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            outdated && latest != nil
                ? "版本 \(installed ?? "未知") 更新到 \(latest ?? "")"
                : "版本 \(installed ?? "未知")"
        )
    }
}

/// 文字链接（O-03）：依赖行 / 漏洞行的下一步用链接而不是禁用按钮。
private struct TextLinkButton: View {
    var title: String
    var systemImage: String?
    var font: Font
    var help: String?
    var action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        font: Font = AppTheme.callout(12),
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.font = font
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(font)
            }
            .foregroundStyle(AppTheme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel(title)
    }
}

/// 漏洞提示条：与 `GlassNotice` 同材质与降级规则，但需要「说明 + 文字链接
/// （更新到修复版本 / 查看安全详情）」，共享组件只有单按钮动作，故在详情页内保留
/// 一个局部实现。页级的废弃 / 只读 / cask 自动更新提示直接用共享 `GlassNotice`。
private struct DetailNotice: View {
    enum Level {
        case info, warning, danger, success

        var color: Color {
            switch self {
            case .info: return AppTheme.info
            case .warning: return AppTheme.warning
            case .danger: return AppTheme.danger
            case .success: return AppTheme.success
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "exclamationmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }

    var level: Level = .info
    var title: String?
    var message: String
    var linkTitle: String?
    var linkAction: (() -> Void)?
    var secondaryLinkTitle: String?
    var secondaryLinkAction: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: level.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(level.color)

            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(AppTheme.headline(12))
                        .foregroundStyle(AppTheme.text1)
                }
                HStack(spacing: 5) {
                    Text(message)
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let linkTitle, let linkAction {
                        TextLinkButton(title: linkTitle, action: linkAction)
                    }
                }
            }

            Spacer(minLength: 8)

            if let secondaryLinkTitle, let secondaryLinkAction {
                TextLinkButton(title: secondaryLinkTitle, action: secondaryLinkAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { noticeBackground }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var noticeBackground: some View {
        if reduceTransparency {
            // L1 降低透明度：退化为实底 + 描边，避免牺牲可读性（§1.1）。
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.separator, lineWidth: AppMaterial.strokeWidth(for: contrast))
                )
        } else {
            Color.clear
                .glassEffect(.regular.tint(level.color.opacity(0.12)), in: .rect(cornerRadius: 12))
        }
    }
}

/// 卡片内的 warning 行（内容层实底卡片内不再叠玻璃提示条，§1.2）。
private struct InlineWarningRow: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .padding(.top, 1)
            Text(message)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// 依赖方 chip：已安装的可点进详情（文字链接语义），未安装的只作为信息展示。
private struct DependentNameChip: View {
    @Environment(AppState.self) private var appState
    var name: String

    var body: some View {
        let installed = appState.index.package(named: name, kind: .formula)
        Group {
            if let installed {
                Button {
                    appState.selectPackage(installed)
                } label: {
                    ValueChip(text: name, mono: true, color: AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("打开 \(name) 的详情")
                .accessibilityAddTraits(.isLink)
                .accessibilityLabel("打开依赖方 \(name) 的详情")
            } else {
                ValueChip(text: name, mono: true)
                    .help("该依赖方当前未安装，无法打开详情")
                    .accessibilityLabel("\(name)，当前未安装")
            }
        }
    }
}
