# E 部分：全局外壳（导航 / 命令面板 / 菜单栏 / 状态栏 / 快捷键 / 跨页一致性）

> 评审范围：`Brewbutler/ContentView.swift`、`MyApp.swift`、`UI/SidebarView.swift`、`UI/CommandPaletteView.swift`、`UI/MenuBarView.swift`、`Design/AppTheme.swift`、`Design/Components.swift` 中的共享组件，以及跨页快捷键与状态提示。
> 视角：用户交互（能不能看懂、能不能恢复、会不会误操作）。方法：静态阅读源码 + 对照 PRD/UI 规范 + 只读命令，未启动真实 App（除标注「需运行验证」外均为代码级判断）。

## 一、结论

外壳整体完成度不低：三栏结构、状态栏、命令面板、菜单栏常驻、7 页 ⌘1–⌘7 都在，状态与危险动作都走统一状态机。但**三处 P0 级缺口都集中在「异常路径」**：未装 brew 时导航与设置入口失效（死路感）、退出 App 不确认运行中任务、未装 brew 没有可执行的安装指引。另有一组「宣称存在、实际不生效」的交互：命令面板标注的 ⌘⇧K / ⌘⇧D 只在维护页存在，⌘R 在三处重复注册，菜单栏圖标不显示可更新数。这些不会让主流程崩溃，但会让用户对快捷键与菜单栏的信任度下降。

## 二、功能覆盖核对表（外壳相关条目）

| 条目 | 状态 | 证据 | 一句话问题 |
| --- | --- | --- | --- |
| F0.2 未装 brew 给可执行下一步（P0） | 缺失 | ContentView.swift:163–207；OnboardingView 全文 grep 无 `brew.sh`/安装命令 | 只有手动填路径，没有打开 brew.sh、没有可复制安装命令 |
| F6.1 关窗转后台并提示 / 退出确认（P0） | 缺失 | MyApp.swift:17–46 无 NSApplicationDelegate；MenuBarView.swift:73–75 `NSApp.terminate(nil)` | 运行中 ⌘Q / 菜单栏「退出」直接杀 App，不提示 |
| F14.1 菜单栏显示可更新数（P1） | 部分 | MyApp.swift:31–43 标签只有 “Brewbutler”+mug；数字在 MenuBarView.swift:22/86–96 的 popover 内 | 菜单栏本身看不到更新数，要点击才知道 |
| F14 点击不抢前台焦点（需运行验证） | 无法判定 | MyApp.swift:31–44 `.menuBarExtraStyle(.window)` | window 风格是否抢焦点需实机验证 |
| F15.1 空查询显示最近任务与推荐动作（P0） | 部分 | CommandPaletteView.swift:194–260 | 空查询只有 7 页面 + 5 动作，无最近任务、无状态推荐 |
| F15.1 可跳转任意已安装包 | 部分 | CommandPaletteView.swift:215 `.prefix(10)` | 第 11 个匹配之后不可见，也无「更多」入口 |
| 7 个一级页面 + ⌘1–⌘7 | 已实现 | MyApp.swift:50–60；AppSection.shortcut AppState.swift:44–54 | — |
| 状态栏（brew 版本/刷新中/排队/日志） | 已实现 | SidebarView.swift:133–187 | 日志按钮无快捷键提示；无「正在扫描漏洞」状态 |
| 外观切换 | 部分 | ContentView.swift:109–158 | 只能循环点按，无菜单；菜单栏 popover 不跟随 |
| 共享组件（徽章/按钮/toast） | 已实现 | Components.swift | Toast 单条 2.8s，可被覆盖 |
| 无障碍（动态字体/减少动效/焦点环） | 缺失 | 44 处固定 `.system(size:)`；grep 无 dynamicTypeSize / accessibilityReduceMotion / focusEffect | 规范 §7 的承诺未落地 |

## 三、发现（按严重度）

