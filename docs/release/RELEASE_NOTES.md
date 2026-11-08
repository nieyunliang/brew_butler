# Brewbutler v1.0 发布说明

| 项目 | 内容 |
| --- | --- |
| 版本 | v1.0（Build 1） |
| 发布日期 | 2026-10-23 |
| 平台 | macOS 27+（部署目标 27.0），Apple 芯片（arm64） |
| Bundle ID | `com.brewbutler.app` |
| 显示名 | Brewbutler |
| 安装包 | `dist/Brewbutler-1.0.dmg`（DMG，推荐）、`dist/Brewbutler-1.0.pkg`（PKG）、`dist/Brewbutler-1.0.zip`（ZIP，备用） |
| 校验和 | `dist/SHA256SUMS` |
| 签名状态 | ad-hoc 签名；未使用 Developer ID，未公证 |

## 一句话定位

Brewbutler 是 macOS 27+ 的原生 Homebrew 可视化管理器：把「装了什么、能不能安全地更新、占了多少空间、谁依赖谁」变成一眼可见、可取消、可追溯的操作。它不是 brew 命令的按钮外壳，界面数据全部来自本机 Homebrew。

## 本版亮点

### 首次启动与环境

- 自动定位 brew：依次探测 `/opt/homebrew/bin/brew`、`/usr/local/bin/brew`、`/home/linuxbrew/.linuxbrew/bin/brew`，再用登录 shell 兜底；失败可在设置中手动指定并校验。
- 未安装 Homebrew 时给出安装指引与可复制命令；Brewbutler 不代为执行安装脚本。
- 首次启动引导依次完成 Homebrew 检测、已安装包索引与隐私说明。

### 仪表盘与已安装

- 仪表盘聚合 Homebrew 健康度、可更新数、漏洞状态、磁盘占用、服务状态与最近操作。
- 已安装页列出全部 formula / cask，含版本、tap 与状态徽标；支持按类型（formula / cask）、状态（可更新 / 已锁定 / 有漏洞 / 手动安装 / keg-only）筛选，按名称、体积、安装时间、状态排序，本地即时过滤与多选批量操作。
- 体积与磁盘占用在后台计算，未完成时显示占位，不阻塞列表。

### 包详情

- 主区 6 个标签页：概览、安全、依赖、被依赖、文件、历史；右侧 inspector 固定显示操作、概要、健康、路径、被依赖与危险区。
- 概览含版本、tap、license、描述、主页、安装时间与 caveats 原文；依赖 / 被依赖可跳转；可查看安装路径与文件列表；可锁定 / 解锁、卸载、打开主页、复制路径。
- 卸载前展示反向依赖；「删除关联文件」（对应 `--zap` 语义）需输入包名确认，并明确提示会删除偏好与配置等关联文件。

### 更新

- 更新页汇总可更新项，区分 formula / cask 与安全更新，支持单个、批量、全部升级；已锁定的包会被跳过并计数。
- 所有变更任务走串行队列（同一时刻仅 1 个），其余显示「排队中」；任务可随时取消，取消按 SIGINT → SIGTERM → SIGKILL 分级。
- 日志抽屉展示完整原始命令与流式输出，错误行高亮；失败时给出退出码、关键错误行与建议动作，不自动回滚。
- 批量操作结束给出「成功 / 失败 / 已取消 / 未确认 / 已跳过」汇总，失败项可逐个重试。

### 安全（漏洞可见性）

- 基于 `brew vulns --json`（OSV.dev 数据）在后台扫描已安装 formula，不阻塞界面、可取消；结果缓存并显示扫描时间。
- 展示漏洞严重度、CVE / GHSA 别名与修复版本，可跳转 OSV 查看详情，并按「有修复 / 无修复」筛选。
- 强制展示覆盖范围：检查数、跳过的包及原因、未扫描的包与 `complete` 状态；扫描失败显示「未知」而不是「安全」。
- `brew vulns` 发现漏洞时退出码为 1 属预期行为，界面不会当作任务失败。

### 发现、服务与维护

- 发现页按关键词搜索 formula 与 cask（含描述搜索），可直接查看详情并安装。
- 服务页读取 `brew services list --json`，支持启动、停止、重启，操作后复查状态；空状态给出明确文案。
- 维护页提供：清理预览（`brew cleanup -n`）与执行、孤立依赖预览（`brew autoremove --dry-run`）与执行、`brew doctor` 健康检查（目录权限不足单独识别并给修复建议）、`brew missing` 缺失依赖检查、Brewfile 导出 / 导入、已锁定包列表与 Homebrew 目录概览。

### 全局入口与设置

