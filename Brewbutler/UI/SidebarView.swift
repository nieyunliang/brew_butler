import SwiftUI

/// 规范 §3.1 / §3.2：系统浮动玻璃侧边栏 + 5 项一级导航
/// （概览 / 更新 / 资料库 / 服务 / 维护）。底部 `safeAreaInset` 放 Homebrew 状态卡。
///
/// 「发现」不是一级导航（工具栏搜索结果页），“设置”回到系统 Settings 窗口（⌘,）。
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        List(selection: selection) {
            ForEach(AppSection.allCases) { section in
                if section == .updates, let count = securityBadgeCount {
                    // 规范 §3.2：有安全更新时更新徽标为红。
                    HStack(spacing: 6) {
                        Label(section.title, systemImage: section.symbol)
                        Spacer(minLength: 6)
                        Text("\(count)")
                            .font(AppTheme.caption(11))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppTheme.danger, in: Capsule())
                            .accessibilityLabel("\(count) 个可更新，含安全更新")
                    }
                    .tag(section)
                } else {
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            homebrewStatusCard
        }
    }

    /// 选中项回写。点空白处（nil）时保持当前分区，不清空主内容。
    private var selection: Binding<AppSection?> {
        Binding(
            get: { appState.section },
            set: { newValue in
                if let newValue {
                    appState.openSection(newValue)
                }
            }
        )
    }

    /// 有安全更新时用红色徽标显示可更新总数（普通可更新仍用系统 badge）。
    private var securityBadgeCount: Int? {
        let outdated = appState.index.outdated.count
        guard outdated > 0, !appState.index.securityUpdates.isEmpty else { return nil }
        return outdated
    }

    /// 规范 §3.2：侧边栏徽标。更新 = 可更新数，资料库 = 已安装数，服务 = 运行中/总数。
    private func badge(for section: AppSection) -> Text? {
        switch section {
        case .updates:
            let count = appState.index.outdated.count
            return count > 0 ? Text("\(count)") : nil
        case .library:
            let count = appState.index.packages.count
            return count > 0 ? Text("\(count)") : nil
        case .services:
            guard appState.servicesLoaded, !appState.services.isEmpty else { return nil }
            let running = appState.services.filter { $0.lifecycle == .running }.count
            return Text("\(running)/\(appState.services.count)")
        case .overview, .maintenance:
            return nil
        }
    }

    /// M2 A-04：状态卡此前是纯展示，brew 缺失时用户只能卡在错误页。点击打开
    /// 系统设置窗口（可手动指定 brew 路径 / 重新检测）。
    private var homebrewStatusCard: some View {
        Button {
            openSettings()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Hairline()
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let installation = appState.installation {
                            HStack(spacing: 6) {
                                Circle().fill(AppTheme.success).frame(width: 6, height: 6)
                                Text(installation.versionText)
                                    .font(AppTheme.caption())
                                    .foregroundStyle(AppTheme.text2)
                            }
                            Text(installation.prefix)
                                .font(AppTheme.mono())
                                .foregroundStyle(AppTheme.text3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if appState.isLocatingBrew {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("正在检测 Homebrew…")
                                    .font(AppTheme.caption())
                                    .foregroundStyle(AppTheme.text2)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Circle().fill(AppTheme.danger).frame(width: 6, height: 6)
                                Text("未检测到 Homebrew")
                                    .font(AppTheme.caption())
                                    .foregroundStyle(AppTheme.danger)
                            }
                            Text("点击指定路径")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.text3)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(appState.installation == nil ? "指定 Homebrew 路径或重新检测" : "打开设置查看 Homebrew 信息")
        .accessibilityLabel(appState.installation == nil ? "未检测到 Homebrew，打开设置" : "\(appState.installation?.versionText ?? "Homebrew")，打开设置")
    }
}

struct PulsingDot: View {
    @State private var pulse = false
    /// E-15：减少动效时不闪烁，保留静态圆点表示运行中。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(AppTheme.accent)
            .frame(width: 6, height: 6)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.35 : 1))
            .opacity(reduceMotion ? 1 : (pulse ? 0.6 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { if !reduceMotion { pulse = true } }
    }
}
