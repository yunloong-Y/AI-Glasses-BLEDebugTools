import 'dart:async';

import 'glass_protocol.dart';
import 'sn_binding_service.dart';

/// ============================================================
/// SN 绑定编排器（从 BesAPP MoonixSnBindingCoordinator.java 移植）
///
/// 固定执行顺序：
///   读取设备身份 → 后台绑定 → 0x000E 写入 → 0x0009 回读验证
///
/// 失败恢复语义：后台已成功、BLE 写入/验证失败时，
/// 仅重试设备侧步骤（retryDeviceWrite），不再重复后台绑定。
/// ============================================================

/// SN 绑定五阶段
enum SnBindingStage {
  validateSn,
  readDeviceIdentity,
  backendBind,
  deviceWrite,
  deviceVerify,
}

/// 绑定过程异常（携带失败阶段 + 后台是否已绑定成功）
class SnBindingException implements Exception {
  final SnBindingStage stage;
  final String message;
  final bool backendBound;

  const SnBindingException(this.stage, this.message,
      {this.backendBound = false});

  @override
  String toString() => 'SnBindingException(${stage.name}): $message';
}

/// 绑定成功结果
class SnBindingResult {
  final String serialNumber;
  final String? previousFirmwareSn;

  const SnBindingResult(this.serialNumber, this.previousFirmwareSn);
}

/// 设备身份（上报后台用）
class SnDeviceIdentity {
  final String mac;
  final String firmwareSn;
  final String firmwareVersion;

  const SnDeviceIdentity(this.mac, this.firmwareSn, this.firmwareVersion);
}

/// SN 绑定编排器
class SnBindingCoordinator {
  static final RegExp _snPattern = RegExp(r'^[0-9A-Z]{12}$');

  final GlassInfoApi device;
  final SnBindingService backend;
  final String Function() macProvider;
  final void Function(String message)? onLog;

  SnBindingCoordinator({
    required this.device,
    required this.backend,
    required this.macProvider,
    this.onLog,
  });

  /// SN 规范化：去空格、转大写，必须 12 位 Base36（0-9 A-Z）
  static String normalizeSerialNumber(String value) {
    final normalized = value.trim().toUpperCase();
    if (!_snPattern.hasMatch(normalized)) {
      throw const FormatException('SN 必须是 12 位数字或大写字母');
    }
    return normalized;
  }

  /// 不抛异常版本：非法输入返回 null（UI 便捷用）
  static String? normalizeSerialNumberSafe(String value) {
    try {
      return normalizeSerialNumber(value);
    } on FormatException {
      return null;
    }
  }

  /// 完整绑定流程
  Future<SnBindingResult> bind(String rawSerialNumber) async {
    final String serialNumber;
    try {
      serialNumber = normalizeSerialNumber(rawSerialNumber);
    } on FormatException catch (e) {
      throw SnBindingException(
          SnBindingStage.validateSn, e.message, backendBound: false);
    }

    // 1. 读取设备身份
    final identity = await _readIdentity();
    final previousSn = identity.firmwareSn;

    // 2. 后台绑定
    await _guard(SnBindingStage.backendBind, false, () async {
      onLog?.call('后台绑定 $serialNumber (mac=${identity.mac})');
      await backend.bind(serialNumber, identity.mac,
          identity.firmwareSn, identity.firmwareVersion);
    });

    // 3+4. 设备写入 + 回读验证（此时后台已绑定，backendBound=true）
    return _writeAndVerify(serialNumber, previousSn, backendBound: true);
  }

  /// 仅重试设备侧步骤（后台已绑定成功时）
  Future<SnBindingResult> retryDeviceWrite(String rawSerialNumber) async {
    final String serialNumber;
    try {
      serialNumber = normalizeSerialNumber(rawSerialNumber);
    } on FormatException catch (e) {
      throw SnBindingException(
          SnBindingStage.validateSn, e.message, backendBound: true);
    }
    return _writeAndVerify(serialNumber, null, backendBound: true);
  }

  Future<SnDeviceIdentity> _readIdentity() {
    return _guard(SnBindingStage.readDeviceIdentity, false, () async {
      final mac = macProvider().trim();
      if (mac.isEmpty) {
        throw StateError('设备 MAC 为空，请先连接设备');
      }
      onLog?.call('读取固件 SN (0x0009)');
      final firmwareSn = (await device.getSerialNumber()).trim();
      if (firmwareSn.isEmpty) {
        throw StateError('固件 SN 为空');
      }
      onLog?.call('读取固件版本 (0x0003)');
      final version = (await device.getFirmwareVersion()).trim();
      if (version.isEmpty) {
        throw StateError('固件版本为空');
      }
      onLog?.call('设备身份: mac=$mac sn=$firmwareSn ver=$version');
      return SnDeviceIdentity(mac, firmwareSn, version);
    });
  }

  Future<SnBindingResult> _writeAndVerify(String serialNumber,
      String? previousFirmwareSn, {required bool backendBound}) async {
    // 3. 0x000E 写入
    await _guard(SnBindingStage.deviceWrite, backendBound, () async {
      onLog?.call('写入 SN → $serialNumber (0x000E)');
      await device.writeSerialNumber(serialNumber);
    });

    // 4. 0x0009 回读验证
    final verified = await _guard(
        SnBindingStage.deviceVerify, backendBound, () async {
      onLog?.call('回读 SN 验证 (0x0009)');
      return (await device.getSerialNumber()).trim();
    });

    if (verified != serialNumber) {
      throw SnBindingException(
          SnBindingStage.deviceVerify,
          '回读 SN 不一致：期望 $serialNumber，'
          '实际 ${verified.isEmpty ? '—' : verified}',
          backendBound: backendBound);
    }
    return SnBindingResult(serialNumber, previousFirmwareSn);
  }

  /// 包装异步操作，统一转换为 SnBindingException（保留阶段与后台状态）
  Future<T> _guard<T>(SnBindingStage stage, bool backendBound,
      Future<T> Function() action) async {
    try {
      return await action();
    } on SnBindingException {
      rethrow;
    } catch (error) {
      throw SnBindingException(
          stage, _errorMessage(error), backendBound: backendBound);
    }
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return '命令超时：${error.message ?? ''}';
    }
    final message = error.toString();
    return message.isEmpty ? '未知错误' : message;
  }
}
