# S-shell · 外壳与全局交互 — 修复复核（2026-11-06）

评审人：reviewer-s（外壳/全局交互组）
评审对象：2026-11-05 UX 评审后 M1/M2/M3 的修复（无 git diff 基线：HEAD 仅模板提交，新代码全 untracked；改动清单以三份 fix-matrix 与文件 mtime 为准）
评审方法：纯静态走查真实代码路径（用户点哪里 → 哪个 action → 状态怎么变 → 最终看到什么），只读，未运行 App、未执行任何变更类 brew 命令。
范围文件：`Brewbutler/MyApp.swift`、`Brewbutler/ContentView.swift`、`Brewbutler/UI/MenuBarView.swift`、`Brewbutler/UI/SidebarView.swift`、`Brewbutler/UI/CommandPaletteView.swift`、`Brewbutler/Design/AppTheme.swift`、`Brewbutler/Design/Components.swift`、`Brewbutler/App/QuitGuard.swift`

---

## 0. 概览

| 项 | 值 |
| --- | --- |
| 本组相关修复 | 17 条（E-04…E-19 = 16 条 + P0-10 = 1 条） |
| ✅ 成立 | 9 条：E-04、E-05、E-06、E-07、E-08、E-09、E-12、E-13、E-19 |
| ⚠️ 部分成立/待实机 | 8 条：E-10、E-11、E-14、E-15、E-16、E-17、E-18、P0-10 |
| ❌ 不成立或引入新问题 | 0 条 |
| 新发现问题 | 12 条（P1 2 条 / P2 10 条，无 P0） |

一句话结论：**主路径基本兑现（快捷键、菜单栏、外观、⌘K 这批做得干净），但「写了代码却没接到用户面」的修复有三处**——E-15 的 `focusRing` 全仓 0 调用、E-17 的收敛在关闭时把未呈现的弹层一起清空、E-14 的「查看」打开的是错任务的日志；P0-10 覆盖了三条退出路径中的两条，且只认「运行中」不认「排队中」。

同时说明：`docs/reviews/fix-matrix-m1.md` 写的「有运行/排队任务时」与代码不符——`QuitGuard` 只判 `isRunning`（`Brewbutler/App/QuitGuard.swift:21`，`isRunning` 定义为 `currentRecordID != nil`，`Brewbutler/App/TaskQueueStore.swift:202`），排队与暂停态不在守卫内。这是本组矩阵与实现的唯一直接矛盾。

---

## 1. 逐条判定表

