import AppKit
import SwiftUI

// MARK: - 概览（ui-design.md v2.0.2 §4.1）
//
// 结构：hero（标题 + 双时间戳 + 主/次操作）→ 4 个指标环 → 安全卡 →
// 最近任务 / 健康 两栏。内容层全部实底卡；玻璃只出现在 notice / 按钮等控制层。
// 页面底部让位由 ContentView 的 safeAreaBar 任务岛负责，这里不再加状态栏。

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    /// 内容列宽度：窄窗时「最近任务 / 健康」从两栏降为单列（§4.7 同规则）。
    @State private var contentWidth: CGFloat = 1000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                statusNotices
                metrics
                if showsHealthyEmptyState {
                    InlineNotice(level: .success, message: "环境健康，没有需要处理的事项。")
                }
                SecurityCardView()
                bottomCards
            }
            .pagePadding()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
        // 概览是「一眼看健康」的页面：维护类只读检查（doctor / missing / 清理预览）
        // 在这里惰性加载一次，AppState 内部按 loadedAt 去重，不会每次切页都重跑。
        .task { await appState.loadMaintenanceIfNeeded() }
        .task { if !appState.servicesLoaded { await appState.loadServices() } }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("概览")
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                Text(heroSubtitle)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(heroSubtitle)
                // P0-02：缓存数据必须标注来源与时间，不能看起来像刚刚检查过。
                if let cachedNote {
                    Text(cachedNote)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button {
                    Task { await appState.checkUpdates() }
                } label: {
                    Label(checkUpdatesTitle, systemImage: "arrow.triangle.2.circlepath")
                }
                .glassSecondaryButton()
                .disabled(checkingUpdates || appState.installation == nil)
                .help("先同步 Homebrew 索引，再检查可更新项（全局 ⌘R）")

                Button {
                    appState.scanVulnerabilities()
                } label: {
                    Label(appState.isScanning ? "扫描中…" : "重新扫描", systemImage: "checkmark.shield")
                }
                .glassSecondaryButton()
                .disabled(appState.isScanning || appState.installation == nil)
                .help("手动运行一次 brew vulns 安全扫描（约 30 秒，不自动触发）")

                Button {
                    // P0-07：批量更新必须先经过确认面板（BatchUpdateSheet），不直接入队。
                    appState.requestBatchUpdate(.all)
                } label: {
                    Text(appState.index.outdated.isEmpty ? "全部更新" : "全部更新 \(appState.index.outdated.count)")
                }
                .glassPrimaryButton()
                .disabled(appState.index.outdated.isEmpty || appState.isReadOnly || appState.isUpgradeAllActive || outdatedUnavailable)
                .help(upgradeAllHelp)
            }
        }
    }

    private var checkUpdatesTitle: String {
        if appState.isSyncingUpstream { return "正在同步…" }
        if appState.isRefreshing { return "正在检查…" }
        return "检查更新"
    }

    private var checkingUpdates: Bool {
        appState.isSyncingUpstream || appState.isRefreshing
    }

    private var upgradeAllHelp: String {
        if appState.isReadOnly { return "只读模式下不可用" }
        if outdatedUnavailable { return "上次检查更新失败，请先点「检查更新」重试" }
        if appState.isUpgradeAllActive { return "已有批量更新正在进行" }
        return "先预览再确认，批量更新全部可更新项"
    }

    /// O-01：两个时间必须分开写，不合并成「已是最新」。
    private var heroSubtitle: String {
        var parts: [String] = [todayText]
        if appState.isSyncingUpstream {
            parts.append("正在同步 Homebrew 索引…")
        } else if let at = appState.lastUpstreamSyncAt {
            parts.append("上游同步于 \(at.relativeText)")
        } else {
            parts.append("尚未同步上游")
        }
        if let at = appState.lastRefreshAt {
            parts.append("本机检查于 \(at.relativeText)\(appState.usesCachedIndex ? "（缓存）" : "")")
        } else {
            parts.append("尚未检查本机")
        }
        return parts.joined(separator: " · ")
    }

    /// 固定 zh-Hans：界面文案 zh 优先，不随系统语言漂移成英文日期。
    private static let dayFormatter: DateFormatter = {        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private var todayText: String {
        Self.dayFormatter.string(from: Date())
    }

    /// 缓存数据来源（§4.2 离线 / 缓存口径）：可更新项来自缓存时优先说明它的检查时间。
    private var cachedNote: String? {
        if appState.outdatedIsCached {
            return "可更新项来自缓存 · 上次检查于 \(appState.outdatedFetchedAt?.relativeText ?? "未知时间")"
        }
        if appState.usesCachedIndex, let note = appState.indexSourceNote, !note.isEmpty {
            return note
        }
        return nil
    }

    // MARK: - 数据来源提示

    /// P0-02：检查更新失败时不能看起来像「0 个更新」；缓存数据要标注时间。
    /// 同屏只出一条 notice（规范 §5：GlassNotice 不叠放）。
    @ViewBuilder
    private var statusNotices: some View {
        if let error = appState.outdatedRefreshError {
            GlassNotice(
                level: .danger,
                title: "检查更新失败",
                message: "\(error)；当前显示上次结果，数量可能不完整",
                actionTitle: "重试",
                action: { Task { await appState.checkUpdates() } }
            )
        } else if let error = appState.refreshError {
            GlassNotice(
                level: .danger,
                title: "读取已安装包失败",
                message: error,
                actionTitle: "重试",
                action: { Task { await appState.checkUpdates() } }
            )
        } else if let error = appState.upstreamSyncError {
            GlassNotice(
                level: .warning,
                title: "未能同步上游",
                message: "\(error)。结果基于 \(appState.lastRefreshAt?.relativeText ?? "上次")的本地索引。",
                actionTitle: "重试",
                action: { Task { await appState.checkUpdates() } }
            )
        }
    }

    // MARK: - 指标环

    /// 索引/更新数据「不可用且无缓存可回退」：此时显示「—」而不是 0。
    private var outdatedUnavailable: Bool {
        (appState.outdatedRefreshError != nil || appState.refreshError != nil)
            && appState.index.outdated.isEmpty
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            outdatedMetric
            vulnerabilityMetric
            diskMetric
            servicesMetric
        }
    }

    private var outdatedMetric: some View {
        let count = appState.index.outdated.count
        let security = appState.index.securityUpdates.count
        let detail: String
        if outdatedUnavailable {
            detail = "检查更新失败"
        } else if count == 0, checkingUpdates, appState.lastRefreshAt == nil {
            detail = "正在读取已安装包…"
        } else if count == 0 {
            detail = "已是最新"
        } else {
            detail = "\(security) 个安全更新"
        }
        return MetricTileCard(
            title: "可更新",
            value: outdatedUnavailable ? "—" : "\(count)",
            detail: detail,
            systemImage: "arrow.down.circle",
            tint: AppTheme.accent,
            progress: outdatedUnavailable ? nil : Double(count) / Double(max(appState.index.packages.count, 1)),
            isLoading: checkingUpdates,
            action: { appState.openSection(.updates) }
        )
        .accessibilityLabel(outdatedUnavailable ? "可更新数量未知，检查更新失败" : "可更新 \(count) 个包")
        .accessibilityHint("打开更新页")
    }

    private var vulnerabilityMetric: some View {
        let hasReport = appState.vulnReport != nil
        let affected = appState.vulnerabilityAffectedCount
        let checked = appState.vulnReport.map { min(max($0.checked, 0), max(appState.scannableFormulaCount, 1)) } ?? 0
        let detail: String
        if hasReport {
            detail = affected == 0
                ? "本次扫描未发现"
                : "\(appState.vulnReport?.totalVulnerabilityCount ?? 0) 条记录 · \(appState.vulnerabilityFixableCount) 个已有修复"
        } else if appState.isScanning {
            detail = "正在扫描…"
        } else if appState.scanError != nil {
            detail = "扫描未知"
        } else {
            detail = "尚未扫描"
        }
        return MetricTileCard(
            title: "有已知漏洞",
            value: hasReport ? "\(affected)" : (appState.isScanning ? "…" : "—"),
            detail: detail,
            systemImage: hasReport && affected == 0 ? "checkmark.shield" : "exclamationmark.shield",
            tint: hasReport ? (affected > 0 ? AppTheme.danger : AppTheme.success) : AppTheme.text3,
            progress: hasReport && checked > 0 ? Double(min(affected, checked)) / Double(checked) : nil,
            isLoading: appState.isScanning,
            action: {
                // 未扫描时资料库的「有已知漏洞」scope 是禁用项，直接落到资料库即可。
                if hasReport {
                    appState.openLibrary(scope: .vulnerable)
                } else {
                    appState.openSection(.library)
                }
            }
        )
        .accessibilityLabel(hasReport
            ? "有已知漏洞 \(affected) 个包"
            : (appState.isScanning ? "正在扫描已知漏洞" : "有已知漏洞数量未知，尚未扫描"))
        .accessibilityHint(hasReport ? "打开资料库并筛选「有已知漏洞」" : "打开资料库")
    }

    private var diskMetric: some View {
        let usage = appState.diskUsage
        let total = [usage.cellarBytes, usage.cacheBytes, usage.caskroomBytes].compactMap { $0 }.reduce(0, +)
        let hasBytes = usage.cellarBytes != nil || usage.cacheBytes != nil || usage.caskroomBytes != nil
        let reclaim = appState.maintenance.cleanupPreview?.reclaimText
        let detail: String
        if hasBytes {
            detail = reclaim.map { "\($0) 可回收" } ?? "可回收空间未知"
        } else {
            detail = usage.isComputing ? "统计中…" : "尚未统计"
        }
        return MetricTileCard(
            title: "占用",
            value: hasBytes ? total.byteCountText : "—",
            detail: detail,
            systemImage: "internaldrive",
            tint: AppTheme.warning,
            progress: hasBytes && total > 0 ? Double(usage.cacheBytes ?? 0) / Double(total) : nil,
            isLoading: usage.isComputing,
            action: { appState.openSection(.maintenance) }
        )
        .accessibilityLabel(hasBytes ? "占用 \(total.byteCountText)，\(detail)" : "占用空间未知")
        .accessibilityHint("打开维护页，查看缓存与旧版本")
    }

    private var servicesMetric: some View {
        let total = appState.services.count
        let running = appState.services.filter { $0.lifecycle == .running }.count
        let errors = appState.services.filter { $0.lifecycle == .error }.count
        let loaded = appState.servicesLoaded
        let detail: String
        if !loaded {
            detail = appState.servicesLoading ? "正在加载…" : "尚未加载"
        } else if errors > 0 {
            detail = "\(errors) 个异常"
        } else if total == 0 {
            detail = "没有已注册服务"
        } else if running == total {
            detail = "全部运行中"
        } else {
            detail = "\(total - running) 个未运行"
        }
        return MetricTileCard(
            title: "服务",
            value: loaded ? "\(running)/\(total)" : "—",
            detail: detail,
            systemImage: "gearshape.2",
            tint: errors > 0 ? AppTheme.danger : (running > 0 ? AppTheme.success : AppTheme.text2),
            progress: loaded && total > 0 ? Double(running) / Double(total) : (loaded ? 0 : nil),
            isLoading: appState.servicesLoading,
            action: { appState.openSection(.services) }
        )
        .accessibilityLabel(loaded ? "服务 \(running)/\(total) 个运行中，\(detail)" : "服务状态尚未加载")
        .accessibilityHint("打开服务页")
    }

    // MARK: - 空态

    /// 规范 §4.1：只有「无更新 + doctor 通过 + 缺失依赖正常」才说环境健康；
    /// 安全卡仍按覆盖率口径单独陈述，不参与这个判断。
    private var showsHealthyEmptyState: Bool {
        guard !outdatedUnavailable, appState.index.outdated.isEmpty else { return false }
        guard let doctor = appState.maintenance.doctorReport,
              doctor.issues.isEmpty,
              appState.maintenance.doctorExitCode == 0 else { return false }
        guard let missing = appState.maintenance.missingReport else { return false }
        return !missing.hasIssues
    }

    // MARK: - 底部两栏

    @ViewBuilder
    private var bottomCards: some View {
        if contentWidth >= 760 {
            HStack(alignment: .top, spacing: 16) {
                RecentTasksCard()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                OverviewHealthCard()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 16) {
                RecentTasksCard()
                OverviewHealthCard()
            }
        }
    }
}

