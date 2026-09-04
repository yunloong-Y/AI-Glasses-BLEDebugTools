import 'dart:async';
import 'dart:typed_data';

import '../adapter/base_bluetooth.dart';
import 'glass_protocol.dart';

/// ============================================================
/// 眼镜 OTA 协议层（从 BesAPP bes-glass-sdk GlassOtaProtocol.java 移植）
///
/// 纯协议层：命令生成 + 响应解析 + 分包 + CRC32。
/// 传输走独立 OTA GATT 通道（Service 6666... / Char 7777...），
/// 与控制协议（01000100...）分离，响应无 0xA5 外层帧。
///
/// 命令一览：
///   0x7A [00 00]                      握手（获取协议版本）
///   0x7B [side 00]                    选边（0=stereo 1=left 2=right 3=both）
///   0x7E [lenLE(2)]                   协商分包长度
///   0x80 [00 00]                      开始 OTA
///   0x81 [offset(3 LE) ...data]       数据包（等待 0x8B ACK）
///   0x82 [crc32(4 LE)]                整包 CRC 校验
///
/// 响应一览：
///   0x7A [protocolVersion]            握手响应
///   0x7C [status]                     选边响应
///   0x7E [lenLE(2)]                   分包长度响应（协商后实际值）
///   0x81 [status]                     开始 OTA 响应
///   0x8B                              数据包 ACK
///   0x83 / 0x85 [status]              CRC 校验响应（分段/整体）
/// ============================================================

/// OTA 响应解析结果
class OtaResponse {
  final bool success;
  final String message;
  final int cmdCode;

  const OtaResponse._(this.success, this.message, this.cmdCode);

  factory OtaResponse.success(String message, int cmdCode) =>
      OtaResponse._(true, message, cmdCode);

  factory OtaResponse.error(String message, int cmdCode) =>
      OtaResponse._(false, message, cmdCode);

  factory OtaResponse.unknown(String message, int cmdCode) =>
      OtaResponse._(false, message, cmdCode);

  @override
  String toString() =>
      'OtaResponse(0x${cmdCode.toRadixString(16)}, ${success ? "ok" : "err"}: $message)';
}

/// OTA 纯协议层（无 BLE 依赖，镜像 Java GlassOtaProtocol）
class GlassOtaProtocol {
  final String firmwareVersion;
  final Uint8List firmwareData;

  int currentOffset = 0;
  int segmentLength = 512;

  GlassOtaProtocol(this.firmwareVersion, this.firmwareData) {
    if (firmwareVersion.isEmpty) {
      throw ArgumentError('firmwareVersion 不能为空');
    }
    if (firmwareData.isEmpty) {
      throw ArgumentError('firmwareData 不能为空');
    }
  }

  int get firmwareSize => firmwareData.length;
  int get progress =>
      firmwareSize == 0 ? 0 : (currentOffset * 100) ~/ firmwareSize;
  bool get isTransferComplete => currentOffset >= firmwareData.length;

  // ---------- 命令生成 ----------

  Uint8List buildGetProtocolVersionCmd() =>
      Uint8List.fromList([0x7A, 0x00, 0x00]);

  Uint8List buildSelectSideCmd(int side) =>
      Uint8List.fromList([0x7B, side & 0xFF, 0x00]);

  Uint8List buildSetSegmentLengthCmd(int length) => Uint8List.fromList([
        0x7E,
        length & 0xFF,
        (length >> 8) & 0xFF,
      ]);

  Uint8List buildStartOtaCmd() => Uint8List.fromList([0x80, 0x00, 0x00]);

