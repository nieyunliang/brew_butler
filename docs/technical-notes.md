# Brewbutler 技术基准与实现约束

> 版本 1.0 ｜ 日期 2026-10-23 ｜ 维护：Lead ｜ 状态：已在本机实测验证
>
> 本文是 PRD（`docs/product-plan.md`）与 UI 设计（`docs/ui-design.md`）的共同技术事实来源。实现阶段如与本文冲突，以重新实测结果为准并更新本文。

## 0. 结论速览

| 结论 | 说明 |
| --- | --- |
| 数据层以 JSON 为主 | 包列表、详情、更新、服务、漏洞均有官方 JSON 输出；只有搜索、deleting、文本类命令需要解析 |
| 首选架构 | SwiftUI（macOS 27+）+ 进程执行层（串行队列 + 流式读取 + 可取消）+ JSON 解码 + 本地缓存 |
| 分发方式 | Developer ID 签名 + 公证直发；**不做 Mac App Store**（沙盒无法执行 brew / 写 HOMEBREW_PREFIX） |
| 最大技术风险 | brew 的文本输出不稳定、cask 的 sudo/系统授权、网络型命令（outdated/vulns/search）的失败与耗时 |
| 硬性约束 | 所有参数必须走 Process 参数数组，禁止拼接 shell；同一时刻只允许一个变更类任务 |

## 1. 验证环境

| 项 | 值 |
| --- | --- |
| 主机 | macOS 27.0.1 (arm64) |
| Homebrew | 7.0.10，HOMEBREW_PREFIX=/opt/homebrew |
| Xcode / Swift | Xcode 27.0（Build 27A266a），工程 SWIFT_VERSION=5.0，部署目标 27.0 |
| 工程形态 | SwiftUI 多平台模板：iphoneos / iphonesimulator / macosx / xros / xrsimulator，TARGETED_DEVICE_FAMILY=1,2,7 |
| 已安装 | 59 个 formula，0 个 cask，0 个 service，7 个 leaves |
| 可更新 | 36 个 formula（`brew outdated`） |
| 占用 | Cellar 1.1 GB，Homebrew 缓存 175 MB |
| jq | 1.7.1（Apple），路径 `/usr/bin/jq`（不在 /opt/homebrew/bin，需确保 PATH 可见）；`brew list --versions --json` 依赖 jq |

> 注：本次基准采集在受限执行沙箱中完成，brew 写 cache/lock/prefix 会被拒绝（`Operation not permitted`），因此 `brew update` / `brew outdated` 首次拉取 API 数据时出现下载失败但仍使用缓存输出。真实用户环境中这些目录通常可写；该现象恰好对应应用需要处理的「权限不足」错误态。

## 2. brew 命令能力矩阵

图例：JSON=有官方 JSON 输出；Stream=流式文本、耗时长、可能改变系统状态；Risk 为集成风险（低/中/高）。

