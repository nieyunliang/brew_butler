# S-updates-queue · 更新/队列/日志/服务/维护 — 修复复核（2026-11-06）

评审人：reviewer-c（只读静态走查：用户点哪里 → action → 状态 → 最终看到什么；未运行 App、未执行 brew）。范围：`Brewbutler/UI/UpdatesView.swift`、`Brewbutler/App/TaskQueueStore.swift`、`Brewbutler/App/TaskModels.swift`、`Brewbutler/UI/LogDrawerView.swift`、`Brewbutler/UI/MaintenanceView.swift`、`Brewbutler/UI/ServicesView.swift`；关联 `AppState.swift`、`Sheets.swift`、`BatchUpdateSheet.swift`、`MyApp.swift`、`ContentView.swift`。相关修复 15 条（C-08…C-18、P0-06、P0-09、D-19、D-22）。

## 1. 一句话结论

C/D 组修复整体可信度高：15 条里 8 条真正端到端兑现（含最难的 P0-06 逐包计数、C-14 取消语义、C-11 只读预览、C-13 全量日志），主链路「检查更新 → 选包 → 确认 → 批次进度 → 汇总 → 日志/重试」已闭环，**无 P0**；但仍有 4 条 P1 属「状态诚实性」问题（批次面板口径、自动检查时间戳、无安全更新时的范围说明、失败行归因），建议发布前修。

判定统计：✅ 已修 8 / ⚠️ 部分 7 / ❌ 未修 0。说明：fix-matrix 的行号已大面积漂移（P0-06 声称 `TaskQueueStore.swift:705-760`，实际 `:922-980`；C-14 声称 `LogDrawerView.swift:690`，该文件仅 680 行），下表证据均取自本人复核后的实际行号。

## 2. 逐条判定

| ID | 判定 | 一句话证据 |
| --- | --- | --- |
| C-08 | ✅ 已修 | 刷新按钮 `ProgressView`+「检查中…」+置灰，页头 `TimelineView` 每秒「已用 m:ss」、≥10s 提示「可能在等待网络或锁」（`Brewbutler/UI/UpdatesView.swift:186-200, 221-238`；outdated 有 90s 超时兜底 `Brewbutler/Core/Brew/BrewClient.swift:151-159`） |
| C-09 | ✅ 已修 | 全选框三态 `checkmark.square.fill/minus.square.fill/square` + `accessibilityValue`，⌘A 只作用于当前筛选（`UpdatesView.swift:84-95, 153-173, 700-701`） |
| C-10 | ⚠️ 部分 | 「已选 N 项 / 将更新 X 个包」成立（`UpdatesView.swift:664-693`），但「跳过 M 个锁定或已进入批次」分支不可达：selection 恒 ⊆ `selectableEntryIDs`（`UpdatesView.swift:80-95, 141-143`），故 `skipped` 恒为 0，真正的跳过数只在确认面板（`BatchUpdateSheet.swift:103-113`） |
| C-11 | ✅ 已修 | 行内「预览」图标（不再只藏右键）+ 560pt 只读弹层、带「不修改本机…结果可能不同」免责、运行中可取消、**不入变更队列**（`UpdatesView.swift:296-353, 943-954`；`AppState.swift:1445-1491` 只走 `client.upgradeDryRun`） |
| C-12 | ⚠️ 部分 | 「上次自动检查 X 前」可见（`UpdatesView.swift:267-281`），但该字段=尝试时间：自动检查**失败也写**（`AppState.swift:2380`）、手动刷新也覆盖（`AppState.swift:698`），离线陈旧时页面无任何失败提示 |
| C-13 | ✅ 已修 | 截断时「复制完整日志」走 `logText(for:)` 落盘全量；抽屉内「打开完整日志」`NSWorkspace.activateFileViewerSelecting`（`Brewbutler/UI/LogDrawerView.swift:507-531, 369-378, 471-479`；`TaskQueueStore.swift:462-472`；`TaskModels.swift:75-84`） |
| C-14 | ✅ 已修 | 取消/移除时只在真正 running 的行写 `.cancelled`，pending 行写 `.skipped`（未执行）（`TaskQueueStore.swift:792-807`）；圆点：已取消=空心+stop.fill，未执行=虚线空心（`LogDrawerView.swift:634-680`）；取消后队列先暂停并提示「剩余 N 个未执行」（`TaskQueueStore.swift:338-348, 866-878`） |
| C-15 | ⚠️ 部分 | 「x/y 已处理 · 完成 a · 失败 b · 已用 m:ss · ≥10s 等待 brew 输出」都成立（`LogDrawerView.swift:211-284`），但 note 只判失败数：`finished && failed == 0` 一律写「全部完成」（`:220-228`），未确认/已取消/未执行批次也被说成全部完成 |
| C-16 | ✅ 已修 | 进度条 `accessibilityLabel/Value`（`LogDrawerView.swift:281-283`）；⌘. 全仓仅 `LogDrawerView.swift:99` 一处注册，`UpdatesView.swift:699` 留注释说明不再重复 |
| C-17 | ⚠️ 部分 | 上一批结束后再起新批次会清旧行/复位计时（`TaskQueueStore.swift:250-276`）；但**有任务正在运行时不清**（`runningRecordIDs.isEmpty` 才 `startsOtherBatch`，`:259-262`），且 `progressTitle` 仅 nil 时赋值（`:278-292`），标题会残留上一批次名 |
| C-18 | ⚠️ 部分 | 有安全更新时说明「只覆盖有可用更新版本的 N 个；其余 M 个…」（`UpdatesView.swift:409-436`），确认面板同提示（`BatchUpdateSheet.swift:36-41`）；但安全更新为空时整段返回 nil（`UpdatesView.swift:427-429`），「0 个安全更新」时受影响包范围再次消失 |
| P0-06 | ✅ 已修 | 单任务聚合批次按 `progressItems` 逐包计数（成功/失败/取消/未确认/跳过），`failedTitles` 取包名，30 包=30 不再「成功 1」（`TaskQueueStore.swift:936-960`；面板 5 列+失败项前 5 +「等 N 个」`Sheets.swift:645-690`） |
| P0-09 | ⚠️ 部分 | 覆盖率/部分覆盖/扫描时间移到页头常显、无报告写「尚未运行 · 覆盖范围未知」（`UpdatesView.swift:244-263`）✅；但矩阵声称的「维护页新增漏洞历史入口」**未实现**（全仓 UI 无相关实现，`MaintenanceView.swift` 无 vuln 引用），且扫描失败时仍写「尚未运行」（不读 `AppState.scanError`） |
| D-19 | ✅ 已修 | 页头健康摘要（回收/doctor/missing/索引时效，`MaintenanceView.swift:60-63, 67-100`）；目录卡给数量+「统计于 X」+「重新统计」（`:487-520`）；missing 项可点进详情（`:363-387`）；doctor/missing 非 0 退出码文案不再说「正常/通过」（`:245-248, 351-354`） |
| D-22 | ⚠️ 部分 | 清理预览给 `removal.detail`（`MaintenanceView.swift:146-152`）、cask 解锁 help 解释 auto_updates（`:471-479`）✅；「↑↓/↵ 选择」子项不在维护页（该文件无 `onMoveCommand/focusable/keyboardShortcut` 命中，原证据属 `DiscoverView.swift`），本次未涉及 |

