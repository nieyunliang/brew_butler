import SwiftUI

/// Diagnostics export sheet (M1 P0-08).
///
/// Both switches default to off. The preview is regenerated from
/// `AppState.diagnosticsText(_:)` — the same function that produces the file
/// contents — so the privacy statement the user reads is the statement that
/// ships with the export.
struct DiagnosticsSheet: View {
    let plan: DiagnosticsExportPlan

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var includePackages: Bool
    @State private var includePaths: Bool

    init(plan: DiagnosticsExportPlan) {
        self.plan = plan
        _includePackages = State(initialValue: plan.includePackages)
        _includePaths = State(initialValue: plan.includePaths)
    }

    private var effectivePlan: DiagnosticsExportPlan {
        var plan = self.plan
        plan.includePackages = includePackages
        plan.includePaths = includePaths
        return plan
    }

    private var previewText: String {
        appState.diagnosticsText(effectivePlan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出诊断包")
                .font(AppTheme.subheading())
                .foregroundStyle(AppTheme.text1)

            Text("默认不含包名与本机路径。仅在排查具体包或路径问题时再勾选；勾选内容会随文件一起离开本机。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("包含包名（最近任务标题）", isOn: $includePackages)
                Toggle("包含本机绝对路径", isOn: $includePaths)
            }
            .font(AppTheme.body())

            HStack {
                Text("预览")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                Spacer()
                Text("\(previewText.count) 字符")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .monospacedDigit()
            }

            ScrollView {
                Text(previewText)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 300)
            .background(AppTheme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("导出…") {
                    appState.saveDiagnostics(previewText)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(AppTheme.background)
    }
}