| 命令 | JSON | 用途 | 实测 | Risk | 备注 |
| --- | --- | --- | --- | --- | --- |
| `brew --version` / `--prefix` / `--repository` / `--cache` / `config` | 否 | 环境探测、能力判定 | <0.3s | 低 | 首次启动必跑；`config` 可展示 Ruby/CPU/CLT 等信息 |
| `brew info --json=v2 --installed` | 是 | 已安装包主数据源 | 0.41s / 59 包 | 低 | 元数据完整，含 installed[]、outdated、pinned、caveats、service 字段 |
| `brew info --json=v2 <formula>` | 是 | 未安装包详情/发现 | 0.3-1s（走 API 缓存） | 低 | 无网络且无缓存时失败 |
| `brew info --json=v2 --cask <token>` | 是 | Cask 详情 | 0.3-1s | 低 | 返回 `casks[]`，字段与 formula 不同 |
| `brew list --versions --json` | 是 | 快速版本/固定状态 | 快（未单独计时） | 低 | 需 `--versions`、无位置参数、依赖 jq；只有版本字段 |
| `brew outdated --json=v2` | 是 | 可更新列表 | 0.36s（缓存） | 中 | 可能触发 API 数据下载；无网时可能报错或用缓存 |
| `brew services list --json` | 是 | 服务状态 | <1s | 低 | 无服务返回 `[]`；字段固定为 name/status/user/file/exit_code |
| `brew services info --json` | 是 | 单服务详情 | <1s | 低 | 与 list 同源 |
| `brew services <start/stop/restart/run/kill/cleanup>` | 否 | 服务生命周期 | 秒级 | 高 | 影响 launchd，需明确反馈；`kill` 与 `stop` 语义不同 |
| `brew vulns --json` | 是 | OSV.dev 漏洞扫描 | 29.7s / 36 包 | 中 | 覆盖不完整：23 包无 source URL 被跳过、complete=false；发现漏洞时退出码可能为 1 |
| `brew search <text>` | 否 | 名称搜索 | 0.3-1s | 中 | 无 JSON，需解析文本；`--formula/--cask/--desc` |
| `brew desc -s <text>` | 否 | 名称+描述搜索 | 首次慢、后续快 | 中 | 首次建缓存；文本解析 |
| `brew leaves` | 否 | 顶层包 | <1s | 低 | 一行一个；可识别 tap 形式（如 `user/tap/formula`） |
| `brew deps --tree/--installed` | 否 | 依赖树 | <1s | 低 | 无 JSON；`--json` 不存在（已确认） |
| `brew uses --installed <formula>` | 否 | 被依赖（反向依赖） | 1-3s | 中 | 无 JSON；结果只含已安装包 |
| `brew update` | 否 | 更新 tap/API 元数据 | 数秒-数十秒 | 高 | 网络操作，可能失败；不应在用户无感知时频繁执行 |
| `brew update-if-needed` | 否 | 按需更新 tap/API 元数据 | 需技术验证（索引新鲜时预期很快） | 中 | 能力由 `BrewLocator` 从命令列表探测（`capabilities.updateIfNeeded`）；`BrewClient.updateIfNeeded` 以变更 scope 运行（不注入 `HOMEBREW_NO_AUTO_UPDATE`）、超时 300s；退出码与离线输出需技术验证 |
| `brew install / uninstall / reinstall` | 否 | 变更包 | 秒级-分钟级 | 高 | 流式输出；失败需保留完整日志 |
| `brew upgrade [--dry-run] [--no-ask]` | 否 | 升级 | 秒级-分钟级 | 高 | `--dry-run` 可做预览；批量升级建议逐个执行以便定位失败 |
| `brew pin / unpin` | 否 | 固定版本 | <1s | 低 | 固定后不出现在可更新列表 |
| `brew trust --json=v1` | 是（仅 v1） | 读取 tap/formula/cask/command 信任条目 | <1s | 低（读） | 写入信任为高危动作，GUI 只读展示 |
| `brew cleanup -n` | 否 | 清理预演 | 1-3s | 低 | 先 `-n` 预览，再执行清理 |
| `brew autoremove --dry-run` | 否 | 清理孤立依赖预演 | 1-3s | 中 | 可清理用户不知情的依赖，必须确认 |
| `brew doctor` | 否 | 环境诊断 | 1-5s | 低 | 输出自然语言警告；本机 `--list-checks` 列出 72 项；受限环境下会报目录不可写 |
| `brew missing` | 否 | 缺失依赖检查 | 1-3s | 低 | 有缺失时退出码非 0 |
| `brew log <formula>` | 否 | 变更历史 | 1-3s | 低 | 可做「历史」tab 的 P2 数据源 |
| `brew bundle dump --file=<path>` | 否 | 导出 Brewfile | 1-3s | 低 | 可写文件；注意 tap 与注释格式 |
| `brew bundle install --file=<path>` | 否 | 导入 Brewfile | 分钟级 | 高 | 流式；失败项需逐条呈现 |
| `brew --help` / `brew <cmd> --help` | 否 | 能力探测 | <0.5s | 低 | 用帮助文本判断当前 brew 支持哪些参数 |

### 2.1 不可用/需注意的命令

