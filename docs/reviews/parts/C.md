# 簇 C：更新与任务队列/日志

评审范围：F4.1–F4.8（检查/单包/批量/全部更新、失败诊断、取消、暂停、漏洞优先、dry-run、自动检查）+ F6.1–F6.6（串行、排队可见、实时日志、进度、取消分级、失败解释、历史）+ 批次汇总与重试。只读评审，未修改 `Brewbutler/` 下任何源码。

## 0. 结论（3–5 条）

1. **底层机制比表面交互扎实**：串行单进程、同包同操作去重、只按实际完成数推进的进度、取消后的「可能部分完成请复查」文案、崩溃后把未完成任务标为 `interrupted` 的对账，都能在代码里找到证据；问题集中在「结果如何被表达、以及用户能否行动」。
2. **两个 P0 都在批量入口**：`全部更新` 没有确认面板（PRD §8 流程 3 步骤 2 明确要求「确认面板列出包与数量」）；批次汇总按**任务数**而非包数统计，导致 30 个包的全量更新在结果弹窗里显示「成功 1」。
3. **队列只有计数、没有实体**：排队项既不可见也不可单独取消（F6.1 硬要求「排队项可取消」），而且取消当前任务后下一个包会立刻开跑，F4.4 的「取消后可选暂停队列」在交互上不成立。
4. **失败诊断断在半路**：失败行只留一行截断错误，退出码/中文建议/复制命令/重试只存在于日志抽屉和一次性的结果弹窗里；弹窗一关，失败项就没有可操作入口。
5. **修复顺序建议**：确认面板 → 汇总按包计数 → 队列列表 + 取消/暂停联动 → 失败行闭环 → 历史可回看。

## 1. 功能覆盖核对表

| ID | 状态 | 证据 | 一句话交互问题 |
| --- | --- | --- | --- |
| F4.1 检查更新 | 部分实现 | `Brewbutler/UI/UpdatesView.swift:90-96`（刷新仅置灰）、`Brewbutler/App/AppState.swift:490-505`（失败回退缓存并标注） | 点击后无「正在检查」反馈，也没有耗时/预计下载信息；离线标注本身是完整的 |
| F4.2 单包更新 | 已实现 | `Brewbutler/UI/UpdatesView.swift:487-495`（锁定禁用 + help 解释）、`Brewbutler/App/AppState.swift:805-813`（同包/同操作去重） | 去重只靠 toast 告知，行内按钮状态不反映「该包已有任务」 |
| F4.3 批量/全部更新 | 部分实现 | `Brewbutler/App/AppState.swift:909-946`、`:996-1026`（串行入队）、`Brewbutler/UI/Sheets.swift:346-351`（汇总计数） | 无确认面板；汇总按任务数统计，「全部更新」显示成功 1；无「复制命令」 |
| F4.4 取消与暂停 | 部分实现 | `Brewbutler/App/TaskQueueStore.swift:240-244`、`:352`（取消后循环继续）、`Brewbutler/UI/LogDrawerView.swift:82-95`（暂停按钮） | 取消当前包后队列立即继续，用户需在秒级内抢点「暂停队列」 |
| F4.5 不自动回滚 | 部分实现 | `Brewbutler/App/TaskQueueStore.swift:490-492`（取消文案明确不回滚）、`Brewbutler/UI/Sheets.swift:315`（危险重试文案） | 失败路径的行内文案没有「不自动回滚」说明，只在抽屉/确认页出现 |
| F4.6 dry-run 预览 | 部分实现 | `Brewbutler/UI/UpdatesView.swift:221-226`（右键）、`Brewbutler/UI/PackageDetailView.swift:134-139`（详情页按钮）、`Brewbutler/App/AppState.swift:1029-1049`（入串行队列） | 无「预览可能与真实执行不同」标注；结果埋在日志抽屉，不结构化 |
| F4.7 自动检查 | 缺失 | 全仓库无 `Timer`/周期刷新（仅 `Brewbutler/Core/Process/SpawnedProcess.swift:311` 超时定时器）；`Brewbutler/App/AppState.swift:578-590` 仅由手动刷新触发 | 不会自动发现更新，也没有间隔/开关设置 |
| F4.8 漏洞优先 | 部分实现 | `Brewbutler/UI/UpdatesView.swift:157-161`（一键 `--vulnerable`）、`:236-272`（覆盖率文案） | 「更新安全项」旁无「仅覆盖 outdated 交集」说明，易被理解为全机安全已修 |
| F6.1 串行与排队可见 | 部分实现 | `Brewbutler/App/TaskQueueStore.swift:113`（pending 私有）、`:146`（只暴露 pendingCount）、`:340-356`（串行循环） | 只能看到「队列 N 项」，看不到是谁、不能取消 |
| F6.2 实时日志 | 部分实现 | `Brewbutler/UI/LogDrawerView.swift:212-251`（LazyVStack、阶段/错误着色）、`Brewbutler/App/TaskQueueStore.swift:510-513`（截断并落盘） | 无 PTY 失败回退「无进度信息」提示；截断后「复制日志」丢早期行 |
| F6.3 取消分级 | 部分实现 | 取消链路在 `Brewbutler/Core/Process/SpawnedProcess.swift`（本次未逐行复核，需运行验证）；UI 侧 `Brewbutler/UI/LogDrawerView.swift:77-79`、`Brewbutler/App/TaskQueueStore.swift:485-493` | 单任务取消语义清楚，但取消后队列继续跑，接近「越取消越多在跑」 |
| F6.4 失败解释 | 部分实现 | `Brewbutler/UI/LogDrawerView.swift:265-314`（退出码/message/suggestion 只对最新记录）；`Brewbutler/UI/UpdatesView.swift:405-415`（行内只有一行 message） | 失败详情必须打开抽屉，且只看得到最新一条任务 |
| F6.5 环境注入 | 无法判定 | 未读取 `Brewbutler/Core/Brew/BrewEnvironment.swift`，本次不构成证据 | — |
| F6.6 任务历史 | 部分实现 | `Brewbutler/App/TaskModels.swift:191-216`（20 条持久化）、`:80-105`（日志 20 条/50MB）、`Brewbutler/UI/DashboardView.swift:396-430`（最近 5 条） | 历史只列 5 条且点击只打开抽屉；抽屉永远显示最新记录，旧任务的日志/状态看不到 |

