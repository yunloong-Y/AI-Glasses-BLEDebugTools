import 'dart:typed_data';

/// ============================================================
/// AI-Glasses-BLEDebugTools - 通用蓝牙抽象层
/// 定义与厂商无关的标准蓝牙操作接口
/// ============================================================

/// 设备类型枚举
enum DeviceType { ble, bredr, twsHeadset, arGlass, unknown }

/// 厂商标识
enum VendorId { bes, qcc, wq, std, unknown }

/// 扫描到的设备信息
class DeviceInfo {
  final String mac;
  final String name;
  final int rssi;
  final VendorId vendorId;
  final DeviceType deviceType;
  final bool supportOta;
  final bool supportAudioDebug;
  final bool supportRegisterRead;
  final List<String> bleServices;

  DeviceInfo({
    required this.mac,
    required this.name,
    required this.rssi,
    this.vendorId = VendorId.unknown,
    this.deviceType = DeviceType.unknown,
    this.supportOta = false,
    this.supportAudioDebug = false,
    this.supportRegisterRead = false,
    this.bleServices = const [],
  });

  factory DeviceInfo.fromMap(Map<String, dynamic> map) {
    return DeviceInfo(
      mac: map['mac'] ?? '',
      name: map['name'] ?? 'Unknown',
      rssi: map['rssi'] ?? 0,
      vendorId: _parseVendorId(map['vendorId']),
      deviceType: _parseDeviceType(map['deviceType']),
      supportOta: map['supportOta'] ?? false,
      supportAudioDebug: map['supportAudioDebug'] ?? false,
      supportRegisterRead: map['supportRegisterRead'] ?? false,
      bleServices: List<String>.from(map['bleServices'] ?? []),
    );
  }

  static VendorId _parseVendorId(String? id) {
    switch (id?.toUpperCase()) {
      case 'BES':
        return VendorId.bes;
      case 'QCC':
        return VendorId.qcc;
      case 'WQ':
        return VendorId.wq;
      case 'STD':
        return VendorId.std;
      default:
        return VendorId.unknown;
    }
  }

  static DeviceType _parseDeviceType(String? type) {
    switch (type?.toUpperCase()) {
      case 'AR_GLASS':
        return DeviceType.arGlass;
      case 'TWS_HEADSET':
        return DeviceType.twsHeadset;
      case 'BLE':
        return DeviceType.ble;
      case 'BREDR':
        return DeviceType.bredr;
      default:
        return DeviceType.unknown;
    }
  }

  Map<String, dynamic> toMap() => {
        'mac': mac,
        'name': name,
        'rssi': rssi,
        'vendorId': vendorId.name.toUpperCase(),
        'deviceType': deviceType.name,
        'supportOta': supportOta,
        'supportAudioDebug': supportAudioDebug,
        'supportRegisterRead': supportRegisterRead,
        'bleServices': bleServices,
      };
}

/// GATT 服务描述
class GattService {
  final String uuid;
  final String? displayName;
  final List<GattCharacteristic> characteristics;

  GattService({
    required this.uuid,
    this.displayName,
    this.characteristics = const [],
  });
}

/// GATT 特征值描述
class GattCharacteristic {
  final String uuid;
  final List<String> properties;
  final String? displayName;
  Uint8List? lastValue;

  GattCharacteristic({
    required this.uuid,
    this.properties = const [],
    this.displayName,
    this.lastValue,
  });
}

/// OTA 升级结果
class OtaResult {
  final bool success;
  final String message;
  final int totalBytes;
  final int sentBytes;
  final Duration elapsed;

  OtaResult({
    required this.success,
    required this.message,
    this.totalBytes = 0,
    this.sentBytes = 0,
    this.elapsed = Duration.zero,
  });
}

/// 日志条目
class LogItem {
  final DateTime timestamp;
  final String deviceMac;
  final LogType type;
  final LogDirection dir;
  final String rawHex;
  final String decodeText;
  final int logLevel;

  LogItem({
    required this.timestamp,
    required this.deviceMac,
    required this.type,
    required this.dir,
    required this.rawHex,
    required this.decodeText,
    this.logLevel = 0,
  });
}

enum LogType { hci, vendorLog, audio, ota, atCmd, system }
enum LogDirection { send, recv }

/// ============================================================
/// 核心抽象接口 - 所有插件必须实现
/// ============================================================
abstract class BaseBluetoothAdapter {
  /// 扫描设备
  Future<List<DeviceInfo>> scanDevices(Duration timeout);

  /// 连接设备
  Future<bool> connect(String mac);

  /// 断开连接
  Future<void> disconnect();

  /// 发现 GATT 服务
  Future<List<GattService>> discoverServices();

  /// 读取特征值
  Future<Uint8List> readChar(String serviceUuid, String charUuid);

  /// 写入特征值
  Future<void> writeChar(
      String serviceUuid, String charUuid, Uint8List data);

  /// 订阅通知
  Future<void> subscribeNotify(
      String serviceUuid, String charUuid, Function(Uint8List) callback);

  /// 取消订阅
  Future<void> unsubscribeNotify(String serviceUuid, String charUuid);

  /// 启动 OTA 升级
  ///
  /// [chunkSize] 为请求的分片大小；设备可能通过协商返回一个更小的值，
  /// 实际生效值以日志/进度回调为准。传 null 时由适配器自行决定（通常 512）。
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress, int? chunkSize});

  /// 暂停 OTA
  Future<void> pauseOta();

  /// 恢复 OTA
  Future<void> resumeOta();

  /// 当前 OTA 已传输字节数（用于断点续传展示）
  int get otaTransferredBytes;
  set otaTransferredBytes(int value);

  /// 获取设备日志流
  Stream<LogItem> getDeviceLogStream();

  /// 打开 SPP 串口通道
  Stream<Uint8List> openSppChannel(int port);

  /// 读取寄存器
  Future<Uint8List> readRegister(int address, int length);

  /// 写入寄存器
  Future<void> writeRegister(int address, Uint8List data);

  /// 发送 AT 指令
  Future<String> sendAtCommand(String cmd);

  /// 获取当前连接状态
  bool get isConnected;

  /// 连接状态变化流（true=已连，false=已断）
  Stream<bool> get connectionStateStream;

  /// 获取设备信息
  DeviceInfo? get deviceInfo;

  /// 最近一次连接失败的原因（成功为 null）
  String? get lastConnectError;
}