- `brew search --json`、`brew services list --json` 之外的 `--json` 不要臆造；UI 不得暴露不存在的开关。
- `brew deps --json` 不存在；依赖图只能解析文本或基于 `info --json` 的 `dependencies` / `installed[].runtime_dependencies` 自建。
- `brew update` 不是只读命令：可能触发迁移与大量网络请求，应放在显式的「检查更新」动作里。
- **「检查更新」命令序列（2026-11-07 用户决策，UX 方案 O-01）**：手动检查（⌘R / 按钮 / 命令面板 / 菜单栏）= ① `brew update-if-needed`，作为变更任务进入 `TaskQueueStore` 串行队列，去重键 `updateIndex`；② 无论 ① 成功与否，接着跑只读 `brew outdated --json=v2`。① 失败、超时、被取消，或 brew 不支持 `update-if-needed` 时，② 照常执行，界面标注「基于本地索引」，不自动重试。**自动检查（24h 定时器）只跑 ②**，不在用户无感知时联网更新索引。界面区分两个时间：上游索引同步时间（① 最近一次成功）与本机检查时间（② 最近一次成功）。
- `brew vulns` 仅扫描 formula，**不扫描 cask**；扫描覆盖不完整时必须如实标注。
- `brew pin`：7.0.12 实测 `--formula` 与 `--cask` 均受支持（`brew pin --help` 含 `--cask`，并提示 auto_updates 应用可能自行更新）；cask 锁定在 GUI 中已启用，文案保留该例外。
- 抑制类环境变量（`HOMEBREW_NO_AUTO_UPDATE`、`HOMEBREW_NO_INSTALL_CLEANUP`、`HOMEBREW_NO_ENV_HINTS` 及 `HOMEBREW_ALLOW_*`）通过 `BrewEnvironment` 白名单注入、诊断包可见；界面开关默认关闭，开启需说明后果。
- `brew tap-info --json` 的信任/来源字段未在本机确认，GUI 的 tap 信任区按「只读 + 复制 `brew trust` 命令」处理，字段口径标注「需技术验证」，不臆造解析。
- `brew upgrade --dry-run` 为只读预览（不进变更队列、不写日志）；输出可能因依赖解析或 auto_updates 与真实执行不同，界面必须标注。

## 3. JSON 数据模型摘要

### 3.1 `brew info --json=v2 --installed`

顶层：`{ formulae: [...], casks: [...] }`。

formula 关键字段（实测 59 个包的稳定字段）：

```json
{
  "name": "aom",
  "full_name": "aom",
  "tap": "homebrew/core",
  "desc": "Codec library for encoding and decoding AV1 video streams",
  "license": "BSD-2-Clause",
  "homepage": "https://aomedia.googlesource.com/aom",
  "versions": { "stable": "3.15.2", "head": "HEAD", "bottle": true },
  "installed": [{
    "version": "3.14.1",
    "time": 1780037178,
    "installed_on_request": false,
    "built_as_bottle": true,
    "poured_from_bottle": true,
    "runtime_dependencies": [
      { "full_name": "libvmaf", "version": "3.1.0", "revision": 0,
        "bottle_rebuild": 0, "pkg_version": "3.1.0", "declared_directly": true }
    ]
  }],
  "dependencies": ["libvmaf"],
  "keg_only": false,
  "outdated": true,
  "pinned": false,
  "caveats": null,
  "service": null
}
```

要点：

- 展示版本用 `installed[].version`，最新版用 `versions.stable`；是否可更新以 `outdated` 或 `outdated --json` 为准（两者可能因缓存时序不同而短暂不一致）。
- `installed[].time` 为 Unix 时间戳，用于「安装时间」排序。
- `installed_on_request=false` 表示作为依赖被装上，可用于「自动安装的依赖」分组与清理建议。
- `runtime_dependencies` 是实际运行时依赖（含版本）；`dependencies` 是声明依赖（不含版本）。两者都可用于依赖 tab，但要标注差异。
- `service` 字段存在但未安装服务的包通常为 null；服务是否存在应以 `services list --json` 为准。
- 大小不在 JSON 中：需对 `$(brew --cellar)/<name>/<version>` 计算 `du -sk`（本机 Cellar 总量 1.1 GB，aom 约 10.4 MB）。建议懒加载 + 缓存 5 分钟，避免主线程阻塞。

### 3.2 `brew outdated --json=v2`

```json
{
  "formulae": [{
    "name": "aom",
    "installed_versions": ["3.14.1"],
    "current_version": "3.15.2",
    "pinned": false,
    "pinned_version": null
  }],
  "casks": []
}
```

- 该命令可能触发 `Downloading Homebrew API data`；离线/无缓存时会有错误输出，但仍可能返回缓存结果。
- 先 `brew update` 再 `outdated` 结果最准；应用里应区分「本机已知的可更新」与「刚检查过的可更新」。

### 3.3 `brew services list --json`