  Uint8List buildCrcCheckCmd() {
    final crc = _crc32(firmwareData);
    return Uint8List.fromList([
      0x82,
      crc & 0xFF,
      (crc >> 8) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 24) & 0xFF,
    ]);
  }

  /// 下一个数据包：[0x81, offset(3 LE), ...data]，传输完成返回 null
  Uint8List? getNextDataPacket() {
    if (currentOffset >= firmwareData.length) return null;
    final remaining = firmwareData.length - currentOffset;
    final chunkSize = segmentLength < remaining ? segmentLength : remaining;
    final packet = Uint8List(4 + chunkSize);
    packet[0] = 0x81;
    packet[1] = currentOffset & 0xFF;
    packet[2] = (currentOffset >> 8) & 0xFF;
    packet[3] = (currentOffset >> 16) & 0xFF;
    packet.setAll(4, firmwareData.sublist(currentOffset, currentOffset + chunkSize));
    currentOffset += chunkSize;
    return packet;
  }

  /// 断点续传：重置偏移
  void resetToBreakpoint(int offset) {
    if (offset < 0 || offset > firmwareData.length) {
      throw ArgumentError('断点偏移越界: $offset');
    }
    currentOffset = offset;
  }

  // ---------- 响应解析 ----------

  OtaResponse parseResponse(Uint8List data) {
    if (data.isEmpty) {
      return OtaResponse.error('响应数据为空', 0);
    }
    switch (data[0]) {
      case 0x7A:
        if (data.length < 2) {
          return OtaResponse.error('握手响应长度无效', 0x7A);
        }
        return OtaResponse.success(
            '协议版本: ${data[1]}', 0x7A);
      case 0x7C:
        if (data.length < 2) {
          return OtaResponse.error('选边响应长度无效', 0x7C);
        }
        return data[1] == 0x00
            ? OtaResponse.success('选边成功', 0x7C)
            : OtaResponse.error(
                '选边失败: 0x${data[1].toRadixString(16)}', 0x7C);
      case 0x7E:
        if (data.length < 3) {
          return OtaResponse.error('分包长度响应无效', 0x7E);
        }
        final negotiated = data[1] | (data[2] << 8);
        segmentLength = negotiated;
        return OtaResponse.success('分包长度: $negotiated', 0x7E);
      case 0x81:
        if (data.length < 2) {
          return OtaResponse.error('开始 OTA 响应长度无效', 0x81);
        }
        return data[1] == 0x00
            ? OtaResponse.success('OTA 已开始', 0x81)
            : OtaResponse.error(
                'OTA 启动失败: 0x${data[1].toRadixString(16)}', 0x81);
      case 0x8B:
        return OtaResponse.success('数据包 ACK', 0x8B);
      case 0x83:
      case 0x85:
        if (data.length < 2) {
          return OtaResponse.error('CRC 响应长度无效', data[0]);
        }
        return data[1] == 0x00
            ? OtaResponse.success('CRC 校验通过', data[0])
            : OtaResponse.error(
                'CRC 校验失败: 0x${data[1].toRadixString(16)}', data[0]);
      default:
        return OtaResponse.unknown(
            '未知响应: 0x${data[0].toRadixString(16)}', data[0]);
    }
  }

  // ---------- CRC32 ----------

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  /// 标准 CRC-32（IEEE 802.3，与 java.util.zip.CRC32 一致）
  static int _crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

/// OTA 传输器：在 OTA GATT 通道上执行完整升级流程
///
/// 通道 UUID 可覆盖：眼镜走默认的 6666/7777 段，BES TWS 走 ffe0/ffe2，
/// 由厂商 adapter 传入。协议帧格式完全一致。
class GlassOtaTransactor {
  final BaseBluetoothAdapter adapter;

  /// OTA 服务 UUID（默认眼镜段，厂商可覆盖）
  final String otaServiceUuid;

  /// OTA 数据特征 UUID（读写复用同一特征）
  final String otaCharUuid;

  final Duration responseTimeout;
  final void Function(String message)? onLog;
  final void Function(int percent)? onProgress;
  final Duration interPacketDelay;

  bool _subscribed = false;
  bool _aborted = false;
  final List<Completer<Uint8List>> _responseWaiters = [];

  /// 断点偏移（中止时记录，续传时从这里开始）
  int _breakpoint;

  GlassOtaTransactor({
    required this.adapter,
    this.otaServiceUuid = GlassUuid.otaService,
    this.otaCharUuid = GlassUuid.otaChar,
    this.responseTimeout = const Duration(seconds: 10),
    this.interPacketDelay = const Duration(milliseconds: 12),
    this.mtu = 23,
    this.initialBreakpoint = 0,
    this.onLog,
    this.onProgress,
  }) : _breakpoint = initialBreakpoint;

  /// 构造时注入的断点（重建传输器后继续上次的进度）
  final int initialBreakpoint;

  /// 协商后的 ATT MTU，用于收敛分包长度（默认 23 为蓝牙规范最小值）
  final int mtu;

  /// 已记录的断点字节数（0 表示无可续传进度）
  int get breakpoint => _breakpoint;

  /// 是否存在可续传的进度
  bool get hasBreakpoint => _breakpoint > 0;