| ID | 修复声称 | 用户实际路径 | 判定 | 证据 |
| --- | --- | --- | --- | --- |
| E-04 | 菜单栏 label 显示更新数 + a11y | 有更新时菜单栏 mug 旁显示数字；VO 读「Brewbutler，N 个可更新」 | ✅ | `MyApp.swift:48-58`；计数与应用内同源（`AppState.swift:739`、`DashboardView.swift:159`） |
| E-05 | 命令面板空查询给最近任务 | ⌘K 直接回车 → 打开最近一条任务日志；运行中项有 hourglass 图标 | ✅ | `CommandPaletteView.swift:206-221` |
| E-06 | ⌘⇧K / ⌘⇧D 提升为全局 | 任意页面按 ⌘⇧K 出清理预览、⌘⇧D 跑 doctor；维护页无重复注册 | ✅ | `MyApp.swift:99-114`（含 `isScanning`/`doctorLoading`/`isReadOnly` 禁用态） |
| E-07 | 面板结果截断给出路 | 搜到 >10 个包时列表末尾出现「共 N 个结果 · 在发现页查看全部」，回车跳到发现页并带入查询 | ✅ | `CommandPaletteView.swift:258-272`、`240` |
| E-08 | 快捷键去重 | ⌘A/⌘⌫ 只在包表格聚焦时有效，搜索框里 ⌘A 仍是全选文本 | ✅ | `InstalledView.swift:584-596`（`.disabled(!tableFocused)`） |
| E-09 | 菜单标题不手写 ⌘N | 导航菜单显示「仪表盘 ⌘1」只出现一次 | ✅ | `MyApp.swift:70-74` |
| E-10 | ⌘, 打开设置页 | 主窗口存在时：切到设置页并激活窗口 ✅；**主窗口已关闭时：按 ⌘, 什么都不发生**，也不开窗 | ⚠️ | `MyApp.swift:85-92`（`NSApp.windows.first(where: { $0.canBecomeMain })` 找不到窗口即无操作）；对照 `MenuBarView.swift:41-44` 用 `openWindow(id:"main")` 才是可靠做法 |
| E-11 | 详情态侧边栏高亮所属分区 +「详情」徽章 | 从列表进详情：父分区高亮 +「详情」徽章 ✅；从 ⌘K 打开包详情：沿用原分区（在设置页时变成「设置 + 详情」）；VO 只读「仪表盘」读不到「详情」 | ⚠️ | `SidebarView.swift:13-14`、`122-129`、`161`；`CommandPaletteView.swift:252` → `AppState.swift:509-514`（`selectPackage` 不改 `section`） |
| E-12 | 状态卡可点进设置 + help/a11y | 点 Homebrew 状态卡 → 设置页；未安装时红点 +「未检测到 Homebrew」+「点击指定路径」 | ✅ | `SidebarView.swift:44-97`（Button→`openSection(.settings)`、`:95-96` help/a11y）；未安装时设置页可进（`ContentView.swift:138-141` 只拦非设置分区） |
| E-13 | 外观三选一菜单 | 工具栏眼镜图标 → 菜单三选项带勾，选中即生效 | ✅ | `ContentView.swift:169-184`；`SettingsStore.swift:4-26` |
| E-14 | toast FIFO（错误 5s/其他 2.8s）+ 队列徽章 + 失败「查看」 | 失败提示 5s 后消失，右上显 `+N`，有「查看」；但「查看」只开抽屉不定位记录，抽屉里可能是别的任务；无手动关闭 | ⚠️ | `AppState.swift:2170-2206`、`Components.swift:505-533`、`ContentView.swift:34-37` |
| E-15 | 动态字体 + 焦点环 + 减少动效 | 字体默认尺寸改文本样式 ✅；`focusRing()` 全仓 0 调用，自定义行/面板无焦点环；ContentView 声明了 `reduceMotion` 却未使用，抽屉/面板过渡仍无条件动画 | ⚠️ | `AppTheme.swift:60-83`、`149-157`（0 调用）；`ContentView.swift:5`、`:42`、`:50` |
| E-16 | 菜单栏 popover 跟随外观 | 代码已给 MenuBarExtra 内容加 `preferredColorScheme`；实际是否影响 popover 面板外观需实机 | ⚠️（待实机） | `MyApp.swift:44`；`AppTheme.swift:101-116` 用动态 NSColor，原理上可跟随 |
| E-17 | 9 个 sheet 收敛为单一 ShellSheet | 9 个来源合一 ✅；但 `set(nil)` 一次清空全部 9 个来源 → 未呈现的来源被静默丢弃；页面级 5 个 `.sheet` 未收敛，仍可与 ShellSheet 争同一窗口 | ⚠️ | `ContentView.swift:54-108`（`:96` `guard newValue == nil`，`:97-106` 清 9 个）；`UpdatesView.swift:145`、`InstalledView.swift:185,188`、`PackageDetailView.swift:68,749`、`SettingsView.swift:696` |
| E-18 | 面板方向键可用 | 输入框与容器各注册了一次 ↑↓/回车（重复注册）；实际是移动一次还是跳两格、回车是否只触发一次，静态无法判定 | ⚠️（待实机） | `CommandPaletteView.swift:65-67` 与 `89-91`、`:68` `onExitCommand` |
| E-19 | ⌘K 是开关 | 面板开着再按 ⌘K 关闭 ✅；但面板不是真模态：工具栏按钮仍可点、⌘R 等全局快捷键仍会穿透 | ✅ | `MyApp.swift:76-81`；`ContentView.swift:44-50`（overlay 只覆盖内容区） |
| P0-10 | 退出守卫：运行/排队中退出要确认，默认安全按钮，超时取消退出 | ⌘Q 与菜单栏「退出」都会弹「有任务正在运行」，默认按钮是「继续运行」（回车安全）✅；**排队/暂停态退出不弹确认**；关窗无「仍在后台」提示；点「停止任务并退出」后最长 10s 无任何进度反馈，且确认框不说是哪个任务 | ⚠️ | `QuitGuard.swift:20-22`（只判 `isRunning`）、`:24-32`、`:40-52`、`:54-59`；`TaskQueueStore.swift:177`（`pendingCount` 未判）；全仓无 `windowShouldClose` |

