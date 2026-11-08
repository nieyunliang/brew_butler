# Brewbutler v1.0 安装指南

适用于 macOS 27+（Apple 芯片 / arm64）的 Brewbutler 1.0（Build 1）。

发布产物位于 `dist/`，三种格式任选其一，安装的是同一个应用（Bundle ID `com.brewbutler.app`）：

| 文件 | 用途 | 大小 |
| --- | --- | --- |
| `dist/Brewbutler-1.0.dmg` | 拖拽安装到 `/Applications`（推荐） | 约 1.4 MB |
| `dist/Brewbutler-1.0.pkg` | 安装器安装到 `/Applications` | 约 1.4 MB |
| `dist/Brewbutler-1.0.zip` | 解压后把 Brewbutler.app 拖入 `/Applications`（备用） | 约 1.4 MB |
| `dist/SHA256SUMS` | 上述三个产物的 SHA-256 校验和（共 3 行） | — |

产物为 ad-hoc 签名，**未使用 Developer ID 签名、未公证**，首次打开需要处理 Gatekeeper 提示，见第 6 节。

## 1. 系统要求

- macOS 27.0 或更高版本。
- Apple 芯片（arm64）。
- 已安装 Homebrew。应用会自动定位 brew（默认 `/opt/homebrew/bin/brew`），也需要能够执行 brew、读写 Homebrew 目录。
- 应用不使用 App Sandbox（沙盒内无法执行 brew、无法写入 `/opt/homebrew`），因此只通过 DMG / PKG / ZIP 分发，不提供 Mac App Store 版本。

安装前可在终端快速确认：

```bash
sw_vers --productVersion     # 应为 27.x 或更高
uname -m                     # 应为 arm64
brew --version               # 应能输出版本号
command -v brew              # 常见路径 /opt/homebrew/bin/brew
```

> 从访达（Finder）启动的图形应用默认没有 `/opt/homebrew/bin` 的 PATH，Brewbutler 会自行探测 brew 路径；上面最后两条只是安装前的环境确认。

## 2. 安装前：校验安装包

从发布来源拿到产物与 `SHA256SUMS` 后，先校验完整性。校验和文件中记录的是相对文件名，共 3 行（DMG / PKG / ZIP），需在 `dist/` 目录内执行：

```bash
cd dist
shasum -a 256 -c SHA256SUMS
```

三个文件都输出 `OK` 即通过；某一项输出 `FAILED` 请重新获取对应文件。本指南不写死哈希值，一律以 `SHA256SUMS` 与实际产物为准。

## 3. 方式一：DMG 安装（推荐）

1. 双击 `Brewbutler-1.0.dmg`，等待磁盘映像挂载（卷名为 **Brewbutler 1.0**）。
2. 打开的窗口内有 **Brewbutler.app**、**Applications** 文件夹链接和 **安装说明.txt**；把 **Brewbutler** 拖到 **Applications** 上。
3. 在访达侧边栏点按映像旁的推出按钮（⏏），推出磁盘映像。
4. 打开「应用程序」，双击 Brewbutler（首次打开见第 6 节）。

## 4. 方式二：PKG 安装

1. 双击 `Brewbutler-1.0.pkg`。
2. 按安装器提示点「继续」「安装」，默认安装到 `/Applications`；安装器可能要求输入管理员密码。
3. 安装完成后，从「应用程序」启动 Brewbutler（首次打开见第 6 节）。

## 5. 方式三：ZIP 解压安装（备用）

适用于不便于挂载磁盘映像、或希望直接用归档文件的场景。

1. 双击 `Brewbutler-1.0.zip` 自动解压（或在终端执行 `unzip Brewbutler-1.0.zip`）。
2. 将解压得到的 **Brewbutler.app** 拖到「应用程序」。
3. 从「应用程序」启动 Brewbutler（首次打开见第 6 节）。

解压得到的应用已实测可正常启动并退出。请先把 app 移入「应用程序」再启动，不要长期直接从「下载」或解压目录运行。

