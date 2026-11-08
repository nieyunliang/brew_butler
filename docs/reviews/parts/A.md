# 簇 A：首次启动与仪表盘

> 评审对象：首次启动 + 环境探测（F0.1–F0.4）、仪表盘（统计卡 / F11 安全卡 / 最近任务 / 健康度 / Cellar 卡）与启动路径上的加载 / 空 / 错误态。
> 基准：代码为事实来源，PRD/UI 规范为期望依据（AGENTS §3 冲突顺序：本机实测 > technical-notes > PRD > UI 规范）。
> 只读评审：未改源码、未编译、未执行任何 brew 命令；无法运行 App，交互类结论标注「需运行验证」。

## 0. 结论

- 最严重：仪表盘会把「有已知漏洞但暂无修复」显示成「本次扫描未发现」（`DashboardView.swift:67-73`），并把 `outdated` 拉取失败显示成「可更新 0」（同文件 26-65），两个决定「今天要不要更新」的关键数字都可能错成"安全"。
- 真正的首次用户被卡在失败分支：未装 brew 时没有安装指引（F0.2 缺失），且 brew 缺失期间设置页被整体顶掉、「打开设置」是死按钮（`ContentView.swift:81-82,198-200`）。
- 探测进行中主界面直接渲染 0 值空仪表盘，没有页面级不确定态，与 F0.1「探测中显示不确定态」和 NFR「冷启动骨架 ≤1.5s」不符（`ContentView.swift:79-97`）。
- 最近任务卡点任意记录都只打开「最新一条」任务抽屉，点旧失败记录看不到失败原因（`DashboardView.swift:404-406` + `LogDrawerView.swift:14`）。
- 做得好：无扫描结果时默认「扫描未知」、部分覆盖 badge + 跳过原因可展开、扫描可取消并保留上次结果、能力降级原因在设置页有列出。

## 1. 功能覆盖核对表

| ID | 状态 | 证据 | 一句话交互问题 |
| --- | --- | --- | --- |
| F0.1 | 部分实现 | `AppState.swift:326-334,372-390`；`BrewLocator.swift:19-45`；`SidebarView.swift:40-75` | 探测无页面级不确定态；多 brew 静默取第一个；无执行权限被报成「找不到」 |
| F0.2 | 缺失 | `OnboardingView.swift:111-134`；`ContentView.swift:163-206`；全仓无 brew.sh 链接/复制命令 | 失败页只有手动路径与重试，没有可执行的安装下一步 |
| F0.3 | 部分实现 | `SettingsView.swift:186-190`；`BrewInstallation.swift:88,122`；主界面无横幅 | 能力降级只在设置页列出，进入主界面后无「部分功能不可用」提示 |
| F0.4 | 部分实现 | `OnboardingView.swift:170-185`；`SettingsView.swift:139` | 隐私步只有 2 条，未写「不上传包列表/命令输出/环境信息」；回看只能从设置进（缺 brew 时进不去） |
| F11.1 | 部分实现 | `DashboardView.swift:162-182,250-252,302-333`；`AppState.swift:594-597` | checked/total、skipped、complete、扫描时间均可见；但覆盖分母含 cask 且取消/失败文案不自洽 |
| F11.2 | 部分实现 | `DashboardView.swift:67-73,336-387`；`PackageSnapshot.swift:201,175`；全仓无「完整扫描不代表没有漏洞」 | 失败显示「扫描未知」✓；但「无修复漏洞」被写成「本次扫描未发现」，缺免责文案 |
| F13.1 | 部分实现 | `OnboardingView.swift:117-125`；`SettingsView.swift:150-210`；`AppState.swift:392-414` | 手动路径可校验；设置页失败无就地报错（`brewError` 不渲染） |
| F1.1（骨架） | 部分实现 | `MyApp.swift:26`；`DashboardView.swift:77-110` | 「骨架先出数据后填」未实现；冷启动探测期显示 0 个包 |
| 流程 1（PRD §8） | 部分实现 | `OnboardingView.swift:73-200`；`ContentView.swift:44-46` | 成功/隐私/首次索引/⌘K 提示在；异常支线「安装指引」「多 brew 选择并记忆」缺失 |
| 流程 6（PRD §8） | 部分实现 | `DashboardView.swift:445-507`；`AppState.swift:1291-1305` | 有 doctor 摘要；无诊断时间戳、无复制命令/文档链接、无「重新检查」前后对比 |
| NFR（PRD §9） | 部分实现 | `Components.swift:435-454`；`DashboardView.swift:184-204` | 冷启动骨架未做；扫描无「24/36」计数与 progressbar 语义；VO 全流程未验证 |

