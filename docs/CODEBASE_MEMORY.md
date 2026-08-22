# AI-Glasses-BLEDebugTools 代码记忆文档

> 通读全部源码后形成的理解文档，用于跨会话快速回忆架构、数据流与已知坑点。
> 最后更新：2026-08-22（全量通读核实，与 0393bb1 之后的未提交改动一致）
> 代码规模：`lib/` 共 22 个 Dart 文件、约 6901 行。

---

## 1. 项目定位

跨平台 **AI 眼镜 / TWS 耳机 / 通用 BLE 设备** 调试助手。核心能力：BLE 扫描、GATT 浏览与读写、实时通信日志、固件 OTA、寄存器 / AT 指令调试、音频参数调试、厂商协议解析。

- 包名：`aiglasses_bledebugtools`（pubspec.yaml）
- 版本：`1.0.0+1`
- 入口：`lib/main.dart` → `main()` → `runApp(const BleDebugApp())`

---

## 2. 技术栈

| 领域 | 选型 |
|------|------|
| UI 框架 | Flutter 3.x，Material 3，自定义 **iOS 风格** 主题 |
| 状态管理 | `provider`（MultiProvider + ChangeNotifier） |
| BLE 引擎 | `flutter_blue_plus` ^1.32.0（实际底层，非原生桥） |
| 存储 | `path_provider` / `shared_preferences` / `sqflite` |
| 字体/主题 | `google_fonts`（Inter）、`dynamic_color` |
| 权限 | `permission_handler` |
| 文件/分享 | `file_picker` ^9.0.0、`share_plus` ^10.0.0 |
| 其他 | `csv` / `intl` / `crypto`（MD5） |

> 注：构建配置（AGP/Kotlin/Gradle）已降级以复用本地 Gradle 8.14.2，详见第 8 节。

---

## 3. 目录结构（`lib/`）

```
lib/
├── main.dart                 # 入口、启动加载、BleState/导航
├── adapter/
│   ├── base_bluetooth.dart   # 数据模型 + 抽象接口 BaseBluetoothAdapter
│   └── bluetooth_impl.dart   # StandardBluetoothAdapter（flutter_blue_plus 实现）
├── core/
│   ├── device_manager.dart   # 多设备连接池（单例）
│   ├── log_parser.dart       # LogParser（日志缓存/过滤）+ HciLogDecoder
│   ├── protocol_parser.dart  # 协议解析引擎（839 行，最大文件）
│   ├── protocol_registry.dart# ProtocolRegistry（协议注册中心，单例）
│   ├── script_engine.dart    # 自动化脚本引擎 + TestReport
│   └── file_export.dart      # 文件导出（log/pcap/csv）
├── plugins/
│   ├── base_plugin.dart      # BaseChipPlugin + PluginRegistry
│   ├── bes_tws_plugin.dart   # 恒玄 BES 插件 + BesTwsAdapter
│   ├── qcc_ar_plugin.dart    # 高通 QCC/AR1 插件 + QccArAdapter
│   └── wq_bluetooth_plugin.dart # 物奇微 WQ 插件 + WqAdapter
└── ui/
    ├── theme.dart            # AppTheme（亮/暗 iOS 风）+ IosCard/IosEmptyState/IosSectionHeader（2026-08 新增，未提交）
    ├── scan_page.dart        # ① 扫描
    ├── gatt_view.dart        # ② GATT 服务树
    ├── log_console.dart      # ③ 实时日志
    ├── ota_page.dart         # ④ OTA 升级
    ├── register_debug.dart   # ⑤ 寄存器 / AT 调试
    ├── audio_debug.dart      # ⑥ 音频调试
    ├── plugin_manager.dart   # ⑦ 插件管理
    └── protocol_editor.dart  # 协议编辑器（从插件管理页进入）
```

7 个底部导航页：`扫描 / GATT / 日志 / OTA / 寄存器 / 音频 / 插件`（`MainPage` 中 `IndexedStack`）。

---

## 4. 核心架构（分层与职责）

### 4.1 数据模型层 — `adapter/base_bluetooth.dart`
- **枚举**：`DeviceType`（ble/bredr/twsHeadset/arGlass/unknown）、`VendorId`（bes/qcc/wq/std/unknown）、`LogType`（hci/vendorLog/audio/ota/atCmd/system）、`LogDirection`（send/recv）。
- **值对象**：
  - `DeviceInfo`：mac/name/rssi/vendorId/deviceType/能力位(supportOta…)/bleServices，含 `fromMap`/`toMap`。
  - `GattService` / `GattCharacteristic`（含 `lastValue`、`properties` 列表）。
  - `OtaResult`、`LogItem`、`LogType`。
