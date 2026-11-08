# S 组复核：已安装列表 / 包详情 / 弹层（reviewer-b）

- 范围：`Brewbutler/UI/InstalledView.swift`、`PackageDetailView.swift`、`Sheets.swift`、`BatchUpdateSheet.swift`；修复 ID B-13～B-19、P0-03/04/05/06/07。
- 方法：只读代码走查，沿「用户点哪里 → action → 状态 → 最终看到什么」；仓库无 diff 基线（重命名未提交），行号为 2026-11-06 当前工作树。
- 口径：✅ 成立 / ⚠️ 部分成立 / ❌ 不成立或引入新问题；P0=据此做错决定/危险无兜底；P1=主流程受阻或明显误导可绕过；P2=打磨/一致性/可发现性。

**一句话结论**：修复方向正确，危险文案与依赖阻断明显进步，但「可执行性」仍由视图 disabled、sheet 开关、enqueue 运行时三层各判各的：12 项里 3 ✅ / 8 ⚠️ / 1 ❌；最严重的是未扫描包仍显示「本次扫描未发现」（P0），以及重试路径绕过卸载闸门（P1）。

## 1. 逐条判定

| ID | 判定 | 证据与说明（文件:行） |
| --- | --- | --- |
| B-13 批量卸载分组 | ⚠️ 部分 | 已按 formula/cask 分组、确认数=实际可卸载数、被依赖包列出原因（Sheets.swift:154-211）；但 cask 组无 zap，只提示去详情页逐个操作（Sheets.swift:186），原建议的组级 zap/命令预览未落地。 |
| B-14 cask 锁定 | ✅ 已修 | cask 可锁定/解锁且命令带 `--cask`（PackageDetailView.swift:156-162、AppState.swift:1553-1559），pinHelp 与 auto_updates 例外齐（PackageDetailView.swift:195-203、Sheets.swift:301-306）；仅 7.0.12 实测支持，见 V3。 |
| B-15 摘要/空态 | ⚠️ 部分 | 筛选时显示「显示 M / 共 N 个包」（InstalledView.swift:257-265），空态新增发现页入口（376-379）；但 formula/cask/可更新数仍取全量（265），与筛选后列表不匹配。 |
| B-16 行尾 ⋯ | ⚠️ 部分 | ⋯ 常显（40% 不透明度）且独立 a11y（InstalledView.swift:799-826）；但无快捷键打开行菜单（584-598 仅 ⌘F/⌘A/⌘⌫），「键盘可达」依赖系统全键盘访问。 |
| B-17 卸载绝对承诺 | ✅ 已修 | 改「本次已安装快照中未发现依赖方…」（PackageDetailView.swift:493）；未装依赖的禁用安装带 help（478-486）；依赖非空三处禁用并注明数量（181-185、737-742、516/811）。 |
| B-18 安装确认信息 | ⚠️ 部分 | 新增类型/来源/版本/体积/auto_updates 行，未知写「未知」（Sheets.swift:337-342）；但版本/体积恒未知、来源是套话（384-388），349 行「brew 未提供安装前预检接口」与 technical-notes.md:39-41 冲突（B2-09）。 |
| B-19 锁定风险 | ⚠️ 部分 | 风险说明 + auto_updates 例外已加（Sheets.swift:296-306），批量锁定/解锁入口已有（InstalledView.swift:556-567）；但未列受影响的已安装依赖方，sheet 也无 isConfirmEnabled（仅靠 InstalledView.swift:654-657 guard）。 |
| P0-03 被依赖阻断卸载 | ⚠️ 部分 | 五个入口同步禁用：详情 ⋯（181-185）、inspector（737-742）、列表右键（516-520）、行 ⋯（811）、卸载面板（59）+ 批量跳过（154-211）；但依赖映射可能漏报（B2-02）、重试绕过闸门（B2-01）。 |
| P0-04 zap 明细 | ⚠️ 部分 | 通用范围 + 本体路径/体积 + 未知兜底齐（Sheets.swift:107-141）；但详情未加载时无出路（128）、标题归因错误（121）、命令预览缺 `--zap`（82）。 |
| P0-05 未覆盖不得写「未发现」 | ❌ 未修 | 共享函数与三分支存在（PackageDetailView.swift:607-618），但只判 skippedFormulae，不判 unscanned_formulae/complete → untrusted tap 包落到「本次扫描未发现」（617），与 DashboardView.swift:431-438 冲突。 |
| P0-06 汇总面板 | ✅ 已修 | 按 progressItems 逐包计数、failedTitles 取包名、前 5 +「等 N」（TaskQueueStore.swift:922-980、Sheets.swift:650-714）；多任务分支用任务标题（970）可接受。 |
| P0-07 BatchUpdateSheet | ⚠️ 部分 | Plan 三 scope、确认页包数/前 8 名/跳过说明、默认焦点取消齐（BatchUpdateSheet.swift:21-64）；但 .all/.vulnerable 执行时重算集合（AppState.swift:1345-1364），与 sheet 的「进行中跳过」不一致（B2-08），Esc 仅靠系统行为。 |

