# S · 设置 / 状态层 / 核心契约组（reviewer-d）

日期：2026-11-06 · 范围：`SettingsView.swift`、`DiagnosticsSheet.swift`、`AppState.swift`、`SettingsStore.swift`、`BrewLocator.swift`、`BrewInstallation.swift`、`BrewEnvironment.swift` · 方法：只读走查真实用户路径（点击 → action → 状态 → 界面），无 git 基线，落点以 fix-matrix + mtime 为准。

## 0. 一句话结论

D 组的**状态层支撑大多真实存在且可用**（候选扫描、行内任务、FIFO toast、自动检查时间戳、六项抑制开关、诊断脱敏函数都写完了），但 **P0-08 的入口接错了面板、D-04/A-19 的「坏路径」处理存在静默回退漏洞**，因此修复在用户界面层面只能算「实现完成、体验未闭环」——整体可信度：中。

## 1. 逐条判定

| ID | 修复声称 | 用户实际路径 | 判定 | 证据 |
|---|---|---|---|---|
| D-15 | 发现页快捷筛选 + 说明 | 搜索框下预设按钮 → 改 `discover.kind` / query → 重搜 | ✅ 已修 | DiscoverView.swift:12-26（注释自认「不是真实分类」）、:98-105 |
| D-16 | 错误态可见、可重试 | 搜索失败 → InlineNotice + 重试 | ⚠️ 部分 | DiscoverView.swift:44-48；错误无时间戳，且缓存回退时错误被替换（AppState.swift:2057-2060、2079-2081） |
| D-17 | 安装/排队行内可见 | 发现页点安装 → 行内 ProgressView +「排队中/处理中」，按钮被替换 | ✅ 已修 | DiscoverView.swift:279-282、:303-320；AppState.swift:2345-2350 |
| D-18 | 通知授权 banner/深链/denied 禁用 | 进入设置即读授权状态，denied 时 banner + 打开系统设置，开关禁用 | ⚠️ 部分 | SettingsView.swift:459-484 成立；但仅在 pane 首次出现刷新（:502），系统授权后返回不更新；「重新检查授权状态」实为再次请求授权（:489-492 → AppState.swift:2435） |
| D-19 | 维护页健康摘要/统计时间/missing 下钻 | 维护页头一行摘要含 doctor/missing/索引/缓存与统计时间 | ✅ 已修 | MaintenanceView.swift:58-99、:488-507；状态层有 `loadedAt/doctorError/missingError`（AppState.swift:151-170） |
| D-20 | 只读 tap 信任区 + 复制命令 | 设置 → 首页「tap 信任状态（只读）」：能力位、跳过包清单、复制 `brew trust --json=v1` | ⚠️ 部分 | SettingsView.swift:665-701、:704-708；`untrustedTapNames` 按 reason 字符串含 "untrusted" 过滤（AppState.swift:786-792，fixture 值 `untrusted_tap`，Tests/Fixtures/vulns.json:2718-2719）；但未展示任何实际信任数据，「当前 brew 支持（只读展示）」名不副实 |
| D-21 | 六项抑制开关显式化 | 高级 → 6 个 Toggle，附带作用域/风险说明，切换即 `applyEnvironmentSettings()` | ⚠️ 部分 | SettingsView.swift:590-663；BrewEnvironment.swift:61-83、:107-111；无二次确认/无「恢复默认」，3 个 `ALLOW_*` 后果文案写成既定事实（product-plan.md:224 标「需逐一验证语义」） |
| D-22 | ↑↓/↵、清理预览详情、cask 解锁说明 | 发现页键盘选择；清理 sheet 详情（UI 组范围） | ⚠️ 部分（本组仅状态层） | 选择集在结果数变化时重置 DiscoverView.swift:64-66；状态层无新缺陷，其余由 UI 组判 |
| P0-08 | 诊断导出脱敏 + 预览 + 隐私声明 | 高级 →「导出诊断包…」→ 期望弹预览 sheet | ❌ 未修（用户不可达） | 按钮在 AdvancedSettingsPane（SettingsView.swift:578），预览 sheet 却挂在 HomebrewSettingsPane（:696-701），而 `sectionContent` 一次只挂载一个 pane（:95-107）；在高级页点击无呈现（详见 D2-01）。脱敏函数本身成立：AppState.swift:2224-2297、2300-2340 |
| A-18 | 「装了但坏了」与「没装」区分 | 路径不可执行 → 失败 → `brewPathError` 内联 danger + notExecutable 文案 | ⚠️ 部分 | 文案 BrewInstallation.swift:139-145；`isNotExecutable` 注释称「UI 用来区分」（:149-152）但全仓无调用；BrewMissingView 标题仍「找不到 Homebrew」（ContentView.swift:289），Onboarding 仍给安装区块（OnboardingView.swift:139-150） |
| A-19 | 多 brew 只读候选 + 单选记忆 | 扫描本机安装 → 列出路径/版本/不可执行徽章 → 点选即应用并持久化 | ⚠️ 部分 | 列表/记忆/持久化成立（SettingsView.swift:309-373；BrewLocator.swift:56-84；SettingsStore.swift:60-62）；但「可执行但 `--version` 失败」的候选无徽章且可选（BrewLocator.swift:171-172，SettingsView.swift:361-371） |
| D-04 | 路径校验内联错误且保留已保存值 | 输入坏路径 → 应用 → 内联「无法使用该路径」 | ❌ 未修 | 失败分支确实回滚并给错误（AppState.swift:551-559），但 `locate` 在 override 失败后会静默采用其它 brew 并返回成功（BrewLocator.swift:19-51），于是 `applyBrewPath` 走成功分支把坏路径持久化（AppState.swift:549、561-569） |
| D-05 | 代理/镜像校验 + 应用按钮 | 输入非法 URL → 应用 → 字段下红字，已保存值不变 | ✅ 已修 | SettingsView.swift:375-409、:286-291；仅接受 http(s)（socks5 被拒为 P2 缺口） |
| E-14 | FIFO toast + 失败查看 + 队列计数 | 连续任务完成 → 底部依次展示，failure 停留 5s 带「查看」，右侧「+N」 | ⚠️ 部分 | AppState.swift:2170-2207；ToastView Components.swift:482-536；`dismissToast`/`openLogDrawerFromToast` 无调用方（AppState.swift:2178-2187），无点击/Esc 关闭，批量任务只能等队列播完 |
| C-12 | 自动检查时间戳持久可见 | 高级/更新页显示「上次自动检查 …」，关页重开仍可见 | ⚠️ 部分 | 持久化 SettingsStore.swift:103-111、175；展示 SettingsView.swift:550-554、UpdatesView.swift:267-281；失败也写时间戳（AppState.swift:2379-2381）、手动刷新亦写（:697-700），UI 不区分成败/自动手动；启动定位失败则不启动定时器（:479-484） |

