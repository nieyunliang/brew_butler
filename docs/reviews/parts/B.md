# 簇 B：已安装、包详情与安装/卸载/锁定

## 0. 结论

1. **危险动作的骨架是对的，关键闸门是空的。** 二次确认、默认焦点在取消、zap 需输入包名、sudo 只给指引都实现了（`Brewbutler/UI/Sheets.swift:5-41`、`:58`、`:151-155`），但「被 N 个包依赖仍可直接确认卸载」和「zap 风险只写一句泛化警告」两处直接撞上 PRD F3.3/F3.4 与流程 4 的硬约束。
2. **安全信息诚实度是全项目最强的部分**，但被跳过的 formula 仍显示「本次扫描未发现该包的漏洞记录」，与同页「跳过 N 个包不在映射范围」自相矛盾——用户会把「未覆盖」读成「已检查且安全」。
3. **已安装列表的选择模型与筛选/刷新不同步**：批量栏计数取 `selection.count`，执行目标取当前可见 `packages`，用户可看到「已选 5 项」却打开「卸载 0 个包？」的确认面板。
4. **体积维度整体空转**：`diskUsageBytes` 全仓无赋值点，列表体积恒「—」、按体积排序恒等；F1.3/F2.5 作为 P0 验收在当前构建里不可用。
5. **键盘与 VoiceOver 明显落后于 ui-design §4.2/§7**：表格无行导航、表头不可排序、复选框被 `.combine` 吞掉、行 hint 声称回车可打开但无焦点承载；锁定/卸载等行内操作只藏在右键菜单。

## 1. 功能覆盖核对表

| ID | 状态 | 证据 | 一句话交互问题 |
| --- | --- | --- | --- |
| F1.2 | 部分实现 | `InstalledView.swift:99-107`、`AppState.swift:1526-1545` | 缺 tap / 仅手动安装 / keg-only 三种 PRD 筛选；0 cask 时仍显示 cask 分段；筛选是单选、无法组合。 |
| F1.3 | 部分实现 | `InstalledView.swift:113-121`、`:341`；`AppState.swift:1556-1562` | 排序可切换但无勾选/方向反馈；体积列恒「—」，按体积排序无效果且无「计算中」占位。 |
| F1.4 | 部分实现 | `InstalledView.swift:208-245`、`:251-256`；`Sheets.swift:99-132` | 多选可用，但计数与执行目标脱节；批量卸载不校验依赖；批量更新逐包入队，与 F1.4 验收「单条任务」不符（又与 F4.3「逐个入队」冲突，需产品定稿）。 |
| F1.5 | 部分实现 | `InstalledView.swift:111`、`:140-148`、`:249-252` | ⌘F 聚焦、即时过滤、清除筛选均可用；空态只提到发现页，没有「在发现页搜索」按钮。 |
| F2.1 | 已实现 | `PackageDetailView.swift:20-26`、`:76-123`、`:231-252` | 缺失字段用「—」，废弃/禁用横幅置于头部；层级清晰，无需改动。 |
| F2.2 | 部分实现 | `PackageDetailView.swift:374-438` | 依赖可跳转（已安装时）；被依赖 chip 纯展示不可跳转；未安装依赖禁用无提示；卸载不因反向依赖阻断（见 B-01）。 |
| F2.3 | 部分实现 | `PackageDetailView.swift:254-262` | caveats 保留换行、可选中，但无一键复制、长文本不折叠。 |
| F2.4 | 部分实现 | `PackageDetailView.swift:148-151`、`:576-589`、`:463-476` | 路径可查不可复制；keg-only 未解释 opt 路径差异；文件列表前 500 项非虚拟滚动。 |
| F2.5 | 部分实现 | `PackageDetailView.swift:108-112`、`:543-551`；`AppState.swift:687-705`、`:733-738` | 详情能显示体积；权限不足/路径不存在时静默省略而非「不可计算」；无 24h 缓存与口径说明。 |
| F2.6 | 部分实现 | `PackageDetailView.swift:125-172`、`:591-606` | 锁定/卸载/主页/复制安装命令齐备；复制路径缺失；禁用态普遍无原因。 |
| F3.1 | 已实现 | `AppState.swift:818-843`；`DiscoverView.swift:178-199` | formula 直接入队，有实时日志与取消；发现页已安装后按钮变「详情」。 |
| F3.2 | 部分实现 | `Sheets.swift:136-174`、`:62-88` | cask 安装前有 sudo 指引；cask 卸载/zap 需授权时无同类指引，失败后也只有一句话 toast。 |
| F3.3 | 缺失 | `Sheets.swift:58`、`:63-68`；`PackageDetailView.swift:600-604` | 被依赖时只加一句 warning，确认按钮照常可用，主流程未阻断（见 B-01）。 |
| F3.4 | 部分实现 | `Sheets.swift:75-87`、`:58`、`:70` | 独立开关、输入包名、默认取消齐备；风险未列「共享文件/登录项」，无待删路径、体积、是否移除本体。 |
| F5.1 | 部分实现 | `InstalledView.swift:202-203`；`PackageDetailView.swift:141-146`、`:530-533`；`AppState.swift:1111-1127` | cask 一律禁用锁定且无解释；pin 前无「依赖其新版本的其他包」风险提示；批量跳过计数已做（`AppState.swift:1001-1025`）。 |
| F5.2 | 已实现 | `AppState.swift:1111-1127`；`UpdatesView.swift:500-501`；`Sheets.swift:354-359` | 解锁后可再次更新；更新页与批量汇总解释了跳过原因。 |