判定统计：✅ 3 · ⚠️ 8 · ❌ 1；新增问题 11 条（P0×1、P1×3、P2×7）。

## 2. 新发现问题

### P0

- **B2-07 未覆盖包仍显示「本次扫描未发现」**
  - 用户看到：打开来自 untrusted tap 的包 →「漏洞」tab 显示「本次扫描未发现该包的漏洞记录。」
  - 代码位置：PackageDetailView.swift:607-618（else 617）；BrewModels.swift:545 已解码 `unscanned_formulae`，DashboardView.swift:431-438 也如实列出；technical-notes.md:183 要求如实呈现部分覆盖。
  - 影响：把「未扫描」当「无漏洞」，用户可能据此保留风险包——正是 P0-05 要消除的决策误导。

### P1

- **B2-01 任务重试绕过卸载闸门**
  - 用户看到：失败过的 `brew uninstall --cask --zap X` 记录，在任务历史点「重试」→ 只有命令预览 + 一次确认。
  - 位置：Sheets.swift:600-625；TaskQueueStore.swift:426-456 直接复用原 commandText/run，不复查 dependents、不要求重输包名。
  - 影响：期间新装的依赖方会被一并卸掉；zap 失去「输入包名」二次确认（违反 AGENTS 危险动作约束 7）。
- **B2-02 dependents 可能漏报**
  - 用户看到：「被 0 个包依赖」→ 卸载按钮可用。
  - 位置：反向依赖以 `dependencies + runtimeDependencies.fullName` 作键（PackageSnapshot.swift:407-416、120-127），`dependents(of:)` 用短名 `package.name` 查（213-215）。
  - 影响：tap 包以全名入键时依赖数漏报，卸载闸门与全部禁用态失效；静态推断，需 V2 用 tap 依赖 fixture 复核。
- **B2-06 zap 命令预览与实际不一致**
  - 用户看到：勾选「同时删除关联文件」后，确认页仍显示 `brew uninstall --cask X`。
  - 位置：Sheets.swift:82 用不含 zap 的 `uninstallCommand`（PackageSnapshot.swift:136-141），实际入队含 `--zap`（AppState.swift:1142-1160）。
  - 影响：危险操作预览少关键参数，用户据预览误判删除范围。

### P2

- **B2-03 只读口径三处不一致**
  - 用户看到：只读模式下右键「卸载…」/「更新到」仍可点，⌘⌫ 与安装确认也能打开完整面板。
  - 位置：InstalledView.swift:501-504（更新只判 pinned）、516-520（卸载只判 dependents）、584-592/677-683（⌘⌫ 不判只读）；AppState.swift:1109-1117 与 Sheets.swift:366-370（安装不判只读）。
  - 影响：确认后必然在 enqueue 处 toast 失败（AppState.swift:1088-1097），多一次无效且无预警的操作。
- **B2-04 zap 明细没有「出路」**
  - 用户看到：「未知（在详情页打开后可读取路径与体积）」，但 sheet 内无入口。
  - 位置：Sheets.swift:128；AppState.swift:387 只保留最近加载的 detail → 从列表右键打开时几乎必然命中该分支。
  - 影响：用户须取消 → 进详情 → 重新打开卸载，易放弃查看明细。
