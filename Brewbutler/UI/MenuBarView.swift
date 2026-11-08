import AppKit
import SwiftUI

/// 规范 §4.13：`MenuBarExtra(.window)` popover（系统玻璃）。
///
/// 设计约束（UX 方案 O-12）：
/// - 只做「看一眼 + 回主窗口」，不提供「全部更新」之类批量变更——批量变更
///   必须回主窗口走确认弹层（§4.10），菜单栏里永远不出现批量按钮。
/// - 最多列 3 个安全更新；点击直接打开主窗口并进入该包详情。
/// - 当前任务一行，点击展开任务岛（`tasks.showDrawer`）并回主窗口。
/// - 入口固定为：打开主窗口 / 检查更新 / 运行扫描 / 退出。
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// 规范 §4.13：菜单栏宽度 300–320、内边距 14。
    private let panelWidth: CGFloat = 320
    private let panelPadding: CGFloat = 14
    /// O-12：popover 里最多列 3 个安全更新，其余回主窗口看。
    private let maxSecurityRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary

            if appState.installation == nil {
                brewMissingHint
            } else if !securityEntries.isEmpty {
                securitySection
            }

            if let record = appState.tasks.displayedRecord {
                taskRow(record)
            }

            Hairline()
            actions
            Hairline()
            footer
        }
        .padding(panelPadding)
        .frame(width: panelWidth)
    }

    // MARK: - Header & summary

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "mug.fill")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.accent)
            Text("Brewbutler")
                .font(AppTheme.headline())
                .foregroundStyle(AppTheme.text1)
            Spacer(minLength: 8)
            if appState.tasks.isRunning {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("有任务正在运行")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appState.tasks.isRunning ? "Brewbutler，有任务正在运行" : "Brewbutler")
    }

    @ViewBuilder
    private var summary: some View {
        if appState.installation == nil {
            Text("未检测到 Homebrew")
                .font(AppTheme.headline(13))
                .foregroundStyle(AppTheme.danger)
        } else if appState.index.packages.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取已安装包…")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
            }
        } else if appState.index.outdated.isEmpty {
            // P0-02：上次检查失败时不能写成「所有包都是最新版本」。
            if appState.outdatedRefreshError != nil {
                Text("未能检查更新")
                    .font(AppTheme.headline(13))
                    .foregroundStyle(AppTheme.warning)
            } else {
                Text("所有包都是最新版本。")
                    .font(AppTheme.headline(13))
                    .foregroundStyle(AppTheme.text1)
            }
        } else {
            countsLine
        }

        if let statusText {
            Text(statusText)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .lineLimit(1)
        }
    }

    /// 顶部固定句式：「N 个可用更新 · M 个安全更新」（§4.13）。
    private var countsLine: some View {
        let outdated = appState.index.outdated.count
        let security = appState.index.securityUpdates.count
        return HStack(spacing: 5) {
            Text("\(outdated) 个可用更新")
                .font(AppTheme.headline(13))
                .foregroundStyle(AppTheme.text1)
                .monospacedDigit()
            Text("·")
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text3)
            Text(security > 0 ? "\(security) 个安全更新" : "0 个安全更新")
                .font(AppTheme.callout(12))
                .foregroundStyle(security > 0 ? AppTheme.warning : AppTheme.text2)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(outdated) 个可用更新，\(security) 个安全更新")
    }

    /// 数据新鲜度：同步 / 刷新中优先，否则给上次检查时间，避免「看起来是 0」。
    private var statusText: String? {
        if appState.isSyncingUpstream {
            return "正在同步 Homebrew 索引…"
        }
        if appState.isRefreshing {
            return "正在检查更新…"
        }
        if appState.installation == nil {
            // 缺失说明由 body 里的 brewMissingHint 统一承担，避免重复两遍。
            return nil
        }
        if appState.outdatedRefreshError != nil {
            return "上次检查更新失败，回主窗口重试。"
        }
        if let lastRefreshAt = appState.lastRefreshAt {
            return "上次检查 \(lastRefreshAt.relativeText)"
        }
        return nil
    }

    private var brewMissingHint: some View {
        Text("打开主窗口指定 brew 路径或重新检测；Brewbutler 不会自动安装，也不代输管理员密码。")
            .font(AppTheme.caption())
            .foregroundStyle(AppTheme.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Security updates（最多 3 行）

    /// 按严重度降序取前 3 个；与更新页同源（`index.securityUpdates`）。
    private var securityEntries: [OutdatedEntry] {
        appState.index.securityUpdates
            .sorted { ($0.severity ?? .unknown).rank > ($1.severity ?? .unknown).rank }
            .prefix(maxSecurityRows)
            .map { $0 }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("安全更新")
                    .font(AppTheme.caption())
                    .captionTracking()
                    .foregroundStyle(AppTheme.text3)
                Spacer(minLength: 8)
            }

            ForEach(securityEntries) { entry in
                securityRow(entry)
            }

            if appState.index.securityUpdates.count > securityEntries.count {
                Text("还有 \(appState.index.securityUpdates.count - securityEntries.count) 个安全更新，回主窗口查看。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }

    private func securityRow(_ entry: OutdatedEntry) -> some View {
        Button {
            openPackageDetail(for: entry)
        } label: {
            HStack(spacing: 8) {
                SeverityBadge(severity: entry.severity ?? .unknown, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(AppTheme.headline(12))
                        .foregroundStyle(AppTheme.text1)
                        .lineLimit(1)
                    versionChange(from: entry.installedText, to: entry.currentVersion)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开 \(entry.name) 详情")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(securityAccessibilityLabel(entry))
        .accessibilityAddTraits(.isButton)
    }

    /// 规范 §5 VersionChange：旧 → 新，新版本 accent 加粗 mono。
    private func versionChange(from old: String, to new: String) -> some View {
        HStack(spacing: 4) {
            Text(old.isEmpty ? "—" : old)
                .font(AppTheme.mono(11))
                .foregroundStyle(AppTheme.text3)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppTheme.text3)
            Text(new)
                .font(AppTheme.mono(11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .lineLimit(1)
    }

    private func securityAccessibilityLabel(_ entry: OutdatedEntry) -> String {
        let severity = (entry.severity ?? .unknown).label
        let old = entry.installedText.isEmpty ? "未知版本" : entry.installedText
        return "\(entry.name)，\(severity)漏洞，安全更新，从 \(old) 到 \(entry.currentVersion)"
    }

    // MARK: - Current task

    private func taskRow(_ record: TaskRecord) -> some View {
        Button {
            appState.tasks.showDrawer = true
            openMainWindow()
        } label: {
            HStack(spacing: 8) {
                taskStatusIcon(record)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(AppTheme.headline(12))
                        .foregroundStyle(AppTheme.text1)
                        .lineLimit(1)
                    Text(taskStatusLine(record))
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.text3)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("展开任务岛")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title)，\(taskStatusLine(record))，展开任务岛")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func taskStatusIcon(_ record: TaskRecord) -> some View {
        if record.status == .running || record.status == .cancelling {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: statusSymbol(record.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor(record.status))
        }
    }

    private func taskStatusLine(_ record: TaskRecord) -> String {
        var parts = [record.status.label]
        if let duration = record.duration {
            parts.append("\(record.status == .running ? "已用 " : "")\(durationText(duration))")
        }
        if let exitCode = record.exitCode, record.status == .failed {
            parts.append("退出码 \(exitCode)")
        }
        return parts.joined(separator: " · ")
    }

    private func statusSymbol(_ status: TaskRecord.Status) -> String {
        switch status {
        case .pending: return "clock"
        case .running: return "hourglass"
        case .cancelling: return "hourglass"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .unverified: return "questionmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .interrupted: return "exclamationmark.triangle"
        }
    }

    private func statusColor(_ status: TaskRecord.Status) -> Color {
        switch status {
        case .succeeded: return AppTheme.success
        case .failed: return AppTheme.danger
        case .unverified, .interrupted: return AppTheme.warning
        case .running, .cancelling, .pending: return AppTheme.accent
        case .cancelled: return AppTheme.neutral
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .glassPrimaryButton()
            .help("打开 Brewbutler 主窗口")

            HStack(spacing: 8) {
                Button {
                    Task { await appState.checkUpdates() }
                } label: {
                    Text("检查更新")
                        .frame(maxWidth: .infinity)
                }
                .glassSecondaryButton()
                .disabled(appState.isRefreshing || appState.isSyncingUpstream || appState.installation == nil)
                .help("先同步 Homebrew 索引，再检查可更新项 ⌘R")

                Button {
                    appState.scanVulnerabilities()
                } label: {
                    Text(appState.isScanning ? "正在扫描…" : "运行扫描")
                        .frame(maxWidth: .infinity)
                }
                .glassSecondaryButton()
                .disabled(appState.isScanning || appState.installation == nil)
                .help("运行安全扫描（约 30 秒）⇧⌘V")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if appState.index.securityUpdates.count > 0 {
                Text("批量更新请回主窗口确认")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("退出") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(AppTheme.caption())
            .foregroundStyle(AppTheme.text2)
            .help("退出 Brewbutler ⌘Q")
        }
    }

    // MARK: - Navigation

    /// 菜单栏是独立窗口；所有跳转都要先关 popover，再激活主窗口。
    private func openMainWindow() {
        dismiss()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPackageDetail(for entry: OutdatedEntry) {
        // 先写选中包，再打开窗口；两者都是全局状态，顺序不影响结果。
        if let package = appState.index.package(named: entry.name, kind: entry.kind) {
            appState.selectPackage(package)
        } else {
            appState.openSection(.updates)
        }
        openMainWindow()
    }

    /// 与 `RecentTasksCard.durationText` 同口径；本地实现避免依赖其它页面文件。
    private func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
