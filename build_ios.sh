#!/usr/bin/env bash
# ============================================================
# build_ios.sh — AI-Glasses-BLEDebugTools iOS 构建脚本
#
# 用途: 补齐 iOS 脚手架 -> 安装 CocoaPods -> 写入签名 -> 构建真机包 -> 安装
# 用法:
#   ./build_ios.sh                  # 构建并安装到已连接真机
#   ./build_ios.sh --no-install     # 仅构建
#   DEVELOPMENT_TEAM=XXXXXX ./build_ios.sh   # 直接指定团队 ID
#
# 签名说明:
#   开发团队 ID 获取优先级:
#     1. 环境变量 DEVELOPMENT_TEAM
#     2. 项目根 ios_build.env 文件 (DEVELOPMENT_TEAM=XXXX)
#     3. 脚本运行时交互输入
#   获取你的 Team ID: Xcode -> Settings -> Accounts -> 选中 Apple ID -> Team ID
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
      echo "用法: ./build_ios.sh [--no-install]"
      echo "  --no-install  仅构建，不安装到设备"
      echo "  可用 DEVELOPMENT_TEAM=XXXXXX 环境变量直接指定签名团队"
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
command -v xcodebuild >/dev/null 2>&1 || { err "未找到 xcodebuild，请通过 App Store 安装 Xcode"; exit 1; }

# ---------- 关闭代理（全局） ----------
# 用户配了国内镜像 PUB_HOSTED_URL/FLUTTER_STORAGE_BASE_URL，但环境变量同时有 HTTPS_PROXY，
# 导致 pub/CocoaPods 下载时先走代理绕到境外再回来，严重超时甚至卡死。
# 全程关闭代理，直连国内镜像即可。（与 build_android.sh 保持一致）
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

# ---------- 版本号解析 ----------
if ! grep -qE '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+' pubspec.yaml; then
  err "pubspec.yaml 缺少合法的 version 字段（应为 1.0.0+1 格式）"
  exit 1
fi
BUILD_NAME=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/\1/')
BUILD_NUMBER=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)/\1/')
ok "版本号: name=${BUILD_NAME}, number=${BUILD_NUMBER}"

# ---------- 1. 补齐 iOS 原生脚手架 ----------
if [ ! -f ios/Podfile ]; then
  info "检测到 ios/ 缺少 Podfile，执行 flutter create --platforms=ios ..."
  flutter create --platforms=ios . --project-name "$(grep '^name:' pubspec.yaml | sed -E 's/name:[[:space:]]*//')"
  ok "iOS 脚手架已补齐"
else
  ok "iOS 脚手架已存在，跳过"
fi

# ---------- 2. CocoaPods 检测与安装 ----------
if ! command -v pod >/dev/null 2>&1; then
  warn "未检测到 CocoaPods（iOS 构建必需），尝试自动安装 ..."
  if command -v brew >/dev/null 2>&1; then
    info "通过 Homebrew 安装 CocoaPods ..."
    brew install cocoapods
  else
    err "CocoaPods 未安装，且未找到 Homebrew"
    echo
    echo -e "请手动安装后重试:"
    echo -e "  ${CYAN}sudo gem install cocoapods${NC}"
    echo -e "  或先安装 Homebrew: ${CYAN}https://brew.sh${NC}"
    exit 1
  fi
  ok "CocoaPods 安装完成: $(pod --version)"
else
  ok "CocoaPods 已安装: $(pod --version)"
fi

# ---------- 3. 安装依赖 ----------
info "flutter pub get ..."
flutter pub get
ok "依赖安装完成"

# ---------- 4. pod install ----------
info "执行 pod install ..."
if [ -f ios/Podfile ]; then
  (cd ios && pod install)
  ok "pod install 完成"
else
  warn "未找到 ios/Podfile，跳过（首次 flutter create 后应已生成）"
fi

# ---------- 5. 读取签名团队 ID ----------
TEAM="${DEVELOPMENT_TEAM:-}"
ENV_FILE="$SCRIPT_DIR/ios_build.env"
if [ -z "$TEAM" ] && [ -f "$ENV_FILE" ]; then
  # 从 ios_build.env 读取
  TEAM=$(grep -E '^DEVELOPMENT_TEAM=' "$ENV_FILE" 2>/dev/null | sed -E 's/DEVELOPMENT_TEAM=//' || true)