## 2. 发现清单

### P0

**[A-01] P0｜「暂无修复的漏洞」在仪表盘被显示成「本次扫描未发现」**

- 证据：`DashboardView.swift:67-73` 的 `securityDetail` 以 `index.securityUpdates.isEmpty` 判「本次扫描未发现」；同一安全卡 header 用 `report.affectedFormulaCount`（`:162-166`）；`PackageSnapshot.swift:201` 的 `securityUpdates = outdated.filter(\.isSecurityUpdate)`、`:175` 的 `isSecurityUpdate = finding != nil`，即两者是「有漏洞 ∧ 有可更新版本」的交集。全仓 grep「完整扫描」「不代表」无结果。
- 场景：用了两周的老用户早上扫一次，`libtiff`/`openssl` 有 CVE 但上游无修复版本 → 「可更新 0 · 本次扫描未发现」，下方安全卡却写「2 个受影响包 · 0 个有修复」。
- 现状：统计卡给出"未发现"结论，与同一屏安全卡自相矛盾；用户据此判断「今天不用更新」。
- 期望：PRD F11.1「如实展示覆盖范围」与 F11.2「扫描失败显示未知而非安全」；AGENTS 硬约束 8「任何位置都不写『无漏洞』，只写『本次扫描未发现』+ 覆盖率」；ui-design §8 要求区分「修复可用 / 暂无修复」并注明「完整扫描不代表没有漏洞」。
- 建议：`securityDetail` 改用 `vulnReport.affectedFormulaCount`，文案改为「2 个受影响包 · 0 个有修复」；在安全卡底部固定一行免责文案；`index.securityUpdates` 只用于「可更新」页标记。

**[A-02] P0｜刷新 / outdated 拉取失败在仪表盘完全不可见，0 值看起来像健康状态**

- 证据：`DashboardView.swift:26-65` 的 header 只拼日期 + 版本 + `lastRefreshAt`，不读 `refreshError` / `outdatedRefreshError` / `indexSourceNote`；`AppState.swift:485-505` 拉取失败会回退缓存并注释「A failed outdated read must never look like "0 updates"」，但这两个错误只在 `UpdatesView.swift:123,134-139` 显示，`indexSourceNote` 只在 `InstalledView.swift:29-33` 显示；`AppState.swift:542-549` 的索引失败同样不进入仪表盘。
- 场景：代理坏了/断网，刷新返回错误 → 仪表盘「已安装 0」「可更新 0」「更新索引 12 分钟前」→ 用户以为环境干净，直接关窗。
- 现状：错误被状态层正确记录，但没有一处聚合到启动即看的仪表盘；无缓存时甚至显示 0 个包。
- 期望：PRD F11.1、F13.5 与 AGENTS「失败不得显示为 0」；ui-design §4.1 要求仪表盘呈现数据来源与陈旧状态。
- 建议：仪表盘顶部按优先级渲染 `InlineNotice(.warning)`（刷新失败 / 更新列表失败 / 正在显示缓存），把失败时的 0 显示成「—」并附「重试」；陈旧数据在 header 标注「缓存 · X 前」。

### P1

**[A-03] P1｜探测进行中主界面是空仪表盘，没有页面级不确定态**

