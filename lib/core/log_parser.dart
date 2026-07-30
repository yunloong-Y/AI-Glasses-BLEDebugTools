import 'dart:async';
import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 日志解析与缓存模块
/// 异步队列处理，分离 UI 渲染与蓝牙报文接收
/// 支持过滤、导出、离线回放
/// ============================================================

class LogParser {
  static final LogParser _instance = LogParser._internal();
  factory LogParser() => _instance;
  LogParser._internal();

  /// 日志缓存上限
  static const int maxLogCount = 100000;

  final List<LogItem> _logs = [];
  final StreamController<LogItem> _logStream =
      StreamController<LogItem>.broadcast();

  /// 当前过滤关键字
  String? filterKeyword;

  /// 当前过滤日志类型
  Set<LogType>? filterTypes;

  /// 日志流（UI 监听）
  Stream<LogItem> get logStream => _logStream.stream;

  /// 所有日志（只读）
  List<LogItem> get allLogs => List.unmodifiable(_logs);

  /// 当前过滤后的日志
  List<LogItem> get filteredLogs {
    if (filterKeyword == null && filterTypes == null) {
      return List.from(_logs);
    }
    return _logs.where((log) {
      if (filterTypes != null && !filterTypes!.contains(log.type)) {
        return false;
      }
      if (filterKeyword != null && filterKeyword!.isNotEmpty) {
        return log.decodeText.toLowerCase().contains(
                  filterKeyword!.toLowerCase(),
                ) ||
            log.rawHex.toLowerCase().contains(filterKeyword!.toLowerCase());
      }
      return true;
    }).toList();
  }

  /// 添加日志
  void addLog(LogItem item) {
    _logs.add(item);

    // 滚动清理
    if (_logs.length > maxLogCount) {
      _logs.removeRange(0, _logs.length - maxLogCount);
    }

    _logStream.add(item);
  }

  /// 批量添加
  void addLogs(Iterable<LogItem> items) {
    for (final item in items) {
      addLog(item);
    }
  }

  /// 清空日志
  void clear() {
    _logs.clear();
  }

  /// 设置关键字过滤
  void setKeywordFilter(String? keyword) {
    filterKeyword = keyword;
  }

  /// 设置类型过滤
  void setTypeFilter(Set<LogType>? types) {
    filterTypes = types;
  }

  /// 导出为文本日志
  String exportAsText() {
    final buffer = StringBuffer();
    for (final log in _logs) {
      buffer.writeln(
        '${_formatTime(log.timestamp)} '
        '[${log.type.name.toUpperCase()}] '
        '[${log.dir == LogDirection.send ? "TX" : "RX"}] '
        '${log.deviceMac} '
        '${log.decodeText.isNotEmpty ? log.decodeText : log.rawHex}',
      );
    }
    return buffer.toString();
  }

  /// 导出为 PCAP 格式 (供 Wireshark 打开)
  /// TODO: 实现完整 PCAP 封装
  List<int> exportAsPcap() {
    // PCAP 文件头 + 报文记录
    throw UnimplementedError('PCAP export pending implementation');
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  void dispose() {
    _logStream.close();
  }
}

/// HCI 日志解析工具
class HciLogDecoder {
  /// 解析 HCI 二进制数据为可读文本
  static String decode(Uint8List data) {
    if (data.length < 4) return _bytesToHex(data);

    // HCI 包类型
    final pktType = data[0];
    switch (pktType) {
      case 0x01: // HCI Command Packet
        return _decodeHciCommand(data);
      case 0x02: // ACL Data Packet
        return _decodeAclData(data);
      case 0x04: // HCI Event Packet
        return _decodeHciEvent(data);
      default:
        return '[Unknown HCI Packet] ${_bytesToHex(data)}';
    }
  }

  static String _decodeHciCommand(Uint8List data) {
    if (data.length < 4) return _bytesToHex(data);
    final opcode = data[1] | (data[2] << 8);
    return '[HCI CMD] Opcode=0x${opcode.toRadixString(16).toUpperCase()} '
        'Data=${_bytesToHex(data.sublist(4))}';
  }

  static String _decodeAclData(Uint8List data) {
    if (data.length < 5) return _bytesToHex(data);
    final handle = data[1] | ((data[2] & 0x0F) << 8);
    final length = data[3] | (data[4] << 8);
    return '[ACL] Handle=0x${handle.toRadixString(16).toUpperCase()} '
        'Len=$length Data=${_bytesToHex(data.sublist(5))}';
  }

  static String _decodeHciEvent(Uint8List data) {
    if (data.length < 3) return _bytesToHex(data);
    final eventCode = data[1];
    return '[HCI EVT] Event=0x${eventCode.toRadixString(16).toUpperCase()} '
        'Data=${_bytesToHex(data.sublist(3))}';
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
