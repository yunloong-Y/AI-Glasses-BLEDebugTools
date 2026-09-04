/// ============================================================
/// Qualcomm GAIA 协议逆向解码器
/// ------------------------------------------------------------
/// 来源（逆向工程分析，仅用于研究/调试）：
///   https://github.com/pubglite55/SpaceTravel-Protocol
/// 目标设备：水月雨 MOONDROP Space Travel 太空漫游 TWS 耳机
///           及同类 Qualcomm GAIA V3 设备。
///
/// GAIA 是 Qualcomm 的通用音频接口架构协议，原跑在 RFCOMM /
/// BLE GATT 上。本项目只做「字节级逆向解析」——把抓到的原始
/// BLE 特征值 / 日志里的 hex 还原成 厂商(Vendor) / 功能(Feature) /
/// 命令(Command) / 包类型 / Payload(ASCII 或 hex)，便于调试。
///
/// ⚠️ 注意：以下帧格式来自社区逆向，并非 Qualcomm 官方文档，
///    不同 APP（官方 MOONDROP Link 用 `FF 04` 封装，开源测试
///    App 用裸 4 字节）线上格式不完全一致，解码器按「可识别的
///    几种形态」做启发式匹配，识别不上就返回 null（不误报）。
/// ============================================================

import 'dart:typed_data';

/// 方向：手机→设备 为指令(TX)，设备→手机 为响应/通知(RX)
enum GaiaDirection { tx, rx }

/// 一条解析出来的 GAIA 数据包
class GaiaPacket {
  final GaiaDirection direction;
  final int vendorId;
  final int featureId;
  final int commandId;
  /// 响应/通知标志：RX 包的命令字节 bit7(0x80) 置位时为真
  final bool responseFlag;
  final Uint8List payload;
  final Uint8List raw;
  /// 识别到的线上封装形式，仅用于调试展示
  final String wrapper;

  GaiaPacket._({
    required this.direction,
    required this.vendorId,
    required this.featureId,
    required this.commandId,
    required this.responseFlag,
    required this.payload,
    required this.raw,
    required this.wrapper,
  });

  String get featureName =>
      _featureNames[featureId] ?? 'Feature=0x${featureId.toRadixString(16)}';

  String get commandName {
    final group = _featureCommands[featureId];
    if (group != null) return group[commandId] ?? 'Cmd=$commandId';
    return 'Cmd=$commandId';
  }

  /// Payload 展示：全可打印 ASCII 则按字符串，否则按 hex
  String get payloadText {
    if (payload.isEmpty) return '(空)';
    final allPrintable = payload.every((b) => b >= 0x20 && b <= 0x7E);
    if (allPrintable) return '"${String.fromCharCodes(payload)}"';
    return '[${payload.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}]';
  }

  /// 渲染成日志里展示的可读文本
  String format() {
    final b = StringBuffer();
    b.write('[GAIA ${direction == GaiaDirection.tx ? 'TX▶' : 'RX◀'}]');
    b.write(' Vendor=0x${vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()}');
    b.write(' Feature=0x${featureId.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '(${featureName})');
    b.write(' Cmd=0x${commandId.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '(${commandName})');
    if (responseFlag) b.write(' [响应/通知]');
    b.write(' Payload=${payloadText}');
    return b.toString().trim();
  }
}

/// GAIA 逆向解码器（启发式匹配三种已知线上形态）
class GaiaDecoder {
  /// 已知厂商 Vendor ID（MOONDROP Space Travel = 0x001D = 29）
  static const int vendorId = 0x001D;

  /// 尝试从一段原始字节解码 GAIA 包；识别不上返回 null。
  static GaiaPacket? tryDecode(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // 形态 B：官方 MOONDROP Link APP 的 `FF 04` 封装指令（TX）
    //   结构: FF 04 [type] [seq] [00] [vendor=0x1D] [feature] [cmd] [payload...]
    if (bytes.length >= 8 && bytes[0] == 0xFF && bytes[1] == 0x04) {
      final vendor = bytes[5];
      final feature = bytes[6];
      final command = bytes[7];
      final payload = bytes.sublist(8);
      return GaiaPacket._(
        direction: GaiaDirection.tx,
        vendorId: vendor,
        featureId: feature,
        commandId: command,
        responseFlag: false,
        payload: payload,
        raw: bytes,
        wrapper: 'FF04',
      );
    }

    // 形态 A：开源测试 App 的裸 4 字节指令（TX）
    //   结构: [vendorLo=0x1D] [vendorHi=0x00] [cmdValLo] [cmdValHi] [payload...]
    //   cmdVal = (feature<<9) | (command & 0x7F)
    if (bytes[0] == 0x1D && bytes[1] == 0x00) {
      final cmdVal = bytes[2] | (bytes[3] << 8);
      final feature = (cmdVal >> 9) & 0x7F;
      final command = cmdVal & 0x7F;
      final payload = bytes.length > 4 ? bytes.sublist(4) : Uint8List(0);
      return GaiaPacket._(
        direction: GaiaDirection.tx,
        vendorId: vendorId,
        featureId: feature,
        commandId: command,
        responseFlag: false,
        payload: payload,
        raw: bytes,
        wrapper: 'RAW',
      );
    }

    // 形态 C：设备响应 / 通知（RX）
    //   结构: [0x00] [vendor=0x1D] [feature] [cmdByte] [payload...]
    //   cmdByte 的 bit7(0x80) 置位表示这是响应/通知（而非指令回显）
    if (bytes[0] == 0x00 && bytes[1] == 0x1D) {
      final vendor = bytes[1];
      final feature = bytes[2];
      final cmdByte = bytes[3];
      final responseFlag = (cmdByte & 0x80) != 0;
      final command = cmdByte & 0x7F;
      final payload = bytes.length > 4 ? bytes.sublist(4) : Uint8List(0);
      return GaiaPacket._(
        direction: GaiaDirection.rx,
        vendorId: vendor,
        featureId: feature,
        commandId: command,
        responseFlag: responseFlag,
        payload: payload,
        raw: bytes,
        wrapper: 'RX',
      );
    }

    return null;
  }
}

/// Feature ID → 名称（来自逆向文档，0x00–0x0B 为已确认项）
const Map<int, String> _featureNames = {
  0x00: '设备管理',
  0x01: '基础功能',
  0x02: '电池/电源',
  0x03: 'ANC V2',
  0x05: '固件版本',
  0x06: '音频处理',
  0x07: 'EQ/音乐处理',
  0x0A: '设备信息',
  0x0B: '状态查询',
};

/// Feature → { Command → 名称 }（逆向文档中已确认的命令）
const Map<int, Map<int, String>> _featureCommands = {
  0x00: {
    0: 'GET/ACK',
    1: '电池查询',
    2: '连接状态',
  },
  0x01: {
    0: 'GET',
    1: '状态',
    5: '版本信息',
    7: '基础控制',
  },
  0x03: {
    1: 'ANC 状态/控制',
  },
  0x05: {
    5: '查询固件版本',
  },
  0x06: {
    0: 'GET',
  },
  0x07: {
    3: '设置 EQ 预设',
  },
  0x0A: {
    0: 'GET_RESPONSE',
    1: '设备信息',
    3: '设备信息',
  },
  0x0B: {
    2: '状态查询',
    3: '状态响应',
  },
};