判定统计：✅ 9 / ⚠️ 8 / ❌ 0。其中 E-16、E-18 属于「代码看似到位但静态无法证实」，不计入成立。

---

## 2. 新发现问题

### S-01 历史记录选中态不会因新任务清除 → toast「查看」与抽屉自动打开都显示错任务的日志
- **严重度**：P1
- **用户操作序列**：在日志抽屉里点开一条历史任务（`selectedRecordID` 被设）→ 关闭抽屉 → 发起一个新更新 → 任务失败 → 点失败 toast 的「查看」。
- **实际行为**：`displayedRecord` 优先返回 `selectedRecordID`（`TaskQueueStore.swift:184-195`），而 `selectedRecordID` 只在 `followLatestRecord()` 里清（`TaskQueueStore.swift:1055-1057`，调用点仅 `:383`、`:1043`）；新任务开始时只 `showDrawer = true`（`TaskQueueStore.swift:547`）没有回归实时态。结果是：失败 toast 的「查看」把人带到**旧任务**的日志；任务启动时自动弹出的抽屉也停留在旧记录，看不到新任务的实时输出。E-14 里为「定位该记录」写的 `openLogDrawerFromToast()`（`AppState.swift:2185-2187`）全仓无人调用，ContentView 直接传了 `{ tasks.showDrawer = true }`（`ContentView.swift:36`），所以「查看」只开抽屉、不选记录。
- **建议修法**：把 record id 带进 `ToastMessage`，`onOpenDetails` 改调 `tasks.openHistoryRecord(record.id)`；同时在新任务启动时（`TaskQueueStore.swift:547` 旁）调用 `followLatestRecord()`，避免抽屉停留在历史模式。
- **能否静态确认**：能（`selectedRecordID` 的读写点已穷举）。

### S-02 单一 ShellSheet 关闭时清空全部来源 → 未呈现的批次汇总被静默丢弃
- **严重度**：P1
- **用户操作序列**：发起批量更新 → 更新进行中打开「清理缓存」弹层（`cleanupRequest` 非空，优先级高于 batchSummary）→ 批次结束（`batchSummary` 被赋值，但不会呈现）→ 关掉清理弹层。
- **实际行为**：`set(nil)` 把 9 个来源一次性置空（`ContentView.swift:96-106`），`batchSummary` 从未呈现就被清掉；`BatchSummarySheet` 是批次「N 成功 / M 失败」的唯一集中入口（抽屉里的 `batchSummary` 是逐包进度，`LogDrawerView.swift:211`，不是同一份数据）。同理，用户正在 `BatchUpdateSheet` 里确认第二批时，若前一批结束，`get` 的优先级会让 item 变成 `batchSummary`（`ContentView.swift:86` vs `:89`），正在填的确认面板被换掉/关掉时 `pendingBatchUpdate` 一并清空。
- **建议修法**：`set(nil)` 只清当前呈现的那一个来源（或用 `dismissed` 记录），其余来源保持，让下一个自然顶上；更好的做法是给来源建一个小队列（presented / queued）。
- **能否静态确认**：能（`set` 清空逻辑是确定性的；「输入值非 nil 时 `guard` 直接 return」也排除了正常关闭路径的逐项清理）。

### S-03 主窗口关闭后 ⌘, 与「设置…」菜单项无反应
- **严重度**：P2
- **用户操作序列**：点红点关掉主窗口（App 仍驻留）→ 按 ⌘,（或菜单栏「设置…」）。
- **实际行为**：`openSection(.settings)` 只改状态，随后 `NSApp.windows.first(where: { $0.canBecomeMain })` 为空 → 无窗口被打开，用户看到「按了没反应」，也没有任何提示。菜单栏「打开主窗口」用的是正确写法 `openWindow(id:"main")`（`MenuBarView.swift:41-44`），两处不一致。
- **建议修法**：先 `openWindow(id: "main")` 再 `openSection(.settings)`；或去掉窗口查找，用 SwiftUI 的 `openWindow` + `.activate`。
- **能否静态确认**：能（窗口关闭后无 canBecomeMain 窗口这一前提需实机确认，但代码没有任何补偿分支）。

