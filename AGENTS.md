# AGENTS.md — Brewbutler

> AI 编码代理进入本仓库的唯一入口；人类工程师同样适用。开始任务前先读本文件，再按 §3 读对应文档。
>
> 基线：macOS 27.0.1 (arm64) · Xcode 27.0 (27A266a) · Swift 6.4 编译器（工程使用 Swift 5 语言模式）· Homebrew 7.0.10
> 更新：2026-11-08

---

## 1. 项目是什么

**Brewbutler** 是 macOS 27+ 原生 SwiftUI Homebrew 可视化管理器。定位不是「brew 命令的 GUI 外壳」，而是**包可见性与安全更新体验**：一次看清装了什么、能不能安全更新、谁依赖谁、占了多少空间、有哪些已知漏洞。

当前状态（经本机实测，不是计划）：

- 实现已完整：`Brewbutler/Core` 3,466 行（纯 Foundation/Darwin）→ `Brewbutler/App` 4,518 行（`@MainActor @Observable` 状态与任务队列）→ `Brewbutler/UI` 11,647 行 + `Brewbutler/Design` 1,231 行，加上入口共约 21.4k 行；测试 857 行。UI 已按 `docs/ui-design.md` v2.0.2（Liquid Glass）与 `docs/ux-optimization-plan.md` O-01–O-12 重写（2026-11-08）。
- `swift test --disable-sandbox`：58 个 XCTest，55 通过；3 个 PTY 用例（merged capture / timeout / cancel）在沙箱下 `spawnFailed(1)`（2026-11-08 实测，属环境限制，见 §8）。
- Debug 构建与 Release archive 均已成功执行过；构建产物在 `build/`。
- 发布链路已就绪：`scripts/build_release.sh` 在 `dist/` 生成 pkg / zip / SHA256SUMS（ad-hoc 签名、未公证），安装与发布说明在 `docs/release/`。
- `docs/` 的 PRD、UI 规范、技术基线已评审，原型可交互；UI 规范 v2.0.2 已由代码实现，`docs/README.md` 的旧「工程现状」描述以本文件与 `git status` 为准。
---

## 2. 快速命令

| 目的 | 命令 |
| --- | --- |
| 跑全部单测 | `swift test --disable-sandbox` |
| 只跑一组 | `swift test --disable-sandbox --filter FixtureTests` |
| Debug 构建 | 见下方代码块 |
| 启动 Debug App | `open build/DerivedData/Build/Products/Debug/Brewbutler.app` |
| 发布打包 | `./scripts/build_release.sh`（沙箱内加 `--skip-dmg`；输出到 `dist/`） |
| 打开 UI 原型 | `open docs/ui-mockup.html` |

```bash
# Debug 构建（-derivedDataPath 必须指向仓库内：默认 DerivedData 目录在本机沙箱只读）
xcodebuild -project Brewbutler.xcodeproj \
  -scheme Brewbutler \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

Release archive（只在要验证分发时跑；本机曾用此命令成功归档）：

```bash
xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  -archivePath build/Brewbutler.xcarchive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  PRODUCT_BUNDLE_IDENTIFIER=com.brewbutler.app \
  ENABLE_HARDENED_RUNTIME=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MODULE_CACHE_DIR="$PWD/build/modulecache" \
  'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' \
  archive
