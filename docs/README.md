# Brewbutler · 产品方案与 UI 设计（交付索引）

> 交付日期：2026-10-23 ｜ 状态：产品方案 / UI 设计 / UX 优化方案均已评审，UI v2.0.2 已落地到代码（2026-11-08）
> 协作方式：Claude 产品负责人撰写 PRD，Claude UI/UX 负责人撰写设计规范与高保真原型；Lead 提供经本机实测的 brew 技术基准并完成交叉审校。
> 工程现状：Xcode 27 原生 SwiftUI 应用（`Brewbutler.xcodeproj`），任务岛已取代日志抽屉 / toast / 状态栏；最近一次 Debug 构建与逐页走查见 `docs/ux-optimization-plan.md` 修订记录。

---

## 1. 交付物

| 文件 | 规模 | 内容 | 状态 |
| --- | --- | --- | --- |
| [product-plan.md](product-plan.md) | 448 行 | PRD：定位、画像、竞品、指标、IA、68 条功能（P0 41 / P1 24 / P2 3）、41 条 P0 验收、6 条关键流程、NFR、架构决策、风险、里程碑、Open Questions | 已评审 |
| [ui-design.md](ui-design.md) | v2.0.2 | UI 规范 v2.0.2（Liquid Glass，2026-11-08，已与 UX 方案同步）：材质分层与 L0–L3 降级、系统语义色 tokens、5 项一级导航 + 全局搜索 + 设置窗口、任务岛、各页面与弹层、组件、文案、无障碍、SwiftUI API 映射 | 已评审 |
| [ux-optimization-plan.md](ux-optimization-plan.md) | v1.6 | UX 体验分析与优化方案（2026-11-08）：5 条用户旅程走查、18 个问题（附代码位置）、12 条优化方案（P0–P2）、与 v2 UI 的对应、落地状态；O-01–O-12 已在代码落地 | 已评审 |
| [ui-mockup.html](ui-mockup.html) | 单文件 | v2.0.2 可交互原型：全部页面、任务岛（折叠 / 展开 / 同步索引 / 批次结果 / 汇总）、资料库「筛选」菜单与 token、更新页随 scope 的主按钮、重新安装确认、依赖搜索链接、维护页「需要处理」排序、3 步首启引导、⌘K、卸载确认（输入包名）、浅/深色、降低透明度、减少动效、系统强调色切换、1024 窄窗 | 可交互 |
| [screenshots/](screenshots/) | 25 张 PNG（`v2-*`） | v2.0.2 逐屏截图（2x，已含 UX 方案 v1.4）；v1 截图归档在 `screenshots/v1/` | 已核对 |
| [technical-notes.md](technical-notes.md) | 350 行 | 经本机 Homebrew 7.0.10 实测的技术基准：命令能力矩阵、JSON schema、进程/环境约束、分发与安全清单、性能基线、待验证项 | 单一事实来源 |

### 查看原型

直接用浏览器打开 `docs/ui-mockup.html`（双击即可，无需服务器、无外部网络依赖）：

```bash
open docs/ui-mockup.html
```

支持 URL 参数复现任意状态，例如：

```
ui-mockup.html?screen=updates&select=1
ui-mockup.html?screen=library&island=open&theme=dark
ui-mockup.html?screen=detail&sheet=uninstall&target=openssl@3
ui-mockup.html?screen=library&sheet=uninstall&zap=1
ui-mockup.html?screen=library&lf=manual,tap:homebrew/core&menu=1
ui-mockup.html?screen=library&island=result
ui-mockup.html?screen=updates&uscope=安全&sync=fail
ui-mockup.html?screen=detail&sheet=reinstall
ui-mockup.html?onboard=1
```

参数：`screen=overview|updates|library|discover|services|maintenance|detail|settings`、`theme=dark`、`reduce=1`、`island=open|result|summary|sync`、`palette=1`、`sheet=uninstall|reinstall`、`lf=`、`menu=1`、`uscope=`、`sync=fail`、`dtab=`、`settab=`、`onboard=1|2|3`、`target=`、`zap=1`、`select=1`、`w=1024`、`dock=0`（隐藏演示控制坞）。