  /// 单包载荷上限
  ///
  /// 数据包格式 `[0x81, offset(3B), ...data]`，头部占 4 字节，
  /// 整包还要塞进 ATT MTU（再扣 3 字节 ATT 头），故载荷上限 = MTU - 7。
  /// 蓝牙规范 MTU 上限 517 → 载荷最多 510B。
  int maxSegmentForMtu(int mtu) {
    final usable = mtu - 3; // ATT 头
    final payload = usable - 4; // OTA 包头
    return payload < 20 ? 20 : payload;
  }

  void _log(String message) => onLog?.call(message);

  Future<void> _ensureSubscribed() async {
    if (_subscribed) return;
    await adapter.subscribeNotify(otaServiceUuid, otaCharUuid, _onOtaNotify);
    _subscribed = true;
    _log('OTA 通道已就绪 (${otaCharUuid.substring(0, 8)}...)');
  }

  void _onOtaNotify(Uint8List data) {
    if (_responseWaiters.isEmpty) return;
    final waiter = _responseWaiters.removeAt(0);
    if (!waiter.isCompleted) {
      waiter.complete(data);
    }
  }

  Future<Uint8List> _writeAndWait(Uint8List cmd,
      {Duration? timeout}) async {
    final waiter = Completer<Uint8List>();
    _responseWaiters.add(waiter);
    try {
      await adapter.writeChar(
          GlassUuid.otaService, GlassUuid.otaChar, cmd);
    } catch (e) {
      _responseWaiters.remove(waiter);
      rethrow;
    }
    try {
      return await waiter.future.timeout(timeout ?? responseTimeout);
    } on TimeoutException {
      _responseWaiters.remove(waiter);
      rethrow;
    }
  }

  /// 发送命令并解析响应
  ///
  /// 必须用**同一个 protocol 实例**解析：0x7E 分包长度协商会把结果写回
  /// `segmentLength`，若用临时实例解析，协商结果会被丢弃，后续仍按旧值分包。
  Future<OtaResponse> _roundTrip(
      GlassOtaProtocol protocol, Uint8List cmd) async {
    final raw = await _writeAndWait(cmd);
    return protocol.parseResponse(raw);
  }

  /// 完整 OTA 流程
  ///
  /// 若存在断点（上次调用 [pause] 中止过），会自动从断点续传。
  Future<OtaResult> run(GlassOtaProtocol protocol, int side) async {
    final startTime = DateTime.now();

    // 0. 分包长度受 MTU 硬限制，必须先收敛再协商，
    //    否则 UI 选的 4096B 会被 BLE 栈静默截断。
    final maxSeg = maxSegmentForMtu(mtu);
    if (protocol.segmentLength > maxSeg) {
      _log('分包长度 ${protocol.segmentLength}B 超过 MTU 上限，'
          '收敛为 ${maxSeg}B（ATT MTU=$mtu）');
      protocol.segmentLength = maxSeg;
    }

    // 0.5 断点续传：把偏移重置到上次中止处
    if (_breakpoint > 0 && _breakpoint < protocol.firmwareSize) {
      protocol.resetToBreakpoint(_breakpoint);
      _log('从断点 $_breakpoint/${protocol.firmwareSize}B 续传');
    } else if (_breakpoint > 0) {
      _log('断点 $_breakpoint 已覆盖整个固件，从头开始');
      _breakpoint = 0;
      protocol.resetToBreakpoint(0);
    }

    try {
      await _ensureSubscribed();

      // 1. 握手
      _log('握手 (0x7A)');
      var resp = await _roundTrip(
          protocol, protocol.buildGetProtocolVersionCmd());
      if (!resp.success) {
        throw StateError('握手失败: ${resp.message}');
      }

      // 2. 选边
      _log('选边 side=$side (0x7B)');
      resp = await _roundTrip(protocol, protocol.buildSelectSideCmd(side));
      if (!resp.success) {
        throw StateError('选边失败: ${resp.message}');
      }

      // 3. 协商分包长度
      _log('协商分包长度 ${protocol.segmentLength}B (0x7E)');
      resp = await _roundTrip(protocol,
          protocol.buildSetSegmentLengthCmd(protocol.segmentLength));
      if (!resp.success) {
        throw StateError('设置分包长度失败: ${resp.message}');
      }
      _log('实际分包长度: ${protocol.segmentLength}B');

      // 4. 开始 OTA
      _log('开始 OTA (0x80)');
      resp = await _roundTrip(protocol, protocol.buildStartOtaCmd());
      if (!resp.success) {
        throw StateError('启动 OTA 失败: ${resp.message}');
      }

      // 5. 传输数据（每包等 0x8B ACK）
      var packetIndex = 0;
      while (!protocol.isTransferComplete && !_aborted) {
        final packet = protocol.getNextDataPacket()!;
        final ack = await _writeAndWait(packet,
            timeout: responseTimeout * 3);
        final ackResp = protocol.parseResponse(ack);
        if (!ackResp.success) {
          throw StateError(
              '第 $packetIndex 包传输失败: ${ackResp.message} '
              '(offset=${protocol.currentOffset})');
        }
        packetIndex++;
        onProgress?.call(protocol.progress);
        if (interPacketDelay > Duration.zero) {
          await Future.delayed(interPacketDelay);
        }
      }

      if (_aborted) {
        return OtaResult(
          success: false,
          message: 'OTA 已中止（断点 offset=${protocol.currentOffset}）',
          totalBytes: protocol.firmwareSize,
          sentBytes: protocol.currentOffset,
          elapsed: DateTime.now().difference(startTime),
        );
      }

      // 6. CRC 校验
      _log('CRC32 校验 (0x82)');
      resp = await _roundTrip(protocol, protocol.buildCrcCheckCmd());
      if (!resp.success) {
        throw StateError('CRC 校验失败: ${resp.message}');
      }

      // 成功后清除断点
      _breakpoint = 0;

      final elapsed = DateTime.now().difference(startTime);
      _log('OTA 完成: ${protocol.firmwareSize} 字节 / $elapsed');
      return OtaResult(
        success: true,
        message: 'OTA 升级成功（${protocol.firmwareSize} 字节）',
        totalBytes: protocol.firmwareSize,
        sentBytes: protocol.firmwareSize,
        elapsed: elapsed,
      );
    } catch (e) {
      return OtaResult(
        success: false,
        message: 'OTA 失败: $e',
        totalBytes: protocol.firmwareSize,
        sentBytes: protocol.currentOffset,
        elapsed: DateTime.now().difference(startTime),
      );
    } finally {
      await _cleanup();
    }
  }

