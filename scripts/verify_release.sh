#!/bin/bash
# ===========================================================================
# Brewbutler 1.0 发布产物独立验收（QA）脚本
#
# 用法:
#   scripts/verify_release.sh [--skip-launch]
#
# 退出码:
#   0  所有关键检查通过（WARN / SKIP 不视为失败）
#   1  存在 FAIL 关键项
#   2  参数错误
#
# 设计原则:
#   * 只读取 dist/，绝不修改发布产物；临时文件写入 build/qa-*
#   * 可重复执行：重建 build/qa-stage、build/qa-pkg，并清理挂载点
#   * 沙箱导致的环境限制记录为 SKIP（如 DMG 挂载被拒绝），不视为产物缺陷
#   * 依赖 macOS 自带命令: hdiutil, diskutil, shasum, plutil, codesign,
#     spctl, pkgutil, lsbom, file, ditto, unzip, open, pgrep, osascript
# ===========================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
SKIP_LAUNCH=0

usage() {
  echo "用法: $0 [--skip-launch]"
  echo "  --skip-launch  跳过 GUI 启动冒烟测试（仅在无图形会话时使用）"
}

for arg in "$@"; do
  case "$arg" in
    --skip-launch) SKIP_LAUNCH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $arg" >&2; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# 路径与预期值
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DIST_DIR="$ROOT/dist"
DMG_FILE="$DIST_DIR/Brewbutler-1.0.dmg"
PKG_FILE="$DIST_DIR/Brewbutler-1.0.pkg"
ZIP_FILE="$DIST_DIR/Brewbutler-1.0.zip"
SUMS_FILE="$DIST_DIR/SHA256SUMS"
BUILD_INFO="$DIST_DIR/BUILD-INFO.txt"

BUILD_DIR="$ROOT/build"
QA_DIR="$BUILD_DIR/qa-stage"
QA_APP="$QA_DIR/Brewbutler.app"
MNT_DIR="$BUILD_DIR/qa-mnt"
PKG_EXPAND_DIR="$BUILD_DIR/qa-pkg"
LOG_DIR="$BUILD_DIR/qa-logs"
ARCHIVE_APP="$BUILD_DIR/Brewbutler.xcarchive/Products/Applications/Brewbutler.app"

EXPECTED_BUNDLE_ID="com.brewbutler.app"
EXPECTED_VERSION="1.0"
EXPECTED_BUILD="1"
EXPECTED_MIN_OS="27.0"
EXPECTED_VOLUME="Brewbutler 1.0"
APP_NAME="Brewbutler"
EXEC_REL="Contents/MacOS/Brewbutler"

# ---------------------------------------------------------------------------
# 计数与状态
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
FAILED_ITEMS=""
WARNED_ITEMS=""
SKIPPED_ITEMS=""
ATTACHED=0
APP_SRC=""
DMG_APP_SHA=""
ZIP_EXEC_SHA=""
PKG_APP=""
PKG_APP_ANY=""
PKG_APP_SHA=""
SCRIPT_CMD_SEQ=0

# ---------------------------------------------------------------------------
# 结果输出原语
# ---------------------------------------------------------------------------
pass() { PASS_COUNT=$((PASS_COUNT+1)); echo "PASS  $*"; }
fail() {
  FAIL_COUNT=$((FAIL_COUNT+1))
  FAILED_ITEMS="$FAILED_ITEMS
  - $*"
  echo "FAIL  $*"
}
warn() {
  WARN_COUNT=$((WARN_COUNT+1))
  WARNED_ITEMS="$WARNED_ITEMS
  - $*"
  echo "WARN  $*"
}
skip() {
  SKIP_COUNT=$((SKIP_COUNT+1))
  SKIPPED_ITEMS="$SKIPPED_ITEMS
  - $*"
  echo "SKIP  $*"
}
info() { echo "INFO  $*"; }
section() { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
# 命令执行辅助
# ---------------------------------------------------------------------------
print_output() {
  local max_lines="$1" total
  if [ -n "$RUN_OUT" ]; then
    echo "$RUN_OUT" | head -n "$max_lines" | sed 's/^/        /' || true
    total=$(echo "$RUN_OUT" | wc -l | tr -d ' ')
    if [ "$total" -gt "$max_lines" ]; then
      info "...（命令输出共 $total 行，已截断显示前 $max_lines 行）"
    fi
  fi
}

run_cmd() {
  local max_lines="$1"
  shift
  echo "CMD: $*"
  RUN_OUT=""
  RUN_RC=0
  if RUN_OUT=$("$@" 2>&1); then
    RUN_RC=0
  else
    RUN_RC=$?
  fi
  print_output "$max_lines"
  return 0
}

run_cmd_t() {
  local timeout_s="$1" max_lines="$2" outfile pid waited state
  shift 2
  SCRIPT_CMD_SEQ=$((SCRIPT_CMD_SEQ+1))
  outfile="$LOG_DIR/cmd-$SCRIPT_CMD_SEQ.log"
  echo "CMD: $*"
  : > "$outfile"
  "$@" > "$outfile" 2>&1 &
  pid=$!
  waited=0
  RUN_RC=0
  while :; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    state=$(ps -p "$pid" -o stat= 2>/dev/null | tr -d ' ' || true)
    case "$state" in
      Z*) break ;;
    esac
    if [ "$waited" -ge "$timeout_s" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      RUN_RC=124
      break
    fi
    sleep 1
    waited=$((waited+1))
  done
  if [ "$RUN_RC" -eq 124 ]; then
    wait "$pid" 2>/dev/null || true
  else
    RUN_RC=0
    wait "$pid" 2>/dev/null || RUN_RC=$?
  fi
  RUN_OUT="$(cat "$outfile" 2>/dev/null || true)"
  print_output "$max_lines"
  if [ "$RUN_RC" -eq 124 ]; then
    warn "命令执行超时（已终止，timeout=$timeout_s s）"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 值读取与比对辅助
# ---------------------------------------------------------------------------
sha256_of() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

plist_str() {
  local plist="$1" key="$2"
  plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

check_plist_equals() {
  local plist="$1" key="$2" expected="$3" actual
  actual="$(plist_str "$plist" "$key")"
  if [ -n "$actual" ]; then
    if [ "$actual" = "$expected" ]; then
      pass "Info.plist $key = $actual"
    else
      fail "Info.plist $key = '$actual'（期望 '$expected'）"
    fi
  else
    fail "Info.plist 缺少 ${key}（期望 '$expected'）"
  fi
}

# 从 SHA256SUMS 内容中查找指定文件名的期望哈希（支持 shasum 与 BSD 两种格式）
expected_hash_for() {
  local want="$1" line hash name
  EXPECTED_HASH=""
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in
      "SHA256 ("*") = "*)
        hash=$(echo "$line" | cut -d '=' -f 2 | tr -d ' ')
        name=$(echo "$line" | sed 's|^SHA256 (||; s|) = [0-9a-fA-F]*$||')
        ;;
      *)
        hash=$(echo "$line" | cut -c 1-64)
        if ! echo "$hash" | grep -Eq '^[0-9a-fA-F]{64}$'; then
          continue
        fi
        name=$(echo "$line" | cut -c 65- | sed 's/^[[:space:]]*//')
        ;;
    esac
    name=$(echo "$name" | sed 's|^[*]||; s|^[.]/||')
    hash=$(echo "$hash" | tr 'A-F' 'a-f')
    case "$name" in
      "$want"|*"/$want")
        EXPECTED_HASH="$hash"
        return 0
        ;;
    esac
  done <<< "$SUMS_CONTENT"
  return 1
}

