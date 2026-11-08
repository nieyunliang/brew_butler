# 修复计划 · 里程碑 1（P0，10 条）

> 依据：[ux-review-2026-11-05.md](ux-review-2026-11-05.md)（98 条发现 / 10 P0）。
> 目标：先修复 P0（错误决策、系统数据风险、死路、硬约束违背）；P1/P2 在后续里程碑按报告顺序处理。
> 本文件是团队契约：文件所有权、跨文件接口、验收标准。改动前先读这里和对应 `parts/*.md`。

## 0. 前置与约定

- **基线**：`xcodebuild ... build` 已通过（日志 `build/uxfix-baseline-build2.log`）。**必须**带 `OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox`，否则 Observation 宏插件在沙箱内报 `ObservationMacros.ObservableMacro could not be found`。
- **每个人用自己的 DerivedData，禁止共用 `build/DerivedData`**（会互相阻塞）：
  ```bash
  xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath build/DerivedData-<name> \
    MODULE_CACHE_DIR="$PWD/build/modulecache-<name>" \
    'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build
  ```
- **禁止**：`git` 任何写操作（仓库处于「重命名未提交」状态，`checkout/reset/clean` 会毁掉工作树）；变更类 brew 命令；`swift test`（Lead 统一跑）；改 `Package.swift` / `project.pbxproj`；加第三方依赖；大规模格式化。
- 新增 Swift 文件放进既有目录（`Brewbutler/App`、`Brewbutler/UI`），工程用 `PBXFileSystemSynchronizedRootGroup`，会自动纳入 target。
- 文案：zh-Hans；状态词与危险动作词按 `docs/ui-design.md` §6；颜色/字号只用 `AppTheme`；漏洞措辞不得出现「无漏洞」，未覆盖/失败要明说。所有危险确认默认焦点在「取消」（`ConfirmSheetLayout` 已保证，不要绕过）。
- **只改自己 scope 内文件**；确需跨 scope，先 `send_message` 给 lead，等回复再动。同一文件同一时刻只有一个 owner。
- 完成定义：自己的改动编译通过（自己的 DerivedData）+ 逐条自查 + `team_task_update` 标记 complete + `send_message` 给 lead（≤300 字：改动文件、每条 fix 一行、build 结果、未解决风险）。

## 1. 里程碑 1 文件所有权

| 负责人 | 文件 | 任务 |
| --- | --- | --- |
| lead | `Brewbutler/ContentView.swift`（批量确认/诊断 sheet 挂载、集成修复） | 集成 |
| reviewer-d | `Brewbutler/MyApp.swift`、`Brewbutler/UI/MenuBarView.swift`、新 `Brewbutler/App/QuitGuard.swift` | P0-10 |
| reviewer-a | `Brewbutler/UI/DashboardView.swift`、`Brewbutler/UI/UpdatesView.swift` | P0-01、P0-02、P0-09、P0-07 接线 |
| reviewer-b | `Brewbutler/UI/Sheets.swift`、`Brewbutler/UI/PackageDetailView.swift`、`Brewbutler/UI/InstalledView.swift` | P0-03、P0-04、P0-05 |
| reviewer-c | `Brewbutler/App/AppState.swift`、`Brewbutler/App/TaskQueueStore.swift`、`Brewbutler/App/TaskModels.swift`、`Brewbutler/UI/SettingsView.swift`、新 `Brewbutler/UI/BatchUpdateSheet.swift`、新 `Brewbutler/UI/DiagnosticsSheet.swift` | P0-06、P0-07 API+sheet、P0-08 |

## 2. 跨文件接口契约（必须逐字对齐，名字/签名不改）

### 2.1 批量更新确认（P0-07）

```swift
// AppState.swift（reviewer-c）
struct BatchUpdatePlan: Identifiable {
    enum Scope: Hashable, Sendable {
        case all
        case selected([String])   // PackageSnapshot.id，调用方负责排序/去重
        case vulnerable
    }
    let id = UUID()
    let scope: Scope
    let title: String            // "更新全部包" / "更新 3 个包" / "更新安全项"
    let packageIDs: [String]     // 将更新的包（已排除 pinned / 已有任务）
    let packageNames: [String]   // 与 packageIDs 一一对应
    let formulaCount: Int
    let caskCount: Int
    let skippedPinned: [String]  // 被跳过的包名
    let skippedActive: [String]  // 已有任务/排队中的包名
    let emptyReason: String?     // 非 nil 时确认按钮禁用，sheet 只显示原因
}

// AppState
var pendingBatchUpdate: BatchUpdatePlan?          // 可观察，@Observable 自动
func requestBatchUpdate(_ scope: BatchUpdatePlan.Scope)   // 生成 plan；不可执行时也生成（emptyReason）
func confirmBatchUpdate()                          // 按 scope 复用现有 upgradeAll()/upgradeVulnerable()/bulkUpgrade(entries:) 逻辑
func cancelBatchUpdate()                           // pendingBatchUpdate = nil

// UI/BatchUpdateSheet.swift（reviewer-c）
struct BatchUpdateSheet: View { let plan: BatchUpdatePlan }   // 从 @Environment(AppState.self) 取 appState
```

