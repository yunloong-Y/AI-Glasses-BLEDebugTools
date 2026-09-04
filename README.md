<div align="center">

# 🔵 AI-Glasses-BLEDebugTools

### Universal Cross-Platform Bluetooth Debug Assistant

**一套同时支持 Android / iOS 双端、兼容主流 AI 眼镜、TWS 耳机、多蓝牙芯片平台的 BLE/BR-EDR 调试工具**

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

</div>

---

## 📖 项目简介

AI-Glasses-BLEDebugTools 是一款面向**硬件固件工程师、音频算法工程师、AR 眼镜驱动开发、产线测试人员**的通用蓝牙调试助手。

基于 Flutter 跨平台框架开发，一套代码同时编译 Android APK 和 iOS IPA，通过插件化架构适配多种芯片方案。

### 🎯 核心定位

| 芯片方案 | 型号 | 典型设备 |
|---------|------|---------|
| **高通 QCC** | QCC3040 / 512X / AR1 | AI AR 眼镜、TWS 耳机 |
| **恒玄 BES** | BES2700 / 2710 / 2800 / 6100 | TWS 耳机、AR 眼镜、智能手表 |
| **物奇微 WQ** | WQ7033 / WQ9000 / WQ7036 | 耳机、AI 眼镜、穿戴设备 |
| **紫光展锐 UNISOC** | W517 | 4G AI 拍照眼镜、AR 显示眼镜 |
| **瑞昱 Realtek** | RTL8763E / RTL8763B / RTL8773 | 音频眼镜、TWS 耳机、助听器眼镜 |
| **炬芯 Actions** | ATS3089C / ATW6095 | 智能穿戴眼镜、智能手表 |
| **Nordic** | nRF54L / nRF5340 | IoT 设备、健康监测眼镜 |
| **通用 BLE** | 任意标准 BLE | 第三方设备 |

### ✨ 核心能力（含实现状态）

> 状态说明：✅ 可在真机上使用 ｜ ⚠️ 有通路但存在限制 ｜ 🚧 未接线/未完成 ｜ ❌ 本架构不支持

- ✅ **BLE GATT 调试** — 服务树可视化、特征值读写、通知订阅
- ✅ **AT 指令请求-响应闭环** — 透传通道自动探测、行缓冲重组、超时判定、指令串行化
- ⚠️ **寄存器读写** — 走 AT 指令通路（设备需实现 `AT+REG_RD/WR`）；写入会校验设备确认，不再假成功
- ⚠️ **OTA 固件升级** — BES 走完整协议（握手/选边/分包协商/逐包 ACK/CRC32/断点续传）；
  QCC、WQ 降级为裸分片传输（无 ACK 与 CRC）。**双通道并行未实现**
- ⚠️ **音频参数调节** — 仅支持厂商通过私有 AT 指令暴露的参数，由插件声明驱动；
  ❌ **不支持 A2DP/HFP 通路切换**（属 BR-EDR 协议栈，纯 BLE 做不到）
- ⚠️ **实时日志** — 记录 App 自身发起的 GATT/AT 交互；
  🚧 抓不到设备侧 HCI / 厂商私有日志流；🚧 PCAP 导出未实现
- 🚧 **产线自动化** — 脚本引擎已实现但**未接入任何 UI**（死代码），9 个指令仅实现 4 个
- 🚧 **蓝牙协议解析** — 解析引擎已实现但**未被调用**（死代码）；
  7 套 JSON 协议仅加载 3 套，另外 4 套因键名不匹配会加载失败
- ❌ **SPP 串口透传** — 项目只依赖 `flutter_blue_plus`（纯 BLE），无 BR-EDR/SPP 能力

---

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────┐
│        UI 交互层 (Flutter 跨平台)             │
│   扫描｜GATT树｜日志｜OTA｜寄存器｜音频｜脚本    │
└────────────────────┬────────────────────────┘
                     ▼
┌─────────────────────────────────────────────┐
│        业务逻辑核心层                          │
│   连接管理｜报文缓存｜日志存储｜脚本引擎        │
└────────────────────┬────────────────────────┘
                     ▼
┌─────────────────────────────────────────────┐
│     通用蓝牙抽象层 (统一接口协议)               │
│   统一 BLE读写/SPP/OTA/日志 API              │
└────────────────────┬────────────────────────┘
                     ▼
┌─────────────────────────────────────────────┐
│     厂商芯片插件层 (热插拔插件架构)             │
│   🔵高通QCC  🟢恒玄BES  🟠物奇微WQ  ⚪通用BLE │
└────────────────────┬────────────────────────┘
                     ▼
