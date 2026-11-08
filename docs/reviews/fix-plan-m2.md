# M2 修复计划（40 条 P1）

> 依赖：M1（10 条 P0）合入并全量构建通过后开始。条目编号沿用 `docs/reviews/ux-review-2026-11-05.md`；
> 明细证据见 `docs/reviews/parts/{A,B,C,D,E-shell}.md` 对应编号。M1 合入后行号会漂移，**以编号和意图为准，动手前先重读目标代码**。

## 0. 通则（与 M1 相同，另加两条）

- 构建：每人用专属 derivedDataPath，宏沙箱标志必须带：
  ```bash
  xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData-<owner> \
    MODULE_CACHE_DIR="$PWD/build/modulecache-<owner>" \
    'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build
  ```
- 禁止：`swift test`（只由 Lead 跑）；变更类 brew 命令；`git` 写操作；改 `project.pbxproj` / `Package.swift`；引入依赖；大范围格式化。
- 文案：zh-Hans；状态词与危险动作词遵循 `docs/ui-design.md` §6；漏洞相关任何位置不写「无漏洞」，只写「本次扫描未发现」+ 覆盖率。
- **文件单一所有者**（见 §1）：只改自己名下的文件；需要别人文件的 API，按 §2 的理由在完成消息里提出，由 Lead 协调，不要越界修改。
- 新增交互必须同时给出：禁用原因（`.help`）、空态下一步、失败后的重试/复制入口；涉及按钮先行/后行的危险动作默认焦点在「取消」。
- 完成：`team_task_update complete` + `send_message lead`（改动文件 / 逐条修复 / build 结果 / 风险 / 未做项，≤300 字）。

## 1. M2 文件所有权

| 所有者 | 文件 |
| --- | --- |
| reviewer-a | `Brewbutler/UI/OnboardingView.swift`、`Brewbutler/UI/DashboardView.swift` |
| reviewer-b | `Brewbutler/UI/InstalledView.swift`、`Brewbutler/UI/PackageDetailView.swift`、`Brewbutler/UI/Sheets.swift` |
| reviewer-c | `Brewbutler/App/TaskQueueStore.swift`、`Brewbutler/App/TaskModels.swift`、`Brewbutler/UI/UpdatesView.swift`、`Brewbutler/UI/LogDrawerView.swift` |
| reviewer-d | `Brewbutler/App/AppState.swift`、`Brewbutler/App/SettingsStore.swift`、`Brewbutler/UI/SettingsView.swift`、`Brewbutler/UI/MaintenanceView.swift`、`Brewbutler/UI/ServicesView.swift`、`Brewbutler/UI/DiscoverView.swift`、`Brewbutler/UI/MenuBarView.swift`、`Brewbutler/MyApp.swift` |
| lead | `Brewbutler/ContentView.swift`、`Brewbutler/UI/CommandPaletteView.swift`、`Brewbutler/UI/SidebarView.swift` |

## 2. 分组与逐条要求

### M2-A（reviewer-a，7 条：A-05/A-07/A-08 + 配合项）

- **A-05** 首次安装指引：`OnboardingView` 未检测到 brew 的步骤给出「安装 Homebrew」段落——可点击打开 `https://brew.sh`（`Link`，http(s) 白名单内）、可复制的安装命令文本框、「安装后重新检测」按钮。文案不承诺自动安装。
- **A-08** 引导页扫描步骤：失败时显示原因 + 「重试」；成功/失败都允许「跳过」进入主界面；扫描进行中禁用「下一步」并有进度文字。
- **A-07** 最近任务行：点第 N 行必须打开第 N 条记录。依赖 reviewer-c 提供 `TaskQueueStore.openHistoryRecord(_ id: UUID)`（内部切换 `selectedRecordID` 并展示抽屉）；a 只改 `DashboardView` 行的 action 与选中态。未拿到 API 前不要用 `records.first` 兜底。
- 配合项（Lead 协调，不属 a）：A-03/A-04/A-06 由 Lead 在 `ContentView` 处理，a 不改 ContentView。

### M2-B（reviewer-b，9 条：B-04~B-12，B-10 由 c 负责状态层）