## 2. 发现清单

### [B-01] P0｜被依赖的包仍可直接确认卸载，主操作未阻断
**证据**：`Brewbutler/UI/Sheets.swift:58` 的 `isConfirmEnabled` 只校验 zap 输入，不检查 `dependents`；`:63-68` 仅渲染 warning；`Brewbutler/UI/PackageDetailView.swift:163-164`、`:600-604` 的卸载入口不因反向依赖禁用；`Brewbutler/UI/InstalledView.swift:205` 行右键同样；`Sheets.swift:108-110` 批量面板逐包直接执行。
**场景**：谨慎用户③想删掉一个「看着没用」的库，打开详情发现被 10 个包依赖，但「卸载…」按钮仍是可点的 Danger 按钮，回车默认取消之外确认即执行。
**现状**：反向依赖只以黄色小字提示，不阻断、不要求额外确认、无「先看依赖方」路径；批量面板连逐包依赖都不列。
**期望**：PRD F3.3/§7.9 明确「被依赖时先展示反向依赖并禁用主按钮」；ui-design §4.12「标题即后果」、§5 ConfirmDialog 显示卸载影响。
**建议**：`UninstallSheet` 在 `dependents` 非空时禁用确认，改为「查看被依赖（N）→」跳转被依赖 tab；批量面板先筛出有依赖的包并单独分组，默认排除。

### [B-02] P0｜删除关联文件的强确认没有列出共享文件、偏好、登录项与待删内容
**证据**：`Brewbutler/UI/Sheets.swift:79-82` 全文只有「会一并移除应用数据、偏好设置等，不可恢复。输入包名…以确认」；`:70` 只预览 `brew uninstall` 命令，无体积/本体/路径；`:83-85` 输入框无拼写辅助或包名高亮。
**场景**：P3 用户②想「删干净」一个 cask，勾选「同时删除关联文件」后只能凭想象判断会删什么；偏好与登录项里有共享数据时无从得知。
**现状**：缺少流程 4 要求的「体积、是否移除应用本体」与「共享文件、偏好、登录项」三类风险；也不提示 zap 可能触发系统授权。
**期望**：PRD F3.4 + §8 流程 4 第 2/3 步、ui-design §4.12；HIG 要求破坏性确认说明具体损失。
**建议**：勾选后展开明细区：应用本体路径 + 体积（可从 `detail.sizeBytes` 取）、三类风险清单；`brew uninstall --zap --dry-run` 若不可用则给出命令复制；界面文案继续用「删除关联文件」，不展示 `--zap` 参数串（ui-design §6）。

### [B-03] P0｜被跳过的 formula 仍显示「本次扫描未发现该包的漏洞记录」
**证据**：`Brewbutler/UI/PackageDetailView.swift:342-350` 的 `noFindingText` 只区分 cask 与「report 存在」，formula 一律返回「未发现」；同一视图 `:359-361` 却列出 `report.skippedFormulae` 数量；inspector `:566` 同样文案。
**场景**：谨慎用户③看一个不在 OSV 映射里的 formula，看到「本次扫描未发现该包的漏洞记录」，据此认为已检查且安全。
**现状**：「未覆盖」被写成「已检查无发现」，与同页覆盖率/跳过数矛盾，违反 AGENTS 硬约束「漏洞语义诚实」与 PRD F11。
**期望**：AGENTS §5.8、PRD F11「任何位置不写无漏洞，只写本次扫描未发现 + 覆盖率」。
**建议**：`noFindingText` 增加 `report.skippedFormulae.contains(package.name)` 分支返回「该包不在 brew vulns 的 OSV 映射范围，本次未覆盖」并附覆盖率；同步 inspector 健康区。

