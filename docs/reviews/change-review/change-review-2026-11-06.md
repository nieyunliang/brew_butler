# Brewbutler 修改复核报告（2026-11-06）

> 评审对象：2026-11-06 针对 2026-11-05 UX 评审（98 条：10 P0 / 40 P1 / 48 P2）所做的 M1/M2/M3 修复。
> 评审角度：用户交互（操作路径、反馈、口径、边界状态），不重审架构本身。
> 判定依据：三份 fix-matrix 的**声称** + 源码实际路径（无 git diff 基线：HEAD 仅模板 Initial Commit，全部实现 untracked），并以本机构建与测试复核为佐证。

---

## 0. 结论先行

**修复方向正确、主链路可用，但不能宣布「98 条全部修复」。**

| 分组 | 覆盖条目 | ✅ 成立 | ⚠️ 部分 | ❌ 未成立 |
| --- | --- | --- | --- | --- |
| S 外壳/菜单栏/快捷键 | 17 | 9 | 8 | 0 |
| A 仪表盘/发现/引导 | 18 | 10 | 8 | 0 |
| B 已安装/详情/确认面板 | 12 | 3 | 8 | 1 |
| C 更新/队列/日志 | 15 | 8 | 7 | 0 |
| D 设置/诊断/状态源 | 15 | 5 | 9 | 1 |
| **合计** | **77（含 4 条跨组重复）** | **35** | **40** | **2** |

Lead 更正：D 组原报的 P0-08 ❌ 为**误报**（见 §5.6），更正后 `P0-08` 成立；唯一未成立项为 `P0-05`（未扫描包仍写「未发现」，**P0 级残留**）。`D-04`（诊断路径状态）仍为部分成立。

新发现去重后 **54 条**：**1 个 P0 + 12 个 P1 + 1 条 P1 待 fixtures 复核 + 40 个 P2**。发布前建议至少清掉 P0 与 P1。

**本机验证**
- `swift test --disable-sandbox`：56 个用例、3 个失败，恰为 AGENTS.md §8 记录的 3 个 PTY 用例（`testMergedOutputAndExitCode`、`testTaskCancellationTerminatesChild`、`testTimeoutEscalatesAndFinishes`，失败均为 `spawnFailed(1)`，`Brewbutler/Core/Process/SpawnedProcess.swift:66`），**无新增失败**。
- Debug 构建：直接构建首次失败（环境：`sandbox-exec: sandbox_apply: Operation not permitted` 导致宏插件返回 malformed response）；按 AGENTS.md §8 追加 `'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'` 后 **BUILD SUCCEEDED**（`build/review-build-check2.log`）。

---

## 1. 修复中做得好的部分

这些不是客套，是本次修改真正的质量增量：

1. **危险动作闸门**：卸载查 `dependents` 阻断（`UninstallSheet`）、`--zap` 要求输入包名、批量卸载区分「可直接卸载/需先处理」——P0-03/04 的机制层修复成立。
2. **批量更新从「无确认直发」变成「范围确认」**：`BatchUpdatePlan`（`Brewbutler/App/AppState.swift:266-285`）+ `BatchUpdateSheet` 把「将更新 N 个（formula a · cask b）」「已跳过锁定/进行中」摆到确认页，P0-07 方向正确，且三个入口统一走 `requestBatchUpdate`。
3. **诊断隐私**：`DiagnosticsExportPlan` 默认 `includePackages/includePaths = false`，文案真实列出「包含/不包含」并做路径脱敏，P0-08 的实质修复成立（见 §5.6 对误报的更正）。
4. **退出守卫方向**：`QuitGuard` 拦截 ⌘Q、默认焦点在「继续运行」、超时后取消退出并二次提示，P0-10 的模型是对的（缺口见 P1-3）。
5. **队列可解释性**：任务抽屉有 pending 位次、取消会暂停队列、批次有汇总、失败可重试——「队列只是数字」的老问题基本解决。
6. **错误恢复路径**：诊断页对 `sandbox_apply` 等沙箱错误给出可复制的诊断包；批处理失败带 command/exitCode/tail。

---

## 2. 发布前必须修（P0 / P1）

### P0-1 未扫描包仍显示「本次扫描未发现该包的漏洞记录」