- **B-04** 选择集与筛选脱节：`InstalledView` 在筛选/搜索/刷新变化时按当前可见集合裁剪 `selectedIDs`；页头「已选 N 项」与实际可执行目标同源；批量按钮显示目标数，为 0 时禁用并说明。
- **B-05** 体积列空转：等 reviewer-d 提供 `AppState.packageDiskUsage` 逐包体积（后台、限量、可取消）后，列表体积列显示数字/「计算中」/「—（不可计算）」三态；按体积排序在有值时生效，无值时排在最后并 `.help` 说明。
- **B-06** 筛选补 tap / 「仅手动安装」/ keg-only 三个条件；cask 分段计数为 0 时不渲染该段。
- **B-07** 被依赖 chip 可点击跳转（`appState.selectPackage`）；依赖未安装时禁用「安装」并 `.help` 说明原因。
- **B-08** caveats 长文本折叠 + 「复制」按钮（含 a11y label）。
- **B-09** 路径行加复制按钮（保留可选中文本）；文件列表首项注明「仅显示前 500 项」。
- **B-11** 禁用控件补 `.help` 原因；只读模式下按钮文案改为「只读（原因）」而不是笼统禁用；`PackageDetailView` 禁用主按钮给出下一步。
- **B-12** 表格键盘导航（↑↓ 移动选中、Return 打开、Space 勾选）、表头可排序（点击列头切换 asc/desc 并显示指示）、VoiceOver 下复选框独立元素（去掉把整行合并的 `.combine`）。
- 顺带 **D-10**（cask 安装确认信息：版本/体积/auto_updates 若有）+ **D-13**（Brewfile 导入差异预览）：D-13 需要 reviewer-d 先提供 `AppState.brewfileImportPreview`（预计将安装/已安装/不支持的条目），拿到前先做 D-10。

### M2-C（reviewer-c，5 条：C-03/C-04/C-05/C-07 + 对外 API）

- **C-03** 取消当前任务不自动继续：批量任务被取消后，同批未开始的目标标记为 `cancelled`（不自动入队下一个包）；`UpdatesView`/抽屉文案写「已取消，剩余 N 个未执行，可重新选择」。
- **C-04** 队列实体化：`TaskQueueStore` 暴露只读 `pendingRecords: [TaskRecord]`（或等价）与 `removePending(id:)`；`LogDrawerView` 增加「排队中」区，每行可移除；更新页行内显示「排队中 · 第 N 位」。
- **C-05** 失败行可行动：`UpdatesView` 失败行展示退出码 + 首行错误 + `suggestion`，提供「查看日志」「复制命令」「重试」（重试走既有 enqueue，仍去重）。
- **C-07** 历史可回看：`TaskQueueStore.loadHistory()` 暴露历史列表；`LogDrawerView` 增加历史选择器（最近 N 条，含成功/失败/已中断），可打开任意历史记录、复制命令；重启后的 `interrupted` 记录给复查建议。
- 对外 API（a 需要，合入时一并完成）：`openHistoryRecord(_ id: UUID)`、`loadHistory()` 的返回类型、`selectedRecordID`。

### M2-D（reviewer-d，12 条：D-03~D-14 的状态/页面侧 + A-09 + E-04）

- **A-09** 扫描状态文案自洽：取消时区分「首次扫描已取消（无结果）」与「保留了上次结果」；扫描/刷新/检查更新三个词的副标题统一（扫描=漏洞，检查更新=outdated，刷新=索引）。
- **D-03** root 级服务：`AppState` 识别 `user == "root"`（或 plist 在 `/Library/LaunchDaemons`）的服务，标「系统级（需管理员权限，Brewbutler 不代理 sudo）」，禁用启停按钮 + `.help` + 可复制的等价命令；`ServicesView` 显示该状态。
- **D-04** brew 路径失败就地错误：`SettingsView` 路径字段下方 `InlineNotice`，不静默回滚，失败时保留用户输入。
- **D-05** 代理输入：URL 校验（http(s)、host 非空），非法值就地错误且不落盘；三个输入框配「应用」按钮（回车也能提交）；保存后提示是否重新检查更新。
- **D-06** 清理预览失败诚实化：预览解析失败/退出码非 0 时显示「预览失败」+ 原文折叠 + 「重试」，「执行清理」禁用。
- **D-07** doctor/missing：按退出码与输出判定，非 0 不得显示「未发现问题/检查通过」；展示原文（可复制）、分组，`missingError` 渲染，missing 行可跳转包详情。
- **D-08** kill 语义：`ServicesView` 运行中的服务给「停止进程（kill）」入口，复用危险确认、默认取消，文案说明与 `brew services stop` 的区别。
- **D-09** 服务日志入口：`AppState` 解析服务的 log/error_log 路径（plist），无则明确「未配置日志路径」；入口文案改「打开日志」，不再复制 plist。
- **D-11** 缓存过期：>24h 缓存不丢弃，显示「数据可能过期 · X 前」+ 强制刷新入口；离线横幅与过期提示不互相覆盖（可并列）。
- **D-12** Brewfile 导出失败可诊断：显示退出码/首行错误 + 「在 Finder 中显示」；成功后可「打开所在文件夹」。
- **D-13** Brewfile 导入预览（状态层）：提供 `brewfileImportPreview`（条目/已安装/不支持/重复），供 Sheets 呈现；执行后逐条结果。
- **D-14** 日志保留：按设置天数清理 `Library/Application Support/.../Logs` 下的旧日志（启动时 + 设置变更时），并显示「已清理 N 个文件」；设置项文案与实际行为一致。
- **E-04** 菜单栏可更新数：`MenuBarExtra` label 显示「mug + N」（有更新时），无更新时纯图标；数字来源与仪表盘同源；`MenuBarView` popover 保持现有摘要。
- 对外 API（b/a 需要）：`packageDiskUsage`、`brewfileImportPreview` 的最终签名。

