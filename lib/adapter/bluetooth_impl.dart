import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 通用蓝牙实现 - 基于 flutter_blue_plus 的标准实现
/// 所有厂商插件可继承此类并 override 差异化逻辑
/// ============================================================

class StandardBluetoothAdapter implements BaseBluetoothAdapter {
  bool _connected = false;
  DeviceInfo? _deviceInfo;

  /// flutter_blue_plus 设备实例
  fbp.BluetoothDevice? _fbpDevice;

  /// 已发现的服务列表（flutter_blue_plus 原生对象）
  List<fbp.BluetoothService> _fbpServices = [];

  /// notify 订阅管理（charUuid -> subscription）
  final Map<String, StreamSubscription> _notifySubs = {};

  /// 当前 notify 回调
  final Map<String, Function(Uint8List)> _notifyCallbacks = {};

  final StreamController<LogItem> _logController =
      StreamController<LogItem>.broadcast();

  /// 连接状态变化控制器
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  DeviceInfo? get deviceInfo => _deviceInfo;

  /// 连接状态流
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// 获取 flutter_blue_plus 设备实例（供子类使用）
  fbp.BluetoothDevice? get fbpDevice => _fbpDevice;

  /// 获取已发现的服务（flutter_blue_plus 原生）
  List<fbp.BluetoothService> get fbpServices => _fbpServices;

  @override
  Future<List<DeviceInfo>> scanDevices(Duration timeout) async {
    final results = <DeviceInfo>[];
    final seen = <String>{};

    // 监听扫描结果
    final sub = fbp.FlutterBluePlus.onScanResults.listen((scanResult) {
      for (final r in scanResult) {
        final device = r.device;
        final mac = device.remoteId.str;
        if (seen.contains(mac)) {
          // 更新 RSSI
          final idx = results.indexWhere((d) => d.mac == mac);
          if (idx >= 0) {
            results[idx] = DeviceInfo(
              mac: mac,
              name: device.platformName.isNotEmpty
                  ? device.platformName
                  : 'Unknown',
              rssi: r.rssi,
              vendorId: _detectVendor(r),
              deviceType: _detectDeviceType(r),
              bleServices: r.advertisementData.serviceUuids
                  .map((su) => su.str)
                  .toList(),
            );
          }
          continue;
        }
        seen.add(mac);

        // 解析厂商信息
        final vendorId = _detectVendor(r);
        final deviceType = _detectDeviceType(r);

        results.add(DeviceInfo(
          mac: mac,
          name: device.platformName.isNotEmpty ? device.platformName : 'Unknown',
          rssi: r.rssi,
          vendorId: vendorId,
          deviceType: deviceType,
          bleServices: r.advertisementData.serviceUuids
              .map((su) => su.str)
              .toList(),
        ));
      }
    });

    // 启动扫描
    await fbp.FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: const [],
    );

    // 等待扫描完成
    await Future.delayed(timeout);

    await sub.cancel();