- **抽象接口 `BaseBluetoothAdapter`**：`scanDevices / connect / discoverServices / readChar / writeChar / subscribeNotify / unsubscribeNotify / startOta / pauseOta / resumeOta / getDeviceLogStream / openSppChannel / readRegister / writeRegister / sendAtCommand / isConnected / deviceInfo`。这是一切厂商适配器的契约。

### 4.2 适配器实现 — `adapter/bluetooth_impl.dart`
`StandardBluetoothAdapter implements BaseBluetoothAdapter`，基于 `flutter_blue_plus`：
- `scanDevicesStream(timeout)`：监听 `FlutterBluePlus.onScanResults`，按 mac 去重，输出 `DeviceInfo` 流；vendor/device 类型靠**名称关键词 + Service UUID 前缀**启发式识别。
- `connect(mac)`：用 `BluetoothDevice.fromId` 连接，监听断连，回写 `_connected`。
- `discoverServices`：把 flutter_blue_plus 原生 `BluetoothService` 映射成 `GattService`/`GattCharacteristic`，并做标准 UUID 名称解析（`_getServiceName`/`_getCharName`）。
- `readChar/writeChar/subscribeNotify`：按 UUID 查找特征值并收发；写时按属性选择 `withoutResponse`。
- `startOta`：**通用占位实现**——把固件按 512B 分片写入硬编码 UUID `0000ff00/ff01`，无 ACK/CRC；真实厂商 OTA 由各 Adapter 子类覆盖（目前全部 `throw UnimplementedError`）。
- `openSppChannel`：用 BLE Notify（ffe0/ffe1）模拟串口。
- `readRegister/writeRegister/sendAtCommand`：通过 AT 指令（写 ffe0/ffe1）实现；**缺陷：`sendAtCommand` 写完立即返回字符串 `'OK'`，并不等待设备真实响应**（详见第 9 节）。

### 4.3 状态管理 — `main.dart` 的 `BleState`（ChangeNotifier）
全局单例状态：`scanning / scanResults / selectedDevice / connected / adapter / services`。
- `startScan` → 用 `StandardBluetoothAdapter.scanDevicesStream`。
- `connectDevice(device)` → 委托 `DeviceManager`，成功后把 adapter 的日志流桥接到 `LogParser`，并自动 `discoverServices`。
- 通过 `MultiProvider` 注入 **BleState + DeviceManager + LogParser** 三个单例。

### 4.4 设备管理器 — `core/device_manager.dart`
`DeviceManager`（单例）：维护 `mac -> adapter` 连接池，`maxConnections = 8`。
- `connectDevice`：`PluginRegistry().matchPlugin(device)` 选厂商适配器，失败回退 `StandardBluetoothAdapter`。
- `broadcastCommand`：对所有已连设备批量下发。

### 4.5 插件系统 — `plugins/`
- `BaseChipPlugin`：契约 = `vendorId / name / description / canHandle(DeviceInfo) / createAdapter() / registerMap / atCommandTemplates / otaChunkSize(512) / otaSupportResume / otaSupportDualChannel`。
- `PluginRegistry`（单例）：`register / unregister / matchPlugin(DeviceInfo) / getPlugin(VendorId)`。
- 三个内置插件：
  - `BesTwsPlugin`（bes）：BES2700/2710/2800 耳机&AR；OTA 512B；寄存器映射 ~17 项；AT 模板 ~20 条。
  - `QccArPlugin`（qcc）：QCC3040/512x/AR1；OTA **4096B**、`otaSupportDualChannel=true`；含 AR 显示/IMU/相机指令。
  - `WqBluetoothPlugin`（wq）：WQ7033/9000；OTA 512B；含产线校准/烧录指令。
- 每个插件配套一个 `Adapter` 子类（`BesTwsAdapter`/`QccArAdapter`/`WqAdapter`），**覆盖 `startOta/readRegister/writeRegister`——但当前均 `throw UnimplementedError` 或返回 `Uint8List(0)`**（厂商差异化逻辑未实现）。

