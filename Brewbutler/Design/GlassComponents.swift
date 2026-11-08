import SwiftUI

// MARK: - 玻璃控制层组件（ui-design.md v2.0.2 §5）
//
// 这里只放「控制层」组件：scope 栏、浮动操作栏、玻璃提示条、玻璃 toast、
// 指标卡。内容层（列表、表格、日志正文、表单）永远实底，不要用这里的修饰符。
//
// L1/L2/L3 降级由各处实现读取系统环境：
// - L1 accessibilityReduceTransparency：`glassPanel` / `glassCapsule` 已退化为实底；
//   本文件的自绘玻璃同样退化为 raised + separator 描边。
// - L2 colorSchemeContrast：描边 1pt → 1.5pt。
// - L3 accessibilityReduceMotion：morph/弹簧 → 0.15s 淡入。

// MARK: - Scope 栏

/// GlassScopeBar 的一项：id 用 rawValue（例如 UpdateFilter.rawValue），
/// 选中态由 `selection` 字符串回写，避免每个页面各造一套枚举绑定。
struct GlassScopeOption: Identifiable, Hashable {
    let id: String
    var title: String
    var count: Int?
    var isEnabled = true
    var help: String?

    init(id: String, title: String, count: Int? = nil, isEnabled: Bool = true, help: String? = nil) {
        self.id = id
        self.title = title
        self.count = count
        self.isEnabled = isEnabled
        self.help = help
    }
}

/// 规范 §5 GlassScopeBar：**一个**玻璃容器 + 选中项 accent 胶囊（matchedGeometry
/// 滑动）。容器是控制层玻璃；未选中项透明，选中项实底 accent + 白字，与原型
/// `.scope` / `.pill` 一致。≤6 项。
struct GlassScopeBar: View {
    var options: [GlassScopeOption]
    @Binding var selection: String
    var accessibilityLabel: String = "范围"

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                item(option)
            }
        }
        .padding(3)
        .glassCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func item(_ option: GlassScopeOption) -> some View {
        let isSelected = option.id == selection
        return Button {
            guard option.isEnabled, !isSelected else { return }
            if reduceMotion {
                selection = option.id
            } else {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    selection = option.id
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(option.title)
                    .font(AppTheme.callout(12.5))
                    .fontWeight(isSelected ? .semibold : .regular)
                if let count = option.count {
                    Text("\(count)")
                        .font(AppTheme.mono(11))
                        .monospacedDigit()
                        .opacity(isSelected ? 0.85 : 0.6)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.text2)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(reduceTransparency ? AppTheme.accent : AppTheme.accentFill)
                        .matchedGeometryEffect(id: "scope-selection", in: pillNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .opacity(option.isEnabled ? 1 : 0.4)
        .help(option.help ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(option.count.map { "\(option.title)，\($0) 项" } ?? option.title)
    }
}

// MARK: - 浮动操作栏

/// 规范 §4.2/§5 FloatingActionBar：玻璃胶囊 44pt，选中 ≥1 时出现；
/// 内容由页面组合（计数 + 主操作 + 次操作），本组件只负责材质、高度与内边距。
struct FloatingActionBar<Content: View>: View {
    var selectionCount: Int
    var accessibilityLabel: String?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectionCount) 项")
                .font(AppTheme.callout(12))
                .foregroundStyle(AppTheme.text2)
                .monospacedDigit()
            content
        }
        .padding(.horizontal, 14)
        .frame(height: AppTheme.glassBarHeight)
        .modifier(FloatingBarSurface(reduceTransparency: reduceTransparency,
                                     strokeWidth: AppMaterial.strokeWidth(for: contrast)))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "已选 \(selectionCount) 项的操作栏")
    }
}

private struct FloatingBarSurface: ViewModifier {
    let reduceTransparency: Bool
    let strokeWidth: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppTheme.raised, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator, lineWidth: strokeWidth))
        } else {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - 玻璃提示条

/// 规范 §5 GlassNotice：玻璃条（info / warning tint 0.12），图标 + 标题 +
/// 说明 + 一个动作 + 关闭。同一屏不要叠放多条。
struct GlassNotice: View {
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
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .danger: return "xmark.octagon"
            case .success: return "checkmark.circle"
            }
        }
    }

    var level: Level = .info
    var title: String? = nil
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: level.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(level.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(AppTheme.headline(12))
                        .foregroundStyle(AppTheme.text1)
                }
                Text(message)
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭提示")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.raised)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.separator, lineWidth: AppMaterial.strokeWidth(for: contrast)))
            } else {
                Color.clear
                    .glassEffect(.regular.tint(level.color.opacity(0.12)), in: .rect(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title.map { "\($0)：" } ?? "")\(message)")
    }
}

// MARK: - 玻璃 toast（任务岛左侧小胶囊）

/// 规范 §4.8/§5 GlassToast：2.6s；可点击打开对应任务；失败不在这里
/// （失败由任务岛结果态承载）。
struct GlassToastPill: View {
    var toast: ToastMessage
    var queuedCount: Int
    var onOpen: (() -> Void)?

    private var color: Color {
        switch toast.kind {
        case .success: return AppTheme.success
        case .failure: return AppTheme.danger
        case .info: return AppTheme.info
        }
    }

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(toast.text)
                .font(AppTheme.callout(12))
                .foregroundStyle(AppTheme.text1)
                .lineLimit(1)
            if queuedCount > 0 {
                Text("+\(queuedCount)")
                    .font(AppTheme.mono(10))
                    .foregroundStyle(AppTheme.text3)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .glassCapsule(interactive: onOpen != nil)
        .contentShape(Capsule())
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.text)\(queuedCount > 0 ? "，还有 \(queuedCount) 条提示" : "")")
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
    }
}

// MARK: - 指标卡（内容层实底）

/// 规范 §4.1 指标环 / §5 MetricTile：内容层实底卡，环 + 数字 + 标签 + 说明，
/// 可点击。环只表达占比，不用来表达无上限的量。
struct MetricTileCard: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color = AppTheme.accent
    /// 0...1；nil 时不画环（例如「服务 3/4」用图标而不是环）。
    var progress: Double?
    var isLoading = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .help("\(title)，\(value)")
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if let progress {
                    Circle()
                        .stroke(tint.opacity(0.16), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(AppTheme.caption())
                        .captionTracking()
                        .foregroundStyle(AppTheme.text3)
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(value)
                    .font(AppTheme.statValue(22))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)\(detail.map { "，\($0)" } ?? "")")
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

// MARK: - 行内小按钮（玻璃 / 主操作）

extension View {
    /// 主操作：`.buttonStyle(.glassProminent)` + 胶囊。系统无此 style 时退回
    /// 自绘 accent 填充，保证 50+ 处调用点视觉一致。
    func glassPrimaryButton() -> some View {
        self.buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
    }

    func glassSecondaryButton() -> some View {
        self.buttonStyle(.glass)
            .buttonBorderShape(.capsule)
    }
}