    return results;
  }

  /// 实时扫描流（用于 UI 实时更新）
  Stream<DeviceInfo> scanDevicesStream({
    Duration? timeout,
    List<fbp.Guid> withServices = const [],
  }) {
    final controller = StreamController<DeviceInfo>.broadcast();
    final seen = <String>{};

    final sub = fbp.FlutterBluePlus.onScanResults.listen((scanResult) {
      for (final r in scanResult) {
        final device = r.device;
        final mac = device.remoteId.str;
        if (seen.contains(mac)) continue;
        seen.add(mac);

        final vendorId = _detectVendor(r);
        final deviceType = _detectDeviceType(r);

        controller.add(DeviceInfo(
          mac: mac,
          name: device.platformName.isNotEmpty
              ? device.platformName
              : 'Unknown',
          rssi: r.rssi,
          vendorId: vendorId,
          deviceType: deviceType,
          bleServices: r.advertisementData.serviceUuids.map((su) => su.str).toList(),
        ));
      }
    });

    fbp.FlutterBluePlus.startScan(timeout: timeout, withServices: withServices);

    // 扫描结束自动关闭
    final actualTimeout = timeout ?? const Duration(seconds: 10);
    Future.delayed(actualTimeout).then((_) {
      sub.cancel();
      controller.close();
    });

    return controller.stream;
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  /// 检测蓝牙适配器状态
  Future<bool> isBluetoothReady() async {
    return await fbp.FlutterBluePlus.isSupported;
  }

  /// 检查蓝牙是否开启
  bool isBluetoothOn() {
    return fbp.FlutterBluePlus.adapterStateNow == fbp.BluetoothAdapterState.on;
  }

  @override
  Future<bool> connect(String mac) async {
    try {
      _fbpDevice = fbp.BluetoothDevice.fromId(mac);

      // 建立连接
      await _fbpDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      _connected = true;
      _deviceInfo = DeviceInfo(
        mac: mac,
        name: _fbpDevice!.platformName.isNotEmpty
            ? _fbpDevice!.platformName
            : 'Unknown',
        rssi: 0,
      );

      // 监听断连
      _fbpDevice!.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _connected = false;
          _connectionStateController.add(false);
          _pushSystemLog('设备已断开: $mac');
        } else if (state == fbp.BluetoothConnectionState.connected) {
          _connectionStateController.add(true);
        }
      });

      _pushSystemLog('设备已连接: $mac');

      return true;
    } catch (e) {
      _pushSystemLog('连接失败: $mac - $e');
      _connected = false;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_fbpDevice != null) {
        await _fbpDevice!.disconnect();
      }
    } catch (_) {}
    _connected = false;
    _deviceInfo = null;
    _fbpServices.clear();
    _notifySubs.values.forEach((s) => s.cancel());
    _notifySubs.clear();
    _notifyCallbacks.clear();
    _connectionStateController.add(false);
  }

  @override
  Future<List<GattService>> discoverServices() async {
    if (_fbpDevice == null) {
      throw StateError('设备未连接');
    }

    _fbpServices = await _fbpDevice!.discoverServices();

    return _fbpServices.map((svc) {
      return GattService(
        uuid: svc.serviceUuid.str,
        displayName: _getServiceName(svc.serviceUuid.str),
        characteristics: svc.characteristics.map((ch) {
          return GattCharacteristic(
            uuid: ch.characteristicUuid.str,
            properties: _parseCharProperties(ch.properties),
            displayName: _getCharName(ch.characteristicUuid.str),
            lastValue: ch.lastValue.isNotEmpty
                ? Uint8List.fromList(ch.lastValue)
                : null,
          );
        }).toList(),
      );
    }).toList();
  }

  /// 获取 flutter_blue_plus 特征值对象
  fbp.BluetoothCharacteristic? _findChar(String serviceUuid, String charUuid) {
    for (final svc in _fbpServices) {
      if (_uuidMatch(svc.serviceUuid.str, serviceUuid)) {
        for (final ch in svc.characteristics) {
          if (_uuidMatch(ch.characteristicUuid.str, charUuid)) {
            return ch;
          }
        }
      }
    }
    return null;
  }

  bool _uuidMatch(String a, String b) {
    return a.toLowerCase() == b.toLowerCase();
  }

  @override
  Future<Uint8List> readChar(String serviceUuid, String charUuid) async {
    final ch = _findChar(serviceUuid, charUuid);
    if (ch == null) {
      throw StateError('特征值不存在: $charUuid');
    }

    final data = await ch.read();
    final bytes = Uint8List.fromList(data);
    _pushLog(LogType.hci, LogDirection.recv, bytes, 'READ $charUuid');
    return bytes;
  }

  @override
  Future<void> writeChar(
      String serviceUuid, String charUuid, Uint8List data) async {
    final ch = _findChar(serviceUuid, charUuid);
    if (ch == null) {
      throw StateError('特征值不存在: $charUuid');
    }

    // 根据属性选择写入方式
    if (ch.properties.writeWithoutResponse) {
      await ch.write(data, withoutResponse: true);
    } else {
      await ch.write(data, withoutResponse: false);
    }

    _pushLog(LogType.hci, LogDirection.send, data, 'WRITE $charUuid');
  }

  @override
  Future<void> subscribeNotify(
      String serviceUuid, String charUuid, Function(Uint8List) callback) async {
    final ch = _findChar(serviceUuid, charUuid);
    if (ch == null) {
      throw StateError('特征值不存在: $charUuid');
    }

    await ch.setNotifyValue(true);

    _notifyCallbacks[charUuid] = callback;

    final sub = ch.onValueReceived.listen((data) {
      final bytes = Uint8List.fromList(data);
      _pushLog(LogType.hci, LogDirection.recv, bytes, 'NOTIFY $charUuid');
      callback(bytes);
    });
    _notifySubs[charUuid] = sub;
  }

  @override
  Future<void> unsubscribeNotify(String serviceUuid, String charUuid) async {
    final ch = _findChar(serviceUuid, charUuid);
    if (ch != null) {
      await ch.setNotifyValue(false);
    }
    await _notifySubs[charUuid]?.cancel();
    _notifySubs.remove(charUuid);
    _notifyCallbacks.remove(charUuid);
  }

  @override
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress}) async {
    // 标准 OTA 通用流程
    // 厂商特定 OTA 逻辑由各 adapter override
    final file = File(filePath).readAsBytesSync();
    final totalBytes = file.length;
    const chunkSize = 512; // 默认分片
    final totalChunks = (totalBytes / chunkSize).ceil();

    final startTime = DateTime.now();

    try {
      for (var i = 0; i < totalChunks; i++) {
        final offset = i * chunkSize;
        final end = (offset + chunkSize > totalBytes)
            ? totalBytes
            : offset + chunkSize;
        final chunk = Uint8List.sublistView(file, offset, end);

        await writeChar(
          '0000ff00-0000-1000-8000-00805f9b34fb',
          '0000ff01-0000-1000-8000-00805f9b34fb',
          chunk,
        );

        if (onProgress != null) {
          onProgress((i + 1) / totalChunks);
        }

        // 小延迟避免丢包
        await Future.delayed(const Duration(milliseconds: 20));
      }

      final elapsed = DateTime.now().difference(startTime);
      return OtaResult(
        success: true,
        message: 'OTA 升级成功',
        totalBytes: totalBytes,
        sentBytes: totalBytes,
        elapsed: elapsed,
      );
    } catch (e) {
      final elapsed = DateTime.now().difference(startTime);
      return OtaResult(
        success: false,
        message: 'OTA 失败: $e',
        totalBytes: totalBytes,
        sentBytes: 0,
        elapsed: elapsed,
      );
    }
  }

  @override
  Future<void> pauseOta() async {
    // 通用实现：无操作（厂商 adapter 可 override）
  }

  @override
  Future<void> resumeOta() async {
    // 通用实现：无操作
  }

  @override
  Stream<LogItem> getDeviceLogStream() {
    return _logController.stream;
  }

  @override
  Stream<Uint8List> openSppChannel(int port) {
    // SPP 通道通过 BLE Notify 模拟
    final controller = StreamController<Uint8List>.broadcast();
    // 尝试订阅通用 SPP UUID
    subscribeNotify(
      '0000ffe0-0000-1000-8000-00805f9b34fb',
      '0000ffe1-0000-1000-8000-00805f9b34fb',
      (data) => controller.add(data),
    ).catchError((_) {});
    return controller.stream;
  }

  @override
  Future<Uint8List> readRegister(int address, int length) async {
    // 通用实现：通过 AT 指令读取寄存器
    final cmd = 'AT+REG_RD=0x${address.toRadixString(16).toUpperCase()}';
    final result = await sendAtCommand(cmd);
    // 将返回的十六进制字符串转换为 bytes
    return _parseHexResult(result);
  }

  @override
  Future<void> writeRegister(int address, Uint8List data) async {
    final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(',');
    final cmd = 'AT+REG_WR=0x${address.toRadixString(16).toUpperCase()},$hexData';
    await sendAtCommand(cmd);
  }

  @override
  Future<String> sendAtCommand(String cmd) async {
    // 通过 BLE 写入 AT 指令到通用透传通道
    final data = Uint8List.fromList('$cmd\r\n'.codeUnits);
    try {
      await writeChar(
        '0000ffe0-0000-1000-8000-00805f9b34fb',
        '0000ffe1-0000-1000-8000-00805f9b34fb',
        data,
      );
      _pushLog(LogType.atCmd, LogDirection.send, data, cmd);
      return 'OK'; // 实际返回需要等待 notify
    } catch (e) {
      _pushLog(LogType.atCmd, LogDirection.send, data, 'FAILED: $cmd');
      return 'ERROR: $e';
    }
  }

  // ============ 私有辅助方法 ============

  void _pushLog(LogType type, LogDirection dir, Uint8List data, String decode) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _logController.add(LogItem(
      timestamp: DateTime.now(),
      deviceMac: _deviceInfo?.mac ?? '',
      type: type,
      dir: dir,
      rawHex: hex,
      decodeText: decode,
    ));
  }

  void _pushSystemLog(String msg) {
    _logController.add(LogItem(
      timestamp: DateTime.now(),
      deviceMac: _deviceInfo?.mac ?? '',
      type: LogType.system,
      dir: LogDirection.recv,
      rawHex: '',
      decodeText: msg,
    ));
  }

  VendorId _detectVendor(fbp.ScanResult r) {
    final name = r.advertisementData.advName.toLowerCase();
    final services = r.advertisementData.serviceUuids.map((s) => s.str.toLowerCase());

    if (name.contains('bes') || name.contains('bes2700') || name.contains('bes2710')) {
      return VendorId.bes;
    }
    if (name.contains('qcc') || name.contains('ar1') || name.contains('ar-glass')) {
      return VendorId.qcc;
    }
    if (name.contains('wq') || name.contains('wuqi')) {
      return VendorId.wq;
    }

    // 通过 Service UUID 匹配
    for (final uuid in services) {
      if (uuid.startsWith('0000ffe')) return VendorId.bes;
      if (uuid.startsWith('0000fe')) return VendorId.qcc;
    }

    return VendorId.unknown;
  }

  DeviceType _detectDeviceType(fbp.ScanResult r) {
    final name = r.advertisementData.advName.toLowerCase();
    if (name.contains('glass') || name.contains('ar-')) {
      return DeviceType.arGlass;
    }
    if (name.contains('tws') || name.contains('ear') || name.contains('bud')) {
      return DeviceType.twsHeadset;
    }
    return DeviceType.ble;
  }

  List<String> _parseCharProperties(fbp.CharacteristicProperties props) {
    final result = <String>[];
    if (props.read) result.add('read');
    if (props.write) result.add('write');
    if (props.writeWithoutResponse) result.add('writeNoResp');
    if (props.notify) result.add('notify');
    if (props.indicate) result.add('indicate');
    if (props.broadcast) result.add('broadcast');
    return result;
  }

  String _getServiceName(String uuid) {
    final lower = uuid.toLowerCase();
    // 常见标准服务 UUID（短码）
    const known = {
      '1800': 'Generic Access',
      '1801': 'Generic Attribute',
      '180a': 'Device Information',
      '180f': 'Battery Service',
      '180d': 'Heart Rate',
      'ffe0': 'BES Data Service',
      'ff00': 'OTA Service',
      'fe00': 'Custom Service',
    };
    for (final entry in known.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return uuid;
  }

  String _getCharName(String uuid) {
    final lower = uuid.toLowerCase();
    const known = {
      '2a00': 'Device Name',
      '2a01': 'Appearance',
      '2a04': 'Peripheral Preferred',
      '2a19': 'Battery Level',
      '2a29': 'Manufacturer Name',
      '2a24': 'Model Number',
      '2a25': 'Serial Number',
      '2a26': 'Firmware Revision',
      '2a27': 'Hardware Revision',
      'ffe1': 'BES Data',
      'ffe2': 'BES OTA',
      'ff01': 'OTA Write',
      'ff02': 'OTA Notify',
    };
    for (final entry in known.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return uuid;
  }

  Uint8List _parseHexResult(String result) {
    // 尝试从 "0x01,0x02,0x03" 格式解析
    final hexStr = result.replaceAll(RegExp(r'[^0-9a-fA-F,]'), '');
    if (hexStr.isEmpty) return Uint8List(0);
    final parts = hexStr.split(',');
    return Uint8List.fromList(
      parts.where((p) => p.isNotEmpty).map((p) => int.parse(p, radix: 16)).toList(),
    );
  }

  /// 保护方法：向日志流推送日志（供子类调用）
  void pushLog(LogItem item) {
    _logController.add(item);
  }

  void dispose() {
    _notifySubs.values.forEach((s) => s.cancel());
    _logController.close();
    _connectionStateController.close();
  }
}
