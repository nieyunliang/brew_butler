# M3 修复计划（48 条 P2）

> 依据：`docs/reviews/ux-review-2026-11-05.md` §4（48 条 P2，逐条细节见 `docs/reviews/parts/*.md`）。
> 前序：M1（10 P0）见 `fix-matrix-m1.md`；M2（40 P1）见 `fix-matrix-m2.md`。
> 目标：M3 结束后 48 条全部「已修复」或「已修复（部分，需运行验证）」并写进 `fix-matrix-m3.md`；不静默跳过。

## 0. 通则（沿用 M1/M2）

- 构建（各自独占 derived data，禁止共用）：
  `xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData-<name> MODULE_CACHE_DIR="$PWD/build/modulecache-<name>" 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build`
- 只改自己名下文件；跨文件 API 先发 `send_message` 给 lead 与对方，签名落地再通知。
- 不跑 `swift test`（Lead 统一跑）、不执行变更类 brew、不做 git 写操作、不新增依赖、不改 `Package.swift`/`pbxproj`。
- 危险动作仍须确认、默认焦点取消；漏洞语义不得出现「无漏洞」；`AppTheme` tokens；zh-Hans。
- 逐条完成后在任务里注明：条目 ID、改动文件:行、验证方式、未做/运行验证项。

## 1. 文件所有权

| 成员 | 文件 |
| --- | --- |
| reviewer-a | `UI/OnboardingView.swift`、`UI/DashboardView.swift` |
| reviewer-b | `UI/InstalledView.swift`、`UI/PackageDetailView.swift`、`UI/Sheets.swift` |
| reviewer-c | `App/TaskQueueStore.swift`、`App/TaskModels.swift`、`UI/UpdatesView.swift`、`UI/LogDrawerView.swift` |
| reviewer-d | `App/AppState.swift`、`App/SettingsStore.swift`、`UI/SettingsView.swift`、`UI/MaintenanceView.swift`、`UI/ServicesView.swift`、`UI/DiscoverView.swift`、`UI/MenuBarView.swift`、`Core/Brew/BrewLocator.swift`、`Core/Brew/BrewInstallation.swift`、`Core/Brew/BrewEnvironment.swift` |
| lead | `ContentView.swift`、`MyApp.swift`、`UI/SidebarView.swift`、`UI/CommandPaletteView.swift`、`Design/AppTheme.swift`、`Design/Components.swift` |

## 2. 分组与逐条要求

### M3-A（reviewer-a，6 条：A-12～A-17）

- **A-12** 扫描进度可读：接 d 提供的 `AppState.scanProgress`（`checked/total`），`scanningBody` 显示「已检查 24/36」+ 已用时间；`LoadingBar`/进度文本补 a11y value。d 未落地前先做 a11y 部分。
- **A-13** 统计卡可点性一致：四张卡统一——已安装→已安装页、可更新→更新页、安全/漏洞→更新页安全区（或包筛漏洞）、服务→服务页；全部可点或全部不可点，可点卡加 `.help` 与 hover 指示。
- **A-14** 健康卡可行动：显示最近检查时间；「运行诊断」显式按钮（不再点卡片隐式执行）；结果可复制摘要；缺失依赖行跳转。
- **A-15** 引导页布局/可达性：固定 560×420 改为可伸缩（maxWidth 620 + ScrollView），步骤点带 a11y label（第 N 步/共 M 步），「跳过」点击区 ≥24pt。
- **A-16** 路径输入回车冲突：路径 TextField `.onSubmit` 执行「使用该路径」，并让默认动作（下一步/重新检测）在输入聚焦时不抢 Return。
- **A-17** 术语统一（本组页面 + 全组遵守）：刷新＝索引刷新、检查更新＝outdated、扫描＝漏洞；副标题/按钮/空态统一，硬编码「刷新」但语义是检查更新的文案改掉。其余组同类文案顺手对齐。

### M3-B（reviewer-b，7 条：B-13～B-19）