- 位置：`Brewbutler/UI/PackageDetailView.swift:607-618`（`packageNoFindingText`）
- 判决逻辑只覆盖 `report == nil`、cask、`report.skippedFormulae`，**没有判 `unscannedFormulae` / `report.complete`**，落到 else 返回「本次扫描未发现该包的漏洞记录。」
- 而 `unscanned_formulae` 已解码（`Brewbutler/Core/Models/BrewModels.swift:545`），仪表盘也如实列出（`Brewbutler/UI/DashboardView.swift:431-438`）。
- 用户影响：打开一个来自不受信 tap、本次未扫描的包，漏洞 Tab 给出「未发现」——正是 P0-05 要消除的误导。修复：复用仪表盘同一口径，显示「未扫描（原因：…）+ 覆盖率」；`complete == false` 时禁止出现「未发现」。
- 对应：`S-installed-detail-sheets.md` B2-07。

### P1（12 条）

| # | 问题 | 证据 | 用户影响 |
| --- | --- | --- | --- |
| 1 | toast「查看」打开**旧任务日志** | `TaskQueueStore.swift:547` 启动任务只 `showDrawer = true`，不清 `selectedRecordID`（`:184-195` 优先显示选中记录）；`ContentView.swift:36` 只传 showDrawer；`AppState.swift:2185` 的 `openLogDrawerFromToast` 全仓 0 调用 | 失败 toast 点「查看」，抽屉展示上一次的日志，用户看不到本次失败原因 |
| 2 | 关闭任一全局弹层会**清空全部 9 个状态源** | `ContentView.swift:96-106`（setter 收到 nil 逐项置 nil） | 清理/批量更新弹层打开期间后台完成批次 → 汇总被静默丢弃；确认面板可能被结果面板替换；关闭动作产生不可解释的丢失 |
| 3 | 退出守卫漏掉「队列还有排队任务」 | `QuitGuard.swift:20-22` 只判 `isRunning`（`currentRecordID != nil`）；取消后队列 `isPaused`、pending 仍存在 | ⌘Q 在「取消后队列暂停」状态直接退出，排队任务无提示丢弃；10s 等待无进度反馈 |
| 4 | 健康卡用**旧结果**冒充本次健康 | `AppState.swift:1770-1785` catch 只写 `doctorError`，不清 `doctorReport`；`DashboardView.swift:603-619` 先渲染 report、`issues.isEmpty` 即绿色「环境健康」，error 分支在 report 之后才可达；退出码不参与判色 | 上次 doctor 成功、本次执行失败 → 卡片绿色 + 「复制摘要」复制旧报告 |
| 5 | 索引失败时「可更新」显示 **0** 而非「—」 | `DashboardView.swift:68-70,162-171` 的 `outdatedUnavailable` 只认 `outdatedRefreshError`；info 失败且无缓存时该错误为 nil（`AppState.swift:640-661,702-709`） | 用户看到「0 个可更新」，误以为已是最新 |
| 6 | 失败任务重试**绕过危险闸门**，且界面出现 `--zap` | `TaskQueueStore.swift:426-456` 复制原 `ChangeTask`；`Sheets.swift:600-625` 只展示 `record.commandText`；依据 AGENTS.md §5.12 界面不应出现参数串 | 失败的强删重试不再查 dependents、不要求输入包名；同时违反术语硬规则 |
| 7 | 强删确认页**命令预览缺 `--zap`** | 预览用 `package.uninstallCommand`（`Sheets.swift:82`，`PackageSnapshot.swift:136-141` 只拼 `brew uninstall --cask X`）；实际入队 `AppState.swift:1142-1160` 带 `--zap` 且标题「并删除关联文件」 | 危险操作「将执行：」少关键参数，用户核对的是错的命令 |
| 8 | 批次「全部完成」不看取消/跳过 | `LogDrawerView.swift:220-228` 仅 `failed == 0` 即写「全部完成」 | 30 包取消 3 个，日志仍写「全部完成」 |
| 9 | 未确认（unverified）被计为**成功**，三处口径打架 | `TaskQueueStore.swift:772-776` 把 `.unverified` 映射为 `.succeeded`；汇总 `:946-949` 又把成功置 0；`Sheets.swift:742-744` 的 `hasFailedItems` 漏 unverified | 面板全绿「30/30」、汇总「成功 0 / 未确认 30」、日志「全部完成」 |
| 10 | 自动检查时间戳**失败也写**，手动刷新也写 | `AppState.swift:2364`（成功）、`:2380`（catch）、`:698`（手动）都写 `lastAutoCheckAt`；页头只显示相对时间（`UpdatesView.swift:267-281`） | 离线/失败用户看到「刚刚检查」，陈旧数据被当新鲜 |
| 11 | 「0 个安全更新」时范围说明再次消失 | `UpdatesView.swift:427-429` 首行 `guard !securityEntries.isEmpty else { return nil }`，按钮同条件隐藏（`:392-397`） | 扫描发现受影响包但都无可用更新时，用户再次失去「覆盖 0/59 · 未扫描 3」的上下文（P0-09 同源残留） |
| 12 | 坏 brew 路径被**静默接受并持久化**；坏候选无标记 | `BrewLocator.swift:19-51` override 失败后继续遍历固定路径，任一成功即返回，不校验路径；`AppState.swift:544-568` 先写 `brewPathOverride` 再仅按 `!success` 回滚。`SettingsView.swift:354-374` 只给 `!isExecutable` 打徽章；`versionText == nil && isExecutable`（`BrewLocator.swift:171-172`）无提示且仍可点 | 用户设置了一个坏路径，界面显示成功、仍用旧 brew；「可执行但版本取不到」的候选被当成正常选项 |