### [E-01] P0｜退出应用不确认运行中的变更任务，brew 可能成为孤儿进程

- **证据**：`MyApp.swift:17–46` 只有 WindowGroup + MenuBarExtra，全仓库 grep 无 `NSApplicationDelegate` / `applicationShouldTerminate`；菜单栏退出是裸调用 `NSApp.terminate(nil)`（`MenuBarView.swift:73–75`）；⌘Q 走 AppKit 默认路径，同样不检查 `appState.tasks.isRunning`。
- **用户场景**：用户点了「全部更新」，看到日志在跑，直接 ⌘Q 关掉 App；App 立即退出，子进程因 `POSIX_SPAWN_SETSID` 独立会话继续执行。
- **现状**：无任何确认；用户以为停止，实际 upgrade 仍在后台跑并可能改系统状态，下次启动看到的索引也可能与真实状态不一致。
- **期望**（PRD F6.1 P0）：「退出时有运行任务需确认」——`applicationShouldTerminate` 中检测到运行/排队任务时弹确认（继续退出会中断任务 / 取消 / 等待完成），并说明「退出后当前任务会被中断」；关窗时给一次「已转入后台，任务继续」提示。
- **建议**：加 `NSApplicationDelegateAdaptor`，`applicationShouldTerminate` 返回 `.terminateCancel` 并复用现有确认 Sheet 风格；菜单栏「退出」与 ⌘Q 共用同一逻辑；关窗提示可用现有 toast（但 toast 只有 2.8s，建议常驻到任务结束）。

### [E-02] P1｜未装 brew 时，侧边栏导航与「打开设置」都是死的

- **证据**：`ContentView.swift:81–86` 的 `detailColumn` 第一分支 `if appState.installation == nil && !appState.isLocatingBrew { BrewMissingView() }` 先于 section switch；`BrewMissingView` 里「打开设置」调 `appState.openSection(.settings)`（`ContentView.swift:192–194`），但 detail 仍渲染 BrewMissingView。
- **用户场景**：用户从旧机器迁移、brew 路径变了，App 显示「找不到 Homebrew」；点侧边栏「设置」或点「打开设置」，只有侧边栏高亮变了，右侧内容纹丝不动；而设置页恰好是填 brew 路径（`brewPathOverride`）的地方。
- **现状**：看起来像按钮坏了/导航卡死；用户只剩「手工输入路径」一条窄路。
- **期望**：未装 brew 只应挡住依赖数据的页面（仪表盘/已安装/更新…），设置、发现应仍可进入；或侧边栏对不可用项置灰并说明「需要先定位 Homebrew」。
- **建议**：把 `BrewMissingView` 收进各数据页的 empty-state（仪表盘/已安装/更新/服务/维护），设置页始终可达；`BrewMissingView` 自身补「打开设置」以外的恢复入口（见 E-03）。

### [E-03] P1｜未装 brew 没有任何「可执行的下一步」（F0.2 P0 缺失）

- **证据**：`ContentView.swift:163–207`（BrewMissingView）只有「手动路径 + 使用该路径 / 重新检测 / 打开设置」；`OnboardingView.swift` 全文无 `brew.sh` / 安装命令 / 复制按钮（grep 仅命中 `formulae.brew.sh` 与包详情的「复制安装命令」）；PRD F0.2 验收明确要求「打开 brew.sh、复制安装命令」。
- **用户场景**：第一次用 Brewbutler、机器上没有 Homebrew；引导页和缺 brew 页都只说「请安装 Homebrew」，用户得自己搜命令。
- **期望**：给静态安装指引 + 「打开 https://brew.sh」+「复制安装命令」（`/bin/bash -c "$(curl -fsSL …/install.sh)"`），并明确「Brewbutler 不会代你执行安装脚本」；无网络时仍是静态文案。
- **建议**：抽一个共享 `BrewInstallGuidance` 视图，引导页与 BrewMissingView 复用；复制用现成 copy + toast 模式。**（本条与 A 部分 F0.2 重叠，合并时保留一条即可）**

