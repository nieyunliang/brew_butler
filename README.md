# Brewbutler

**macOS 27+ 原生 SwiftUI Homebrew 可视化管理器。**

一次看清装了什么、能不能安全更新、谁依赖谁、占了多少空间、有哪些已知漏洞。它不是「brew 命令的按钮外壳」——界面数据全部来自本机 Homebrew，操作可取消、可追溯、可解释。

> v1.0（Build 1） · macOS 27+ / arm64 · Swift 5 语言模式 · 零第三方依赖 · 数据不上传

![Brewbutler 仪表盘](docs/screenshots/overview-light.png)

## 这是什么

Brewbutler 把 Homebrew 的日常维护收敛到 7 个页面、一个包详情页和一个 ⌘K 命令面板里：

- **可见性优先**：已安装清单、更新项、依赖关系、磁盘占用、服务状态、健康检查在一处可解释。
- **安全更新体验**：基于 `brew vulns --json`（OSV.dev）后台扫描漏洞，强制展示扫描覆盖率与时间，**不说「无漏洞」**，只说「本次扫描未发现」。
- **操作有边界**：同一时刻只允许 1 个变更类 brew 进程，取消按 SIGINT → SIGTERM → SIGKILL 分级，危险动作二次确认，失败不回滚。
- **本地优先**：无账号、无自建后端，v1.0 不启用遥测，不上传包列表、命令输出或环境信息。

当前实现约 1.2 万行 Swift（Core 3,326 / App 2,624 / UI 4,643 / Design 581，测试 733），包含 47 个 XCTest 与 14 份真实 brew 输出 fixture。

## 功能概览

| 页面 | 快捷键 | 关键能力 |
| --- | --- | --- |
| 仪表盘 | ⌘1 | Homebrew 健康度、可更新数、漏洞状态、磁盘占用、服务状态、最近操作 |
| 已安装 | ⌘2 | formula / cask 全量列表，按类型、状态、体积、安装时间筛选排序，批量操作 |
| 更新 | ⌘3 | 单个 / 批量 / 全部升级，区分安全更新，已锁定包跳过并计数，串行队列与实时日志 |
| 发现 | ⌘4 | 关键词搜索 formula / cask（含描述），查看详情并安装 |
| 服务 | ⌘5 | `brew services` 列表，启动 / 停止 / 重启并复查状态 |
| 维护 | ⌘6 | 清理（cleanup）、孤立依赖（autoremove）、doctor、missing、Brewfile 导入导出 |
| 设置 | ⌘7 | brew 路径、代理与镜像、通知、主题、日志保留、诊断导出、清除本地缓存 |
| 包详情 | — | 6 个标签页（概览 / 安全 / 依赖 / 被依赖 / 文件 / 历史）+ 固定 inspector |
| 命令面板 | ⌘K | 跳页面、跳包、执行操作；菜单栏常驻显示可更新数与漏洞提示 |

![包详情安全页](docs/screenshots/detail-security.png)

> 截图与 `docs/ui-mockup.html` 中的包版本、CVE、cask 与服务记录为演示数据，不是事实基线。

## 设计原则

这些约束是产品与安全评审的硬边界，也是贡献代码前必须遵守的规则：

1. **不经过 shell**：所有 brew 调用走 `posix_spawn` + argv 数组，禁止 `/bin/sh -c`、禁止字符串拼接命令。
2. **输入白名单**：进入参数的用户输入先过 `BrewArgumentValidator`（字符集、长度、禁止 `-` 开头与 `..`）。
3. **单一变更队列**：变更类任务串行执行，同一时刻最多 1 个 brew 变更进程；只读查询可并发。
4. **取消不留孤儿**：对进程组发信号，分级升级；timeout / cancel 语义优先于已解析输出。
5. **退出码按命令解释**：`brew vulns` 发现漏洞时退出码可能为 1，不算失败；`outdated` 接受 [0,1]。
6. **确定性环境**：清空继承的 `HOMEBREW_*`，只注入白名单变量；只读 scope 关闭自动更新。
7. **漏洞语义诚实**：任何位置都不写「无漏洞」，扫描失败显示「未知」，覆盖率与扫描时间始终可见。
8. **隐私本地优先**：缓存与任务日志只存本机；导出的诊断包默认脱敏。
9. **JSON 优先**：有 JSON 不解析文本；文本解析集中在 `BrewTextParser`，每个解析器配真实 fixture 与降级路径。
10. **永不代理 sudo**：不请求、不代理管理员密码；cask 授权失败时给出终端命令指引。

## 技术架构

依赖方向严格单向：UI → App → Core。Core 只依赖 Foundation / Darwin，可脱离 Xcode 用 SwiftPM 单测。

| 目录 | 行数 | 职责 |
| --- | ---: | --- |
| `Brewbutler/Core` | 3,326 | brew 定位与调用、进程/PTY、JSON 模型、缓存、文本解析与安全工具 |
| `Brewbutler/App` | 2,624 | `@MainActor @Observable` 状态层、串行任务队列、日志与历史、偏好设置 |
| `Brewbutler/UI` | 4,643 | 14 个 SwiftUI 视图：页面、弹层、日志抽屉、命令面板、菜单栏 |
| `Brewbutler/Design` | 581 | 颜色 / 字体 / 间距 tokens 与可复用组件 |
| `Tests/BrewbutlerCoreTests` | 733 | 47 个 XCTest：fixture、解析、安全、进程、更新管线 |

