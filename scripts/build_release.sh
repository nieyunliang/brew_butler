#!/bin/bash
#
# Brewbutler 发布打包脚本
# 生成：dist/Brewbutler-<版本>.dmg、dist/Brewbutler-<版本>.pkg、dist/Brewbutler-<版本>.zip、dist/SHA256SUMS
#
# 用法：
#   ./scripts/build_release.sh              # 完整构建 + 打包
#   ./scripts/build_release.sh --skip-dmg   # 跳过 DMG（例如在无挂载权限的沙箱中）
#   ./scripts/build_release.sh --clean      # 清空 DerivedData 后重新构建
#
# 说明：
# - 本机没有 Developer ID 证书，默认使用 ad-hoc 签名（SIGN_IDENTITY=-），产物未公证。
#   如果以后拿到 Developer ID Application 证书：
#     SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM=TEAMID ./scripts/build_release.sh
#   并另行执行 notarytool/stapler 流程。
# - 构建参数 -disable-sandbox 用于允许 Swift 宏插件在受限沙箱中运行；对产物没有影响。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---------- 参数 ----------
DO_DMG=1
DO_PKG=1
DO_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --skip-dmg) DO_DMG=0 ;;
    --skip-pkg) DO_PKG=0 ;;
    --clean)    DO_CLEAN=1 ;;
    -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
    *)          echo "未知参数：$arg（使用 --help 查看用法）" >&2; exit 2 ;;
  esac
done

# ---------- 版本信息 ----------
VERSION="${VERSION:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' Brewbutler.xcodeproj/project.pbxproj | head -1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' Brewbutler.xcodeproj/project.pbxproj | head -1)}"
BUNDLE_ID="${BUNDLE_ID:-com.brewbutler.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TEAM="${TEAM:-}"

: "${VERSION:?无法从工程读取 MARKETING_VERSION}"
: "${BUILD_NUMBER:?无法从工程读取 CURRENT_PROJECT_VERSION}"

BUILD_DIR="$ROOT/build/release"
DERIVED_DATA="$BUILD_DIR/DerivedData"
TMP_DIR="$BUILD_DIR/tmp"
MODULE_CACHE="$BUILD_DIR/modulecache"
ARCHIVE="$BUILD_DIR/Brewbutler.xcarchive"
APP="$ARCHIVE/Products/Applications/Brewbutler.app"
STAGE="$BUILD_DIR/dmg-stage"
PKG_ROOT="$BUILD_DIR/pkg-root"
DIST="$ROOT/dist"
DMG="$DIST/Brewbutler-$VERSION.dmg"
PKG="$DIST/Brewbutler-$VERSION.pkg"
ZIP="$DIST/Brewbutler-$VERSION.zip"

# 防止误删：所有清理路径必须在工程目录内
case "$BUILD_DIR" in "$ROOT"/build/release) ;; *) echo "内部错误：不安全的构建目录 $BUILD_DIR" >&2; exit 1 ;; esac

echo "== Brewbutler 发布构建 =="
echo "   版本：$VERSION ($BUILD_NUMBER)  Bundle ID：$BUNDLE_ID"
echo "   签名：$SIGN_IDENTITY${TEAM:+ (Team $TEAM)}"
echo "   输出：$DIST"

mkdir -p "$BUILD_DIR" "$TMP_DIR" "$MODULE_CACHE" "$DIST"

if [ "$DO_CLEAN" = "1" ]; then
  echo "== 清理旧的构建产物 =="
  rm -rf "$DERIVED_DATA" "$ARCHIVE"
fi

# ---------- 1. Archive ----------
echo "== [1/5] xcodebuild archive =="
rm -rf "$ARCHIVE"
mkdir -p "$TMP_DIR"
ARCHIVE_LOG="$BUILD_DIR/archive.log"
if ! TMPDIR="$TMP_DIR" xcodebuild \
  -project Brewbutler.xcodeproj \
  -scheme Brewbutler \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MODULE_CACHE_DIR="$MODULE_CACHE" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  archive > "$ARCHIVE_LOG" 2>&1; then
  echo "!! archive 失败，日志末尾：" >&2
  tail -40 "$ARCHIVE_LOG" >&2
  exit 1
fi
echo "   archive 成功：$ARCHIVE"