源码（`services/subcommand/list.rb`）明确字段：`JSON_FIELDS = [:name, :status, :user, :file, :exit_code]`。

```json
[{ "name": "nginx", "status": "started", "user": "yunliang",
   "file": "/Users/yunliang/Library/LaunchAgents/homebrew.mxcl.nginx.plist",
   "exit_code": 0 }]
```

- 无服务时返回 `[]`（本机实测）。
- status 语义以 brew 输出为准（常见：started / stopped / error / none / scheduled 等），UI 不应硬编码为只有两态。
- `brew services info <name> --json` 可获取单服务详情。

### 3.4 `brew vulns --json`

```json
{
  "findings": [{
    "formula": "libheif",
    "version": "1.22.2",
    "tag": "v1.22.2",
    "repo_url": "https://github.com/strukturag/libheif",
    "vulnerabilities": [{
      "id": "CVE-2026-50142",
      "severity": "HIGH",
      "summary": "libheif: unbounded heap allocation ...",
      "aliases": ["GHSA-jvmp-j3cw-84mh"],
      "fixed_versions": ["bd114ed6...", "a6caa38f..."]
    }]
  }],
  "skipped_formulae": ["libtiff"],
  "checked": 36,
  "complete": false,
  "outdated_without_sbom": [],
  "unscanned_formulae": { "oh-my-posh": "untrusted_tap" }
}
```

- 数据来自 OSV.dev，需要网络；本机 36 包耗时约 29.7s，23 包被跳过（无支持的 source URL），`complete=false`。
- **实测发现漏洞时进程退出码为 1**。不能把非 0 当失败；以能否解析出 JSON 判断。
- 只有 formula 被扫描，cask 不在范围内；`unscanned_formulae` 与 `skipped_formulae` 必须在 UI 中如实呈现（「部分覆盖」）。
- 建议：后台扫描 + 结果缓存（例如 24h）+ 手动刷新；不要阻塞启动，也不要每次启动全量扫描。

### 3.5 Cask 字段（`brew info --json=v2 --cask <token>`）

关键字段：`token / full_token / name[] / desc / version / installed / installed_time / outdated / pinned / tap / homepage / url / artifacts / depends_on / caveats`。

- `installed` 在未安装时为 null；已安装 cask 的版本与时间用于列表展示。
- `artifacts` 包含 `app`、`uninstall`、`zap` 等安装物信息，可用于「卸载将删除什么」的可视化。
- cask 列表不能靠 `info --installed --cask`（本机返回空数组且无 cask 安装）；用 `brew list --cask`（文本）或 `brew info --json=v2 --cask <token>` 逐个补全。

## 4. 进程执行层设计约束

### 4.1 启动方式

- 用 `Process` 直接 exec brew 绝对路径，`arguments` 传数组；禁止 `/bin/sh -c` 拼接。
- 先探测 brew 路径（见 §5），再把其所在 bin 目录放进子进程 `PATH`。
- 环境变量建议（均为已验证存在的开关）：
  - `HOMEBREW_NO_AUTO_UPDATE=1`：读命令不隐式更新。
  - `HOMEBREW_NO_INSTALL_CLEANUP=1`：升级后不自动清理，避免不可预期的磁盘操作。
  - `HOMEBREW_NO_ANALYTICS=1`、`HOMEBREW_NO_ENV_HINTS=1`：减少噪声与隐私面。
  - `HOMEBREW_NO_COLOR=1`、`HOMEBREW_NO_EMOJI=1`：简化日志解析与渲染。
  - 谨慎使用 `HOMEBREW_NO_SUDO=1` 与 `HOMEBREW_NO_SANDBOX_CASK=1`：会改变 brew 行为，需对应产品决策。
- 关闭 stdin（给 `/dev/null`），避免 brew 因等待输入而挂起；需要确认的变更操作由应用自己弹窗，再以 `--no-ask` / `--yes` 执行。

### 4.2 输出读取

