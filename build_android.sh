#!/usr/bin/env bash
# ============================================================
# build_android.sh — AI-Glasses-BLEDebugTools Android 构建脚本
#
# 用途: 自动补齐 Android 原生脚手架 -> 构建 Debug APK -> 安装到已连接真机
# 用法:
#   ./build_android.sh              # 构建并安装
#   ./build_android.sh --no-install # 仅构建，不安装
# ============================================================
set -euo pipefail

# ---------- 路径与参数 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NO_INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --no-install) NO_INSTALL=true ;;
    -h|--help)
      echo "用法: ./build_android.sh [--no-install]"
      echo "  --no-install  仅构建，不安装到设备"
      exit 0
      ;;
  esac
done

# ---------- 颜色 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- 前置检查 ----------
command -v flutter >/dev/null 2>&1 || { err "未找到 flutter，请先安装 Flutter SDK"; exit 1; }

# ---------- 关闭代理（全局） ----------
# 用户配了国内镜像 PUB_HOSTED_URL/FLUTTER_STORAGE_BASE_URL，但环境变量同时有 HTTPS_PROXY，
# 导致 Gradle/pub 下载时先走代理绕到境外再回来，严重超时甚至卡死。
# 全程关闭代理，直连国内镜像即可。
if [ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}" ]; then
  warn "检测到代理环境变量，构建期间临时关闭（国内镜像不需要代理）"
  export _SAVED_http_proxy="${http_proxy:-}" _SAVED_https_proxy="${https_proxy:-}"
  export _SAVED_HTTP_PROXY="${HTTP_PROXY:-}" _SAVED_HTTPS_PROXY="${HTTPS_PROXY:-}"
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
  # 脚本退出时自动恢复
  trap '
    [ -n "$_SAVED_http_proxy" ]  && export http_proxy="$_SAVED_http_proxy"   || unset http_proxy
    [ -n "$_SAVED_https_proxy" ] && export https_proxy="$_SAVED_https_proxy" || unset https_proxy
    [ -n "$_SAVED_HTTP_PROXY" ]  && export HTTP_PROXY="$_SAVED_HTTP_PROXY"   || unset HTTP_PROXY
    [ -n "$_SAVED_HTTPS_PROXY" ] && export HTTPS_PROXY="$_SAVED_HTTPS_PROXY" || unset HTTPS_PROXY
  ' EXIT
fi

# ---------- 版本号解析（以 pubspec.yaml 为真源） ----------
if ! grep -qE '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+' pubspec.yaml; then
  err "pubspec.yaml 缺少合法的 version 字段（应为 1.0.0+1 格式）"
  exit 1
fi
BUILD_NAME=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/\1/')
BUILD_NUMBER=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)/\1/')
ok "版本号: name=${BUILD_NAME}, number=${BUILD_NUMBER}"

# ---------- 1. 补齐 Android 原生脚手架 ----------
if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  info "检测到 android/ 缺少标准构建文件，执行 flutter create --platforms=android ..."
  flutter create --platforms=android . --project-name "$(grep '^name:' pubspec.yaml | sed -E 's/name:[[:space:]]*//')"
  ok "Android 脚手架已补齐"
else
  ok "Android 脚手架已存在，跳过"
fi

# ---------- 2. 安装依赖 ----------
info "flutter pub get ..."
flutter pub get
ok "依赖安装完成"

# ---------- 3. 构建 Debug APK ----------
info "开始构建 Debug APK ..."
flutter build apk --debug \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
  err "未找到构建产物: $APK_PATH"
  exit 1
fi
ok "APK 构建成功"
echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  APK 产物:${NC} $APK_PATH"
echo -e "${GREEN}  文件大小:${NC} $(du -h "$APK_PATH" | cut -f1)"
echo -e "${GREEN}============================================================${NC}"
echo

# ---------- 4. 安装 ----------
if [ "$NO_INSTALL" = true ]; then
  info "已指定 --no-install，跳过安装"
  echo -e "手动安装命令: ${CYAN}adb install $APK_PATH${NC}"
  exit 0
fi

# 直接用 adb install，不走 flutter install（后者在无设备时会尝试构建 macOS/iOS 桌面产物）
if ! command -v adb >/dev/null 2>&1; then
  warn "未找到 adb，请确认 Android platform-tools 已安装"
  echo -e "手动安装: ${CYAN}adb install $APK_PATH${NC}"
  exit 0
fi

info "正在安装到已连接的 Android 设备 ..."
if adb devices | grep -q '\bdevice\b'; then
  if adb install -r "$APK_PATH"; then
    ok "安装成功！请在手机上打开应用查看效果"
  else
    err "adb install 失败"
    exit 1
  fi
else
  warn "未检测到已连接的 Android 设备"
  echo
  echo -e "请检查:"
  echo -e "  1. 手机已通过 USB 连接并开启 ${CYAN}USB 调试${NC}"
  echo -e "  2. ${CYAN}adb devices${NC} 能看到设备"
  echo -e "  3. 连上设备后手动安装: ${CYAN}adb install -r $APK_PATH${NC}"
  exit 1
fi
