import 'dart:async';
import 'dart:typed_data';

import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 眼镜 BLE 协议层（从 BesAPP bes-glass-sdk 移植，协议 v2.0.17）
///
/// 外层帧: A5 | Length(2 LE) | Payload | CRC16-IBM(2 LE)
///   CRC 覆盖 A5 + Length + Payload（不含 CRC 自身）
/// 内层 Payload: CMD(2 LE) | Type(1) | Seq(1) | DataLen(2 LE) | Data
///   Type=1 请求 / Type=2 响应 / Type=3 设备主动 Notify
/// ============================================================

/// 眼镜控制协议 GATT UUID（协议 v2.0.17，2000 段，勿改成 1000 段）
class GlassUuid {
  static const String service =
      '01000100-0000-2000-8000-009078563412';
  /// Notify（上行，设备 → App）
  static const String notifyRx =
      '02000200-0000-2000-8000-009178563412';
  /// Write（下行，App → 设备）
  static const String writeTx =
      '03000300-0000-2000-8000-009278563412';

  /// OTA 服务
  static const String otaService =
      '66666666-6666-6666-6666-666666666666';
  static const String otaChar =
      '77777777-7777-7777-7777-777777777777';
}

/// CRC-16/IBM（多项式 0xA001 反转，初值 0x0000）
class GlassCrc16Ibm {
  static int compute(Uint8List data, [int start = 0, int? end]) {
    int crc = 0x0000;
    final stop = end ?? data.length;
    for (int i = start; i < stop; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }
}

/// 解码后的内层 Payload
class GlassInnerPayload {
  final int commandId;
  final int type;
  final int sequence;
  final Uint8List data;

  const GlassInnerPayload({
    required this.commandId,
    required this.type,
    required this.sequence,
    required this.data,
  });

  String get dataAsUtf8 => String.fromCharCodes(data);
}

/// 内层 Payload 编解码：CMD(2 LE) | Type(1) | Seq(1) | DataLen(2 LE) | Data
class GlassPayloadCodec {
  static const int headerSize = 6;

  static Uint8List encode(GlassInnerPayload p) {
    final buf = BytesBuilder();
    final header = Uint8List(headerSize);
    _writeU16Le(header, 0, p.commandId);
    header[2] = p.type;
    header[3] = p.sequence;
    _writeU16Le(header, 4, p.data.length);
    buf.add(header);
    buf.add(p.data);
    return buf.toBytes();
  }

  static GlassInnerPayload? tryDecode(Uint8List bytes) {
    if (bytes.length < headerSize) return null;
    final commandId = _readU16Le(bytes, 0);
    final type = bytes[2];
    final sequence = bytes[3];
    final dataLen = _readU16Le(bytes, 4);
    if (bytes.length < headerSize + dataLen) return null;
    final data = Uint8List.sublistView(bytes, headerSize, headerSize + dataLen);
    return GlassInnerPayload(
      commandId: commandId,
      type: type,
      sequence: sequence,
      data: data,
    );
  }

  static int _readU16Le(Uint8List d, int o) => d[o] | (d[o + 1] << 8);
  static void _writeU16Le(Uint8List d, int o, int v) {
    d[o] = v & 0xFF;
    d[o + 1] = (v >> 8) & 0xFF;
  }
}

/// 外层 0xA5 帧编解码（含跨包重组缓冲）
class GlassBleFramer {
  static const int framePrefix = 0xA5;
  static const int outerHeaderSize = 3;
  static const int crcSize = 2;

  /// 编码完整帧
  static Uint8List encode(GlassInnerPayload inner) {
    final payload = GlassPayloadCodec.encode(inner);
    final crcInput = Uint8List(outerHeaderSize + payload.length);
    crcInput[0] = framePrefix;
    crcInput[1] = payload.length & 0xFF;
    crcInput[2] = (payload.length >> 8) & 0xFF;
    crcInput.setAll(outerHeaderSize, payload);
    final crc = GlassCrc16Ibm.compute(crcInput);
    final frame = Uint8List(crcInput.length + crcSize);
    frame.setAll(0, crcInput);
    frame[frame.length - 2] = crc & 0xFF;
    frame[frame.length - 1] = (crc >> 8) & 0xFF;
    return frame;
  }

