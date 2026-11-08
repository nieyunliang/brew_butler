# 簇 D：发现、服务、维护与设置

> 评审人 D · 2026-11-05 · 只读静态走查（未运行 App、未执行任何变更类 brew 命令、未 xcodebuild）
> 期望依据：docs/product-plan.md F7–F13、docs/ui-design.md §4.4/§4.6–§4.8/§6–§8；事实依据：当前工作树代码。

## 0. 结论（3–5 条）

1. **危险动作的「确认骨架」是扎实的**：清理、autoremove、服务启停、Brewfile 导入都有独立确认页，默认焦点固定在「取消」（Sheets.swift:5-41），清理的 dry-run 预览与执行彻底分离、scrub 默认关闭。问题不在「敢不敢执行」，而在「失败与未知状态被系统性地显示成健康」——这是本簇最大的系统风险（D-06、D-07）。
2. **诊断导出是隐私承诺与实现相反的地方**：文件里写入了绝对路径、可能含凭据的代理环境变量、含包名的任务标题，却声明「不含包列表、用户名或代理凭据」，且没有预览与脱敏勾选（D-01，P0）。
3. **漏洞覆盖率不是「始终可见」**：Updates 页只在存在安全更新行时才渲染覆盖率；无安全更新、扫描失败或漏洞包不可升级时整块消失，页面头部只剩「0 个安全更新」——足以让「部分覆盖」用户误判安全（D-02，P0）。
4. **发现页主链路可用但降级语义被吞掉**：350ms 防抖、离线缓存+本地索引双回退、⌘F 都在；但 >24h 缓存直接丢弃、「仅显示本地已安装包」的提示又被离线缓存横幅覆盖；cask 安装前没有版本/体积/auto_updates 预览（D-10、D-11）。
5. **服务与维护多处是「半成品语义」**：kill 无入口、日志入口实际复制 plist 路径、doctor/missing 解析失败一律显示通过、Brewfile 导入无差异预览（D-08、D-09、D-13、D-07）。建议修复顺序：P0 隐私与覆盖率 → 三个「假健康」状态 → 功能缺口。

## 1. 功能覆盖核对表