// MARK: - 安全卡（§4.1 / §8）

struct SecurityCardView: View {
    @Environment(AppState.self) private var appState
    @State private var showCoverageDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if appState.isScanning {
                scanningBody
            } else if let report = appState.vulnReport {
                reportBody(report)
            } else {
                unscannedBody
            }
        }
        .cardStyle(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("安全")
    }

    // MARK: 标题行

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text("安全")
                .font(AppTheme.subheading())
                .foregroundStyle(AppTheme.text1)
            Spacer(minLength: 8)
            if appState.isScanning {
                StatusPill(text: "扫描中", color: AppTheme.accent)
            } else if let report = appState.vulnReport {
                if !report.complete {
                    Badge(text: "部分覆盖", color: AppTheme.warning, systemImage: "circle.lefthalf.filled")
                }
                Text(coverageLine(report))
                    .font(AppTheme.caption())
                    .monospacedDigit()
                    .foregroundStyle(isReportOld(report) ? AppTheme.warning : AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .help(coverageTooltip(report))
            } else if appState.scanError != nil {
                Badge(text: "扫描未知", color: AppTheme.warning, systemImage: "questionmark.circle")
            } else {
                Text("尚未扫描")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }

    private func coverageLine(_ report: VulnReport) -> String {
        let total = appState.scannableFormulaCount
        let checked = total > 0 ? min(max(report.checked, 0), total) : report.checked
        let coverage = total > 0 ? "覆盖 \(checked)/\(total)" : "未安装可扫描的 formula"
        return "\(coverage) · 本次扫描 \(report.scannedAt.relativeText)\(appState.vulnReportIsCached ? "（缓存）" : "")"
    }

    private func coverageTooltip(_ report: VulnReport) -> String {
        appState.vulnerabilityCoverageText
    }

    /// 扫描结果超过 24h：时间戳转 warning 色（§4.1 状态）。
    private func isReportOld(_ report: VulnReport) -> Bool {
        Date().timeIntervalSince(report.scannedAt) > 24 * 60 * 60
    }

    // MARK: 扫描中

    private var scanningBody: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if let progress = appState.scanProgress, progress.total > 0, progress.checked > 0 {
                    ProgressView(value: Double(min(progress.checked, progress.total)), total: Double(progress.total))
                        .progressViewStyle(.linear)
                        .accessibilityHidden(true)
                } else {
                    LoadingBar()
                        .accessibilityHidden(true)
                }
                HStack(spacing: 8) {
                    Text(scanStatusText(at: context.date))
                        .font(AppTheme.callout())
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text2)
                        .accessibilityLabel("安全扫描进行中")
                        .accessibilityValue(scanStatusText(at: context.date))
                    Spacer()
                    Button("取消") { appState.cancelScan() }
                        .glassSecondaryButton()
                        .help("停止本次安全扫描，保留上次扫描结果")
                }
                Text("brew vulns 不提供逐包进度；取消后保留上次结果，不会自动重扫。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func scanStatusText(at date: Date) -> String {
        let elapsed = Int(date.timeIntervalSince(appState.scanStartedAt ?? date))
        let time = "已用 \(elapsed) 秒"
        guard let progress = appState.scanProgress, progress.total > 0, progress.checked > 0 else {
            return time + " · 正在解析 brew vulns 输出"
        }
        return "已检查 \(min(progress.checked, progress.total))/\(progress.total) 个 formula · \(time)"
    }

    // MARK: 未扫描 / 扫描失败

    @ViewBuilder
    private var unscannedBody: some View {
        if let error = appState.scanError {
            // 规范 §8：扫描失败显示「扫描未知」，不写「无漏洞」。
            InlineNotice(
                level: .warning,
                title: "扫描未知",
                message: error,
                actionTitle: "重试",
                action: { appState.scanVulnerabilities() }
            )
            Text("全量扫描约需 30 秒；扫描只在你手动点击时运行。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
        } else {
            EmptyStateView(
                systemImage: "checkmark.shield",
                title: "尚未扫描",
                message: "全量扫描约需 30 秒。",
                compact: true,
                actionTitle: "开始扫描"
            ) {
                appState.scanVulnerabilities()
            }
        }
    }

    // MARK: 有结果

    @ViewBuilder
    private func reportBody(_ report: VulnReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // UX O-07：快照已变化 → warning，只给入口，不自动扫描。
            if appState.scanIsStale {
                InlineNotice(
                    level: .warning,
                    message: "已安装的包有变化，扫描结果可能已过时。",
                    actionTitle: "重新扫描",
                    action: { appState.scanVulnerabilities() }
                )
            }

            if let error = appState.scanError {
                InlineNotice(
                    level: .warning,
                    title: "最近一次扫描失败",
                    message: error,
                    actionTitle: "重试",
                    action: { appState.scanVulnerabilities() }
                )
            }

            if report.findings.isEmpty {
                Text("本次扫描未发现受影响包。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.success)
                Text(appState.vulnerabilityCoverageText)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(severitySummary(report))
                        .font(AppTheme.callout())
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text2)
                    Spacer(minLength: 8)
                    Text(fixSummary(report))
                        .font(AppTheme.caption())
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text3)
                }
                SeverityDistributionBar(counts: report.severityCounts)
                affectedChips(report)
            }

            coverageDisclosure(report)
        }
    }

    private func severitySummary(_ report: VulnReport) -> String {
        let counts = report.severityCounts
        let order: [VulnSeverity] = [.critical, .high, .medium, .low]
        let pieces = order.compactMap { severity -> String? in
            guard let count = counts[severity], count > 0 else { return nil }
            return "\(severity.label) \(count)"
        }
        let base = "\(report.affectedFormulaCount) 个受影响包"
        return pieces.isEmpty ? base : base + " · " + pieces.joined(separator: " · ")
    }

    private func fixSummary(_ report: VulnReport) -> String {
        let fixable = report.fixableFindingCount
        let noFix = max(report.affectedFormulaCount - fixable, 0)
        return "已有修复 \(fixable) · 上游暂无修复版本 \(noFix)"
    }

    @ViewBuilder
    private func affectedChips(_ report: VulnReport) -> some View {
        let sorted = report.findings.sorted { $0.worstSeverity > $1.worstSeverity }
        FlowChipsLayout(spacing: 6) {
            ForEach(sorted.prefix(14)) { finding in
                affectedPackageChip(finding)
            }
        }
        if sorted.count > 14 {
            Text("另有 \(sorted.count - 14) 个受影响包")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
        }
    }

    private func affectedPackageChip(_ finding: VulnerabilityFinding) -> some View {
        Button {
            if let package = appState.index.package(named: finding.formula, kind: .formula) {
                appState.selectPackage(package)
                appState.detailTab = .security
            }
        } label: {
            HStack(spacing: 5) {
                Text(finding.formula)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text1)
                SeverityBadge(severity: finding.worstSeverity, compact: true)
                Text(finding.hasFix ? "有修复" : "暂无修复")
                    .font(AppTheme.caption())
                    .foregroundStyle(finding.hasFix ? AppTheme.success : AppTheme.warning)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("打开 \(finding.formula) 的安全详情")
        .accessibilityLabel("\(finding.formula)，\(finding.worstSeverity.label)漏洞，\(finding.hasFix ? "有修复" : "上游暂无修复版本")")
        .accessibilityHint("打开包详情的安全 tab")
    }

    /// 覆盖率口径的展开说明：跳过原因 + 第三方 tap + 退出码 1 属预期。
    private func coverageDisclosure(_ report: VulnReport) -> some View {
        DisclosureGroup(isExpanded: $showCoverageDetails) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.vulnerabilityCoverageText)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text2)
                if !report.skippedFormulae.isEmpty {
                    Text("跳过 \(report.skippedFormulae.count) 个包：\(report.skippedFormulae.prefix(6).joined(separator: "、"))\(report.skippedFormulae.count > 6 ? " 等" : "")")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                if !appState.untrustedTapNames.isEmpty {
                    Text("第三方 tap 不在 OSV 映射范围：\(appState.untrustedTapNames.prefix(5).joined(separator: "、"))\(appState.untrustedTapNames.count > 5 ? " 等" : "")")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                if !report.unscannedFormulae.isEmpty {
                    ForEach(report.unscannedFormulae.keys.sorted().prefix(6), id: \.self) { name in
                        Text("· \(name)：\(report.unscannedFormulae[name] ?? "原因未知")")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                    if report.unscannedFormulae.count > 6 {
                        Text("…另有 \(report.unscannedFormulae.count - 6) 个包未扫描")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                }
                Text("cask 与第三方 tap 不在 OSV 映射范围内；发现漏洞时 brew vulns 退出码可能为 1，属预期，不是扫描失败。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } label: {
            Text(report.complete ? "本次扫描说明" : "为什么是部分覆盖？")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 严重度分布条：只画条，计数文案由安全卡单独排版；VoiceOver 合并朗读。
struct SeverityDistributionBar: View {
    var counts: [VulnSeverity: Int]

    private let order: [VulnSeverity] = [.critical, .high, .medium, .low]

    private var total: Int { order.reduce(0) { $0 + (counts[$1] ?? 0) } }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if total == 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.success.opacity(0.4))
                } else {
                    ForEach(order, id: \.self) { severity in
                        let count = counts[severity] ?? 0
                        if count > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.severity(severity))
                                .frame(width: max(8, proxy.size.width * CGFloat(count) / CGFloat(total)))
                        }
                    }
                }
            }
        }
        .frame(height: 8)
        .background(AppTheme.surface3, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard total > 0 else { return "本次扫描未发现受影响包" }
        let pieces: [String] = order.compactMap { severity in
            guard let count = counts[severity], count > 0 else { return nil }
            return "\(severity.label) \(count)"
        }
        return pieces.joined(separator: "，")
    }
}

