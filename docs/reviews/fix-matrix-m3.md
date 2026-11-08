# M3 修复矩阵（48 条 P2）

- 依据：`docs/reviews/ux-review-2026-11-05.md` §4（P2 清单，A-10..E-19）。
- 分组：M3-A reviewer-a（6）、M3-B reviewer-b（7）、M3-C reviewer-c（10）、M3-D reviewer-d（13）、M3-E Lead（10）。A-10 由 M1 批量确认覆盖，A-20 由 M2 D-04 覆盖，故实际新改 46 条，矩阵仍列全 48 行以便回归对照。
- 验证：全量 Debug 构建 `** BUILD SUCCEEDED **`（`build/m3-final-build.log`，EXIT 0，无编译错误）；`swift test --disable-sandbox` → 56 用例 / 53 通过 / 3 失败，失败均为已知 PTY `spawnFailed(1)`（`testMergedOutputAndExitCode`、`testTimeoutEscalatesAndFinishes`、`testTaskCancellationTerminatesChild`，AGENTS.md §8 环境限制，无新增失败；`build/m3-final-test.log`）。

## 1. 逐条矩阵

| ID | 条目 | 状态 | 落点（代表） |
| --- | --- | --- | --- |
| A-10 | 全部更新无确认 | 已完成（M1 P0-07 覆盖） | `BatchUpdateSheet` + `AppState.requestBatchUpdate` |
| A-11 | 覆盖率分母含 cask / 0 分母 | 已完成 | `AppState.vulnerabilityCoverageText`（formula 分母、cask 单列、跳过数）；`DashboardView.swift:344-360` |
| A-12 | LoadingBar 无 a11y / 无扫描进度 | 已完成 | `DashboardView.swift:267-322`（时间 + 已检查 X/Y、LoadingBar 移出 VO 树、取消可聚焦） |
| A-13 | 统计卡可点性不一致 | 已完成 | `DashboardView.swift:146-197,745` 四卡统一整卡可点 + help |
| A-14 | 健康卡不可操作 | 已完成 | `DashboardView.swift:551-743`（运行诊断、时间戳、复制摘要、展开修复命令、跳维护页） |
| A-15 | 引导页固定尺寸 / 步点 / 跳过 | 已完成 | `OnboardingView.swift:20-82`（可伸缩尺寸、第 N 步/共 5 步、跳过点击区） |
| A-16 | 路径输入 Enter 触发默认动作 | 已完成 | `OnboardingView.swift:189-191,300,320`（onSubmit → applyManualPath；聚焦时默认动作让位） |
| A-17 | 术语 刷新/检查更新/扫描混用 | 已完成 | `DashboardView.swift:41,88,109,123`、`OnboardingView.swift:232,236,253`（统一「检查更新 / 索引更新于 / 可更新项来自缓存」） |
| A-18 | brew 非可执行被报成未安装 | 已完成 | `BrewLocator.swift`（`.notExecutable(path)`）+ `BrewEnvironmentError.isNotExecutable` + 区分文案 |
| A-19 | 多个 brew 静默取首个 | 已完成 | `BrewLocator.discoverCandidates` / `AppState.brewCandidates` / 设置页单选记忆 |
| A-20 | 设置无效路径无内联错误 | 已完成（M2 D-04 覆盖） | `SettingsView` brewPathError 就地提示 |
| B-13 | 卸载面板未按 formula/cask 分组 | 已完成 | `Sheets.swift:162-223`（分组、依赖方列出、确认数=实际可卸载数） |
| B-14 | cask 无法锁定（禁用） | 已完成 | `PackageDetailView.swift:161,196-200,271-292`；`brew pin --cask` 于 7.0.12 实测支持，含 auto_updates 提示 |
| B-15 | 列表摘要与筛选不一致 | 已完成 | `InstalledView.swift:257,376`（显示 M/共 N + 空态清除筛选/去发现页） |
| B-16 | 行尾 ⋯ 菜单仅 hover 可见 | 已完成 | `InstalledView.swift:799`（常显、键盘可达） |
| B-17 | 「卸载它是安全的」过度承诺 | 已完成 | `PackageDetailView.swift:473,493`（改「本次快照未发现依赖方」+ 未装依赖 tooltip） |
| B-18 | 安装确认缺来源/版本/体积 | 已完成 | `Sheets.swift:329,339,379-384`（kind、来源、版本、体积、自动更新；未知则明说） |
| B-19 | 锁定确认缺 F5.1 风险说明 | 已完成 | `Sheets.swift:255`；`InstalledView.swift:556,562` 批量锁定/解锁 |
| C-08 | 检查更新无进度反馈 | 已完成 | `UpdatesView.swift:214-227`（spinner + 已用时长 + ≥10s 提示） |
| C-09 | 全选不含部分选中 / 越界 | 已完成 | `UpdatesView.swift:149`（三态 + ⌘A + accessibilityValue，仅当前筛选） |
| C-10 | 入队集合不明确 | 已完成 | `UpdatesView.swift:93,580`（将更新 N · 跳过 M 个锁定或已进入批次） |
| C-11 | 预览不可见 / 占用变更队列 | 已完成 | `AppState.previewUpgrade` 改只读；`UpdatesView.swift:145,286-350` 只读弹层；删除抽屉 dry-run 死代码 |
| C-12 | 自动检查不可见 | 已完成 | `AppState.lastAutoCheckAt` / `autoCheckUpdatesIfNeeded`；`UpdatesView` 页头「上次自动检查 X 前」 |
| C-13 | 截断日志无法拿全量 | 已完成 | `TaskQueueStore.swift:474`、`LogDrawerView.swift:386`（复制完整文件 + 打开日志） |
| C-14 | 取消后未启动行语义 | 已完成 | `TaskQueueStore.swift:782`、`LogDrawerView.swift:690`（已取消 / 未执行 + 圆点区分） |
| C-15 | 批次进度不含失败与计时 | 已完成 | `TaskQueueStore.swift:227`、`LogDrawerView.swift:254`（已处理 x/y · 完成 A · 失败 B、已用 m:ss、静默提示） |
| C-16 | 进度条缺 a11y；⌘. 重复注册 | 已完成 | `LogDrawerView.swift:297`；全仓仅抽屉注册 ⌘. |
| C-17 | 面板复用残留旧行 | 已完成 | `TaskQueueStore.swift:255`（新批次清行/复位计时） |
| C-18 | 「更新安全项」覆盖说明缺失 | 已完成 | `UpdatesView.swift:324`（只覆盖有可用版本的 N 个） |
| D-15 | 发现页分类浏览未实做 | 已完成 | `DiscoverView.swift`（快捷筛选 + help） |
| D-16 | 发现页错误态无下一步 | 已完成 | `DiscoverView.swift`（时间戳、重试、空态清除关键词+重试） |
| D-17 | 安装入队无行内状态 | 已完成 | `AppState.activeTask(for:kind:)` + `DiscoverView` 行内「排队中/安装中」 |
| D-18 | 通知授权状态不可见 | 已完成 | `SettingsView`（授权 banner、系统设置深链、denied 禁用开关） |
| D-19 | 维护页层级/统计缺失 | 已完成 | `MaintenanceView`（健康摘要、目录数量与统计时间、missing 跳详情） |
| D-20 | tap 信任无 UI | 已完成（只读工作台） | 高级 tap 信任区 + 复制 `brew trust`；`brew tap-info` 字段标注「需技术验证」 |
| D-21 | 三个抑制开关无 UI | 已完成 | `SettingsStore` + `BrewEnvironment` 注入 + 诊断可见 + 风险说明 |
| D-22 | 维护页小项合集 | 已完成 | ↑↓/↵ 选择、清理预览 detail、cask 解锁 |
| E-09 | 菜单项标题重复快捷键 | 已完成 | `MyApp.swift:52` 附近（去掉手写 ⌘N，由 keyboardShortcut 渲染） |
| E-10 | 无 ⌘, / 设置入口 | 已完成 | `MyApp.swift` `CommandGroup(replacing: .appSettings)` → 设置页 + 激活窗口 |
| E-11 | 打开详情时侧边栏无高亮 | 已完成 | `SidebarView.swift`（isActive 仅按分区 + 「详情」徽章） |
| E-12 | 状态卡不可点 / 状态栏无 help | 已完成 | `SidebarView.swift`（状态卡改 Button → 设置；任务日志按钮 help + a11y label） |
| E-13 | 外观只能循环切换 | 已完成 | `ContentView.swift`（Menu 三选一） |
| E-14 | toast 覆盖、时长过短、无历史 | 已完成 | `AppState` FIFO（错误 5s / 其他 2.8s）+ `toastQueueCount`；`ToastView` 失败「查看」+ 队列计数；`openLogDrawerFromToast` |
| E-15 | 不支持动态字体 / 焦点环 / 减少动效 | 部分完成（有意保留残余） | `AppTheme` 默认尺寸改文本样式；新增 `View.focusRing`；`LoadingBar`/`PulsingDot` reduce-motion。残余：45 处 9–13pt 徽章/图标旁文案保留固定 pt（按设计像素，已注释） |
| E-16 | 菜单栏 popover 忽略外观设置 | 已完成 | `MyApp.swift` MenuBarExtra 内容 `.preferredColorScheme(settings.appearance.colorScheme)` |
| E-17 | 多个 `.sheet` 同时挂载可能冲突 | 已完成 | `ContentView.swift:49-108` 收敛为单一 `.sheet(item: shellSheet)` + `ShellSheet` 优先级 |
| E-18 | 命令面板方向键可能被输入框吞掉 | 已完成 | `CommandPaletteView.swift` TextField 自身 `.onKeyPress(.upArrow/.downArrow/.return)` |
| E-19 | ⌘K 只能打开不能关闭 | 已完成 | `MyApp.swift` `showCommandPalette.toggle()` |