### [E-04] P1｜菜单栏常驻图标不显示可更新数（F14.1 P1 缺失）

- **证据**：`MyApp.swift:31–43` 的 `MenuBarExtra("Brewbutler", systemImage: "mug", …)` 是静态标题；可更新数只出现在 popover 内 `MenuBarView.swift:22` 的 `summaryText`（:86–96）。
- **用户场景**：Brewbutler 的产品卖点之一是「菜单栏一眼看到有几个更新」；现在必须点开 popover 才能看到。
- **期望**：菜单栏项显示数字（如 label 文本「3」/ 自绘 NSStatusItem 角标），0 时不显示数字；点击仍打开 popover。
- **建议**：`MenuBarExtra` 的 label 用 `Text`/`Label` 动态渲染 `outdatedCount`（macOS 13+ 支持自定义 label）；若系统限制，退回 AppKit `NSStatusItem`。

### [E-05] P1｜命令面板空查询缺「最近任务与推荐动作」（F15.1 P0 缺失）

- **证据**：`CommandPaletteView.swift:194–260` 的 `buildItems()`：空查询时只遍历 7 个 section + 固定 5 个 action，包分组被 `if !needle.isEmpty` 跳过，且**完全没有读取** `appState.tasks.latestRecord`、`appState.index.outdated` 等状态。
- **用户场景**：用户按 ⌘K 想「继续刚才的任务 / 看看有什么该做」，看到的是 7 个页面和 5 个固定动作，与仪表盘信息重复。
- **期望**（PRD F15.1 P0）：空查询时显示「最近任务」（可再打开日志/重试）+ 基于当前状态的推荐动作（如「有 6 个可更新 → 全部更新」）。
- **建议**：`buildItems()` 增加 `group = .recent`，空查询时插入 `tasks.recentRecords.prefix(3)` 与 1–2 条条件动作（可更新数 >0、扫描过期、有失败任务可重试）。

### [E-06] P1｜命令面板标注的 ⌘⇧K / ⌘⇧D 实际只在维护页生效

- **证据**：`CommandPaletteView.swift:237–241` 给「清理缓存」「运行 brew doctor」标了 `⌘⇧K` / `⌘⇧D`；这两个快捷键只定义在 `MaintenanceView.swift:107`、`:51` 的页面内按钮上。SwiftUI 中页面未挂载时该 shortcut 不注册。
- **用户场景**：用户在仪表盘看到面板写「清理缓存 ⌘⇧K」，按下无反应；到维护页再按才有用（而那时已不需要面板）。
- **期望**：面板里标注的快捷键必须是全局可用的；否则不显示。
- **建议**：把这两条提升到 `AppCommands`（与 E-08 一起整理快捷键表），或从 `PaletteItem.shortcut` 去掉。

### [E-07] P1｜命令面板包结果上限 10 且无「更多」提示，与「任意已安装包」冲突

- **证据**：`CommandPaletteView.swift:215` `.prefix(10)`；无结果时倒是有「在发现页搜索」的兜底（:103–110），但**有结果但被截断时没有任何提示**。
- **用户场景**：用户搜 `lib`，面板只显示 10 个包，找不到第 11 个；也没有「去已安装页继续筛选」的入口。
- **期望**：超过上限时在列表末尾加「还有 N 个结果，在已安装页筛选」；或把上限提高并支持滚动加载。
- **建议**：末尾插入一条 `group = .more` 的动作行，跳 `installed` 并预填 `appState.installed.filter = query`（需确认该字段名）。

### [E-08] P1｜快捷键重复/冲突：⌘R ×3、⌘⇧V ×2、⌘A/⌘⌫ 占用系统语义

