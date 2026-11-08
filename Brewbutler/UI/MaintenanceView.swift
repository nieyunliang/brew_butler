import SwiftUI

// MARK: - 维护（ui-design.md v2.0.2 §4.7）
//
// UX O-09：页面顶部只放「需要处理」的问题卡（doctor 有提示 / missing 非空 /
// 可回收 > 500 MB / 有孤立依赖），其余收进「一切正常」折叠区；全部正常时
// 显示 ContentUnavailableView，并把 Brewfile 与目录信息留在折叠区内。
// 清理与移除孤立依赖都先 dry-run 预览再进入确认弹层，绝不自动执行。

struct MaintenanceView: View {
    @Environment(AppState.self) private var appState
    @State private var showCleanupPreviewList = false
    @State private var showDoctorRaw = false
    @State private var showCleanupRaw = false
    @State private var healthyExpanded = true
    @State private var contentWidth: CGFloat = 1000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if pendingCount > 0 {
                    pendingSection
                } else if healthyDataReady {
                    healthyEmptyState
                }
                healthySection
            }
            .pagePadding()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
        .task {
            await appState.loadMaintenanceIfNeeded()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("维护")
                    .font(AppTheme.display())
                    .foregroundStyle(AppTheme.text1)
                Text(subtitle)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button {
                    Task { await appState.loadMaintenanceIfNeeded(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.triangle.2.circlepath")
                }
                .glassSecondaryButton()
                .disabled(isRefreshingMaintenance)
                .help("重新运行 doctor / missing / 清理预览 / 孤立依赖检查")

                Button {
                    Task { await appState.runDoctor() }
                } label: {
                    Label(appState.maintenance.doctorLoading ? "诊断中…" : "运行诊断", systemImage: "stethoscope")
                }
                .glassPrimaryButton()
                .disabled(appState.maintenance.doctorLoading || appState.installation == nil)
                .help("运行 brew doctor（可能需要几秒到数十秒）")
            }
        }
    }

    private var isRefreshingMaintenance: Bool {
        appState.maintenance.doctorLoading
            || appState.maintenance.missingLoading
            || appState.maintenance.cleanupLoading
            || appState.maintenance.autoremoveLoading
            || appState.diskUsage.isComputing
    }

    private var subtitle: String {
        if appState.maintenance.loadedAt == nil, isRefreshingMaintenance {
            return "正在检查维护状态…"
        }
        var parts: [String] = ["\(pendingCount) 项需要处理"]
        if appState.maintenance.doctorLoading {
            parts.append("doctor 运行中…")
        } else if let report = appState.maintenance.doctorReport {
            parts.append("doctor \(report.issues.count) 条提示")
        } else {
            parts.append("doctor 未检查")
        }
        parts.append("\(autoremoveCount) 个孤立依赖")
        return parts.joined(separator: " · ")
    }

    // MARK: - 分类

    private var doctorIssueCount: Int {
        appState.maintenance.doctorReport?.issues.count ?? 0
    }

    private var missingIssueCount: Int {
        appState.maintenance.missingReport?.entries.count ?? 0
    }

    private var autoremoveCount: Int {
        appState.maintenance.autoremovePreview?.packages.count ?? 0
    }

    /// 可回收字节：cleanup 预览已给出精确值时用它；预览已跑完但没给数字，
    /// 说明没有可清理项（不能拿缓存占用冒充「可回收」）。预览尚未结果时才退回缓存下界。
    private var reclaimBytes: Int64? {
        if let preview = appState.maintenance.cleanupPreview {
            guard let text = preview.reclaimText else { return 0 }
            // 无法解析的文案不猜：退回缓存占用下界，避免把「大缓存」误判成「无可回收」。
            return Self.byteCount(from: text) ?? appState.diskUsage.cacheBytes
        }
        return appState.diskUsage.cacheBytes
    }

    /// doctor 异常 / 缺失依赖属于「需要处理」；可回收 ≤ 500 MB 视为正常。
    private var healthPending: Bool {
        if appState.maintenance.doctorError != nil || appState.maintenance.missingError != nil { return true }
        if let code = appState.maintenance.doctorExitCode, code != 0 { return true }
        if let code = appState.maintenance.missingExitCode, code != 0 { return true }
        return doctorIssueCount > 0 || missingIssueCount > 0
    }

    private var cleanupPending: Bool {
        appState.maintenance.cleanupPreviewFailed || (reclaimBytes ?? 0) > 500 * 1024 * 1024
    }

    private var autoremovePending: Bool {
        autoremoveCount > 0 || appState.maintenance.autoremoveError != nil
    }

    private var pendingCount: Int {
        [healthPending, cleanupPending, autoremovePending].filter { $0 }.count
    }

    /// 只有本轮检查真的跑完（doctor / missing 都有结论）才允许说「环境健康」，
    /// 加载中或首次检查失败时不能用空态冒充结论。
    private var healthyDataReady: Bool {
        appState.maintenance.loadedAt != nil
            && appState.maintenance.doctorReport != nil
            && appState.maintenance.missingReport != nil
            && !isRefreshingMaintenance
    }

    private var normalCardNames: [String] {
        var names: [String] = []
        if !cleanupPending { names.append("缓存与旧版本") }
        if !healthPending { names.append("Homebrew 健康") }
        if !autoremovePending { names.append("孤立依赖") }
        names.append("Brewfile")
        names.append("已锁定")
        names.append("Homebrew 目录")
        return names
    }

    private var columns: [GridItem] {
        if contentWidth >= 780 {
            return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        }
        return [GridItem(.flexible())]
    }

    // MARK: - 需要处理

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                Text("需要处理 · \(pendingCount)")
                    .font(AppTheme.headline(13))
                    .foregroundStyle(AppTheme.text1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("需要处理 \(pendingCount) 项")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                if healthPending { homebrewHealthCard }
                if cleanupPending { cleanupCard }
                if autoremovePending { autoremoveCard }
            }
        }
    }

    private var healthyEmptyState: some View {
        ContentUnavailableView {
            Label("环境健康，没有需要处理的事项。", systemImage: "checkmark.circle")
        } description: {
            Text("下方保留 Brewfile 与 Homebrew 目录信息；随时可以运行诊断复查。")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - 一切正常

    private var healthySection: some View {
        DisclosureGroup(isExpanded: $healthyExpanded) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                if !cleanupPending { cleanupCard }
                if !healthPending { homebrewHealthCard }
                if !autoremovePending { autoremoveCard }
                brewfileCard
                pinnedCard
                directoriesCard
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                if healthyDataReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.success)
                    Text("一切正常 · \(normalCardNames.count)")
                        .font(AppTheme.headline(13))
                        .foregroundStyle(AppTheme.text1)
                    Text(normalCardNames.joined(separator: " · "))
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                } else {
                    ProgressView().controlSize(.mini)
                    Text("正在检查维护状态…")
                        .font(AppTheme.headline(13))
                        .foregroundStyle(AppTheme.text1)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(healthyDataReady
            ? "一切正常 \(normalCardNames.count) 项：\(normalCardNames.joined(separator: "，"))"
            : "正在检查维护状态")
    }

    // MARK: - Homebrew 健康

    private var homebrewHealthCard: some View {
        SectionCard(
            title: "Homebrew 健康",
            subtitle: doctorSubtitle,
            accessory: healthAccessory
        ) {
            VStack(alignment: .leading, spacing: 8) {
                doctorContent
                Hairline()
                missingContent
                if appState.maintenance.doctorReport != nil {
                    HStack(spacing: 8) {
                        Button("复制诊断摘要") { copyDoctorSummary() }
                            .glassSecondaryButton()
                            .help("把 doctor 结论、退出码与建议命令复制为文本")
                        Spacer(minLength: 0)
                    }
                }
                if let report = appState.maintenance.doctorReport {
                    rawOutputDisclosure(
                        title: "查看 brew doctor 原始输出",
                        text: report.raw,
                        isExpanded: $showDoctorRaw
                    )
                }
            }
        }
    }

    private var healthAccessory: AnyView? {
        if appState.maintenance.doctorLoading { return nil }
        if doctorIssueCount > 0 {
            return AnyView(Badge(text: "\(doctorIssueCount) 条提示", color: AppTheme.warning, systemImage: "exclamationmark.triangle"))
        }
        if let code = appState.maintenance.doctorExitCode, code != 0 {
            return AnyView(Badge(text: "退出码 \(code)", color: AppTheme.warning))
        }
        return nil
    }

    private var doctorSubtitle: String? {
        if appState.maintenance.doctorLoading { return "运行中…" }
        guard let report = appState.maintenance.doctorReport else { return nil }
        if report.issues.isEmpty {
            return appState.maintenance.doctorExitCode == 0 ? "正常" : "有异常"
        }
        return "\(report.issues.count) 条提示"
    }

    @ViewBuilder
    private var doctorContent: some View {
        if appState.maintenance.doctorLoading {
            Label("正在运行 brew doctor…", systemImage: "hourglass")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
        } else if let report = appState.maintenance.doctorReport {
            if let exitCode = appState.maintenance.doctorExitCode, exitCode != 0, report.issues.isEmpty {
                Label("doctor 退出码 \(exitCode)：未能解析出具体问题。", systemImage: "exclamationmark.triangle")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.warning)
            } else if report.issues.isEmpty {
                Label("doctor 未发现问题。", systemImage: "checkmark.circle")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.success)
            } else {
                doctorIssueGroups(report)
            }
        } else if let error = appState.maintenance.doctorError {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重新运行诊断") {
                    Task { await appState.runDoctor() }
                }
                .glassSecondaryButton()
            }
        } else {
            Text("尚未运行诊断。")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
        }
    }

    @ViewBuilder
    private func doctorIssueGroups(_ report: DoctorReport) -> some View {
        let permissionIssues = report.issues.filter(\.isPermissionIssue)
        let otherIssues = report.issues.filter { !$0.isPermissionIssue }
        if !permissionIssues.isEmpty {
            Text("权限相关（\(permissionIssues.count)）")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            ForEach(permissionIssues.prefix(4)) { issue in
                doctorIssueRow(issue)
            }
        }
        if !otherIssues.isEmpty {
            if !permissionIssues.isEmpty {
                Text("其他问题（\(otherIssues.count)）")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .padding(.top, 2)
            }
            ForEach(otherIssues.prefix(4)) { issue in
                doctorIssueRow(issue)
            }
        }
        let hidden = max(0, report.issues.count - permissionIssues.prefix(4).count - otherIssues.prefix(4).count)
        if hidden > 0 {
            Text("另有 \(hidden) 条提示")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
        }
    }

    @ViewBuilder
    private func doctorIssueRow(_ issue: DoctorIssue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: issue.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(issue.level == .error ? AppTheme.danger : AppTheme.warning)
                Text(issue.title)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(issue.level == .error ? "错误" : "警告")
                    .font(AppTheme.caption())
                    .foregroundStyle(issue.level == .error ? AppTheme.danger : AppTheme.warning)
            }
            ForEach(issue.suggestedCommands.prefix(2), id: \.self) { command in
                HStack(spacing: 6) {
                    ValueChip(text: command, mono: true, color: AppTheme.accent)
                    Button("复制") { copy(command) }
                        .glassSecondaryButton()
                        .help("复制该修复命令")
                }
                .padding(.leading, 18)
            }
            if issue.isPermissionIssue {
                Text("权限不足：确认目录所有权，或按上方命令修复。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var missingContent: some View {
        if appState.maintenance.missingLoading {
            Label("正在检查缺失依赖…", systemImage: "hourglass")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
        } else if let error = appState.maintenance.missingError {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重新检查缺失依赖") {
                    Task { await appState.checkMissing() }
                }
                .glassSecondaryButton()
            }
        } else if let missing = appState.maintenance.missingReport {
            if missing.hasIssues {
                Text("缺失依赖（\(missing.entries.count)）")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                ForEach(missing.entries, id: \.package) { entry in
                    missingEntryRow(entry)
                }
            } else if let exitCode = appState.maintenance.missingExitCode, exitCode != 0 {
                Label("brew missing 退出码 \(exitCode)：未能解析出缺失项。", systemImage: "exclamationmark.triangle")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.warning)
            } else {
                Label("brew missing 检查通过。", systemImage: "checkmark.circle")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.success)
            }
        } else {
            Text("尚未检查缺失依赖。")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text2)
        }
    }

    @ViewBuilder
    private func missingEntryRow(_ entry: MissingEntry) -> some View {
        if let package = appState.index.package(named: entry.package, kind: .formula)
            ?? appState.index.package(named: entry.package, kind: .cask) {
            Button {
                appState.selectPackage(package)
            } label: {
                HStack(spacing: 6) {
                    Text(entry.package)
                        .font(AppTheme.mono(11.5))
                        .foregroundStyle(AppTheme.text1)
                    Text("缺少 \(entry.missing.joined(separator: ", "))")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开 \(entry.package) 的详情")
        } else {
            Text("\(entry.package)：缺少 \(entry.missing.joined(separator: ", "))")
                .font(AppTheme.mono(11.5))
                .foregroundStyle(AppTheme.warning)
        }
    }

    // MARK: - 缓存与旧版本

    private var cleanupCard: some View {
        SectionCard(title: "缓存与旧版本", subtitle: cleanupSubtitle, accessory: nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(reclaimValueText)
                        .font(AppTheme.statValue(24))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text1)
                    Text(cleanupBreakdown)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                if appState.maintenance.cleanupLoading {
                    Label("正在预览可清理项…", systemImage: "hourglass")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                } else if appState.maintenance.cleanupPreviewFailed {
                    Label("预览失败，无法确认可清理内容。", systemImage: "exclamationmark.triangle")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.danger)
                    if let error = appState.maintenance.cleanupError {
                        Text(error)
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    rawOutputDisclosure(
                        title: "查看 brew cleanup -n 原始输出",
                        text: appState.maintenance.cleanupRawText,
                        isExpanded: $showCleanupRaw
                    )
                    Button("重试预览") {
                        Task { await appState.previewCleanup(presentSheet: false) }
                    }
                    .glassSecondaryButton()
                } else if let preview = appState.maintenance.cleanupPreview {
                    if preview.isEmpty {
                        Label("没有可清理的内容，环境很干净。", systemImage: "checkmark.circle")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.success)
                    } else {
                        cleanupRemovalList(preview)
                    }
                } else if let error = appState.maintenance.cleanupError {
                    Text(error)
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.danger)
                }

                HStack(spacing: 8) {
                    Button(showCleanupPreviewList ? "收起预览" : "预览") {
                        previewCleanupList()
                    }
                    .glassSecondaryButton()
                    .disabled(
                        appState.maintenance.cleanupLoading
                            || appState.maintenance.cleanupPreviewFailed
                            || (appState.maintenance.cleanupPreview?.isEmpty ?? true)
                    )

                    Button("清理…") {
                        Task { await appState.previewCleanup(presentSheet: true) }
                    }
                    .glassPrimaryButton()
                    .disabled(
                        appState.maintenance.cleanupLoading
                            || appState.maintenance.cleanupPreviewFailed
                            || appState.isReadOnly
                    )
                    .help(
                        appState.maintenance.cleanupPreviewFailed
                            ? "预览失败时不会执行清理；请先重试预览并确认可清理内容。"
                            : "先预览可清理项，再确认执行。"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func cleanupRemovalList(_ preview: CleanupPreview) -> some View {
        Text("可移除 \(preview.removals.count) 项\(preview.reclaimText.map { "，释放 \($0)" } ?? "")")
            .font(AppTheme.callout())
            .foregroundStyle(AppTheme.text2)
        if showCleanupPreviewList {
            ForEach(preview.removals.prefix(8), id: \.path) { removal in
                VStack(alignment: .leading, spacing: 1) {
                    Text(removal.path)
                        .font(AppTheme.mono())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // D-22：清理项要带体积/版本等估算信息，否则用户无法判断值不值得清。
                    if let detail = removal.detail, !detail.isEmpty {
                        Text(detail)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                }
            }
            if preview.removals.count > 8 {
                Text("…另有 \(preview.removals.count - 8) 项")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }

    private var cleanupSubtitle: String? {
        if appState.maintenance.cleanupLoading { return "预览中…" }
        guard let preview = appState.maintenance.cleanupPreview else { return nil }
        return preview.reclaimText.map { "\($0) 可回收" }
    }

    private var reclaimValueText: String {
        if appState.maintenance.cleanupLoading { return "…" }
        if let reclaim = appState.maintenance.cleanupPreview?.reclaimText { return reclaim }
        if let cache = appState.diskUsage.cacheBytes { return cache.byteCountText }
        return "—"
    }

    private var cleanupBreakdown: String {
        var parts: [String] = []
        if let cache = appState.diskUsage.cacheBytes {
            parts.append("缓存 \(cache.byteCountText)")
        }
        if let reclaim = reclaimBytes, let cache = appState.diskUsage.cacheBytes, reclaim > cache {
            parts.append("旧版本 \((reclaim - cache).byteCountText)")
        }
        if parts.isEmpty {
            parts.append(appState.diskUsage.isComputing ? "正在统计磁盘占用…" : "磁盘占用尚未统计")
        }
        return parts.joined(separator: " · ")
    }

    private func previewCleanupList() {
        if appState.maintenance.cleanupPreview == nil {
            Task { await appState.previewCleanup(presentSheet: false) }
            showCleanupPreviewList = true
        } else {
            showCleanupPreviewList.toggle()
        }
    }

    // MARK: - 孤立依赖

    private var autoremoveCard: some View {
        SectionCard(title: "孤立依赖", subtitle: autoremoveSubtitle, accessory: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if appState.maintenance.autoremoveLoading {
                    Label("正在检测孤立依赖…", systemImage: "hourglass")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                } else if let preview = appState.maintenance.autoremovePreview {
                    if preview.packages.isEmpty {
                        Label("没有可自动移除的孤立依赖。", systemImage: "checkmark.circle")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.success)
                    } else {
                        Text("\(preview.packages.count) 个包已不再被任何已安装包需要")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text2)
                        FlowChipsLayout(spacing: 6) {
                            ForEach(preview.packages.prefix(12), id: \.self) { name in
                                ValueChip(text: name, mono: true)
                            }
                        }
                        if preview.packages.count > 12 {
                            Text("…另有 \(preview.packages.count - 12) 个")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                    }
                } else if let error = appState.maintenance.autoremoveError {
                    Text(error)
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("预览") {
                        Task { await appState.previewAutoremove(presentSheet: false) }
                    }
                    .glassSecondaryButton()
                    .disabled(appState.maintenance.autoremoveLoading)
                    .help("运行 brew autoremove --dry-run 预览，不会执行移除")

                    Button("移除…") {
                        Task { await appState.previewAutoremove(presentSheet: true) }
                    }
                    .glassSecondaryButton()
                    .disabled(appState.maintenance.autoremoveLoading || appState.isReadOnly)
                    .help("先 dry-run 预览，再在确认弹层中执行 brew autoremove")
                }
            }
        }
    }

    private var autoremoveSubtitle: String? {
        if appState.maintenance.autoremoveLoading { return "检测中…" }
        guard let preview = appState.maintenance.autoremovePreview else { return nil }
        return preview.packages.isEmpty ? "无" : "\(preview.packages.count) 个包不再被需要"
    }

    // MARK: - Brewfile

    private var brewfileCard: some View {
        SectionCard(
            title: "Brewfile",
            subtitle: appState.settings.lastBrewfileExport.isEmpty ? "尚未导出" : "上次导出 \(appState.settings.lastBrewfileExport)",
            accessory: nil
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Brewfile 包含当前已安装的 formula、cask 与 tap，可用于在新机器上恢复环境。")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                if let error = appState.brewfileExportError {
                    InlineNotice(level: .danger, title: "导出失败", message: error, actionTitle: "重试导出") {
                        appState.exportBrewfile()
                    }
                }
                HStack(spacing: 8) {
                    Button("导出…") { appState.exportBrewfile() }
                        .glassSecondaryButton()
                    Button("导入…") { appState.chooseBrewfileToImport() }
                        .glassSecondaryButton()
                        .disabled(appState.isReadOnly)
                    if !appState.settings.lastBrewfileExport.isEmpty {
                        Button("在 Finder 中显示") { appState.revealBrewfileExport() }
                            .glassSecondaryButton()
                    }
                }
            }
        }
    }

    // MARK: - 已锁定的包

    private var pinnedCard: some View {
        let pinned = appState.index.packages.filter(\.pinned)
        return SectionCard(title: "已锁定的包", subtitle: pinned.isEmpty ? "无" : "\(pinned.count) 个", accessory: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if pinned.isEmpty {
                    Text("锁定的包不会被 brew upgrade 更新。在包详情页可以锁定。")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                } else {
                    ForEach(pinned) { package in
                        HStack(spacing: 8) {
                            Text(package.displayName)
                                .font(AppTheme.mono(11.5))
                                .foregroundStyle(AppTheme.text1)
                            Text(package.installedVersion ?? "")
                                .font(AppTheme.mono())
                                .foregroundStyle(AppTheme.text3)
                            if package.kind == .cask, package.autoUpdates == true {
                                Badge(text: "auto_updates", color: AppTheme.warning)
                            }
                            Spacer()
                            // D-22 / B-14：cask 与 formula 同口径可解锁；
                            // auto_updates cask 需说明「解锁也不一定能 brew upgrade」。
                            Button("解锁") { appState.setPinned(package, pinned: false) }
                                .glassSecondaryButton()
                                .help(
                                    package.kind == .cask
                                        ? "解除锁定。auto_updates 的 cask 由应用自行更新，brew upgrade 仍可能跳过它。"
                                        : "解除锁定，允许 brew upgrade 更新。"
                                )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Homebrew 目录

    private var directoriesCard: some View {
        SectionCard(title: "Homebrew 目录", subtitle: nil, accessory: nil) {
            VStack(alignment: .leading, spacing: 4) {
                if let installation = appState.installation {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                        alignment: .leading,
                        spacing: 0
                    ) {
                        directoryRow(label: "前缀", value: installation.prefix, mono: true)
                        directoryRow(label: "Cellar", value: installation.cellar, mono: true)
                        directoryRow(label: "缓存", value: installation.cache.isEmpty ? "—" : installation.cache, mono: true)
                        directoryRow(label: "Caskroom", value: appState.diskUsage.caskroomBytes?.byteCountText ?? "—", mono: false)
                        directoryRow(label: "已安装", value: "\(appState.scannableFormulaCount) formula · \(appState.caskCount) cask", mono: true)
                        directoryRow(label: "Cellar 占用", value: appState.diskUsage.cellarBytes?.byteCountText ?? "—", mono: false)
                    }
                    HStack(spacing: 8) {
                        if let computedAt = appState.diskUsage.computedAt {
                            Text("统计于 \(computedAt.relativeText)")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        } else if appState.diskUsage.isComputing {
                            Text("正在统计…")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                        Spacer()
                        Button("重新统计") {
                            Task { await appState.computeDiskUsage() }
                        }
                        .glassSecondaryButton()
                        .disabled(appState.diskUsage.isComputing)
                    }
                    .padding(.top, 6)
                } else {
                    Text("Homebrew 未就绪。")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.text2)
                }
            }
        }
    }

    private func directoryRow(label: String, value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(mono ? AppTheme.mono(11.5) : AppTheme.callout())
                .foregroundStyle(AppTheme.text1)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(value)")
    }

    // MARK: - 原始输出

    @ViewBuilder
    private func rawOutputDisclosure(title: String, text: String?, isExpanded: Binding<Bool>) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                DisclosureGroup(isExpanded: isExpanded) {
                    ScrollView {
                        Text(text)
                            .font(AppTheme.mono(11))
                            .foregroundStyle(AppTheme.text2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(maxHeight: 140)
                    .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } label: {
                    Text(title)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                Button("复制原文") { copyRaw(text) }
                    .glassSecondaryButton()
            }
        }
    }

    // MARK: - Helpers

    private func copy(_ text: String) {
        copyToPasteboard(text)
        appState.showToast("已复制命令", kind: .success)
    }

    private func copyRaw(_ text: String) {
        copyToPasteboard(text)
        appState.showToast("已复制原文", kind: .success)
    }

    /// 诊断摘要：doctor 结论 + 退出码 + 缺失依赖，用于贴到 issue / 自检。
    private func copyDoctorSummary() {
        guard let report = appState.maintenance.doctorReport else { return }
        var lines = [
            "Homebrew 健康检查摘要",
            "问题：\(report.issues.count) 条",
            "退出码：\(appState.maintenance.doctorExitCode.map(String.init) ?? "—")",
        ]
        for issue in report.issues {
            lines.append("- [\(issue.level == .error ? "错误" : "提示")] \(issue.title)")
            if !issue.detail.isEmpty { lines.append("  详情：\(issue.detail)") }
            if !issue.suggestedCommands.isEmpty {
                lines.append("  建议：\(issue.suggestedCommands.joined(separator: "；"))")
            }
        }
        if let missing = appState.maintenance.missingReport, missing.hasIssues {
            lines.append("缺失依赖：\(missing.entries.count) 个包")
        }
        copyToPasteboard(lines.joined(separator: "\n"))
        appState.showToast("诊断摘要已复制", kind: .success)
    }

    /// brew 的可回收文案形如 `485.3MB` / `1.2GB`（无空格）；用于「> 500 MB」分类。
    static func byteCount(from text: String) -> Int64? {
        let cleaned = text.replacingOccurrences(of: " ", with: "").uppercased()
        let units: [(String, Double)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1024),
            ("B", 1),
        ]
        for (unit, multiplier) in units where cleaned.hasSuffix(unit) {
            let number = String(cleaned.dropLast(unit.count))
            if let value = Double(number) { return Int64(value * multiplier) }
        }
        return nil
    }
}