## 2. 发现清单

### [C-01] P0｜批次汇总按「任务数」统计，全部更新 30 个包显示「成功 1」
- 证据：`Brewbutler/App/AppState.swift:909-946` 把整个 `brew upgrade` 作为**一个** `ChangeTask` 入队（`:929-944`）；`Brewbutler/App/TaskQueueStore.swift:705-729` 的 `finishBatchIfComplete` 用 `batch.taskIDs`（即任务）计数；`Brewbutler/UI/Sheets.swift:346-351` 直接渲染 `succeeded/failed/...`。
- 用户场景：36 个可更新包点「全部更新」，跑完后结果弹窗写「成功 1 / 失败 0 / 已跳过 0」。
- 现状：进度面板里 36 行逐个打勾，汇总却只报 1，且「已跳过」只含锁定包；用户会误以为只有一个包更新成功，或以为其余 35 个失败但没报告。
- 期望：PRD §7.9 F4.3 验收要求「结束给出成功/失败清单」、§8 流程 3 要求「N 成功 / M 失败 / K 已跳过（已锁定）」——N/M 是包数。UI 规范 §4.3 的批次总进度同样按包。
- 建议：批次汇总改为按 `progressItems` 的终态计数（succeeded/failed/cancelled/skipped），失败项取 progress 行的 name+recordID；任务数留在内部。或让升级全部改为逐包任务（代价：验证与日志语义变化，需评估）。

### [C-02] P0｜「全部更新 / 更新所选 / 更新安全项」单击即执行，没有确认面板
- 证据：`Brewbutler/UI/UpdatesView.swift:105-108`（`appState.upgradeAll()` 直接调用，仅按空/只读/进行中禁用）、`:157-161`（`upgradeVulnerable()` 直调）、`:304-309`（`bulkUpgrade(entries:)` 直调）；`Brewbutler/UI/Sheets.swift` 中不存在批量更新确认页，`Brewbutler/ContentView.swift:44-69` 也没有对应 sheet。
- 用户场景：想勾两个包，手滑点到工具栏右侧的「全部更新」（⌘⇧U 还在同一区域）；没有任何面板列出「将更新 36 个包、跳过 3 个已锁定」，变更已经开始。
- 现状：唯一反馈是入队后抽屉开始滚动；`bulkUpgrade` 只给一句 toast「已加入 N 个更新任务」。没有包清单、数量、锁定跳过数与取消机会。
- 期望：PRD §8 流程 3 步骤 2「勾选或全选 → 「更新选中」→ 确认面板列出包与数量」；HIG 对长时、批量、不可撤销操作要求先确认。
- 建议：复用 `ConfirmSheetLayout`（`Brewbutler/UI/Sheets.swift:5-41`）新增 `BatchUpdateSheet`：标题+「将更新 N 个包」+ 类型分组列表（formula/cask）+「已锁定 K 个将跳过」+ 默认焦点在取消；「更新安全项」同样加覆盖范围说明。