- **证据**：
  - ⌘R：`MyApp.swift:66`（菜单「检查更新」）、`DashboardView.swift:43`、`ServicesView.swift:53`（刷新服务）。
  - ⌘⇧V：`MyApp.swift:69`、`DashboardView.swift:179`。
  - ⌘A / ⌘⌫：`InstalledView.swift:252–256` 的隐藏按钮（选中全部 / 批量卸载），与文本输入的标准「全选 / 删除到行首」重叠。
- **用户场景**：用户在服务页按 ⌘R，期望刷新服务，实际命中的可能是菜单的「检查更新」（或反之，取决于 SwiftUI 匹配顺序）；在筛选框里按 ⌘A 可能触发列表全选而不是全选文字。
- **期望**：同一快捷键只注册一次；页面级刷新与全局刷新用不同键（如页面刷新 ⌘⇧R），⌘A 只在列表聚焦时生效、输入框聚焦时让位。
- **建议**：建一张「快捷键登记表」并在 `AppCommands` 集中注册；页面内按钮不再重复定义全局键；⌘A/⌘⌫ 用 `.focused` 判断焦点是否在搜索框。**实际命中顺序需运行验证。**

### [E-09] P2｜「导航」菜单标题里重复写了快捷键

- **证据**：`MyApp.swift:52` 菜单项标题是 `"\(section.title) ⌘\(index + 1)"`，同时又 `.keyboardShortcut(...)`；macOS 会在菜单右侧再渲染一次快捷键。
- **用户场景**：菜单里显示「仪表盘 ⌘1」右侧再来一个「⌘1」，显得粗糙且占宽。
- **建议**：标题只留 `section.title`，快捷键交给 `.keyboardShortcut` 渲染。

### [E-10] P2｜没有 Settings 场景与 ⌘, 快捷键

- **证据**：`MyApp.swift:17–46` 无 `Settings { … }`；`AppCommands` 也没有 ⌘,；设置页只能靠侧边栏或 ⌘7 进入。
- **用户场景**：macOS 用户习惯 ⌘, 打开偏好设置，按下无反应；应用菜单里也没有「设置…」项。
- **期望**：补 `Settings` 场景（或用命令菜单项绑定 ⌘, 打开 `.settings` 页），与侧边栏设置页共用内容。
- **建议**：最小改动是在 `AppCommands` 里加 `Button("设置…")` + `keyboardShortcut(",", modifiers: .command)` → `openSection(.settings)`。

### [E-11] P2｜打开包详情后侧边栏没有任何高亮，用户丢失位置