  /// 校验帧 CRC（frame 含尾部 2 字节 CRC）
  static bool verifyCrc(Uint8List frame) {
    if (frame.length < outerHeaderSize + crcSize) return false;
    final expected =
        GlassCrc16Ibm.compute(frame, 0, frame.length - crcSize);
    final actual = frame[frame.length - 2] | (frame[frame.length - 1] << 8);
    return expected == actual;
  }
}

/// 跨 BLE 包的帧重组缓冲：喂入 notify 分片，吐出完整内层 payload
class GlassFrameAssembler {
  final BytesBuilder _buffer = BytesBuilder(copy: true);

  /// 输入新收到的字节，返回本批次解出的所有完整 payload（可能为空）
  List<GlassInnerPayload> feed(Uint8List incoming) {
    _buffer.add(incoming);
    final bytes = _buffer.toBytes();
    final out = <GlassInnerPayload>[];
    int offset = 0;
    int consumed = 0;
    while (offset < bytes.length) {
      if (bytes[offset] != GlassBleFramer.framePrefix) {
        offset++;
        continue;
      }
      if (offset + GlassBleFramer.outerHeaderSize > bytes.length) break;
      final payloadLen = bytes[offset + 1] | (bytes[offset + 2] << 8);
      final frameLen = GlassBleFramer.outerHeaderSize +
          payloadLen +
          GlassBleFramer.crcSize;
      if (offset + frameLen > bytes.length) break;
      final frame =
          Uint8List.sublistView(bytes, offset, offset + frameLen);
      if (!GlassBleFramer.verifyCrc(frame)) {
        offset++;
        continue;
      }
      final payloadBytes = Uint8List.sublistView(bytes,
          offset + GlassBleFramer.outerHeaderSize,
          offset + GlassBleFramer.outerHeaderSize + payloadLen);
      final inner = GlassPayloadCodec.tryDecode(payloadBytes);
      if (inner != null) out.add(inner);
      offset += frameLen;
      consumed = offset;
    }
    // 保留未消费的尾巴（不完整帧），丢弃已消费部分
    if (consumed > 0) {
      _buffer.clear();
      if (consumed < bytes.length) {
        _buffer.add(Uint8List.sublistView(bytes, consumed));
      }
    } else if (offset > 0) {
      // 没有完整帧但跳过了垃圾字节，同样收缩缓冲
      _buffer.clear();
      if (offset < bytes.length) {
        _buffer.add(Uint8List.sublistView(bytes, offset));
      }
    }
    return out;
  }

  void clear() => _buffer.clear();
}

/// 命令客户端：发送 Type=1 请求并等待匹配 seq 的 Type=2 响应
class GlassCommandClient {
  static const int typeRequest = 1;
  static const int typeResponse = 2;
  static const int typeNotify = 3;

  final BaseBluetoothAdapter adapter;
  final Duration timeout;
  final void Function(String message)? onLog;

  int _sequence = 0;
  bool _subscribed = false;
  final GlassFrameAssembler _assembler = GlassFrameAssembler();
  final Map<int, Completer<GlassInnerPayload>> _pending = {};
  final Map<int, void Function(GlassInnerPayload)> _notifyHandlers = {};
  StreamSubscription<LogItem>? _logTap;

  GlassCommandClient({
    required this.adapter,
    this.timeout = const Duration(seconds: 8),
    this.onLog,
  });

  int _nextSeq() => (++_sequence) & 0xFF;

  /// 订阅 Notify 通道并开始解析（连接后调用一次）
  Future<void> start() async {
    if (_subscribed) return;
    await adapter.subscribeNotify(
        GlassUuid.service, GlassUuid.notifyRx, _onNotifyData);
    _subscribed = true;
    _log('命令通道已就绪 (Notify=${GlassUuid.notifyRx})');
  }

  void _onNotifyData(Uint8List data) {
    for (final payload in _assembler.feed(data)) {
      if (payload.type == typeResponse) {
        final completer = _pending.remove(payload.sequence);
        if (completer != null && !completer.isCompleted) {
          completer.complete(payload);
        } else {
          _log('收到孤儿响应 cmd=0x${payload.commandId.toRadixString(16)}');
        }
      } else if (payload.type == typeNotify) {
        final handler = _notifyHandlers[payload.commandId];
        if (handler != null) {
          handler(payload);
        }
      }
    }
  }