UI 约定：`ConfirmSheetLayout`（默认焦点取消）；标题「开始\(plan.title)？」；正文：`将更新 N 个包（formula X · cask Y）`，前 8 个包名 + 「等 N 个」；skipped 非空显示「已跳过：锁定 K · 进行中 M」；`scope == .vulnerable` 时加一行「仅覆盖有可更新版本的安全项，其余受影响包不会在此处理」；`emptyReason != nil` 时确认按钮禁用并显示原因。

调用点（reviewer-a）：
- `DashboardView.swift`「全部更新」按钮 → `appState.requestBatchUpdate(.all)`
- `UpdatesView.swift`「全部更新」→ `.all`；「更新安全项」→ `.vulnerable`；「更新所选」→ `.selected(...)`（用现有过滤后的 targets 的 id，`selection` 清空逻辑保持）
- 展示（lead）：`ContentView.swift` 挂 `.sheet(item:)` 呈现 `BatchUpdateSheet`。

### 2.2 诊断包导出（P0-08）

```swift
// AppState.swift（reviewer-c）
struct DiagnosticsExportPlan: Identifiable {
    let id = UUID()
    var includePackages: Bool   // 默认 false
    var includePaths: Bool      // 默认 false
}
var pendingDiagnosticsExport: DiagnosticsExportPlan?
func presentDiagnosticsExport()                       // createdDiagnosticsExport = .init(...)
func diagnosticsText(_ plan: DiagnosticsExportPlan) -> String
func saveDiagnostics(_ text: String)                  // NSSavePanel + 写入 + toast
```

内容与脱敏规则（必须与声明一致）：
- **默认**：不含包名（任务标题改为「安装 / 更新 / 卸载（包名已隐藏）」）、不含绝对路径（`$HOME`→`~`，其他路径显示为 `<已隐藏>`）、注入环境变量按 `KEY=value` 只保留非敏感键（如 `HOMEBREW_NO_AUTO_UPDATE`），含凭据的值（`user:pass@`、`://...@`）一律掩码为 `***`。
- 勾选「包含包名」才输出任务标题原样；勾选「包含本机路径」才输出 prefix/cellar/cache/repository 原值（仍把 `$HOME` 缩写为 `~`）。
- 末尾声明按实际内容动态生成：如「本诊断包不含包名与绝对路径」/「本诊断包包含包名，不含绝对路径」。
- `DiagnosticsSheet`（reviewer-c）：两个 Toggle + `ScrollView` 预览（`AppTheme.mono()`、`textSelection(.enabled)`）+「导出…」+ 取消；`SettingsView.swift` 的导出按钮改为 `presentDiagnosticsExport()` 并挂 `.sheet`。

### 2.3 批次汇总按包计数（P0-06）

`TaskQueueStore.finishBatchIfComplete`：当批次只有 1 个任务且该任务 `progressTargets` 非空（聚合的 `brew upgrade` / `--vulnerable`），不再用 `taskIDs.count` 计数，而是：
- `succeeded/failed/cancelled` = 该 `recordID` 名下 `progressItems` 对应状态计数；
- `skipped` = `batch.skipped + 该 recordID 名下 .skipped 行数`；
- `failedRecordIDs = [taskID]`（仅当 failed > 0，用于「重试」）；`failedTitles` = 失败行的包名；
- 其余字段语义不变，`TaskBatchSummary` 结构可保持，如加字段需同步 `Sheets.swift` 消费方（reviewer-b 不改该 sheet，若需改由 lead 协调）。
并发/多任务批次（更新所选）仍按任务统计——每个任务 = 一个包，语义正确。

### 2.4 退出守卫（P0-10）

新文件 `Brewbutler/App/QuitGuard.swift`：

```swift
@MainActor
final class QuitGuard: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var isTerminatingAfterCancel = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
}
```

- 无运行中任务 → `.terminateNow`。
- 有运行中任务（`appState?.tasks.isRunning == true`）→ `NSAlert`：标题「有任务正在运行」，说明「退出会中断当前变更，系统可能处于部分完成状态。brew 子进程会随任务取消结束。」；按钮「继续运行」（默认、等价取消退出）、「停止任务并退出」。用户选停止 → `appState.tasks.cancelCurrent()`，返回 `.terminateLater`，用 `Task { @MainActor in ... }` 每 100ms 轮询 `tasks.isRunning`，最多 10s，结束后 `NSApp.reply(toApplicationShouldTerminate: true)`；超时则 `reply(false)` 并提示。
- `MyApp.swift`：`@NSApplicationDelegateAdaptor(QuitGuard.self) private var quitGuard`；在 `WindowGroup` 内容与 `MenuBarExtra` 内容上都设置 `quitGuard.appState = appState`（用 `.onAppear` 或 `.task`；二选一确保冷启动 WindowGroup 先出现）。菜单栏「退出」保持 `NSApp.terminate(nil)` 即可（会走 delegate）。
- 不引入 `applicationShouldTerminateAfterLastWindowClosed` 之类改变既有窗口行为。

