#!/bin/bash
#
# Brewbutler 只构建 .app 的脚本（不生成 DMG / PKG / ZIP）
#
# 产物：build/app/Brewbutler.app（以及 build/app/<Config>/Brewbutler.app）
#
# 用法：
#   ./scripts/build_app.sh                  # Release 构建，产物在 build/app/Brewbutler.app
#   ./scripts/build_app.sh --debug          # Debug 构建
#   ./scripts/build_app.sh --run            # 构建完成后直接启动
#   ./scripts/build_app.sh --clean          # 先清空本脚本使用的 DerivedData
#   ./scripts/build_app.sh --sign "Developer ID Application: Name (TEAMID)" --team TEAMID
#   ./scripts/build_app.sh --verbose        # 实时打印 xcodebuild 输出
#
# 说明：
# - 默认 ad-hoc 签名（CODE_SIGN_IDENTITY=-），本机无 Developer ID 证书；仅本机运行足够。
# - DerivedData / 宏插件缓存都放在仓库内 build/ 下：默认 ~/Library/Developer/Xcode/DerivedData
#   在受限沙箱里不可写。
# - -disable-sandbox 让 Swift 宏插件在沙箱环境中可运行，不改变产物行为。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---------- 参数 ----------
CONFIG="${CONFIG:-Release}"
DO_CLEAN=0
DO_RUN=0
DO_OPEN_DIR=0
VERBOSE=0
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TEAM="${TEAM:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)      CONFIG="Debug" ;;
    --release)    CONFIG="Release" ;;
    --config)     shift; CONFIG="${1:?--config 需要一个值（Debug 或 Release）}" ;;
    --clean)      DO_CLEAN=1 ;;
    --run)        DO_RUN=1 ;;
    --open-dir)   DO_OPEN_DIR=1 ;;
    --verbose)    VERBOSE=1 ;;
    --sign)       shift; SIGN_IDENTITY="${1:?--sign 需要一个签名标识}" ;;
    --team)       shift; TEAM="${1:-}" ;;
    -h|--help)    sed -n "2,24p" "$0"; exit 0 ;;
    *) echo "未知参数：$1（使用 --help 查看用法）" >&2; exit 2 ;;
  esac
  shift
done

case "${CONFIG}" in
  Debug|Release) ;;
  *) echo "不支持的构建配置：${CONFIG}（只支持 Debug / Release）" >&2; exit 2 ;;
esac

# ---------- 版本信息（可被环境变量覆盖） ----------
VERSION="${VERSION:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' Brewbutler.xcodeproj/project.pbxproj | head -1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' Brewbutler.xcodeproj/project.pbxproj | head -1)}"
BUNDLE_ID="${BUNDLE_ID:-com.brewbutler.app}"

: "${VERSION:?无法从工程读取 MARKETING_VERSION}"
: "${BUILD_NUMBER:?无法从工程读取 CURRENT_PROJECT_VERSION}"

# ---------- 路径（全部在仓库内，避免写入只读的默认 DerivedData） ----------
BUILD_DIR="${ROOT}/build/app-build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
TMP_DIR="${BUILD_DIR}/tmp"
MODULE_CACHE="${BUILD_DIR}/modulecache"
LOG_DIR="${BUILD_DIR}/logs"
LOG_FILE="${LOG_DIR}/build-app-${CONFIG}.log"
OUT_DIR="${ROOT}/build/app"
PRODUCT_APP="${DERIVED_DATA}/Build/Products/${CONFIG}/Brewbutler.app"
FINAL_APP="${OUT_DIR}/Brewbutler.app"
CONFIG_APP="${OUT_DIR}/${CONFIG}/Brewbutler.app"

# 防止误删：所有清理路径必须在仓库内
case "${BUILD_DIR}" in "${ROOT}"/build/app-build) ;; *) echo "内部错误：不安全的构建目录 ${BUILD_DIR}" >&2; exit 1 ;; esac
case "${OUT_DIR}" in "${ROOT}"/build/app) ;; *) echo "内部错误：不安全的输出目录 ${OUT_DIR}" >&2; exit 1 ;; esac