## 3. 新发现问题

### P1

**C2-01 批次结束面板写「全部完成」，即使有未确认/已取消/未执行**
用户看到什么：取消一个 30 包批次后，抽屉显示「30/30 已处理 · 完成 27 · 失败 0 · 全部完成」，只剩一行「跳过 N 个锁定或进行中」。
代码位置：note 仅 `if finished, failed == 0 { note = "全部完成" }`，取消/跳过行不计入 failed 也不进 note（`LogDrawerView.swift:220-228`；`progressSkippedCount` 只含 `batch.skipped`=`TaskQueueStore.swift:285`）。
影响：用户以为 30 个包都升级了，实际 3 个没执行；与「已取消」「未执行」行的文案直接矛盾。

**C2-02 未确认批次：进度面板与汇总面板两套数字，汇总面板不给任何下一步**
用户看到什么：brew 退出 0 但 `outdated` 复核失败时，进度面板 30/30 全绿「完成」，汇总面板却是「成功 0 / 未确认 30」，没有失败项卡、没有重试、没有建议。
代码位置：`.unverified` 把所有行改成 `.succeeded`（`TaskQueueStore.swift:772-776`），汇总又把成功置 0（`:946-949`）；`TaskBatchSummary.hasFailures` 含 unverified（`TaskModels.swift:198`）但全仓无调用，面板自算 `hasFailedItems` 漏掉 unverified（`Sheets.swift:742-744`），`PackageProgressItem.State` 也没有 unverified 态（`TaskQueueStore.swift:56-96`）。
影响：一次 30 包更新结束后用户不知道到底成功没有，也没有「去检查更新复查」的入口。

**C2-03 自动检查把「失败尝试」与「手动刷新」都写成「上次自动检查」**
用户看到什么：离线放置一天后，页头写「上次自动检查 刚刚」，列表仍是旧数据，无任何横幅。
代码位置：成功写（`AppState.swift:2364`）、**catch 也写**（`:2380`）、手动刷新成功也写（`:698`）；页头只读相对时间（`UpdatesView.swift:267-281`）；`offlineNotice` 只认 `outdatedRefreshError`（`UpdatesView.swift:355-381`），自动检查故意不写它。
影响：用户把陈旧数据当成新鲜结果；「上次自动检查」这个措辞在手动刷新后也不成立。

