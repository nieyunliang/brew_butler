import SwiftUI

/// Shared layout for the app's confirmation sheets: title states the
/// consequence, body lists the impact, and the default focus is on 取消.
private struct ConfirmSheetLayout<Content: View>: View {
    var title: String
    var confirmTitle: String
    var isConfirmEnabled = true
    var onConfirm: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // 规范 §4.10：系统 sheet（macOS 27 自带玻璃边框），宽 440；
        // 标题即后果，默认焦点「取消」，危险按钮用玻璃 + 红色 tint。
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(AppTheme.packageTitle(21))
                .foregroundStyle(AppTheme.text1)
                .fixedSize(horizontal: false, vertical: true)

            content

            HStack(spacing: 10) {
                Spacer()
                // 回车落在「取消」上：危险操作确认的默认焦点必须在取消侧。
                // Esc 关闭 sheet 由系统行为提供，不与 defaultAction 叠加。
                Button("取消") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
                Button(confirmTitle) {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(isConfirmEnabled ? AppTheme.danger : nil)
                .disabled(!isConfirmEnabled)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(AppTheme.canvas)
    }
}

// MARK: - Uninstall

struct UninstallSheet: View {
    @Environment(AppState.self) private var appState
    var package: PackageSnapshot

    @State private var zap = false
    @State private var zapConfirmation = ""

    private var dependents: [String] { appState.index.dependents(of: package.name) }
    private var detail: PackageDetailState { appState.detail }

    var body: some View {
        ConfirmSheetLayout(
            title: "卸载 \(package.displayName)？",
            confirmTitle: zap ? "卸载并删除关联文件" : "卸载",
            isConfirmEnabled: dependents.isEmpty && (!zap || zapConfirmation == package.name)
        ) {
            performUninstall()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if !dependents.isEmpty {
                    InlineNotice(
                        level: .danger,
                        title: "卸载已禁用：有 \(dependents.count) 个包依赖它",
                        message: "直接卸载会让下列包无法运行。请先更新或卸载依赖方，再回来处理 \(package.name)。"
                    )
                    FlowChipsLayout(spacing: 6) {
                        ForEach(Array(dependents.prefix(8)), id: \.self) { name in
                            ValueChip(text: name, mono: true)
                        }
                    }
                    if dependents.count > 8 {
                        Text("另有 \(dependents.count - 8) 个依赖方未列出。")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                }

                Text("将执行：\(package.uninstallCommand)")
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)

                if zap {
                    // P1-7：预览必须说明会比上面这条命令多做一步；界面仍不出现
                    // `--zap` 参数串（AGENTS §5.12）。
                    Text("并附加删除关联文件的参数：移除 brew 为该 cask 声明的关联文件，不可恢复。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if package.kind == .cask {
                    Toggle("同时删除关联文件", isOn: $zap)
                        .font(AppTheme.body())
                    if zap {
                        zapWarning
                        zapDeleteDetail
                        Text("输入包名「\(package.name)」以确认：")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField(package.name, text: $zapConfirmation)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTheme.mono(11.5))
                    }
                }
            }
        }
    }

    /// 勾选「删除关联文件」后的风险说明：写明 brew 的能力边界，不假装知道具体待删清单。
    private var zapWarning: some View {
        Text("删除关联文件会移除 brew 为该 cask 声明的关联文件，可能包含偏好设置、共享文件与登录项，删除后不可恢复。")
            .font(AppTheme.callout())
            .foregroundStyle(AppTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// 删除明细：路径与体积来自详情页缓存；拿不到就明说，通用分类说明不冒充具体清单。
    private var zapDeleteDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("删除明细（brew 未提供删除明细，以下为通用说明）")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text2)
            if detail.packageID == package.id {
                InfoRow(label: "应用本体", value: detail.path ?? "未知", mono: true)
                InfoRow(label: "本身体积", value: detail.sizeBytes?.byteCountText ?? "未知（计算中或不可计算）", mono: true)
            } else {
                InfoRow(label: "应用本体", value: "未知（在详情页打开后可读取路径与体积）", mono: true)
            }
            Text("偏好设置：~/Library/Preferences 下与该应用相关的 plist")
            Text("共享文件：多个应用共用的配置或缓存，删除后其他应用也可能受影响")
            Text("登录项：~/Library/LaunchAgents 下与该应用相关的 plist")
        }
        .font(AppTheme.caption())
        .foregroundStyle(AppTheme.text3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func performUninstall() {
        appState.performUninstall(package, zap: zap)
    }
}

// MARK: - Batch uninstall

struct BatchUninstallSheet: View {
    @Environment(AppState.self) private var appState
    var packages: [PackageSnapshot]