- 用管道 + `readabilityHandler` / `DispatchIO` 逐行/分块读取 stdout 与 stderr，合并为带通道标记的日志事件。
- Ruby 在非 TTY 下可能全缓冲：推荐伪终端（`openpty` + `posix_spawn`，或用 `script -q /dev/null` 包装）以获得近实时输出；若用管道，至少保证结束时 flush 且不丢尾部错误。
- 解析进度标记（`==>`、`Downloading`、`Pouring`、`Installing`、`Summary`、`Warning:`、`Error:`）生成阶段与进度，但**只做展示**，不据此判断成败；成败以退出码 + JSON/最终文本为准。
- 进度面板解析器为 `BrewProgressParser`（Core/Utilities）：把 `==>` 行映射为展示阶段（Downloading/Fetching → 下载中；Installing/Pouring/Moving/Patching → 安装中；Finishing/Cleaning/Purging/Summary/Caveats → 清理中；Auto-updating/Reading/Refreshing/Checking → 准备中），并从 `==> Upgrading/Installing/Reinstalling <name>` 行提取逐包推进信号。汇总行（`==> Upgrading 2 outdated packages`）、依赖行（`==> Installing dependency: x`）与 `Pouring`（参数是 bottle 文件名）一律不产生包归属。解析失败时 UI 降级为「首个包运行中 + 不定态进度条」，不臆造进度。
- 日志落本地文件（按天滚动、限制大小），UI 展示最近 N 行；导出时脱敏用户主目录路径。

### 4.3 取消与超时

- 变更任务提供取消：发送 SIGINT（brew 可清理中断），3s 未退出再 SIGTERM，累计 7s 发 SIGKILL。超时路径为 SIGTERM → 2s → SIGKILL。
- 对通过包装脚本/PTY 启动的进程，需对**进程组**发送信号（`kill(-pgid, ...)`），避免只杀父进程留下 brew 子进程。
- 只读命令超时（与代码实现一致，`BrewClient`）：`info --json=v2` 30s、`services list` 15s、`outdated` 90s、`vulns` 300s、`search` 60s、`list --versions` 30s；变更类默认 1800s，`cleanup`/`autoremove` 600s，`update` 300s。超时后 UI 给出可重试错误，不静默。

### 4.4 并发与互斥

- 应用内：串行执行队列，变更类任务同时最多 1 个；只读查询可并行但受总并发限制（≤3）。
- 应用间：用 `NSDistributedLock`（放 App Support 目录）防止多实例同时变更；检测失败时提示「另一个 Brewbutler 实例正在执行任务」。
- 与终端里的 brew 并发：brew 自带锁，失败信息需原样展示并给「重试」；不要自动重试超过 2 次。

### 4.5 退出码

- 0 = 成功；非 0 = 失败（例外：`brew vulns` 发现漏洞可能为 1；`brew missing` 有缺失为 1；`brew doctor` 有警告可能为 0）。必须按命令单独定义语义。
- 失败时保留完整 stderr、退出码、命令参数（脱敏后）与时间戳，支持「复制诊断信息」。

## 5. 环境与路径探测

- Finder / LaunchServices 启动的 GUI 进程 `PATH` 通常只有 `/usr/bin:/bin:/usr/sbin:/sbin`，**不包含** `/opt/homebrew/bin`，直接 `Process` 调 `brew` 会失败。
- 探测顺序（结果缓存，设置页可覆盖）：
  1. 用户设置中显式指定的路径；
  2. `/opt/homebrew/bin/brew`、`/usr/local/bin/brew`、`/home/linuxbrew/.linuxbrew/bin/brew`；
  3. `/bin/zsh -lc 'command -v brew'`（超时 3s；输出可能混入 rc 文件噪声，取最后一个绝对路径行）。
- 找到后执行 `brew --prefix` / `brew --version` 确认可执行与版本；把 `<prefix>/bin`、`/usr/bin`、`/bin`、`/usr/sbin`、`/sbin` 传入子进程 `PATH`。
- 常见故障与 UI 文案：未安装 Homebrew、路径不可执行（`EACCES`）、架构不匹配（Rosetta/arm64）、前缀不可写（`Operation not permitted`）、网络不可用。
- 版本能力探测：以 `brew --version` 的主版本号 + `brew <cmd> --help` 是否包含某开关为准，缺失时降级并提示；不要假设所有用户都是 7.x。

## 6. 性能基线与预算