> 待 fixtures 复核（不升级为已确认）：dependents 查询可能因短名/全名键不一致漏报（`PackageSnapshot.swift:123,407-416` 以 `fullName` 建 `allDependencies`，`:213-215` 用短名查；现有测试仅覆盖 `reverseDependencies["libvmaf"]`，`Tests/BrewbutlerCoreTests/CoreTests.swift:79`）。若成立，P0-03 的闸门存在漏网，应升 P0。

---

## 3. 建议修（P2，按主题）

### 3.1 外壳 / 窗口 / 菜单栏
- ⌘N 可开第二个主窗口共享同一 `AppState`（`MyApp.swift` 未替换 `.newItem`）→ 两个窗口的弹层/选择互相打架。
- 主窗口关闭后 ⌘, 无反应：`MyApp.swift:85-91` 用 `NSApp.windows.first(where: canBecomeMain)`；菜单栏「打开主窗口」用的是 `openWindow`（`MenuBarView.swift:41`）才对。
- 关窗（红点）不提示运行中任务：全仓无 `windowShouldClose` / `NSWindowDelegate`（P0-10 只修了退出路径）。
- `focusRing`（`AppTheme.swift:151`）全仓 **0 调用**；行焦点在发现页/已安装页表现不一致（`DiscoverView.swift:231` vs `InstalledView.swift:417`）。
- 菜单栏计数：含 pinned 包（`S-12`）、无覆盖率/扫描时间（P0-09 残留）、最近任务不可点、无「停止任务」入口。
- 通知点击无深链：全仓无 `UNUserNotificationCenterDelegate`；正文写「打开更新页查看」（`AppState.swift:745-750,835-840`），点击只打开 App 不跳转。
- toast 无点击/Esc 关闭（`dismissToast` `AppState.swift:2178` 与 `openLogDrawerFromToast` `:2185` 均 0 调用，注释承诺未实现）；失败文案无 `lineLimit`；sheet 打开时 toast 位于 sheet 之后不可见。
- onboarding 用 Esc 关闭不写 `onboardingCompleted`（`ContentView.swift:96-106` 只清源；`AppState.swift:2209` 才写）→ 每次启动重弹；未加 `interactiveDismissDisabled`。
- 命令面板动作不读禁用态（`CommandPaletteView.swift:274-297` 无 `.disabled`）→ 扫描中/只读/刷新中仍可点，靠内部 guard 兜底。

### 3.2 已安装 / 详情 / 危险确认
- 只读模式下「卸载」右键菜单/⌘⌫、行内「更新」仍可按（`InstalledView.swift:501-520,584-592`；`UpdatesView.swift:960-966`）→ 点击后才 toast 报错。
- `--zap` 明细行没有「在 Finder/终端查看」出路（B2-04），「其中 y 项在应用内更新不了」归因到错误标题（B2-05）。
- cask 组没有「删除关联文件」入口（B-13）；锁定面板不展示依赖影响面、无 `isConfirmEnabled`（B-19）。
- 安装确认页版本/体积恒「未知」、来源是固定套话（B2-09）；「349 行结论」对未检查项的推断过强。
- 漏洞覆盖率分母含 cask（B2-10）——分母与实际扫描对象不一致。
- 摘要区数字与当前筛选结果不一致（B-15）；行右键菜单无快捷键（B-16）。
- 页面级 `.sheet` 未收敛：`UpdatesView.swift:145`、`InstalledView.swift:185/188`、`PackageDetailView.swift:68/749`、`SettingsView.swift:696` 仍是页面内挂载，与 `ContentView` 的单一 `ShellSheet` 同窗争抢风险仍在（E-17 声称过度）。