- **B-13** 批量卸载面板：按 formula/cask 分组显示、显示将被跳过的依赖方数量与原因、「删除关联文件」选项仅对 cask? 按现有语义逐包列出；确认按钮显示实际可卸载数。
- **B-14** cask 锁定：Homebrew 7 `brew pin --cask` 已支持（本机 `brew pin --help` 实测），`BrewClient.pin` 也已传 `--cask`；删除 `PackageDetailView` 里 "cask 不支持 pin" 的禁用分支，改为可锁定；对 `auto_updates == true` 的 cask 显示「可能绕过 Homebrew 自行更新」提示。
- **B-15** 空态与摘要：已安装页空态补「清除筛选」+「在发现页搜索」按钮；页头摘要随筛选更新（N/M 项）。
- **B-16** 行内操作可发现：列表行加 hover/常显「⋯」菜单（更新/锁定/卸载/复制命令），不要求右键；键盘可达。
- **B-17** 绝对承诺改诚实：删除「卸载它是安全的」，改「本次快照未发现依赖方；卸载前建议确认」；未安装依赖的禁用按钮补 `.help`。
- **B-18** cask 安装确认信息：版本/体积/auto_updates/来源 tap；命令预览按 kind 生成（`brew install --cask`），不硬编码。
- **B-19** 锁定风险提示：首次锁定弹确认（或 InlineNotice）说明 F5.1「依赖该包新版本的其他包可能无法安装或运行」+ `auto_updates` cask 例外；多选支持「批量锁定」。

### M3-C（reviewer-c，10 条：C-08～C-11、C-13～C-18）

- **C-08** 检查更新进行中：按钮态/工具条显示 spinner + 已用时间，超 10s 提示「仍在检查」。
- **C-09** 更新页全选：页头复选框（含部分选中态），与已安装页行为一致，选择集受当前筛选约束。
- **C-10** 选中与入队一致：批量入口使用「当前可见且可更新」集合；有被跳过项时确认面板/Toast 明示「N 个因筛选/锁定/运行中未纳入」。
- **C-11** dry-run 预览可发现：行内/工具栏「预览」入口（不再只藏在溢出菜单）；接 d 将预览改为只读 scope（不占变更队列）。
- **C-13** 复制完整日志：优先复制/定位落盘日志文件（TaskQueueStore 已保存路径），日志被截断时给「打开完整日志」；抽屉内复制加 `.help`。
- **C-14** 部分完成语义：取消/失败后提示「可能已部分完成，请复查该包状态」；未执行行文案用「未执行」而非「已取消」。
- **C-15** 进度信息：进度面板显示已用时间；失败计入「已处理」；长时间无输出显示「等待 brew 输出…」。
- **C-16** a11y/键盘：进度条 `.accessibilityValue("已完成 X/Y")`；移除重复的 ⌘. 注册（保留 LogDrawer 一处）；关键按钮 a11y label。
- **C-17** 面板复位竞态：新批次开始时重置进度面板状态（行、计时、汇总），不混入上一批残留。
- **C-18** 「更新安全项」范围说明：按钮 help/确认面板写明「仅覆盖有可用修复的 X 个安全项；其余 Y 个受影响包需等待上游修复」，不暗示全机安全。

### M3-D（reviewer-d，13 条：D-15～D-22 + A-11/A-18/A-19 + C-12 + E-14）

- **D-15** 「分类浏览」更名/实做：改名「快捷筛选」并在 chip 上标关键词；或按真实分类（GUI/开发工具/数据库…）分组，二者择一，文案与行为一致。
- **D-16** 发现页错误/离线态：显示时间戳 +「重试」+「查看缓存结果」；空结果给「清除关键词/浏览全部」。
- **D-17** 安装入队行内状态：发现页/详情行的安装按钮在排队/运行中显示「排队中/安装中」并禁用，避免重复点击只得到去重 toast。
- **D-18** 通知授权状态：开关反映系统授权（notDetermined/denied/authorized）；denied 时给「打开系统设置」深链；开关失败回滚。
- **D-19** 维护页信息层级：doctor/missing/索引/缓存摘要分组；missing 行可跳包详情；目录项显示最近检查时间与数量。
- **D-20** tap 信任 UI（F12.4）：设置-高级加「tap 信任状态」区；数据来源须先查 `technical-notes.md`/fixture，无 JSON 字段则显示「当前 brew 版本不提供机器可读信任状态」并给 `brew tap-info` 文本入口（标「需技术验证」）。
- **D-21** 抑制开关 UI：设置-高级暴露 `HOMEBREW_NO_AUTO_UPDATE`、`HOMEBREW_NO_INSTALL_CLEANUP`、`HOMEBREW_NO_ENV_HINTS`（以 technical-notes 白名单为准），说明风险与作用域；接 `BrewEnvironment` 注入，诊断包中可见。
- **D-22** 小项：发现页搜索支持 ↑↓ 选择；清理预览列出分组与体积估算；cask 解锁说明原因（与 B-14 对齐）。
- **A-11** 覆盖率分母：只统计可扫描项（formula），cask/不可扫描项单独标注；不出现「覆盖 36/0」；与 UpdatesView 覆盖率文案一致（d 改 AppState 计算，a 不改）。
- **A-18** brew 非可执行：`BrewLocator` 区分 `.notFound` / `.notExecutable`（权限/损坏），错误文案区分；Lead 在 `ContentView` 加对应下一步（先发代码片段给 Lead）。
- **A-19** 多 brew：探测 `/opt/homebrew`、`/usr/local`、`PATH` 多个候选，设置页单选 + 记忆；默认仍取当前规则。
- **C-12** 自动检查更新（F4.7）：`SettingsStore.autoCheckUpdates` 默认开、24h 间隔可关；启动 + 定时静默 `outdated` 检查，离线失败静默；`UpdatesView` 显示「上次自动检查 X」由 c 加（d 提供 `lastAutoCheckAt`）。
- **E-14** Toast 队列：`AppState` 维护 FIFO 队列（错误 5s / 成功 2.8s），不再覆盖；暴露队列计数给 Lead；失败 toast 可点击打开任务日志（Lead 改 ToastView）。