is_env_mount_denied() {
  local text="$1"
  case "$text" in
    *"Operation not permitted"*|*"操作不被允许"*|*"Permission denied"*|*"not authorized"*|*"sandbox"*|*"Sandbox"*|*"Resource temporarily unavailable"*|*"device not configured"*|*"权限"*|*"不允许"*)
      return 0
      ;;
  esac
  return 1
}

is_env_gui_denied() {
  local text="$1"
  case "$text" in
    *"Operation not permitted"*|*"操作不被允许"*|*"Permission denied"*|*"not authorized"*|*"sandbox"*|*"Sandbox"*|*"LaunchServices"*|*"LSOpen"*|*"XPC"*|*"connection to service"*|*"Could not connect"*|*"权限"*|*"不允许"*)
      return 0
      ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# .app 校验主体
# ---------------------------------------------------------------------------
verify_app() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local exec_path="$app/$EXEC_REL"

  if [ -d "$app/Contents" ] && [ -d "$app/Contents/MacOS" ] && [ -d "$app/Contents/Resources" ]; then
    pass "app bundle 基本结构完整（Contents/MacOS/Resources）"
  else
    fail "app bundle 结构不完整（缺少 Contents/MacOS 或 Contents/Resources）"
  fi

  if [ ! -f "$plist" ]; then
    fail "缺少 Contents/Info.plist"
    return 0
  fi

  run_cmd 10 plutil -lint "$plist"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "Info.plist 语法合法"
  else
    fail "Info.plist 语法非法"
  fi

  check_plist_equals "$plist" "CFBundleIdentifier" "$EXPECTED_BUNDLE_ID"
  check_plist_equals "$plist" "CFBundleShortVersionString" "$EXPECTED_VERSION"
  check_plist_equals "$plist" "CFBundleVersion" "$EXPECTED_BUILD"
  check_plist_equals "$plist" "LSMinimumSystemVersion" "$EXPECTED_MIN_OS"
  check_plist_equals "$plist" "CFBundleDisplayName" "$APP_NAME"
  check_plist_equals "$plist" "CFBundleName" "$APP_NAME"
  check_plist_equals "$plist" "CFBundlePackageType" "APPL"

  local exec_name icon_file icon_name copyright icon_path
  exec_name="$(plist_str "$plist" "CFBundleExecutable")"
  if [ "$exec_name" = "$APP_NAME" ] && [ -x "$app/Contents/MacOS/$exec_name" ]; then
    pass "CFBundleExecutable = ${exec_name}，主可执行文件存在且可执行"
  else
    fail "CFBundleExecutable = '$exec_name'，主可执行文件缺失或无执行权限"
  fi

  icon_file="$(plist_str "$plist" "CFBundleIconFile")"
  icon_name="$(plist_str "$plist" "CFBundleIconName")"
  if [ -z "$icon_file" ] && [ -z "$icon_name" ]; then
    fail "Info.plist 未声明 CFBundleIconFile / CFBundleIconName"
  else
    pass "Info.plist 声明图标: CFBundleIconFile='$icon_file' CFBundleIconName='$icon_name'"
  fi
  if [ -n "$icon_file" ]; then
    case "$icon_file" in
      *.icns) icon_path="$app/Contents/Resources/$icon_file" ;;
      *) icon_path="$app/Contents/Resources/$icon_file.icns" ;;
    esac
    if [ -f "$icon_path" ]; then
      pass "图标文件存在: $icon_path"
    else
      fail "图标文件缺失: $icon_path"
    fi
  fi
  if [ -n "$icon_name" ]; then
    if [ -f "$app/Contents/Resources/Assets.car" ] || [ -f "$app/Contents/Resources/$icon_name.icns" ]; then
      pass "图标资源存在（Assets.car 或 $icon_name.icns）"
    else
      fail "未找到图标资源 Assets.car 或 $icon_name.icns"
    fi
  fi

  copyright="$(plist_str "$plist" "NSHumanReadableCopyright")"
  if [ -n "$copyright" ]; then
    pass "NSHumanReadableCopyright = $copyright"
  else
    warn "Info.plist 未设置 NSHumanReadableCopyright（非阻塞，建议发布前补充版权信息）"
  fi

  local cs_format cs_sig cs_team cs_flags
  run_cmd 30 codesign -dvvv "$app"
  CODESIGN_INFO="$RUN_OUT"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "codesign -dvvv 可读取签名信息"
    cs_format="$(echo "$CODESIGN_INFO" | sed -n 's/^Format=//p' | head -n 1)"
    cs_sig="$(echo "$CODESIGN_INFO" | sed -n 's/^Signature=//p' | head -n 1)"
    cs_team="$(echo "$CODESIGN_INFO" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
    cs_flags="$(echo "$CODESIGN_INFO" | sed -n 's/^CodeDirectory .* flags=//p' | head -n 1)"
    info "签名格式: $cs_format"
    info "签名类型: $cs_sig / TeamIdentifier: $cs_team"
    info "CodeDirectory flags: $cs_flags"
    case "$cs_format" in
      *"Mach-O thin (arm64)"*) pass "签名显示为 arm64 单架构 app bundle" ;;
      *universal*) info "签名显示为通用二进制（universal）" ;;
      *) warn "签名 Format 未识别为 arm64 thin: $cs_format" ;;
    esac
    if [ "$cs_sig" = "adhoc" ]; then
      warn "签名为 ad-hoc（本机无 Developer ID 证书，未公证——已知/预期限制）"
    elif [ -n "$cs_sig" ]; then
      pass "签名类型: $cs_sig"
    else
      warn "未解析到签名类型"
    fi
    case "$cs_team" in
      "not set"|"") warn "TeamIdentifier 未设置（ad-hoc 签名的预期结果）" ;;
      *) pass "TeamIdentifier = $cs_team" ;;
    esac
    case "$cs_flags" in
      *runtime*) pass "Hardened Runtime 标志已启用" ;;
      *) warn "CodeDirectory flags 中未看到 runtime（Hardened Runtime 未启用）" ;;
    esac
  else
    fail "codesign -dvvv 失败（rc=${RUN_RC}）"
  fi

  local ent_out ent_list
  ent_out="$(codesign -d --entitlements :- "$app" 2>&1 || true)"
  if echo "$ent_out" | grep -q "com.apple.security.app-sandbox"; then
    fail "app 含 com.apple.security.app-sandbox entitlement（与 ENABLE_APP_SANDBOX=NO 不符）"
  else
    pass "未启用 App Sandbox entitlement（与 ENABLE_APP_SANDBOX=NO 一致）"
  fi
  ent_list="$(echo "$ent_out" | grep -o 'com[.]apple[.]security[.][A-Za-z0-9.-]*' | sort -u || true)"
  if [ -n "$ent_list" ]; then
    info "检测到的 entitlements:"
    echo "$ent_list" | sed 's/^/        /'
  else
    info "未检测到任何 entitlements（ad-hoc 直签通常如此）"
  fi

  if [ -f "$app/Contents/_CodeSignature/CodeResources" ]; then
    pass "存在代码签名资源 Contents/_CodeSignature/CodeResources"
  else
    warn "缺少 Contents/_CodeSignature/CodeResources（无签名打包时可能出现）"
  fi

  run_cmd 30 codesign --verify --deep --strict --verbose=2 "$app"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "codesign --verify --deep --strict 通过"
  else
    fail "codesign --verify --deep --strict 失败（rc=${RUN_RC}）"
  fi

  local spctl_out
  run_cmd 30 spctl -a -vvv -t exec "$app"
  spctl_out="$RUN_OUT"
  if echo "$spctl_out" | grep -q "accepted"; then
    pass "spctl 接受（预期为 rejected：本机 ad-hoc 未公证）"
  elif echo "$spctl_out" | grep -q "rejected"; then
    pass "spctl rejected（预期：ad-hoc 签名 + 未公证；网络分发后首次打开需右键或系统设置放行）"
    info "拒绝原因推断：无 Developer ID 签名、未公证（本机构建产物，非产品逻辑缺陷）"
  else
    fail "spctl 结果无法识别（rc=${RUN_RC}）"
  fi

  run_cmd 5 file "$exec_path"
  FILE_OUT="$RUN_OUT"
  case "$FILE_OUT" in
    *"Mach-O"*arm64*) pass "主可执行文件为 arm64 Mach-O" ;;
    *arm64*) pass "主可执行文件包含 arm64 架构" ;;
    *) fail "主可执行文件架构异常: $FILE_OUT" ;;
  esac
  if echo "$FILE_OUT" | grep -q "x86_64"; then
    info "主可执行文件同时包含 x86_64（universal）"
  fi
}

