import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../adapter/base_bluetooth.dart';
import '../core/at_transport.dart';
// 用前缀导入：本类保留同名静态 normalizeUuid 作为兼容别名
import '../core/ble_uuid.dart' as ble_uuid;

/// ============================================================
/// 通用蓝牙实现 - 基于 flutter_blue_plus 的标准实现
/// 所有厂商插件可继承此类并 override 差异化逻辑
///
/// 同时实现 [AtIo]，为 [AtTransport] 提供底层读写能力。
/// ============================================================

class StandardBluetoothAdapter implements BaseBluetoothAdapter, AtIo {
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

  /// 协商后的 ATT MTU（默认值用于未协商时的保守估算）
  int _mtu = 23;

  /// AT 透传通道（连接后惰性探测，断开时释放）
  AtTransport? _atTransport;

  /// 探测到的透传通道（供 atWrite/atSubscribe 定位特征）
  AtTransportSelection? _atSelection;

  /// AT 通道探测失败原因（避免每次调用重复探测并重复抛错）
  String? _atProbeError;

  @override
  bool get isConnected => _connected;

  @override
  DeviceInfo? get deviceInfo => _deviceInfo;

  /// 最近一次连接失败原因（成功或未曾失败为 null）
  String? _lastConnectError;
  @override
  String? get lastConnectError => _lastConnectError;

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
                  .map((su) => su.str128)
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
              .map((su) => su.str128)
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
  ///
  /// 实现要点：
  /// 1. 必须 **先 startScan 再订阅 scanResults**。若反过来用 `onScanResults`，
  ///    在未扫描时它会返回 `_scanResults.stream.skip(1)`，吞掉第一批结果。
  /// 2. 使用 `scanResults`（而非 `onScanResults`）以持续获取同一设备的 RSSI 刷新。
  /// 3. `androidCheckLocationServices: false` —— 已在 Manifest 中给
  ///    BLUETOOTH_SCAN 声明 `neverForLocation`，无需系统位置服务开启。
  Stream<DeviceInfo> scanDevicesStream({
    Duration? timeout,
    List<fbp.Guid> withServices = const [],
  }) {
    final controller = StreamController<DeviceInfo>();
    StreamSubscription? scanSub;

    controller.onCancel = () async {
      await scanSub?.cancel();
      await fbp.FlutterBluePlus.stopScan();
    };

    () async {
      try {
        await fbp.FlutterBluePlus.startScan(
          timeout: timeout,
          withServices: withServices,
          continuousUpdates: true,
          androidCheckLocationServices: false,
        );

        // startScan 返回后订阅：scanResults 会先补发当前已缓存的结果快照
        scanSub = fbp.FlutterBluePlus.scanResults.listen(
          (results) {
            if (controller.isClosed) return;
            for (final r in results) {
              final device = r.device;
              final mac = device.remoteId.str;
              controller.add(DeviceInfo(
                mac: mac,
                name: device.platformName.isNotEmpty
                    ? device.platformName
                    : 'Unknown',
                rssi: r.rssi,
                vendorId: _detectVendor(r),
                deviceType: _detectDeviceType(r),
                // 用 str128 而非 str：str 会把 16-bit UUID 压成 "ffe0"，
                // 导致插件 canHandle() 里写的 128-bit 常量永远匹配不上，
                // 厂商专用 adapter 因此永远不会被选中。
                bleServices: r.advertisementData.serviceUuids
                    .map((su) => su.str128)
                    .toList(),
              ));
            }
          },
          onError: (Object e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        // 等待扫描真正结束（自然超时或外部 stopScan）
        await fbp.FlutterBluePlus.isScanning.firstWhere((s) => s == false);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      } finally {
        await scanSub?.cancel();
        if (!controller.isClosed) await controller.close();
      }
    }();

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
    _lastConnectError = null;
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

      // 协商更大的 MTU：默认 23B 会让稍长一点的 AT 指令被拆包，
      // 部分固件按包解析，拆包即丢弃。
      //
      // 注意 `requestMtu` 是 **Android only**，iOS 上直接抛
      // FlutterBluePlusException("android-only")。iOS 由系统自动协商
      // （通常 185+），只需读 `mtuNow`。两侧最后统一以 mtuNow 为准。
      if (Platform.isAndroid) {
        try {
          await _fbpDevice!.requestMtu(517);
        } catch (e) {
          _pushSystemLog('MTU 协商未生效，使用系统默认: $e');
        }
      }
      _mtu = _fbpDevice!.mtuNow;
      if (_mtu > 23) {
        _pushSystemLog('ATT MTU = $_mtu 字节（单包可写 ${atMtuPayload} 字节）');
      }

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
      _lastConnectError = e.toString();
      _pushSystemLog('连接失败: $mac - $e');
      _connected = false;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    // 先释放 AT 通道（它会取消 notify 订阅与在途请求）
    await _atTransport?.dispose();
    _atTransport = null;
    _atSelection = null;
    _atProbeError = null;
    _mtu = 23;

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

  /// 把任意写法归一化为 128-bit 小写形式
  ///
  /// 背景（致命坑）：flutter_blue_plus 的 `Guid.str` 返回的是**最短表示**——
  /// 16-bit UUID `0000ffe1-0000-1000-8000-00805f9b34fb` 会被压成 `"ffe1"`。
  /// 而项目里常量常写成完整 128-bit 形式，两者直接字符串比较必然失配，
  /// 导致 `_findChar` 永远返回 null → 读写特征值一律抛
  /// `StateError('特征值不存在')`。AT 指令、寄存器、OTA、SPP 全部受此影响。
  ///
  /// 实现统一收口在 `core/ble_uuid.dart`，此处仅做转发的兼容别名。
  static String normalizeUuid(String uuid) => ble_uuid.normalizeUuid(uuid);

  bool _uuidMatch(String a, String b) => ble_uuid.uuidEquals(a, b);

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

  /// 已传输字节数（断点续传展示用）
  int _otaTransferredBytes = 0;

  @override
  int get otaTransferredBytes => _otaTransferredBytes;

  @override
  set otaTransferredBytes(int value) => _otaTransferredBytes = value;

  /// OTA 通道 UUID（厂商 adapter 按需覆盖）
  String get otaServiceUuid => '0000ff00-0000-1000-8000-00805f9b34fb';
  String get otaWriteCharUuid => '0000ff01-0000-1000-8000-00805f9b34fb';
  String get otaNotifyCharUuid => '0000ff02-0000-1000-8000-00805f9b34fb';

  @override
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress, int? chunkSize}) async {
    // 标准 OTA 通用流程（无厂商握手的裸分片传输）
    // 厂商特定 OTA 逻辑由各 adapter override
    final file = File(filePath);
    if (!await file.exists()) {
      return OtaResult(
          success: false, message: '固件文件不存在: $filePath');
    }

    final data = Uint8List.fromList(await file.readAsBytes());
    if (data.isEmpty) {
      return OtaResult(success: false, message: '固件文件为空');
    }

    final totalBytes = data.length;
    final startTime = DateTime.now();
    _otaTransferredBytes = 0;

    // 分片大小受 ATT MTU 硬限制：BLE 单包最多 (MTU-3) 字节，
    // Android 最大 MTU 517 → 单包上限 514B。UI 选的 4096 在 BLE 上不现实。
    final requested = chunkSize ?? 512;
    final effective = requested > atMtuPayload ? atMtuPayload : requested;
    if (effective != requested) {
      _pushSystemLog('OTA 分片由 ${requested}B 下调至 ${effective}B'
          '（ATT MTU=$_mtu，单包上限 ${atMtuPayload}B）');
    }

    if (_fbpServices.isEmpty) {
      try {
        await discoverServices();
      } catch (e) {
        return OtaResult(
            success: false, message: 'GATT 服务发现失败: $e', totalBytes: totalBytes);
      }
    }

    final writeTarget = _findChar(otaServiceUuid, otaWriteCharUuid);
    if (writeTarget == null) {
      return OtaResult(
        success: false,
        message: '未找到 OTA 写入特征 ${uuidShortOf(otaWriteCharUuid)}'
            '（服务 ${uuidShortOf(otaServiceUuid)}）。'
            '请在 GATT 页确认设备暴露的 OTA 服务，'
            '或由厂商插件覆盖 otaServiceUuid / otaWriteCharUuid。',
        totalBytes: totalBytes,
      );
    }

    // 尝试订阅 OTA 进度通知；拿不到就退化为盲发（仅记录，不阻塞）
    var hasProgressNotify = false;
    try {
      await subscribeNotify(otaServiceUuid, otaNotifyCharUuid, (bytes) {
        _pushLog(LogType.ota, LogDirection.recv, bytes, 'OTA 进度');
      });
      hasProgressNotify = true;
    } catch (_) {
      _pushSystemLog('OTA 通知通道不可用，退化为盲发（不等待设备 ACK）');
    }

    final totalChunks = (totalBytes / effective).ceil();
    _pushSystemLog('开始 OTA：${totalBytes}B / $totalChunks 片 × ${effective}B');

    try {
      for (var i = 0; i < totalChunks; i++) {
        if (_otaAbortRequested) {
          return OtaResult(
            success: false,
            message: 'OTA 已中止（断点 offset=$_otaTransferredBytes）',
            totalBytes: totalBytes,
            sentBytes: _otaTransferredBytes,
            elapsed: DateTime.now().difference(startTime),
          );
        }

        final offset = i * effective;
        final end =
            (offset + effective > totalBytes) ? totalBytes : offset + effective;
        final chunk = Uint8List.sublistView(data, offset, end);

        await writeChar(otaServiceUuid, otaWriteCharUuid, chunk);
        _otaTransferredBytes = end;

        onProgress?.call(_otaTransferredBytes / totalBytes);

        // 小延迟避免丢包；有通知通道时可以更快
        await Future.delayed(
            Duration(milliseconds: hasProgressNotify ? 8 : 20));
      }

      return OtaResult(
        success: true,
        message: 'OTA 传输完成（${totalBytes}B，未做设备端校验）',
        totalBytes: totalBytes,
        sentBytes: totalBytes,
        elapsed: DateTime.now().difference(startTime),
      );
    } catch (e) {
      return OtaResult(
        success: false,
        message: 'OTA 失败: $e（已发送 $_otaTransferredBytes/$totalBytes 字节）',
        totalBytes: totalBytes,
        sentBytes: _otaTransferredBytes,
        elapsed: DateTime.now().difference(startTime),
      );
    }
  }

  /// OTA 中止请求标志（pauseOta 置位，startOta 循环内检查）
  bool _otaAbortRequested = false;

  @override
  Future<void> pauseOta() async {
    // 通用实现：请求中止循环。厂商 adapter 可覆盖为真正的协议级暂停。
    _otaAbortRequested = true;
    _pushSystemLog('已请求中止 OTA，将在当前分片结束后停止');
  }

  @override
  Future<void> resumeOta() async {
    // 通用实现：清除中止标志。真正的断点续传需要协议层记录 offset，
    // 由厂商 adapter（如 BesTwsAdapter）override 实现。
    _otaAbortRequested = false;
    _pushSystemLog('已清除中止标志（通用通道不支持断点续传，将重新传输）');
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

  // ============ AT 透传通道 ============

  /// 单包可写字节数（ATT 头占 3 字节）
  @override
  int get atMtuPayload => _mtu > 3 ? _mtu - 3 : 20;

  @override
  Future<void> atWrite(Uint8List data, {bool withoutResponse = false}) async {
    final sel = _atSelection;
    if (sel == null) {
      throw const AtTransportException('AT 通道未初始化');
    }
    final ch = _findChar(sel.serviceUuid, sel.writeUuid);
    if (ch == null) {
      throw StateError('AT 写入特征不存在: ${sel.writeUuid}');
    }

    // 优先带响应的写入（可确认对端已收到），仅在特征不支持时降级
    final useWithoutResponse =
        withoutResponse || (ch.properties.writeWithoutResponse && !ch.properties.write);
    await ch.write(data, withoutResponse: useWithoutResponse);
    _pushLog(LogType.atCmd, LogDirection.send, data,
        'AT WRITE ${uuidShortOf(sel.writeUuid)}');
  }

  @override
  Future<void> atSubscribe(Function(Uint8List) onData) async {
    final sel = _atSelection;
    if (sel == null) {
      throw const AtTransportException('AT 通道未初始化');
    }
    await subscribeNotify(sel.serviceUuid, sel.notifyUuid, onData);
  }

  @override
  Future<void> atUnsubscribe() async {
    final sel = _atSelection;
    if (sel == null) return;
    await unsubscribeNotify(sel.serviceUuid, sel.notifyUuid);
  }

  /// 探测并构建 AT 透传通道（首次调用时执行，结果缓存）
  ///
  /// 优先匹配已知厂商通道表，匹配不到则自动挑选具备
  /// notify + write 能力的特征对，让未知固件也能用起来。
  Future<AtTransport> _ensureAtTransport() async {
    if (_atTransport != null) return _atTransport!;
    if (_atProbeError != null) {
      throw AtTransportException(_atProbeError!);
    }

    if (_fbpServices.isEmpty) {
      await discoverServices();
    }

    final endpoints = _gattEndpoints();
    final selection = selectAtTransport(endpoints);
    if (selection == null) {
      _atProbeError = '未找到可用的 AT 透传通道。'
          '设备需具备一个可 Notify + 一个可 Write 的特征值'
          '（已扫描 ${endpoints.length} 个特征，'
          '其中 notify ${endpoints.where((e) => e.canNotify).length} 个、'
          'write ${endpoints.where((e) => e.canWrite).length} 个）。'
          '请在 GATT 页确认服务是否发现完整。';
      throw AtTransportException(_atProbeError!);
    }

    _atSelection = selection;
    _atTransport = AtTransport(
      io: this,
      selection: selection,
      onLog: (msg) => _pushLog(LogType.atCmd, LogDirection.recv, Uint8List(0), msg),
      onUnsolicited: (line) => _pushSystemLog('设备上报: $line'),
    );
    _pushSystemLog('AT 透传通道: $selection');
    return _atTransport!;
  }

  /// 导出 GATT 端点（供通道探测，与 flutter_blue_plus 类型解耦）
  List<GattEndpoint> _gattEndpoints() {
    final out = <GattEndpoint>[];
    for (final svc in _fbpServices) {
      for (final ch in svc.characteristics) {
        out.add(GattEndpoint(
          serviceUuid: svc.serviceUuid.str,
          charUuid: ch.characteristicUuid.str,
          properties: _parseCharProperties(ch.properties).toSet(),
        ));
      }
    }
    return out;
  }

  /// 当前 AT 透传通道描述（未探测时为 null）
  AtTransportSelection? get atTransportSelection => _atSelection;

  @override
  Future<Uint8List> readRegister(int address, int length) async {
    final cmd =
        'AT+REG_RD=0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    // 用 Detailed 版本：即使设备回 ERROR 或超时，也要拿到原始响应
    // 用于报错时告诉用户设备到底回了什么（`sendAtCommand` 会直接抛异常）
    final resp = await sendAtCommandDetailed(cmd);

    final bytes = _parseRegisterValue(resp, address);
    if (bytes.isEmpty) {
      throw AtTransportException(
          '寄存器 0x${address.toRadixString(16).toUpperCase()} 未解析到有效数据'
          '（设备响应: ${resp.raw.isEmpty ? "无" : resp.raw}）');
    }
    return bytes;
  }

  @override
  Future<void> writeRegister(int address, Uint8List data) async {
    final hexData =
        data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(',');
    final cmd =
        'AT+REG_WR=0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')},$hexData';
    final resp = await sendAtCommandDetailed(cmd);

    // 关键：不再无条件返回成功。写入必须拿到设备确认，
    // 否则抛异常让 UI 显示红色错误——调试工具的「假成功」比报错更危险。
    if (!resp.ok) {
      throw AtTransportException(
          '寄存器写入未被设备确认: ${resp.timedOut ? "等待响应超时" : resp.finalLine}');
    }
  }