> DMG、PKG 与 ZIP 三选一即可。若已安装旧版本，请先退出 Brewbutler 再安装，覆盖后设置与本地数据会保留。

## 6. 首次启动与 Gatekeeper 处理

本版产物为 ad-hoc 签名且未公证。**本机构建并拷贝到本机的产物未带 `com.apple.quarantine` 隔离属性，可直接双击打开**；只有经浏览器、网盘、邮件等途径下载到其他 Mac 的副本，系统才可能附加隔离属性并出现下述提示。

首次打开时，macOS 可能提示：

- 「无法打开 Brewbutler，因为 Apple 无法检查其是否包含恶意软件。」
- 「无法验证开发者。」

这是未公证产物的预期提示，**不代表文件损坏**。按以下任一方式打开：

**方式 A：右键打开（推荐）**

1. 在「应用程序」中右键（或按住 Control 点按）Brewbutler 图标。
2. 选择「打开」。
3. 在随后出现的对话框中再点「打开」。之后可正常双击启动。

**方式 B：系统设置放行**

1. 双击 Brewbutler，出现被阻止提示后点「完成」。
2. 打开「系统设置 → 隐私与安全性」，向下滚动到「安全性」区域。
3. 对「已阻止使用 Brewbutler」点「仍要打开」，并按提示验证（Touch ID / 密码）。

**方式 C：终端清除隔离属性**

```bash
xattr -dr com.apple.quarantine /Applications/Brewbutler.app
```

执行后正常双击启动。该命令只清除下载隔离标记，不修改应用内容。

首次启动后会出现引导：欢迎 → 检测 Homebrew → 扫描已安装的包 → 安全与隐私说明 → 就绪。Homebrew 检测失败不会阻断使用，可稍后在「设置」中手动指定 brew 路径。

## 7. 校验安装结果

```bash
codesign --verify --deep --strict /Applications/Brewbutler.app
codesign -dv --verbose=4 /Applications/Brewbutler.app 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier'
```

- 第一条无输出即签名结构完整（ad-hoc 签名同样可通过）。
- 第二条会显示 `Signature=adhoc`、`TeamIdentifier=not set`，与「未使用 Developer ID」一致。
- `spctl --assess --type execute /Applications/Brewbutler.app` 会显示 rejected，这是未公证产物的预期结果。

## 8. 卸载

1. 退出 Brewbutler：切换到应用后按 ⌘Q；若窗口未在前台，可从菜单栏图标或「活动监视器」退出。
2. 打开「应用程序」，把 **Brewbutler.app** 拖到废纸篓，然后清空废纸篓。
3. PKG 与 ZIP 安装同样用上述方式卸载：PKG 没有独立卸载器，删除应用即完成卸载。

可选：清理应用在本机留下的数据。建议先打开「设置 → 高级 → 清除全部本地缓存」：

```bash
rm -rf ~/Library/Application\ Support/Brewbutler
defaults delete com.brewbutler.app
```

- `~/Library/Application Support/Brewbutler` 保存缓存（`Cache`）与任务日志（`Logs`）。
- `com.brewbutler.app` 是应用的偏好设置域（外观、通知、brew 路径等）。

> 以上只删除 Brewbutler 自身的数据。**卸载 Brewbutler 不会卸载 Homebrew，也不会卸载通过它安装的 formula / cask**；如需清理 Homebrew，请使用 brew 自身命令。

## 9. 从源码构建

需要 macOS 27、Xcode 27（含 macOS 27 SDK）。

**图形界面（推荐）**

1. 用 Xcode 打开仓库根目录的 `Brewbutler.xcodeproj`。
2. 选择 scheme **Brewbutler**，运行目标选 **My Mac**。
3. 按 ⌘R 运行。

工程为 SwiftUI 多平台模板，macOS 部署目标为 27.0；本机运行使用 Apple Development 证书或 ad-hoc 签名即可，不需要 Developer ID。

**命令行归档（可选）**

```bash
xcodebuild -project Brewbutler.xcodeproj -scheme Brewbutler \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -archivePath build/Brewbutler.xcarchive archive
```