### [B-04] P1｜选择集与当前筛选脱节：计数与实际操作目标可差很多，甚至出现「卸载 0 个包？」
**证据**：`Brewbutler/UI/InstalledView.swift:13` 选择集只增不减；`:220` 显示 `selection.count`，而 `:228`、`:234`、`:268` 的目标是 `packages.filter { selection.contains }`（仅当前筛选结果）；`packages` 由筛选/搜索派生（`:17-19`），筛选变化和刷新后无任何清理；`:227-230` 的卸载按钮无 0 项守卫。
**场景**：P1 用户①勾选 5 个旧 formula，再点「已锁定」筛选，批量栏仍说「已选 5 项」，点「卸载…」得到「卸载 0 个包？」；或包被刷新移除后选择集仍保留其 id。
**现状**：计数、文案、执行目标三处不一致；「卸载 0 个包」确认面板可确认并关闭，用户会以为操作已完成。
**期望**：HIG/§4.2 批量操作必须明确作用于哪些对象；PRD F1.4 要求选择集生成可靠任务。
**建议**：`onChange(of: filter/query/packages)` 时清理失效 id；批量栏改为「已选 N 项（当前可见 M 项）」或直接按 `targets.count` 显示；目标为空时禁用按钮并给 tooltip；筛选时提供「全选当前结果」提示。

### [B-05] P1｜体积列恒为「—」、按体积排序无效果
**证据**：`Brewbutler/UI/InstalledView.swift:341` 读 `package.diskUsageBytes`；`Brewbutler/Core/Models/PackageSnapshot.swift:41` 声明该字段，但 `:265-289`（formula）与 `:322-338`（cask）构造均未传该参数；`Brewbutler/App/AppState.swift:1560` 排序按 `(diskUsageBytes ?? -1)`，因此全部相等；`:687-705` 的 `computeDiskUsage` 只算三个根目录总量，不回写 per-package。
**场景**：用户想找「占空间最大」的包批量清理，看到整列「—」，切到按体积排序列表毫无变化，也没有任何提示说数据不可用。
**现状**：F1.3（P1）与 F2.5（P0）的体积口径在列表页完全未实现；详情页体积依赖 `loadDetail` 单包 du（`:733-738`）。
**期望**：PRD F1.3「体积未算完显示占位并可触发后台计算」、F2.5 验收。
**建议**：后台按 keg 路径并发 du 并写回快照（带缓存与代际号）；列表显示「计算中…/不可计算」而非「—」；排序在无数据时禁用并说明；口径（du vs 安装清单）写进列 title/help。

### [B-06] P1｜筛选缺 tap / 仅手动安装 / keg-only，cask 分段不按 PRD 隐藏
**证据**：`Brewbutler/UI/InstalledView.swift:99-107` 只有 全部/formula/cask/可更新/已锁定/有已知漏洞；`Brewbutler/App/AppState.swift:1541-1544` 已实现 `.manual`、`.kegOnly` 但 UI 无入口；`InstalledView.swift:101` 无条件渲染 cask chip。
**场景**：P1 用户①只想批量卸载「自己手动装的」旧 formula（排除依赖带入），或按 tap 定位某第三方 tap 的包；当前只能肉眼翻列表。
**现状**：enum 能力闲置；tap 维度完全缺失；按 PRD 应「无 cask 时隐藏 cask 分段」（本机基线 0 cask，仍显示 0）。
**期望**：PRD F1.2（P0）逐项列出六类筛选并明确隐藏规则；ui-design §4.2 筛选行。
**建议**：筛选行加「手动安装」「keg-only」「更多筛选 ▾（tap 列表）」，`count == 0` 时隐藏对应 chip；保持单选互斥并在 PRD 中确认是否需要组合筛选。