```

约定：

- `swift test` 必须带 `--disable-sandbox`；否则 SwiftPM 的嵌套沙箱在本机失败。
- 命令输出可写入 `build/*.log`，那里的内容不参与版本库。
- 长构建放后台；不要并发跑多个 xcodebuild（共享 DerivedData 会互相阻塞）。
- 本机是沙箱执行环境，`xcodebuild -list` 会打印 `IDELogStore ... permission` 警告，属噪声，可忽略。

---

## 3. 文档：先读哪一份

| 文档 | 角色 | 什么时候读 |
| --- | --- | --- |
| `docs/technical-notes.md` | **单一技术事实来源**：brew 命令能力矩阵、JSON schema、退出码、超时、环境变量、分发与安全清单 | 任何碰 brew / 进程 / JSON / 分发的改动 |
| `docs/product-plan.md` | PRD：定位、范围、68 条功能（P0/P1/P2）、41 条 P0 验收、流程、NFR、里程碑 | 判断「该不该做」「做到什么程度」 |
| `docs/ui-design.md` | UI 规范：tokens、三栏布局、8 个页面、14 个组件、文案表、无障碍、SwiftUI 映射 | 任何 UI / 交互 / 文案改动 |
| `docs/README.md` | 交付索引与 30 秒结论 | 快速了解全局 |
| `docs/release/INSTALL.md`、`RELEASE_NOTES.md` | 安装 / 发布说明（随版本更新，需与产物一致） | 打包、发版、校验和与签名状态 |
| `docs/ui-mockup.html` + `docs/screenshots/` | 高保真原型与逐屏截图（含演示数据） | 对齐视觉细节 |
| `design/app-icon/README.md` | 图标生成流程（SVG → icns） | 只改图标时 |

**冲突处理顺序**：本机实测 > `technical-notes.md` 的事实 > PRD 的范围 > UI 规范的呈现。发现冲突要显式消除（更新文档），不要在代码里默默二选一。

硬规则：

- 任何 brew 行为、JSON 字段、退出码的结论必须能在 `docs/technical-notes.md` 找到，或由你实测后补进去；未验证的写「需技术验证」，不臆造能力。
- 改用户可见行为 → 同步 PRD 中对应的 P0 验收（Given/When/Then）；改 UI/文案 → 同步 `ui-design.md`。
- `docs/README.md` §7「仓库状态与说明」是交付当天快照（写着「未修改任何源码」），**已过时**；现状以 `git status` 和代码为准。
- 原型与截图里的包版本、CVE、cask、服务记录是演示数据，不是事实基线；事实口径见 `technical-notes.md` §1。

---

## 4. 目录地图

```
Brewbutler/
  MyApp.swift              @main；WindowGroup + MenuBarExtra + ⌘1–⌘7 / ⌘K
  ContentView.swift        NavigationSplitView 三栏骨架、工具栏搜索、弹层宿主、任务岛宿主
  Core/                    纯 Foundation/Darwin，可被 SwiftPM 单测
    Brew/                  BrewLocator、BrewInstallation、BrewClient、BrewEnvironment、
                           BrewTextParser、BrewArgumentValidator
    Process/               SpawnedProcess（PTY/管道/取消）、ProcessTypes、BrewProcessRunner
    Models/                BrewModels（brew JSON）、PackageSnapshot（索引与展示模型）
    Persistence/           DiskCache
    Utilities/             ANSIStripper、BrewSectionClassifier
  App/                     @MainActor @Observable 状态层
    AppState.swift         导航、brew 探测、索引刷新、漏洞扫描、磁盘、任务构造、诊断
    TaskQueueStore.swift   串行变更队列、日志、历史、批次汇总
    TaskModels.swift       任务 / 日志 / 记录模型与落盘
    SettingsStore.swift    UserDefaults 偏好
  UI/                      18 个 SwiftUI 视图文件（页面、任务岛、弹层、局部组件）
  Design/                  AppTheme（色/字/间距 tokens）+ Components（徽章、卡片、按钮…）
Tests/
  BrewbutlerCoreTests/     58 个 XCTest（fixture / parsing / security / process / update 管线）
  Fixtures/                真实 brew 7.0.10 输出；不要手改 fixture 让测试变绿
docs/                      产品方案 / UI 规范 / UX 优化方案 / 技术基准 / 原型 / 截图；release/ 放安装与发布说明
design/app-icon/           图标源文件与 build-icon.sh
scripts/build_release.sh   Release 打包：archive → pkg/zip/dmg → SHA256SUMS → dist/
dist/                      发布产物（pkg / zip / SHA256SUMS / BUILD-INFO.txt），默认不提交
Package.swift              BrewbutlerCore 的 SwiftPM 清单，直接复用 Brewbutler/Core
build/                     本地产物（DerivedData、xcarchive、日志、qa-stage），不提交
.workbuddy-ai/memory/      历史工作日志，只作背景参考，不是规范
```

Xcode 27 工程使用 `PBXFileSystemSynchronizedRootGroup`：`Brewbutler/` 下新增文件会被自动纳入 target，**不要手改 `project.pbxproj`**。

---

## 5. 架构与不可协商的约束

### 分层

- 依赖方向：UI → App → Core。Core 不知道 UI/App，且只 import `Foundation` / `Darwin`。
- `Brewbutler/Core` 同时被 Xcode target 与 SwiftPM target（`Package.swift`，平台 macOS 14）编译。不要把 macOS 27 专属 API 放进 Core，除非同步评估单测可编译性。
- 状态层是 `@MainActor @Observable`；视图只读状态、调方法，**不直接触碰 `Process`**。
- 后台解码、扫描、磁盘统计放在独立 `Task` 中，结果回主线程更新状态；缓存用 `@ObservationIgnored`。

### 硬约束（来自 PRD/NFR 与安全评审，改动前先确认）

1. **不经过 shell**：所有 brew 调用走 `BrewClient` → `BrewProcessRunner` → `SpawnedProcess`，用 `posix_spawn` 传 argv 数组；禁止 `/bin/sh -c`、禁止字符串拼接命令、禁止 shell 转义。
2. **输入白名单**：任何进入参数的用户输入先过 `BrewArgumentValidator`（字符集 `[A-Za-z0-9@+._/-]`、≤128、禁止 `-` 开头、禁止 `..`、禁止空段/绝对路径式 tap）；URL 只允许 http(s)。
3. **单一变更队列**：变更类任务由 `TaskQueueStore` 串行执行，同一时刻最多 1 个 brew 变更进程；同一包同一操作去重；只读查询在设计上可并发（上限见 technical-notes §4.4）。
4. **取消不留孤儿**：取消时 SIGINT → 3s 未退出发 SIGTERM → 累计 7s 发 SIGKILL；超时则 SIGTERM → 2s → SIGKILL。均对**进程组**发信号（`POSIX_SPAWN_SETSID`）；timeout/cancel 语义优先于已解析的 stdout。
5. **退出码按命令解释**：`BrewClient.decodeJSON` 用 `acceptedExitCodes`；`brew vulns` 发现漏洞时退出码可能为 1，**不算失败**（以能否解析 JSON 判定）；`outdated` 接受 [0,1]；`doctor`/`missing` 非 0 表示「有问题」而非崩溃。
6. **确定性环境**：`BrewEnvironment` 清空继承的 `HOMEBREW_*`，只注入白名单变量；只读 scope 注入 `HOMEBREW_NO_AUTO_UPDATE`，变更 scope 去掉它；注入清单在诊断包可见。
7. **危险动作**：卸载、`--zap`、清理、autoremove、服务启停必须二次确认，默认焦点在「取消」；`--zap` 必须输入包名；**永不请求或代理 sudo / 管理员密码**；失败不自动回滚、不自动重试。
8. **漏洞语义诚实**：任何位置都不写「无漏洞」，只写「本次扫描未发现」+ 覆盖率（checked/total、skipped、complete、扫描时间）；扫描失败显示「未知」；结果按「已安装快照哈希 + 24h TTL」缓存。
9. **隐私本地优先**：无账号、无自建后端、v1.0 无遥测；不上传包列表、命令输出、主机名、路径；日志/诊断导出默认不含凭据与包清单，导出前做脱敏。
10. **JSON 优先**：有 JSON 就不解析文本；文本解析集中在 `BrewTextParser`，每个解析器配真实 fixture + 失败用例；解码宽容（字段可选、未知字段忽略），解析失败降级为「原始输出 + 复制」，不崩溃。
11. **UI 只消费状态**：颜色/字号/间距只用 `AppTheme` tokens，组件优先复用 `Design/Components.swift`；不硬编码十六进制色值。
12. **术语与文案**：界面 zh-Hans 优先；formula / cask / tap / keg-only / Bottle / Brewfile 保留英文小写；状态词固定为「未安装 / 已安装 / 可更新 / 已是最新 / 已锁定 / 有已知漏洞 / 已废弃 / 扫描未知 / 部分覆盖」；危险动作词「卸载 / 强制卸载 / 删除关联文件」（界面不出现 `--zap` 参数串）。

违反以上任一条的改动，视为需要用户明确决策，不要自行放宽。

---

## 6. 代码约定

- **语言与并发**：Swift 5 语言模式；`async/await` + `@MainActor`。Core 模型 `Sendable`；只有确实线程安全的包装才用 `@unchecked Sendable`（如 `SpawnedProcess`），并在注释里说明。
- **零第三方依赖**：Xcode 工程没有任何 SPM 引用，`Package.swift` 也无 dependencies。新增依赖必须先获得用户同意。
- **Core 公共 API**：`public` 类型/方法要显式 `init`、尽量 `Sendable`、带文档注释（现状：公共 API 注释为英文，用户可见文案为中文）。
- **错误**：用 `LocalizedError`；失败统一带 `BrewFailureKind` + 中文 `suggestion` + command/exitCode/stdout/stderr/firstErrorLine，便于诊断与复制。
- **文件组织**：一个主类型一个文件，文件名与类型同名；新代码放进既有目录（Core/Brew、Core/Process、Core/Models、Core/Persistence、Core/Utilities、App、UI、Design）。
- **格式**：4 空格缩进，跟随相邻代码；仓库没有 SwiftLint / SwiftFormat / Makefile，**不要大规模重排格式**。
- **注释**：解释「为什么 / 约束 / 易踩的坑」，不要翻译代码；临时 hack 必须写明原因与移除条件。
- **改动范围**：保持 diff 聚焦；不顺手重构无关文件；不删除现有中文文案或降级处理。
- **数据持久化**：现状是 UserDefaults（偏好）+`Library/Application Support` 下的 JSON 缓存与任务日志文件（DiskCache / TaskModels）；PRD §10 提到的 SwiftData 尚未引入，不要擅自添加。不要把大文本塞进 UserDefaults。

---

## 7. 测试

- 框架：XCTest（当前 0 个 Swift Testing 用例）。位置 `Tests/BrewbutlerCoreTests/`，fixture 在 `Tests/Fixtures/`。
- 覆盖重点：
  - `FixtureTests`：JSON 解码、索引合并、`vulns` 退出码语义；
  - `ParsingTests`：search / cleanup / doctor / missing 文本解析；
  - `SecurityTests`：token 注入、URL 白名单、ANSI 剥离、严重度排序；
  - `ProcessIntegrationTests`：真实子进程、超时、取消、真实 brew（无 brew 时自动 skip）；
  - `UpdatePipelineTests`：命令行参数快照、失败语义、索引边界。
- 新增 brew 命令/参数：必须同时加「精确 argv」测试 + 退出码/降级语义测试。
- 新增文本解析器：必须加真实 fixture + 成功用例 + 解析失败用例；fixture 取自真实 brew 输出，不手改。
- 安全用例（注入、URL、ANSI）是回归门禁，**不允许删除或放宽断言**。
- 变更类命令一律用 `MockProcessRunner` / `ReplayProcessRunner` 测试，不在本机真实执行。
- 本机已知：3 个 PTY 用例失败（§8）；汇报时说明这是环境限制，不要以「测试全绿」描述。

---

## 8. 本机环境与已知问题

- **沙箱**：当前执行环境是 workspace-write 沙箱。`ProcessIntegrationTests` 的 3 个 PTY 用例（`testMergedOutputAndExitCode`、`testTimeoutEscalatesAndFinishes`、`testTaskCancellationTerminatesChild`）在 2026-10-25 曾通过，2026-11-08 实测再次 `spawnFailed(1)`（子进程被沙箱拒绝）：属环境限制，按环境限制汇报而不是当作代码回归。
- **SwiftPM 缓存**：`~/Library/Caches/org.swift.swiftpm` 与 `~/Library/org.swift.swiftpm` 只读，出现 `disabling user-level cache features` / `readonly database` 警告，属噪声；测试仍可完成。
- **DerivedData**：默认 `~/Library/Developer/Xcode/DerivedData` 不可写；必须用 `-derivedDataPath build/DerivedData`。
- **宏/插件沙箱**：若 xcodebuild 出现 plugin / 宏相关沙箱错误，可追加 `'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`（Release archive 曾使用）。
- **brew 环境**：Homebrew 7.0.10，前缀 `/opt/homebrew`，`jq` 在 `/usr/bin/jq`；59 formula / 0 cask / 0 service。真实 brew 集成测试会读取本机状态，数量变化属正常。
- **发布签名**：本机没有 Developer ID 证书，`scripts/build_release.sh` 默认 ad-hoc 签名（`SIGN_IDENTITY=-`）且不公证。DMG 制作与挂载校验需要磁盘镜像权限，沙箱内可能被跳过（`--skip-dmg`）。版本号读自 pbxproj 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；产物是否为 DMG/PKG/ZIP 以 `dist/` 实际内容为准。
- **不要在本机执行变更类 brew 命令**（install / uninstall / upgrade / cleanup / autoremove / services / update）来「验证」代码；除非用户明确要求并理解影响。只读命令（`--version`、`info --json`、`outdated --json`、`services list --json`、`vulns --json`）可用于实测。
- **取消时间线**：代码与文档已对齐（2026-10-25）：取消「SIGINT → 3s → SIGTERM → 累计 7s → SIGKILL」，超时「SIGTERM → 2s → SIGKILL」；technical-notes §4.3 已按此更新。PRD F6.3 的 3s/10s 属 PRD 阶段口径，改动取消逻辑前以代码为准并与用户确认。
- `build/` 当前数百 MB（DerivedData、xcarchive、日志、qa-stage），未跟踪；不要提交，也不要删除用户可能还要用的归档。

---

## 9. Git 状态与提交（特殊，先读完再动）

仓库当前处于「重命名未提交」状态：

- HEAD 只有模板项目 `Initial Commit`（旧 `brew/`、`brew.xcodeproj/` 路径）。
- 工作树里旧 `brew/` 文件显示为 deleted，新 `Brewbutler/`、`Brewbutler.xcodeproj/`、`Tests/`、`Package.swift`、`docs/`、`design/`、`scripts/`、`dist/`、`build/`、`.build/`、`.workbuddy-ai/`、`AGENTS.md` 全部 **untracked**。
- 没有 `.gitignore`。

因此：

- **禁止** `git checkout -- .`、`git reset --hard`、`git clean -fd`：会直接毁掉整个未提交的实现。
- 提交只在用户明确要求时进行；不要 push、不要改写历史。
- 提交前逐项检查 `git status`，只 add 源码 / 测试 / 文档 / 工程与设计文件；排除 `build/`、`.build/`、`dist/`、`*.xcarchive`、`*.log`、`.DS_Store`、`xcuserdata/`、`*.xcuserstate`。
- `scripts/`、`docs/release/` 属于源码/文档，应纳入版本；`dist/` 是发布产物，默认不提交（除非用户要求归档）。
- 若用户要求「初始化提交」，建议先补一个 `.gitignore`（上述排除项）再提交；未获指示不要自行创建额外文件。
- 提交信息沿用 Conventional Commits 风格：`feat:` / `fix:` / `docs:` / `test:` / `refactor:` / `chore:`，正文说明验证命令与已知环境限制。

---

## 10. 任务路由

| 要改什么 | 必读 | 必改 / 必验 |
| --- | --- | --- |
| brew 命令、参数、超时 | technical-notes §2/§4 | `BrewClient` + 参数测试 + 退出码测试 + 命令矩阵 |
| JSON 模型 / 新字段 | technical-notes §3 | `BrewModels` 宽容解码 + fixture + 失败用例 |
| 文本解析 | technical-notes §2/§8 | `BrewTextParser` + fixture + 降级路径 |
| 任务队列 / 取消 / 日志 | technical-notes §4、PRD F6 | `TaskQueueStore` + `SpawnedProcess` + 集成/模拟测试 |
| 漏洞展示 / 覆盖度 | technical-notes §3.4、PRD F11、ui-design §8 | `VulnReport`/`PackageSnapshot` + 覆盖率文案 + fixture（complete=false、退出码 1） |
| 页面 / 交互 | ui-design §3–§5、§9 | 新 View + `AppSection`/侧边栏/命令面板入口 + 无障碍 + `AppTheme` |
| 文案 / 术语 | ui-design §6、PRD §6 | 同步两份文档；状态词与大小写 |
| 图标 / 分发 / 签名 | technical-notes §7、design/app-icon/README.md | 归档命令 + 不进 App Store 的约束 |
| 发布 / 打包 | `scripts/build_release.sh`、`docs/release/*.md` | 版本号、签名状态、pkg/zip/dmg、SHA256SUMS 与说明文档一致 |
| 文档本身 | 本文件 §3 | 保持 PRD / UI / 技术三份交叉一致，更新修订记录 |

---

## 11. 完成定义（DoD）

- [ ] `swift test --disable-sandbox` 无**新增**失败（本机 3 个 PTY 用例为已知环境限制）。
- [ ] 影响 UI / 入口 / 工程配置时，`xcodebuild ... build` 成功。
- [ ] 新逻辑有测试；解析/命令/安全相关改动用 fixture 或 Mock 覆盖。
- [ ] 所有用户输入仍过 `BrewArgumentValidator`；没有任何 shell 拼接。
- [ ] 危险操作仍有二次确认；没有新增 sudo / 密码代理；没有自动回滚。
- [ ] 漏洞文案没有出现「无漏洞」；覆盖率与扫描时间仍可见。
- [ ] 行为变更同步到 `docs/technical-notes.md`（必要时 PRD / UI 文档）。
- [ ] 发版改动：`scripts/build_release.sh` 能完成打包，`docs/release/` 与 `dist/BUILD-INFO.txt`、`SHA256SUMS` 保持一致。
- [ ] `git status` 干净可控：没有把 `build/`、`.build/`、`dist/`、`.DS_Store`、`xcuserdata/` 加入暂存区。
- [ ] 最终回复列出改动文件、执行的验证命令、以及未验证/受环境限制的事项。

---

## 12. 绝对不要做

- 不要用 `sh -c` / 字符串拼接执行 brew，或绕过 `BrewArgumentValidator`。
- 不要在本机真实执行变更类 brew 命令来「测试」。
- 不要删除/放宽安全测试或把 fixture 改成让测试通过的样子。
- 不要为了让测试通过而移除 PTY 取消/超时断言。
- 不要引入第三方依赖、Web 技术栈或新的构建系统。
- 不要把「扫描未发现漏洞」写成「无漏洞」。
- 不要提交 `build/`、DerivedData、`dist/`、`.DS_Store`、`xcuserdata/`、日志或密钥。
- 不要手改 `dist/` 里的产物或校验和；需要更新时重新运行 `scripts/build_release.sh`。
- 不要执行 `git checkout -- .` / `git reset --hard` / `git clean -fd`。
- 不要臆造 brew 参数或不存在的 JSON 字段；不确定就标记「需技术验证」并实测。