┌─────────────────────────────────────────────┐
│        原生底层桥接层  ⚠️ 尚未集成              │
│   Android: BleBridgePlugin.kt                │
│   iOS:     BleBridge.swift                   │
│   两端均未注册进 Flutter 引擎，当前为死代码       │
└─────────────────────────────────────────────┘
```

> **实际链路**：UI → `BleState`(Provider) → `BaseBluetoothAdapter`
> → `StandardBluetoothAdapter` / 厂商 Adapter → `flutter_blue_plus`
> → 平台原生 BLE。厂商差异化逻辑通过 Adapter 子类 + 插件 `canHandle()` 匹配注入。

---

## 📁 工程结构

```
AI-Glasses-BLEDebugTools/
├── lib/                        # Flutter 主代码
│   ├── ui/                     # 所有页面 UI
│   │   ├── scan_page.dart      # 设备扫描页
│   │   ├── gatt_view.dart      # GATT 服务树
│   │   ├── log_console.dart    # 实时日志控制台
│   │   ├── ota_page.dart       # OTA 固件升级
│   │   ├── register_debug.dart # 寄存器 & AT 调试
│   │   ├── audio_debug.dart    # 音频调试面板
│   │   └── plugin_manager.dart # 插件管理
│   ├── core/                   # 业务核心层
│   │   ├── device_manager.dart # 多设备连接池
│   │   ├── log_parser.dart     # 日志解析 & HCI 解码
│   │   ├── script_engine.dart  # 自动化脚本引擎
│   │   └── file_export.dart    # 文件持久化导出
│   ├── adapter/                # 蓝牙抽象层
│   │   ├── base_bluetooth.dart # 标准抽象接口
│   │   └── bluetooth_impl.dart # 标准实现
│   └── plugins/                # 芯片插件目录
│       ├── base_plugin.dart    # 插件基类 & 注册中心
│       ├── qcc_ar_plugin.dart  # 高通 AR1/QCC
│       ├── bes_tws_plugin.dart # 恒玄 BES
│       └── wq_bluetooth_plugin.dart # 物奇微 WQ
├── android/                    # Android 原生桥
├── ios/                        # iOS 原生桥
├── assets/
│   ├── plugin_config/          # 厂商 JSON 协议配置
│   ├── register_map/          # 寄存器映射 CSV
│   └── protocols/             # 🔥 7套芯片厂商BLE协议定义
│       ├── bes_v2.json        # 恒玄 BES2700 (0xA5帧/BCCMD)
│       ├── ar1_v1.json        # 高通 AR1 Gen1 (显示/IMU/相机)
│       ├── wq_v1.json         # 物奇 WQ7036 (0x70076E/CLI双层帧)
│       ├── unisoc_w517.json   # 紫光展锐 W517 (JSON-RPC/Android)
│       ├── realtek_rtl8763e.json # 瑞昱 RTL8763E (TLV/LE Audio)
│       ├── actions_ats3089.json  # 炬芯 ATS3089C (0xACAC帧/AI ENC)
│       └── nordic_nrf54.json  # Nordic nRF54 (SMP/MCUboot OTA)
├── scripts/                    # 产线自动化脚本
└── docs/                       # 开发文档
```

---

## 🚀 快速开始

### 环境要求

- Flutter 3.x
- Dart 3.x
- Android Studio (Android 开发)
- Xcode 15+ (iOS 开发)

### 安装运行

```bash
# 克隆仓库
git clone https://github.com/yunlongyang/AI-Glasses-BLEDebugTools.git
cd AI-Glasses-BLEDebugTools

# 安装依赖
flutter pub get

# 运行 (Android)
flutter run -d android

# 运行 (iOS)
flutter run -d ios
```

---

## 🔌 插件开发

AI-Glasses-BLEDebugTools 采用插件化架构，新增芯片方案无需修改主工程代码。

### 创建自定义插件

```dart
class MyChipPlugin extends BaseChipPlugin {
  @override
  VendorId get vendorId => VendorId.unknown;

  @override
  String get name => 'My Chip';

  @override
  bool canHandle(DeviceInfo device) {
    // 通过广播包判断是否是你的芯片
    return device.name.contains('MY_CHIP');
  }