| ID | 结论 | 证据 | 一句话交互问题 |
| --- | --- | --- | --- |
| F7.1 搜索 | 已实现 | DiscoverView.swift:63-68, 152-161; AppState.swift:1424-1506 | 错误态横幅无重试按钮；结果行不含版本信息 |
| F7.2 离线降级 | 部分实现 | AppState.swift:1470-1505（TTL :292） | 超 24h 缓存被丢弃；「仅本地已安装包」提示被离线缓存横幅覆盖 |
| F7.3 cask 独立入口 | 部分实现 | DiscoverView.swift:91-98; Sheets.swift:136-174; BrewTextParser.swift:5-19 | 可筛可装，但无 auto_updates 标注（模型无该字段） |
| F7.4 分类浏览 | 部分实现 | DiscoverView.swift:14-19, 46-48 | 四个 chip 只是把关键词 build/terminal/… 塞进搜索框，不是分类/榜单 |
| F7.5 安装前预览 | 部分实现（弱） | Sheets.swift:136-174; AppState.swift:818-843 | 无版本/体积/类型预览；formula 完全无确认直接入队 |
| F8.1 服务列表 | 部分实现 | ServicesView.swift:95-124; BrewModels.swift:478-534 | 有状态与 plist，无 user 列、无 sudo 系统级服务提示 |
| F8.2 sudo 拒绝 | 部分实现 | AppState.swift:1145-1159; ServicesView.swift:177-205 | 无 root 判定、无拒绝态、无可复制命令；操作后 loadServices 复查有做 |
| F8.3 run/kill | 部分实现 | ServicesView.swift:207-217; BrewClient.swift:560-583 | kill 无入口；run 只在非运行状态出现；文案未解释两者差异 |
| F8.4 日志入口 | 缺失 | AppState.swift:1269-1272; ServicesView.swift:195-198 | 「复制 plist 路径」返回的是 plist；无日志路径；按钮仅异常行可见 |
| F9.1 Brewfile 导出 | 部分实现 | AppState.swift:1381-1406; BrewClient.swift:508-513 | 无 --force/无 Finder 显示；失败提示「查看日志」但该命令不产生日志 |
| F9.2 Brewfile 导入 | 部分实现 | AppState.swift:1408-1417; Sheets.swift:265-290 | 无「将安装项」差异预览；失败项无逐条记录 |
| F10.1 磁盘总览 | 部分实现 | MaintenanceView.swift:280-295; AppState.swift:1276-1289 | 有 Cellar/缓存/Caskroom 数字，无时间戳/刷新；header 口径混用 du 与 dry-run |
| F10.2 预览/执行分离 | 部分实现 | AppState.swift:1325-1350; MaintenanceView.swift:71-113 | 分离与确认有做；解析失败或退出码非 0 仍显示「很干净」并允许执行 |
| F10.3 scrub/prune | 已实现 | Sheets.swift:178-231 | scrub 默认关、二次确认；prune 无入口（未暴露，不算缺陷） |
| F10.4 autoremove | 已实现 | Sheets.swift:235-261; AppState.swift:1352-1377 | 预览 chips + 危险确认；缺「为什么这些包可移除」的依赖链说明 |
| F11.1 覆盖率 | 部分实现 | DashboardView.swift:170-176; UpdatesView.swift:238-253; PackageDetailView.swift:347-366 | Updates 页仅在存在安全更新行时展示覆盖率；维护页无 |
| F11.2 严重度/跳过原因 | 已实现 | DashboardView.swift:302-333; PackageDetailView.swift:287, 302-322 | 跳过原因原样键值（untrusted_tap）未本地化 |
| F11.3 --vulnerable 子集 | 部分实现 | UpdatesView.swift:156-161; AppState.swift:949-988 | 有按钮与 help 文案，无子集差异说明 |
| F11.4 修复计划确认 | 部分实现 | PackageDetailView.swift:194, 302-322; AppState.swift:949-988 | 单包有修复版本；批量一键执行，无计划预览与人工确认 |
| F12.1 doctor | 部分实现 | MaintenanceView.swift:169-212; AppState.swift:1291-1306 | 平铺非分组；权限仅角注；exit≠0 或解析失败显示「未发现问题」；无原文 |
| F12.2 missing | 部分实现 | MaintenanceView.swift:214-224; AppState.swift:1308-1323 | 列出但不可跳转；missingError 从不渲染，非 0 仍可能显示「检查通过」 |
| F12.3 索引时效/变更历史 | 部分实现 | DashboardView.swift:61-62; InstalledView.swift:77; PackageDetailView.swift:482-503 | 索引时间与手动更新有；无索引变更历史；维护页无时效 |
| F12.4 tap 信任 | 缺失 | BrewInstallation.swift:48; BrewLocator.swift:156-180 | Core 探测了 trust 能力，UI 无任何只读展示 |
| F13.1 brew 路径 | 部分实现 | AppState.swift:392-414; SettingsView.swift:167-181 | 校验失败静默回滚，无就地错误（brewError 无渲染） |
| F13.2 外观 | 已实现 | MyApp.swift:21; SettingsView.swift:280-303 | 即时生效，无问题 |
| F13.3 隐私 | 已实现 | SettingsStore.swift:129-130; BrewEnvironment.swift:55; SettingsView.swift:342-373 | 无上传、无遥测、本地统计可清，文案与实现一致 |
| F13.4 通知 | 部分实现 | SettingsView.swift:257-273; AppState.swift:1687-1713 | 有检查按钮与文案引导；无授权状态展示、无系统设置深链，开关与系统授权脱节 |
| F13.5 代理/镜像 | 部分实现 | SettingsView.swift:206-245; SettingsStore.swift:93-115; BrewEnvironment.swift:63-76 | 无 URL 校验/反馈、仅回车生效；三个 HOMEBREW 抑制开关无 UI |
| F13.6 诊断导出 | 部分实现（不安全） | SettingsView.swift:328-332; AppState.swift:1613-1675 | 无预览/脱敏勾选；内容与「不含路径/凭据/包名」声明冲突（见 D-01） |