### 3.3 更新 / 批次 / 队列
- 批次运行中追加任务：面板分母跳变、`progressTitle` 仅 nil 时赋值（C2-06/C-17）。
- 聚合批次「重试」重跑全部目标且不再生成汇总（C2-07）；`stillOutdated` 失败行带「退出码 0」徽章、可能指向错误包（C2-05）。
- 汇总面板无「查看任务日志」入口（`Sheets.swift` 底部只有「关闭」）；多失败时 10 个同名「重试」按钮无法分辨（C2-08 + Lead）。
- `⌘.` 只在任务抽屉内生效，无全局取消（C2-09）；菜单 ⌘R 无禁用/无反馈（C2-11）；「复制完整日志」在主线程同步读 ≤50MB（C2-12）。
- 扫描进度 `checked` 常为 0，首扫取消后文案仍写「保留上次结果」（A2-05）。
- 服务页忙碌菊花无位次说明、队列暂停时永久转圈（C2-10）。

### 3.4 仪表盘 / 发现 / 维护
- 搜索报错被误标为「网络错误」、真实错误不可达（A2-04）；搜索结果点行只高亮不打开（A2-10）。
- 刷新失败后「索引来自缓存」标随时间倒推自相矛盾（A2-07）；旧横幅冒充当前错误（A2-08）；刷新中无进度（A2-07）。
- 取消中的队列行仍显示「排队中」（A2-10）。
- 部分覆盖时 `SeverityDistributionBar` 仍固定成功色 + 「本次扫描未发现受影响包」（`DashboardView.swift:468-470,498-508`）。
- **fix-matrix 声称「维护页新增漏洞历史入口」但 `MaintenanceView.swift` 无任何 vuln/漏洞 引用**——未实现（见 §5）。

### 3.5 设置 / 诊断 / 状态同步
- 通知授权不随系统设置刷新：全仓无 scenePhase/激活监听；「重新检查授权状态」实际再请求一次授权（`SettingsView.swift:489-492` → `AppState.requestNotificationPermission()`）。
- `lastBrewCheck`/自动检查/手动刷新各写各的时间戳（D2-05）。
- 诊断/状态源存在多处「界面声明的状态 ≠ 实际执行的状态」（D-04 部分成立）。

---

## 4. 系统性问题（比单条 bug 更值得处理）

1. **「状态真相」没有单一出口**：扫描覆盖、可更新、doctor、自动检查时间、批次结果各有各的判定与文案，导致同一个事实在不同页面呈现不同结论（P0-1、P1-8/9/10/11、§3.4 都是它的症状）。建议把「覆盖率/新鲜度/健康」收敛为状态层派生值，UI 只读。
2. **弹层状态源仍被「关闭动作」越权清空**：`ShellSheet` 的 setter(nil) 清 9 源（P1-2），且页面级 sheet 尚未纳入同一仲裁；关闭一个弹层 = 静默丢弃另一件事。
3. **同一动作多入口、禁用态与结果定位不一致**：菜单/命令面板/页面按钮/菜单栏/通知五处对「更新、刷新、扫描、退出」的加工不同（S-11、S-12、§3.1）。
4. **危险操作的可核对性不足**：预览命令与实际入队命令不一致（P1-7）、重试绕过闸门（P1-6）、强删明细无出路（§3.2）。这是本次修改中最值得回头补的一类。

---

## 5. 与修复声明不一致之处（fix-matrix 复核）

