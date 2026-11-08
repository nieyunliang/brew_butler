import SwiftUI

// MARK: - Badges

struct Badge: View {
    var text: String
    var color: Color = AppTheme.text2
    var background: Color?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(AppTheme.caption())
                .captionTracking()
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(background ?? color.opacity(0.11), in: RoundedRectangle(cornerRadius: AppTheme.badgeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.badgeRadius, style: .continuous)
                .strokeBorder(color.opacity(0.26), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct KindBadge: View {
    var kind: PackageSnapshot.Kind

    var body: some View {
        Badge(
            text: kind.rawValue,
            color: kind == .formula ? AppTheme.accent : AppTheme.info,
            background: kind == .formula ? AppTheme.accentSoft : AppTheme.infoSoft
        )
    }
}

struct SeverityBadge: View {
    var severity: VulnSeverity
    var compact = false

    var body: some View {
        Badge(
            text: compact ? severity.label : "\(severity.label)漏洞",
            color: AppTheme.severity(severity),
            background: AppTheme.severitySoft(severity),
            systemImage: compact ? nil : "exclamationmark.triangle.fill"
        )
    }
}

struct StatusPill: View {
    var text: String
    var color: Color
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(AppTheme.caption()).captionTracking()
        }
        .foregroundStyle(filled ? AppTheme.onAccent : color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(filled ? color : color.opacity(0.10), in: Capsule())
    }
}

struct ServiceStatusPill: View {
    var lifecycle: ServiceLifecycle

    private var color: Color {
        switch lifecycle {
        case .running: return AppTheme.success
        case .error: return AppTheme.danger
        case .unknown: return AppTheme.text3
        default: return AppTheme.text2
        }
    }

    var body: some View {
        StatusPill(text: lifecycle.label, color: color)
    }
}

// MARK: - Cards

struct SectionCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || accessory != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title).font(AppTheme.headline()).foregroundStyle(AppTheme.text1)
                    }
                    if let subtitle {
                        Text(subtitle).font(AppTheme.caption()).captionTracking().foregroundStyle(AppTheme.text3)
                    }
                    Spacer(minLength: 8)
                    if let accessory { accessory }
                }
            }
            content
        }
        .cardStyle()
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color = AppTheme.accent
    var isWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isWarning ? AppTheme.warning : tint)
                    .frame(width: 22, height: 22)
                    .background((isWarning ? AppTheme.warning : tint).opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title).font(AppTheme.caption()).captionTracking().foregroundStyle(AppTheme.text3)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(AppTheme.statValue())
                .monospacedDigit()
                .foregroundStyle(AppTheme.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(AppTheme.caption()).captionTracking().foregroundStyle(AppTheme.text3).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(isWarning ? AppTheme.warning.opacity(0.32) : AppTheme.hair, lineWidth: 1)
        )
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.accentFill

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.onAccent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.text1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? AppTheme.surface3 : AppTheme.surface2, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .strokeBorder(AppTheme.hairStrong, lineWidth: 1)
            )
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.danger.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.text2)
            .frame(width: 27, height: 27)
            .background(configuration.isPressed ? AppTheme.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Filter chips

struct FilterChip: View {
    var title: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(AppTheme.caption())
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? AppTheme.onAccent.opacity(0.8) : AppTheme.text3)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.text2)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isSelected ? AppTheme.accentFill : AppTheme.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : AppTheme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Search field

/// 页面内搜索框（已安装 / 更新 / 发现共用）：高 28、圆角 6、描边 hair-2（规范 §2.3）。
/// 三个页面此前各自实现，高度与圆角曾漂移为 26/7，收敛到这一个组件。
struct SearchField: View {
    var placeholder: String
    @Binding var text: String
    /// nil 时横向撑满（发现页）；给值时固定宽度（已安装 / 更新页的筛选行）。
    var width: CGFloat?
    var isBusy = false
    var focus: FocusState<Bool>.Binding
    /// 发现页：回车跳过防抖立即搜索；列表页筛选无此需求。
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.text3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.callout())
                .focused(focus)
                .onSubmit { onSubmit?() }
            if isBusy {
                ProgressView().controlSize(.small)
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
        .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .strokeBorder(AppTheme.hairStrong, lineWidth: 1)
        )
        .accessibilityLabel(placeholder)
    }
}

// MARK: - Empty & error states

struct EmptyStateView: View {
    var systemImage: String = "shippingbox"
    var title: String
    var message: String
    /// 卡片内嵌空态（如仪表盘安全卡）用紧凑档，避免整页空态的 54pt 留白。
    var compact = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 22 : 34, weight: .light))
                .foregroundStyle(AppTheme.text3)
            Text(title)
                .font(AppTheme.subheading())
                .foregroundStyle(AppTheme.text1)
            Text(message)
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 18 : 54)
        .padding(.horizontal, 24)
    }
}

struct InlineNotice: View {
    enum Level {
        case info, warning, danger, success
    }

    var level: Level = .info
    var title: String?
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    private var color: Color {
        switch level {
        case .info: return AppTheme.info
        case .warning: return AppTheme.warning
        case .danger: return AppTheme.danger
        case .success: return AppTheme.success
        }
    }