## 2. 发现清单

### [D-01] P0｜诊断包导出内容与隐私声明相反（路径 + 代理凭据 + 包名），且无预览
- 证据：SettingsView.swift:330-332 声明「不含包列表、命令输出、用户名或代理凭据」；AppState.swift:1628-1634 写入 executablePath/prefix/cellar/cache/repository 绝对路径，:1651-1652 原样写入注入环境变量（BrewEnvironment.swift:63-67 把 proxyURL 塞进 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY，:100-104 不脱敏返回 KEY=value），:1664 写入「安装 foo」式任务标题，:1667 再次声明不含凭据；导出无预览、无勾选（:1613-1618）。
- 场景：高级用户按支持指引导出诊断发给他人或贴到 issue。
- 现状：一次确认即落盘，含用户主目录路径、可能带 user:pass 的代理 URL、最近安装的包名。
- 期望：PRD F13.6「导出前预览 + 默认不含包清单与路径用户名 + 显式勾选」；AGENTS.md §5.9 要求导出前脱敏。
- 建议：加预览与脱敏开关；默认把 $HOME 替换为 ~、掩码代理凭据、任务标题降级为操作类型；或者修正声明（但不应降级隐私承诺）。

### [D-02] P0｜无安全更新时漏洞覆盖率整块消失，只剩「0 个安全更新」
- 证据：UpdatesView.swift:238 仅当 securityEntries 非空才渲染 securityHeader，:245-253 覆盖率/部分覆盖/扫描时间都在其中；页面 header 只写「X 个可用更新 · Y 个安全更新」（:85）。DashboardView.swift:170-176 有覆盖率，但维护页无（MaintenanceView.swift:34-60）。
- 场景：只扫出「部分覆盖」的用户，扫描后发现没有可升级的安全项（漏洞包已是最新/无修复），来更新页确认自己是否安全。
- 现状：页面不显示 checked/total、跳过原因与扫描时间；「安全 0」读起来就是安全。
- 期望：PRD F11.1 / ui-design §8「覆盖率与跳过原因必须始终可见，不写『无漏洞』」。
- 建议：覆盖率行移到页面级 header（与「X 个安全更新」同一行），不随列表为空而消失；维护页补一行安全摘要入口。

### [D-03] P1｜系统级（root）服务不识别、不拒绝，直接入队 `brew services`
- 证据：BrewService 含 user 字段（BrewModels.swift:478-521），ServicesView 从不读 user（grep user/root/sudo 无命中，行渲染见 :95-124）；serviceAction 无条件构造 `brew services <action> <name>`（AppState.swift:1145-1159）。需运行验证：`brew services list --json` 是否返回 user=root 的服务、start 时 brew 是否尝试 sudo。
- 场景：P1 用户看到一个「已停止」的服务，点启动。
- 现状：若该服务 root 托管，UI 与普通服务无区别；按 F8.2 应拒绝并给出可复制命令，而这里会静默交给 brew（无 TTY 下 sudo 只表现为超时/失败）。
- 期望：PRD F8.1/F8.2「sudo 系统级服务不在列表→提示；需 sudo→拒绝并给命令」。
- 建议：user == root 时禁用按钮并显示「需 sudo，请复制命令在终端执行」+ 复制按钮；列表顶部提示系统级服务不会出现在本页。

### [D-04] P1｜brew 路径校验失败没有任何就地错误，输入框残留非法值
- 证据：applyBrewPath 失败会回滚配置并写 brewError（AppState.swift:392-405，:403），但 brewError 的唯一渲染点是 OnboardingView.swift:112，SettingsView 无引用；按钮先置 pathEditing=false 再 await（SettingsView.swift:167-176），:179-181 使按钮立即变回「重新检测」，输入框保留非法路径，再点只会 `locateBrew(nil)` 丢弃输入。
- 场景：高级用户把 brew 路径改到 /opt/homebrew/bin/brew 以外的位置，想确认是否生效。
- 现状：配置静默回到原值，界面没有任何错误文字，用户以为「应用」按钮失灵。
- 期望：PRD F13.1「非法路径就地报错，配置保持不变」。
- 建议：在路径行下方渲染错误与「恢复自动探测」按钮；失败后把 pathDraft 重置为当前生效值，或保留 draft 并让按钮继续为「应用」以便重试。