mkdir -p "${BUILD_DIR}" "${TMP_DIR}" "${MODULE_CACHE}" "${LOG_DIR}" "${OUT_DIR}"

echo "== Brewbutler 构建（仅 .app） =="
echo "   配置：${CONFIG}"
echo "   版本：${VERSION} (${BUILD_NUMBER})  Bundle ID：${BUNDLE_ID}"
echo "   签名：${SIGN_IDENTITY}${TEAM:+ (Team ${TEAM})}"
echo "   输出：${FINAL_APP}"

if [ "${DO_CLEAN}" = "1" ]; then
  echo "== 清理旧的构建目录 =="
  rm -rf "${DERIVED_DATA}"
fi

# ---------- 构建 ----------
echo "== xcodebuild build =="
if [ "${VERBOSE}" = "1" ]; then
  BUILD_STDOUT="/dev/stdout"
else
  BUILD_STDOUT="${LOG_FILE}"
fi

# 注意：这里只 build，不 archive，也不做 DMG/PKG。
if ! TMPDIR="${TMP_DIR}" xcodebuild \
  -project Brewbutler.xcodeproj \
  -scheme Brewbutler \
  -configuration "${CONFIG}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  DEVELOPMENT_TEAM="${TEAM}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MODULE_CACHE_DIR="${MODULE_CACHE}" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  build > "${BUILD_STDOUT}" 2>&1; then
  echo "!! 构建失败。日志末尾（完整日志：${LOG_FILE}）：" >&2
  tail -40 "${LOG_FILE}" >&2 2>/dev/null || true
  exit 1
fi
echo "   构建成功"

# ---------- 校验 ----------
echo "== 校验 .app =="
[ -d "${PRODUCT_APP}" ] || { echo "!! 未找到产物 ${PRODUCT_APP}（日志：${LOG_FILE}）" >&2; exit 1; }
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PRODUCT_APP}/Contents/Info.plist")"
GOT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PRODUCT_APP}/Contents/Info.plist")"
[ "${GOT_ID}" = "${BUNDLE_ID}" ] || { echo "!! Bundle ID 不符：${GOT_ID} != ${BUNDLE_ID}" >&2; exit 1; }
[ "${GOT_VER}" = "${VERSION}" ] || { echo "!! 版本不符：${GOT_VER} != ${VERSION}" >&2; exit 1; }
codesign --verify --deep --strict "${PRODUCT_APP}"
ARCHS_OUT="$(lipo -archs "${PRODUCT_APP}/Contents/MacOS/Brewbutler" 2>/dev/null || echo unknown)"
echo "   ${GOT_ID} ${GOT_VER}；签名有效；架构 ${ARCHS_OUT}"

# ---------- 导出到固定路径 ----------
echo "== 导出产物 =="
rm -rf "${CONFIG_APP}" "${FINAL_APP}"
mkdir -p "$(dirname "${CONFIG_APP}")"
ditto "${PRODUCT_APP}" "${CONFIG_APP}"
xattr -cr "${CONFIG_APP}" 2>/dev/null || true
ditto "${PRODUCT_APP}" "${FINAL_APP}"
xattr -cr "${FINAL_APP}" 2>/dev/null || true
codesign --verify --deep --strict "${FINAL_APP}"
SIZE_OUT="$(du -sh "${FINAL_APP}" | cut -f1)"
echo "   ${FINAL_APP}  (${SIZE_OUT})"

if [ "${DO_RUN}" = "1" ]; then
  echo "== 启动 =="
  open "${FINAL_APP}"
  echo "   已启动：${FINAL_APP}"
fi

if [ "${DO_OPEN_DIR}" = "1" ]; then
  open -R "${FINAL_APP}"
fi

# 构建日志保留在 build/ 下，不随产物分发
if [ -f "${LOG_FILE}" ]; then echo "   构建日志：${LOG_FILE}"; fi

echo "== 完成 =="