- 证据：`ContentView.swift:79-97` 仅在 `installation == nil && !isLocatingBrew` 时切到 `BrewMissingView`；探测中条件为假，落到 `switch section` → `DashboardView`。`MyApp.swift:26` 的 `.task` 启动 `bootstrap()`，`SidebarView.swift:40-75` 有 spinner，但详情区是「已安装 0 / 可更新 0 / Cellar — / 尚未扫描」。
- 场景：新机器首次打开或 `brew` 在慢磁盘/zsh 探测中，引导「跳过」后看到满屏 0 和「尚未扫描」，误以为没装任何包或索引坏了。
- 现状：无骨架、无「正在探测 Homebrew…」页面级提示，2 秒以上没有任何反馈。
- 期望：PRD F0.1「探测中显示不确定态」；NFR 冷启动骨架 ≤1.5s、≥2s 无反馈需心跳；HIG 加载反馈。
- 建议：`detailColumn` 增加 `isLocatingBrew` 分支渲染探测骨架（复用 `SidebarView` 的 spinner 文案 + 3 个统计卡骨架），探测失败再切 `BrewMissingView`。

**[A-04] P1｜brew 缺失时设置页不可达，「打开设置」是死按钮**

- 证据：`ContentView.swift:81-82` 的 `BrewMissingView` 分支优先于 `switch section`，因此侧栏选「设置」也仍渲染缺 brew 页；`ContentView.swift:198-200` 的「打开设置」只 `appState.openSection(.settings)`，界面无任何变化。`OnboardingView.swift:131-133` 还提示「可以稍后继续在设置中配置」——该建议在缺 brew 时无效。
- 场景：用户要在设置里配代理/镜像（F13.5）或看隐私声明（F13.3）→ 点侧栏设置，内容仍是缺 brew 页 → 认为按钮坏了；或按引导提示去设置填路径，也到不了。
- 现状：设置页所有分区（含 Homebrew 环境）在 brew 缺失期间完全不可达；用户只能留在缺 brew 页用那个内嵌路径输入。
- 期望：PRD F13.1/F13.3「设置随时可达」；ui-design §9 异常态不应互相阻断。
- 建议：`BrewMissingView` 只在「依赖 brew 的 section」前置显示（如已安装/可更新/服务），设置/外观/隐私保持可达；「打开设置」改为聚焦本页路径输入框或跳转后滚动定位。

**[A-05] P1｜未装 brew 时没有任何安装指引（F0.2 P0 缺失）**

- 证据：`OnboardingView.swift:111-134` 失败分支只有「手动指定 brew 路径 / 使用 / 重试自动探测」+ 一句 caption；`ContentView.swift:163-206` 同样只有路径输入与「重新检测」；全仓外部链接只有 OSV（`BrewModels.swift:723`）和主页/路径打开（`AppState.swift:786,791`），无 brew.sh、无复制安装命令。
- 场景：新 Mac 完全没装 Homebrew，按引导走到底后在「找不到 Homebrew」页找不到任何"怎么装"的入口。
- 现状：流程卡住，用户必须自己知道去 brew.sh 或搜索引擎。
- 期望：PRD F0.2 与验收「展示安装指引与可复制命令；不崩溃、不自动执行安装」；无网络时仍可读静态说明。
- 建议：抽一个 `BrewInstallGuide` 组件（一句说明 +「打开 brew.sh」按钮 + 可复制命令 + 复制成功 toast + 「不代为执行」说明），同时用于引导失败步与 `BrewMissingView`。

**[A-06] P1｜能力降级（F0.3）没有主界面横幅，功能静默降级**

- 证据：降级原因只在 `SettingsView.swift:186-190` 的 Homebrew 环境里列出；`BrewInstallation.swift:88` 的 `isDegraded`、`:122` 的 `versionText` 未被仪表盘/侧栏/状态栏使用；`AppState.swift:372-390` 仅对只读模式发一次 toast，jq 缺失等降级无提示。
- 场景：旧版 brew 或 PATH 无 `jq` → 快路径被禁用、某些能力不可用 → 用户看到列表加载慢/数据缺字段，却没有任何"部分功能不可用"的解释。
- 期望：PRD F0.3 验收「进入主界面显示能力降级横幅，依赖新 flag 或 `list --versions --json` 的功能禁用并说明原因」；ui-design §9 错误/降级态。
- 建议：`ContentView` 顶部（`StatusBarView` 之上）用 `InlineNotice(.warning)` 展示 `installation.capabilities.degradedReasons` 摘要，带「详情」跳设置环境区；依赖受影响能力的按钮加 `.help` 原因。

