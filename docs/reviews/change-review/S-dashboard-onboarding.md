# S 组复核：仪表盘 / 引导 / 发现（用户交互视角）

- 复核范围：`Brewbutler/UI/DashboardView.swift`、`OnboardingView.swift`、`DiscoverView.swift`，及决定其行为的 `AppState.swift`、`BatchUpdateSheet.swift`、`ContentView.swift`。
- 方法：静态走查真实路径「点哪里 → action → 状态 → 看到什么」；本机未运行 App，交互动效标「需实机」。
- 基线说明：仓库无 git diff 基线，严格按三份 fix-matrix 的声称逐条核对，不照抄矩阵行号。

## 1. 一句话结论

A 组修复的**主体方向可信**：误导性安全文案、失败不可见、批量更新无确认这三个 P0 的主要路径都真实落地了；但失败/未知态的「最后一公里」仍有 3 处会让人做出错误判断（健康卡假健康、失败时显示 0、部分覆盖仍用安全绿），属于修完 80% 但状态口径未收敛。

判定统计：共 18 项——✅ 已修 10 / ⚠️ 部分 8 / ❌ 未修 0。

## 2. 逐条判定

| ID | 修复声称 | 用户实际看到 | 判定 | 证据（file:line） |
| --- | --- | --- | --- | --- |
| A-10 | 全部更新先确认 | 点「全部更新 N」弹出确认面板，列出包数与前 8 名，默认焦点在取消 | ✅ | DashboardView.swift:47-55；AppState.swift:1327-1341；BatchUpdateSheet.swift:19-70 |
| A-11 | 覆盖率分母改 formula、cask 单列 | 安全卡右侧「覆盖 x/y 个 formula · cask 不在 OSV · 跳过 n」，无假比例 | ✅ | AppState.swift:764-780；DashboardView.swift:344-360 |
| A-12 | 扫描进度=时间+已检查 X/Y+取消可聚焦 | 只有「已用 N 秒」；`已检查 X/Y` 在扫描中恒不可见（进度只在完成后写入） | ⚠️ | DashboardView.swift:267-323；AppState.swift:821,829-832 |
| A-13 | 四张统计卡整卡可点 | 四卡均可点、hover 描边、help/VO 提示与实际跳转一致 | ✅ | DashboardView.swift:139-197,776-793 |
| A-14 | 健康卡可行动、有时间戳、可复制摘要 | 运行诊断/复制摘要/展开命令/跳维护页都在；但失败与退出码异常会被显示成「环境健康」 | ⚠️ | DashboardView.swift:582-773；AppState.swift:1770-1784 |
| A-15 | 引导页可伸缩、显示第 N 步、跳过可点 | ScrollView+min/max 布局、5 个步骤点（读屏有「第 N 步，共 5 步」）、跳过有 44pt 点击区 | ✅ | OnboardingView.swift:21-55,78-80 |
| A-16 | 路径输入回车不再误触发下一步 | 输入框聚焦时 Enter 应用路径；失焦后 Enter 才走默认按钮 | ✅ | OnboardingView.swift:184-198,320-331 |
| A-17 | 刷新/检查/扫描术语统一 | 「检查更新」「重新扫描」「运行诊断」「读取」在各自场景含义稳定，引导页明确指回仪表盘「检查更新」 | ✅ | DashboardView.swift:38-55；OnboardingView.swift:232；DashboardView.swift:290 |
| A-18 | 区分「没装」与「装了但坏」 | 报错文案区分并给出 chmod 指引；但引导页仍无条件展示「安装 Homebrew」面板 | ⚠️ | BrewInstallation.swift:135-149；OnboardingView.swift:138-182；isNotExecutable 无 UI 引用 |
| A-19 | 多 brew 不再静默取首个 | 设置页「扫描本机安装」后单选列表，不可执行项有危险徽章且禁用 | ✅ | BrewLocator.swift:56-82；SettingsView.swift:309-343 |
| A-20 | 设置路径错误内联显示 | 错误以内联 danger 通知呈现，带「重试应用」，不再只 toast | ✅ | SettingsView.swift:188-193；AppState.swift:560-572 |
| P0-01 | 「未发现」不再冒充安全 | 统计卡已改用 affectedFormulaCount，与安全卡一致；但部分覆盖时仍显示无覆盖限定的「本次扫描未发现」，分布条仍是成功绿 | ⚠️ | DashboardView.swift:133-137,236,457-508 |
| P0-02 | 刷新失败可见、数量不显示 0 | 失败横幅+重试、缓存来源/时间、「—」均已落地；无缓存失败时「可更新」仍显示 0 | ⚠️ | DashboardView.swift:62-128,139-185；AppState.swift:615-710 |
| P0-09 | 无安全更新时覆盖率仍可见 | 更新页覆盖行常显（含「尚未运行·覆盖范围未知」）；仪表盘有报告时覆盖信息始终在安全卡内 | ✅ | UpdatesView.swift:242-262；DashboardView.swift:325-374 |
| P0-07 入口 | 三个「全部更新」入口都走确认 | 仪表盘入口已接入并禁用重复/只读/失败态；但 all/vulnerable 确认后重新全局执行，面板承诺的「已跳过进行中」不成立 | ⚠️ | DashboardView.swift:47-55；AppState.swift:1345-1359,1202-1242；BatchUpdateSheet.swift:103-112 |
| D-15 | 发现页「分类浏览」改为诚实标注 | 顶部写「快捷筛选」，help/说明明确「只是预置关键词，不是分类榜单」；chip 名称仍像分类 | ✅ | DiscoverView.swift:12-23,131-152 |
| D-16 | 错误态给下一步 | 空结果有清除关键词/重试，缓存提示有强制刷新与缓存时间；但真实错误横幅实际不可达，失败一律显示「网络不可用」 | ⚠️ | DiscoverView.swift:30-44,166-187；AppState.swift:2042-2082 |
| D-17 | 安装行内显示排队中/安装中 | 有任务时按钮换成 spinner+「排队中/安装中/处理中」，带 a11y；取消中的任务也显示「排队中」 | ⚠️ | DiscoverView.swift:304-316；AppState.swift:1990-2004 |