本机没有 Developer ID 时，命令行构建若遇到签名或写权限相关错误（例如没有可用证书、DerivedData 目录不可写），改用 Xcode 图形界面构建即可；本版发布产物就是在本机以 ad-hoc 签名方式生成的。仓库提供 `scripts/build_release.sh`，用于按同样方式生成 `dist/` 下的 DMG / PKG / ZIP 与 `SHA256SUMS`。

## 10. 常见问题

**Q1：双击后提示「无法验证开发者」或「Apple 无法检查其是否包含恶意软件」**

按第 6 节的方式 A / B / C 处理。这是未公证产物的正常提示。

**Q2：提示「Brewbutler 已损坏，无法打开」**

通常是下载隔离属性未清除，先执行：

```bash
xattr -dr com.apple.quarantine /Applications/Brewbutler.app
```

仍失败时，重新按第 2 节校验安装包，确认下载完整后再重新安装。

**Q3：应用显示未检测到 Homebrew / 找不到 brew**

1. 在终端确认 `brew --version` 可用，并记录路径（常见为 `/opt/homebrew/bin/brew`，Intel 迁移环境可能为 `/usr/local/bin/brew`）。
2. 打开「设置 → Homebrew → brew 路径」，填写该绝对路径后点「应用」。
3. Homebrew 安装在非标准位置时同样手动指定。Brewbutler 不会代为安装 Homebrew。

**Q4：提示权限不足（Operation not permitted / 目录不可写）**

1. 不要用 `sudo` 启动 Brewbutler，应用不会也不要请求管理员密码。
2. 在终端运行 `brew doctor`，按提示修复 Homebrew 目录所有权或权限。
3. 确认当前用户对 `/opt/homebrew`（或对应 prefix）有读写权限。

**Q5：cask 安装、卸载卡住或提示需要授权**

cask 操作可能触发系统授权，图形界面无法输入密码，Brewbutler 不代理密码。按界面给出的命令在终端执行，例如：

```bash
brew install --cask <token>
```

服务类操作需要 sudo 时同理，应用会给出可复制的终端命令。

**Q6：漏洞扫描显示「部分覆盖」或扫描失败**

`brew vulns` 只扫描 formula，部分包因缺少 source URL 被跳过，`complete` 可能为 false；界面会展示检查数、跳过原因与扫描时间。离线或网络失败时显示「未知」而非「安全」。可稍后重新扫描。

**Q7：检查更新、搜索很慢或失败**

这些功能依赖网络。离线时会使用缓存并标注时间；可在「设置」中检查代理与 API / Bottle 镜像配置，或稍后重试。

**Q8：为什么同时只能执行一个变更任务**

brew 的锁机制不允许安全的并行变更，Brewbutler 固定串行执行，其余任务排队，可随时取消。

**Q9：升级到新版本**

本版不包含应用内自动更新。下载新的 DMG / PKG / ZIP，退出旧版本后按第 3、4、5 节覆盖安装即可；设置与本地数据会保留。

## 11. 安全说明

- **无账号、无自建后端、不启用遥测**：v1.0 不采集也不上传包列表、命令输出或环境信息。
- **命令执行**：应用以参数数组直接调用 brew，不拼接 shell；包名、tap 与镜像 URL 经过校验后才传给 brew。
- **不索取密码**：不代理 sudo、不请求完全磁盘访问权限；仅在用户主动操作触发权限错误时给出系统设置或终端指引。
- **网络范围**：仅 Homebrew 自身、formulae.brew.sh 与 OSV.dev（经 brew）等完成包管理与漏洞查询所需的访问，不做证书绕过。
- **本地数据**：缓存与任务日志保存在 `~/Library/Application Support/Brewbutler`；导出的诊断包不含包列表、命令输出、用户名或代理凭据。
- **完整性校验**：用 `dist/SHA256SUMS` 校验安装包，用 `codesign --verify` 校验安装后的应用。产物为 ad-hoc 签名且未公证，Gatekeeper 的「无法验证开发者」提示属于预期行为。