### M2-E（lead，5 条：E-05/E-06/E-07/E-08 + A-03/A-04/A-06）

- **A-03** 探测中：`ContentView.detailColumn` 在 `isLocatingBrew` 时显示骨架/「正在检测 Homebrew…」而不是 0 值仪表盘。
- **A-04** brew 缺失不再是死路：允许 `.settings` 分区在无 installation 时渲染设置页（设置页需能在 nil 下渲染，由 d 保证）；侧边栏底部的 Homebrew 状态卡可点击进入设置；`BrewMissingView` 的「打开设置」保留。
- **A-06** 能力降级横幅：`ContentView` 顶部（或详情列顶部）在只读/缺少能力时显示窄横幅，说明「本次启动为只读：brew 不可写 / 版本过旧……」，可展开详情、可关闭（本次会话）。
- **E-05** 命令面板空查询：显示「最近任务」（来自 c 的 `records`，最多 5）与「推荐动作」；任务项可直达日志。
- **E-06** 把「清理缓存…」「运行 brew doctor」两个动作提升为真正的全局命令（`MyApp` AppCommands，保留面板里的行），并移除维护页里重复注册的快捷键（由 d 在 `MaintenanceView` 删，Lead 与 d 对齐后再删）。
- **E-07** 包结果上限：`.prefix(10)` 时在结果组尾显示「共 N 个结果 · 在发现页查看全部」，可回车跳转到发现页并带上查询词。
- **E-08** 快捷键去重与语义：⌘R 只保留「检查更新」全局一条（移除 Dashboard/Services 页局部注册，页面刷新改为按钮）；⌘⇧V 只保留全局安全扫描；⌘A/⌘⌫ 仅在表格（非输入框）聚焦时生效（b 在 InstalledView 用 `focus` 判断，Lead 记录规则）。
- 顺带 P2 中与外壳强相关的 E-10（⌘, 打开设置）、E-11（详情态侧边栏高亮）、E-13（外观改为菜单）、E-19（⌘K 改为 toggle）：M3 处理，此处只确保不冲突。

## 3. 跨组契约（动手前 Lead 确认，签名以最终代码为准）

| 提供方 | API | 消费方 |
| --- | --- | --- |
| c | `TaskQueueStore.pendingRecords`、`removePending(id:)`、`openHistoryRecord(_:)`、`loadHistory()` | lead（面板最近任务）、a（Dashboard 行）、b（无） |
| d | `AppState.packageDiskUsage`（逐包体积，后台计算，三态） | b（体积列/排序） |
| d | `AppState.brewfileImportPreview`（条目/已安装/不支持/重复） | b（Sheets 差异预览） |
| d | `AppState.capabilityNotice`（只读/降级原因文本，可空） | lead（A-06 横幅） |
| d | 服务根级判定 `isSystemLevelService`、服务日志路径 | d 自用（ServicesView） |

契约变更必须同时更新本文件 §3；某一方先落地则 send_message 通知对方，勿等完成时才发现签名不符。

## 4. 验收与产出

- 每个任务：专属构建通过 + 逐条修复说明；不新增编译警告更好。
- Lead 在四组全部完成后：main DerivedData 全量构建 + `swift test --disable-sandbox`；逐条对照报告 §3 核验；产出 `docs/reviews/fix-matrix-m2.md`（40 行：ID / 状态 / 改动文件 / 验证方式 / 未完成原因）；更新 `ux-review-2026-11-05.md` 中对应条目状态。
- 若某条在当前架构下无法安全实现（如需要新 brew 能力），标「需技术验证/延期到 M3」并在矩阵里写明，不允许静默跳过。
