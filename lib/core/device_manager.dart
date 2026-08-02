import 'dart:async';
import '../adapter/base_bluetooth.dart';
import '../adapter/bluetooth_impl.dart';
import '../plugins/base_plugin.dart';

/// ============================================================
/// 多设备连接管理器
/// 维护连接池，独立消息队列，多设备日志隔离
/// ============================================================

class DeviceManager {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;
  DeviceManager._internal();

  /// 已连接设备池 (mac -> adapter)
  final Map<String, BaseBluetoothAdapter> _connected = {};

  /// 最大并发连接数
  static const int maxConnections = 8;

  /// 当前连接数
  int get connectionCount => _connected.length;

  /// 获取所有已连接设备 MAC
  List<String> get connectedMacs => _connected.keys.toList();

  /// 连接设备
  Future<bool> connectDevice(DeviceInfo device) async {
    if (_connected.length >= maxConnections) {
      throw Exception('已达最大连接数 $maxConnections');
    }
    if (_connected.containsKey(device.mac)) {
      return true; // 已连接
    }

    // 自动匹配插件
    final plugin = PluginRegistry().matchPlugin(device);
    final adapter = plugin?.createAdapter() ?? StandardBluetoothAdapter();

    final ok = await adapter.connect(device.mac);
    if (ok) {
      _connected[device.mac] = adapter;
    }
    return ok;
  }

  /// 断开设备
  Future<void> disconnectDevice(String mac) async {
    final adapter = _connected.remove(mac);
    await adapter?.disconnect();
  }

  /// 断开所有设备
  Future<void> disconnectAll() async {
    for (final adapter in _connected.values) {
      await adapter.disconnect();
    }
    _connected.clear();
  }

  /// 获取指定设备的适配器
  BaseBluetoothAdapter? getAdapter(String mac) => _connected[mac];

  /// 批量下发指令
  Future<void> broadcastCommand(
      Future Function(BaseBluetoothAdapter) action) async {
    final futures = _connected.values.map((a) => action(a));
    await Future.wait(futures);
  }
}