## 3. 新发现问题

### P1

**A2-01 健康卡会把「失败/异常」显示成「环境健康」**
用户看到：跑过一次诊断后再次运行诊断失败，卡片仍显示上次的绿色「环境健康」，没有任何失败提示；或 doctor 退出码非 0 但未解析出 issue 时，仍是绿色「环境健康」、副标题「正常」。
代码：`runDoctor` 失败时不清空旧 `doctorReport`/`doctorExitCode`（AppState.swift:1770-1784），HealthCard 先渲染 report 后才渲染 error（DashboardView.swift:603-619），且只按 `issues.isEmpty` 判绿（604-607、723-731）；维护页对同一结果有退出码检查（MaintenanceView.swift:245-248）。
影响：用户据此判断「环境没问题」，且「复制摘要」会把旧结果当本次结果复制出去。

**A2-02 索引读取失败时「可更新」仍显示 0**
用户看到：断网/brew 异常且本机无缓存，顶部有红色「读取已安装包失败」，但「可更新」大数字仍是 0（detail「扫描未知」），不是「—」。
代码：`outdatedUnavailable` 只看 `outdatedRefreshError`，info 失败时该值为 nil（DashboardView.swift:68-70,162-171；AppState.swift:640-661,702-709）。
影响：P0-02 修了「已安装」，漏了「可更新」；看卡片数字的人会误以为没有更新。

### P2

**A2-03 批量确认面板的「已跳过：进行中」并未真的跳过**
用户看到：面板写「将更新 9 个包 · 已跳过：进行中 1」，确认后实际执行 `brew upgrade`（全部）或 `--vulnerable`，进行中的包仍会被这批命令覆盖。
代码：confirm 的 `.all/.vulnerable` 分支重新调用 `upgradeAll()/upgradeVulnerable()`，不读 `plan.packageIDs`（AppState.swift:1345-1359,1202-1242），与 BatchUpdatePlan 注释「确认的就是队列收到的」矛盾。
影响：确认页的承诺不可核对，锁定/进行中包的跳过说明失真（update 动作本身不危险，故 P2）。

**A2-04 发现页真实搜索错误永远不可见，且被误标成网络问题**
用户看到：`brew search` 因非网络原因失败，页面顶部仍写「网络不可用，仅显示本地已安装包」，没有「搜索失败：…」或「强制刷新失败：…」。
代码：失败路径必然把 `usingCache` 置 true，`else if let error` 分支（DiscoverView.swift:40-44）实际不可达；本地回退无条件覆盖 error（AppState.swift:2067-2082，缓存回退见 2042-2062）。
影响：用户按错误原因排查（断网 vs brew/参数问题）会走错方向；重试按钮仍在，故未阻断。

**A2-05 扫描进度文案与事实不符**
用户看到：30 秒扫描期间只有「已用 N 秒」，没有「已检查 X/Y」；首次扫描取消后却提示「保留了上次结果」。
代码：`scanProgress.checked` 只在扫描成功后写入（AppState.swift:821,829-832），`progressText` 要求 checked>0（DashboardView.swift:318-323），所以常态不可见；固定 caption 写「取消后保留上次结果」（DashboardView.swift:290），首扫取消文案在 AppState.swift:846-848。
影响：长扫描像卡死；首扫取消文案自相矛盾。

