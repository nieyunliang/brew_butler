# M2 修复矩阵（40 条 P1）

> 对应报告：`docs/reviews/ux-review-2026-11-05.md` §3（40 条 P1）。
> 计划：`docs/reviews/fix-plan-m2.md`。执行：reviewer-a/b/c/d 四组并行，Lead 负责外壳（M2-E）与最终验收。
> 验收环境：2026-11-06，本机 macOS 27 / Xcode 27，`swift test` 56 用例（3 个已知 PTY 沙箱失败）。
> 状态口径：已修复＝代码落地 + 全量构建通过；部分＝主要路径已改、边界或运行验证未做；延期＝不在 M2 范围（写明去处）。

## 1. 矩阵

| ID | 条目（简） | 状态 | 改动文件（代表位置） | 验证 |
| --- | --- | --- | --- | --- |
| A-03 | 探测期渲染 0 值仪表盘 | 已修复 | `ContentView.swift` `BrewLocatingView` + `detailColumn` 分支 | 构建；探测态需运行验证 |
| A-04 | brew 缺失时设置页不可达、状态卡不可点 | 已修复 | `ContentView.swift` detailColumn `.settings` 放行；`SidebarView.swift` `homebrewStatusCard` 改 Button | 构建；导航路径需运行验证 |
| A-05 | F0.2 无安装指引 | 已修复 | `OnboardingView.swift:141`（brew.sh + 复制命令 + 重新检测）；`ContentView.swift` BrewMissingView 同款 | 构建 |
| A-06 | 能力降级主界面无横幅 | 已修复（可关闭） | `ContentView.swift` `capabilityNotice` + `InlineNotice(.warning)` 会话内可关 | 构建；文案需运行验证 |
| A-07 | 最近任务点任意行只开最新记录 | 已修复 | `DashboardView.swift` `openHistoryRecord(record.id)` + `selectedRecordID` 高亮 | 构建；行点击需运行验证 |
| A-08 | 引导页扫描失败无反馈/重试 | 已修复 | `OnboardingView.swift:228-230` InlineNotice + 重试；扫描中禁「下一步」 | 构建 |
| A-09 | 扫描状态文案不自洽 | 已修复 | `AppState.swift` 取消文案区分首扫/保留结果；`DashboardView.swift` 术语统一扫描/检查更新/刷新 | 构建；文案需走查 |
| B-04 | 选择集与筛选脱节 | 已修复 | `InstalledView.swift:124,187-188` 随 `visibleIDs` 裁剪；吸底计数同源、0 禁用 | 构建；筛选+多选需运行验证 |
| B-05 | 体积列恒「—」、按体积排序无效 | 已修复 | `InstalledView.swift:200-211` 三态 + 排序；接 `AppState.packageDiskUsage`（d） | 构建；首次计算耗时需运行验证 |
| B-06 | 筛选缺 tap/仅手动/keg-only | 已修复 | `InstalledView.swift` 筛选菜单；cask 计数 0 隐藏分段 | 构建 |
| B-07 | 被依赖 chip 不可跳、未装依赖禁用无提示 | 已修复 | `PackageDetailView.swift` chip → `selectPackage`；禁用 + `.help` | 构建 |
| B-08 | caveats 无一键复制/折叠 | 已修复 | `PackageDetailView.swift` 折叠 + 复制 CAVEATS | 构建 |
| B-09 | 路径无复制入口、文件列表 500 项无说明 | 已修复 | `PackageDetailView.swift` 复制路径；文件区上限提示 | 构建 |
| B-10 | 卸载失败只有 2.8s toast | 已修复（状态层） | `TaskQueueStore` 失败结果保留 → 更新页失败行/抽屉可回看（配合 C-05） | 构建 |
| B-11 | 禁用控件无原因、只读提示误导 | 已修复 | `InstalledView.swift`/`PackageDetailView.swift` 只读横幅 + `.help` | 构建 |
| B-12 | 表格无键盘导航/表头不可排序/VO 复选框合并 | 已修复 | `InstalledView.swift` ↑↓/↵/Space、可排序表头、独立复选框 a11y | 构建；全键盘流程需运行验证 |
| C-03 | 取消当前任务后队列立即继续 | 已修复 | `TaskQueueStore.swift:448,811` 暂停 + `cancelQueuedBatchRemainder`；文案「剩余 N 个未执行」 | 构建；取消时序需运行验证 |
| C-04 | 排队项不可见不可取消 | 已修复 | `TaskQueueStore.pendingRecords:175`、`removePending:316`；`LogDrawerView.swift:285-304` 排队区 + 位次 | 构建；抽屉布局需运行验证 |
| C-05 | 失败行无退出码/建议/重试 | 已修复 | `UpdatesView.swift:377-395` 退出码徽章 + 首行 + suggestion + 查看日志/复制命令/重试 | 构建；窄宽度换行需运行验证 |
| C-06 | 退出不提示（与 P0-10 合并） | 已修复 | `QuitGuard.swift`（M1 P0-10） | 构建；交互需人工验证 |
| C-07 | 历史任务不可回看、重启后不可重试 | 已修复 | `TaskQueueStore.loadHistory:964`/`openHistoryRecord:978`/`followLatestRecord:993`；`LogDrawerView` 历史选择器 | 构建；日志加载时延需运行验证 |
| D-03 | root 服务不识别不拒绝 | 已修复 | `ServicesView.swift:127,144,246-248` 系统级 Badge + 禁启停 + 复制 sudo 命令 | 构建 |
| D-04 | brew 路径校验失败无就地错误 | 已修复 | `SettingsView.swift` + `AppState.swift` 就地 InlineNotice、保留输入 | 构建 |
| D-05 | 代理无校验、仅回车生效且非法值落盘 | 已修复 | `SettingsView.swift` URL 校验 + 「应用」按钮；`SettingsStore` 不落非法值 | 构建；回车提交需运行验证 |
| D-06 | 清理预览失败仍「很干净」 | 已修复 | `MaintenanceView.swift` 预览失败禁用执行 + 原文 + 重试 | 构建 |
| D-07 | doctor/missing 假「通过」 | 已修复 | `MaintenanceView.swift` 按退出码判定、分组、原文复制、`missingError` 渲染、跳详情 | 构建 |
| D-08 | kill 语义无入口 | 已修复 | `ServicesView.swift` 「停止进程」+ 危险确认（默认取消） | 构建；确认交互需运行验证 |
| D-09 | 服务日志入口缺失 | 已修复 | `AppState.swift` 解析 plist `log/error_log`；`ServicesView` 「打开日志」 | 构建 |
| D-10 | cask 无版本/体积/auto_updates 预览 | 已修复 | `Sheets.swift` 安装确认补充信息 + 诚实说明 | 构建 |
| D-11 | >24h 缓存被丢弃 | 已修复 | `AppState.swift` 保留过期缓存 + 「可能过期」+ 强制刷新 | 构建 |
| D-12 | Brewfile 导出失败不可诊断 | 已修复 | `AppState.swift` 退出码/首行 + Finder 显示 | 构建 |
| D-13 | Brewfile 导入无差异预览 | 已修复 | `AppState.brewfileImportPreview` + `Sheets.swift` 差异预览（解析完成前禁确认） | 构建；Sheet 交互需运行验证 |
| D-14 | 日志保留设置无效果 | 已修复 | `AppState.pruneTaskLogs` + 启动/设置变更触发；Toast「已清理 N 个」 | 构建 |
| E-02 | brew 缺失导航死路（与 A-04 合并） | 已修复 | 同 A-04 | 构建 |
| E-03 | 安装指引缺失（与 A-05 合并） | 已修复 | 同 A-05 | 构建 |
| E-04 | 菜单栏不显示可更新数 | 已修复 | `MyApp.swift:35-60` MenuBarExtra 自定义 label（mug+N）+ a11y label | 构建；菜单栏渲染需运行验证 |
| E-05 | 命令面板空查询无最近任务 | 已修复 | `CommandPaletteView.swift` `Group.recent` + `records.suffix(5)` → `openHistoryRecord` | 构建 |
| E-06 | 面板快捷键非全局 | 已修复 | `MyApp.swift` 全局 ⌘⇧K/⌘⇧D；删除 `MaintenanceView` 重复注册 | 构建；全局面板动作需运行验证 |
| E-07 | 包结果上限 10 无提示 | 已修复 | `CommandPaletteView.swift` 尾行「共 N 个结果 · 在发现页查看全部」 | 构建 |
| E-08 | ⌘R×3、⌘⇧V×2、⌘A/⌘⌫ 冲突 | 已修复 | 仅 `MyApp.swift:82,85` 保留全局；删 Dashboard/Services 局部；⌘A/⌘⌫ 仅在表格聚焦时生效（InstalledView） | 构建；输入框内快捷键需运行验证 |