### [B-07] P1｜被依赖 tab 不可跳转，依赖行的「未安装」禁用无提示
**证据**：`Brewbutler/UI/PackageDetailView.swift:430-434` 用 `ValueChip`（纯展示，`Brewbutler/Design/Components.swift:413`）渲染 dependents，无 Button；`:393-416` 依赖行仅 `installed != nil` 时可点，`:406` `.disabled(installed == nil)` 无 tooltip/help。
**场景**：谨慎用户③在卸载前想点开依赖方看它是否还在使用，或想从被依赖列表跳到对方详情——点不动；看到灰色依赖名也不知道为什么点不了。
**现状**：F2.2「可读可跳转」只完成一半；ui-design §5 DependencyList 的卸载影响有了，跳转没有。
**期望**：PRD F2.2（P0）「依赖与被依赖可读、可跳转，未安装标『未安装』」；ui-design §5 Don't 明确禁止「裸依赖名不给状态」。
**建议**：dependents chip 改 Button → `appState.selectPackage`；未安装依赖行加 `.help("该依赖未安装")` 并提供「安装」次级操作；被依赖 tab 顶部 InlineNotice 增加「查看依赖方」滚动定位。

### [B-08] P1｜caveats 无复制按钮，长文本不折叠
**证据**：`Brewbutler/UI/PackageDetailView.swift:254-262` 仅 `Text(caveats).textSelection(.enabled).fixedSize(...)`，SectionCard 无 header 动作。
**场景**：P3 用户②装完 cask 后要按 caveats 里的步骤配置（常含多行命令），只能手动选中复制整段，遇到超长 caveats 会占满整屏。
**现状**：F2.3 两个验收点（一键复制、长文本折叠）都缺；与同类文本（安装命令 `:264-270`、路径 `:576-589`）的处理不一致。
**期望**：PRD F2.3（P0）；ui-design §4.5 概览信息层级。
**建议**：SectionCard 标题行加「复制」按钮复用 `copy(_:)`（`:505-508`）；超过 6~8 行用 DisclosureGroup「展开全部」，默认保留原文换行。

### [B-09] P1｜路径没有复制入口，复制后也无反馈
**证据**：`Brewbutler/UI/PackageDetailView.swift:148-151` 只有「目录」按钮；`:576-589` inspector 路径为可选文本 +「在 Finder 中显示」；`:505-508` 已有统一 `copy()` + toast，但未用于路径。
**场景**：用户要粘贴安装路径到终端排查，只能手动选中一段 mono 文本；键盘用户更无从触发。
**现状**：F2.4 验收「点击复制路径」未实现；F2.6 快捷操作列表里也缺复制路径。
**期望**：PRD F2.4/F2.6；ui-design §4.5 快捷键 ⌘⇧C 归属复制安装命令，路径可给独立按钮。
**建议**：路径 section 增加「复制路径」按钮（复用 `copy(path)` → toast「已复制」）；路径加载中给占位/骨架，避免「目录」按钮延迟出现造成布局跳动（`:148-151`）。

### [B-10] P1｜卸载失败只有一句 toast，没有残留路径、退出码与下一步
**证据**：`Brewbutler/App/AppState.swift:1219-1250` 的 `handleTaskFinished` 失败分支仅 `showToast("\(record.title)失败：\(record.message ?? "查看日志")", kind: .failure)`（`:1226`）；`Brewbutler/UI/Sheets.swift:92-94` 确认后关闭面板，无后续承载。
**场景**：谨慎用户③卸载一个 cask 失败（文件被占用/权限不足），2.8 秒后 toast 消失，不知道哪些文件残留、该用哪条命令手动清理。
**现状**：PRD 流程 4 的异常支线要求「展示残留路径与手动清理建议」，ui-design §4.12 要求抽屉失败追加退出码与诊断建议；当前只在日志抽屉里有原始输出，无「残留/下一步」结论。
**期望**：PRD §8 流程 4、F4.5 失败语义；ui-design §4.12。
**建议**：失败记录在包详情/日志抽屉增加结构化区块：退出码、firstErrorLine、可能的残留路径（`detail.path` 是否仍存在）、「复制清理命令」；toast 增加「查看详情」动作而不是纯消失。