### [D-05] P1｜代理/镜像输入无校验、仅回车生效，非法值被持久化并影响下次启动
- 证据：三个 TextField 只有 `.onSubmit { applyEnvironmentSettings() }`（SettingsView.swift:212-215, 222-225, 232-235），旁注却写「修改后即时生效」（:242）；applyEnvironmentSettings 只 rebuildClient（AppState.swift:427-429）；proxyURL 的 didSet 立刻写 UserDefaults（SettingsStore.swift:93-99），与是否应用无关；代理不校验直接注入（BrewEnvironment.swift:63-67），API/Bottle 校验失败则静默忽略（:68-73）。
- 场景：用户把代理写成 `127.0.0.1:7890`（缺 scheme）或填了错误镜像地址，没按回车就离开设置页。
- 现状：界面无任何反馈；代理值已落盘，下次启动被注入到所有 brew 调用，搜索/更新全部表现为「网络不可用」，用户难以联想到是代理导致。
- 期望：PRD F13.5「URL 校验」「仅影响 Brewbutler 进程」；校验失败应就地报错且不落盘。
- 建议：失焦即校验并显示错误、提供「应用」按钮与脏标记；非法值不持久化；把 API/Bottle 被忽略的原因显示为警告。

### [D-06] P1｜清理 dry-run 解析失败或退出码非 0，仍显示「环境很干净」并允许执行
- 证据：previewCleanup 只解析 combinedOutput，从不看 result.exitCode（AppState.swift:1331-1343）；parseCleanupPreview 只认「Would remove:」「This operation would free」（BrewTextParser.swift:112-140），其余文本一律返回空 preview；空 preview 时 MaintenanceView.swift:71-75 显示绿色「没有可清理的内容，环境很干净。」，而「清理…」按钮仍可点（:102-106，只按 loading/isReadOnly 禁用）。
- 场景：想清理磁盘但怕误删的用户，先看维护页判断要不要清理。
- 现状：`brew cleanup -n` 因权限/版本/输出格式变化失败时，UI 告诉用户「很干净」，且不解释失败。
- 期望：PRD F10.2「解析失败禁用执行」。
- 建议：exitCode != 0 或 removals 为空但输出不含预期关键字时，显示「预览失败」+ 原始输出折叠 + 复制；此时禁用「清理…」。

### [D-07] P1｜doctor/missing 把「解析失败/非 0 退出」显示为「未发现问题 / 检查通过」
- 证据：runDoctor 保存 doctorExitCode（AppState.swift:1301）但 UI 从不读；MaintenanceView.swift:170-173 只要 issues 为空就显示绿色「doctor 未发现问题。」，:229-233 subtitle 同样只看 issues；checkMissing 在 exit≠0 且 entries 空时设置 missingError（AppState.swift:1317-1318），但 MaintenanceView 从不渲染 missingError，:219 只要 missingReport 非 nil 就显示「brew missing 检查通过。」；parseMissing 把任何非 Warning/Error 行都当条目（BrewTextParser.swift:223-241），解析失败也无法与「无缺失」区分。
- 场景：用户点「运行诊断」确认环境健康。
- 现状：doctor 输出格式变化、权限错误只出现在 stderr、missing 退出码 1 都可能显示为绿色通过；原文折叠入口不存在。
- 期望：PRD F12.1「按问题分组 + 权限不足独立错误态 + 解析失败展示原文」；F12.2「missing 非 0 即有问题」。
- 建议：以 exitCode 为准决定「未知/失败」状态；missingError 渲染为独立错误行；两者都补「查看原始输出」与复制。