## 3. 逐条修复要点

### reviewer-a（仪表盘/更新页诚实性）
- **P0-01**（DashboardView.swift:67-73）：`securityDetail` 改为基于 `vulnReport`：无报告→「扫描未知」；`affectedFormulaCount == 0`→「本次扫描未发现」；否则「\(affected) 个受影响包（\(fixable) 个有修复）」；安全卡底部固定免责行「完整扫描仅覆盖 OSV 映射范围；未覆盖部分不代表无漏洞」。`:336-390` 的分布条 `total == 0` 同样不要用它来表示「全部安全」，改为「本次扫描未发现受影响包」并保持与头部覆盖信息同源。
- **P0-02**（DashboardView.swift:26-65）：header 增加数据来源/失败横幅：`refreshError` / `outdatedRefreshError` / `indexSourceNote` / `outdatedIsCached`；失败时统计卡数字显示「—」而不是 0；「重试」调用 `refreshIndex()`。文案参考 `UpdatesView.offlineNotice`（:113-140）。
- **P0-09**（UpdatesView.swift:238）：覆盖率/部分覆盖 badge/扫描时间移出 `if !securityEntries.isEmpty`，放到页面级 header（与「X 个可用更新 · Y 个安全更新」同区），无安全行也常显；维护页入口不在此任务范围。
- **P0-07 接线**：按 §2.1 改 3 个按钮；保留禁用逻辑（`index.outdated.isEmpty`→禁用仍成立，但 `.all` 的确认由 sheet 显示）。

### reviewer-b（危险动作闸门）
- **P0-03**（Sheets.swift:58,63-68）：`isConfirmEnabled` 增加 `dependents.isEmpty`；sheet 内原本的 warning 改为带列表的 SectionCard（前 8 个 + 「等 N 个」），并提供「查看依赖关系」按钮（`appState.selectPackage(...)` 打开第一个反向依赖的详情，或至少列名）——若实现成本高就只列名+说明，不阻塞。`PackageDetailView.swift:163-164,600-604` 的卸载按钮在 `dependents` 非空时禁用并加 help「有 N 个包依赖它」；`InstalledView.swift:205` 右键菜单同理禁用。批量卸载（Sheets.swift:108-110）需先过滤/标注有依赖的包：确认面板列出「N 个将被卸载，M 个因被依赖而跳过」；`AppState` 侧数据 `index.dependents(of:)` 已有，直接消费。
- **P0-04**（Sheets.swift:70,79-82）：勾选「删除关联文件」后展开明细：应用本体路径（来自 `PackageSnapshot.path` / `detail`）、体积（`detail.sizeBytes`，未知显示「未知」）、偏好/共享文件/登录项说明（基于 cask `zap` 语义，写明「brew 会删除 cask 声明的关联文件」）；若拿不到明细就明确写「brew 未提供删除明细，以下为通用说明」——不得假装已知。保留命令预览与默认取消。
- **P0-05**（PackageDetailView.swift:342-350）：`noFindingText` 增加跳过分支：`report.skippedFormulae.contains(package.name)` → 「该包不在 brew vulns 的 OSV 映射范围，本次未覆盖」；`vulnReport == nil` → 「尚未扫描」；cask → 现有文案。inspector 复用同一函数。

### reviewer-c（状态/队列/隐私）
- **P0-06**：按 §2.3 改 `finishBatchIfComplete`；`BatchSummarySheet`（Sheets.swift，reviewer-b 文件）如果显示口径需要调整，由 lead 协调，不在本任务内改。
- **P0-07**：按 §2.1 实现 `BatchUpdatePlan`/请求/确认/取消 + `BatchUpdateSheet`；确认时按 scope 调现有逻辑（`.all`→`upgradeAll()`；`.vulnerable`→`upgradeVulnerable()`；`.selected`→`bulkUpgrade(entries:)`）。`emptyReason` 覆盖：只读、无更新、全部锁定、全部进行中。
- **P0-08**：按 §2.2 实现；`exportDiagnostics()` 保留为 `presentDiagnosticsExport()` 兼容层或直接替换调用点。

### reviewer-d（退出守卫）
- 按 §2.4 实现 `QuitGuard` + MyApp 接线；不动 ContentView / AppState。

## 4. 里程碑 2/3 预告（暂不开始）

- M2 = 40 条 P1，按报告 §3 分四组（诚实/危险闸门/队列结果/信息与空态），M1 验收后按同样所有权模式分配。
- M3 = 48 条 P2，按主题分组（文案一致性、a11y/键盘、设置项承诺对齐、边界态）。
- 每个里程碑结束由 lead 统一跑 `xcodebuild` + `swift test --disable-sandbox`，并在 `docs/reviews/` 记录修复矩阵（finding → 变更文件 → 验证方式）。