| 场景 | 实测/预算 | 设计目标 |
| --- | --- | --- |
| `info --installed`（59 包） | 0.41s | 冷启动先展示骨架屏，首屏数据 < 1.5s |
| `outdated` | 0.36s（缓存）/ 视网络 | 手动检查 < 5s；超时 60s |
| `services list` | < 1s | 即时刷新 |
| `vulns`（36 包） | 29.7s | 后台执行，可离开页面；结果缓存 24h |
| `search --desc` | 0.35s（缓存）/ 首次较慢 | 300ms 防抖，结果 < 1s |
| 1 万行包表 | 未实测 | `Table`/`List` 懒加载，滚动 60fps，搜索本地过滤 < 100ms |
| 磁盘占用扫描 | Cellar 1.1GB | 后台并发 `du`，10 个包 < 2s，全量 < 15s |

内存与包体：常驻 < 300MB；安装包 < 50MB（不含 Sparkle 更新包）；不做常驻后台扫描。

## 7. 分发、沙盒与安全

### 7.1 为什么不做 Mac App Store

- App Sandbox 下，应用只能写自己的容器；执行 `/opt/homebrew/bin/brew` 后，子进程继承沙盒，brew 无法写 `/opt/homebrew`、`~/Library/Caches/Homebrew` 与 launchd 服务目录，绝大多数安装/升级/服务操作必然失败。
- 临时例外（security-scoped bookmark + 用户授权目录）无法覆盖 Homebrew 的全局写路径与 launchd 操作，体验不可接受。
- 结论：Developer ID 签名 + Hardened Runtime + 公证（`notarytool`）+ DMG/ZIP 直发；可选通过自建 Homebrew tap 或 homebrew-cask 分发（`brew install --cask brewbutler`）。

### 7.2 更新机制

- 直发版本用 Sparkle 2（EdDSA 签名、appcast）；非沙盒应用可正常使用。
- 若同时提供 cask 分发，需检测自身是否由 Homebrew 管理，避免与 `brew upgrade` 冲突；在设置页给出「通过 Homebrew 更新」的说明。
- 不自动下载并执行未签名内容；更新包必须验证签名与 Team ID。

### 7.3 安全清单

- 参数注入：只接受 brew token/已安装包名，正则 `^[A-Za-z0-9@+._/-]+$`，禁止以 `-` 开头、禁止 `..`、长度 ≤ 128；taps 允许 `/` 但需分段校验。任何用户输入都不得进入 shell。
- 危险操作：卸载、`--zap`、`cleanup`、`autoremove`、服务停止必须二次确认，并明确列出影响（文件/服务/依赖）。
- 日志：默认本地存储；导出/反馈前脱敏 home 路径、用户名、token；不采集命令输出到远端。
- 隐私：无账号、无默认遥测；如未来加匿名统计，必须 opt-in 且可关闭。
- 网络：仅访问 brew 自身、formulae.brew.sh、OSV.dev（经 brew）；HTTPS；不做自定义证书绕过。
- 权限：不请求 Full Disk Access；仅当用户主动操作触发权限错误时给出系统设置指引。
- tap 信任：brew 7 的 `brew trust` / untrusted tap 会影响 `vulns` 与安装行为，UI 需解释而不是静默失败。

## 8. 稳定性与解析策略

1. 能用 JSON 的绝不用文本；文本只用于 `search/desc/leaves/deps/uses/doctor/cleanup/doctor/bundle` 等无 JSON 命令。
2. 所有 JSON 解码使用宽容策略：未知字段忽略、可选字段给默认值、记录解码失败样本；避免 brew 升级导致崩溃。
3. 文本解析集中在一个 `BrewTextParser`，每个解析器配真实 fixture 与失败用例；解析失败时降级为「原始输出 + 复制」而不是崩溃。
4. 版本适配：启动时记录 `brew --version`，按能力开关降级；对已知不支持的版本给明确提示。
5. 测试：真实输出 fixture（info/outdated/services/vulns/search/doctor）、10k 合成包性能测试、参数校验 fuzz、进程取消与超时测试、UI 关键路径 UI Test。
6. 观测：本地环形日志 + 「导出诊断包」（版本、brew config、最近任务日志、错误码），不自动上传。

## 9. 已知限制