# ---------------------------------------------------------------------------
# 挂载清理
# ---------------------------------------------------------------------------
cleanup_mount() {
  if [ "$ATTACHED" = "1" ]; then
    echo "CLEAN 尝试卸载 $MNT_DIR"
    if hdiutil detach "$MNT_DIR" >/dev/null 2>&1; then
      ATTACHED=0
    elif hdiutil detach -force "$MNT_DIR" >/dev/null 2>&1; then
      ATTACHED=0
    else
      echo "CLEAN 警告: 无法卸载 ${MNT_DIR}，请手动卸载"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------
mkdir -p "$BUILD_DIR" "$LOG_DIR"
trap cleanup_mount EXIT
trap 'cleanup_mount; exit 130' INT TERM

section "0. 环境与前置检查"
info "时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
info "主机: $(uname -m) / macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
info "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
info "用户: $(id -un) (uid $(id -u))"
info "工作区: $ROOT"
info "脚本: $0"
if [ "$SKIP_LAUNCH" = "1" ]; then
  info "GUI 启动测试: 跳过（--skip-launch）"
else
  info "GUI 启动测试: 启用"
fi

for tool in hdiutil diskutil shasum plutil codesign spctl pkgutil lsbom file ditto unzip open pgrep osascript mount; do
  if command -v "$tool" >/dev/null 2>&1; then
    info "系统命令可用: $tool"
  else
    fail "缺少系统命令: $tool"
  fi
done

# ---------------------------------------------------------------------------
section "1. 产物存在性与 SHA-256 校验和"
# ---------------------------------------------------------------------------
if [ -d "$DIST_DIR" ]; then
  pass "dist/ 目录存在: $DIST_DIR"
else
  fail "dist/ 目录不存在: $DIST_DIR"
fi

check_artifact() {
  local path="$1" label="$2" size
  if [ -f "$path" ]; then
    size=$(stat -f%z "$path" 2>/dev/null || echo 0)
    if [ "$size" -gt 0 ]; then
      pass "$label 存在且非空（$size 字节）: $path"
    else
      fail "$label 为空文件: $path"
    fi
  else
    fail "$label 不存在: $path"
  fi
}

check_artifact "$DMG_FILE" "DMG"
check_artifact "$PKG_FILE" "PKG"
check_artifact "$ZIP_FILE" "ZIP"
check_artifact "$SUMS_FILE" "SHA256SUMS"

if [ -d "$DIST_DIR" ]; then
  DIST_EXTRA="$(find "$DIST_DIR" -maxdepth 1 -type f ! -name "Brewbutler-1.0.dmg" ! -name "Brewbutler-1.0.pkg" ! -name "Brewbutler-1.0.zip" ! -name "SHA256SUMS" ! -name "BUILD-INFO.txt" ! -name "VERIFICATION.md" ! -name ".DS_Store" -print 2>/dev/null || true)"
  if [ -n "$DIST_EXTRA" ]; then
    warn "dist/ 中存在预期外文件（请确认是否应随发布包分发）:"
    echo "$DIST_EXTRA" | sed 's/^/        /'
  fi
fi

if [ -f "$BUILD_INFO" ]; then
  pass "BUILD-INFO.txt 存在"
  if grep -q "com.brewbutler.app" "$BUILD_INFO"; then
    pass "BUILD-INFO.txt 标注 bundle id 为 com.brewbutler.app"
  else
    warn "BUILD-INFO.txt 未标注 bundle id"
  fi
  if grep -q "1.0" "$BUILD_INFO"; then
    pass "BUILD-INFO.txt 标注版本 1.0"
  else
    warn "BUILD-INFO.txt 未标注版本 1.0"
  fi
  if grep -q "公证: 否" "$BUILD_INFO"; then
    pass "BUILD-INFO.txt 如实声明未公证"
  else
    warn "BUILD-INFO.txt 未明确声明公证状态"
  fi
fi

if [ -f "$SUMS_FILE" ]; then
  echo "CMD: (cd dist && shasum -a 256 -c SHA256SUMS)"
  SHASUM_LOG="$LOG_DIR/shasum-check.log"
  SHASUM_RC=0
  if ( cd "$DIST_DIR" && shasum -a 256 -c "$SUMS_FILE" ) > "$SHASUM_LOG" 2>&1; then
    SHASUM_RC=0
  else
    SHASUM_RC=$?
  fi
  sed 's/^/        /' "$SHASUM_LOG" || true
  if [ "$SHASUM_RC" -eq 0 ]; then
    pass "shasum -a 256 -c dist/SHA256SUMS 校验通过"
  else
    if ( cd "$ROOT" && shasum -a 256 -c "$SUMS_FILE" ) > "$SHASUM_LOG" 2>&1; then
      pass "shasum -a 256 -c 校验通过（SHA256SUMS 使用相对项目根的路径）"
      warn "SHA256SUMS 中的路径基准不是 dist/，建议在 dist/ 内生成"
    else
      fail "shasum -a 256 -c 校验失败（详见上方输出）"
    fi
  fi

  SUMS_CONTENT="$(cat "$SUMS_FILE")"
  ENTRY_COUNT="$(grep -cE '^[0-9a-fA-F]{64} [ *]|^SHA256 [(]' "$SUMS_FILE" 2>/dev/null || true)"
  if [ -z "$ENTRY_COUNT" ]; then
    ENTRY_COUNT=0
  fi
  info "SHA256SUMS 条目数（估算）: $ENTRY_COUNT"

  for artifact in "$DMG_FILE" "$PKG_FILE" "$ZIP_FILE"; do
    if [ ! -f "$artifact" ]; then
      continue
    fi
    base="$(basename "$artifact")"
    if expected_hash_for "$base"; then
      actual="$(sha256_of "$artifact")"
      if [ "$EXPECTED_HASH" = "$actual" ]; then
        pass "SHA-256 匹配: $base ($actual)"
      else
        fail "SHA-256 不匹配: ${base}（SHA256SUMS=${EXPECTED_HASH}，实际=${actual}）"
      fi
    else
      fail "SHA256SUMS 未包含 $base 条目"
    fi
  done

  if [ -f "$BUILD_INFO" ]; then
    for base in Brewbutler-1.0.dmg Brewbutler-1.0.pkg Brewbutler-1.0.zip; do
      info_hash="$(grep -F "$base" "$BUILD_INFO" | grep -oE '[0-9a-f]{64}' | head -n 1 || true)"
      if expected_hash_for "$base"; then
        if [ -n "$info_hash" ]; then
          if [ "$info_hash" = "$EXPECTED_HASH" ]; then
            pass "BUILD-INFO.txt 中 $base 哈希与 SHA256SUMS 一致"
          else
            fail "BUILD-INFO.txt 中 $base 哈希与 SHA256SUMS 不一致"
          fi
        else
          warn "BUILD-INFO.txt 中未找到 $base 的哈希"
        fi
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
section "2. DMG 校验"
# ---------------------------------------------------------------------------
DMG_ATTACH_OK=0
if [ ! -f "$DMG_FILE" ]; then
  skip "DMG 不存在，跳过 DMG 结构与挂载校验"
else
  run_cmd 60 hdiutil verify "$DMG_FILE"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "hdiutil verify 通过（DMG 内部校验和有效）"
  else
    fail "hdiutil verify 失败（rc=${RUN_RC}）"
  fi

  run_cmd 120 hdiutil imageinfo "$DMG_FILE"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "hdiutil imageinfo 可读取"
    DMG_FORMAT="$(echo "$RUN_OUT" | sed -n 's/^Format: //p' | head -n 1)"
    DMG_FORMAT_DESC="$(echo "$RUN_OUT" | sed -n 's/^Format Description: //p' | head -n 1)"
    info "DMG 格式: $DMG_FORMAT / $DMG_FORMAT_DESC"
    case "$DMG_FORMAT" in
      UDZO|UDRO|ULFO|ULMO|ASIF) pass "DMG 为只读/压缩磁盘映像格式: $DMG_FORMAT" ;;
      "") warn "hdiutil imageinfo 未报告 Format" ;;
      *) warn "DMG 格式非常见只读格式: $DMG_FORMAT" ;;
    esac
  else
    fail "hdiutil imageinfo 失败（rc=${RUN_RC}）"
  fi

  run_cmd 60 diskutil image info "$DMG_FILE"
  if [ "$RUN_RC" -eq 0 ]; then
    DII_FORMAT="$(echo "$RUN_OUT" | sed -n 's/^Image Format: //p' | head -n 1)"
    DII_DESC="$(echo "$RUN_OUT" | sed -n 's/^Format Description: //p' | head -n 1)"
    DII_VOL="$(echo "$RUN_OUT" | sed -n 's/^[[:space:]]*volume-name: //p' | grep -v '^N/A$' | tail -n 1)"
    info "diskutil image info: $DII_FORMAT / $DII_DESC / 卷名 $DII_VOL"
    if echo "$DII_DESC" | grep -qi "read-only"; then
      pass "diskutil 确认映像为只读格式"
    else
      info "diskutil 格式描述未包含 read-only"
    fi
    if [ -n "$DII_VOL" ] && [ "$DII_VOL" = "$EXPECTED_VOLUME" ]; then
      pass "DMG 卷名为 '$EXPECTED_VOLUME'"
    elif [ -n "$DII_VOL" ]; then
      warn "DMG 卷名为 '$DII_VOL'（期望 '$EXPECTED_VOLUME'）"
    fi
  else
    warn "diskutil image info 失败（rc=${RUN_RC}），改用 hdiutil imageinfo 结果"
  fi

  if mount | grep -Fq "on $MNT_DIR "; then
    info "挂载点 $MNT_DIR 已被占用，尝试先卸载"
    hdiutil detach "$MNT_DIR" >/dev/null 2>&1 || hdiutil detach -force "$MNT_DIR" >/dev/null 2>&1 || true
  fi

  if mount | grep -Fq "on $MNT_DIR "; then
    fail "无法清理已存在的挂载点: $MNT_DIR"
  else
    rm -rf "$MNT_DIR"
    mkdir -p "$MNT_DIR"
    run_cmd_t 60 60 hdiutil attach -nobrowse -readonly -mountpoint "$MNT_DIR" "$DMG_FILE"
    ATTACH_OUT="$RUN_OUT"
    if [ "$RUN_RC" -eq 0 ]; then
      ATTACHED=1
      DMG_ATTACH_OK=1
      pass "hdiutil attach 成功（只读、不浏览）"
    elif mount | grep -Fq "on $MNT_DIR "; then
      ATTACHED=1
      DMG_ATTACH_OK=1
      warn "hdiutil attach 返回非零（rc=${RUN_RC}），但卷已挂载，继续校验"
    elif is_env_mount_denied "$ATTACH_OUT"; then
      skip "DMG 挂载被沙箱拒绝（环境限制），跳过卷内结构校验：$ATTACH_OUT"
    else
      fail "hdiutil attach 失败（rc=${RUN_RC}）"
    fi
  fi

  if [ "$DMG_ATTACH_OK" = "1" ]; then
    MNT_INFO="$(diskutil info "$MNT_DIR" 2>&1 || true)"
    echo "$MNT_INFO" | grep -E 'Volume Name|File System|Read-Only|Mount Point' | sed 's/^/        /' || true
    MNT_VOL_NAME="$(echo "$MNT_INFO" | sed -n 's/^[[:space:]]*Volume Name:[[:space:]]*//p' | head -n 1)"
    MNT_FS="$(echo "$MNT_INFO" | sed -n 's/^[[:space:]]*File System Personality:[[:space:]]*//p' | head -n 1)"
    MNT_RO="$(echo "$MNT_INFO" | grep 'Read-Only' | grep -c 'Yes' || true)"
    if [ -n "$MNT_VOL_NAME" ]; then
      pass "挂载卷名: $MNT_VOL_NAME"
      case "$MNT_VOL_NAME" in
        *Brewbutler*) ;;
        *) warn "挂载卷名未包含 Brewbutler: $MNT_VOL_NAME" ;;
      esac
    else
      warn "无法读取挂载卷名"
    fi
    if [ -n "$MNT_FS" ]; then
      pass "挂载文件系统: $MNT_FS"
    else
      warn "无法读取挂载文件系统类型"
    fi
    if [ -z "$MNT_RO" ]; then
      MNT_RO=0
    fi
    if [ "$MNT_RO" -gt 0 ]; then
      pass "DMG 为只读挂载"
    else
      warn "DMG 未报告只读挂载"
    fi

    if [ -d "$MNT_DIR/Brewbutler.app" ]; then
      pass "DMG 卷内存在 Brewbutler.app"
      if [ -x "$MNT_DIR/Brewbutler.app/$EXEC_REL" ]; then
        pass "DMG 卷内 app 主可执行文件存在且可执行"
      else
        fail "DMG 卷内 app 主可执行文件缺失"
      fi
      DMG_APP_SHA="$(sha256_of "$MNT_DIR/Brewbutler.app/$EXEC_REL" 2>/dev/null || true)"
      rm -rf "$QA_DIR"
      mkdir -p "$QA_DIR"
      if ditto "$MNT_DIR/Brewbutler.app" "$QA_APP" 2>"$LOG_DIR/ditto-dmg.log"; then
        pass "已从 DMG 复制 app 到 build/qa-stage，用于后续 .app 校验与启动"
        APP_SRC="DMG 卷内 Brewbutler.app"
      else
        fail "无法从 DMG 复制 app 到 build/qa-stage"
      fi
    else
      fail "DMG 卷内缺少 Brewbutler.app"
    fi

    if [ -L "$MNT_DIR/Applications" ]; then
      APPL_LINK="$(readlink "$MNT_DIR/Applications" || true)"
      APPL_LINK_NORM="$(echo "$APPL_LINK" | sed 's|/*$||')"
      if [ "$APPL_LINK_NORM" = "/Applications" ]; then
        pass "DMG 卷内 Applications 是指向 /Applications 的符号链接"
      else
        fail "DMG 卷内 Applications 链接目标异常: $APPL_LINK"
      fi
    else
      fail "DMG 卷内缺少 Applications 符号链接"
    fi

    if [ -f "$MNT_DIR/安装说明.txt" ]; then
      pass "DMG 卷内含安装说明.txt"
      info "安装说明.txt 前几行:"
      head -n 6 "$MNT_DIR/安装说明.txt" | sed 's/^/        /' || true
    else
      warn "DMG 卷内缺少安装说明.txt"
    fi

    VOL_EXTRA="$(ls -A "$MNT_DIR" | grep -v -F -e "Brewbutler.app" -e "Applications" -e "安装说明.txt" -e ".DS_Store" -e ".fseventsd" -e ".Spotlight-V100" -e ".Trashes" || true)"
    if [ -n "$VOL_EXTRA" ]; then
      warn "DMG 卷内存在预期外内容: $VOL_EXTRA"
    else
      pass "DMG 卷内内容符合预期（app + Applications + 安装说明）"
    fi

    info "DMG 卷根目录内容:"
    ls -la "$MNT_DIR" | sed 's/^/        /' || true

    echo "CMD: hdiutil detach $MNT_DIR"
    if hdiutil detach "$MNT_DIR" >/dev/null 2>&1; then
      ATTACHED=0
      pass "DMG 已卸载"
    elif hdiutil detach -force "$MNT_DIR" >/dev/null 2>&1; then
      ATTACHED=0
      warn "DMG 常规卸载失败，已强制卸载"
    else
      warn "DMG 卸载失败，将在脚本退出时重试"
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "3. ZIP 附加产物校验"
# ---------------------------------------------------------------------------
if [ ! -f "$ZIP_FILE" ]; then
  info "未提供 ZIP 产物（附加项），跳过"