### S-04 退出守卫不覆盖排队/暂停态，且等待期间无可视反馈
- **严重度**：P2
- **用户操作序列**：取消一个任务（`cancelCurrent` 会把队列置 `isPaused`，`TaskQueueStore.swift:343-345`）→ 队列里还有 3 个待执行 → ⌘Q。
- **实际行为**：`isRunning == false`（`currentRecordID` 已清），`applicationShouldTerminate` 直接 `.terminateNow`，3 个排队任务被静默丢弃，用户没机会知道；矩阵宣称的「运行/排队」未实现。另外「停止任务并退出」后要轮询最长 10s（`QuitGuard.swift:42-48`），期间界面没有任何「正在结束任务」提示，二次确认框也没有说明被中断的是哪个任务（`:26-27` 只写「有任务正在运行」）。
- **建议修法**：条件改为 `isRunning || pendingCount > 0`；确认框与等待期间显示任务标题/进度；等待时给出可取消的进度提示。
- **能否静态确认**：能。

### S-05 关窗不提示「已转入后台继续运行」
- **严重度**：P2
- **用户操作序列**：任务运行中点主窗口红点。
- **实际行为**：窗口消失、brew 继续跑，用户没有任何提示（全仓无 `windowShouldClose` / `applicationShouldTerminateAfterLastWindowClosed` / 后台提示文案），容易误以为已退出而直接合盖/关机。
- **建议修法**：`NSWindowDelegate.windowShouldClose` 或 SwiftUI `onDisappear` + 一次性提示（「Brewbutler 仍在菜单栏运行，任务继续」）。
- **能否静态确认**：能（缺失可静态确认；具体提示时机需实机）。

### S-06 toast 无法手动关闭，注释承诺的「点击 toast 或按 Esc」没有实现
- **严重度**：P2
- **用户操作序列**：连续触发 3 个动作（如逐个安装 3 个包）→ 想跳过当前提示。
- **实际行为**：`dismissToast()` 的注释写着「点击 toast 或按 Esc」（`AppState.swift:2176-2182`），但 `ToastView`（`Components.swift:505-533`）没有 `onTapGesture`、没有 Esc 处理，全仓也没有调用 `dismissToast()` → 提示只能等 2.8s/5s 自动过，`+N` 队列只能干等。另外失败文案是 `"\(title)失败：\(message)"`（`AppState.swift:1672`，message 可能是一整行错误），`ToastView` 文案没有 `lineLimit`，长错误会把胶囊撑满甚至换行。
- **建议修法**：给 ToastView 加点击/Esc 关闭并调 `dismissToast()`；文案加 `lineLimit(2)` + `truncationMode(.tail)`；失败 toast 增加 `.accessibilityLiveRegion(.assertive)` 之类播报。
- **能否静态确认**：能。

### S-07 E-11 的两个边界：⌘K 打开详情时父分区错位 + VO 读不到「详情」
- **严重度**：P2
- **用户操作序列**：停在「设置」页 → ⌘K 搜包 → 回车。
- **实际行为**：进入包详情，但侧边栏仍是「设置」高亮并挂「详情」徽章，读起来像「设置里有详情」；VoiceOver 只播报「设置，0 项」（`SidebarView.swift:161` 的 `accessibilityLabel` 没有包含详情状态），看不到层级信息。`accessibilityHint` 也只给快捷键（`:162`）。
- **建议修法**：`selectPackage` 时若当前分区不包含该包，切到一个语义合理的分区（或新增「详情」不挂父分区）；a11y label 追加「，已打开包详情」。
- **能否静态确认**：能。

### S-08 E-15 的焦点环是死代码，且两个列表页的焦点视觉不一致
- **严重度**：P2
- **用户操作序列**：Tab 进包列表 / 在发现页结果间移动 / 键盘选行。
- **实际行为**：`AppTheme.focusRing(_:)`（`AppTheme.swift:151-157`）注释写「自定义行/面板项没有系统焦点环，这里统一补 2pt copper 环」，但全仓 0 处调用 → 自定义行、侧边栏项、统计卡在键盘焦点下仍无可见环，纯键盘用户不知道焦点在哪。另：`DiscoverView.swift:231` 用了 `.focusEffectDisabled()`，`InstalledView.swift:417-418` 的 `.focusable()` 没有 → 两个列表一个隐藏系统焦点效果、一个显示，视觉不一致。`ContentView.swift:5` 的 `reduceMotion` 声明后未使用，`:42`/`:50` 的抽屉与面板过渡照常播放。
- **建议修法**：行组件统一走 `focusRing(focused)`；统一 `focusEffectDisabled` 策略；`ContentView` 的两处 animation 按 `reduceMotion` 降级为 `.none`。
- **能否静态确认**：能（0 调用可静态确认；键盘焦点具体落到哪个 view 需实机）。