**[A-07] P1｜最近任务点任意记录都打开「最新一条」，看不到当时失败原因**

- 证据：`DashboardView.swift:404-406` 行按钮只 `appState.tasks.showDrawer = true`，不传 record id；`LogDrawerView.swift:14` 固定取 `appState.tasks.latestRecord`；`TaskQueueStore.swift:101,137` 已有 `records` 与跨会话 `loadHistory()`。
- 场景：早上点开昨天失败的升级记录，抽屉展示的是刚刚成功的刷新任务 → 找不到失败诊断，也无法复制命令。
- 现状：卡片语义（点击查看该任务）与实际（打开最新任务）不一致；行内只有状态胶囊/标题/耗时，失败无摘要。
- 期望：PRD F6.4 失败可诊断（退出码 + 关键行 + 复制命令）；列表点击应打开对应记录（HIG 视图选择与详情一致）。
- 建议：`showDrawer` 改成携带 `recordID`；`LogDrawerView` 优先用注入记录、缺省回退最新；行内补失败首行与「查看详情」。

**[A-08] P1｜引导「扫描已安装的包」失败后无任何反馈，会原地循环**

- 证据：`OnboardingView.swift:138-168` 完全不渲染 `appState.refreshError`；`startScan`（161-165）失败后 `isRefreshing` 变 false、`index` 仍为空，于是又回到「首次读取需要几秒钟…」+「开始扫描」；`AppState.swift:462-550` 的 `catch` 只写状态。
- 场景：网络或 brew 异常时，用户在引导里连点三次「开始扫描」都只看到 LoadingBar 闪一下，没有任何错误与替代路径（「跳过」只前进，不提示）。
- 现状：失败不可见、不可区分；PRD 流程 1 要求首次索引 >3s 可跳过且失败给出下一步。
- 期望：失败时就地显示原因（`InlineNotice`）+「重试」+「先跳过，稍后在仪表盘刷新」。
- 建议：`scanStep` 增加错误分支与跳过按钮；失败时文案改为「读取失败：…」。

**[A-09] P1｜扫描状态机文案不自洽：前置失败只 toast、取消/失败后仍写「尚未扫描」**

- 证据：`AppState.swift:607-657` 三个前置 guard（未就绪 / 不支持 vulns / 索引为空）只弹 toast；`DashboardView.swift:145-153` 空态固定「尚未扫描」+ 可点的「开始扫描」，`:156-158` 的错误提示与它并列；`AppState.swift:645,650` 取消文案固定「扫描已取消；保留了上次结果。」，而首次扫描被取消时并无上次结果。
- 场景：索引尚未刷新好时点「开始扫描」→ 只有右上角 toast 一闪 → 卡片仍写「尚未扫描」；首次扫描点取消 → 卡片说「保留了上次结果」但页面仍「尚未扫描」。
- 现状：用户不知道扫描是否真的开始/为何没开始/当前是可重试还是等待。
- 期望：AGENTS 硬约束 8（扫描失败显示「未知」）+ ui-design §8 扫描状态；禁用要有原因。
- 建议：前置不满足时 CTA 禁用并在卡片内写明原因与跳转（如「先刷新包列表」）；失败/取消后空态标题改为「扫描失败 / 已取消」+ 重试；取消文案按有无历史结果分支。

### P2

**[A-10] P2｜「全部更新 N」是批量变更，却无确认面板**