### [B-11] P1｜禁用控件普遍没有原因；只读模式与 cask 锁定的提示还误导
**证据**：`InstalledView.swift:203`（cask 锁定禁用无 help）、`:232`、`:239`（只读禁用无说明）、`:205`（只读时右键「卸载…」却没禁用）；`PackageDetailView.swift:130-131`（readOnly 禁用时 help 仍写「⌘U」）、`:145`、`:218`、`:528`、`:533`、`:535`、`:604`；只读原因由 `AppState.swift:801-804` 的 enqueue toast 兜底，但按钮本身不解释。
**场景**：键盘用户④在旧版 brew（只读模式）下反复点更新，按钮灰着、hover 提示「⌘U」，按 ⌘U 也无反应；cask 用户看到锁图标位置是灰按钮，不知道 brew 是否支持 cask pin。
**现状**：同一能力在不同入口的禁用条件不一致（右键卸载未禁用 vs 批量栏禁用），用户无法从 UI 学到规则。
**期望**：HIG 禁用控件应可发现原因；ui-design §7 全部功能键盘可达。
**建议**：统一注入 `.help(reason)`：`isReadOnly → "Homebrew 版本过低，当前为只读模式"`，cask 锁定 → `"锁定仅支持 formula"`（若技术验证不支持 cask）；只读模式在页头加一条 InlineNotice；右键菜单同样 `.disabled(isReadOnly)`。

### [B-12] P1｜表格没有键盘导航，表头不可排序，VoiceOver 复选框被合并
**证据**：`InstalledView.swift:171-193` 表头是静态 `Text`，仅整体 `.accessibilityAddTraits(.isHeader)`，无排序按钮；`:155-166` 行无 `.focusable`/`.onMoveCommand`/`.onKeyPress`；`:359-361` 行 `.accessibilityElement(children: .combine)` 会把 `:291-297` 的复选框并入行标签；`:249-261` 只有 ⌘⌫ 批量卸载，无 Delete 单行卸载、无 ⌘⇧U。
**场景**：键盘用户④想用 ↑↓ 移动、Enter 打开、Delete 卸载，实际只能用 Tab 逐个走按钮；VoiceOver 读行时无法单独勾选。
**现状**：行 hint「按下回车打开详情」没有焦点承载，属于声明与行为不一致；排序只能通过菜单。
**期望**：ui-design §4.2（aria-sort、复选框独立 aria-label、行 tabindex+Enter）、§7（↑↓/↵/Esc、⌘⇧U、Delete）。
**建议**：行容器 `.focusable()` + `.onMoveCommand` 移动选择/打开；表头列改为 Button 切换排序并暴露 `.accessibilityValue` 方向；复选框移出 combine 或给行 `.accessibilityAction`；补齐 Delete = 卸载当前行、⌘⇧U = 更新所选。

### [B-13] P2｜批量卸载面板信息不足，混合类型与依赖风险不可见
**证据**：`Sheets.swift:104-106` 标题只给数量；`:108-110` 逐包 `performUninstall(..., zap:false)`；`:116-124` 仅列前 12 个名字；`:126-128` 一句泛化警告；无类型分组、无逐包依赖标记、无 zap 选项。
**场景**：用户①混选 formula + cask 一起卸载，面板里看不出哪些是 cask（本该单独走 zap 决策）、哪些会破坏依赖方。
**现状**：PRD F1.4 要求混合类型「拆两个任务并提示」，当前混在一个面板里无提示；危险包与安全包视觉同权。
**期望**：PRD F1.4、ui-design §5 ConfirmDialog「标题即后果」。
**建议**：按 kind 分组并给出「其中 3 个 cask 将只卸载本体，不删除关联文件」；把有反向依赖的包单列并默认不勾选；允许为 cask 组选择 zap（组内逐包输入包名过重，可退化为组级开关 + 命令预览）。

### [B-14] P2｜cask 的锁定能力被 UI 全面禁用且无解释，与 PRD/状态层不一致
**证据**：`InstalledView.swift:202-203`、`PackageDetailView.swift:145`、`:530-533` 均 `disabled(package.kind == .cask)`；而 `AppState.swift:1111-1127` 的 `setPinned` 已按 kind 传 `--cask`，PRD F5.1 也写 `brew pin --formula/--cask`，且模型层 `PackageSnapshot.swift:338` 已映射 `cask.pinned`，说明并非模型不支持；`technical-notes.md:56` 未记录 cask pin 限制。
**场景**：cask 用户想阻止某个 auto-updates 应用被批量更新，找不到锁定入口，也没有说明为什么不能锁。
**现状**：能力要么未实现（UI 层），要么已实现（状态层）却不可达；`technical-notes.md:56` 未记录 cask pin 的限制，无法据此判断。
**期望**：PRD F5.1；能力不确定时应在 UI 给出「当前版本 brew 不支持锁定 cask」而不是静默禁用。
**建议**：先实测 `brew pin --cask` 行为（见 §4）；支持则放开并补 cask pinned 映射，不支持则在三处加 `.help("brew 当前版本不支持锁定 cask")` 并同步 technical-notes/PRD。

