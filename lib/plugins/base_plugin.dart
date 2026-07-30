import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 插件基类 - 所有芯片厂商插件继承此类
/// ============================================================

abstract class BaseChipPlugin {
  /// 厂商标识
  VendorId get vendorId;

  /// 插件名称
  String get name;

  /// 插件描述
  String get description;

  /// 是否支持自动识别（通过广播包判断）
  bool canHandle(DeviceInfo device);

  /// 创建对应的蓝牙适配器实例
  BaseBluetoothAdapter createAdapter();

  /// 获取内置寄存器映射表
  Map<int, String> get registerMap;

  /// 获取 AT 指令模板列表
  List<String> get atCommandTemplates;

  /// OTA 分片大小（字节）
  /// 默认 512B (TWS), AR 眼镜建议 4096B
  int get otaChunkSize => 512;

  /// OTA 是否支持断点续传
  bool get otaSupportResume => true;

  /// OTA 是否支持双通道并行传输
  bool get otaSupportDualChannel => false;
}

/// 插件注册中心
class PluginRegistry {
  static final PluginRegistry _instance = PluginRegistry._internal();
  factory PluginRegistry() => _instance;
  PluginRegistry._internal();

  final List<BaseChipPlugin> _plugins = [];

  List<BaseChipPlugin> get plugins => List.unmodifiable(_plugins);

  void register(BaseChipPlugin plugin) {
    _plugins.add(plugin);
  }

  void unregister(BaseChipPlugin plugin) {
    _plugins.remove(plugin);
  }

  /// 根据设备信息自动匹配插件
  BaseChipPlugin? matchPlugin(DeviceInfo device) {
    for (final p in _plugins) {
      if (p.canHandle(device)) return p;
    }
    return null;
  }

  /// 根据 vendorId 获取插件
  BaseChipPlugin? getPlugin(VendorId id) {
    for (final p in _plugins) {
      if (p.vendorId == id) return p;
    }
    return null;
  }
}