| 声明 | 实际 | 结论 |
| --- | --- | --- |
| P0-05 已修（未扫描不再写「未发现」） | `packageNoFindingText` 不判 `unscannedFormulae`（P0-1） | **未闭环** |
| P0-09 已修（覆盖率常显） | 更新页空安全更新时整段返回 nil；扫描失败被写成「尚未运行」；菜单栏计数无覆盖率 | 部分成立 |
| P0-09 附「维护页新增漏洞历史入口」 | `MaintenanceView.swift` 无 vuln/漏洞 引用 | **未实现** |
| E-17「收敛为单一 `.sheet(item: shellSheet)`」 | 仅收敛 9 个全局源，5 处页面级 sheet 仍在 | 声称过度 |
| E-15「新增 `View.focusRing`」 | 有定义（`AppTheme.swift:151`），全仓 0 调用；reduceMotion 确有使用（`SidebarView.swift:227-236` 等） | 部分成立；评审员「reduceMotion 未用」表述有误 |
| P0-10 已修 | 只拦退出（⌘Q/菜单栏退出），关窗路径无 `windowShouldClose` | 部分成立 |
| P0-08 诊断导出入入口 | 按钮与 `.sheet` 同在 `AdvancedSettingsPane`（`SettingsView.swift:535-721`，sheet :696-703），路径可用，隐私默认关闭已核实 | **评审员 D2-01 误报，成立** |
| fix-matrix 行号可复验 | P0-06 声称 `TaskQueueStore.swift:705-760`，实际 `:922-980`；C-14 声称 `LogDrawerView.swift:690`，文件仅 680 行 | 行号不可作复验依据，须按符号名定位 |

---

## 6. 实机验证清单（建议发布前执行）

1. 退出三路径：⌘Q、菜单栏「退出」、Dock 退出——运行中都有确认；取消后队列暂停时 ⌘Q 不再静默丢弃（P1-3）。
2. 关窗（红点）时有任务运行：是否应提示「任务将在后台继续」（S-05）。
3. 弹层仲裁：打开清理面板 → 后台完成一次批量更新 → 关闭清理面板，汇总是否出现（P1-2）。
4. 失败 toast 点「查看」是否定位到**本次**失败记录（P1-1）。
5. 未扫描包（untrusted tap）打开漏洞 Tab，是否出现「未扫描」而非「未发现」（P0-1）。
6. 强删确认页与实际入队命令是否一致；失败强删重试是否再次要求输入包名（P1-6/7）。
7. 扫描 `complete=false` / 0 个安全更新时，更新页是否仍显示覆盖率与扫描时间（P1-11）。
8. 30+ 包批量更新中取消 3 个：日志、抽屉、汇总三处文案是否一致（P1-8/9）。
9. E-16 菜单栏外观跟随设置；E-18 命令面板方向键不被输入框吞掉（需实机）。
10. 系统字号调大：正文可读、45 处 9–13pt 固定尺寸是否溢出（E-15 已声明残余）。

---

## 7. 验证记录与证据

- 源码：43 个 Swift 文件、12,963 行；改动 25 个文件；新增 `App/QuitGuard.swift`、`UI/BatchUpdateSheet.swift`、`UI/DiagnosticsSheet.swift`。
- 测试：`CLANG_MODULE_CACHE_PATH=$PWD/build/clang-module-cache swift test --disable-sandbox --scratch-path build/swiftpm-scratch` → 56 执行 / 3 失败（已知 PTY 三项，`spawnFailed(1)`）→ 无新增失败；日志 `build/review-test-check.log`、`build/review-test-filter.log`。
- 构建：`xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build` → **BUILD SUCCEEDED**；日志 `build/review-build-check2.log`。直接构建失败是沙箱宏插件限制，非源码问题。
- 分组报告：
  - `docs/reviews/change-review/S-shell.md`（172 行）
  - `docs/reviews/change-review/S-dashboard-onboarding.md`（104 行）
  - `docs/reviews/change-review/S-installed-detail-sheets.md`（99 行）
  - `docs/reviews/change-review/S-updates-queue.md`（120 行）
  - `docs/reviews/change-review/S-settings-state.md`（106 行）

## 8. 建议的下一步

1. 修 P0-1 与 12 条 P1（其中 P1-1/2/3/6/7 是交互链路断点，建议优先）。
2. 用 fixtures 复核 dependents 短名/全名问题；若成立升 P0。
3. 更新三份 fix-matrix：修正 P0-05/P0-09/E-15/E-17/P0-10 的完成度，删除「维护页漏洞历史入口」等未落地声称；行号改为符号名。
4. P2 排入下一迭代，优先「状态真相单一出口」（§4.1）与「弹层仲裁」（§4.2）。