### M3-E（lead，10 条：E-09～E-13、E-15～E-19；A-10 已在 M1 覆盖）

- **E-09** 导航菜单标题去掉手写「⌘N」（系统已渲染快捷键）。
- **E-10** 新增 `Settings` scene + ⌘,（`SettingsLink`/`openSettings`）；保留侧边栏设置页。
- **E-11** 详情打开时侧边栏仍高亮所属分区（加次级指示表示「详情中」）。
- **E-12** 状态栏任务日志按钮补 `.help`（含 ⌘⌥L）；状态卡已可点击（M2 A-04），补 help 文案。
- **E-13** 外观改为工具栏 Menu（跟随系统/浅色/深色 + 勾选态），不再循环点按。
- **E-15** 动态字体/减少动效/焦点环基础：`AppTheme` 字体 helper 默认尺寸改用文本样式（display→title、headline→headline、subheading→title3、body→body、callout→callout、caption→subheadline；显式 size 仍走固定值并注释）；`PulsingDot`/抽屉/Toast 动画在 `accessibilityReduceMotion` 时禁用位移/脉冲；新增 `.focusRing()` 并用于面板行/侧边栏行；各组把本文件 *文本* 直接 `.system(size:)` 换成 helper（图标尺寸可不改）。
- **E-16** 菜单栏 popover 应用 `settings.appearance.colorScheme`。
- **E-17** ContentView 多个 `.sheet` 收敛为单一 enum `ShellSheet` + 单个 `.sheet(item:)`，dismiss 时清对应状态；保持所有入口行为。
- **E-18** 面板键盘：方向键/回车改为可靠拦截（TextField `.onKeyPress` 优先级或局部 `NSEvent` monitor），Esc/⌘K 关闭；标「需运行验证」。
- **E-19** ⌘K toggle（打开/关闭），关闭时恢复焦点。

## 3. 跨组契约（先落地方 send_message 通知）

| 提供方 | API | 消费方 |
| --- | --- | --- |
| d | `AppState.scanProgress: ScanProgress?`（`checked: Int, total: Int`） | a（A-12） |
| d | `AppState.lastAutoCheckAt: Date?`、`SettingsStore.autoCheckUpdates` | c（C-12 文案） |
| d | `AppState.previewUpgrade` 改只读 scope | c（C-11 入口） |
| d | Toast 队列 + `AppState.toastQueueCount` | lead（ToastView） |
| d | `BrewLocator` 新错误 case（A-18） | lead（ContentView 文案） |
| lead | `AppTheme` 字体 helper（签名不变）、`.focusRing()`、`ToastView` 可点击 | 全组 |
| lead | `ShellSheet` 只动 ContentView | 无 |

## 4. 验收

- 每组：专属构建通过 + 逐条说明；Lead 全量构建 + `swift test`（56 用例，3 个已知 PTY 失败允许）。
- 产出 `docs/reviews/fix-matrix-m3.md`（48 行：ID / 状态 / 文件:行 / 验证 / 未做原因），更新 `ux-review` 顶部进度，最后向用户汇报。
- 文档同步（Lead 收口）：`docs/ui-design.md`（字体/焦点环/设置场景/术语）、`docs/product-plan.md`（F5.1 cask 锁定已支持、F4.7 自动检查落地口径）、`docs/technical-notes.md`（cask pin、suppression 变量、tap-info 能力）。
