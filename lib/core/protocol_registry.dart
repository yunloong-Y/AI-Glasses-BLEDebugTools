/// BlueDebug Protocol Registry
///
/// 协议注册中心：管理所有已加载的协议定义，支持热加载、卸载、查询。
/// 内置三种厂商协议的快速匹配逻辑。

import 'dart:convert';
import 'dart:typed_data';
import 'protocol_parser.dart';

/// 协议注册中心
class ProtocolRegistry {
  static final ProtocolRegistry _instance = ProtocolRegistry._();
  factory ProtocolRegistry() => _instance;
  ProtocolRegistry._();

  final Map<String, ProtocolDef> _protocols = {};

  /// 根据协议 ID 查询
  ProtocolDef? get(String id) => _protocols[id];

  /// 所有已注册协议
  List<ProtocolDef> get all => _protocols.values.toList();

  /// 协议 ID 列表
  List<String> get ids => _protocols.keys.toList();

  /// 注册协议
  void register(ProtocolDef protocol) {
    _protocols[protocol.id] = protocol;
  }

  /// 从 JSON 文件内容加载协议
  ProtocolDef loadFromJson(String jsonStr) {
    final protocol = ProtocolParser.loadProtocol(jsonStr);
    register(protocol);
    return protocol;
  }

  /// 卸载协议
  void unregister(String id) {
    _protocols.remove(id);
  }

  /// 根据设备广播数据自动匹配协议
  /// 返回匹配的协议 ID，未匹配返回 null
  String? matchProtocol({
    required String? deviceName,
    required Uint8List? manufacturerData,
    required Map<String, List<String>>? serviceUuids,
  }) {
    // 策略 1: 制造商数据前缀匹配
    if (manufacturerData != null && manufacturerData.isNotEmpty) {
      // BES 制造商数据 (HSC 前缀)
      if (_checkPrefix(manufacturerData, [0x48, 0x53, 0x43])) {
        return 'bes_v2';
      }
    }

    // 策略 2: Service UUID 匹配
    if (serviceUuids != null) {
      final allUuids = serviceUuids.values.expand((l) => l).toSet();

      // BES
      if (allUuids.any((u) =>
          u.toUpperCase().contains('2000-8000-009078563412') ||
          u.toUpperCase().contains('66666666-6666-6666'))) {
        return 'bes_v2';
      }

      // WQ
      if (allUuids.any((u) =>
          u.toUpperCase().contains('00007033') ||
          u.toUpperCase().contains('00007034'))) {
        return 'wq_v1';
      }

      // AR1 / QCC
      if (allUuids.any((u) =>
          u.toUpperCase().contains('0000FF00'))) {
        return 'ar1_v1';
      }
    }

    // 策略 3: 设备名称关键词匹配
    if (deviceName != null) {
      final name = deviceName.toUpperCase();
      if (name.contains('BES') || name.contains('MOONIX')) return 'bes_v2';
      if (name.contains('WQ') || name.contains('WUQI')) return 'wq_v1';
      if (name.contains('AR') || name.contains('SNAPDRAGON') || name.contains('QCC')) return 'ar1_v1';
    }

    return null;
  }

  /// 获取协议帧格式列表供自动解析器使用
  List<FrameFormatDef> getAllFrameFormats() {
    return all.expand((p) => p.frameFormats).toList();
  }

  /// 根据协议 ID 查找 GATT 服务定义
  GattServiceDef? findService(String protocolId, String uuid) {
    final protocol = _protocols[protocolId];
    if (protocol == null) return null;
    final upper = uuid.toUpperCase();
    return protocol.services.cast<GattServiceDef?>().firstWhere(
          (s) => s!.uuid.toUpperCase() == upper,
          orElse: () => null,
        );
  }

  /// 跨协议搜索 GATT 服务
  List<MapEntry<String, GattServiceDef>> searchService(String uuid) {
    final results = <MapEntry<String, GattServiceDef>>[];
    for (final p in _protocols.values) {
      for (final s in p.services) {
        if (s.uuid.toUpperCase() == uuid.toUpperCase()) {
          results.add(MapEntry(p.id, s));
        }
      }
    }
    return results;
  }

  bool _checkPrefix(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}