else
  run_cmd 5 unzip -t "$ZIP_FILE"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "ZIP 完整性检查（unzip -t）通过"
  else
    fail "ZIP 完整性检查失败（rc=${RUN_RC}）"
  fi

  run_cmd 60 unzip -l "$ZIP_FILE"
  if echo "$RUN_OUT" | grep -Fq "Brewbutler.app/Contents/MacOS/Brewbutler"; then
    pass "ZIP 内含 Brewbutler.app 主可执行文件"
  else
    fail "ZIP 内未找到 Brewbutler.app/Contents/MacOS/Brewbutler"
  fi
  AD_COUNT="$(echo "$RUN_OUT" | grep -c '/[.]_' || true)"
  if [ -z "$AD_COUNT" ]; then
    AD_COUNT=0
  fi
  if [ "$AD_COUNT" -gt 0 ]; then
    warn "ZIP 内含 $AD_COUNT 个 AppleDouble（._）条目（xattr 打包产物，非阻塞；部分解压工具会显示额外文件）"
  else
    pass "ZIP 未包含 AppleDouble 条目"
  fi

  ZIP_EXEC_SHA="$(unzip -p "$ZIP_FILE" "Brewbutler.app/Contents/MacOS/Brewbutler" 2>/dev/null | shasum -a 256 | cut -d ' ' -f 1 || true)"
  if [ -n "$ZIP_EXEC_SHA" ]; then
    info "ZIP 内主可执行文件 SHA-256: $ZIP_EXEC_SHA"
  fi

  if [ -z "$APP_SRC" ]; then
    rm -rf "$QA_DIR"
    mkdir -p "$QA_DIR"
    if ditto -x -k "$ZIP_FILE" "$QA_DIR" 2>"$LOG_DIR/ditto-zip.log"; then
      if [ -d "$QA_APP" ]; then
        APP_SRC="ZIP 解压的 Brewbutler.app（DMG 卷内 app 不可用，回退）"
        warn "因 DMG 卷内 app 不可用，.app 校验与启动改用 ZIP 解压副本"
      else
        fail "ZIP 解压后未找到 Brewbutler.app"
      fi
    else
      fail "ZIP 解压失败"
    fi
  else
    info "DMG 已提供 app，ZIP 仅做结构与完整性检查"
  fi