- ⌘1–⌘7 切换一级导航；⌘K 命令面板可跳页面、跳包或执行操作，危险操作二次确认。
- 菜单栏常驻项显示可更新数与漏洞提示，提供检查更新、运行扫描、打开主窗口与最近任务入口（可在设置中关闭）。
- 设置项包括 brew 路径、代理与 API / Bottle 镜像、通知、主题（跟随系统 / 浅色 / 深色）、日志保留天数、诊断包导出、清除全部本地缓存、本地使用统计查看与清除。

### 隐私

- 无账号、无自建后端；v1.0 不启用遥测，也不提供开启入口。
- 不采集、不上传包列表、命令输出或环境信息；缓存与任务日志只保存在本机。
- 导出的诊断包不含包列表、命令输出、用户名或代理凭据。

## 安装包与校验和

| 文件 | 用途 | 大小 |
| --- | --- | --- |
| `dist/Brewbutler-1.0.dmg` | 拖拽安装到 `/Applications`（推荐） | 约 1.4 MB |
| `dist/Brewbutler-1.0.pkg` | 安装器安装到 `/Applications` | 约 1.4 MB |
| `dist/Brewbutler-1.0.zip` | 解压后把 Brewbutler.app 拖入 `/Applications`（备用） | 约 1.4 MB |
| `dist/SHA256SUMS` | 上述三个产物的 SHA-256 校验和（共 3 行） | — |

校验命令（`SHA256SUMS` 记录的是相对文件名，需在 `dist/` 目录内执行）：

```bash
cd dist
shasum -a 256 -c SHA256SUMS
```

三个文件都输出 `OK` 即通过；某一项 `FAILED` 请重新获取该文件。本说明不写死哈希值，一律以 `SHA256SUMS` 与实际产物为准。

安装、首次启动与卸载的完整步骤见 [INSTALL.md](INSTALL.md)。

## 系统要求

- macOS 27.0 或更高版本。
- Apple 芯片（arm64）。
- 已安装 Homebrew。应用会自动定位 brew（默认 `/opt/homebrew/bin/brew`，也可在设置中手动指定），并需要能够执行 brew、读写 Homebrew 目录。
- 应用不使用 App Sandbox，因此不会以 Mac App Store 形式分发：沙盒内无法执行 brew，也无法写入 `/opt/homebrew` 或读写 launchd 配置。

## 签名与公证说明

- 构建机只有 Apple Development 证书、没有 Developer ID，因此发布产物为 **ad-hoc 签名**：**未使用 Developer ID 签名，也未公证（notarized）**。
- 本机构建与安装可直接运行。在其他 Mac 上首次打开需要以下任一操作：
  - 右键（或按住 Control 点按）Brewbutler 图标 → 选择「打开」→ 在弹窗中再次点「打开」；
  - 或在终端执行 `xattr -dr com.apple.quarantine /Applications/Brewbutler.app` 后正常双击。
- Gatekeeper 可能提示「无法验证开发者」或「Apple 无法检查其是否包含恶意软件」。这是未公证产物的预期提示，不代表文件损坏。
- 本机构建并拷贝到本机的产物未带 `com.apple.quarantine` 隔离属性，可直接双击打开；经浏览器、网盘、邮件等下载到其他 Mac 的副本才会被系统附加隔离属性，需要按上述方式放行。
- `codesign --verify --deep --strict /Applications/Brewbutler.app` 应通过；`spctl` 评估会显示 rejected，这也是未公证产物的预期结果。

## 已知限制

| 限制 | 说明 |
| --- | --- |
| cask 安装 / 卸载可能触发 sudo 或系统授权 | 图形界面没有终端，应用不代理密码；失败时给出可在终端执行的命令指引 |
| 漏洞扫描覆盖不完整 | `brew vulns` 只扫描 formula；部分包因缺少 source URL 被跳过、`complete` 可能为 false，因此界面展示覆盖范围，不承诺「无漏洞」 |
| 漏洞扫描较慢 | 本机 36 个包约 29.7 秒；扫描在后台执行、可取消，不阻塞界面 |
| 网络相关命令离线受限 | 检查更新、漏洞扫描、搜索与安装依赖网络；离线时使用缓存并标注时间，或给出可重试的错误 |
| 部分命令无 JSON 输出 | 搜索、`brew doctor`、`brew cleanup` 等依赖文本解析，可能随 brew 版本变化；解析失败降级为原始输出而非崩溃 |
| 变更任务串行 | 同一时刻只执行 1 个变更任务（brew 锁机制要求），其余排队；取消或失败可能已部分完成，应用不会自动回滚 |
| 不提供应用内自动更新 | 升级到后续版本需手动下载并替换应用 |
| 不提供 Mac App Store 版本 | 沙盒限制导致无法执行 brew、无法写入 Homebrew 目录 |