  @override
  Future<String> sendAtCommand(String cmd) async {
    final transport = await _ensureAtTransport();
    final resp = await transport.transact(cmd);

    // 严格模式：设备未确认即视为失败。
    // 绝不把「无响应」或「设备回 ERROR」伪装成 OK —— 调试工具的假成功
    // 会让工程师在错误的方向上排查很久，比直接报错危险得多。
    if (!resp.ok) {
      throw AtTransportException(
        resp.timedOut
            ? '设备无响应（等待 ${transport.responseTimeout.inSeconds}s 超时）'
                '${resp.lines.isEmpty ? "" : "，期间收到: ${resp.lines.join(" | ")}"}'
            : '设备返回错误: ${resp.finalLine}',
      );
    }

    return resp.lines.isEmpty ? (resp.finalLine ?? 'OK') : resp.lines.join(' | ');
  }

  /// 发送 AT 指令并拿到底层响应对象（供需要区分 ok / 数据行的场景）
  Future<AtResponse> sendAtCommandDetailed(String cmd) async {
    final transport = await _ensureAtTransport();
    return transport.transact(cmd);
  }

  /// 从 AT 响应中解析寄存器字节
  ///
  /// 兼容多种固件格式：
  ///   `+REG_RD:0x10,0x5A`  /  `REG_RD=0x10,5A`  /  `0x5A`  /  `+REG_RD:5A`
  Uint8List _parseRegisterValue(AtResponse resp, int address) {
    final addrHex = address.toRadixString(16).toLowerCase();
    final addrDec = address.toString();

    for (final line in resp.lines) {
      var s = line.trim();

      // 去掉 `+XXX:` 或 `XXX=` 前缀
      final colonIdx = s.indexOf(':');
      if (colonIdx >= 0) s = s.substring(colonIdx + 1);
      final eqIdx = s.indexOf('=');
      if (eqIdx >= 0) s = s.substring(eqIdx + 1);

      // 若第一段是地址（本指令的地址），丢弃它
      final parts = s.split(',').map((p) => p.trim()).toList();
      if (parts.length > 1) {
        final first = parts.first.toLowerCase().replaceAll('0x', '');
        if (first == addrHex || first == addrDec) {
          parts.removeAt(0);
        }
      }

      final bytes = <int>[];
      for (final part in parts) {
        final token = part.toLowerCase().replaceAll('0x', '');
        if (token.isEmpty) continue;
        // 支持 "5a 7f" 空格分隔以及 "5a7f" 连续 hex
        final chunks = token.contains(' ') ? token.split(RegExp(r'\s+')) : [token];
        for (final c in chunks) {
          if (c.length == 2) {
            final v = int.tryParse(c, radix: 16);
            if (v != null) bytes.add(v);
          } else if (c.length == 4 || c.length == 8) {
            // 32-bit 值按大端拆字节（固件常返回整字）
            final v = int.tryParse(c, radix: 16);
            if (v != null) {
              final n = c.length ~/ 2;
              for (var i = n - 1; i >= 0; i--) {
                bytes.add((v >> (i * 8)) & 0xFF);
              }
            }
          }
        }
      }
      if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
    }
    return Uint8List(0);
  }

  /// UUID 短码显示（日志用）
  String uuidShortOf(String uuid) => ble_uuid.uuidShort(uuid);

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

  /// 保护入口：子类向日志流推送一条系统日志（跨库可见版本）
  void pushSystemLog(String msg) => _pushSystemLog(msg);

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
    // 同样必须归一化：str 返回短格式 "ffe0"，不以 "0000ffe" 开头
    final services =
        r.advertisementData.serviceUuids.map((su) => normalizeUuid(su.str));

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

  /// 保护方法：向日志流推送日志（供子类调用）
  void pushLog(LogItem item) {
    _logController.add(item);
  }

  void dispose() {
    _atTransport?.dispose();
    _atTransport = null;
    _notifySubs.values.forEach((s) => s.cancel());
    _logController.close();
    _connectionStateController.close();
  }
}