### [D-08] P1｜服务缺少 kill 语义，「仅运行一次」只对已停止服务可见
- 证据：Core 的 ServiceAction 明确区分 stop/kill，kill 文案为「停止但保留注册」（BrewClient.swift:560-583）；但 UI 的停止按钮固定发 `.stop`（ServicesView.swift:181），运行中/已计划状态没有更多菜单（:179-186），serviceOptionsMenu 只有「仅运行一次」且只出现在 error/default 分支（:187-217）。
- 场景：P1 用户想临时停掉一个后台服务，但保留登录自启。
- 现状：只能「停止」，而确认文案明确说「launchd 注册也会被移除」（:165）——即无法完成该主任务；kill 语义在 UI 完全不可达。
- 期望：PRD F8.3「run 与 kill 语义必须区分」。
- 建议：运行中服务提供「停止（保留自启）」与「停止并取消自启」两个动作，用菜单承载并在确认文案中写明差异。

### [D-09] P1｜服务日志入口缺失，「复制 plist 路径」返回的是 plist 而不是日志
- 证据：serviceLogPath 直接返回 service.file（AppState.swift:1269-1272），即 launchd plist 路径；ServicesView.swift:195-198 的按钮叫「复制 plist 路径」且只在 error 状态出现；无「查看日志」按钮、无日志路径推导。
- 场景：服务异常（上次退出码非 0）用户想看日志定位。
- 现状：无日志入口；ui-design §4.6 要求的异常行「查看日志」不存在；复制 plist 对排障帮助有限且命名暴露实现细节。
- 期望：PRD F8.4「日志入口；路径不存在时按钮隐藏」。
- 建议：由 plist 的 StandardOutPath/StandardErrorPath 或 `brew services` 约定推导日志路径，存在才显示「查看日志」；否则保留 plist 复制但改名说明用途。

### [D-10] P1｜cask 安装前没有版本/体积/auto_updates 预览，formula 无确认
- 证据：InstallConfirmSheet 只有标题、`brew install --cask <name>` 命令与授权提示（Sheets.swift:136-174）；搜索模型只有 name/summary/kind（BrewTextParser.swift:5-19），无 version/size/autoUpdates；requestInstall 对 formula 直接 performInstall 入队（AppState.swift:818-843）。
- 场景：断网想装 cask 的 P3 用户 / 只想装小体积工具的用户。
- 现状：看不到版本、体积、是否 auto_updates（这类 cask 会被 brew 自己更新），也没有已安装版本信息；安装后只能从任务日志观察。
- 期望：PRD F7.5 / 流程 2「安装前预览版本/体积/类型」；F7.3「auto_updates 标注」。
- 建议：搜索结果补 info 查询（版本/体积/auto_updates，可惰性加载），确认页展示这些字段；对 auto_updates cask 明确提示更新由应用自身完成。

### [D-11] P1｜断网超 24h 后缓存被丢弃，且「仅显示本地已安装包」提示被覆盖
- 证据：performDiscoverSearch 只使用 24h 内的缓存（AppState.swift:1471-1488，TTL :292），过期后回落到本地已安装索引并设置 error「网络不可用，仅显示本地已安装包。」（:1490-1505）；但 DiscoverView.swift:26 的 usingCache 分支优先于 :36 的 error 分支，横幅显示「当前使用离线缓存 / 结果可能不是最新」，且 cacheDate 为 nil 时没有时间戳。
- 场景：P3 用户在飞机上想装一个 cask，两天前搜过。
- 现状：搜不到任何未安装包；界面却说是「离线缓存」的结果，用户无法知道实际只搜了本机已安装包，也不知道缓存已过期。
- 期望：PRD F7.2「过期缓存仍可用，并明确标注可能过期」。
- 建议：过期缓存继续展示并标「缓存已过期（2 天前）」；本地回退时切换横幅标题与文案，明确「仅搜索本机已安装包」，并提供「重试连接」。