### [B-15] P2｜空态「在发现页搜索」没有入口，摘要不随筛选更新
**证据**：`InstalledView.swift:140-148` 空态正文提到发现页，但只有「清除筛选」一个按钮；`:87-93` `summaryText` 永远基于 `index` 全量计数；`:58` 摘要与列表内容可完全不同。
**场景**：用户搜「rust」没结果，读完提示还得自己找侧边栏去发现页；筛选到「已锁定」后页头仍写「59 个包」。
**现状**：F1.5 空态入口验收未落地；摘要与列表脱节，属于信息误导级的小问题。
**期望**：PRD F1.5、ui-design §5 EmptyState「一句为什么 + 一个下一步」。
**建议**：空态加第二个按钮「在发现页搜索」→ `appState.section = .discover`（并预填 query）；摘要改为「显示 M / 共 N 个包」或仅在 `filter == .all && query.isEmpty` 时显示全量。

### [B-16] P2｜行内操作不可发现：锁定/卸载/更新全在右键菜单
**证据**：`InstalledView.swift:196-206` 是唯一承载行级更新/锁定/卸载的地方；`PackageRowView`（`:281-362`）除复选框（`:291-297`）与整行点击外没有行级动作或 ⋯ 菜单；行 hover 只有背景变化（`:357-358`）。
**场景**：用户①想快速锁定或卸载某行，不知道要右键；ui-design §4.2 的「行内操作不误触」被理解成彻底隐藏。
**现状**：右键菜单在触控板/Magic Mouse 之外不可发现；键盘用户也没有入口。
**期望**：ui-design §4.2 行内操作、§7 键盘可达。
**建议**：行尾 hover 时显示 ⋯ 菜单（与详情页 Menu 一致），或提供行内「卸载」次级按钮；右键菜单保留作为快捷路径。

### [B-17] P2｜「卸载它是安全的」是绝对承诺，且未安装依赖禁用无 tooltip
**证据**：`PackageDetailView.swift:421` 空态文案「没有其他包依赖该包，卸载它是安全的。」；反向依赖只覆盖已安装 formula 的 runtime deps（`PackageSnapshot.swift:409-415`）；未安装依赖行 `.disabled(installed == nil)`（`:406`）无说明。
**场景**：用户③看到「卸载它是安全的」就直接卸载；实际上 brew 仍可能因未记录的 build 依赖、服务的引用或同名 cask 冲突而失败/留下残留。
**现状**：结论强于数据（反向依赖仅来自本地快照），与 AGENTS「结论可追溯」精神不符。
**期望**：ui-design §6 文案要求后果具体而非保证；PRD F2.2 只要求「展示影响」。
**建议**：改为「当前已安装的包中没有依赖它的记录；卸载后仍可能影响未安装/外部工具」；未安装依赖行加 help「未安装，无法跳转」并给「安装」动作。

### [B-18] P2｜cask 安装确认信息太少，且命令字符串硬编码
**证据**：`Sheets.swift:142-149` 只显示包名和 `"brew install --cask \(target.name)"`；`:151-155` 仅 sudo 指引；无版本、体积、来源 tap、是否 auto_updates。
**场景**：两个同名 formula/cask 或第三方 tap 覆盖 homebrew/core 时，用户在确认页无法核对装的是哪个来源。
**现状**：F3.2 的 sudo 指引达标，但流程 2 的「安装前预览」完全依赖发现页 inspector（`DiscoverView`），确认页本身没有信息量；`:146` 字符串拼接与 `AppState.swift:834` 的命令构造重复，未来改参易漂移。
**期望**：PRD §8 流程 2、ui-design §4.12「标题即后果」。
**建议**：确认页展示发现结果里的 `version/tap/auto_updates` 与来源 URL；命令文本复用 `ChangeTask.commandText` 而不是手写。

