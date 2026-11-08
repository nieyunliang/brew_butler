import SwiftUI

// MARK: - 资料库「筛选 ⌄」菜单与 token 行（ui-design v2.0.2 §4.3 / UX 方案 O-06）
//
// scope 栏只保留 5 项互斥条件；「已锁定 / 手动安装 / keg-only / tap」收进这个
// 玻璃按钮的菜单里，可以组合。启用后由 token 行把当前条件摊开，用户不用再
// 打开菜单回忆自己筛了什么。

/// 「筛选」菜单的附加条件：与 scope 栏取交集。
/// 独立成型，让菜单、token 行与查询共用同一份状态，避免三处各存一套布尔值。
struct LibraryFilterSelection: Equatable {
    var pinnedOnly = false
    var manualOnly = false
    var kegOnlyOnly = false
    var tap: String?

    var activeCount: Int {
        var count = 0
        if pinnedOnly { count += 1 }
        if manualOnly { count += 1 }
        if kegOnlyOnly { count += 1 }
        if tap != nil { count += 1 }
        return count
    }

    func options(scope: InstalledFilter) -> LibraryFilterOptions {
        LibraryFilterOptions(
            scope: scope,
            pinnedOnly: pinnedOnly,
            manualOnly: manualOnly,
            kegOnlyOnly: kegOnlyOnly,
            tap: tap
        )
    }

    /// token 顺序固定为与菜单一致：已锁定 → 手动安装 → keg-only → tap。
    var tokens: [LibraryFilterToken] {
        var result: [LibraryFilterToken] = []
        if pinnedOnly {
            result.append(LibraryFilterToken(kind: .pinned, label: "已锁定", spokenLabel: "已锁定"))
        }
        if manualOnly {
            result.append(LibraryFilterToken(kind: .manual, label: "手动安装", spokenLabel: "手动安装"))
        }
        if kegOnlyOnly {
            result.append(LibraryFilterToken(kind: .kegOnly, label: "keg-only", spokenLabel: "keg-only"))
        }
        if let tap {
            result.append(LibraryFilterToken(kind: .tap(tap), label: "tap: \(tap)", spokenLabel: "tap \(tap)"))
        }
        return result
    }

    /// VoiceOver 朗读：「已启用筛选：手动安装，tap homebrew/core」。
    var accessibilityText: String {
        let labels = tokens.map(\.spokenLabel)
        return labels.isEmpty ? "未启用筛选" : "已启用筛选：\(labels.joined(separator: "，"))"
    }

    mutating func remove(_ token: LibraryFilterToken) {
        switch token.kind {
        case .pinned: pinnedOnly = false
        case .manual: manualOnly = false
        case .kegOnly: kegOnlyOnly = false
        case .tap: tap = nil
        }
    }

    mutating func clear() {
        self = LibraryFilterSelection()
    }
}

struct LibraryFilterToken: Identifiable, Equatable {
    enum Kind: Equatable {
        case pinned, manual, kegOnly, tap(String)
    }

    var kind: Kind
    /// token 上展示的文字（tap 保留 `tap: homebrew/core` 的写法）。
    var label: String
    /// VoiceOver 朗读用（tap 去掉冒号，更接近口语）。
    var spokenLabel: String

    var id: String {
        switch kind {
        case .pinned: return "pinned"
        case .manual: return "manual"
        case .kegOnly: return "keg-only"
        case .tap(let tap): return "tap:\(tap)"
        }
    }
}

/// 「筛选」菜单的 tap 选项（单选，带计数）。
struct LibraryTapOption: Identifiable, Equatable {
    var tap: String
    var count: Int

    var id: String { tap }
}

// MARK: - 玻璃筛选按钮 + 菜单

struct LibraryFilterMenuButton: View {
    @Binding var selection: LibraryFilterSelection
    var pinnedCount: Int
    var manualCount: Int
    var kegOnlyCount: Int
    var taps: [LibraryTapOption]

    private var isActive: Bool { selection.activeCount > 0 }

    var body: some View {
        Menu {
            Toggle(isOn: $selection.pinnedOnly) {
                Text("已锁定（\(pinnedCount)）")
            }
            Toggle(isOn: $selection.manualOnly) {
                Text("手动安装（\(manualCount)）")
            }
            Toggle(isOn: $selection.kegOnlyOnly) {
                Text("keg-only（\(kegOnlyCount)）")
            }

            Divider()
            // 菜单里没有「分组标题」控件，用不可点的 Text 充当 tap 单选的小标题。
            Text("tap（单选）")
            Button {
                selection.tap = nil
            } label: {
                if selection.tap == nil {
                    Label("全部 tap", systemImage: "checkmark")
                } else {
                    Text("全部 tap")
                }
            }
            ForEach(taps) { option in
                Button {
                    selection.tap = option.tap
                } label: {
                    if selection.tap == option.tap {
                        Label("\(option.tap)（\(option.count)）", systemImage: "checkmark")
                    } else {
                        Text("\(option.tap)（\(option.count)）")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(isActive ? "筛选 \(selection.activeCount)" : "筛选")
                    .font(AppTheme.callout(12))
                    .fontWeight(isActive ? .semibold : .regular)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.text2)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
            .modifier(LibraryFilterGlass(isActive: isActive))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("按已锁定、手动安装、keg-only、tap 组合筛选")
        .accessibilityLabel("筛选")
        .accessibilityValue(isActive ? "已启用 \(selection.activeCount) 项" : "未启用")
    }
}

/// 与 GlassScopeBar 的选中胶囊同一套材质规则：控制层玻璃；
/// 降低透明度时退化为实底 + 描边（§1.1 L1），提高对比度时描边加粗（L2）。
private struct LibraryFilterGlass: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    isActive ? AppTheme.accentSoft : AppTheme.raised,
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isActive ? AppTheme.accent.opacity(0.5) : AppTheme.separator,
                            lineWidth: AppMaterial.strokeWidth(for: contrast)
                        )
                )
        } else if isActive {
            content.glassEffect(.regular.tint(AppTheme.accent).interactive(), in: .capsule)
        } else {
            content.glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

// MARK: - token 行

/// scope 栏下方的「已启用筛选」token 行：点 ✕ 移除单项；≥2 项时给「清除全部」。
struct LibraryFilterTokenRow: View {
    @Binding var selection: LibraryFilterSelection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(selection.tokens) { token in
                tokenCapsule(token)
            }
            if selection.activeCount >= 2 {
                Button("清除全部") {
                    selection.clear()
                }
                .buttonStyle(.plain)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.accent)
                .help("移除全部附加筛选")
            }
            Spacer(minLength: 0)
        }
        // 容器朗读整体条件，单个 ✕ 仍可被单独聚焦并朗读要移除哪一项。
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selection.accessibilityText)
    }

    private func tokenCapsule(_ token: LibraryFilterToken) -> some View {
        HStack(spacing: 4) {
            Text(token.label)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text2)
                .lineLimit(1)
            Button {
                selection.remove(token)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.text3)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除筛选：\(token.spokenLabel)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(AppTheme.surface2, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.separator, lineWidth: 1))
    }
}