// MARK: - 最近任务

struct RecentTasksCard: View {
    @Environment(AppState.self) private var appState

    private var records: [TaskRecord] {
        Array(appState.tasks.records.prefix(4))
    }

    var body: some View {
        SectionCard(title: "最近任务", subtitle: nil, accessory: records.isEmpty ? nil : AnyView(showAllButton)) {
            if records.isEmpty {
                Text("还没有执行过任务。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        recordRow(record)
                        if record.id != records.last?.id {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private var showAllButton: some View {
        Button("全部") {
            appState.tasks.showDrawer = true
        }
        .buttonStyle(.plain)
        .font(AppTheme.caption())
        .foregroundStyle(AppTheme.accent)
        .help("在任务岛中查看全部任务")
        .accessibilityLabel("在任务岛中查看全部任务")
    }

    private func recordRow(_ record: TaskRecord) -> some View {
        Button {
            appState.tasks.openHistoryRecord(record.id)
        } label: {
            HStack(spacing: 8) {
                statusIcon(record.status)
                    .frame(width: 16)
                Text(record.title)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                if record.status == .failed, let exitCode = record.exitCode {
                    Badge(text: "退出码 \(exitCode)", color: AppTheme.danger)
                }
                Spacer(minLength: 8)
                if let duration = record.duration {
                    Text(Self.durationText(duration))
                        .font(AppTheme.mono())
                        .foregroundStyle(AppTheme.text3)
                }
                Text(record.createdAt.relativeText)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("在任务岛中查看这次任务的日志")
        .accessibilityLabel("\(record.title)，\(record.status.label)，\(record.createdAt.relativeText)")
        .accessibilityHint("在任务岛中查看日志")
    }

    @ViewBuilder
    private func statusIcon(_ status: TaskRecord.Status) -> some View {
        switch status {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.success)
        case .failed, .interrupted:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.danger)
        case .unverified:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.text3)
        case .running, .cancelling:
            ProgressView().controlSize(.mini)
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
        }
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - 健康卡

/// 概览健康卡：只给「结论 + 一个入口」，完整诊断在维护页。
private struct OverviewHealthCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SectionCard(title: "健康", subtitle: nil, accessory: nil) {
            VStack(spacing: 0) {
                doctorRow
                Hairline()
                missingRow
                Hairline()
                reclaimRow
                Hairline()
                autoremoveRow
            }
        }
    }

    private var doctorRow: some View {
        let maintenance = appState.maintenance
        if maintenance.doctorLoading {
            return healthRow(icon: nil, color: AppTheme.text3, text: "正在运行 brew doctor…", pending: false)
        }
        if let error = maintenance.doctorError {
            return healthRow(icon: "xmark.octagon", color: AppTheme.danger, text: "brew doctor 运行失败：\(short(error))", pending: true)
        }
        guard let report = maintenance.doctorReport else {
            return healthRow(icon: "minus.circle", color: AppTheme.text3, text: "尚未运行诊断", pending: false)
        }
        if report.issues.isEmpty, maintenance.doctorExitCode == 0 {
            return healthRow(icon: "checkmark.circle", color: AppTheme.success, text: "brew doctor 未发现需要处理的事项", pending: false)
        }
        if report.issues.isEmpty {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "brew doctor 退出码 \(maintenance.doctorExitCode ?? 0)，未能完成诊断", pending: true)
        }
        return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "brew doctor \(report.issues.count) 条提示", pending: true)
    }

    private var missingRow: some View {
        let maintenance = appState.maintenance
        if maintenance.missingLoading {
            return healthRow(icon: nil, color: AppTheme.text3, text: "正在检查缺失依赖…", pending: false)
        }
        if maintenance.missingError != nil {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "brew missing 检查失败", pending: true)
        }
        guard let report = maintenance.missingReport else {
            return healthRow(icon: "minus.circle", color: AppTheme.text3, text: "尚未检查缺失依赖", pending: false)
        }
        if report.hasIssues {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "\(report.entries.count) 个包缺少依赖", pending: true)
        }
        if let exitCode = maintenance.missingExitCode, exitCode != 0 {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "brew missing 退出码 \(exitCode)", pending: true)
        }
        return healthRow(icon: "checkmark.circle", color: AppTheme.success, text: "brew missing 未发现缺失依赖", pending: false)
    }

    private var reclaimRow: some View {
        let maintenance = appState.maintenance
        if maintenance.cleanupLoading {
            return healthRow(icon: nil, color: AppTheme.text3, text: "正在预览可回收空间…", pending: false)
        }
        if maintenance.cleanupPreviewFailed {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "清理预览失败，无法确认可回收空间", pending: true)
        }
        guard let preview = maintenance.cleanupPreview else {
            return healthRow(icon: "minus.circle", color: AppTheme.text3, text: "可回收空间尚未统计", pending: false)
        }
        if let reclaim = preview.reclaimText {
            return healthRow(icon: "arrow.counterclockwise.circle", color: AppTheme.warning, text: "可回收 \(reclaim) 缓存与旧版本", pending: true)
        }
        return healthRow(icon: "checkmark.circle", color: AppTheme.success, text: "缓存与旧版本无可回收", pending: false)
    }

    private var autoremoveRow: some View {
        let maintenance = appState.maintenance
        if maintenance.autoremoveLoading {
            return healthRow(icon: nil, color: AppTheme.text3, text: "正在检查孤立依赖…", pending: false)
        }
        if maintenance.autoremoveError != nil {
            return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "孤立依赖检查失败", pending: true)
        }
        guard let preview = maintenance.autoremovePreview else {
            return healthRow(icon: "minus.circle", color: AppTheme.text3, text: "尚未检查孤立依赖", pending: false)
        }
        if preview.packages.isEmpty {
            return healthRow(icon: "checkmark.circle", color: AppTheme.success, text: "未发现可自动移除的孤立依赖", pending: false)
        }
        return healthRow(icon: "exclamationmark.triangle", color: AppTheme.warning, text: "\(preview.packages.count) 个孤立依赖", pending: true)
    }

    /// `icon == nil` 时用 spinner；整行可点 → 维护页。
    private func healthRow(icon: String?, color: Color, text: String, pending: Bool) -> some View {
        Button {
            appState.openSection(.maintenance)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .frame(width: 16)
                Text(text)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if pending {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.text3)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开维护页查看详情")
        .accessibilityLabel(text)
        .accessibilityHint("打开维护页")
    }

    private func short(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > 42 ? String(line.prefix(42)) + "…" : line
    }
}

// MARK: - Flow layout for chips

struct FlowChipsLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