    private var icon: String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .danger: return "xmark.octagon"
        case .success: return "checkmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).font(AppTheme.headline(12)).foregroundStyle(AppTheme.text1)
                }
                Text(message).font(AppTheme.callout()).foregroundStyle(AppTheme.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Rows

struct InfoRow: View {
    var label: String
    var value: String
    var mono = false
    var valueColor: Color = AppTheme.text1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(AppTheme.callout())
                .foregroundStyle(AppTheme.text3)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(mono ? AppTheme.mono(11.5) : AppTheme.callout())
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }
}

struct ValueChip: View {
    var text: String
    var mono = false
    var color: Color = AppTheme.text2

    var body: some View {
        Text(text)
            .font(mono ? AppTheme.mono() : AppTheme.callout(11.5))
            .foregroundStyle(color)
            // 名称胶囊在窄列里宁可截断也不折行；完整名称在 help / 无障碍标签里。
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .textSelection(.enabled)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(AppTheme.hair).frame(height: 1)
    }
}

struct LoadingBar: View {
    var height: CGFloat = 2
    /// E-15：减少动效时用静态进度条，避免持续位移。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 99)
                        .fill(AppTheme.accent.opacity(0.75))
                        .frame(width: proxy.size.width * 0.32)
                }
            } else {
                GeometryReader { proxy in
                    TimelineView(.animation) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let width = proxy.size.width * 0.32
                        let x = (proxy.size.width + width) * phase - width
                        RoundedRectangle(cornerRadius: 99)
                            .fill(AppTheme.accent.opacity(0.75))
                            .frame(width: width)
                            .offset(x: x)
                    }
                }
            }
        }
        .frame(height: height)
        .background(AppTheme.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 99))
    }
}

/// 任务状态圆点：日志抽屉进度行与更新页单一列表共用。
struct PackageStateDot: View {
    let state: PackageProgressItem.State

    var body: some View {
        switch state {
        case .succeeded:
            // onAccent 而非固定白色：深色模式下 success/danger 是浅色，白字对比不足。
            statusCircle(fill: AppTheme.success, text: "✓", textColor: AppTheme.onAccent)
        case .failed:
            statusCircle(fill: AppTheme.danger, text: "✕", textColor: AppTheme.onAccent)
        case .unverified:
            // P1-9：brew 成功但校验失败，既不是成功也不是失败。
            statusCircle(fill: AppTheme.warning, text: "?", textColor: AppTheme.onAccent)
        case .running:
            Circle()
                .strokeBorder(AppTheme.accent, lineWidth: 1.5)
                .background(Circle().fill(AppTheme.accent).frame(width: 8, height: 8))
                .frame(width: 16, height: 16)
        case .pending:
            Circle()
                .strokeBorder(AppTheme.surface3, lineWidth: 1.5)
                .frame(width: 16, height: 16)
        case .cancelled:
            // C-16：已取消（跑过但被中止）与未执行（从未开始）必须可区分。
            Circle()
                .strokeBorder(AppTheme.text3.opacity(0.6), lineWidth: 1.5)
                .overlay(
                    Image(systemName: "stop.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(AppTheme.text3)
                )
                .frame(width: 16, height: 16)
        case .skipped:
            Circle()
                .strokeBorder(AppTheme.surface3, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 16, height: 16)
        }
    }

    private func statusCircle(fill: Color, text: String, textColor: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay(
                Text(text)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(textColor)
            )
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case failure
        case info
    }

    var id = UUID()
    var text: String
    var kind: Kind = .info
}

extension TaskRecord.Status {
    /// 任务状态 → 语义色。仪表盘「最近操作」与日志抽屉共用，避免两份 switch。
    var displayColor: Color {
        switch self {
        case .succeeded: return AppTheme.success
        case .failed, .interrupted: return AppTheme.danger
        case .unverified: return AppTheme.warning
        case .cancelled: return AppTheme.text3
        case .running, .cancelling: return AppTheme.accent
        case .pending: return AppTheme.warning
        }
    }
}

/// 进度行的 trailing 状态区：进行中为「不定态条在前、阶段徽章贴最右」。
/// 更新页单一列表与日志抽屉进度行共用，避免两份排版逻辑漂移。
struct ProgressStateTrailing: View {
    let state: PackageProgressItem.State
    let stage: BrewProgressStage?

    var body: some View {
        switch state {
        case .running:
            HStack(spacing: 6) {
                LoadingBar(height: 4)
                    .frame(width: 96)
                    .accessibilityHidden(true)
                Text(stage?.label ?? "运行中")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: AppTheme.badgeRadius, style: .continuous))
            }
        case .pending, .succeeded, .failed, .unverified, .cancelled, .skipped:
            Text(state.label)
                .font(AppTheme.caption())
                .foregroundStyle(state == .failed
                                 ? AppTheme.danger
                                 : (state == .unverified ? AppTheme.warning : AppTheme.text3))
        }
    }
}

/// 剪贴板写入的统一入口；调用方负责各自的 toast 提示文案。
func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