### [C-03] P1｜取消当前任务后队列立刻继续下一个，没有「取消并暂停」
- 证据：`Brewbutler/App/TaskQueueStore.swift:352` 的 `while !pending.isEmpty && !isPaused` 在 `execute` 返回后立即取下一个；`:240-244` 的 `cancelCurrent()` 只置 `.cancelling`、不碰 `isPaused`；`Brewbutler/UI/LogDrawerView.swift:82-95` 的暂停按钮只在 `pendingCount > 0` 时出现，且与取消是两个独立操作。
- 用户场景：批量更新 10 个包，第 3 个卡在编译，点「取消任务」想停下来检查；取消完成后第 4 个包已经开始下载。
- 现状：取消语义是「跳过这个包继续」，不是「停」。用户必须在取消瞬间再点一次「暂停队列」，存在竞态；若在更新页（抽屉 122pt 紧凑模式）更容易错过。
- 期望：PRD F4.4「取消后可选「暂停队列」而非继续下一个」；§8 异常支线「其余保持排队，可选「暂停队列」」。
- 建议：`cancelCurrent()` 增加参数或新 API `cancelCurrentAndPause()`；取消按钮做成分段/菜单：「取消当前任务」+「取消并暂停队列」；批量任务中暂停按钮常驻并在取消后自动高亮。

### [C-04] P1｜排队项不可见、不可单独取消
- 证据：`Brewbutler/App/TaskQueueStore.swift:113`（`pending` 为 `@ObservationIgnored private`）、`:146`（对外只有 `pendingCount`）；无 `cancelPending(id)`/`pendingTasks` 访问器（`:240-278` 仅有 current/pause/clearFinished/hasActivePackage）；`Brewbutler/UI/LogDrawerView.swift:82-85` 只渲染「队列 N 项」文本。
- 用户场景：批量更新 20 个包后发现其中一个不该升级，想把排在第 7 位的它取消；只能看着它执行。
- 现状：队列对用户是一个不透明数字；无法查看顺序、无法取消、无法调整顺序。
- 期望：F6.1「队列可见、排队项可取消」；UI 规范 §4.3 单一列表内联「排队中」状态与 UI 规范 §4.12 行状态「排队中」。
- 建议：把 `pending` 暴露为只读 `[QueuedTask]`（id/title/packageName），在进度面板或抽屉里列出「排队中」行并提供取消（`removePending(id)`，需撤销 `records` 中对应 `.pending` 记录）；更新页行内已有「排队中」行，可把取消放进行内 hover 操作。

### [C-05] P1｜更新失败行缺少退出码/诊断建议/命令/重试，结果弹窗关闭后无入口
- 证据：`Brewbutler/UI/UpdatesView.swift:405-415` 失败行只渲染 `progress.errorMessage`（`lineLimit(1)` + 中间截断），无退出码、无 suggestion、无重试按钮；`Brewbutler/UI/LogDrawerView.swift:265-314` 的退出码/message/suggestion 只针对 `latestRecord`；重试只在 `Brewbutler/UI/Sheets.swift:361-388`（BatchSummarySheet 失败项）出现一次。
- 用户场景：批量更新结束，看到某行「失败」和半句错误；点「关闭」后发现弹窗里没有该包的重试，抽屉也只显示最后一个任务，失败包的命令与建议都找不到。
- 现状：`TaskRecord` 已存 `exitCode/message/suggestion`（`Brewbutler/App/TaskModels.swift:115-168`），但更新页没有消费；UI 规范 §4.3 明确要求失败态「行内错误首行 + 退出码 + 诊断建议」。
- 期望：同上，以及 F6.4「退出码 + 关键行 + 中文解释」，未知错误保留原文 + 一键复制。
- 建议：失败行展开为两行（首行 message、次行 `退出码 N · suggestion`）+ hover 操作「重试 / 复制命令」；行点击打开该包详情或抽屉并定位到该 record。

