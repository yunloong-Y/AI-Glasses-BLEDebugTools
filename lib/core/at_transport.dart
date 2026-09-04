import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'ble_uuid.dart';

/// ============================================================
/// AT 指令透传层
///
/// 解决的核心问题（2026-09-02）：
/// 原 `StandardBluetoothAdapter.sendAtCommand` 写入后直接 `return 'OK'`，
/// 从不读取设备响应。这导致：
///   - 寄存器读取永远拿到空数据
///   - 寄存器写入无论成功失败都显示 "OK"（异常被吞成字符串）
///   调试工具出现「假成功」比直接报错更危险。
///
/// 本层提供真正的请求-响应闭环：
///   1. 透传通道探测（已知厂商表 → 自动挑选 notify/write 特征对）
///   2. 行缓冲重组（BLE 通知可能被拆包/粘包）
///   3. 终止行判定（OK / ERROR / +CME ERROR ...）+ 静默超时兜底
///   4. 指令串行化（避免多条并发 AT 互相串扰）
///   5. 设备主动上报（URC）旁路到独立流，不污染响应
/// ============================================================

/// GATT 端点描述（探测用，与 flutter_blue_plus 类型解耦，便于测试）
class GattEndpoint {
  final String serviceUuid;
  final String charUuid;
  final Set<String> properties;

  const GattEndpoint({
    required this.serviceUuid,
    required this.charUuid,
    required this.properties,
  });

  bool get canNotify =>
      properties.contains('notify') || properties.contains('indicate');

  bool get canWrite =>
      properties.contains('write') || properties.contains('writeNoResp');

  /// 优先用带响应的写入，失败时上层可降级
  bool get prefersWriteWithResponse => properties.contains('write');
}

/// 已知厂商透传通道（全部写 16/128-bit，比较前统一归一化）
class AtTransportProfile {
  final String name;
  final String serviceUuid;
  final String notifyUuid;
  final String writeUuid;

  const AtTransportProfile(
      this.name, this.serviceUuid, this.notifyUuid, this.writeUuid);
}