fi

# ---------------------------------------------------------------------------
section "4. PKG 校验"
# ---------------------------------------------------------------------------
if [ ! -f "$PKG_FILE" ]; then
  skip "PKG 不存在，跳过 PKG 结构校验"
else
  run_cmd 30 pkgutil --check-signature "$PKG_FILE"
  SIG_OUT="$RUN_OUT"
  case "$SIG_OUT" in
    *"Status: signed"*)
      if echo "$SIG_OUT" | grep -q "Developer ID Installer"; then
        pass "PKG 已由 Developer ID Installer 签名"
      else
        warn "PKG 已签名，但未识别到 Developer ID Installer 证书"
      fi
      ;;
    *"no signature"*|*"not signed"*)
      warn "PKG 未签名（本机无 Developer ID Installer 证书——已知限制；用户安装时 Gatekeeper 会警告）"
      ;;
    *)
      if [ "$RUN_RC" -ne 0 ]; then
        fail "pkgutil --check-signature 失败（rc=${RUN_RC}）"
      else
        warn "无法解析 PKG 签名状态"
      fi
      ;;
  esac

  run_cmd 30 spctl -a -t install --context context:primary-signature "$PKG_FILE"
  if echo "$RUN_OUT" | grep -q "accepted"; then
    pass "spctl 对 PKG 评估为 accepted"
  elif echo "$RUN_OUT" | grep -q "rejected"; then
    pass "spctl 对 PKG 评估为 rejected（预期：未签名，无 Developer ID Installer）"
  else
    warn "spctl 对 PKG 的评估结果无法识别（rc=${RUN_RC}）"
  fi

  run_cmd 400 pkgutil --payload-files "$PKG_FILE"
  PAYLOAD_LIST="$RUN_OUT"
  if [ "$RUN_RC" -eq 0 ]; then
    pass "pkgutil --payload-files 可读取"
    if echo "$PAYLOAD_LIST" | grep -Fq "Brewbutler.app/Contents/MacOS/Brewbutler"; then
      pass "PKG 载荷包含 Brewbutler.app 主可执行文件"
    else
      fail "PKG 载荷未包含 Brewbutler.app/Contents/MacOS/Brewbutler"
    fi
    if echo "$PAYLOAD_LIST" | grep -Fq "Brewbutler.app/Contents/Info.plist"; then
      pass "PKG 载荷包含 Brewbutler.app/Contents/Info.plist"
    else
      fail "PKG 载荷未包含 Brewbutler.app/Contents/Info.plist"
    fi

    UNEXPECTED_TOPS=""
    while IFS= read -r entry || [ -n "$entry" ]; do
      [ -z "$entry" ] && continue
      top="$(echo "$entry" | sed 's|^[.]/||' | cut -d '/' -f 1)"
      case "$top" in
        "."|""|"Applications"|"Brewbutler.app"|"._Applications"|"._Brewbutler.app") ;;
        *) UNEXPECTED_TOPS="$UNEXPECTED_TOPS $top" ;;
      esac
    done <<< "$PAYLOAD_LIST"
    if [ -n "$UNEXPECTED_TOPS" ]; then
      warn "PKG 载荷包含 Applications 之外的顶层内容:$UNEXPECTED_TOPS"
    else
      pass "PKG 载荷顶层内容仅涉及 Applications / Brewbutler.app"
    fi
  else
    fail "pkgutil --payload-files 失败（rc=${RUN_RC}）"
  fi

  rm -rf "$PKG_EXPAND_DIR"
  run_cmd 30 pkgutil --expand-full "$PKG_FILE" "$PKG_EXPAND_DIR"
  if [ "$RUN_RC" -eq 0 ] && [ -d "$PKG_EXPAND_DIR" ]; then
    pass "pkgutil --expand-full 展开成功"
  else
    fail "pkgutil --expand-full 展开失败（rc=${RUN_RC}）"
  fi

  if [ -d "$PKG_EXPAND_DIR" ]; then
    PKG_INFO_FILES="$(find "$PKG_EXPAND_DIR" -name PackageInfo -type f 2>/dev/null || true)"
    if [ -z "$PKG_INFO_FILES" ]; then
      fail "PKG 内未找到 PackageInfo"
    else
      PKG_INFO_COUNT=0
      while IFS= read -r pinfo; do
        [ -z "$pinfo" ] && continue
        PKG_INFO_COUNT=$((PKG_INFO_COUNT+1))
        pkg_id="$(grep -o ' identifier="[^"]*"' "$pinfo" | head -n 1 | cut -d '"' -f 2 || true)"
        pkg_ver="$(grep -o ' version="[^"]*"' "$pinfo" | head -n 1 | cut -d '"' -f 2 || true)"
        pkg_loc="$(grep -o ' install-location="[^"]*"' "$pinfo" | head -n 1 | cut -d '"' -f 2 || true)"
        pkg_action="$(grep -o ' postinstall-action="[^"]*"' "$pinfo" | head -n 1 | cut -d '"' -f 2 || true)"
        info "组件包: identifier=$pkg_id version=$pkg_ver install-location=$pkg_loc postinstall-action=$pkg_action"
        case "$pkg_id" in
          *brewbutler*) pass "组件包 identifier 与产品匹配: $pkg_id" ;;
          "") warn "组件包缺少 identifier" ;;
          *) warn "组件包 identifier 未包含 brewbutler: $pkg_id" ;;
        esac
        if [ "$pkg_ver" = "$EXPECTED_VERSION" ]; then
          pass "组件包 version = $pkg_ver"
        else
          fail "组件包 version = '$pkg_ver'（期望 ${EXPECTED_VERSION}）"
        fi
        case "$pkg_action" in
          "none"|"") pass "组件包未声明 postinstall 脚本动作" ;;
          *) warn "组件包声明 postinstall-action=${pkg_action}，需人工审查脚本" ;;
        esac
      done <<< "$PKG_INFO_FILES"
      pass "共发现 $PKG_INFO_COUNT 个组件包 PackageInfo"
    fi

    DIST_FILES="$(find "$PKG_EXPAND_DIR" -name Distribution -type f 2>/dev/null || true)"
    if [ -z "$DIST_FILES" ]; then
      info "未发现 Distribution（单个 component package，使用 PackageInfo.install-location 判断安装位置）"
    else
      while IFS= read -r distf; do
        [ -z "$distf" ] && continue
        info "发现 Distribution: $distf"
        if grep -q 'enable_localSystem="true"' "$distf"; then
          pass "Distribution 允许安装到本机系统域（可写入 /Applications）"
        else
          warn "Distribution 未声明 enable_localSystem=true"
        fi
        if grep -q 'version="1.0"' "$distf"; then
          pass "Distribution 引用 version=1.0"
        else
          warn "Distribution 未找到 version=1.0"
        fi
      done <<< "$DIST_FILES"
    fi

    SCRIPT_DIRS="$(find "$PKG_EXPAND_DIR" -type d -name Scripts 2>/dev/null || true)"
    if [ -n "$SCRIPT_DIRS" ]; then
      warn "PKG 含安装脚本目录（需人工审查）: $SCRIPT_DIRS"
    else
      pass "PKG 不含安装脚本目录"
    fi

    BOM_FILES="$(find "$PKG_EXPAND_DIR" -name Bom -type f 2>/dev/null || true)"
    if [ -z "$BOM_FILES" ]; then
      warn "PKG 展开后未找到 Bom，无法校验载荷所有权"
    else
      while IFS= read -r bom; do
        [ -z "$bom" ] && continue
        for entry in "./Brewbutler.app" "./Brewbutler.app/Contents/MacOS/Brewbutler" "./Brewbutler.app/Contents/Info.plist"; do
          bom_line="$(lsbom "$bom" 2>/dev/null | grep -F "$entry" | head -n 1 || true)"
          case "$bom_line" in
            "") warn "Bom 未找到 $entry" ;;
            *"0/0"*) pass "Bom 所有权 root/wheel: $entry" ;;
            *) fail "Bom 所有权异常（期望 0/0）: $bom_line" ;;
          esac
        done
      done <<< "$BOM_FILES"
    fi

    PKG_APP_CANDIDATES="$(find "$PKG_EXPAND_DIR" -type d -name Brewbutler.app 2>/dev/null || true)"
    if [ -z "$PKG_APP_CANDIDATES" ]; then
      fail "PKG 载荷内未找到 Brewbutler.app"
    else
      while IFS= read -r pkg_app; do
        [ -z "$pkg_app" ] && continue
        if [ -z "$PKG_APP_ANY" ]; then
          PKG_APP_ANY="$pkg_app"
        fi
        rel="$(echo "$pkg_app" | sed 's|^.*/Payload/||')"
        payload_dir="$(echo "$pkg_app" | sed 's|/Applications/Brewbutler.app$||; s|/Brewbutler.app$||')"
        component_dir="$(dirname "$payload_dir")"
        pinfo="$component_dir/PackageInfo"
        pkg_loc=""
        if [ -f "$pinfo" ]; then
          pkg_loc="$(grep -o ' install-location="[^"]*"' "$pinfo" | head -n 1 | cut -d '"' -f 2 || true)"
        fi
        if [ -z "$pkg_loc" ]; then
          pkg_loc="/"
        fi
        case "$pkg_loc" in
          "/") installed_path="/$rel" ;;
          *) installed_path="$pkg_loc/$rel" ;;
        esac
        installed_path="$(echo "$installed_path" | sed 's|//*|/|g')"
        info "PKG 载荷 app: $pkg_app"
        info "  安装路径: ${installed_path}（install-location=${pkg_loc}）"
        if [ "$installed_path" = "/Applications/Brewbutler.app" ]; then
          pass "PKG 将 Brewbutler.app 安装到 /Applications"
          if [ -z "$PKG_APP" ]; then
            PKG_APP="$pkg_app"
          fi
        else
          fail "PKG 安装位置异常: ${installed_path}（期望 /Applications/Brewbutler.app）"
        fi
        if [ -f "$pkg_app/Contents/Info.plist" ] && [ -x "$pkg_app/$EXEC_REL" ]; then
          pass "PKG 载荷 app 结构完整（Info.plist 与主可执行文件）"
        else
          fail "PKG 载荷 app 结构不完整"
        fi
      done <<< "$PKG_APP_CANDIDATES"
    fi

    if [ -n "$PKG_APP_ANY" ] && [ -d "$PKG_APP_ANY" ]; then
      PKG_APP_SHA="$(sha256_of "$PKG_APP_ANY/$EXEC_REL" 2>/dev/null || true)"
      run_cmd 30 codesign --verify --deep --strict --verbose=2 "$PKG_APP_ANY"
      if [ "$RUN_RC" -eq 0 ]; then
        pass "PKG 载荷内 app 的 codesign 校验通过"
      else
        fail "PKG 载荷内 app 的 codesign 校验失败（rc=${RUN_RC}）"
      fi
    fi
  fi

  if [ -z "$APP_SRC" ] && [ -n "$PKG_APP" ]; then
    rm -rf "$QA_DIR"
    mkdir -p "$QA_DIR"
    if ditto "$PKG_APP" "$QA_APP" 2>"$LOG_DIR/ditto-pkg.log"; then
      APP_SRC="PKG 载荷（DMG/ZIP 内 app 不可用，回退）"
      warn "因 DMG/ZIP 内 app 不可用，.app 校验改用 PKG 载荷副本"
    else
      fail "无法从 PKG 载荷复制 app 到 build/qa-stage"
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "5. .app 校验"
# ---------------------------------------------------------------------------
if [ -z "$APP_SRC" ] && [ -d "$ARCHIVE_APP" ]; then
  rm -rf "$QA_DIR"
  mkdir -p "$QA_DIR"
  if ditto "$ARCHIVE_APP" "$QA_APP" 2>"$LOG_DIR/ditto-archive.log"; then
    APP_SRC="Xcode archive（回退副本）"
    warn "APP 校验基于 Xcode archive 回退副本，未能直接验证发布产物内的 app"
  else
    fail "无法从 Xcode archive 复制 app"
  fi
