# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 项目初始框架搭建
- Flutter 跨平台项目骨架 (Android + iOS)
- 通用蓝牙抽象层 (`BaseBluetoothAdapter` 接口)
- 三大芯片厂商插件骨架:
  - 高通 QCC / AR1 插件
  - 恒玄 BES 插件
  - 物奇微 WQ 插件
- 通用标准 BLE 插件
- UI 页面骨架: 扫描页、GATT 树、日志控制台、OTA、寄存器调试、音频调试、插件管理
- 多设备连接管理器 (支持最多 8 路并发)
- 日志解析与缓存模块 (HCI 报文解码)
- 轻量自动化脚本引擎
- 文件持久化与导出模块
- 厂商 JSON 协议配置文件 (BES / QCC / WQ)
- BES2710 寄存器映射表 (CSV)
- 产线自动化测试脚本示例
- Android BLE Bridge 原生桥代码 (Kotlin)
- iOS BLE Bridge 原生桥代码 (Swift CoreBluetooth)