### 4.6 协议引擎 — `core/protocol_parser.dart`（839 行）
- **数据模型**（均带 `fromJson/toJson`）：`Endianness`、`ChecksumType`（none/crc8/crc16_ibm/crc16_ccitt/crc32/xor8/sum8/custom）、`FieldEncoding`（hex/ascii/utf8/uint8/16/32/bytes）、`FrameFieldDef`、`FrameFormatDef`（支持魔术字 + 多层字段 + 校验）、`GattCharDef`、`GattServiceDef`、`CommandDef`、`CommandGroup`、`RegisterDef`、`AtCommandDef`、`VendorInfo`、`ProtocolDef`（含 services/frameFormats/commandGroups/registers/atCommands）。
- **解析器 `ProtocolParser`**：`parseFrame`（校验魔术字 → 按字段解析 → 校验和验证）、`parseAuto`（按魔术字自动识别帧格式）、`findCommand`、`findRegister`、`hexToBytes`、`bytesToHex`。
- **校验实现**：`CRC16IBM`（0xA001 多项式，BES 用）、`CRC8`、`ChecksumHelper.compute`。
- `ProtocolRegistry`（单例，文件 `protocol_registry.dart`）：`loadFromJson`、`matchProtocol(deviceName, manufacturerData, serviceUuids)`（按厂商数据前缀 / Service UUID / 设备名匹配协议 ID）——**注意：此方法目前未被任何调用方使用**（见第 9 节）。

### 4.7 脚本引擎 — `core/script_engine.dart`
`ScriptActionType`（delay/connect/disconnect/sendAt/writeReg/readReg/ota/log/assertResult）、`ScriptStep`（repeat/condition）、`TestScript`、`ScriptEngine.execute`（遍历步骤/动作，回调 `onSendAt/onWriteReg/onReadReg`，输出进度流）、`TestReport`/`TestStepResult.toCsv()`。
- `assertResult` 仍是 TODO 桩；脚本引擎**尚未接入任何 UI**。

### 4.8 日志系统 — `core/log_parser.dart`
`LogParser`（单例）：`maxLogCount=100000`，`filterKeyword`/`filterTypes` 过滤，`addLog` 滚动清理，`logStream` 广播，`exportAsText()`；`exportAsPcap()` **抛 UnimplementedError**。`HciLogDecoder`：解析 HCI 命令/ACL/事件包。

### 4.9 文件导出 — `core/file_export.dart`
`FileExporter`：`exportLogFile` / `exportPcapFile` / `exportTestReport`，写入应用文档目录 `ble_debug_exports/`，文件名带时间戳。

---

## 5. UI 层（7 页 + 主题）

- **`scan_page.dart`**：请求蓝牙权限（Android/iOS 分别处理）→ 开关扫描 → 设备卡片（厂商色/图标 + RSSI 质量）→ 点击连接（Cupertino 弹窗，连接中 loading）→ 顶栏显示已连设备徽标。
- **`gatt_view.dart`**：展示 `BleState.services` 为可展开卡片；特征值行带 R/W/N 徽章；底部面板支持 读取 / 订阅 Notify / HEX·ASCII 写入。
- **`log_console.dart`**：监听 `LogParser.logStream`；关键字 + 类型 chip 过滤；自动滚动；导出（`FileExporter` + `Share`）。
- **`ota_page.dart`**：`FilePicker` 选固件 → `crypto` 算 MD5 → 开始升级（`AT+OTA_BEGIN` + `adapter.startOta` + `AT+OTA_END`）→ 暂停/恢复 → 分片大小下拉(128~4096B) + 双通道开关 + 进度条。**注：依赖 `adapter.startOta`，真实厂商会抛异常**。
- **`register_debug.dart`**：分段控件切换「寄存器 / AT」；寄存器读写（hex）；AT 指令输入框 + 厂商模板快捷按钮 + 历史列表。
- **`audio_debug.dart`**：音频模式(A2DP/HFP)、降噪模式(OFF/ANC/通透)、麦克风增益滑块(左右)、音量、低延迟开关——全部经 `adapter.sendAtCommand`。
- **`plugin_manager.dart`**：列出 3 个插件（开关 + 详情底部面板，含 AT 模板/OTA 配置 tag）；入口跳 `ProtocolEditorPage`；「导入」按钮为「待实现」占位。**存在重复注册 bug**（见第 9 节）。
- **`protocol_editor.dart`**：双栏（协议列表 + 详情），5 个 Tab（GATT/帧格式/命令集/寄存器/AT）；导入（粘贴 JSON 或文件路径，可用）/ 导出（弹窗展示 JSON，「复制」按钮为 no-op）。
- **`theme.dart`**（446 行，2026-08 新增未提交）：`AppTheme.light/dark`——iOS 系统色（iosBlue 0xFF007AFF 等）、Google Fonts Inter 字阶、Material 3 组件主题（AppBar 44 高大标题 30 号、卡片 12 圆角零阴影、NavigationBar 56 高）；复用组件 `IosCard`（inset grouped 卡片）/ `IosEmptyState`（圆底图标空态）/ `IosSectionHeader`（大写小字分组头）。所有 UI 页面已统一使用此主题。