### [D-12] P1｜Brewfile 导出失败不可诊断；覆盖已存在文件可能失败；无 Finder 显示
- 证据：exportBrewfile 用 NSSavePanel 允许选择已存在文件，但 bundleDump 不带 `--force`（AppState.swift:1395；BrewClient.swift:508-513）；失败 toast 说「请查看日志」（AppState.swift:1397），而 bundleDump 是单次 execute、不进任务队列、不写日志；成功只存路径，无「在 Finder 中显示」。
- 场景：用户每月导出一次 Brewfile 做备份，选同名文件覆盖。
- 现状：覆盖时 brew 可能报「already exists」→ 导出失败且没有任何可查日志；成功也没有后续动作入口。
- 期望：PRD F9.1「覆盖确认 + 在 Finder 中显示」。
- 建议：自动追加 `--force`（用户在保存面板已确认覆盖）；失败时把 stderr 展示在 toast/详情弹层并提供复制；成功按钮给「在 Finder 中显示」。需运行验证覆盖行为。

### [D-13] P1｜Brewfile 导入没有「将安装项」差异预览，也没有逐条失败记录
- 证据：chooseBrewfileToImport 选完文件直接弹 BrewfileImportSheet（AppState.swift:1408-1417）；sheet 只显示文件路径与一句说明（Sheets.swift:265-290）；performBrewfileImport 以整体任务执行（AppState.swift:1187-1198），失败只留任务日志。
- 场景：P3 用户拿同事的 Brewfile 恢复环境。
- 现状：无法知道会新增哪些包、哪些已存在、哪些 tap 将被引入；部分失败后只能翻日志。
- 期望：PRD F9.2「导入前预览将安装项，并逐条记录失败」。
- 建议：导入前解析 Brewfile 做差异清单（新增/已安装/不支持的 tap），确认页展示；任务结束展示逐条结果（成功/失败/跳过）并支持复制失败命令。

### [D-14] P1｜「日志保留天数」设置无任何实际效果
- 证据：SettingsView.swift:319 的 Stepper 绑定 logRetentionDays；全仓引用仅 SettingsStore.swift:117-119 的持久化与 AppState.swift:1659 的诊断展示，没有任何清理/裁剪任务日志的逻辑。任务日志与历史由 TaskModels 落盘。
- 场景：用户按提示把保留期从 7 天调到 1 天以节省空间。
- 现状：设置值被保存、诊断包会打印它，但日志文件从不按此清理——控件说谎。
- 期望：HIG/PRD 禁止无效果的设置项；要么实现清理，要么移除。
- 建议：在应用启动/任务完成时按保留期裁剪 TaskModels 日志，并在 UI 注明「下次启动生效」；如不实现则删除该控件。

### [D-15] P2｜「分类浏览」实为关键词预设，chip 文案与行为不符
- 证据：categories 只映射 title→query（「开发工具」→"build" 等，DiscoverView.swift:14-19），点击仅写 query 复用搜索（:46-48）。
- 场景：用户点「容器与云」期望看到分类榜单。
- 现状：得到一次 "container" 关键字搜索结果，且 chip 选中态按 query 字面判断。
- 期望：PRD F7.4 分类浏览；至少改名「快捷搜索」并说明是关键词。
- 建议：短期改名并在 chip 上给 .help 说明；中期用 formulae.brew.sh 的 analytics 榜单或 tap/category 数据实现真实分类。

### [D-16] P2｜发现页离线/错误态缺可操作下一步与时间戳
- 证据：error 分支 InlineNotice(.warning) 无 actionTitle（DiscoverView.swift:36-38）；空态「没有找到匹配的包」无按钮（:114-119）；仅 usingCache 分支有「重试连接」与 cacheDate（:26-35）。
- 场景：网络抖动导致搜索失败且无缓存。
- 现状：用户只能自己再敲一次；不知道结果时间。
- 期望：ui-design §4.4 空态与失败态都要有下一步动作。
- 建议：错误横幅与空态统一给「重试」「打开网络设置」；无时间戳时显示「本地索引」。