**C2-04 「0 个安全更新」时受影响包范围消失（P0-09 同源残留）**
用户看到什么：仪表盘扫描出 12 个受影响包、但当前都无可用更新 → 更新页只有「0 个安全更新」+ 覆盖率行，没有任何「还有 12 个受影响包暂无可更新版本」。
代码位置：`securityUpgradeScopeText` 首行 `guard !securityEntries.isEmpty else { return nil }`（`UpdatesView.swift:427-429`），按钮同样条件下隐藏（`:392-397`）；`vulnReport.affectedFormulaCount` 在更新页未被使用（只在 `AppState.swift:795` 与仪表盘）。
影响：正是 P0-09 想消除的「误判安全」，此处只是从「整块消失」改成「按钮和说明一起消失」。

### P2

**C2-05 聚合批次版本复核失败的失败行会指向「错误的包」，且带红色「退出码 0」徽章**
用户看到什么：30 包全部更新，其中 1 个 auto_updates cask 仍可更新 → brew 退出 0 → 列表里某一行变红「失败」「退出码 0」「版本复核未通过：仍有 1 个可更新项」，该行「重试」执行的是这一行包的 `brew upgrade`。
代码位置：`stillOutdated → .failed` 用 brew 退出码（`TaskQueueStore.swift:617-624`），`.failed` 把「当前 running 行」标记失败（`:777-791`），失败行徽章只要 `exitCode != nil` 就渲染 danger「退出码 N」（`UpdatesView.swift:816-818`），聚合行重试退化为单包（`:624-639, 598-608`）。
影响：失败归因可能落到一个已经成功的包；「退出码 0」读起来是成功。需实机确认指向哪个包。

**C2-06 批次运行中追加任务 → 行混进同一面板、分母跳变、标题不回写**
用户看到什么：「全部更新」跑到一半，对另一个包点行内「更新」→ 面板多出一行，`x/y` 的 y 从 30 变 31，标题仍是「更新全部包」。
代码位置：`prepareProgressPanel` 仅在 `runningRecordIDs.isEmpty` 时清面板（`TaskQueueStore.swift:250-276`）；`progressTitle` 仅 nil 时赋值（`:278-292`）；运行中行内「更新」未禁用（`UpdatesView.swift:960-966`）、底栏「更新所选」只禁 `isReadOnly`（`:684`）。
影响：面板总数/汇总数不再对应用户看到的行，C-15/P0-06 的可信度被这条路径破坏。

**C2-07 汇总面板里聚合批次的「重试」= 重跑全部 N 个包，且重试后不再生成汇总**
用户看到什么：失败项列出包名（前 5 条），下方一个「重试」按钮；点击后整个批次重跑，结束后没有汇总面板。
代码位置：`retry` 复制 `ChangeTask` 时丢掉 `batchID`（`TaskQueueStore.swift:441-455`），但保留全量 `progressTargets`；`finishBatchIfComplete` 无 batchID 直接 return（`:922-924`）；按钮按 record 生成（`Sheets.swift:701-716`）。
影响：用户以为是「重试失败的包」，实际重跑 30 个；重跑后没有结果汇总可看。

**C2-08 汇总面板没有「查看日志」，只让你「可在任务日志查看原因」**
用户看到什么：失败摘要只有「重试」「关闭」两个出口，文案却提示去任务日志；关窗后要自己想到 ⌘⌥L。
代码位置：`Sheets.swift:665-735`（无 log/command 入口）。
影响：失败诊断路径断在面板里，C-05 的「查看日志/复制命令」在批次层没有延续。

**C2-09 ⌘. 只存在于抽屉里的按钮，没有全局取消入口**
用户看到什么：抽屉关闭时按 ⌘. 无反应；要取消得先 ⌘⌥L 开抽屉再点「取消任务」。
代码位置：`LogDrawerView.swift:96-100`（按钮条件 `isRunning && !isShowingHistory`）；「操作」菜单无取消项（`MyApp.swift:94-120`）。
影响：取消是变更任务的安全出口，却只有一个「可见才算」的入口。

**C2-10 服务页忙碌态与队列脱节：只有小 spinner，无文字/无位次，队列暂停时永久转圈**
用户看到什么：点「停止服务」确认后，行内按钮变成小菊花且没有说明；若操作排在长批次后面（或用户先取消过任务导致队列暂停），菊花一直转、任务永远不执行，服务页也不说「排队中/已暂停」。
代码位置：`isBusy = records.contains{ packageName 相同 && 非终态 }`（`ServicesView.swift:103-105`），忙碌时整块替换为 `ProgressView()`（`:153-157`）；队列暂停在 `cancelCurrent` 里发生（`TaskQueueStore.swift:338-348`），服务页无 `isPaused/pendingCount` 引用。
影响：双入口状态不同步，用户无法判断服务操作是「在跑」还是「没开始」。

