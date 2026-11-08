import SwiftUI

/// 控制层材质（ui-design.md v2.0.2 §1.1 / §9）。
///
/// 玻璃只用于控制层：工具栏、侧边栏、scope 栏、浮动操作栏、任务岛、检查器、
/// 命令面板、弹层。内容层（列表行、日志正文、表单、卡片）永远实底。
///
/// 降级规则：
/// - L1 降低透明度：自绘玻璃面板改用 `raised` 实底 + 1pt `separator` 描边（系统控件由系统处理）。
/// - L2 提高对比度：描边 1pt → 1.5pt。
/// - L3 减少动态效果：由调用方把 morph/弹簧换成 0.15s 淡入。
enum AppMaterial {
    /// 提高对比度时的描边宽度（L2）。
    static func strokeWidth(for contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1.5 : 1
    }

    /// 提高对比度时的徽章填充不透明度（§1.1 L2：0.15 → 0.25）。
    static func badgeFillOpacity(for contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.25 : 0.15
    }

    /// 减少动态效果时的过渡时长（L3）。
    static let reducedMotionDuration: Double = 0.15
}

extension View {
    /// 玻璃胶囊：任务岛折叠态、浮动操作栏、scope 选中项。
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous), interactive: interactive))
    }

    /// 玻璃面板：任务岛展开态、命令面板、检查器。
    func glassPanel(cornerRadius: CGFloat = AppTheme.glassRadius) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let shape: S
    var interactive = false

    func body(content: Content) -> some View {
        if reduceTransparency {
            // L1：自绘玻璃面板退化为实底，避免牺牲可读性。
            content
                .background(AppTheme.raised, in: shape)
                .overlay(shape.strokeBorder(AppTheme.separator, lineWidth: AppMaterial.strokeWidth(for: contrast)))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}