---

## 2. 30 秒结论

- **Brewbutler** 是 macOS 27+ 原生 Homebrew 可视化管理器，定位不是「brew 命令的 GUI 外壳」，而是**包可见性与安全更新体验**：更新、漏洞、依赖、磁盘、服务、健康度在一处可解释。
- **平台与分发**：macOS 优先；工程多平台能力保留，iPad/iPhone/visionOS 仅架构预留；**Developer ID 公证直发 + 可选 Cask 分发，不做 Mac App Store**（沙盒无法执行 brew / 写入 `HOMEBREW_PREFIX`）。
- **安全原则**：漏洞扫描基于 `brew vulns --json`（OSV.dev），后台、可取消、缓存；UI 强制显示「覆盖 36/59、23 包跳过、部分覆盖、扫描时间」，**绝不写「无漏洞」**；发现漏洞时 `brew vulns` 退出码可能为 1，不判失败。
- **操作边界**：同一时刻仅 1 个变更类 brew 任务；取消/超时/失败诊断可见；失败不自动回滚；`--zap` 需输入包名；永不代理 sudo 密码。
- **隐私**：无账号、无自建后端、v1.0 不启用遥测；不采集包列表与命令输出。

---

## 3. 文档关系

```
technical-notes.md（实测事实：brew 7.0.10 / JSON schema / 约束 / 性能）
        │
        ├──> product-plan.md（为什么做、做什么、做到什么程度、如何验收）
        │            │
        │            └──> ui-design.md（怎么呈现、怎么交互、如何映射 SwiftUI）
        │                        │
        │                        └──> ui-mockup.html + screenshots/（可交互验证）
        └──────────────────────────────> 三者共同约束实现
```

### 已确认的交叉一致性决策

| 决策 | 结论 |
| --- | --- |
| 一级导航 | 仪表盘 / 已安装 / 更新 / 发现 / 服务 / 维护 / 设置（⌘1–⌘7）+ ⌘K 命令面板 + 菜单栏常驻；不新增一级导航 |
| 包详情 | 主区 6 tabs（概览 / 安全 / 依赖 / 被依赖 / 文件 / 历史）+ 右侧固定 inspector（操作 / 概要 / 健康 / 路径 / 被依赖 / 危险区） |
| 状态词 | 未安装 / 已安装 / 可更新 / 已是最新 / 已锁定 / 有已知漏洞 / 已废弃 / 扫描未知 / 部分覆盖 |
| 术语与大小写 | formula / cask / tap / keg-only / Bottle / Brewfile 保留英文小写；操作文案「锁定 / 解锁」 |
| 遥测 | v1.0 默认关闭且不提供开启入口；未来 L2 若启用须显式 opt-in 并单独评审 |
| 危险动作 | 卸载、强制卸载、删除关联文件（对应 `--zap`，界面不出现参数串）、清理、autoremove 一律二次确认，默认焦点在「取消」 |

---

## 4. 技术基准摘要（本机实测，Homebrew 7.0.10）

| 项 | 实测结果 |
| --- | --- |
| 环境 | macOS 27.0.1 arm64，Xcode 27.0，Swift 5.0，部署目标 27.0 |
| 已安装 | 59 formula / 0 cask / 0 service；7 leaves；Cellar 1.1 GB；缓存 175 MB |
| 可更新 | 36 formula（`brew outdated --json=v2`） |
| 主数据源 | `brew info --json=v2 --installed`（0.41s / 59 包）；快路径 `brew list --versions --json`（依赖 jq 1.7.1，路径 /usr/bin/jq） |
| 漏洞 | `brew vulns --json`（OSV.dev）：36 包约 29.7s，23 包跳过，`complete=false`，发现漏洞时退出码可能为 1；仅扫描 formula |
| 服务 | `brew services list --json` 字段 name / status / user / file / exit_code；无服务返回 `[]` |
| 搜索 | `brew search` 无 JSON；`brew desc -s` 可搜描述（首次建缓存较慢）；发现页以 formulae.brew.sh API + 缓存兜底 |
| 环境约束 | Finder 启动的 GUI 无 `/opt/homebrew/bin` PATH；需探测 brew 路径/登录 shell；受限环境写 cache/prefix 会 `Operation not permitted` |
| 进程模型 | Process + PTY 流式读取、SIGINT→SIGTERM→SIGKILL 分级取消、串行变更队列、日志脱敏 |