- **B2-05 zap 标题把实现缺口说成 brew 能力缺口**
  - 用户看到：「brew 未提供删除明细」。
  - 位置：Sheets.swift:121，与 technical-notes.md:191（artifacts 的 zap 可用于可视化「卸载将删除什么」）冲突。
  - 影响：误导用户与后续维护者，掩盖可改进空间。
- **B2-08 批量更新确认集 ≠ 执行集**
  - 用户看到：sheet 写「将更新 N 个包 / 已跳过：进行中 M」，结果面板行数与已跳过数却对不上。
  - 位置：BatchUpdateSheet.swift:28、103-113；AppState.swift:1218（.all 的 progressTargets 含进行中包）、1255（.vulnerable 的 pinned 跳过未传 beginBatch）。
  - 影响：确认页的「数量承诺」不可信，削弱 P0-07 的核对价值。
- **B2-09 安装「来源」不可用、349 行结论过强**
  - 用户看到：「来源：homebrew/cask 或第三方 tap（由 brew 解析）」，没有具体 tap。
  - 位置：Sheets.swift:384-388、349；与 technical-notes.md:39-41、186-192（`brew info --json` 可查未装包/cask 的 version/tap）冲突。
  - 影响：装错同名 tap 包的概率未被消解，且把未接预检说成 brew 不支持。
- **B2-10 覆盖率分母含 cask**
  - 用户看到：详情页「覆盖 36/59 个包」，inspector 健康区却是「覆盖 36/39 formula」。
  - 位置：PackageDetailView.swift:422 用 `index.packages.count`；AppState.swift:764-783 用 `scannableFormulaCount`。
  - 影响：同包两处覆盖率口径不一致，用户难以判断真实覆盖。
- **B2-11 锁定面板不给影响面**
  - 用户看到：仅泛化「依赖该包新版本的其他包可能无法安装或运行」。
  - 位置：Sheets.swift:296-300；dependents 数据本可用（PackageDetailView.swift:12/135）。
  - 影响：批量锁定时无法评估代价，只能盲确认。

## 3. 系统性问题

- **S-1「可执行性」三层各判各的**：视图 `.disabled`、sheet `isConfirmEnabled`、`enqueue` 运行时 toast 三套判断重复且不一致（只读/依赖/zap 均有入口漏判，见 B2-01/B2-03）。建议 AppState 暴露 `uninstallAvailability(_:) -> (allowed, reason, nextStep)` 与 `canInstall`，所有入口只读同一结果。
- **S-2「确认集合」打开时算、执行时重算**：BatchUpdatePlan 注释承诺「confirmation always shows the same package set the queue will receive」（AppState.swift:264-284），但 .all/.vulnerable 走 upgradeAll/upgradeVulnerable 重新取集合（1345-1364），与 sheet 漂移（B2-08）。确认面板应只渲染 plan，执行只用 `plan.packageIDs + plan.skipped`。

## 4. 需实机验证

- V1 Esc 是否关闭 4 个 sheet：仅 `.keyboardShortcut(.defaultAction)`（Sheets.swift:26-34、BatchUpdateSheet.swift:52-57），注释称「Esc 由系统行为提供」，未用 `.cancelAction`。
- V2 tap 依赖下 dependents 计数（B2-02）：装一个依赖 tap 公式的包，看「被 N 个包依赖」是否为 0。
- V3 brew 7.0.0–7.0.11 执行 `brew pin --cask` 是否失败（只读阈值 <7.0；technical-notes.md:73 仅 7.0.12 实测）。
- V4 只读模式（brew<7.0）右键卸载 / ⌘⌫ 批量卸载 / 安装确认：按钮是否可点、点后是否只得到 toast。
- V5 untrusted tap 包详情「漏洞」tab 文案（应复现 B2-07）。
- V6 .all 批量更新存在进行中包时，sheet 的「将更新 N / 已跳过 M」与结果面板行数是否一致。
- V7 cask zap 卸载：确认页命令 vs 任务日志实际命令（静态已确认不一致，B2-06）。
- V8 辅助功能大字号下 400/460pt 固定宽 sheet 是否截断（Sheets.swift:38、BatchUpdateSheet.swift:68、Sheets.swift:738）；VO 读序：依赖 chips / 取消-确认 / 行尾 ⋯。

_只读复核，未运行 app 或 brew；以上行号已逐条对照当前工作树。_