### [D-17] P2｜安装入队后结果行无进度/排队反馈，重复点击得到去重 toast
- 证据：结果行只按 isInstalled 切换按钮，不读任务状态（DiscoverView.swift:190-200）；enqueue 成功无任何 toast（AppState.swift:796-816），日志抽屉只在任务真正开始执行时打开（TaskQueueStore.swift:372）。
- 场景：队列里已有更新任务，用户连续点两个包的「安装」。
- 现状：点击后界面无变化；第二次点/之后点同一包弹出「已有任务在运行或排队中」，像是错误提示。
- 期望：ui-design §4.4「安装中应有明确状态」。
- 建议：行内按 tasks.records 显示「排队中/安装中」并禁用按钮；入队成功给轻量 toast 或按钮态变化。

### [D-18] P2｜通知开关不反映系统授权状态，无系统设置深链
- 证据：三个 Toggle 直接绑定偏好（SettingsView.swift:258-262），无 authorizationStatus 读取；只有「检查系统通知授权」按钮与一句文字指引（:267-273）；被拒绝后广播静默跳过（AppState.swift:1706），开关仍显示为开。
- 场景：用户拒绝过通知，回来发现三个开关都是开的，以为会收到提醒。
- 现状：无状态、无入口；只有点按钮才得到瞬时 toast。
- 期望：PRD F13.4「未授权时引导系统设置」。
- 建议：读取 notificationSettings 展示「已授权/未授权」，未授权时给「打开系统设置」按钮（x-apple.systempreferences 深链）并置灰开关。

### [D-19] P2｜维护页信息层级与可跳转性不足（missing 不可点、目录无时效）
- 证据：header 只有缓存/旧版本（MaintenanceView.swift:34-60），无 doctor/missing/索引/漏洞摘要；缺失依赖只拼成一行文本（:214-218，无按钮）；目录卡无时间戳/刷新（:280-295）；Caskroom 只有大小（:287）；「清理」预览列表只显示 path（:81-87），sheet 里才有 detail。
- 场景：维护页作为「体检中心」被打开。
- 现状：发现问题后只能自己去别的页面找包；磁盘数字不知道何时统计。
- 期望：ui-design §4.8 维护页应汇总 doctor/missing/孤依赖，并可从缺失项跳转详情（PRD F12.2）。
- 建议：缺失项做成可点链接进包详情；目录卡加「刷新」与统计时间；header 汇总 doctor 条数与索引时效。

### [D-20] P2｜F12.4 tap 信任状态完全无 UI
- 证据：能力探测有 trust（BrewInstallation.swift:48，BrewLocator.swift:156-180），vulns 的 unscanned_formulae 还会给出 untrusted_tap 原因，但全仓 UI 无任何 trust 引用。
- 场景：用户想知道某个第三方 tap 是否被信任、为何该包没被扫描。
- 现状：只能在覆盖率「跳过原因」里看到原始键值（DashboardView.swift:310-315）。
- 期望：PRD F12.4「tap 信任只读展示」。
- 建议：在覆盖原因区块加「未受信任 tap」分组，展示 tap 名与原因的中文说明。

### [D-21] P2｜三个 HOMEBREW 抑制开关没有 UI，用户无法开启或了解风险
- 证据：SettingsStore.swift:105-115 定义 allowNoSudo/allowNoSandboxCask/allowNoAppManagementPrompt（默认 false，安全），BrewEnvironment.swift:74-76 会注入，但 SettingsView 无任何控件/说明。
- 场景：高级用户遇到 cask 沙箱/授权反复弹窗，希望按 PRD 选择抑制。
- 现状：设置项不可达，等同于功能缺失；诊断包会打印这些开关的值但界面无处修改。
- 期望：PRD F13.5「抑制项默认关闭并说明」。
- 建议：在「高级」下沉区加三个开关，每个配风险说明与「仅影响 Brewbutler 启动的 brew 进程」提示。