- 证据：`DashboardView.swift:45-53` 点击直接 `appState.upgradeAll()`，`AppState.swift:909-947` 立即 beginBatch + enqueue；全屏无包清单/数量/预计影响确认。
- 场景：想更新两个包，误点「全部更新 12」→ 立刻排队 12 个变更任务，只能逐个取消。
- 期望：PRD 流程 3 步骤 2「勾选或全选 →『更新选中』→ 确认面板列出包与数量」；危险/批量操作先确认（AGENTS 硬约束 7 的同一原则）。
- 建议：先弹确认 sheet（包名、数量、是否有安全更新、取消为默认焦点），再入队。

**[A-11] P2｜覆盖度分母混入不可扫描项，索引为空时出现「覆盖 36/0」**

- 证据：`AppState.swift:594-597` 用 `"覆盖 \(report.checked)/\(index.packages.count)"`，分母含 cask 与无 source URL 的包；`DashboardView.swift:230` 直接展示；`:237-239` 空 findings 时又内联一次 `checked/packages.count`；`index` 为空（刷新失败）时会显示 `36/0`。
- 场景：部分覆盖时用户看到「覆盖 36/59」，但 23 个 skipped 永远不可能被覆盖，比例长期停在 61%，容易被读成「扫描没跑完」。
- 期望：PRD F11.1「如实展示覆盖范围」；ui-design §8 的「36/59」应注明口径。
- 建议：分母取「可扫描包数」（checked + unscanned），或文案改「已检查 36 个 · 跳过 23 个」并 `index.packages.isEmpty` 时不显示比例。

**[A-12] P2｜进度条无语义、扫描无「24/36」计数**

- 证据：`Components.swift:435-454` 的 `LoadingBar` 只有动画，无 `accessibilityValue`/进度；`DashboardView.swift:184-204` 只显示「已用 N 秒」，虽有组合 a11y label，但没有进度值；`TimelineView` 每秒刷新会让 VO 反复播报。
- 期望：ui-design §8「24/36 · 已用 12 秒」+ 无障碍 progressbar；HIG 进度可感知。
- 建议：补 `accessibilityElement` + `accessibilityValue`；若 brew 无法给进度，用「阶段 + 已用时间」并提供「停止」；避免每秒重设 label。

**[A-13] P2｜统计卡可点性不一致：只有「服务」可点且无提示**

- 证据：`DashboardView.swift:98-108` 服务卡外包 `Button` + `.buttonStyle(.plain)`（无 hover、无 `accessibilityHint`），其余「已安装/可更新/Cellar」是不可点 `StatCard`（`Components.swift:133-170` 无按钮/悬停态）。
- 场景：用户想从「可更新 3」直接进更新页，点了没反应；而「服务」卡点了会跳页，行为不可预期。
- 期望：ui-design §4.1 卡片入口一致 + ui-design §7 焦点/悬停可见。
- 建议：让「已安装/可更新/Cellar（清理）」也整卡可点并加 hover 高亮与 VO hint；或统一都不可点、改为卡内文字链。

**[A-14] P2｜健康卡结果不可行动：无时间戳、无复制命令、「诊断」按钮隐式执行**

- 证据：`DashboardView.swift:445-507`：`doctorReport == nil` 显示「尚未运行诊断。」，有结果时列 2 条 issues +「另有 N 条提示」，但问题行不可点、不能复制、无诊断时间；「诊断」按钮（483-491）同时 `openSection(.maintenance)` 并 `Task { await appState.runDoctor() }`；`AppState.swift:1291-1305` 不持久化、不记时间。
- 场景：看到「N 条提示」想解决 → 点不动、看不到具体修复命令；重进页面不知道小结是不是几分钟前的。
- 期望：PRD 流程 6（doctor >30s 分组、每张卡复制命令 + 文档链接、重新检查前后对比）；F6.4 一键复制。
- 建议：加「上次诊断 X 前」、问题行展开 + 复制命令、显式「重新检查」按钮；诊断按钮不再附带自动执行（或说明）。

**[A-15] P2｜引导页固定 560×420、步骤点无标签、「跳过」命中区偏小**

