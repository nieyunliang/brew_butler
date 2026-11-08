import AppKit
import SwiftUI

/// 设计 tokens（ui-design.md v2.0.2 §2）。
///
/// 原则（AGENTS.md §5.11 / 规范 §0）：颜色一律取系统语义色，**不定义十六进制值**，
/// 强调色跟随用户的系统强调色。旧 v1 的暖色板已移除；`background` / `surface*`
/// 等名字保留给尚未迁移的视图，含义已是系统表面。
enum AppTheme {
    // MARK: Surfaces（内容层实底）

    /// `canvas`：内容区底。旧名 `background` 保留，逐页迁移完成后删除。
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let background = canvas
    /// `raised`：内容卡片 / 表格。旧名 `surface`。
    static let raised = Color(nsColor: .controlBackgroundColor)
    static let surface = raised
    /// 次级填充：页头 / 页脚条、行 hover 底。
    static let surface2 = Color(nsColor: .underPageBackgroundColor)
    static let surface3 = Color.primary.opacity(0.06)
    /// `separator`：发丝线。旧名 `hair`。
    static let separator = Color(nsColor: .separatorColor)
    static let hair = separator
    static let hairStrong = Color.primary.opacity(0.18)

    // MARK: Text

    static let text1 = Color.primary
    static let text2 = Color.secondary
    static let text3 = Color(nsColor: .tertiaryLabelColor)

    // MARK: Accent & semantic

    /// 规范 §2.1：强调色 = 用户的系统强调色，不再自带品牌色。
    static let accent = Color.accentColor
    static let accentFill = Color.accentColor
    static let onAccent = Color.white
    static let accentSoft = Color.accentColor.opacity(0.15)
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
    static let infoSoft = Color.blue.opacity(0.12)
    static let neutral = Color.gray

    // MARK: Console（日志正文：内容层实底）

    static let consoleBackground = Color(nsColor: .textBackgroundColor)
    static let consoleText = Color(nsColor: .textColor)
    static let consoleMuted = Color(nsColor: .secondaryLabelColor)

    // MARK: Severity

    /// 规范 §2.1：中危用 `.yellow`，文字仍用 `.primary`（避免黄字低对比）。
    static func severity(_ severity: VulnSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        case .unknown: return text3
        }
    }

    /// 徽章填充：0.15（提高对比度时由视图提升到 0.25，见 §1.1 L2）。
    static func severitySoft(_ severity: VulnSeverity) -> Color {
        AppTheme.severity(severity).opacity(0.15)
    }

    // MARK: Type（§2.2：只用系统文本样式）

    /// Hero：页面标题（概览、更新…）。
    static func display(_ size: CGFloat = 22) -> Font {
        size == 22 ? .largeTitle.weight(.bold) : .system(size: size, weight: .semibold)
    }
    /// Title：包详情标题、弹层标题。
    static func packageTitle(_ size: CGFloat = 21) -> Font {
        size == 21 ? .title2.weight(.semibold) : .system(size: size, weight: .semibold)
    }
    /// Headline：列表包名、指标数字标签。
    static func headline(_ size: CGFloat = 13) -> Font {
        size == 13 ? .headline : .system(size: size, weight: .semibold)
    }
    /// Section：卡片 / 分组标题。
    static func subheading(_ size: CGFloat = 15) -> Font {
        size == 15 ? .title3.weight(.semibold) : .system(size: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 13) -> Font {
        size == 13 ? .body : .system(size: size, weight: .regular)
    }
    static func callout(_ size: CGFloat = 12) -> Font {
        size == 12 ? .callout : .system(size: size, weight: .regular)
    }
    /// Caption：徽章、时间戳。
    static func caption(_ size: CGFloat = 11) -> Font {
        size == 11 ? .caption : .system(size: size, weight: .medium)
    }
    /// Mono：版本、路径、命令、日志。
    static func mono(_ size: CGFloat = 11.5, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Metric：指标大数字，圆角等宽（§2.2）。配 `monospacedDigit()` 使用。
    static func statValue(_ size: CGFloat = 24) -> Font {
        size == 24
            ? .system(.title, design: .rounded).weight(.semibold).monospacedDigit()
            : .system(size: size, weight: .semibold, design: .rounded)
    }

    // MARK: Geometry（§2.3：4pt 栅格）

    /// 内容卡片圆角（18）。
    static let contentRadius: CGFloat = 18
    /// 玻璃面板圆角（24）。
    static let glassRadius: CGFloat = 24
    /// 页面水平边距（28）。
    static let pagePadding: CGFloat = 28
    /// hero 下方到内容的间距（12）。
    static let pageTopPadding: CGFloat = 12
    /// 浮动栏 / 任务岛折叠态高度（44）。
    static let glassBarHeight: CGFloat = 44
    /// 兼容旧视图的圆角名；新代码用 `contentRadius` / `glassRadius`。
    static let cardRadius: CGFloat = contentRadius
    static let controlRadius: CGFloat = 8
    static let badgeRadius: CGFloat = 5
    static let rowHeight: CGFloat = 46
    /// 列表行内首列（复选框 / 状态圆点）之后的分隔线缩进；三处列表共用，避免 40/41/42 漂移。
    static let listHairlineInset: CGFloat = 40
    /// 已安装 / 更新页行首复选框（13pt 图标 + 10 间距）占位宽度，用于行内错误信息与包名对齐。
    static let rowLeadingControlWidth: CGFloat = 23
    /// 日志抽屉进度行首状态圆点（16pt + 11 间距）占位宽度。
    static let progressRowLeadingControlWidth: CGFloat = 27
}

extension View {
    /// 规范 §2.2：Caption 层级自带 +0.04em 字距（11pt → 0.44pt）。SwiftUI 的 kerning
    /// 是 View 修饰符而非 Font 属性，因此只在共享组件内施加，调用方无需重复写。
    /// 定义在 View 上：容器（如表头行）也能整行施加。
    func captionTracking() -> some View {
        kerning(0.44)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.contentRadius, style: .continuous)
                    .strokeBorder(AppTheme.hair, lineWidth: 1)
            )
    }

    func pagePadding() -> some View {
        self.padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, AppTheme.pagePadding)
    }

    func focusableRow() -> some View {
        self.contentShape(Rectangle())
    }

    /// E-15：自定义行/面板项没有系统焦点环，这里统一补 2pt 强调色环。
    /// 只在键盘焦点时显示，鼠标点击不出现（由调用方传 `focused`）。
    func focusRing(_ focused: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .strokeBorder(AppTheme.accent, lineWidth: focused ? 2 : 0)
                .allowsHitTesting(false)
        )
    }
}

extension Int64 {
    var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var shortDateTimeText: String {
        // 界面 zh-Hans 优先：日期不能随系统语言漂移成「Nov 8 at 09:45」。
        formatted(
            .dateTime.month(.abbreviated).day().hour().minute()
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }

    var relativeText: String {
        // 时钟抖动会让「刚刚发生」被格式化成「0 秒后」；60s 内统一读作「刚刚」。
        let interval = timeIntervalSinceNow
        if interval > -60 { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