/// 透传通道候选表（按匹配优先级）
const List<AtTransportProfile> kKnownAtProfiles = [
  // 恒玄 BES / HM-10 / JDY 系：ffe0 服务下 notify=ffe1、write=ffe1
  AtTransportProfile(
      'BES/HM-10 透传', 'ffe0', 'ffe1', 'ffe1'),
  // 汇承 JDY 变体：write 走 ffe2
  AtTransportProfile(
      'JDY 透传 (ffe2 写)', 'ffe0', 'ffe1', 'ffe2'),
  // Nordic UART Service
  AtTransportProfile(
      'Nordic NUS',
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e'),
  // Microchip RN4870/RN4020
  AtTransportProfile(
      'Microchip RN4xxx',
      '49535343-fe7d-4ae5-8fa9-9fafd205e455',
      '49535343-1e4d-4bd9-ba61-23c647249616',
      '49535343-8841-43f4-a8d4-ecbe34729bb3'),
  // 通用私有数据服务 ff00（本项目原 OTA 通道也复用此段）
  AtTransportProfile(
      '通用 FF00 数据通道', 'ff00', 'ff02', 'ff01'),
];

/// 透传通道来源
enum AtTransportSource { knownProfile, autoDetected }

/// 探测结果
class AtTransportSelection {
  final String serviceUuid;
  final String notifyUuid;
  final String writeUuid;
  final String label;
  final AtTransportSource source;

  const AtTransportSelection({
    required this.serviceUuid,
    required this.notifyUuid,
    required this.writeUuid,
    required this.label,
    required this.source,
  });

  @override
  String toString() => '$label (notify=${uuidShort(notifyUuid)}'
      ' write=${uuidShort(writeUuid)})';
}

/// 从 GATT 端点列表中挑选可用的 AT 透传通道
///
/// 策略：先按已知厂商表精确匹配；匹配不到则自动挑选——
/// 优先「同一服务内 notify + write 两个特征」，其次「单特征同时具备
/// notify + write」。调试工具面对未知固件时，自动挑选比直接失败有用。
AtTransportSelection? selectAtTransport(List<GattEndpoint> endpoints) {
  // 1. 已知厂商表精确匹配
  for (final profile in kKnownAtProfiles) {
    final svc = normalizeUuid(profile.serviceUuid);
    final notify = normalizeUuid(profile.notifyUuid);
    final write = normalizeUuid(profile.writeUuid);

    final svcEndpoints =
        endpoints.where((e) => normalizeUuid(e.serviceUuid) == svc);
    if (svcEndpoints.isEmpty) continue;

    final notifyOk =
        svcEndpoints.any((e) => normalizeUuid(e.charUuid) == notify && e.canNotify);
    final writeOk =
        svcEndpoints.any((e) => normalizeUuid(e.charUuid) == write && e.canWrite);
    if (notifyOk && writeOk) {
      return AtTransportSelection(
        serviceUuid: svc,
        notifyUuid: notify,
        writeUuid: write,
        label: profile.name,
        source: AtTransportSource.knownProfile,
      );
    }
  }

  // 2. 自动挑选：同一服务内配对
  final services = <String, List<GattEndpoint>>{};
  for (final e in endpoints) {
    services.putIfAbsent(normalizeUuid(e.serviceUuid), () => []).add(e);
  }

  // 跳过标准服务（设备信息/电池等不可能承载 AT 透传）
  const standardServices = {
    '00001800-0000-1000-8000-00805f9b34fb', // Generic Access
    '00001801-0000-1000-8000-00805f9b34fb', // Generic Attribute
    '0000180a-0000-1000-8000-00805f9b34fb', // Device Information
    '0000180f-0000-1000-8000-00805f9b34fb', // Battery
  };

  GattEndpoint? bestNotify;
  GattEndpoint? bestWrite;
  String? bestService;

  for (final entry in services.entries) {
    if (standardServices.contains(entry.key)) continue;
    final notifyChar = entry.value.where((e) => e.canNotify).toList();
    final writeChar = entry.value.where((e) => e.canWrite).toList();
    if (notifyChar.isEmpty || writeChar.isEmpty) continue;

    // 同服务内优先选不同的特征；若只有双属性单特征也接受
    final n = notifyChar.first;
    final w = writeChar.firstWhere(
      (e) => normalizeUuid(e.charUuid) != normalizeUuid(n.charUuid),
      orElse: () => writeChar.first,
    );
    bestNotify = n;
    bestWrite = w;
    bestService = entry.key;
    break;
  }

  if (bestNotify != null && bestWrite != null && bestService != null) {
    return AtTransportSelection(
      serviceUuid: bestService,
      notifyUuid: normalizeUuid(bestNotify.charUuid),
      writeUuid: normalizeUuid(bestWrite.charUuid),
      label: '自动探测 (服务 ${uuidShort(bestService)})',
      source: AtTransportSource.autoDetected,
    );
  }

  return null;
}

/// AT 传输异常
class AtTransportException implements Exception {
  final String message;
  const AtTransportException(this.message);

  @override
  String toString() => message;
}

/// AT 指令响应
class AtResponse {
  /// 是否收到成功终止行（OK 等）
  final bool ok;

  /// 数据行（已剥离 echo 行与终止行）
  final List<String> lines;

  /// 终止行原文（如 "OK" / "+CME ERROR: 12"），超时无响应时为 null
  final String? finalLine;

  /// 是否因等待超时而结束
  final bool timedOut;

  /// 原始回显（含所有收到的行）
  final String raw;

  final Duration elapsed;

  const AtResponse({
    required this.ok,
    required this.lines,
    this.finalLine,
    this.timedOut = false,
    required this.raw,
    required this.elapsed,
  });

  /// 单行场景下的便捷取值（第一条数据行）
  String? get firstLine => lines.isEmpty ? null : lines.first;

  @override
  String toString() {
    if (timedOut) return 'AT 超时无响应${lines.isEmpty ? '' : '（收到: ${lines.join(" | ")}）'}';
    return finalLine ?? (lines.isEmpty ? '(空响应)' : lines.join(' | '));
  }
}

/// 底层读写能力抽象（由蓝牙适配器实现，core 层不反向依赖 adapter 层）
abstract interface class AtIo {
  Future<void> atWrite(Uint8List data, {bool withoutResponse});

  Future<void> atSubscribe(Function(Uint8List) onData);

  Future<void> atUnsubscribe();

  /// 单包可写字节数（已扣除 ATT 头），用于超长指令告警
  int get atMtuPayload;
}

/// 一次等待中的请求
class _AtPending {
  final Completer<AtResponse> completer = Completer<AtResponse>();
  final String command;
  final List<String> lines = [];
  final StringBuffer rawBuffer = StringBuffer();
  final DateTime startedAt = DateTime.now();
  final Duration timeout;
  final Duration quietPeriod;
  Timer? quietTimer;
  Timer? timeoutTimer;

  _AtPending({
    required this.command,
    required this.timeout,
    required this.quietPeriod,
  });
}

/// AT 透传通道：探测 + 行缓冲 + 请求-响应串行化
class AtTransport {
  final AtIo io;
  final AtTransportSelection selection;
  final void Function(String message)? onLog;
  final void Function(String line)? onUnsolicited;

  /// 等待响应的总时长上限
  final Duration responseTimeout;

  /// 静默期：收到数据后若这段时间内没有新数据，认为响应已结束
  /// （部分固件对纯下发类指令只回一行、不回 OK）
  final Duration quietPeriod;

  /// 指令行终止符，绝大多数 AT 固件用 \r\n
  final String lineTerminator;

  bool _subscribed = false;
  bool _disposed = false;
  _AtPending? _pending;

  /// 指令串行化尾链：保证任意时刻只有一条 AT 指令在途
  Future<dynamic> _tail = Future<void>.value();

  final BytesBuilder _rxBuffer = BytesBuilder(copy: true);

  AtTransport({
    required this.io,
    required this.selection,
    this.responseTimeout = const Duration(seconds: 8),
    this.quietPeriod = const Duration(milliseconds: 400),
    this.lineTerminator = '\r\n',
    this.onLog,
    this.onUnsolicited,
  });

  /// 成功终止行
  static const Set<String> _finalOk = {
    'OK',
    'DONE',
    'SUCCESS',
    'SEND OK',
    'READY',
  };

  /// 失败终止行（含前缀匹配）
  static const Set<String> _finalErrPrefix = {
    'ERROR',
    '+CME ERROR',
    '+CMS ERROR',
    'FAIL',
    'SEND FAIL',
  };

  /// 订阅通知通道（惰性执行一次）
  Future<void> _ensureSubscribed() async {
    if (_subscribed || _disposed) return;
    await io.atSubscribe(_onNotifyData);
    _subscribed = true;
    _log('AT 透传通道就绪: $selection');
  }

  void _log(String message) => onLog?.call(message);

  /// notify 数据入口：字节流 → 行流
  void _onNotifyData(Uint8List data) {
    if (_disposed) return;
    _rxBuffer.add(data);
    final bytes = _rxBuffer.toBytes();
    _rxBuffer.clear();

    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b != 0x0A && b != 0x0D) continue;

      final line = _decodeLine(bytes, start, i);
      start = i + 1;
      // 跳过 \r\n 连续终止符产生的空行
      if (line.isEmpty) continue;
      _handleLine(line);
    }

    // 未消费的半行留到下一批
    if (start < bytes.length) {
      _rxBuffer.add(Uint8List.sublistView(bytes, start));
    }
  }

  String _decodeLine(Uint8List bytes, int start, int end) {
    if (end <= start) return '';
    return utf8
        .decode(bytes.sublist(start, end), allowMalformed: true)
        .trim();
  }

  void _handleLine(String line) {
    final pending = _pending;

    if (pending == null) {
      // 无在途请求 → 设备主动上报（URC）
      _log('← [URC] $line');
      onUnsolicited?.call(line);
      return;
    }

    pending.rawBuffer.writeln(line);

    // 静默计时器：每来一行就重置
    pending.quietTimer?.cancel();

    if (_isEcho(pending.command, line)) {
      _log('← [ECHO] $line');
      _armQuietTimer(pending);
      return;
    }

    final verdict = _judgeFinalLine(line);
    if (verdict != null) {
      final ok = verdict;
      _log('← $line');
      _finish(pending, ok: ok, finalLine: line, timedOut: false);
      return;
    }

    _log('← $line');
    pending.lines.add(line);
    _armQuietTimer(pending);
  }

  /// 静默超时兜底：设备回了数据但不回终止行
  void _armQuietTimer(_AtPending pending) {
    pending.quietTimer = Timer(quietPeriod, () {
      if (_pending != pending) return;
      _finish(pending,
          ok: pending.lines.isNotEmpty,
          finalLine: null,
          timedOut: pending.lines.isEmpty);
    });
  }

  /// 是否为指令回显
  bool _isEcho(String command, String line) {
    final cmd = command.trim();
    if (line == cmd) return true;
    // 部分固件 echo 时不带 AT 前缀的差异，或尾部多余空白
    return line.replaceAll(RegExp(r'\s+'), '') ==
        cmd.replaceAll(RegExp(r'\s+'), '');
  }

  /// 判定终止行：返回 true=成功 / false=失败 / null=非终止行
  bool? _judgeFinalLine(String line) {
    final upper = line.toUpperCase();
    if (_finalOk.contains(upper)) return true;
    for (final prefix in _finalErrPrefix) {
      if (upper.startsWith(prefix)) return false;
    }
    return null;
  }

  void _finish(_AtPending pending,
      {required bool ok, String? finalLine, required bool timedOut}) {
    if (_pending != pending) return;
    _pending = null;
    pending.quietTimer?.cancel();
    pending.timeoutTimer?.cancel();

    if (!pending.completer.isCompleted) {
      pending.completer.complete(AtResponse(
        ok: ok,
        lines: List.unmodifiable(pending.lines),
        finalLine: finalLine,
        timedOut: timedOut,
        raw: pending.rawBuffer.toString().trim(),
        elapsed: DateTime.now().difference(pending.startedAt),
      ));
    }
  }

  /// 串行化执行：保证任意时刻只有一条指令在途
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    // 队列尾总是「正常完成」，单条指令失败只传给各自的 completer，
    // 不会阻断后续排队指令。
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  /// 发送 AT 指令并等待响应
  ///
  /// [expectResponse] = false 时不做等待，仅下发（用于纯触发类指令）。
  /// 注意：等待失败会返回 ok=false 的 AtResponse，**不会抛异常**；
  /// 调用方需要据此决定是提示用户还是继续。
  Future<AtResponse> transact(
    String command, {
    bool expectResponse = true,
    Duration? timeout,
    Duration? quietPeriod,
  }) {
    return _enqueue(() => _transactInner(
          command,
          expectResponse: expectResponse,
          timeout: timeout,
          quietPeriod: quietPeriod,
        ));
  }

  Future<AtResponse> _transactInner(
    String command, {
    required bool expectResponse,
    Duration? timeout,
    Duration? quietPeriod,
  }) async {
    if (_disposed) {
      throw const AtTransportException('AT 通道已关闭');
    }

    await _ensureSubscribed();

    final payload = Uint8List.fromList(
        utf8.encode('$command$lineTerminator'));

    final mtuLimit = io.atMtuPayload;
    if (payload.length > mtuLimit) {
      _log('⚠ 指令 ${payload.length}B 超过单包上限 ${mtuLimit}B，'
          '可能被固件拆包丢弃: $command');
    }

    final effTimeout = timeout ?? responseTimeout;
    final effQuiet = quietPeriod ?? this.quietPeriod;

    _AtPending? pending;
    if (expectResponse) {
      pending = _AtPending(
        command: command,
        timeout: effTimeout,
        quietPeriod: effQuiet,
      );
      _pending = pending;
    }

    _log('→ $command');

    try {
      await io.atWrite(payload, withoutResponse: false);
    } catch (e) {
      if (pending != null) _finish(pending, ok: false, timedOut: false);
      throw AtTransportException('AT 写入失败: $e');
    }

    if (!expectResponse) {
      return AtResponse(
        ok: true,
        lines: const [],
        finalLine: null,
        raw: '',
        elapsed: Duration.zero,
      );
    }

    pending!.timeoutTimer = Timer(effTimeout, () {
      _finish(pending!, ok: false, finalLine: null, timedOut: true);
    });

    return pending.completer.future;
  }

  /// 只读发送（不等待响应）的便捷入口
  Future<void> send(String command) => transact(command, expectResponse: false);

  /// 释放资源
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _pending;
    if (pending != null) {
      pending.quietTimer?.cancel();
      pending.timeoutTimer?.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer
            .completeError(const AtTransportException('AT 通道已关闭'));
      }
      _pending = null;
    }
    if (_subscribed) {
      try {
        await io.atUnsubscribe();
      } catch (_) {}
      _subscribed = false;
    }
    _rxBuffer.clear();
  }
}