---

## 6. 资源层（`assets/`）

- `assets/protocols/*.json` — **7 个协议定义**：
  - 启动自动加载 3 个：`bes_v2`（恒玄，8 服务/5 帧/10 命令/11 寄存器/12 AT）、`ar1_v1`（高通，6/2/8/12/17）、`wq_v1`（物奇微，5/4/7/17/20）。
  - 仅可手动导入 4 个：`actions_ats3089` / `nordic_nrf54` / `realtek_rtl8763e` / `unisoc_w517`。
- `assets/plugin_config/*.json` — `bes_config`/`qcc_config`/`wq_config`：**当前代码未加载**（Dart 在插件类里硬编码 registerMap，这些 JSON 是预留资源）。
- `assets/register_map/bes2710_registers.csv` — 寄存器表：**同样未被代码读取**。
- `assets/*.png` — 应用 Logo 设计稿。

> 资源在 pubspec.yaml 中声明：`assets/plugin_config/`、`assets/register_map/`、`assets/protocols/`。

---

## 7. 原生桥接（Android / iOS）

- **Android** `android/app/.../blebridge/BleBridgePlugin.kt`：类实际名为 `BleBridge`（包 `com.aiglasses_bledebugtools.blebridge`），基于 `BluetoothGatt` 封装 scan/connect/GATT 读写/notify，**但未注册 MethodChannel**，与 Flutter 层无连接。
- **Android** `MainActivity.kt`：包 `com.example.aiglasses_bledebugtools`（`flutter create` 默认前缀）——**与 BleBridge 包名不一致**。
- **iOS** `ios/Runner/BleBridge.swift`：独立 Swift 实现，同样**未接入 Flutter Channel**。

> 结论：原生桥接目前是**游离代码**，App 实际只走 `flutter_blue_plus`。若将来启用原生桥，需统一包名并注册 MethodChannel/Pigeon。

---

## 8. 构建与部署

- 脚本：`build_android.sh`（Android Debug APK → 真机）、`build_ios.sh`（iOS 真机签名包）；均支持 `--no-install`。参考 `BUILD.md`。
- **构建配置降级原因**：`flutter create` 默认 AGP 9.0.1 + Gradle 9.x，本地无 9.x；为复用本地 `gradle-8.14.2` 已改：
  - `android/settings.gradle.kts`：当前 **AGP 8.11.1 + Kotlin 2.2.20**（flutter create 默认 9.0.1 / 2.3.20，已降到与本地 Gradle 8.14.2 兼容的组合；AGP/Kotlin 由用户在 0393bb1 提交中从 8.7.3/2.1.0 上调）。
  - `android/gradle/wrapper/gradle-wrapper.properties`：Gradle `8.14.2`（复用本地缓存，零下载）。
- 依赖修复：`file_picker` 旧版 6.2.1 用了已移除的 v1 Embedding API → 升级到 `^9.2.3`；`share_plus` → `^10.0.0`；新增 `crypto`（OTA 的 MD5）。
- 代码修复（预存笔误）：`main.dart` 类名连字符非法、`bes_tws_plugin.dart` 缺 `dart:typed_data`、`device_manager.dart` import 错位、`script_engine.dart` 构造函数名笔误等，均已修正，`flutter analyze` 当前 **0 error / 约 136 warning·info**（多为 `prefer_const` 等风格）。
- **构建现状（2026-08-22 核实）**：
  - ✅ **Android 已构建成功**：`build/app/outputs/flutter-apk/app-debug.apk` 存在（用户在终端跑 `build_android.sh` 产出，可直接 `adb install` 到真机）。
  - ❌ **iOS 从未构建成功**：无 `build/ios/iphoneos/Runner.app`，`build_ios.sh` 尚未端到端跑通（CocoaPods 安装、Apple Team 签名、pod install 均待验证）。
  - ⚠️ **工作区有大量未提交改动**（截至 2026-08-22）：`git status` 显示 49 项变更（lib/ 十文件约 +2081/−1226 行、新 App 图标全套、iOS 工程配置、`build_ios.sh` 代理关闭+签名自动插入、Android 显示名改「BLE调试工具」、新 `lib/ui/theme.dart` iOS 风格主题、`docs/` 记忆文档）。这些是 0393bb1（08-02）之后继续做的。