  /// 发送 Type=1 请求并等待 Type=2 响应
  Future<GlassInnerPayload> request(int commandId,
      [Uint8List? data]) async {
    final seq = _nextSeq();
    final payload = GlassInnerPayload(
      commandId: commandId,
      type: typeRequest,
      sequence: seq,
      data: data ?? Uint8List(0),
    );
    final frame = GlassBleFramer.encode(payload);

    final completer = Completer<GlassInnerPayload>();
    _pending[seq] = completer;

    _log('→ 0x${commandId.toRadixString(16).toUpperCase().padLeft(4, '0')}'
        ' seq=$seq len=${payload.data.length}');

    try {
      await adapter.writeChar(
          GlassUuid.service, GlassUuid.writeTx, frame);
    } catch (e) {
      _pending.remove(seq);
      rethrow;
    }

    try {
      final resp = await completer.future.timeout(timeout);
      _log('← 0x${resp.commandId.toRadixString(16).toUpperCase().padLeft(4, '0')}'
          ' seq=${resp.sequence} len=${resp.data.length}');
      return resp;
    } on TimeoutException {
      _pending.remove(seq);
      throw TimeoutException(
          '命令 0x${commandId.toRadixString(16)} 等待响应超时', timeout);
    }
  }

  /// 注册设备主动上报（Type=3）处理器
  void setNotifyHandler(int commandId, void Function(GlassInnerPayload)? handler) {
    if (handler == null) {
      _notifyHandlers.remove(commandId);
    } else {
      _notifyHandlers[commandId] = handler;
    }
  }

  /// 停止命令通道（断开连接时调用）
  Future<void> stop() async {
    _logTap?.cancel();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('命令通道已关闭'), StackTrace.current);
      }
    }
    _pending.clear();
    _notifyHandlers.clear();
    _assembler.clear();
    if (_subscribed) {
      try {
        await adapter.unsubscribeNotify(
            GlassUuid.service, GlassUuid.notifyRx);
      } catch (_) {}
      _subscribed = false;
    }
  }

  void _log(String message) {
    onLog?.call(message);
  }
}

/// 设备信息命令（对应 SDK GlassInfoApi，0x0001–0x0009 / 0x000E / 0x0101）
class GlassInfoApi {
  static const int cmdProductInfo = 0x0001;
  static const int cmdModelName = 0x0002;
  static const int cmdVersion = 0x0003;
  static const int cmdHardware = 0x0004;
  static const int cmdDeviceName = 0x0006;
  static const int cmdConnectedSide = 0x0008;
  static const int cmdSerialNumber = 0x0009;
  static const int cmdBattery = 0x0101;
  static const int cmdSetSerialNumber = 0x000E;

  final GlassCommandClient client;

  GlassInfoApi(this.client);

  Future<String> getModelName() async =>
      (await client.request(cmdModelName)).dataAsUtf8;

  Future<String> getHardwareInfo() async =>
      (await client.request(cmdHardware)).dataAsUtf8;

  Future<String> getDeviceName() async =>
      (await client.request(cmdDeviceName)).dataAsUtf8;

  Future<String> getSerialNumber() async =>
      (await client.request(cmdSerialNumber)).dataAsUtf8;

  /// 读取固件版本（3 字节 major.minor.patch）
  Future<String> getFirmwareVersion() async {
    final resp = await client.request(cmdVersion);
    if (resp.data.length < 3) {
      throw StateError('版本响应过短: ${resp.data.length} 字节');
    }
    return '${resp.data[0]}.${resp.data[1]}.${resp.data[2]}';
  }

  /// 写入 SN（0x000E，UTF-8）
  Future<void> writeSerialNumber(String serialNumber) async {
    await client.request(cmdSetSerialNumber,
        Uint8List.fromList(serialNumber.codeUnits));
  }

  /// 读取电量（0x0101：[level, charging]）
  Future<(int level, bool charging)> getBattery() async {
    final resp = await client.request(cmdBattery);
    if (resp.data.isEmpty) {
      throw StateError('电量响应为空');
    }
    return (resp.data[0], resp.data.length > 1 && resp.data[1] != 0);
  }

  /// 查询当前连接侧：1=左腿 2=右腿
  Future<int> getConnectedSide() async {
    final resp = await client.request(cmdConnectedSide);
    return resp.data.isNotEmpty ? resp.data[0] : 0;
  }
}