fi
if [ -z "$TEAM" ]; then
  echo
  echo -e "${YELLOW}========================================================${NC}"
  echo -e "${YELLOW}  需要输入 Apple 开发团队 ID (Team ID)${NC}"
  echo -e "${YELLOW}========================================================${NC}"
  echo -e "  获取方式: Xcode -> Settings -> Accounts -> 选中 Apple ID"
  echo -e "  Team ID 是 10 位字母数字组合（如 ${CYAN}ABCDE12345${NC}）"
  echo -e "  免费个人 Apple ID 也可以（证书 7 天过期）"
  echo
  read -rp "$(echo -e ${CYAN}'请输入 Team ID: '${NC})" TEAM
  if [ -z "$TEAM" ]; then
    err "未输入 Team ID，无法签名"
    echo -e "  也可写入 ${CYAN}ios_build.env${NC} 文件: DEVELOPMENT_TEAM=XXXX"
    exit 1
  fi
  # 保存到 env 文件方便下次使用
  echo "DEVELOPMENT_TEAM=$TEAM" > "$ENV_FILE"
  # 追加到 .gitignore（避免泄露）
  if ! grep -q '^ios_build.env$' .gitignore 2>/dev/null; then
    echo -e "\n# iOS build signing (local)\nios_build.env" >> .gitignore
  fi
  ok "Team ID 已保存到 ios_build.env（已加入 .gitignore）"
fi
ok "签名团队: $TEAM"

# ---------- 6. 写入签名到 pbxproj ----------
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
  info "写入 DEVELOPMENT_TEAM 到 project.pbxproj ..."
  if grep -q 'DEVELOPMENT_TEAM' "$PBXPROJ"; then
    # 已存在则原地替换
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s/DEVELOPMENT_TEAM = \".*\";/DEVELOPMENT_TEAM = \"$TEAM\";/g" "$PBXPROJ"
    else
      sed -i "s/DEVELOPMENT_TEAM = \".*\";/DEVELOPMENT_TEAM = \"$TEAM\";/g" "$PBXPROJ"
    fi
  else
    # 不存在则在每处 CODE_SIGN_STYLE 后插入（Debug/Release/Profile 三个配置）
    info "pbxproj 中无 DEVELOPMENT_TEAM，自动插入到各构建配置 ..."
    perl -pi -e "s/CODE_SIGN_STYLE = Automatic;/CODE_SIGN_STYLE = Automatic;\\n\t\t\t\tDEVELOPMENT_TEAM = \"\Q$TEAM\E\";/g" "$PBXPROJ"
    if ! grep -q 'DEVELOPMENT_TEAM' "$PBXPROJ"; then
      err "自动插入 DEVELOPMENT_TEAM 失败，请手动在 Xcode 中配置签名团队"
      exit 1
    fi
  fi
  ok "签名配置已写入 (DEVELOPMENT_TEAM=$TEAM)"
else
  warn "未找到 $PBXPROJ，跳过签名写入（可能需手动在 Xcode 中配置）"
fi

# ---------- 7. 构建 ----------
info "开始构建 iOS 真机包 (release) ..."
flutter build ios --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APP_PATH="build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  err "未找到构建产物: $APP_PATH"
  exit 1
fi
ok "iOS 构建成功"
echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  iOS 产物:${NC} $APP_PATH"
echo -e "${GREEN}  文件大小:${NC} $(du -sh "$APP_PATH" | cut -f1)"
echo -e "${GREEN}============================================================${NC}"
echo

# ---------- 8. 安装 ----------
if [ "$NO_INSTALL" = true ]; then
  info "已指定 --no-install，跳过安装"
  echo -e "手动安装命令:"
  echo -e "  ${CYAN}xcrun devicectl device install app --device <UDID> $APP_PATH${NC}"
  exit 0
fi

# 直接用 xcrun devicectl，不走 flutter install（后者会尝试构建其他平台产物）
info "正在安装到已连接的 iOS 真机 ..."
# 获取第一个已连接的真机 UDID
DEVICE_UDID=$(xcrun devicectl list devices --json-output - 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); rs=d.get('result',{}).get('devices',[]); print(next((x['identifier'] for x in rs if x.get('hardwareProperties',{}).get('platform')=='iOS' and x.get('connectionProperties',{}).get('transportType')=='wired'),''))" 2>/dev/null || echo "")

if [ -n "$DEVICE_UDID" ]; then
  if xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"; then
    ok "安装成功！请在 iPhone 上打开应用查看效果"
    warn "若提示「不受信任的开发者」，请在 iPhone: 设置 -> 通用 -> VPN与设备管理 -> 信任你的开发者证书"
  else
    err "xcrun devicectl 安装失败"
    exit 1
  fi
else
  warn "未检测到已连接的 iOS 真机"
  echo
  echo -e "请检查:"
  echo -e "  1. iPhone 已通过 USB 连接并信任此电脑"
  echo -e "  2. ${CYAN}xcrun devicectl list devices${NC} 能看到设备"
  echo -e "  3. 手动安装: ${CYAN}xcrun devicectl device install app --device <UDID> $APP_PATH${NC}"
  exit 1
fi