> 完整命令矩阵与 JSON 字段见 [technical-notes.md](technical-notes.md)。

---

## 5. 路线图（详见 PRD §12）

| 里程碑 | 周期 | 目标 |
| --- | --- | --- |
| M0 技术验证 | W1–W2 | brew 探测、ProcessRunner + PTY、fixture 回放、串行队列、`vulns` 退出码语义 |
| M1 MVP 闭环 | W3–W6 | 首启 → 查看 → 批量更新 → 失败处理端到端；P0 验收全过 |
| M2 变更加固与差异化 | W7–W11 | 安装/卸载、发现页、服务、漏洞覆盖度、Brewfile/清理/doctor、菜单栏 |
| M3 打磨与分发 | W12–W16 | 10k 包压测、可访问性、i18n、签名公证、Cask、Sparkle、beta |

---

## 6. 进入实现前必须验证的事项

| 优先级 | 事项 | 原因 |
| --- | --- | --- |
| P0 | PTY 下 brew 流式输出与分级取消 | 决定日志/取消体验与是否残留进程 |
| P0 | `brew vulns` 退出码与 `complete=false` 语义 | 决定任务成败判定与「安全」文案 |
| P0 | 无 TTY 环境 cask 安装的 sudo/授权路径 | 决定失败指引与是否可闭环 |
| P1 | `.inspector` + `NavigationSplitView` 三栏组合 | 设计核心布局依赖 |
| P1 | `Table` 列隐藏/行 Enter/键盘导航 | 已安装与更新页 |
| P1 | Liquid Glass `.glassEffect` 及降低透明度降级 | macOS 27 视觉基线 |
| P2 | 10k 包列表与体积扫描性能 | M3 门槛 |
| P2 | Sparkle 与 Cask 双轨更新冲突 | 分发一致性 |

设计文档 §11 与技术基线 §10 有完整清单与验证方式。

---

## 7. 仓库状态与说明

- 现状（2026-11-08）：UI 已按 `ui-design.md` v2.0.2 重写，任务岛取代日志抽屉 / toast / 状态栏；`docs/` 下为 PRD、UI 规范、UX 优化方案、技术基准、可交互原型与 25 张 v2 截图。
- 未执行 git commit；仓库仍处于「重命名未提交」状态，现状以 `git status` 与代码为准。
- 原型中的包版本、CVE、cask 与服务记录为演示数据；真实数量口径以 technical-notes 实测为准（59 formula / 0 cask / 0 service）。
- 本机验收：Debug 构建成功；`swift test --disable-sandbox` 55/58 通过（3 个 PTY 用例受沙箱限制）；逐页截图走查见 `ux-optimization-plan.md` 修订记录。

---

## 8. 快速验收清单

- [x] PRD 覆盖定位、用户、竞品、指标、IA、P0/P1/P2、验收标准、流程、NFR、架构、风险、里程碑、Open Questions
- [x] 每条 P0 有 Given/When/Then 验收标准
- [x] UI 规范含设计原则、两套 tokens、5 项一级导航 + 设置窗口、组件表、文案、无障碍、SwiftUI 映射（v2.0.2）
- [x] 高保真原型可交互（切页/搜索/详情/任务岛/深浅色/⌘K/扫描/筛选/3 步引导/窄窗）
- [x] 1280×800、1024×768 窄窗、浅色 / 深色渲染核对，无溢出/重叠
- [x] PRD、UI、技术基线三者 IA / 命名 / 状态词 / 结构一致
- [x] 技术事实均来自本机 brew 7.0.10 实测，不确定项标注「需技术验证」