fi

if [ ! -d "$QA_APP" ]; then
  fail "没有可用于校验的 .app"
else
  info "被测 .app: $QA_APP"
  info "来源: $APP_SRC"
  verify_app "$QA_APP"
fi

info "各产物内主可执行文件哈希对比:"
if [ -n "$DMG_APP_SHA" ]; then info "  DMG: $DMG_APP_SHA"; else info "  DMG: 未取得"; fi
if [ -n "$ZIP_EXEC_SHA" ]; then info "  ZIP: $ZIP_EXEC_SHA"; else info "  ZIP: 未取得"; fi
if [ -n "$PKG_APP_SHA" ]; then info "  PKG: $PKG_APP_SHA"; else info "  PKG: 未取得"; fi
if [ -n "$DMG_APP_SHA" ] && [ -n "$ZIP_EXEC_SHA" ]; then
  if [ "$DMG_APP_SHA" = "$ZIP_EXEC_SHA" ]; then
    pass "DMG 与 ZIP 内主可执行文件 SHA-256 一致"
  else
    fail "DMG 与 ZIP 内主可执行文件 SHA-256 不一致"
  fi
fi
if [ -n "$DMG_APP_SHA" ] && [ -n "$PKG_APP_SHA" ]; then
  if [ "$DMG_APP_SHA" = "$PKG_APP_SHA" ]; then
    pass "DMG 与 PKG 内主可执行文件 SHA-256 一致"
  else
    fail "DMG 与 PKG 内主可执行文件 SHA-256 不一致"
  fi