## 2. 全量验收

- 构建：`xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData MODULE_CACHE_DIR="$PWD/build/modulecache" 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build` → `EXIT:0 / ** BUILD SUCCEEDED **`（`build/m2-final-build.log`；日志中 1 条 `error:` 字样为 CoreSimulator 过期噪声，1 条 warning 为 AppIntents 元数据）。
- 单测：`CLANG_MODULE_CACHE_PATH=$PWD/build/clang-module-cache swift test --disable-sandbox --scratch-path build/swiftpm-scratch` → `Executed 56 tests, with 3 failures`，失败均为已知 PTY 沙箱用例（`testMergedOutputAndExitCode`、`testTimeoutEscalatesAndFinishes`、`testTaskCancellationTerminatesChild`，`spawnFailed(1)`），无新增失败（`build/m2-swift-test.log`）。

## 3. 残留与风险（不阻塞 M2 收口）

1. `TaskBatchSummary.failedTaskCount` 已由 c 写入（聚合批次=1、逐包=失败数），但 `BatchSummarySheet` 尚未展示 → M3 处理。
2. `NSSavePanel.runModal` 在已呈现 sheet 内调用需运行验证（诊断导出、Brewfile 导出）。
3. `MenuBarExtra` 自定义 label、`confirmationDialog` 默认焦点、`QuitGuard` 退出确认需人工走查。
4. 逐包体积为后台串行 `du`，首次进入列表较慢；大索引下需观察是否需限量/缓存（M3 视表现）。
5. 依赖未安装时「安装」按钮为禁用占位（避免绕过安装确认），未提供「先安装依赖」快捷链路（P2 候选）。
6. `brew bundle dump` 覆盖已有文件可能需 `--force`（`BrewClient` 未改），导出实测前需确认（技术验证项，非交互回归）。