- 证据：`OnboardingView.swift:58` 固定 `.frame(width: 560, height: 420)`（不可缩放，长文案/大字体下易挤压）；`:30-37` 步骤圆点无 `accessibilityLabel`、无「第 n 步，共 5 步」；`:14-17`「跳过」`.buttonStyle(.plain)` + `caption` 11pt + `text3`。
- 期望：ui-design §7（动态字体、27pt 最小目标、键盘/VO）；HIG 弹窗适应内容、控件 44pt 行高。
- 建议：改为可随动态字体伸展的布局（最小尺寸而非固定），步骤点加「第 2 步，共 5 步」标签，跳过按钮提到正文号并加内边距/悬停。

**[A-16] P2｜默认动作与手动路径输入的回车可能冲突**

- 证据：`OnboardingView.swift:45-49`「下一步」带 `.keyboardShortcut(.defaultAction)`；检测失败步 `:117-125` 的路径 `TextField` 无 `onSubmit`，「使用」按钮是普通样式。
- 场景：用户粘贴 `.../brew` 后按回车，期望"应用路径"，实际可能触发默认动作直接进入下一步（跳过手动路径）。
- 期望：HIG 表单中 TextField 回车应提交本字段。
- 建议：给路径输入加 `.onSubmit { applyManualPath() }` 或在失焦时校验；需运行验证实际行为（见 §4）。

**[A-17] P2｜术语不一致：「刷新」vs PRD/UI 的「检查更新」，「扫描」指代两种动作**

- 证据：`DashboardView.swift:36-43` 按钮文案「刷新」（⌘R），而 `MyApp.swift` 操作菜单同一快捷键写「检查更新」，ui-design §4.1 写「检查更新」；`OnboardingView.swift:141,161-165` 把读取包列表也叫「扫描」，与安全扫描（F11）同名。
- 场景：用户不确定「刷新」是刷包列表还是查更新；引导里「开始扫描」被理解为漏洞扫描而犹豫。
- 期望：ui-design §6 术语表 + 状态词固定表。
- 建议：统一「检查更新」；引导里改为「读取已安装包」；安全扫描保留「安全扫描」。

**[A-18] P2｜brew 存在但无执行权限时被报成「找不到 Homebrew」**

- 证据：`BrewLocator.swift:27-28` `isExecutableFile` 失败静默 `continue`，最终 `:43-46` 返回 `.notFound`；`BrewInstallation.swift:141` 文案固定「找不到 Homebrew。请安装 Homebrew，或在设置中指定 brew 路径。」
- 场景：`/opt/homebrew/bin/brew` 权限被改坏（或迁移后遗留）→ 应用说"没安装"，用户去重装。
- 期望：PRD F0.1 边界「无执行权限提示权限问题」。
- 建议：候选存在但不可执行时记录并返回 `.notExecutable`，错误文案给权限修复提示（如 `chmod`/重装指引），区分「不存在」与「不可执行」。

**[A-19] P2｜多 brew 共存时静默选第一个，无选择与记忆**

- 证据：`BrewLocator.swift:6-11` 固定候选顺序 `/opt/homebrew` → `/usr/local`；`:19-45` 首个 `verify` 成功即返回，不提示存在多个；`SettingsStore`/`AppState` 无多候选选择 UI。
- 场景：Intel 迁移到 Apple Silicon 后两套 brew 都在，用户实际使用 `/usr/local`，应用却接管了 `/opt/homebrew`（反之亦然）。
- 期望：PRD 流程 1 异常支线「检测到多个 brew → 让用户选择并记忆」。
- 建议：探测返回全部可用候选，引导步出现选择列表并写入 `brewPathOverride`。

**[A-20] P2｜设置页输入非法 brew 路径失败无任何反馈（与启动路径交叉）**