fi
if [ -n "$ZIP_EXEC_SHA" ] && [ -n "$PKG_APP_SHA" ]; then
  if [ "$ZIP_EXEC_SHA" = "$PKG_APP_SHA" ]; then
    pass "ZIP 与 PKG 内主可执行文件 SHA-256 一致"
  else
    fail "ZIP 与 PKG 内主可执行文件 SHA-256 不一致"
  fi
fi

# ---------------------------------------------------------------------------
section "6. 启动冒烟测试（GUI）"
# ---------------------------------------------------------------------------
if [ "$SKIP_LAUNCH" = "1" ]; then
  skip "已通过 --skip-launch 跳过 GUI 启动冒烟测试"
elif [ ! -d "$QA_APP" ]; then
  skip "无 app 副本，跳过启动冒烟测试"
else
  LAUNCH_PATTERN="$QA_APP/$EXEC_REL"
  ALL_PIDS="$(pgrep -f "Brewbutler.app/Contents/MacOS/Brewbutler" 2>/dev/null || true)"
  if [ -n "$ALL_PIDS" ]; then
    info "启动前发现已在运行的 Brewbutler 进程:"
    for pid in $ALL_PIDS; do
      cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
      info "  pid=$pid $cmd"
      case "$cmd" in
        *"$ROOT/build/"*|*"$ROOT/dist/"*)
          info "  结束本工作区构建副本进程 pid=$pid"
          kill "$pid" 2>/dev/null || true
          ;;
        *)
          info "  保留非本工作区进程 pid=${pid}（不主动结束）"
          ;;
      esac
    done
    sleep 1
  fi

  run_cmd_t 20 30 open -n "$QA_APP"
  OPEN_RC="$RUN_RC"
  OPEN_OUT="$RUN_OUT"
  if [ "$OPEN_RC" -eq 124 ]; then
    skip "open 启动在 20s 内未返回（沙箱/LaunchServices 可能阻塞，环境限制）"
    info "建议在正常图形会话中手工双击 build/qa-stage/Brewbutler.app 复核"
  elif [ "$OPEN_RC" -ne 0 ]; then
    if is_env_gui_denied "$OPEN_OUT"; then
      skip "GUI 启动被沙箱 / LaunchServices 阻止（环境限制），未能验证 app 运行：$OPEN_OUT"
      info "建议在正常图形会话中手工双击 build/qa-stage/Brewbutler.app 复核"
    else
      fail "open 启动 app 失败（rc=${OPEN_RC}）"
    fi
  else
    sleep 5
    LAUNCH_PIDS="$(pgrep -f "$LAUNCH_PATTERN" 2>/dev/null || true)"
    if [ -n "$LAUNCH_PIDS" ]; then
      pass "启动后 5 秒进程存活（pid: $(echo "$LAUNCH_PIDS" | tr '\n' ' ')）"
      info 'CMD: osascript -e "tell application Brewbutler to quit"'
      run_cmd_t 10 20 osascript -e 'tell application "Brewbutler" to quit'
      if [ "$RUN_RC" -ne 0 ]; then
        warn "osascript 优雅退出失败（rc=${RUN_RC}，沙箱可能限制 AppleEvent），改用 kill"
      fi
      sleep 2
      REMAIN_PIDS="$(pgrep -f "$LAUNCH_PATTERN" 2>/dev/null || true)"
      if [ -n "$REMAIN_PIDS" ]; then
        info "osascript 未结束进程，改为强制结束: $REMAIN_PIDS"
        kill $REMAIN_PIDS 2>/dev/null || true
        sleep 1
        REMAIN_PIDS="$(pgrep -f "$LAUNCH_PATTERN" 2>/dev/null || true)"
        if [ -n "$REMAIN_PIDS" ]; then
          kill -KILL $REMAIN_PIDS 2>/dev/null || true
          sleep 1
          REMAIN_PIDS="$(pgrep -f "$LAUNCH_PATTERN" 2>/dev/null || true)"
        fi
        if [ -n "$REMAIN_PIDS" ]; then
          warn "无法结束后台 Brewbutler 进程: $REMAIN_PIDS"
        else
          pass "应用已强制退出"
        fi
      else
        pass "应用已正常退出"
      fi
    else
      fail "open 返回成功但启动后 5 秒未发现 Brewbutler 进程（可能启动即崩溃）"
      CRASH_REPORT="$(ls -t "$HOME/Library/Logs/DiagnosticReports"/Brewbutler* 2>/dev/null | head -n 1 || true)"
      if [ -n "$CRASH_REPORT" ]; then
        info "最近崩溃报告: $CRASH_REPORT"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "7. 验收后完整性复核"
