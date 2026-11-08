# M1 修复矩阵（10 条 P0）

> 依据：`docs/reviews/ux-review-2026-11-05.md` §1；计划与契约：`docs/reviews/fix-plan-m1.md`。
> 状态：**10 / 10 已修复**；全量 Debug 构建通过；单测 56 执行 / 53 通过 / 3 失败（均为 AGENTS.md §8 记录的 PTY 沙箱限制，非新增）。
> 日期：2026-11-06。验证方式：源码复核 + 全量构建 + `swift test --disable-sandbox`；交互行为需人工运行验证（见 §3）。

## 1. 逐条状态

| ID | 报告条目 | 修复内容 | 主要文件:行 | 状态 |
| --- | --- | --- | --- | --- |
| P0-01 | A-01 扫描「未发现」误导 | `securityDetail` 改用 `vulnReport.affectedFormulaCount` / `fixableFindingCount`；安全卡固定免责行「完整扫描仅覆盖 OSV 映射范围；未覆盖部分不代表无漏洞」；分布条 total==0 文案改「本次扫描未发现受影响包」并补 a11y | `Brewbutler/UI/DashboardView.swift:130-135, 229-230, 452` | ✅ |
| P0-02 | A-02 刷新失败不可见 | header 新增 `dataStatusNotice`：刷新/检查更新失败显示危险横幅 + 重试；缓存回退标注来源与时间；失败且无回退时数量显示「—」 | `Brewbutler/UI/DashboardView.swift:57, 63-110, 239` | ✅ |
| P0-03 | B-01 有依赖仍可卸载 | 卸载确认 `isConfirmEnabled` 增加 `dependents.isEmpty`；面板列前 8 个依赖 + 「等 N 个」；详情菜单 / inspector / 列表右键同步禁用并注明「被 N 个包依赖」；批量卸载只对有 0 依赖的包入队并标注跳过原因 | `Brewbutler/UI/Sheets.swift:52-76, 155-200`；`Brewbutler/UI/PackageDetailView.swift:163`；`Brewbutler/UI/InstalledView.swift:21-35, 206, 246-250` | ✅ |
| P0-04 | B-02 zap 删什么不透明 | 勾选「删除关联文件」后展示本体路径/体积与通用删除范围（偏好、共享文件、登录项），明确「brew 未提供删除明细」；详情缓存未加载时如实写「未知」；命令预览与默认焦点「取消」不变 | `Brewbutler/UI/Sheets.swift:92, 119+` | ✅ |
| P0-05 | B-03 跳过的包报「未发现」 | `noFindingText` 抽为共享 `packageNoFindingText`：区分「不在 OSV 映射范围、本次未覆盖」「尚未扫描、无法判断」，安全 tab 与 inspector 同源 | `Brewbutler/UI/PackageDetailView.swift:346, 356-357, 512-523, 578` | ✅ |
| P0-06 | C-01 批量升 30 报「成功 1」 | `finishBatchIfComplete` 对单任务聚合批次按 `progressItems` 逐包计数（成功/失败/取消/未验证/跳过），`failedTitles` 取失败包名；多任务批次语义不变；汇总面板最多列 5 条失败标题 + 「等 N 个」 | `Brewbutler/App/TaskQueueStore.swift:705-760`；`Brewbutler/UI/Sheets.swift:441-510` | ✅ |
| P0-07 | C-02 批量更新无确认 | 新增 `BatchUpdatePlan`（`.all/.selected/.vulnerable`）与 `BatchUpdateSheet`（默认焦点取消、Esc、列出包数与前 8 个包名、锁定/进行中跳过说明、手动安装提醒）；空计划/只读/重复操作直接 toast 不弹窗；三个入口全部接入 | `Brewbutler/App/AppState.swift:214-260, 1073-1170`；`Brewbutler/UI/BatchUpdateSheet.swift`；`Brewbutler/UI/DashboardView.swift:48`；`Brewbutler/UI/UpdatesView.swift:114, 193, 338`；`Brewbutler/ContentView.swift:67-68` | ✅ |
| P0-08 | D-01 诊断包与隐私声明矛盾 | 新增 `DiagnosticsExportPlan` + `DiagnosticsSheet`：默认隐藏包名与绝对路径（`$HOME`→`~`、其余 `<已隐藏>`）、注入变量按敏感过滤、`user:pass@` 脱敏；导出前可预览；隐私声明按实际内容生成；移除旧的未脱敏导出 | `Brewbutler/App/AppState.swift:238-245, 1777-1899`；`Brewbutler/UI/DiagnosticsSheet.swift`；`Brewbutler/UI/SettingsView.swift:328-341` | ✅ |
| P0-09 | D-02 无安全更新时覆盖率消失 | 覆盖率 / 部分覆盖 / 扫描时间移到更新页 header 常显；无报告显示「漏洞扫描尚未运行 · 覆盖范围未知」；维护页新增漏洞历史入口 | `Brewbutler/UI/UpdatesView.swift:125-139, 271` | ✅ |
| P0-10 | E-01 运行中退出无确认 | 新增 `QuitGuard`（`NSApplicationDelegate`）：有运行/排队任务时 NSAlert「继续运行（默认）/ 停止任务并退出」；停止时暂停队列→取消→`terminateLater`→轮询最多 10s，超时取消退出并提示 | `Brewbutler/App/QuitGuard.swift`；`Brewbutler/MyApp.swift:7, 27, 46` | ✅ |