统计：✅ 4（D-05、D-15、D-17、D-19）· ⚠️ 9（D-16、D-18、D-20、D-21、D-22、A-18、A-19、E-14、C-12）· ❌ 2（D-04、P0-08），共 15 项。

## 2. 新发现问题

**D2-01 P1 · 诊断导出按钮点了没反应（P0-08 被接断）**
用户：设置 → 高级 →「导出诊断包…」→ 无弹层、无 toast、无任何反馈。
代码：按钮 `SettingsView.swift:578` 只置 `pendingDiagnosticsExport`（AppState.swift:2218-2220）；唯一 `.sheet(item:)` 挂在 HomebrewSettingsPane 内 `SettingsView.swift:696-701`；`sectionContent` 为 switch，非当前 section 的 pane 不在视图树（`SettingsView.swift:95-107`）。切回「Homebrew」页才可能补弹（未清理的 pending 状态）。
影响：隐私友好的预览/脱敏导出在真实入口 100% 不可用；用户只会在「高级」里反复点击。

**D2-02 P1 · 无效 brew 路径被静默接受并落盘（D-04 的核心漏洞）**
用户：在路径框填 `/opt/homebrew/bin/brew_bak`（或不可执行副本）→「应用」→ 无错误；路径被记住，但界面显示的版本/prefix 其实来自另一套 brew。
代码：`locate` 把 override 排在候选首位，失败后继续遍历固定路径，任一可用即 `.success`，不校验 `installation.executablePath == override`（`BrewLocator.swift:19-51`，成功点 :31/:44）；`applyBrewPath` 先写 `settings.brewPathOverride = trimmed`（`AppState.swift:549`），仅在 `locate` 失败时回滚（:551-559），故静默回退时坏路径被持久化（:549、:561-569）。
影响：用户以为切到了某个 brew，实际在用另一个；下次启动继续沿用坏路径，且无路径行可核对（Homebrew 面板只显示版本/prefix，`SettingsView.swift:194-205`，从不显示实际 executablePath）。