### S-09 菜单栏「最近任务」不是入口，运行中也没有取消入口
- **严重度**：P2
- **用户操作序列**：菜单栏点开 popover，看到「最近任务：更新 xxx · 运行中」，想查看日志或取消。
- **实际行为**：这一行是纯 `Text`（`MenuBarView.swift:56-67`），不可点；popover 里也没有「停止任务/取消」按钮。用户必须「打开主窗口」→ 找状态栏「任务日志」/抽屉，多两步，且要先知道入口在哪。
- **建议修法**：该行改成 Button（打开主窗口并 `showDrawer = true` + 选中该记录）；运行中加「停止任务」并复用 `cancelCurrent()`。
- **能否静态确认**：能。

### S-10 引导弹层用 Esc 关闭不会记入「已完成」，下次启动又弹
- **严重度**：P2
- **用户操作序列**：首次启动出引导 → 按 Esc（或点关闭）。
- **实际行为**：只有「跳过」和「完成」走 `finish()` → `dismissOnboarding()` 写 `settings.onboardingCompleted = true`（`OnboardingView.swift:21`、`:313`；`AppState.swift:2209-2212`）；Esc 走 `.sheet` 的 `set(nil)`，只把 `showOnboarding = false`（`ContentView.swift:97`），`onboardingCompleted` 仍是 false → 下次启动再弹。全仓无 `interactiveDismissDisabled`（grep 0 命中）。
- **建议修法**：onboarding 加 `.interactiveDismissDisabled()`，或在 `set(nil)` 里对 `.onboarding` 调 `dismissOnboarding()`。
- **能否静态确认**：能（Esc 是否真能关掉 sheet 需实机，但缺少防护是静态事实）。

### S-11 命令面板绕过菜单项的禁用态（同一动作两个入口说法不同）
- **严重度**：P2
- **用户操作序列**：只读模式（Homebrew 版本过低）或扫描/清理进行中，打开 ⌘K 面板点「运行安全扫描 / 运行 brew doctor / 清理缓存与旧版本…」。
- **实际行为**：菜单里这三项有禁用条件（`MyApp.swift:99-114`：`isScanning`、`doctorLoading`、`isReadOnly || cleanupLoading`），命令面板的 `PaletteItem` 完全没有 disabled 概念（`CommandPaletteView.swift:275-300`，只有 `isDangerous` 用于染红）→ 面板里照样可点：扫描会重复请求、只读模式会走到清理预览再失败。用户看到「菜单灰、面板能点」。
- **建议修法**：`PaletteItem` 增加 `isEnabled` + 禁用原因，复用与菜单相同的条件；禁用项置灰并在副标题说明原因。
- **能否静态确认**：能。

### S-12 菜单栏计数含锁定包，与「批量更新会跳过锁定」不一致
- **严重度**：P2
- **用户操作序列**：菜单栏看到「3 个可用更新」→ 进更新页全选 → 批量确认只剩 1 个可更新。
- **实际行为**：`updateCount = appState.index.outdated.count`（`MyApp.swift:48`）包含 pinned；批量更新会过滤 `!$0.pinned`（`AppState.swift:1211`、`:1218`），更新页与确认面板会提示「跳过 N 个锁定」，菜单栏没有任何说明。
- **建议修法**：菜单栏摘要改成「可更新 N（其中 M 个已锁定）」，或直接显示实际可执行数并加 tooltip。
- **能否静态确认**：能。

### 系统性问题（供 Lead 跨组去重）
1. **同一动作多入口，只有部分入口实现禁用态与结果定位**：菜单（MyApp）有禁用、命令面板没有（S-11）；toast 有「查看」但不定位（S-01）；系统通知没有点击处理（全仓无 `UNUserNotificationCenterDelegate.didReceive`，仅有 `AppState.swift:2454-2460` 的发送）；菜单栏「最近任务」不可点（S-09）。凡「结果通知/入口」类修复，建议按「菜单 / 命令面板 / 页面按钮 / 菜单栏 / 通知」五个入口逐项核对，而不是只改主路径。
2. **状态只有一个来源却被多处「清空/覆盖」**：`shellSheet.set(nil)`（S-02）、`selectedRecordID`（S-01）都是「一个布尔/一个 id 驱动多处呈现」，关闭动作会越权清掉别的状态。建议全仓搜 `= nil` 的批量清空点，确认只清自己那一份。