  /// 请求暂停：在当前包边界停下并记录断点，可稍后 [resume] 续传
  void pause() {
    _aborted = true;
  }

  /// 中止并丢弃断点（不再续传）
  void abort() {
    _aborted = true;
    _breakpoint = 0;
  }

  /// 从断点续传
  ///
  /// 需要重新构造 protocol 实例（携带同一份固件数据）：
  /// 传输器只保存断点偏移量，不持有固件内容，避免长驻内存。
  Future<OtaResult> resume(GlassOtaProtocol protocol, int side) async {
    if (!hasBreakpoint) {
      throw StateError('没有可续传的断点，请重新开始');
    }
    if (protocol.firmwareSize <= _breakpoint) {
      throw StateError('固件大小（${protocol.firmwareSize}B）与断点'
          '（${_breakpoint}B）不匹配，疑似更换了固件文件，已拒绝续传');
    }
    _aborted = false;
    return run(protocol, side);
  }

  Future<void> _cleanup() async {
    if (_subscribed) {
      try {
        await adapter.unsubscribeNotify(otaServiceUuid, otaCharUuid);
      } catch (_) {}
      _subscribed = false;
    }
    for (final waiter in _responseWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('OTA 通道已关闭'));
      }
    }
    _responseWaiters.clear();
  }
}

/// OTA 传输器 + 协议实例的便捷组合入口
///
/// [firmwareVersion] 用于协议层记录（部分固件的握手阶段会回传校验），
/// 不可为空——构造 GlassOtaProtocol 时会校验。
Future<OtaResult> runGlassOta({
  required BaseBluetoothAdapter adapter,
  required String firmwareVersion,
  required Uint8List firmwareData,
  int side = 0,
  int segmentLength = 512,
  int mtu = 23,
  String? otaServiceUuid,
  String? otaCharUuid,
  Duration responseTimeout = const Duration(seconds: 10),
  Duration interPacketDelay = const Duration(milliseconds: 12),
  void Function(String message)? onLog,
  void Function(int percent)? onProgress,
}) async {
  final protocol = GlassOtaProtocol(firmwareVersion, firmwareData)
    ..segmentLength = segmentLength;
  final transactor = GlassOtaTransactor(
    adapter: adapter,
    otaServiceUuid: otaServiceUuid ?? GlassUuid.otaService,
    otaCharUuid: otaCharUuid ?? GlassUuid.otaChar,
    responseTimeout: responseTimeout,
    interPacketDelay: interPacketDelay,
    mtu: mtu,
    onLog: onLog,
    onProgress: onProgress,
  );
  return transactor.run(protocol, side);
}