## 2. 验证记录

- 全量构建（M1 集成后，含 reviewer-b 收尾）：
  `xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData MODULE_CACHE_DIR="$PWD/build/modulecache" 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build`
  → `** BUILD SUCCEEDED **`（日志 `build/uxfix-m1-final-build.log`；唯一 warning 为 AppIntents 元数据提示，与代码无关）。
- 单测：`swift test --disable-sandbox --scratch-path build/swiftpm-scratch`（需 `CLANG_MODULE_CACHE_PATH` 指向仓库内，否则沙箱内 clang 模块缓存不可写）
  → 56 tests，53 通过，3 失败：`ProcessIntegrationTests.testMergedOutputAndExitCode` / `testTimeoutEscalatesAndFinishes` / `testTaskCancellationTerminatesChild`，错误均为 `spawnFailed(1)`（openpty 沙箱限制，见 AGENTS.md §8），**无新增失败**（日志 `build/uxfix-m1-swift-test2.log`）。

## 3. 残留风险 / 需人工验证

1. **聚合任务在开跑前失败**（如 brew 缺失导致单条升级记录直接 failed）：逐包行仍被标为 skipped，`BatchSummarySheet` 以兜底提示「本次没有包被执行：N 个包未执行」呈现，而非「1 个任务失败」。要显示任务级失败数需在 `TaskBatchSummary` 增加字段（TaskModels），留待 M2/M3 统一处理。
2. **`NSSavePanel.runModal()` 在已呈现的 sheet 内调用**（诊断导出）需运行验证；若出现面板不显示/层级异常，改 `beginSheetModal`。
3. **QuitGuard 交互**（NSAlert 按钮焦点、10s 超时、菜单栏退出、任务运行中 ⌘Q）需人工验证；冷启动窗口未出现且未开菜单栏时可能未注入 `appState`（低风险）。
4. 依赖闸门按快照判定：卸载确认打开后依赖关系变化不会被感知（与 brew 行为一致），可在 M2 复核是否需要二次校验。
5. P0-07 的批量更新确认在运行时需验证 sheet 与任务队列的呈现顺序（确认后立即关 sheet 再入队）。

## 4. 未做项

- 无交互式 App 运行（沙箱内不做人工点按），上述交互类修复只做源码级复核与编译验证；不执行任何变更类 brew 命令。