---

## 3. 需实机验证清单

1. **退出守卫三路径**：任务运行中分别用 ⌘Q、菜单栏「退出」、Dock 右键「退出」触发；确认默认回车是「继续运行」；菜单栏 popover 打开时 NSAlert 是否能正常出现在最前。
2. **退出守卫超时**：选「停止任务并退出」后观察 10s 内是否有界面冻结/无响应，超时后的「已取消退出」提示与队列是否恢复（`QuitGuard.swift:50`）。
3. **S-03**：关闭主窗口后按 ⌘, / 用菜单「设置…」；再点菜单栏「打开主窗口」两次，观察是否出现两个主窗口、⌘, 命中哪一个。
4. **S-02 场景**：批次运行中打开清理弹层，批次结束后关弹层，看 `BatchSummarySheet` 是否显示；另测「更新预览」页面级 sheet 与 ShellSheet 同时请求时的表现（`UpdatesView.swift:145`）。
5. **E-18 面板键盘**：输入框内 ↑↓ 是移动 1 格还是 2 格（双注册）、回车是否只执行一次、Esc 是否关闭、输入法组词中回车是否误触发。
6. **E-16 外观**：系统深色下切到「浅色」，打开/关闭菜单栏 popover，看底色与文字是否全套跟随（含 popover 圆角边缘）。
7. **S-06**：连续 3 条失败 toast 的总排队时长；失败信息较长时 toast 是否撑满窗口/换行；按 Esc 或点 toast 是否能关闭。
8. **S-01**：先点开一条历史记录，再跑一个失败任务，点 toast「查看」，确认看到的是哪条记录。
9. **E-19**：命令面板打开时点工具栏「外观」菜单、按 ⌘R/⌘⇧K，确认是否真的穿透、面板是否遮住工具栏。
10. **大字号**：把系统/App 文字调大，检查侧边栏 28pt 行（`SidebarView.swift:139`）、状态栏 26pt（`:218`）是否裁切。
11. **S-12**：锁定 1 个有待更新的包，对比菜单栏数字与批量确认面板的「将更新 N 个」。

---

## 4. 本组结论

**值得保留（9 条，不需要再动）**：E-09（菜单标题）、E-12（状态卡改按钮）、E-13（外观三选一）、E-19（⌘K 开关）、E-04（菜单栏计数与 a11y）、E-05（空查询最近任务）、E-06（⌘⇧K/⌘⇧D 全局化）、E-07（截断出路且可点）、E-08（⌘A/⌘⌫ 聚焦栅栏）。这批都是「一处改动、用户立刻可感知」的修复，且没有发现回退。

**必须回炉（4 条）**：
1. **E-15 的焦点环子项**——`focusRing()` 写了但 0 调用，等于没修；同时把 `ContentView` 的 `reduceMotion` 接上（`:42`、`:50`）。这是本组唯一「代码在、用户面不在」的完整落空。
2. **E-17 的关闭语义**——`set(nil)` 一次清 9 个来源（`ContentView.swift:96-106`），会吞掉批次汇总；顺带补齐 `OnboardingView` 的 `interactiveDismissDisabled`（S-10）。收敛方向对，关闭语义要改成「只关当前」。
3. **E-14 的「查看」定位**——接 `openHistoryRecord(record.id)` 并把 record id 带进 toast，否则失败排查会指向错日志（S-01，本组最严重的用户体验缺陷）。
4. **P0-10 的覆盖范围**——条件补 `pendingCount > 0`，等待期给反馈，确认框写清任务名（S-04）。

**可以留到下个迭代（P2 打磨）**：S-03（⌘, 窗口已关）、S-05（关窗提示）、S-06（toast 不可关）、S-07（详情 VO/父分区）、S-09（菜单栏最近任务不可点）、S-11（面板禁用态）、S-12（锁定包计数）。

**一句话给 Lead**：外壳这组修复「八成成立、两成没接到用户面」，最该回炉的是 toast「查看」定位（E-14/S-01）和 E-17 的关闭清空（S-02），这两条都会让用户看到「错的信息」或「没看到该看的信息」；P0-10 的排队盲区建议由 M1 组一并确认是否属同一处遗漏。