- **证据**：`SidebarView.swift:12` `isActive: appState.section == section && appState.selectedPackageID == nil`；进入详情后所有行都不 active。
- **用户场景**：从「已安装」点开某个包看详情，侧边栏一片灰，用户不知道自己还在「已安装」下，只能靠 ⌘[ 或再点侧边栏回去。
- **期望**：父级 section 保持高亮（可用更弱的填充/仅文字加粗），或在详情标题处显示面包屑「已安装 / 包名」。
- **建议**：把 `selectedPackageID == nil` 条件去掉，active 样式在详情态降级；`windowTitle` 已有包名，可再加面包屑。

### [E-12] P2｜未装 brew 时，侧边栏底部状态卡没有恢复入口；状态栏日志按钮无快捷键提示

- **证据**：`SidebarView.swift:40–80` 的 `homebrewStatusCard` 是纯展示 VStack（无 Button）；未装时只有红点 +「未检测到 Homebrew」。状态栏「任务日志」按钮（`SidebarView.swift:161–175`）没有 `.help("任务日志 ⌘⌥L")`，而工具栏同款按钮有（`ContentView.swift:126`）。
- **用户场景**：看到红点想点一下重新检测，点不动；悬浮状态栏按钮也不知道有快捷键。
- **建议**：状态卡改为可点击（未装 → 打开 BrewMissingView/设置；已装 → 打开设置的环境分区）；状态栏按钮补 help。

### [E-13] P2｜外观只能循环点按，无菜单、无「跟随系统」直达

- **证据**：`ContentView.swift:109–158`：一个按钮循环 system → light → dark，唯一说明是 `.help("外观：\(label)（点击切换）")`。
- **用户场景**：用户当前是深色，想回「跟随系统」，要连点两次并记住循环顺序；菜单栏也没有外观入口。
- **期望**：用 `Menu` 列出三态（跟随系统/浅色/深色）并显示当前选中；或放一个 `Picker`。
- **建议**：工具栏按钮换成 `Menu` + `Picker`，保留 ⌘⌥… 可选快捷键。

### [E-14] P2｜Toast 单条、2.8s、会被后续消息覆盖，错误不可操作

- **证据**：`AppState.swift:1593–1604`：新 toast 直接覆盖旧 toast（`toast = message`）并取消旧任务；2.8s 自动消失。`Components.swift:470–501` 的 ToastView 无按钮、不可复制、不可停留。失败任务只在 toast 里说「失败：…」，详细输出在日志抽屉（用户可能不知道）。
- **用户场景**：批量更新时连续完成/失败，前一条失败提示被后一条成功提示顶掉；用户没来得及读，也不知道点哪里看详情。
- **期望**：失败 toast 常驻到用户关闭（或至少 8s），带「查看日志」按钮（打开日志抽屉并定位该记录）；成功提示可自动消失。多条消息应排队而不是互相覆盖。
- **建议**：ToastView 增加可选 action（`查看日志`）与关闭按钮；`showToast` 对 `.failure` 不自动消失；失败时同时让状态栏红点/日志入口高亮。

### [E-15] P2｜规范承诺的「动态字体 / 减少动效 / 焦点环」均未实现

- **证据**：44 处固定 `.system(size:)`（`AppTheme.swift:73–91` 的字体函数全部用固定 pt）；全仓库 grep 无 `dynamicTypeSize` / `ScaledMetric` / `accessibilityReduceMotion` / `focusEffect`；`AppTheme.focusableRow()` 仅 `contentShape`（`AppTheme.swift:130–132`）；`PulsingDot` 无条件 `repeatForever`（`SidebarView.swift:186–200`）；自定义 ButtonStyle 无焦点态（`Components.swift:174–223`）。
- **用户场景**：系统字号调大后界面文字不变（对低视力用户无效）；开启「减少动态效果」后脉冲点仍一直在动；全键盘导航时看不到焦点在哪。
- **期望**（ui-design §7）：关键文本支持动态字体；reduce-motion 下把 PulsingDot 改为静态点、去掉抽屉/面板的位移过渡；焦点态统一 2pt 铜色 ring。
- **建议**：优先做「减少动效」与「焦点环」两件低成本高感知的；动态字体至少让 caption/body 用 `.body`/`.caption` 相对字号或 `@ScaledMetric`。

### [E-16] P2｜菜单栏 popover 不跟随应用外观设置

- **证据**：`preferredColorScheme(settings.appearance.colorScheme)` 只挂在 WindowGroup 内容上（`MyApp.swift:20–22`）；`MenuBarExtra` 是独立场景（`MyApp.swift:31–44`），`MenuBarView` 未应用该值。
- **用户场景**：系统深色 + App 内设为浅色时，主窗口浅色、菜单栏 popover 仍是深色。
- **建议**：给 `MenuBarView` 也加 `.preferredColorScheme(...)`（或包一层读取 settings 的容器）。**需运行验证场景隔离是否真的导致该差异。**

### [E-17] P2｜多个 `.sheet` 挂同一视图，可能互相顶掉

- **证据**：`ContentView.swift:44–70` 连续 7 个 `.sheet(item:)` / `.sheet(isPresented:)`。SwiftUI 同一层级同时只支持呈现一个 sheet；当清理/卸载确认打开时，任务完成触发的 `batchSummary` 或 `pendingRetry` 也可能置位。
- **用户场景**：清理 Sheet 开着时一个更新任务失败 → 重试确认可能不弹（或顶掉清理 Sheet），用户以为「没有失败」。
- **建议**：改成单一 `enum ActiveSheet` + 一个 `.sheet(item:)`，按优先级排队。**需运行验证当前是否会静默丢弃。**

### [E-18] P2｜命令面板方向键/回车依赖容器 `.onKeyPress`，焦点在输入框

- **证据**：`CommandPaletteView.swift:63–66` 把 ↑/↓/↵ 挂在容器 VStack 上，`:85` 焦点在 TextField。TextField 通常自行消费 ↑↓（光标到行首/行尾）。
- **用户场景**：用户按下箭头想选择结果，结果只是光标移动，面板看起来「键盘没用」；只能用鼠标。
- **建议**：改用 `.onMoveCommand` / 或对 TextField 的 `.onKeyPress` 优先级处理，或直接自定义 NSTextField 的 `keyDown`。**必须运行验证。**

### [E-19] P2｜面板打开时 ⌘K 不会关闭，全局快捷键仍会穿透

- **证据**：`MyApp.swift:58–60` 只 `showCommandPalette = true`，无 toggle；面板不拦截 ⌘R/⌘⇧V。
- **建议**：`showCommandPalette.toggle()`；面板打开时可用 `.disabled` 或事件拦截屏蔽冲突命令。

## 四、做得好的地方

- 三栏 + 底部状态栏的结构稳定，状态栏常驻展示 brew 版本/前缀、「刷新索引中」、「排队 N」与任务日志入口，用户随时知道系统在忙什么（`SidebarView.swift:133–187`）。
- 危险操作全部走统一的 state-driven Sheet（卸载/清理/autoremove/重试/批次汇总），没有即点即执行的破坏性按钮（`ContentView.swift:44–70`）。
- 命令面板做了「页面 / 包 / 动作」三类分组、无结果时回落到发现页搜索、危险动作有图标与文字标记，方向正确（`CommandPaletteView.swift:94–190`）。
- 外观颜色全部集中在 `AppTheme`，无硬编码色值（grep 验证）；深/浅色用动态 NSColor，语义色齐全。
- 7 个页面都有 ⌘1–⌘7，⌘K、⌘R、⌘⇧V、⌘⌥L 覆盖高频动作；包详情内还有 ⌘[ 返回、⌘U 更新等。
- 菜单栏图标可在设置里关闭（`isInserted` 绑定），未强制常驻。
- 运行中任务在工具栏、状态栏、菜单栏三处都有小圆点提示，跨页面可见。

## 五、需运行验证

1. 命令面板 ↑↓ 选择与 ↵ 打开在焦点位于输入框时是否生效（E-18）。
2. ⌘R 在仪表盘/服务页实际命中的是「检查更新」还是页面刷新（E-08）；⌘A/⌘⌫ 在筛选框聚焦时是否误触发（E-08）。
3. 菜单栏 `.window` 风格点击是否抢前台焦点（F14.1 验收项）。
4. 多个 sheet 同时置位时是否静默丢弃（E-17）。
5. 菜单栏 popover 是否随 `preferredColorScheme` 分裂（E-16）。
6. 退出时运行中的 brew 子进程是否真的存活（E-01 的影响面）。

## 六、方法限制

- 未启动真实 App 做交互录制，所有「按键是否被 TextField 吞掉」「sheet 是否顶掉」「焦点是否可见」均标注为需运行验证；静态阅读无法排除 SwiftUI 运行时行为差异。
- 未对 44 处固定字号逐屏核对对比度；文中只判定「规范承诺的动态字体/动效/焦点环未实现」，不判定具体 WCAG 数值。
- F0.2 与 A 部分重叠、F14/F15 部分条目可能与 C/D 部分交叉，最终合并报告时会去重。