### [C-06] P1｜退出/关窗时不提示仍在运行的变更任务
- 证据：`Brewbutler/MyApp.swift:17-43` 只有 `WindowGroup` 与 `MenuBarExtra`，`Brewbutler/ContentView.swift:44-69` 无终止钩子；全仓库 grep 不到 `NSApplicationDelegateAdaptor`/`applicationShouldTerminate`/`willClose`/`scenePhase` 用法。
- 用户场景：`brew upgrade` 正在跑，⌘Q 退出应用去开会；回来发现任务被标记「上次未完成」，不知道到底升级到哪一步。
- 现状：退出无确认；重新启动时 `loadHistory` 会把未完成任务标为 `interrupted` 并给出复查建议（`Brewbutler/App/TaskQueueStore.swift:771-779`），这是代码层面的兜底，但不能替代退出前确认。子进程在应用退出后是否被回收需运行验证（`POSIX_SPAWN_SETSID` 创建独立会话）。
- 期望：PRD F6.1 边界「退出时有运行任务需确认」。
- 建议：`NSApplicationDelegateAdaptor` + `applicationShouldTerminate` 返回 `.terminateLater`，弹「有任务在运行：等待完成 / 取消任务并退出 / 保持运行」，默认不退出。

### [C-07] P1｜任务历史不可回看，重启后历史任务无法重试
- 证据：`Brewbutler/UI/DashboardView.swift:396-430`「最近操作」只取 `records.prefix(5)`，每行 Button 的唯一动作是 `showDrawer = true`（`:404-405`）；`Brewbutler/UI/LogDrawerView.swift:13` 抽屉内容固定为 `latestRecord`（`Brewbutler/App/TaskQueueStore.swift:140-144`）；重启后 `taskByID` 为空，`retry(recordID:)` 返回 `.unavailable`（`Brewbutler/App/TaskQueueStore.swift:296-297`），toast 让用户自己去终端。
- 用户场景：昨天的失败任务，想看看当时 brew 到底报了什么；点「最近操作」里那一条，抽屉显示的是今天的最新任务。
- 现状：历史记录与日志文件都在（`Brewbutler/App/TaskModels.swift:191-216`、`:40-105`），但没有选择记录、读取对应日志的入口；「查看原始日志」只切当前记录的内存日志。
- 期望：F6.6 任务历史（P1）要求可查看，PRD 流程 3 步骤 4「可展开诊断」。
- 建议：抽屉增加记录切换（或「历史」列表页，20 条），选中后 `logText(for:)` 读文件展示只读日志；历史任务提供「复制命令」而非直接重试。

### [C-08] P2｜「检查更新」没有进行中反馈，也没有耗时/预计下载信息
- 证据：`Brewbutler/UI/UpdatesView.swift:90-96` 刷新按钮仅 `.disabled(appState.isRefreshing)`，文字与图标不变；抽屉的 `LoadingBar` 只在任务运行时出现（`Brewbutler/UI/LogDrawerView.swift:18-20`）；`Brewbutler/MyApp.swift:63-66` 的 ⌘R 菜单项未置灰（`refreshIndex` 内部会合并请求，`Brewbutler/App/AppState.swift:462-470`）。
- 用户场景：网络慢时点刷新，按钮变灰但页面毫无变化，用户重复点击或以为卡死。
- 期望：UI 规范 §4.3 mock header 含「预计下载 1.8 GB」；进行中状态应有不定态条/文案（如「正在检查更新…」）。
- 建议：刷新按钮在 `isRefreshing` 时显示 spinner + 文案「检查中…」，header 旁加 2pt `LoadingBar`；⌘R 同步 disabled。