**D2-03 P1 · 损坏但「可执行」的候选没有标记且可点选**
用户：扫描本机安装 → 一行显示路径、无版本、无「不可执行」徽章 → 点选 → 无错误重演 D2-02，radio 却标在这一行。
代码：`BrewCandidate.versionText == nil && isExecutable` 正是「坏了」的判据（`BrewLocator.swift:171-172`），UI 只用 `isExecutable` 决定徽章与禁用（`SettingsView.swift:361-371`），`isSelected` 仍按 override 匹配（:343-345）。
影响：坏安装看起来完全正常，选中后进入静默回退，形成最坏组合（看似成功 + 实际未生效）。

**D2-04 P1 · 通知授权状态与系统真实状态不同步**
用户：banner 点「打开系统设置」→ 允许通知 → 回到 App → 仍显示「系统通知已被拒绝」、三个开关仍灰；点「重新检查授权状态」才恢复。
代码：只在 pane 首次出现 `.task` 刷新（`SettingsView.swift:502`），全仓无 scenePhase/激活刷新（grep 仅 AppState.swift:482、2438）；「重新检查授权状态」实际调用 `requestNotificationPermission()`（`SettingsView.swift:489-492` → `AppState.swift:2435-2447`），名实不符。
影响：刚按引导完成授权的用户被界面告知「未授权」，会再次点系统设置或认为开关坏了。

**D2-05 P2 · 「上次自动检查」把失败、手动刷新混为一谈**
用户：看到「上次自动检查 3 分钟前」→ 以为检查成功；实际可能是失败重试或手动点「检查更新」写入的时间。
代码：失败 catch 也写 `settings.lastAutoCheckAt = Date()`（`AppState.swift:2379-2381`）；`refreshIndex` 成功且开关打开时也写（:697-700）；UI 仅显示时间（`SettingsView.swift:550-554`、`UpdatesView.swift:267-281`），无成功/失败/来源区分，也无「检查失败」持久错误态（违背用户要求的「不依赖一次性 toast」）。
影响：自动检查静默失效时用户完全无感，会长期以为更新是新鲜的。

**D2-06 P2 · 启动定位失败后，修好 brew 的本会话不再自动检查/统计磁盘**
用户：装/修好 brew → 设置里成功应用路径 → 自动检查与磁盘统计仍不启动，直到重启 App。
代码：`bootstrap` 在 `guard installation != nil else { return }` 处直接返回（`AppState.swift:479-484`），跳过 `startAutoCheckTimer()`/`computeDiskUsage()`；`applyBrewPath` 成功后只 refreshIndex，不补启动（:561-569）。
影响：路径修好后「上次自动检查」长期「尚未检查」，磁盘占用一直—，看起来像功能坏了。

**D2-07 P2 · 搜索失败原因被缓存/本地回退覆盖，且错误态没有时间戳**
用户：brew 搜索因非网络原因失败 → 界面却写「网络不可用，显示 X 前的缓存」或「仅显示本地已安装包」。
代码：错误先按 `BrewCommandError.kind == .networkFailure` 区分（`AppState.swift:2034-2038`），但缓存分支仅在 `discover.error == nil` 时才补文案（:2057-2060），本地回退**无条件覆盖**为网络不可用（:2081）；`DiscoverState` 无失败时间字段（:187-200）。
影响：误导排障方向（用户去折腾网络/镜像），且 D-16 要求的「错误时间」缺失。

**D2-08 P2 · toast 无法手动关闭或跳过，批量任务时排长队**
用户：批量更新 10 个包 → 底部 toast 连播约半分钟，无关闭/跳过；想立刻看某条失败必须等它轮播。
代码：`dismissToast()` 注释写「点击 toast 或按 Esc」，但全仓无调用方（`AppState.swift:2178-2183`），`ToastView` 无 tap/Esc/关闭按钮（Components.swift:482-536）；`openLogDrawerFromToast` 亦无人调用（:2185-2187）。
影响：反馈层不可控；失败信息可能因后续 toast 排队而被延迟感知。

**D2-09 P2 · 诊断导出：隐私声明只列「不含什么」，导出取消也静默关窗**
用户：勾选「包含绝对路径」后取消保存 → 预览 sheet 仍关闭，无「未导出」提示；读隐私声明无法知道文件里还有设置、注入变量值（代理/镜像主机）、最近 10 条任务元数据。
代码：`diagnosticsPrivacyStatement` 仅描述包名/路径与三个排除项（`AppState.swift:2293-2297`），而实际包含「## 设置」「## 注入的环境变量」（含代理/镜像主机名与 masked 凭据，:2244-2262）、最近任务时间/状态/exit（:2264-2268）；`saveDiagnostics` 面板取消即 return（:2279-2291），`DiagnosticsSheet` 却无条件 `dismiss()`（DiagnosticsSheet.swift:79-82）。另：在 sheet 内 `panel.runModal()` 的模态层级需实机确认。
影响：用户对「会离开本机的内容」判断不完整；取消导出被当成成功体验的一部分。