---

## 9. 已知问题与风险（2026-08-22 更新）

> ✅ 已修复：①插件重复注册（`PluginRegistry.register/unregister` 已按 vendorId 去重，页面 `isRegistered` 改按 vendorId 判断）；⑥协议编辑器「复制」按钮（已接 `Clipboard.setData` + 复制成功提示）。

1. **OTA 不可用**：`BesTwsAdapter/QccArAdapter/WqAdapter.startOta` 全部 `throw UnimplementedError`；`StandardBluetoothAdapter.startOta` 写硬编码 UUID、无 ACK/CRC —— 真实芯片升级跑不通。

2. **寄存器/AT 读取返回空**：`sendAtCommand` 写完后**立即返回 `'OK'` 字符串，不等待设备 Notify 响应**；厂商 `readRegister` 解析返回时也是 `return Uint8List(0)` + TODO。寄存器调试「读取」显示为空。

3. **`ProtocolRegistry.matchProtocol` 死代码**：定义完善但无任何调用方；当前设备→协议匹配并未真正生效（插件匹配走的是 `PluginRegistry`）。

4. **脚本引擎未接入 UI**：`ScriptEngine`/`TestReport` 完整实现，但没有任何页面调用。

5. **插件管理「导入」为占位**：`_importConfig()` 仅弹「待实现」snackbar。

6. **游离资源**：`assets/plugin_config/*.json` 与 `register_map/*.csv` 未被 Dart 加载（registerMap 硬编码于插件类）。

7. **原生桥包名不一致**：`BleBridge.kt`(com.aiglasses_bledebugtools) 与 `MainActivity.kt`(com.example.aiglasses_bledebugtools) 包不同；启用原生桥前需统一。

8. **`exportAsPcap()` 未实现**：`LogParser.exportAsPcap()` 抛 `UnimplementedError`（PCAP 抓包导出不可用）。

9. **iOS 构建的沙箱坑**：Flutter 3.44 新项目 iOS 侧走 **SPM**（pbxproj 含 3 个 Swift Package 引用）而非 CocoaPods 集成插件，`pod install` 只装 Flutter 主 pod 属正常。在受控沙箱里跑 `flutter build ios` 会报 `sandbox-exec: sandbox_apply: Operation not permitted`（Xcode SPM 的 sandbox-exec 与外层沙箱冲突）——**用户真实终端不受影响**；助手执行需非沙箱模式。

10. **iOS 签名现状**：`build_ios.sh` 已支持 pbxproj 无 `DEVELOPMENT_TEAM` 时自动插入（perl 正则）；团队 ID 存于 `ios_build.env`（已入 .gitignore）。本机证书：`Apple Development: yunlong yang (D5R6L7R52Y)`（个人开发证书）+ `Apple Distribution: Xinmou Technology (V4UW5TMP56)`。

---

## 10. 典型数据流

```
用户点「扫描」(ScanPage)
  → BleState.startScan → StandardBluetoothAdapter.scanDevicesStream
  → 填充 scanResults → 设备卡片列表

用户点设备「连接」
  → BleState.connectDevice → DeviceManager.connectDevice
      → PluginRegistry.matchPlugin → 厂商 Adapter（或标准）
      → adapter.connect(mac)
  → 桥接 adapter 日志流 → LogParser（全局日志）
  → adapter.discoverServices → BleState.services

GATT 页读/写特征值
  → BleState.adapter.readChar/writeChar/subscribeNotify → 经 flutter_blue_plus

寄存器/AT/音频页
  → adapter.readRegister/writeRegister/sendAtCommand
  （当前：写后返回占位 'OK'，真实响应未回读）

OTA 页
  → FilePicker 选固件 → MD5 → AT+OTA_BEGIN → adapter.startOta(分片写) → AT+OTA_END
  （当前：厂商适配器抛 UnimplementedError）
```

---

## 11. 一句话总结

这是一个**架构清晰、UI 完成度高，但底层 BLE 真机交互（OTA / 寄存器 / AT 响应回读）尚未真正打通**的 Flutter BLE 调试工具：Dart 侧全用 `flutter_blue_plus`，厂商差异化逻辑（Adapter 子类）多为 TODO/异常，原生桥接代码游离未集成。后续若要「真能调设备」，优先补齐 `StandardBluetoothAdapter` 的 AT 响应回读与各厂商 `Adapter.startOta/readRegister`。
