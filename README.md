<div align="center">

# 🔵 BlueDebug

### Universal Cross-Platform Bluetooth Debug Assistant

**一套同时支持 Android / iOS 双端、兼容主流 AI 眼镜、TWS 耳机、多蓝牙芯片平台的 BLE/BR-EDR 调试工具**

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

</div>

---

## 📖 项目简介

BlueDebug 是一款面向**硬件固件工程师、音频算法工程师、AR 眼镜驱动开发、产线测试人员**的通用蓝牙调试助手。

基于 Flutter 跨平台框架开发，一套代码同时编译 Android APK 和 iOS IPA，通过插件化架构适配多种芯片方案。

### 🎯 核心定位

| 芯片方案 | 型号 | 典型设备 |
|---------|------|---------|
| **高通 QCC** | QCC3040 / 512X / AR1 | AI AR 眼镜、TWS 耳机 |
| **恒玄 BES** | BES2700 / 2710 / 2800 | TWS 耳机、AR 眼镜 |
| **物奇微 WQ** | WQ7033 / WQ9000 | 耳机、穿戴设备 |
| **通用 BLE** | 任意标准 BLE | 第三方设备 |

### ✨ 核心能力

- **BLE GATT 调试** — 服务树可视化、特征值读写、通知订阅
- **HFP/A2DP 音频调试** — 通路切换、增益调节、ANC 控制
- **SPP 串口透传** — 传统 BR-EDR 耳机串口调试
- **OTA 固件升级** — 自动分片、断点续传、双通道并行（AR 眼镜大固件）
- **寄存器读写** — 批量操作、bit 位解析、十进制/十六进制互转
- **实时日志抓取** — HCI 日志 + 厂商私有日志，毫秒级时间戳
- **产线自动化** — 脚本引擎、批量测试、自动生成报告
- **蓝牙协议解析** — 报文解码、区分厂商私有格式

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
│        原生底层桥接层                          │
│   Android: Kotlin BLE API                    │
│   iOS: Swift CoreBluetooth                   │
└─────────────────────────────────────────────┘
```

---

## 📁 工程结构

```
BlueDebug/
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
│   └── register_map/          # 寄存器映射 CSV
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
git clone https://github.com/yunlongyang/BlueDebug.git
cd BlueDebug

# 安装依赖
flutter pub get

# 运行 (Android)
flutter run -d android

# 运行 (iOS)
flutter run -d ios
```

---

## 🔌 插件开发

BlueDebug 采用插件化架构，新增芯片方案无需修改主工程代码。

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

- [x] 项目框架搭建
- [x] 五层架构骨架
- [x] 三大芯片插件骨架
- [x] 全页面 UI 骨架
- [ ] flutter_blue_plus 集成
- [ ] GATT 读写完整实现
- [ ] OTA 升级核心逻辑
- [ ] 恒玄 BES 插件完整实现
- [ ] 物奇微 WQ 插件完整实现
- [ ] 高通 AR1 插件完整实现
- [ ] 音频调试面板
- [ ] 日志 PCAP 导出
- [ ] 产线自动化脚本引擎
- [ ] PC 配套控制台
- [ ] AI 日志智能分析

---

## 🤝 开源参考

本项目参考/复用了以下优秀开源项目：

| 项目 | 用途 |
|------|------|
| [flutter_blue_plus](https://github.com/boskokg/flutter_blue_plus) | Flutter 跨平台 BLE 插件 |
| [nRF Connect for Mobile](https://github.com/NordicSemiconductor/nRF-Connect-Mobile) | BLE 调试标杆参考 |
| [flutter_bluetooth_serial](https://github.com/edwardatherton/flutter_bluetooth_serial) | SPP 串口透传 |

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

Made with 💙 by BlueDebug Contributors

</div>