工程使用 Xcode 27 的 `PBXFileSystemSynchronizedRootGroup`：在 `Brewbutler/` 下新增文件会被自动纳入 target，**不要手改 `project.pbxproj`**。

## 系统要求

- **运行**：macOS 27.0+、Apple 芯片（arm64）、已安装 Homebrew（默认 `/opt/homebrew`）。
- **构建**：Xcode 27.0（含 Swift 6 工具链）、SwiftPM。
- 应用不使用 App Sandbox（沙盒内无法执行 brew、无法写入 Homebrew 目录），因此仅通过 DMG / PKG / ZIP 分发，**不提供 Mac App Store 版本**。

## 快速开始

### 安装发布包

发布产物（ad-hoc 签名、未公证）由 `scripts/build_release.sh` 生成到 `dist/`：

```bash
cd dist
shasum -a 256 -c SHA256SUMS   # 校验 DMG / PKG / ZIP
open Brewbutler-1.0.dmg       # 拖入「应用程序」，或改用 pkg / zip
```

首次打开遇到 Gatekeeper 提示属预期（未使用 Developer ID），右键「打开」即可。完整步骤、卸载与校验见 [安装指南](docs/release/INSTALL.md)。

### 从源码构建运行

```bash
xcodebuild -project Brewbutler.xcodeproj \
  -scheme Brewbutler \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build

open build/DerivedData/Build/Products/Debug/Brewbutler.app
```

`-derivedDataPath` 必须指向仓库内，默认 DerivedData 目录在受限环境只读。

### 运行测试

```bash
swift test --disable-sandbox
```

必须带 `--disable-sandbox`。当前 47 个用例中 44 个通过；3 个 PTY 集成用例（`testMergedOutputAndExitCode`、`testTimeoutEscalatesAndFinishes`、`testTaskCancellationTerminatesChild`）因受限环境拒绝 `openpty` 而失败，属环境限制而非代码回归。

### 发布打包

```bash
./scripts/build_release.sh              # 完整构建 + DMG / PKG / ZIP + SHA256SUMS
./scripts/build_release.sh --skip-dmg   # 受限沙箱中跳过 DMG
```

版本号读自工程 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；默认 ad-hoc 签名、不公证。`dist/` 是本地发布产物，默认不提交。

### 查看 UI 原型

无需服务器，直接打开单文件高保真原型：

```bash
open docs/ui-mockup.html
```

支持 URL 参数复现任意状态（`?screen=detail&pkg=openssl@3&tab=security&theme=dark`、`?log=1`、`?palette=1`、`?scan=1`）。

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/technical-notes.md](docs/technical-notes.md) | **技术事实的单一来源**：命令能力矩阵、JSON schema、退出码、超时、环境变量、分发清单 |
| [docs/product-plan.md](docs/product-plan.md) | PRD：定位、范围、68 条功能、P0 验收、流程、NFR、里程碑 |
| [docs/ui-design.md](docs/ui-design.md) | UI 规范：tokens、三栏布局、8 个页面、14 个组件、文案与无障碍 |
| [docs/ui-mockup.html](docs/ui-mockup.html) | 可交互高保真原型（8 个界面、深浅色、日志、⌘K、扫描态） |
| [docs/release/](docs/release/) | [安装指南](docs/release/INSTALL.md) 与 [发布说明](docs/release/RELEASE_NOTES.md) |
| [AGENTS.md](AGENTS.md) | 开发约定、硬约束、测试要求与「绝对不要做」清单（人类与 AI 代理共用） |
| [design/app-icon/README.md](design/app-icon/README.md) | 图标生成流程（SVG → icns） |

文档冲突时的处理顺序：**本机实测 > technical-notes 的事实 > PRD 的范围 > UI 规范的呈现**。发现冲突应显式更新文档，而不是在代码里默默二选一。

## 已知限制

| 限制 | 说明 |
| --- | --- |
| cask 安装 / 卸载可能触发 sudo | 图形界面不代理密码，失败时给出终端命令指引 |
| 漏洞扫描覆盖不完整 | `brew vulns` 只扫描 formula；部分包被跳过、`complete` 可能为 false；本机 36 个包约 29.7s |
| 部分命令无 JSON 输出 | 搜索、`doctor`、`cleanup` 依赖文本解析，brew 版本变化时可能降级为原始输出 |
| 变更任务串行 | 取消或失败可能已部分完成，应用不自动回滚、不自动重试 |
| 无应用内自动更新 | 升级需手动下载并替换应用 |
| 发布包未公证 | ad-hoc 签名，其他 Mac 首次打开需 Gatekeeper 放行 |

## 参与开发

1. 先读 [AGENTS.md](AGENTS.md)，再按任务类型读对应文档（brew 行为 → technical-notes；范围 → PRD；界面 → UI 规范）。
2. 新增 brew 命令 / 参数必须补「精确 argv」测试与退出码 / 降级语义测试；文本解析器必须有真实 fixture 与失败用例。
3. 安全用例（注入、URL、ANSI）是回归门禁，不允许删除或放宽断言。
4. 不要在本机执行真实的变更类 brew 命令来「测试」；不要把 `build/`、`.build/`、`dist/`、`.DS_Store`、`xcuserdata/` 提交进版本库。
5. 提交信息使用 Conventional Commits（`feat:` / `fix:` / `docs:` / `test:` / `refactor:` / `chore:`）。