- 证据：`AppState.swift:392-414` 失败时回滚设置并写 `brewError`，但 `SettingsView.swift:150-210` 不渲染 `brewError`（全 App 只有引导与 `BrewMissingView` 显示它）。
- 场景：在设置里改了错误路径点「应用」→ 按钮回到「应用」、安装状态不变，没有错误提示 → 用户不知道是否生效。
- 期望：PRD F13.1 验收「非法路径就地报错并保持原配置不变」。
- 建议：环境分区内联显示 `brewError`（InlineNotice `.warning`）+ 失败时聚焦输入框；与簇 B 的设置页评审重叠，归口建议以 B 为准。

## 3. 做得好的地方

1. 无扫描结果时默认「扫描未知」而非"安全"（`DashboardView.swift:67-69`），并把「本次扫描未发现」作为成功色文案（`:336-387`）——漏洞语义底线守住了。
2. 部分覆盖有明确 badge + 可展开的跳过/未扫描原因清单 +「cask 与第三方 tap 不在 OSV 映射范围内」解释（`:168-182,302-333`），信息密度高且不粉饰。
3. 扫描后台可取消，「取消后保留上次结果」与已有结果时的 header 时间戳配合（`:184-204`；`AppState.swift:659-661`），符合 PRD F11.1「不阻塞、可取消」。
4. `outdated` 失败时状态层回退缓存并保留旧时间戳，注释明确写出语义（`AppState.swift:485-505`）——状态层设计是对的，只是展示层没用上（见 A-02）。
5. 引导失败不阻塞（跳过常驻、检测失败可继续），并用 toast 告知只读模式（`AppState.swift:372-390`），符合 F0.1「不阻塞」。
6. 组件与主题 token 复用良好（`StatCard`/`SectionCard`/`EmptyStateView`/`InlineNotice`，`AppTheme` 动态色），未见硬编码十六进制色值。

## 4. 需运行验证清单

1. 窄窗 980/1024：安全卡 header accessory（badge + 时间 + 重新扫描）与「最近任务 + 健康卡」两列 HStack 是否截断/换行（`DashboardView.swift:24,168-182`）。
2. 键盘：路径 TextField 回车是否触发默认动作「下一步」（`OnboardingView.swift:45-49,117-125`，A-16）；Tab 顺序；Esc 关闭引导后 `onboardingCompleted` 是否仍为 false（可再次出现）。
3. 深色模式：warning/success/chip 文本与背景对比度是否 ≥4.5:1（token 有 dark 值，需 Accessibility Inspector 实测）。
4. 探测耗时：三路径候选 + `/bin/zsh -lc` 探测实际是否超 5s？慢探测时仪表盘空态持续多久（PRD F0.1 验收「5s 内识别」）。
5. VoiceOver：扫描卡组合标签是否每秒重复播报；`LoadingBar` 是否被读成无意义元素；统计卡是否读出「服务」可点。
6. 构造无 `jq`/旧 brew 环境，确认降级功能是否静默失败、是否有崩溃（A-06）。
7. brew 缺失时点侧栏「设置」与「打开设置」是否确实无视觉变化（A-04）。
8. 取消扫描后错误条是否持续显示到下一次扫描（`AppState.swift:624` 才清空），以及首次取消的文案与实际（A-09）。

## 5. 评审方法与限制

- 方法：逐屏读源码（`OnboardingView`、`DashboardView`、`AppState` 启动/索引/扫描/磁盘相关方法、`ContentView` 分支、`Components`、`BrewLocator`）+ 对照 PRD §7.1/§7.7/§8/§9 与 ui-design §4.1/§4.9/§6/§7/§8；用 grep 核对文案与调用点，交叉验证「错误写进状态但没人显示」类缺陷。
- 未做：未编译、未运行 App、未执行任何 brew 命令；无截图/DOM，交互与无障碍结论均基于代码路径推断，凡不能从代码确定的已列入 §4。
- 限制：本簇只评审启动路径与仪表盘；设置页/更新页/已安装页仅在与启动路径交叉处引用（A-20 与簇 B 重叠，归口以 B 为准）。文档与代码不一致处以代码为准，期望依据已写明 PRD/UI 条目；`docs/technical-notes.md` 未逐条复核（本簇不涉及命令语义）。