# ---------- 2. 产物自检 ----------
echo "== [2/5] 校验 .app =="
[ -d "$APP" ] || { echo "!! 未找到 $APP" >&2; exit 1; }
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
GOT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
GOT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[ "$GOT_ID" = "$BUNDLE_ID" ] || { echo "!! Bundle ID 不符：$GOT_ID != $BUNDLE_ID" >&2; exit 1; }
[ "$GOT_VER" = "$VERSION" ] || { echo "!! 版本不符：$GOT_VER != $VERSION" >&2; exit 1; }
[ "$GOT_BUILD" = "$BUILD_NUMBER" ] || { echo "!! Build 号不符：$GOT_BUILD != $BUILD_NUMBER" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
echo "   Info.plist：$GOT_ID $GOT_VER ($GOT_BUILD)，签名有效"

# ---------- 3. DMG ----------
if [ "$DO_DMG" = "1" ]; then
  echo "== [3/5] 制作 DMG =="
  rm -rf "$STAGE" "$BUILD_DIR/mnt"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Brewbutler.app"
  xattr -cr "$STAGE/Brewbutler.app" 2>/dev/null || true
  ln -sfn /Applications "$STAGE/Applications"
  cat > "$STAGE/安装说明.txt" <<EOF
Brewbutler $VERSION

安装：把 Brewbutler.app 拖到右侧的「应用程序」文件夹。
首次打开：如果系统提示「无法验证开发者」，请在「应用程序」中右键 Brewbutler.app → 打开。
系统要求：macOS 27 或更高版本（Apple 芯片）。
需要先安装 Homebrew（https://brew.sh）。

校验和见发布目录中的 SHA256SUMS 文件。
更多说明见发行包文档 INSTALL.md / RELEASE_NOTES.md。
EOF
  rm -f "$DMG"
  if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "Brewbutler $VERSION" "$STAGE" "$DMG"
  else
    hdiutil create -volname "Brewbutler $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  fi
  [ -f "$DMG" ] || { echo "!! DMG 创建失败" >&2; exit 1; }
  echo "   $DMG ($(du -h "$DMG" | cut -f1))"

  # 挂载校验（无挂载权限的环境会跳过，不视为失败）
  if [ "${VERIFY_DMG:-1}" = "1" ]; then
    MNT="$BUILD_DIR/mnt"
    mkdir -p "$MNT"
    if diskutil image attach --readOnly --nobrowse --mountPoint "$MNT" "$DMG" >/dev/null 2>&1; then
      test -d "$MNT/Brewbutler.app" || { echo "!! DMG 内缺少 Brewbutler.app" >&2; diskutil eject "$MNT" >/dev/null 2>&1 || true; exit 1; }
      test -L "$MNT/Applications" || { echo "!! DMG 内缺少 Applications 链接" >&2; diskutil eject "$MNT" >/dev/null 2>&1 || true; exit 1; }
      codesign --verify --deep --strict "$MNT/Brewbutler.app"
      echo "   DMG 挂载校验通过（内含 .app 与 Applications 链接，签名有效）"
      diskutil eject "$MNT" >/dev/null 2>&1 || umount "$MNT" 2>/dev/null || true
    else
      echo "   警告：当前环境无挂载权限，跳过 DMG 挂载校验（产物已生成）"
    fi
  fi
else
  echo "== [3/5] 跳过 DMG =="
fi

# ---------- 4. PKG ----------
if [ "$DO_PKG" = "1" ]; then
  echo "== [4/5] 制作 PKG =="
  rm -rf "$PKG_ROOT"
  mkdir -p "$PKG_ROOT"
  ditto "$APP" "$PKG_ROOT/Brewbutler.app"
  rm -f "$PKG"
  pkgbuild \
    --root "$PKG_ROOT" \
    --install-location /Applications \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --ownership recommended \
    "$PKG"
  [ -f "$PKG" ] || { echo "!! PKG 创建失败" >&2; exit 1; }
  pkgutil --payload-files "$PKG" >/dev/null
  echo "   $PKG ($(du -h "$PKG" | cut -f1))"
else
  echo "== [4/5] 跳过 PKG =="
fi

# ---------- 5. ZIP + 校验和 + 构建信息 ----------
echo "== [5/5] ZIP / 校验和 =="
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "   $ZIP ($(du -h "$ZIP" | cut -f1))"

CHECKSUMS=()
[ -f "$DMG" ] && CHECKSUMS+=("$(basename "$DMG")")
[ -f "$PKG" ] && CHECKSUMS+=("$(basename "$PKG")")
[ -f "$ZIP" ] && CHECKSUMS+=("$(basename "$ZIP")")
( cd "$DIST" && shasum -a 256 "${CHECKSUMS[@]}" > SHA256SUMS )
echo "   $DIST/SHA256SUMS"

{
  echo "Brewbutler $VERSION ($BUILD_NUMBER)"
  echo "Bundle ID: $BUNDLE_ID"
  echo "构建时间: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "构建主机: $(uname -m) $(sw_vers -productVersion)"
  echo "Xcode: $(xcodebuild -version 2>/dev/null | head -1)"
  echo "签名: $SIGN_IDENTITY${TEAM:+ (Team $TEAM)}"
  echo "公证: 否（无 Developer ID 证书）"
  echo "系统要求: macOS 27+ (arm64)"
  echo
  echo "产物:"
  for f in "$DMG" "$PKG" "$ZIP"; do
    [ -f "$f" ] && echo "  $(basename "$f")  $(du -h "$f" | cut -f1)  $(shasum -a 256 "$f" | cut -d' ' -f1)"
  done
} > "$DIST/BUILD-INFO.txt"

echo
echo "== 完成 =="
ls -lh "$DIST"