## 2. 附带收口（M2 遗留）

- `BatchSummarySheet`（`Sheets.swift:683-695`）新增消费 `summary.failedTaskCount`：聚合批次在开跑前失败、逐包行全为 skipped 时，不再显示成「失败 0」，而是「N 个任务失败，M 个包未执行」。

## 3. 文档同步

- `docs/ui-design.md` §14：补记动态字体（默认尺寸走文本样式）、2pt 焦点环、「设置…」⌘, 入口、检查更新/索引术语。
- `docs/product-plan.md`：F5.1 补 cask pin 实测支持与 auto_updates 例外；F4.7 与实现对齐（默认 24h、可关、离线静默失败、页头显示上次自动检查时间）。
- `docs/technical-notes.md` §2：补 `brew pin --cask` 实测、抑制类 `HOMEBREW_*` 环境变量注入、`brew tap-info` 字段待验证。

## 4. 需运行验证（未在本机启动 App）

1. 退出守卫（运行中任务 → 继续运行/停止并退出）与 10s 超时。
2. 更新预览弹层：长输出滚动、运行中取消时延、窄窗口宽度。
3. `MenuBarExtra` 自定义 label（mug+N）与 popover 主题跟随。
4. 依赖解析/`--dry-run` 真实输出与 C-11 文案一致性。
5. 批量升级逐包计数在真实 30+ 包场景下的表现。
6. 通知授权深链、系统级服务的 sudo 命令复制。
7. `brew bundle dump` 覆盖既有文件的 `--force` 需求（BrewClient 未改）。
8. 方向键/焦点环在详情页、更新页吸底栏的键盘走查。

## 5. 残留风险与口径

- **E-15 残余 45 处固定 pt 文本**：多为 9–13pt 徽章、图标旁标注与统计卡标签，按设计像素保留；正文、标题、卡片文案已走文本样式，放大字体时主体可读。若要全量动态字体，需连徽章尺寸一起重做，建议单独立项。
- **A-12 扫描进度**：`brew vulns` 不给逐包进度，`scanProgress.checked` 长时间停在 0，因此仅在 `checked > 0` 时显示 `X/Y`，其余时间只报已用时长（避免假进度）。
- **D-20 tap 信任**：`brew tap-info --json` 的信任字段在本机未确认，界面按只读说明 + 复制命令处理，未伪造数据。
- **聚合批次 cancelled 计数**（C 组转来）：仍按 record 计数；逐包取消语义由 C-14 的行级文案兜底。
- 所有改动未触及 Core 之外的安全约束：无 shell、无 sudo 代理、危险动作二次确认、漏洞文案保持「未发现 + 覆盖率 + 时间」。