### [D-22] P2｜一致性/可达性小项：键盘导航、清理预览信息、锁定 cask 无解释
- 证据：搜索支持 ⌘F 但没有 ↑↓/↵ 选择（DiscoverView.swift:56-68, 164-207；ui-design §4.4 要求）；清理内联预览只有 path（MaintenanceView.swift:81-87）；cask 的「解锁」按钮 disabled 无原因（:270-272）。
- 场景：键盘用户浏览搜索；用户想确认清理项是什么；用户想解锁 cask。
- 现状：需鼠标；预览信息不全；禁用按钮无 tooltip/说明。
- 期望：ui-design §7「键盘全部可达、不只靠颜色」；禁用必须有原因。
- 建议：结果行加 .focusable + onKeyPress 上下选择/回车安装；内联预览补 detail；cask 解锁给 .help 说明「cask 不支持锁定」或隐藏按钮。

## 3. 做得好的地方（3–5 条）

1. **危险动作确认骨架**：ConfirmSheetLayout 让回车落在「取消」、确认键用危险样式（Sheets.swift:5-41）；服务确认按动作给不同后果文案（ServicesView.swift:142-175）；InstallConfirmSheet 明确「不代理 sudo，可在终端执行同一命令」（Sheets.swift:151-155）。
2. **状态双编码**：ServiceStatusPill 颜色+文字（Components.swift:76-91，ServicesView.swift:109），异常行还显示上次退出码与 plist 路径（:117-124），不是只靠颜色。
3. **漏洞语义在 Dashboard/详情是诚实的**：部分覆盖 badge + checked/total + 跳过原因 + 扫描时间（DashboardView.swift:170-176, 302-333；PackageDetailView.swift:347-366 用「本次扫描未发现该包的漏洞记录」而非「无漏洞」）；HOMEBREW_NO_ANALYTICS=1（BrewEnvironment.swift:55）与 telemetry 固定关闭（SettingsStore.swift:129-130）兑现了隐私页承诺。
4. **清理/autoremove 的预览与执行分离**：dry-run 结果进独立 sheet、逐项列出、warnings、scrub 默认关且二次确认（Sheets.swift:178-261）；autoremove 用 chips 展示全部包名。
5. **搜索基础设施**：350ms 防抖 + 最新查询优先（DiscoverView.swift:152-161；AppState.swift:1421-1432）、断网缓存与本地索引双回退、缓存时间戳与「重试连接」。

## 4. 需运行验证清单

- `brew services list --json` 是否返回 user=root 的服务；对 root 服务执行 start 时 brew 是否尝试 sudo（决定 D-03 是否升 P0）。
- `brew cleanup -n` 在 Homebrew 7.0.10 的真实前缀（是否为 `==> Would remove:`）与退出码；解析器只认无前缀行（BrewTextParser.swift:112-140）。
- `brew bundle dump --file=<已存在文件>` 是否必须 `--force`（D-12）。
- `brew missing` 非 0 且 stdout 为空/仅 stderr 时的实际输出形态（D-07 的「检查通过」误报路径）。
- `brew doctor` 72 项输出是否全部以 Warning:/Error: 开头（决定 D-07 计数与分组准确性）。
- 搜索失败是否被归为 BrewCommandError.kind == .networkFailure（AppState.swift:1464 的降级文案依赖它）。
- 清理 header「缓存 X」与「旧版本可回收 Y」是否重复计算同一批文件（MaintenanceView.swift:7-11）。
- 通知授权真实状态与设置页 Toggle 的一致性（需在系统设置中改授权后回看）。

## 5. 评审方法与限制

- 只读静态走查：逐个读完 DiscoverView/ServicesView/MaintenanceView/SettingsView/SettingsStore/Sheets 与 AppState 相关方法；未启动 App、未运行任何变更类 brew 命令、未 xcodebuild（遵守本次评审约束）。
- 证据均取自当前工作树代码（仓库处于未提交状态），行号以评审时文件为准；文档用于定义「期望」，冲突时按 AGENTS.md §3 以代码/实测为准。
- 未覆盖：真实 VoiceOver 朗读顺序、窄窗（<980pt）实际布局、系统授权弹窗、服务/清理的真实命令输出——相关结论已标注「需运行验证」。
- 范围限于簇 D；跨簇问题（如 PackageDetail 更新流程、Dashboard 布局）只在证据链需要时引用，不重复评审。