### [B-19] P2｜锁定前没有 F5.1 风险提示，也无法批量锁定
**证据**：`PackageDetailView.swift:141-146`、`InstalledView.swift:202-206`、`:530-533` 点击即 `setPinned`；无确认、无风险文案；批量栏（`:218-245`）只有卸载/更新。
**场景**：用户④批量选中若干包想一起锁定，无法操作；单包锁定时也不清楚锁定会让依赖新版本的包装不上。
**现状**：PRD F5.1 要求 pin 时提示「依赖该包新版本的其他包可能无法安装或运行」；批量更新跳过计数已实现（`AppState.swift:1001-1025`、`Sheets.swift:354-359`），但入口侧提示缺失。
**期望**：PRD F5.1（P0）。
**建议**：首次锁定时 toast/Inspect 说明该影响（可用 `settings` 记住不再提示）；批量栏增加「锁定 / 解锁」次级操作，复用 `setPinned` 并显示进度。

## 3. 做得好的地方

- **危险确认的统一容器**：`ConfirmSheetLayout` 强制「标题即后果 + 取消为 defaultAction + 危险样式确认键」（`Sheets.swift:5-41`），与 ui-design §4.12 和 HIG 一致，所有 sheet 自动继承。
- **zap 双门槛**：仅 cask 出现开关、勾选后必须逐字输入包名才启用确认键（`Sheets.swift:58`、`:75-87`），取消不发命令。
- **安全信息不美化**：覆盖率、`checked/total`、部分覆盖、退出码 1 的预期解释、skipped 数量都在（`PackageDetailView.swift:352-372`），cask 明确写「不在 OSV 映射范围，无法判断」（`:344-346`），是全项目最诚实的部分。
- **依赖行的状态可见性**：已安装/未安装 badge、版本号、已安装才可点（`PackageDetailView.swift:393-416`），被依赖 tab 有 warning 前置（`:418-438`），方向正确。
- **跳过原因的可追溯**：批量汇总区分成功/失败/取消/未确认/跳过并解释「可能已锁定或为 auto_updates」（`Sheets.swift:346-359`），更新页按钮禁用也带 `.help`（`UpdatesView.swift:500-501`）。

## 4. 需运行验证清单

1. `brew pin --cask` 在 Homebrew 7.0.10 的可用性与退出码（只读实测 `brew pin --help` + `brew info --json` 字段），决定 B-14 是能力缺口还是 UI 缺口。
2. 存在反向依赖时 `brew uninstall` 的真实行为：是否直接拒绝、退出码与首行错误，决定 B-01 阻断文案是否还需要「仍要卸载」路径。
3. `brew uninstall --cask --zap` 是否输出待删路径/共享文件/登录项；能否在确认页预览（B-02 建议可行性）。
4. 表格行按 Enter 是否真的打开详情、VoiceOver 下 `.combine` 后复选框能否独立操作（B-12 的 hint 与 a11y 声明）。
5. 体积排序是否在任何刷新路径下仍全为 -1（静态检查无赋值点；确认无遗漏的派生写入，B-05）。
6. 筛选/刷新后残留选择集的实际表现（复现 B-04 的「卸载 0 个包」）。
7. zap 卸载时 brew 是否弹出系统授权（cask 常见），确认没有绕过「不代理 sudo」。
8. 详情页「目录」按钮在 `detail.path` 加载前后是否造成 header 布局跳动（B-09）。

## 5. 评审方法与限制

- 方法：逐行阅读 `Brewbutler/UI/InstalledView.swift`（395 行）、`PackageDetailView.swift`（644 行）、`Sheets.swift`（426 行）、`AppState.swift` 的详情/任务/筛选/结果处理段、`PackageSnapshot.swift` 构建与反向依赖段、`Components.swift` 相关组件，并对照 `DiscoverView`/`UpdatesView`/`ContentView` 的调用点。
- 文档对照：`docs/product-plan.md` §7.3、§7.4、§8 流程 2/4、§7.9 P0 验收；`docs/ui-design.md` §4.2、§4.5、§4.12、§5、§6、§7；`docs/technical-notes.md` 的 brew 能力矩阵与 pin 记录。
- 限制：只读评审，未运行 App、未执行 `xcodebuild`、未执行任何变更类 brew 命令；所有结论基于当前工作树源码，行号以本次阅读为准。涉及真实 brew 行为与运行时交互的点已列入 §4，未臆造能力。
- 文档与代码冲突已显式记录（F1.4「单条任务」vs F4.3「逐个入队」；F5.1 cask pin；technical-notes 未记录 cask pin 限制），未在报告中替产品做单一裁决。