**D2-10 P2 · 高级页三个 `ALLOW_*` 风险项没有确认/撤销路径，且文案越过验证状态**
用户：打开「跳过 cask 沙箱」→ 立即生效，无确认；想恢复原样只能自己记得逐项关掉。
代码：6 个 Toggle 直接写 setting + `applyEnvironmentSettings()`（`SettingsView.swift:590-663`），无 confirmation dialog、无「恢复默认」；`HOMEBREW_NO_SUDO/NO_SANDBOX_CASK/NO_APP_MANAGEMENT_PERMISSIONS_PROMPT` 的后果在 product-plan.md:224 标注「需逐一验证语义」，UI 却写成确定性结论（SettingsView.swift:627-659）。
影响：危险开关的「知情同意」只有一行小字，误开后无快捷回退。

**D2-11 P2 · `activeTask` 的 nil-kind 会跨类型误匹配**
用户：在发现页搜到同名 formula/cask，正跑一个同名服务操作 → 该行显示「处理中」并隐藏「安装/详情」按钮。
代码：`activeTask` 允许 `record.packageKind == nil` 匹配任意 kind（`AppState.swift:2345-2350`），而 `serviceAction` 建记录时只设 packageName（:1592）。
影响：短时（服务启停期间）挡住安装入口，且状态词与实际操作不符。

## 3. 系统性问题

1. **「声明一致性」是本组最集中的缺陷模式**：D-04 声称「失败会保留原配置」但静默回退分支绕开了它；D-18 声称「授权状态可见」但只在进页时读一次；C-12 声称「上次自动检查」但失败/手动都写同一时间戳；P0-08 声称「导出前可预览」但入口挂在另一个面板。共同解法是**把状态机的每个成功/失败分支都映射到一个用户可见、且与声明措辞一一对应的状态位**（例如 `brewPathOutcome` = applied/fallbackRejected/failed，授权状态在 scenePhase 激活时刷新，autoCheck 增加 `.failed(Date)`）。
2. **诊断隐私层：脱敏实现可信，声明与入口不可信**。所有路径→`<已隐藏>`、任务标题→动作级脱敏、`user:pass@`→`***` 均已核对成立（AppState.swift:2300-2340），主机名/命令输出确实不在导出内；但隐私声明只列排除项、未列包含项，且用户根本走不到预览（D2-01）。另外 `<已隐藏>` 对技术支持零信息量，建议路径做「保留末级目录名 + 哈希前缀」的可用脱敏，或提供「仅本次导出包含路径」的显式二次确认。

## 4. 需实机验证（静态不可定论）

1. D2-01：在「高级」点导出是否真的不弹（静态强疑）；若切到「Homebrew」才补弹，确认 pending 状态是否残留。
2. `NSSavePanel.runModal()` 在 SwiftUI sheet 内的层级与可用性（macOS 27），以及取消面板后是否真的无提示关窗。
3. D2-04：系统设置授权后返回，banner/开关是否仍为 denied；深链 `x-apple.systempreferences:com.apple.Notifications-Settings.extension` 是否直达通知列表（可能需要 app id 参数）。
4. D2-02/03：构造「存在但不可执行」与「可执行但 `--version` 失败」的 brew 副本，验证应用后无错误、路径被记住、版本行来自回退 brew。
5. D2-06：启动时改名 brew 制造定位失败 → 恢复 → 看自动检查/磁盘统计是否仍不启动。
6. 多 brew 机器（ARM + Intel 双安装）验证候选单选记忆与重启后一致性。
7. D2-08：批量任务期间 toast 队列节奏与「查看」是否真跳到对应失败任务。

## 5. 本组结论

- 修复的**状态层基础**多数已具备，但「用户路径闭环」缺三处硬伤：诊断导出入口错挂面板（P1）、坏 brew 路径静默回退并落盘（P1）、授权状态只在进页时读取（P1）。
- 建议 M4 优先修 D2-01（把 `.sheet` 上移到 SettingsView 根）、D2-02/D2-03（`applyBrewPath` 校验 `found.executablePath == trimmed`，候选行按 `versionText == nil` 标记「无法运行」并禁用）、D2-04（scenePhase 激活刷新 + 按钮改名/改为纯读取），其余 P2 可与文案澄清一起处理。
