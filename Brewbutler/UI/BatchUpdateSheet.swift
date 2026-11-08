import SwiftUI

/// 批量更新确认（P0-07）：全部更新 / 更新安全项 / 更新所选都先到这里。
///
/// v2 视觉（规范 §4.10 ConfirmSheet）：标题即后果、默认焦点在「取消」、
/// 玻璃按钮；内容层实底。确认 / 取消仍只走 `AppState.confirmBatchUpdate()` /
/// `AppState.cancelBatchUpdate()`，不改变任何提交语义。
struct BatchUpdateSheet: View {
    let plan: BatchUpdatePlan

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let visibleNameLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.packageTitle(18))
                        .foregroundStyle(AppTheme.text1)
                        .accessibilityAddTraits(.isHeader)
                    Text(scopeLine)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                Spacer(minLength: 0)
            }

            if let reason = plan.emptyReason {
                InlineNotice(level: .warning, title: "无法开始更新", message: reason)
            } else {
                summaryLine
                nameList
                skippedList

                if plan.scope == .vulnerable {
                    InlineNotice(
                        level: .info,
                        message: "仅覆盖有可更新版本的安全项，其余受影响包不会在此处理。"
                    )
                }

                InlineNotice(
                    level: .warning,
                    message: "更新会修改已安装的包。Brewbutler 一次只执行一个变更任务，失败不会自动回滚。"
                )
            }

            HStack {
                Spacer()
                // 回车落在「取消」上：与 v1 ConfirmSheetLayout 同口径。
                Button("取消") {
                    appState.cancelBatchUpdate()
                    dismiss()
                }
                .glassSecondaryButton()
                .keyboardShortcut(.defaultAction)

                Button("开始更新") {
                    appState.confirmBatchUpdate()
                    dismiss()
                }
                .glassPrimaryButton()
                .disabled(plan.emptyReason != nil)
                .help(plan.emptyReason ?? "确认后加入单一变更队列，按顺序串行执行")
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(AppTheme.canvas)
    }

    // MARK: - Copy

    private var title: String {
        guard plan.emptyReason == nil else { return "无法更新" }
        return "更新 \(plan.packageNames.count) 个包？"
    }

    /// 范围说明用用户语言，不出现命令行参数串。
    private var scopeLine: String {
        switch plan.scope {
        case .all: return "范围：全部可更新包"
        case .vulnerable: return "范围：有可更新版本的安全项"
        case .selected: return "范围：所选包"
        }
    }

    private var summaryLine: some View {
        HStack(spacing: 6) {
            Text("共 \(plan.packageNames.count) 个包")
                .font(AppTheme.body())
                .foregroundStyle(AppTheme.text2)
            Text("·")
                .foregroundStyle(AppTheme.text3)
            Text("formula \(plan.formulaCount) · cask \(plan.caskCount)")
                .font(AppTheme.mono(11.5))
                .monospacedDigit()
                .foregroundStyle(AppTheme.text3)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var nameList: some View {
        if !plan.packageNames.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(plan.packageNames.prefix(visibleNameLimit).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(AppTheme.mono())
                        .foregroundStyle(AppTheme.text1)
                        .lineLimit(1)
                }
                if plan.packageNames.count > visibleNameLimit {
                    Text("等 \(plan.packageNames.count) 个")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
        }
    }

    /// 跳过清单：让用户在确认前就知道哪些包不会执行、为什么（规范 §4.10）。
    @ViewBuilder
    private var skippedList: some View {
        if !plan.skippedPinned.isEmpty || !plan.skippedActive.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.text3)
                    Text("已跳过 \(plan.skippedPinned.count + plan.skippedActive.count) 个")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text2)
                    Spacer(minLength: 0)
                }
                ForEach(Array(plan.skippedPinned.prefix(5)), id: \.self) { name in
                    skippedRow(name, reason: "已锁定")
                }
                ForEach(Array(plan.skippedActive.prefix(5)), id: \.self) { name in
                    skippedRow(name, reason: "进行中")
                }
                if plan.skippedPinned.count + plan.skippedActive.count > 10 {
                    Text("等 \(plan.skippedPinned.count + plan.skippedActive.count) 个")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func skippedRow(_ name: String, reason: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(AppTheme.mono(11))
                .foregroundStyle(AppTheme.text2)
                .lineLimit(1)
            Text("· \(reason)")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            Spacer(minLength: 0)
        }
    }
}
