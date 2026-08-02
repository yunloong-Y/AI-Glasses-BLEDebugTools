# 构建指南

本项目提供两个一键构建脚本，自动补齐原生脚手架并构建安装到真机。

---

## 前置条件

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| Flutter SDK | 3.x (已测 3.44.8) | `flutter --version` 检查 |
| Android | adb (Platform Tools) | Android 真机调试用 |
| iOS | Xcode 15+ (已测 26.3) + CocoaPods | 脚本会自动安装 CocoaPods |
| Apple ID | 免费/付费均可 | iOS 签名用，免费证书 7 天过期 |

---

## Android 构建

```bash
# 构建并安装到已连接的 Android 真机
./build_android.sh

# 仅构建不安装
./build_android.sh --no-install
```

**产物**：`build/app/outputs/flutter-apk/app-debug.apk`

**手动安装**（脚本安装失败时）：
```bash
adb install build/app/outputs/flutter-apk/app-debug.apk
```

**确保**：
- 手机已开启「USB 调试」（设置 → 开发者选项）
- `adb devices` 能看到设备

---

## iOS 构建

```bash
# 构建并安装到已连接的 iPhone
./build_ios.sh

# 仅构建不安装
./build_ios.sh --no-install

# 直接指定签名团队（免交互输入）
DEVELOPMENT_TEAM=ABCDE12345 ./build_ios.sh
```

**产物**：`build/ios/iphoneos/Runner.app`

**首次运行**：脚本会提示输入 Apple 开发团队 ID (Team ID)，自动保存到 `ios_build.env`（已加入 `.gitignore`）。

**获取 Team ID**：
- Xcode → Settings → Accounts → 选中你的 Apple ID → Team ID（10 位字母数字）

**安装失败排查**：
- iPhone 需通过 USB 连接并在「信任此电脑」
- `flutter devices` 确认设备已识别
- 手动安装：`xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app`
- 若提示「不受信任的开发者」：iPhone 设置 → 通用 → VPN与设备管理 → 信任开发者证书

---

## 版本号管理

版本号统一从 `pubspec.yaml` 的 `version: 1.0.0+1` 解析，自动传入构建命令，确保 Android 和 iOS 版本一致。

---

## 关于原生脚手架

项目 `android/` 和 `ios/` 目录最初仅包含自定义 BLE 桥接源码（`BleBridgePlugin.kt` / `BleBridge.swift`），缺少 Flutter 标准构建文件。脚本首次运行时会自动执行 `flutter create --platforms=android,ios .` 补齐脚手架，**保留**已有自定义文件，之后直接进入构建流程。

> 注：自定义 BLE 桥接代码尚未接入 Flutter 的 MethodChannel，当前 BLE 功能由 `flutter_blue_plus` 插件提供。原生桥接后续启用时需在 `MainActivity` / `AppDelegate` 中注册。
