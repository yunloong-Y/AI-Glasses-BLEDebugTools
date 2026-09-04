import 'dart:io';
import 'dart:typed_data';

import '../adapter/base_bluetooth.dart';
import '../adapter/bluetooth_impl.dart';
import '../core/ble_uuid.dart';
import '../core/glass_ota.dart';
import 'base_plugin.dart';

/// ============================================================
/// 恒玄 BES 插件
/// 适配: BES2700 / BES2710 / BES2800 (TWS & AR 眼镜)
/// 核心能力: 左右耳同步、寄存器调试、功耗采样、ANC
/// ============================================================

class BesTwsPlugin extends BaseChipPlugin {
  @override
  VendorId get vendorId => VendorId.bes;

  @override
  String get name => 'BES TWS / AR';

  @override
  String get description => '恒玄 BES 全系列 TWS耳机/AR眼镜 调试插件';

  /// 恒玄 BLE 服务 UUID
  static const _besServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  @override
  bool canHandle(DeviceInfo device) {
    final name = device.name.toUpperCase();
    if (name.contains('BES') || name.contains('BES2700') ||
        name.contains('BES2710') || name.contains('BES2800')) {
      return true;
    }
    // 必须归一化后比较：广播里的 serviceUuids 可能是 16-bit 短格式
    final target = normalizeUuid(_besServiceUuid);
    for (final uuid in device.bleServices) {
      if (normalizeUuid(uuid) == target) return true;
    }
    return false;
  }

  @override
  BaseBluetoothAdapter createAdapter() => BesTwsAdapter();

  @override
  Map<int, String> get registerMap => {
        0x00: 'CHIP_ID',
        0x04: 'FW_VERSION',
        0x08: 'BT_ADDR',
        0x0C: 'BATTERY_LEVEL',
        0x10: 'AUDIO_GAIN_L',
        0x14: 'AUDIO_GAIN_R',
        0x18: 'ANC_MODE',
        0x1C: 'ANC_GAIN',
        0x20: 'POWER_CONSUMPTION',
        0x24: 'TOUCH_SENSITIVITY',
        0x28: 'CHARGE_STATUS',
        0x2C: 'TWS_PAIR_STATUS',
        0x30: 'LOW_LATENCY_MODE',
        0x34: 'GAME_MODE',
        0x38: 'EQ_PROFILE',
        0x3C: 'MIC降噪开关',
        0x40: 'INEAR_DETECT',
      };

  @override
  List<String> get atCommandTemplates => [
        'AT+VERSION?',
        'AT+BATTERY?',
        'AT+BATTERY?L',
        'AT+BATTERY?R',
        'AT+REG_RD=0x10',
        'AT+REG_WR=0x10,0x01',
        'AT+ANC=ON',
        'AT+ANC=OFF',
        'AT+ANC=TRANSPARENCY',
        'AT+TWS_PAIR',
        'AT+TWS_UNPAIR',
        'AT+AUDIO_GAIN=50',
        'AT+LOW_LATENCY=ON',
        'AT+GAME_MODE=ON',
        'AT+OTA_BEGIN',
        'AT+OTA_DATA=',
        'AT+OTA_END',
        'AT+POWER_SAMPLE=START',
        'AT+POWER_SAMPLE=STOP',
        'AT+RESET',
      ];

  @override
  int get otaChunkSize => 512;

  @override
  bool get otaSupportResume => true;
}

/// 恒玄专用适配器
///
/// OTA 复用 `GlassOtaTransactor` 的完整协议流程——该协议本身即移植自
/// BesAPP 的 bes-glass-sdk（`GlassOtaProtocol.java`），帧格式与 BES 一致，
/// 差异仅在 GATT 通道 UUID（BES 走 ffe0/ffe2，眼镜走 6666/7777）。
class BesTwsAdapter extends StandardBluetoothAdapter {
  /// BES 透传/日志通道
  static const String besServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String besLogChar = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// BES OTA 数据通道（读写复用同一特征）
  static const String besOtaChar = '0000ffe2-0000-1000-8000-00805f9b34fb';

  /// OTA 选边：0=立体声同步 1=左 2=右 3=双侧分别
  int otaSide = 0;

  GlassOtaTransactor? _otaTransactor;

  /// 上次传输的固件大小，用于校验续传是否仍针对同一份固件
  int _lastFirmwareSize = 0;

  @override
  String get otaServiceUuid => besServiceUuid;

  @override
  String get otaWriteCharUuid => besOtaChar;

  @override
  String get otaNotifyCharUuid => besOtaChar;

  @override
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress, int? chunkSize}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return OtaResult(success: false, message: '固件文件不存在: $filePath');
    }

    final data = Uint8List.fromList(await file.readAsBytes());
    if (data.isEmpty) {
      return OtaResult(success: false, message: '固件文件为空');
    }

    // 断点保护：换了固件（大小不同）就丢弃旧断点，
    // 否则会把新固件的数据写到旧偏移上，设备必然变砖。
    final previousBreakpoint = _otaTransactor?.breakpoint ?? 0;
    if (previousBreakpoint > 0 &&
        _lastFirmwareSize > 0 &&
        _lastFirmwareSize != data.length) {
      pushSystemLog('固件大小变化（$_lastFirmwareSize → ${data.length}B），'
          '丢弃旧断点 $previousBreakpoint');
      _otaTransactor = null;
    }
    _lastFirmwareSize = data.length;

    // 分包长度：插件声明 512B，但必须受 MTU 约束。
    // 数据包 = 4B 头 + 载荷，整包还要塞进 ATT MTU（扣 3B 头）。
    final mtu = atMtuPayload + 3;
    final mtuPayloadLimit = mtu - 3 - 4;
    var segment = chunkSize ?? 512;
    if (segment > mtuPayloadLimit) {
      pushSystemLog('分片 ${segment}B 超过 MTU 上限，收敛为 ${mtuPayloadLimit}B'
          '（ATT MTU=$mtu）');
      segment = mtuPayloadLimit;
    }

    // 协议层要求非空版本号；此处用文件名兜底（该字段仅用于协议层记录）
    final version = filePath.split(Platform.pathSeparator).last;

    GlassOtaProtocol protocol;
    try {
      protocol = GlassOtaProtocol(version, data)..segmentLength = segment;
    } catch (e) {
      return OtaResult(success: false, message: '固件加载失败: $e');
    }

    // 每次重建传输器：进度回调是新的闭包，断点通过 initialBreakpoint 带入
    _otaTransactor = GlassOtaTransactor(
      adapter: this,
      otaServiceUuid: besServiceUuid,
      otaCharUuid: besOtaChar,
      mtu: mtu,
      initialBreakpoint: _otaTransactor?.breakpoint ?? 0,
      onLog: (m) => pushSystemLog('[BES OTA] $m'),
      onProgress: (percent) => onProgress?.call(percent / 100),
    );

    final result = await _otaTransactor!.run(protocol, otaSide);
    otaTransferredBytes = result.sentBytes;
    return result;
  }

  @override
  Future<void> pauseOta() async {
    final transactor = _otaTransactor;
    if (transactor == null) {
      pushSystemLog('当前没有进行中的 OTA，无需暂停');
      return;
    }
    transactor.pause();
    pushSystemLog('已请求暂停，将在当前分片的 ACK 返回后停下');
  }

  @override
  Future<void> resumeOta() async {
    final transactor = _otaTransactor;
    if (transactor == null || !transactor.hasBreakpoint) {
      pushSystemLog('没有可续传的断点，需要重新开始传输');
      return;
    }
    pushSystemLog('断点 ${transactor.breakpoint}B，请再次点击「开始升级」续传');
  }
}