  @override
  BaseBluetoothAdapter createAdapter() => MyAdapter();
}
```

### JSON 协议配置

每个芯片对应一份 JSON 配置，定义私有 UUID、AT 指令、寄存器映射：

```json
{
  "vendor": "BES",
  "logNotifyChar": "ffe1",
  "otaWriteChar": "ffe2",
  "regReadCmd": "AT+REG_RD=",
  "regWriteCmd": "AT+REG_WR="
}
```

---

## 📋 开发路线图

> 2026-09-03 按实际代码状态重排。原先勾掉的条目多为「UI 骨架完成」，
> 骨架之下的通路大部分是空的，这里逐条改为真实状态。

### 已完成

- [x] 项目框架搭建
- [x] 五层架构骨架
- [x] 三大芯片插件骨架
- [x] 全页面 UI 骨架
- [x] flutter_blue_plus 集成
- [x] GATT 读写 / 通知订阅
- [x] Android 蓝牙权限声明（此前整个 Manifest 零权限，扫描必然返回空）
- [x] UUID 归一化（16-bit 短码 vs 128-bit 全码比较失配，曾导致所有特征查找失败）
- [x] **AT 指令请求-响应闭环**（透传通道探测 + 行缓冲 + 超时 + 串行化）
- [x] 寄存器读写真实回读（不再硬编码返回空 / 假成功）
- [x] **BES OTA 完整协议流程**（握手 / 选边 / 分包协商 / 逐包 ACK / CRC32 / 断点续传）
- [x] 音频调试页重写为「厂商 AT 参数调节」，明确能力边界
- [x] SN 绑定链路（眼镜协议 v2.0.17，真机可用）

### 进行中 / 有通路但有缺陷

- [ ] QCC AR1 插件完整实现 — OTA 暂降级为裸分片，缺 GAIA 升级协议
- [ ] 物奇微 WQ 插件完整实现 — 同上，缺产线模式与烧录校验
- [ ] OTA 双通道并行 — BLE 单链路无法真并行，需厂商确认通道模型
- [ ] 日志 PCAP 导出 — `file_export.dart` 中 `throw UnimplementedError`
- [ ] 设备侧 HCI / 厂商私有日志抓取 — 需原生桥或 HCI snoop 权限

### 未接线（代码已写但全项目零调用）

- [ ] 协议解析引擎 `core/protocol_parser.dart`（839 行，`parseFrame` 零外部调用）
- [ ] 产线脚本引擎 `core/script_engine.dart`（零 import，9 个指令仅实现 4 个）
- [ ] 原生桥接层 `BleBridge.swift` / `BleBridgePlugin.kt`（双端均未注册）
- [ ] 4 套协议 JSON（展锐/瑞昱/炬芯/Nordic）— 键名 `commands` vs
      解析器读的 `commandGroups` 不匹配，加载即失败

### 本架构不支持

- [ ] SPP / BR-EDR 串口透传 — 需引入 `flutter_bluetooth_serial` 并改用经典蓝牙栈
- [ ] A2DP / HFP 音频通路切换 — 属 BR-EDR 音频协议栈，纯 BLE 无法实现
- [ ] 紫光展锐 W517 / 瑞昱 RTL8763E / 炬芯 ATS3089 / Nordic nRF54 插件 —
      仅有协议 JSON，无插件实现

### 规划中

- [ ] PC 配套控制台
- [ ] AI 日志智能分析

---

## ⚠️ 已知限制

接入真机前请先确认这些边界，避免在不可能支持的方向上排查：

1. **纯 BLE，无经典蓝牙**：A2DP / HFP / SPP / PBAP 一律不可用。
   部分 TWS 耳机的 AT 指令其实是走 SPP 的，这类设备本 App 连不上指令通道。
2. **AT 指令强依赖固件实现**：页面上的指令来自插件模板，设备若未实现会直接报
   「设备无响应」而非静默成功——这是刻意设计，调试工具出现假成功比报错更危险。
3. **OTA 有变砖风险**：QCC / WQ 的裸分片传输无 ACK 与 CRC，
   仅建议在已确认通道 UUID 正确的前提下使用。BES 走完整协议流程。
4. **分包大小受 MTU 硬限制**：BLE 单包上限约 `MTU-3` 字节（Android 最大 517），
   界面选的 1024 / 4096 会被自动收敛并提示。
5. **日志只记录 App 自身发起的交互**，抓不到设备侧的 HCI 流
   （需 Android HCI snoop log 或厂商私有日志通道）。

---

## 🤝 开源参考

本项目参考/复用了以下优秀开源项目：

| 项目 | 用途 |
|------|------|
| [flutter_blue_plus](https://github.com/boskokg/flutter_blue_plus) | Flutter 跨平台 BLE 插件（当前唯一的蓝牙依赖） |
| [nRF Connect for Mobile](https://github.com/NordicSemiconductor/nRF-Connect-Mobile) | BLE 调试标杆参考 |
| BesAPP `bes-glass-sdk` | 眼镜协议 v2.0.17 与 OTA 协议（`GlassOtaProtocol`）移植来源 |

> 早期 README 把 `flutter_bluetooth_serial` 列为依赖，但 `pubspec.yaml` 中并
> 未引入——SPP / BR-EDR 目前不支持，见「已知限制」。

---

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源。

- 底层蓝牙抽象层、通用 GATT、日志模块完全开源
- 厂商私有插件可区分开源版 / 商用授权版

---

## 🌟 Star History

如果这个项目对你有帮助，请给个 Star ⭐

---

<div align="center">

Made with 💙 by AI-Glasses-BLEDebugTools Contributors

</div>