**C2-11 刷新中 ⌘R / 菜单「检查更新」仍可用，点了没有任何反馈**
用户看到什么：页内按钮已变「检查中…」并置灰，菜单项仍可点，点后无变化（`refreshIndex` 内部合并）。
代码位置：`MyApp.swift:95-98` 无 `disabled`/`isRefreshing` 判断；`AppState.swift:622-625` 合并请求。
影响：用户重复触发，怀疑卡死；与页内按钮的禁用态不一致。

**C2-12 「复制完整日志」在主线程同步读最大 50MB 文件**
用户看到什么：点「复制完整日志」或切历史任务时界面卡一下（文件越大越明显）。
代码位置：`TaskLogStore.text(for:)` 用 `String(contentsOf:)`（`TaskModels.swift:75-78`），`copyLogs`/`logText` 直接同步调用（`LogDrawerView.swift:507-531`；`TaskQueueStore.swift:462-465`），保留上限 20 条/50MB（`TaskModels.swift:86-111`）。
影响：主线程 I/O，最坏数百 ms 级卡顿。

**C2-13 扫描失败在更新页仍写「漏洞扫描尚未运行」**
用户看到什么：刚点扫描、失败后回到更新页，页头说「尚未运行 · 覆盖范围未知」，仪表盘才显示失败原因。
代码位置：`UpdatesView.swift:245-263` 只读 `vulnReport`；失败只写 `scanError`（`AppState.swift:846, 850, 853, 857`），唯一渲染处是 `DashboardView.swift:231-232`。
影响：措辞与实际不符（「没跑过」vs「跑了失败」），用户不知道要不要重试。

**C2-14 只读模式下更新页行内「更新」按钮仍可点**
用户看到什么：只读横幅提示版本过低，行内「更新」仍亮着，点后弹 toast 报错。
代码位置：`updateButton` 只 `disabled(entry?.pinned == true)`（`UpdatesView.swift:960-966`），而「全部更新/更新安全项/更新所选」都判了 `isReadOnly`（`:214, 395, 684`）；点击后由 `AppState.enqueue` 兜底 toast（`AppState.swift:1094-1097`）。
影响：可发现性与禁用一致性倒退，用户多点一次才知道不能做。

## 4. 系统性问题

1. **进度面板的状态模型缺「未确认」态，且 note/汇总各自算口径**：`PackageProgressItem` 只有 pending/running/succeeded/failed/cancelled/skipped，未确认被强写成 succeeded（`TaskQueueStore.swift:772-776`），而汇总又单独把成功清零（`:946-949`）；面板 note 只看 failed（`LogDrawerView.swift:220-228`），汇总的 `hasFailedItems` 又不含 unverified（`Sheets.swift:742-744`）。三处各按自己的口径解释同一批次，才会出现「面板全绿、汇总未确认、note 全部完成」三套说法。修法应统一：行级 `unverified` 状态 + 单一 note 判定函数（`finished && (failed+cancelled+skipped+unverified) == 0` 才叫全部完成）。
2. **「诚实披露范围」的补丁只补了有数据的那一支**：C-18 与 P0-09 都在「列表/集合为空」时提前返回（`UpdatesView.swift:427-429`、`:244-263` 无 scanError 分支），而这恰恰是最需要说明的时刻（0 个安全更新≠安全、扫描失败≠未运行）。建议把「范围/新鲜度」做成独立状态行：受影响包数（含 cask）、扫描失败原因、自动检查失败标记三类都常显，不随列表为空而消失。

## 5. 需实机验证（静态无法判定）

1. 聚合批次版本复核失败时，红行落在哪个包、该行「重试」是否重试错包（C2-05）：可用 auto_updates cask 或运行中 `brew pin` 制造 `stillOutdated`。
2. 「全部完成」note 与取消行同屏的实际观感（C2-01）：取消一个 ≥5 包批次后看抽屉首屏。
3. 批次运行中点行内「更新」后 `x/y` 是否真的跳变（C2-06），以及汇总数与面板行数是否可对上。
4. 服务操作排在长批次之后、以及队列暂停后的服务页表现（C2-10）：菊花是否永久转圈、是否有位次。
5. 「复制完整日志」在接近 50MB 日志下的卡顿时长（C2-12）。
6. 自动检查失败场景（拔网 + 清 `brewbutler.lastAutoCheckAt` 后等定时器）页头文案（C2-03）。
7. 焦点类：⌘A 在搜索框聚焦时是否吞掉文本全选（`UpdatesView.swift:700-701` 未判焦点）；⌘. 在抽屉关闭/弹层打开时是否被吞；预览弹层与批次汇总弹层同时触发时是否抢占（`ContentView.swift:54-105`）。