    private var allowed: [PackageSnapshot] {
        packages.filter { appState.index.dependents(of: $0.name).isEmpty }
    }

    private var blocked: [PackageSnapshot] {
        packages.filter { !appState.index.dependents(of: $0.name).isEmpty }
    }

    private var allowedFormulae: [PackageSnapshot] { allowed.filter { $0.kind == .formula } }
    private var allowedCasks: [PackageSnapshot] { allowed.filter { $0.kind == .cask } }

    var body: some View {
        ConfirmSheetLayout(
            title: "卸载 \(allowed.count) 个包？",
            // 确认按钮文案直接给实际可卸载数，避免与选择数不一致时误解。
            confirmTitle: "卸载 \(allowed.count) 个包",
            isConfirmEnabled: !allowed.isEmpty
        ) {
            for package in allowed {
                appState.performUninstall(package, zap: false)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("将逐个执行卸载（串行队列），混合类型会按 formula / cask 分别入队：")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if !allowedFormulae.isEmpty {
                    batchGroup(title: "formula（\(allowedFormulae.count)）", packages: allowedFormulae)
                }
                if !allowedCasks.isEmpty {
                    batchGroup(title: "cask（\(allowedCasks.count)）", packages: allowedCasks)
                    Text("cask 只卸载应用本体，不会删除关联文件；需要清理关联文件（偏好设置、共享文件、登录项）请在包详情页逐个操作。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !blocked.isEmpty {
                    Divider()
                    Text("\(blocked.count) 个包因被其他包依赖而跳过（确认后也不会被执行）：")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(blocked.prefix(5)) { package in
                        let dependents = appState.index.dependents(of: package.name)
                        Text("\(package.displayName)：被 \(dependents.prefix(3).joined(separator: "、"))\(dependents.count > 3 ? " 等" : "") 依赖")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                    if blocked.count > 5 {
                        Text("…另有 \(blocked.count - 5) 个被依赖的包")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.text3)
                    }
                    Text("这些包需要先处理它们的依赖方；本次不会卸载它们。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                if allowed.isEmpty {
                    Text("当前选择中没有可安全卸载的包。")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }

    /// 分组展示：同类型包的卸载后果相同（cask 不删关联文件），分组后用户能预判结果。
    @ViewBuilder
    private func batchGroup(title: String, packages: [PackageSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            FlowChipsLayout(spacing: 6) {
                ForEach(packages.prefix(10)) { package in
                    ValueChip(text: package.displayName, mono: true)
                }
            }
            if packages.count > 10 {
                Text("…另有 \(packages.count - 10) 个")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }
}

// MARK: - Pin confirmation (PRD F5.1)

/// 锁定/解锁确认：锁定会让依赖新版本的包无法安装或运行，批量操作也只弹一次。
struct PinConfirmRequest: Identifiable {
    var packages: [PackageSnapshot]
    var pinned: Bool

    var id: String {
        let ids = packages.map(\.id).sorted().joined(separator: ",")
        return "\(pinned ? "pin" : "unpin"):\(ids)"
    }
}

struct PinConfirmSheet: View {
    @Environment(AppState.self) private var appState
    var request: PinConfirmRequest

    private var autoUpdateCasks: [PackageSnapshot] {
        request.pinned
            ? request.packages.filter { $0.kind == .cask && $0.autoUpdates == true }
            : []
    }

    private var title: String {
        request.pinned
            ? (request.packages.count == 1
                ? "锁定 \(request.packages[0].displayName)？"
                : "锁定 \(request.packages.count) 个包？")
            : (request.packages.count == 1
                ? "解锁 \(request.packages[0].displayName)？"
                : "解锁 \(request.packages.count) 个包？")
    }

    var body: some View {
        ConfirmSheetLayout(
            title: title,
            confirmTitle: request.pinned ? "锁定" : "解锁"
        ) {
            for package in request.packages {
                appState.setPinned(package, pinned: request.pinned)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                FlowChipsLayout(spacing: 6) {
                    ForEach(request.packages.prefix(10)) { package in
                        ValueChip(text: package.displayName, mono: true)
                    }
                }
                if request.packages.count > 10 {
                    Text("…另有 \(request.packages.count - 10) 个")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
                if request.pinned {
                    InlineNotice(
                        level: .warning,
                        title: "锁定后更新会跳过这些包",
                        message: "依赖该包新版本的其他包可能无法安装或运行；需要新版本时请先解锁。"
                    )
                    if !autoUpdateCasks.isEmpty {
                        Text("其中 \(autoUpdateCasks.count) 个 cask 启用了自动更新（auto_updates），锁定可能无法阻止应用自行更新。")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("解锁后这些包会重新纳入下次更新检查。")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.text3)
                }
            }
        }
    }
}

// MARK: - Install (cask authorization guidance)

struct InstallConfirmSheet: View {
    @Environment(AppState.self) private var appState
    var target: InstallTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("安装 \(target.name)？")
                .font(AppTheme.subheading())
                .foregroundStyle(AppTheme.text1)

            Text("将执行：\(installCommandText)")
                .font(AppTheme.mono())
                .foregroundStyle(AppTheme.text2)
                .textSelection(.enabled)

            // 安装前预检：能拿到的只有类型与发现页摘要；版本/体积/auto_updates 属安装后信息，
            // brew 没有安装前查询接口，这里如实说明而不是留空让人以为漏读。
            VStack(alignment: .leading, spacing: 4) {
                InfoRow(label: "名称", value: target.name, mono: true)
                InfoRow(label: "类型", value: target.kind == .cask ? "cask" : "formula")
                InfoRow(label: "来源", value: sourceText)
                InfoRow(label: "版本", value: "未知（安装后可在详情页读取）")
                InfoRow(label: "体积", value: "未知（安装后可在详情页读取）")
                InfoRow(label: "自动更新", value: "未知（安装后可在详情页读取）")
                if let summary = discoverSummary {
                    InfoRow(label: "简介", value: summary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("版本、体积与是否自动更新需安装后才能在详情页读取；brew 未提供安装前预检接口。")
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
                .fixedSize(horizontal: false, vertical: true)

            InlineNotice(
                level: .info,
                title: "可能需要系统授权",
                message: "安装 cask 可能弹出 macOS 授权窗口。Brewbutler 不代理 sudo：请在系统弹窗中授权，或在终端执行同一命令。"
            )

            HStack {
                Spacer()
                // 与 ConfirmSheetLayout 同口径：回车 = 取消，确认键不抢焦点。
                Button("取消") { appState.installTarget = nil }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("安装") {
                    appState.performInstall(name: target.name, kind: target.kind)
                    appState.installTarget = nil
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(AppTheme.background)
    }

    /// 命令文本按 kind 生成，与 AppState 构造卸载/安装命令的口径一致，避免字符串各自漂移。
    private var installCommandText: String {
        "brew install \(target.kind == .cask ? "--cask " : "")\(target.name)"
    }

    /// 来源只能诚实描述 brew 的解析规则：具体 tap 由 brew 在安装时决定，安装前没有机器可读结果。
    private var sourceText: String {
        target.kind == .cask
            ? "homebrew/cask 或第三方 tap（由 brew 解析）"
            : "homebrew/core 或第三方 tap（由 brew 解析）"
    }

    /// 从最近一次发现页搜索里取同名摘要；搜索是只读且不发起新请求。
    private var discoverSummary: String? {
        appState.discover.results
            .first { $0.name == target.name && $0.kind == target.kind }?
            .summary
            .trimmed
            .nilIfEmpty
    }
}

// MARK: - Cleanup

struct CleanupSheet: View {
    @Environment(AppState.self) private var appState
    var request: CleanupRequest

    @State private var scrub = false

    var body: some View {
        ConfirmSheetLayout(
            title: "清理\(request.preview.reclaimText.map { " \($0) " } ?? " ")缓存与旧版本？",
            confirmTitle: "清理"
        ) {
            appState.performCleanup(scrub: scrub, prune: nil)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("将移除 \(request.preview.removals.count) 项（brew cleanup）：")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(request.preview.removals, id: \.path) { removal in
                            HStack(spacing: 6) {
                                Text(removal.path)
                                    .font(AppTheme.mono())
                                    .foregroundStyle(AppTheme.text2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let detail = removal.detail {
                                    Text(detail)
                                        .font(AppTheme.caption())
                                        .foregroundStyle(AppTheme.text3)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)

                ForEach(request.preview.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.warning)
                }

                Toggle("同时清理所有下载缓存", isOn: $scrub)
                    .font(AppTheme.body())
                Text("清理后，回滚到旧版本需要重新下载。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }
}

// MARK: - Autoremove

struct AutoremoveSheet: View {
    @Environment(AppState.self) private var appState
    var request: AutoremoveRequest

    var body: some View {
        ConfirmSheetLayout(
            title: "移除 \(request.preview.packages.count) 个孤立依赖？",
            confirmTitle: "移除"
        ) {
            appState.performAutoremove()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("以下包是安装其他软件时带入的依赖，当前已无人使用（brew autoremove）：")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                FlowChipsLayout(spacing: 6) {
                    ForEach(request.preview.packages, id: \.self) { name in
                        ValueChip(text: name, mono: true)
                    }
                }
                Text("如果之后某个包报错缺依赖，重新安装该包即可自动补齐。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
            }
        }
    }
}

// MARK: - Brewfile import

struct BrewfileImportSheet: View {
    @Environment(AppState.self) private var appState
    var url: URL

    /// 只认「当前这个文件」的预览，避免上一次导入的预览串台。
    private var preview: BrewfileImportPreview? {
        guard let preview = appState.brewfileImportPreview else { return nil }
        return preview.url.path == url.path ? preview : nil
    }

    private var confirmDisabledReason: String? {
        guard let preview else { return "正在解析 Brewfile…" }
        if let parseError = preview.parseError, !parseError.isEmpty { return "Brewfile 无法解析：\(parseError)" }
        if preview.installable.isEmpty, preview.taps.isEmpty { return "没有需要安装的 formula/cask 或 tap" }
        return nil
    }

    var body: some View {
        ConfirmSheetLayout(
            title: preview.map { "导入 Brewfile（\($0.installable.count) 项待安装）？" } ?? "导入 Brewfile？",
            confirmTitle: "导入",
            isConfirmEnabled: confirmDisabledReason == nil
        ) {
            appState.performBrewfileImport(url: url)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(url.path)
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let preview {
                    if let parseError = preview.parseError, !parseError.isEmpty {
                        InlineNotice(level: .danger, title: "无法读取 Brewfile", message: parseError)
                    } else {
                        if !preview.installable.isEmpty {
                            previewSection(
                                title: "将安装 \(preview.installable.count) 项",
                                items: preview.installable,
                                color: AppTheme.accent
                            )
                        }
                        if !preview.alreadyInstalled.isEmpty {
                            previewSection(
                                title: "已安装 \(preview.alreadyInstalled.count) 项（跳过，不重复安装）",
                                items: Array(preview.alreadyInstalled.prefix(6)),
                                color: AppTheme.text3
                            )
                        }
                        if !preview.taps.isEmpty {
                            previewSection(
                                title: "将添加 \(preview.taps.count) 个 tap",
                                items: preview.taps,
                                color: AppTheme.accent
                            )
                        }
                        if !preview.unsupported.isEmpty {
                            InlineNotice(
                                level: .warning,
                                title: "\(preview.unsupported.count) 行不是 brew/cask/tap 指令",
                                message: "导入时会被跳过，或导致 brew bundle 报错：\(preview.unsupported.prefix(4).map(\.name).joined(separator: "、"))"
                            )
                        }
                        if !preview.duplicates.isEmpty {
                            Text("忽略重复条目 \(preview.duplicates.count) 个：\(preview.duplicates.prefix(4).joined(separator: "、"))")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.text3)
                        }
                    }
                    if let reason = confirmDisabledReason {
                        Text(reason)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.warning)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在解析 Brewfile…")
                            .font(AppTheme.callout())
                            .foregroundStyle(AppTheme.text2)
                    }
                }

                Text("导入只安装缺失项（brew bundle install），不会卸载或改动已有包；过程可能耗时较长，可在任务日志中查看进度。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func previewSection(title: String, items: [BrewfileImportPreview.Item], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.caption())
                .foregroundStyle(AppTheme.text3)
            FlowChipsLayout(spacing: 4) {
                ForEach(items) { item in
                    ValueChip(text: item.name, mono: true, color: color)
                }
            }
        }
    }
}

// MARK: - Dangerous retry

/// Second confirmation for retrying a dangerous task (卸载 / 清理 / autoremove /
/// 服务操作). The retry path must pass the same gate as the original submission.
/// P1-6：强删重试要求重新输入包名；界面只展示标题，不再显示原始命令串。
struct RetryConfirmSheet: View {
    @Environment(AppState.self) private var appState
    var record: TaskRecord

    @State private var typedName = ""

    /// 失败的强删重试等同一次新的强删，必须重新输入包名确认。
    private var requiresPackageName: Bool {
        record.commandText.contains("--zap")
    }

    private var isConfirmed: Bool {
        guard requiresPackageName, let name = record.packageName else { return true }
        return typedName.trimmed == name
    }

    var body: some View {
        ConfirmSheetLayout(
            title: "重试「\(record.title)」？",
            confirmTitle: "重试",
            isConfirmEnabled: isConfirmed,
            onConfirm: {
                appState.confirmPendingRetry(packageNameConfirmation: requiresPackageName ? typedName : nil)
            },
            content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("这是危险操作的重试，将再次执行：")
                    .font(AppTheme.callout())
                    .foregroundStyle(AppTheme.text2)
                Text(record.title)
                    .font(AppTheme.body())
                    .foregroundStyle(AppTheme.text1)
                    .fixedSize(horizontal: false, vertical: true)

                if requiresPackageName, let name = record.packageName {
                    Text("该操作会删除关联文件。输入包名「\(name)」以确认：")
                        .font(AppTheme.callout())
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(name, text: $typedName)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTheme.mono(11.5))
                }

                Text("Brewbutler 不会自动回滚；执行前请确认该操作仍然需要。")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.warning)
            }
        }
        )
    }
}

// MARK: - Batch update summary

struct ReinstallSheet: View {
    @Environment(AppState.self) private var appState
    var package: PackageSnapshot

    var body: some View {
        ConfirmSheetLayout(
            title: "重新安装 \(package.displayName)？",
            confirmTitle: "重新安装",
            isConfirmEnabled: true
        ) {
            appState.confirmReinstall()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                InlineNotice(
                    level: .warning,
                    title: "会重新下载并覆盖当前版本的文件",
                    message: "不改变版本号，也不会先卸载；已修改的配置文件可能被覆盖。"
                )
                Text("将执行：\(package.kind == .cask ? "brew reinstall --cask" : "brew reinstall") \(package.name)")
                    .font(AppTheme.mono())
                    .foregroundStyle(AppTheme.text2)
                    .textSelection(.enabled)
            }
        }
    }
}