| 限制 | 影响 | 应对 |
| --- | --- | --- |
| cask 安装/卸载可能触发 sudo 与系统授权 | GUI 无 TTY，可能失败或挂起 | 检测失败并给出「在终端执行」的明确指引；不代理密码 |
| `brew vulns` 覆盖不完整且慢 | 不能承诺「无漏洞」 | 展示 checked/skipped/complete 与扫描时间；支持按 severity 过滤 |
| 搜索无 JSON | 结果可能随版本变化 | 文本解析 + formulae.brew.sh API 兜底 + 缓存 |
| 网络依赖（outdated/vulns/search/install） | 离线时功能受限 | 明确错误态与重试；缓存上次结果并标注时间 |
| brew 输出随版本变化 | 解析回归 | JSON 优先、fixture、快速发版能力 |
| 受限环境写权限不足 | 命令失败（实测 `Operation not permitted`） | 识别错误码，给出修复建议（`brew doctor`、权限修复） |

## 10. 需技术验证清单

| 项 | 原因 | 验证方式 | 影响 |
| --- | --- | --- | --- |
| `brew update-if-needed` 退出码与耗时 | 本机未在可写环境执行；索引新鲜 / 过期 / 离线三种情况下的退出码、输出与耗时未实测 | 用户授权后在三种网络状态下各执行一次并保存 fixture | 「检查更新」第 ① 步的成败判定与进度文案；未验证前按「非 0 即同步失败、照常执行 outdated」处理 |
| `brew vulns` 退出码语义 | 发现漏洞时为 1，需确认是否也受 incomplete 影响 | 构造有/无漏洞与 skipped 场景对比 | 任务成败判定 |
| `brew upgrade` 逐包阶段行格式 | upgrade 是变更命令，本机未真实执行；`==> Upgrading <name>` 的确切写法（是否带版本号 / `Cask` 限定词）未实测 | 用户授权后捕获一次真实 upgrade 输出做 fixture | 进度面板逐包归属；解析失败时已有降级路径（不定态进度），不影响成败判定 |
| 无 TTY 下 brew 进度输出实时性 | Ruby 缓冲策略 | 对比 pipe 与 PTY 的时延 | 日志体验 |
| cask 安装的 sudo 触发条件 | 不同 cask 差异大 | 抽样 10 个 cask 在 GUI 环境安装 | 失败指引 |
| `brew trust` 与 untrusted tap 行为 | brew 7 新机制 | 在测试 tap 上验证 | 安全提示与漏洞扫描覆盖 |
| 10k 包表格性能 | 当前仅 59 包 | 合成数据 + Instruments | 列表架构 |
| 各命令在 Intel/Apple Silicon/Linux 的差异 | 用户环境多样 | CI 矩阵 | 兼容性 |
| Sparkle 与 cask 双分发更新冲突 | 两条更新通道 | 手工升级路径测试 | 更新策略 |

## 11. 参考：真实输出节选

`brew outdated --json=v2`（节选）：

```json
{
  "formulae": [
    { "name": "aom", "installed_versions": ["3.14.1"],
      "current_version": "3.15.2", "pinned": false, "pinned_version": null }
  ],
  "casks": []
}
```

`brew list --versions --json`（节选，需要 jq）：

```json
{"formulae":[
  {"name":"aom","versions":["3.14.1"],"linked_version":"3.14.1",
   "optlinked_version":"3.14.1","pinned_version":null}
]}
```

`brew services list --json`（无服务时）：

```json
[]
```

## 12. 文档交叉对齐记录（2026-10-23）

| 决策 | 结论 | 落点 |
| --- | --- | --- |
| 包详情结构 | 主区 6 tabs（概览/安全/依赖/被依赖/文件/历史）+ 右侧固定 inspector | PRD §6、UI 文档 §4.5/§10 |
| 状态词表 | 未安装 / 已安装 / 可更新 / 已是最新 / 已锁定 / 有已知漏洞 / 已废弃 / 扫描未知 / 部分覆盖 | PRD §6、UI 文档 §6/§10 |
| 术语大小写 | formula / cask / tap / keg-only / Bottle / Brewfile 保留英文小写 | PRD §6、UI 文档 §6 |
| 遥测 | v1.0 默认关闭且不提供开启入口；L2 若启用须显式 opt-in 并单独评审 | PRD F13.3、UI 文档 §4.8 |
| 演示数据 | 原型中的包版本、CVE、cask、服务为演示补全；本机实测 59 formula / 0 cask / 0 service | UI 文档 §0 |

---

**维护约定**：任何实现阶段确认/推翻的事实，更新本文并在 PRD 的「技术方案要点」与 UI 文档的「状态与限制」中同步；本文件为单一事实来源。