**A2-06 部分覆盖仍是「成功绿 + 本次扫描未发现」**
用户看到：报告 `complete=false`（有跳过/cask 未覆盖），安全卡头上有「部分覆盖」，但分布条整条绿色并写「本次扫描未发现受影响包」，统计卡 detail 也只写「本次扫描未发现」。
代码：`SeverityDistributionBar` 的 total==0 分支固定 `success.opacity(0.4)` 与 success 文字（DashboardView.swift:468-470,498-508，a11y 505-508），不区分 complete；统计卡见 133-137。
影响：绿色=安全的直觉强于旁边的小徽章，仍可能被读成「扫过且干净」。

**A2-07 失败态残留：无缓存却说「索引来自缓存」、刷新中无反馈**
用户看到：首刷失败且无缓存时，横幅下方副标题仍写「索引来自缓存」（实际没有任何缓存）；点「检查更新」只看到按钮变灰，界面无 spinner/「检查中」。
代码：info 失败 catch 无条件 `usesCachedIndex = true`（AppState.swift:702-709），副标题据此拼「索引来自缓存」（DashboardView.swift:124-125）；仪表盘刷新按钮无进行中指示（38-45），对比更新页有 LoadingBar+已用时间（UpdatesView.swift:222-239）。
影响：自相矛盾文案降低信任；慢刷新时用户不确定是否点成功。

**A2-08 旧的「检查更新失败」横幅会冒充当前错误**
用户看到：上一轮 outdated 失败后，再点检查更新且这次是安装包列表读取失败，横幅仍报「检查更新失败」并显示旧错误。
代码：refreshIndex 开始时只清 `refreshError`（AppState.swift:627），`outdatedRefreshError` 要等 outdated 成功才清（645）；横幅优先级 outdated 在前（DashboardView.swift:76-84）。
影响：错误归因错误，用户会去重试错误的东西；同属状态源未收敛。

**A2-09 引导页检测失败仍可「下一步」，进入不可操作步骤；装了但坏了仍展示安装指引**
用户看到：第 2 步检测失败后「下一步」可点，第 3 步「开始读取」是灰的，原因只在 hover help；`notExecutable` 的错误文案建议 chmod，但下方仍整块展示「安装 Homebrew」。
代码：`isAdvanceBlocked` 只看第 3 步 isRefreshing（OnboardingView.swift:85-87）；scanStep 禁用原因只在 help（231-241）；detectStep 对所有无 installation 情况都渲染安装区（138-182），`isNotExecutable` 无 UI 使用（BrewInstallation.swift:150-153）。
影响：首次使用用户容易卡在灰按钮或选错修复动作（重装 vs 修权限）。

**A2-10 发现页交互残留：点行只高亮、取消中显示「排队中」**
用户看到：鼠标点结果行只高亮不打开/安装；任务正在取消时该行仍显示「排队中」。
代码：行 onTapGesture 仅设置 selectedIndex/focus（DiscoverView.swift:211-217）；状态文案只判 `.running`，其余全落「排队中」（304-316，`cancelling` 非终态见 TaskModels.swift:122-156）。
影响：鼠标用户多点一步；状态与队列真实状态漂移（可从队列抽屉看到「正在取消」）。

## 4. 系统性问题

1. **同一事实多处各自推导**：安全结论分散在统计卡/安全卡头/分布条，doctor 结论分散在健康卡/维护页，更新数据分散在 header/统计卡/更新页；修复每处都成立，但口径没有单一来源，A2-01/02/06/07/08 都是这类漂移。
2. **失败/未知态仍是视图层 if 拼接**：缺少统一的「未知/缓存/失败/部分覆盖」状态枚举与渲染层，导致 0、旧值、安全绿、缓存文案、跳过承诺在边界路径互相打架。

## 5. 需实机验证清单

1. 断网启动 + 无缓存 / 有缓存两种刷新失败：横幅、统计卡「—」/0、副标题缓存文案是否一致。
2. 全部更新面板：N 与跳过数、确认后抽屉是否自动出现、锁定/进行中包是否真的没被升级。
3. brew doctor：正常、失败但有旧报告、退出码非 0 三种下健康卡与维护页结论是否一致。
4. 安全扫描：30 秒内是否有进展感、取消（首扫/有旧报告）、部分覆盖时分布条读感。
5. 发现页断网/brew search 故障/强制刷新失败：错误文案是否指向真实原因；行点击、↑↓/↵、VO 顺序。
6. 引导页：检测失败后下一步、路径输入 Enter、Esc 关闭后下次启动是否重复弹出（Esc 走 ContentView.swift:95-106，不写 onboardingCompleted，AppState.swift:2209-2212）。
