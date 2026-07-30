import 'dart:async';
import 'dart:typed_data';
import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 通用蓝牙实现 - 基于 flutter_blue_plus 的标准实现
/// 所有厂商插件可继承此类并 override 差异化逻辑
/// ============================================================

class StandardBluetoothAdapter implements BaseBluetoothAdapter {
  bool _connected = false;
  DeviceInfo? _deviceInfo;

  // flutter_blue_plus 实例 (后续引入)
  // FlutterBluePlus _fbp = FlutterBluePlus();

  final StreamController<LogItem> _logController =
      StreamController<LogItem>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  DeviceInfo? get deviceInfo => _deviceInfo;

  @override
  Future<List<DeviceInfo>> scanDevices(Duration timeout) async {
    // TODO: 接入 flutter_blue_plus 扫描
    // 1. 启动扫描，收集广播包
    // 2. 解析厂商 UUID 自动识别 vendorId
    // 3. 返回 DeviceInfo 列表
    throw UnimplementedError('scanDevices not yet implemented');
  }

  @override
  Future<bool> connect(String mac) async {
    // TODO: 连接设备，发现服务
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _deviceInfo = null;
  }

  @override
  Future<List<GattService>> discoverServices() async {
    // TODO: 发现并解析 GATT 服务树
    throw UnimplementedError('discoverServices not yet implemented');
  }

  @override
  Future<Uint8List> readChar(
      String serviceUuid, String charUuid) async {
    throw UnimplementedError('readChar not yet implemented');
  }

  @override
  Future<void> writeChar(
      String serviceUuid, String charUuid, Uint8List data) async {
    throw UnimplementedError('writeChar not yet implemented');
  }

  @override
  Future<void> subscribeNotify(
      String serviceUuid, String charUuid, Function(Uint8List) callback) async {
    throw UnimplementedError('subscribeNotify not yet implemented');
  }

  @override
  Future<void> unsubscribeNotify(
      String serviceUuid, String charUuid) async {
    throw UnimplementedError('unsubscribeNotify not yet implemented');
  }

  @override
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress}) async {
    // 标准 OTA 流程:
    // 1. 校验固件 MD5
    // 2. 自动分片（512B for TWS, 4096B for AR）
    // 3. 传输 + 断点续传
    // 4. 校验 + 重启
    throw UnimplementedError('startOta not yet implemented');
  }

  @override
  Future<void> pauseOta() async {
    throw UnimplementedError('pauseOta not yet implemented');
  }

  @override
  Future<void> resumeOta() async {
    throw UnimplementedError('resumeOta not yet implemented');
  }

  @override
  Stream<LogItem> getDeviceLogStream() {
    return _logController.stream;
  }

  @override
  Stream<Uint8List> openSppChannel(int port) {
    throw UnimplementedError('openSppChannel not yet implemented');
  }

  @override
  Future<Uint8List> readRegister(int address, int length) async {
    throw UnimplementedError('readRegister not yet implemented');
  }

  @override
  Future<void> writeRegister(int address, Uint8List data) async {
    throw UnimplementedError('writeRegister not yet implemented');
  }

  @override
  Future<String> sendAtCommand(String cmd) async {
    throw UnimplementedError('sendAtCommand not yet implemented');
  }

  /// 保护方法：向日志流推送日志（供子类调用）
  void pushLog(LogItem item) {
    _logController.add(item);
  }

  void dispose() {
    _logController.close();
  }
}