### [C-09] P2｜更新页缺少「全选」，与安装页不一致
- 证据：`Brewbutler/UI/UpdatesView.swift:149-167`（筛选 chips + 搜索，无全选）、`:298-320`（底部只有「已选 N 项 / 更新所选」）；对照 `Brewbutler/UI/InstalledView.swift:253-254` 有 ⌘A 全选、`:274` `selectAllVisible()`。
- 用户场景：想更新 12 个包中的 10 个，只能逐行点复选框。
- 期望：PRD §8 流程 3「勾选或全选」。
- 建议：复用安装页模式加「全选可见项」按钮 + ⌘A；与「全部更新」区分开（后者是 `brew upgrade` 全量，含未展示项）。

### [C-10] P2｜「已选 N 项」与实际入队的包可能不一致（筛掉即静默丢弃）
- 证据：`Brewbutler/UI/UpdatesView.swift:300` 显示 `selection.count`；`:306-308` 入队集合只从当前 `rows` 里过滤，切到「安全」或搜索后不可见的已选项不会入队，但计数仍显示。
- 用户场景：在「全部」勾 3 个，切到 cask 筛选又勾 1 个，底部显示「已选 4 项」，实际只更新可见的那 1 个；toast 显示「已加入 1 个」时才察觉。
- 期望：计数与执行集合一致；或明确提示「N 项被筛选隐藏」。
- 建议：入队时用 `selection` 全集（配合 C-09 的可见性），或在 queueBar 标注「其中 N 项当前不可见」并二次确认。

### [C-11] P2｜dry-run 预览埋得深、无差异提示、且占用串行变更队列
- 证据：`Brewbutler/UI/UpdatesView.swift:221-226` 仅在右键菜单提供「预览更新（dry-run）」，行内没有按钮；`Brewbutler/UI/PackageDetailView.swift:134-139` 有按钮但无说明文案；`Brewbutler/App/AppState.swift:1029-1049` 把 `.upgradeDryRun` 作为普通变更任务入队（阻塞真实更新，抽屉里显示为可取消任务）；输出是原始 brew 文本，未解析成「将升级 X→Y」列表。
- 用户场景：想知道全部更新会下载多少、动哪些包，右键试了一下，结果在抽屉里滚过一串 brew 输出，找不到可读的清单。
- 期望：F4.6 要求「预览与真实执行可能不一致 → 标注」。
- 建议：结果面板解析「Would upgrade ...」为结构化列表 + 至少一行免责说明；dry-run 不入变更队列（或明确排队提示），入口从右键提升到 header「预览全部」。

### [C-12] P2｜F4.7 自动检查更新完全缺失
- 证据：全仓库无 `Timer`/`scheduledTimer`（`grep -rn "Timer" Brewbutler/` 只命中 `Brewbutler/Core/Process/SpawnedProcess.swift:311` 的超时定时器）；`Brewbutler/App/SettingsStore.swift` 无自动检查间隔键；`Brewbutler/App/AppState.swift:578-590` `notifyIfNewUpdates` 仅由手动 `refreshIndex` 在 `:540` 调用。
- 用户场景：期望「每天自动检查、有新版本时通知」，实际只有打开应用并手动刷新后才知道。
- 期望：F4.7 P1「默认 24h 可关闭；离线静默失败」。
- 建议：`bootstrap` 后按 24h 间隔（可配）+ 应用激活时判断 TTL；失败不弹窗不进状态栏。

### [C-13] P2｜「复制日志」复制的是被截断的内存日志，完整日志文件没有入口
- 证据：`Brewbutler/App/TaskQueueStore.swift:510-513` 超过 4000 行后 `removeFirst(500)` 并置 `logsTruncated`；`Brewbutler/UI/LogDrawerView.swift:316-317` 复制优先用内存 `logs`，仅当为空才 `logText(for: record)`；抽屉横幅称「完整日志见日志文件」（`:216-219`）但没有打开/定位该文件的按钮。
- 用户场景：失败任务输出上万行，复制日志发给同事，漏掉最早的关键错误行；也无法在 Finder 里找到完整日志。
- 期望：F6.2「巨量输出虚拟化 + 落盘」，F6.4 一键复制应复制完整内容。
- 建议：`logsTruncated` 时复制改读 `logText(for:)`（或提供「复制完整日志」二级操作）；横幅加「在 Finder 中显示」。