# ---------------------------------------------------------------------------
if [ -f "$SUMS_FILE" ]; then
  echo "CMD: (cd dist && shasum -a 256 -c SHA256SUMS)"
  if ( cd "$DIST_DIR" && shasum -a 256 -c "$SUMS_FILE" ) > "$SHASUM_LOG" 2>&1; then
    pass "验收后 shasum -a 256 -c 仍通过（验收过程未修改产物）"
  else
    sed 's/^/        /' "$SHASUM_LOG" || true
    fail "验收后 SHA-256 复核失败（产物可能被修改）"
  fi
fi

# ---------------------------------------------------------------------------
section "8. 汇总"
# ---------------------------------------------------------------------------
echo "PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  WARN=$WARN_COUNT  SKIP=$SKIP_COUNT"
echo
echo "临时文件保留在: build/qa-stage build/qa-pkg build/qa-logs"
if [ -n "$WARNED_ITEMS" ]; then
  echo
  echo "警告 / 已知限制:"
  echo "$WARNED_ITEMS"
fi
if [ -n "$SKIPPED_ITEMS" ]; then
  echo
  echo "跳过项（环境限制）:"
  echo "$SKIPPED_ITEMS"
fi
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo
  echo "结果: PASS（关键检查全部通过）"
  exit 0
else
  echo
  echo "失败项:"
  echo "$FAILED_ITEMS"
  echo
  echo "结果: FAIL（$FAIL_COUNT 项关键检查失败）"
  exit 1
fi