### [C-14] P2｜取消/失败后的批次结果不提示「可能部分完成需复查」，未执行行被标「已取消」
- 证据：`Brewbutler/App/TaskQueueStore.swift:485-493` 单任务取消有「若操作可能已部分完成，请复查」文案；但 `Brewbutler/UI/Sheets.swift:325-398` 的批次汇总只有计数与失败项列表，`cancelled>0` 时无任何复查提示；`:601-620` 取消时把 running 与 pending 行统一标 `.cancelled`，与「未执行」语义混同。
- 用户场景：中途取消批量更新，结果弹窗显示「已取消 8」，用户不知道该不该复查这 8 个包（其中 7 个根本没跑）。
- 期望：F6.3「可能已部分完成 → 提示复查」；UI 规范行状态区分「已取消 / 未执行」。
- 建议：汇总增加 warning notice「K 个包已取消，其中可能有包处于中间状态，请复查」；pending 行保留 `.skipped`（未执行）并在文案上区分。

### [C-15] P2｜进度面板缺「已用时间」，失败不计入完成数，静默期无提示
- 证据：`Brewbutler/UI/LogDrawerView.swift:157-208` 只渲染 `done/total` + 5pt 条，`done = progressDoneCount` 仅统计 `.succeeded`（`Brewbutler/App/TaskQueueStore.swift:152`）；耗時只在 `isRunning` 时显示于 header（`:71-76`，1s TimelineView）；静默期只有 2pt 不定态 `LoadingBar`（`:18-20`）。
- 用户场景：brew 在下载大 bottle 时 90 秒无输出，进度条与「3/10 已完成」不动，用户判断为卡死并取消（反而更慢）；批量结束后也无法知道总共花了多久。
- 期望：UI 规范 §5 `TaskProgressBar` 要求「3/5 · 已用 01:24」；§4.12 ProgressPanel 只按实际完成数推进（已满足）。
- 建议：面板标题加已用时间；`finished && failed>0` 时显示「N 完成 + M 失败」而不是只停在 done/total；静默 ≥10s 在 header 显示「暂无输出，可能正在下载」。

### [C-16] P2｜无障碍与键盘细节
- 证据：`Brewbutler/UI/LogDrawerView.swift:201-202` 进度条只有 `accessibilityLabel`，无 `accessibilityValue`（UI 规范 §7 要求百分比）；`:105-113` 跟随尾部开关仅靠图标与 `.help` 表达状态；`:427-431` `cancelled` 与 `skipped` 圆点同为空心灰；⌘. 在 `Brewbutler/UI/UpdatesView.swift:331`（页面隐藏按钮，块起于 `:322`）与 `Brewbutler/UI/LogDrawerView.swift:79`（取消按钮）重复注册。
- 用户场景：VoiceOver 用户听到「总进度：3 / 10 已完成」但没有 percent 值；视觉用户也难以区分「取消」与「未执行」行。
- 期望：HIG/UI 规范 §7「进度条 accessibilityValue 百分比」「全部功能键盘可达」。
- 建议：补 `accessibilityValue`；跟随开关加 `accessibilityLabel`（跟随中/已暂停）；cancelled 用斜线图标区分；⌘. 只保留一处注册。

### [C-17] P2｜进度面板复位竞态：新批次会混入旧面板
- 证据：`Brewbutler/App/TaskQueueStore.swift:181-185` 仅当 `progressFinished` 为 true 才重置 `progressItems`；`:186-193` 随后无条件覆盖 `progressTitle/progressSkippedCount`；`Brewbutler/App/AppState.swift:1014-1023` 批次的 `beginBatch` 先于逐包 `enqueue`。
- 用户场景：单包更新还在跑，随后点「更新所选」2 个包；面板标题变成「批量更新 2 个包」，但里面还挂着上一个包的行，`3/3` 的完成语义也混了。
- 期望：不同批次/单任务的行应可区分，或队列上只展示当前批。
- 建议：`enqueue` 时若 `progressItems` 含其它 batch/record 的行，给新行加分组标题或先归档旧行；或明确「一个面板只装一个批次」。

### [C-18] P2｜「更新安全项」缺少覆盖范围说明，易被读成「全机安全已修」
- 证据：`Brewbutler/UI/UpdatesView.swift:157-161` 按钮只有 `.help("brew upgrade --vulnerable")`；页面只有 `:236-272` 的扫描覆盖率文案，未说明「--vulnerable 只升级 outdated 交集，未在可更新列表中的漏洞包不会被处理」；执行前无确认。
- 用户场景：看到「5 个安全更新」点「更新安全项」，跑完后以为剩余漏洞已解决。
- 期望：F4.8「仅覆盖 outdated 交集」，F11.3 要求覆盖范围必须可解释，避免误判。
- 建议：按钮旁加说明/确认面板写清「只处理可更新的 N 个包；其余漏洞包需单独处理」，并与覆盖率徽标联动。

## 3. 做得好的地方（3–5 条）

1. **进度是真实计数**：`Brewbutler/UI/LogDrawerView.swift:157-208` 用 `progressDoneCount`（仅 succeeded）算比例，并明写「每完成一个包前进一步，只计实际完成数」；没有包内假百分比，符合 PRD F6.2 与 UI 规范 §5 的硬约束。
2. **取消不会留下失控 UI 状态**：`Brewbutler/App/TaskQueueStore.swift:668-671`「late cancel wins over succeeded」避免取消瞬间任务显示成功；`:485-493` 明确写「Brewbutler 不会自动回滚。可在终端重新执行同一命令」。
3. **三重校验存在**：每个任务结束按退出码 + `outdated` 复核 + 版本比对判定（`Brewbutler/App/TaskQueueStore.swift:408-459`、`:529-566`），并区分 `失败 / 未确认（unverified）`，比「退出码 0 就算成功」诚实。
4. **锁定包与跳过数有交代**：`Brewbutler/App/AppState.swift:918-928`、`:1001-1017` 先把 pinned 计为 skipped 并写入批次，进度行排除锁定包，避免看板永远推不动。
5. **崩溃/强退对账与容量上限**：`Brewbutler/App/TaskQueueStore.swift:771-779` 把上次非终态记录标为 `interrupted / 上次未完成` 并给复查建议；`Brewbutler/App/TaskModels.swift:191-216`、`:80-105` 实现 20 条/50MB 滚动裁剪，符合 F6.6。

## 4. 需运行验证清单

1. 取消时间线：AGENTS §8 写 SIGINT→3s→SIGTERM→累计 7s→SIGKILL，PRD F6.3 写 3s/10s；需实测「点取消到进程退出」的秒数与最终状态是否 `cancelled`。
2. 应用退出/关窗时运行中的 brew 子进程是否被回收：`POSIX_SPAWN_SETSID` 独立会话下可能成为孤儿进程，需实测（只读观察，不执行变更命令）。
3. 取消批量任务后，下一个包是否真的立刻开始（静态代码结论为「是」，需实测确认无额外等待/暂停逻辑）。
4. 刷新 36 个包时 `brew outdated` 的实际耗时与「按钮无反馈」的观感（是否被误认为卡死）。
5. 全部更新后批次汇总的真实显示值（按代码推算为「成功 1」，需 UI 实测确认无其它换算）。
6. 全部包都被 pinned 时点「全部更新」：是否出现「成功 1」而实际什么都没升级（`Brewbutler/UI/UpdatesView.swift:107` 只在 outdated 为空时禁用）。
7. 巨量输出（>4000 行）下复制日志是否丢行、虚拟化滚动是否卡顿。
8. VoiceOver 朗读进度面板与批次汇总的焦点顺序（`accessibilityValue` 缺失的实际影响）。

## 5. 评审方法与限制

- 方法：以 P1 用户脚本走查（3 分钟完成一次安全更新 / 批量中途失败只重试失败项 / 误点全部更新后取消 / 关窗后回来查队列），逐条对照 PRD §7.2/§7.4/§7.9/§8 与 UI 规范 §4.3/§4.12/§5/§7，再回代码找证据。
- 只读：未修改 `Brewbutler/` 下源码，未运行 brew 变更命令与 xcodebuild；结论均来自静态阅读，标注「需运行验证」的条目未实测。
- 限制：F6.3 的取消实现主要在 `Brewbutler/Core/Process/SpawnedProcess.swift`，本次未逐行复核（超出簇 C 重点），因此对进程收敛只做「待验证」结论；F6.5 环境注入未读，标为无法判定。
- 文档时效：`docs/product-plan.md` 的 F6.3 时间线与 AGENTS §8 的代码口径不一致，以代码为准；UI 规范中的「预计下载 1.8 GB」「TaskProgressBar」为文档承诺，代码未实现，已按差异计入发现。
