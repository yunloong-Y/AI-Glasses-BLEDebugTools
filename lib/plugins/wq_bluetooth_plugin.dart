import '../adapter/base_bluetooth.dart';
import '../adapter/bluetooth_impl.dart';
import 'base_plugin.dart';

/// ============================================================
/// 物奇微 WQ 插件
/// 适配: WQ7033 / WQ9000 (耳机 / 穿戴方案)
/// 核心能力: 产线烧录校准、低功耗调试
/// ============================================================

class WqBluetoothPlugin extends BaseChipPlugin {
  @override
  VendorId get vendorId => VendorId.wq;

  @override
  String get name => 'WQ Bluetooth';

  @override
  String get description => '物奇微 WQ 系列 耳机/穿戴 调试插件';

  static const _wqServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  @override
  bool canHandle(DeviceInfo device) {
    final name = device.name.toUpperCase();
    if (name.contains('WQ') || name.contains('WQ7033') ||
        name.contains('WQ9000')) {
      return true;
    }
    for (final uuid in device.bleServices) {
      if (uuid.toLowerCase() == _wqServiceUuid) return true;
    }
    return false;
  }

  @override
  BaseBluetoothAdapter createAdapter() => WqAdapter();

  @override
  Map<int, String> get registerMap => {
        0x00: 'CHIP_ID',
        0x04: 'FW_VERSION',
        0x08: 'BATTERY_VOLTAGE',
        0x0C: 'CHARGE_CURRENT',
        0x10: 'TOUCH_THRESHOLD',
        0x14: 'MIC_BIAS',
        0x18: 'SLEEP_TIMER',
        0x1C: 'WAKEUP_SOURCE',
        0x20: 'PRODUCTION_FLAG',
        0x24: 'CALIBRATION_DATA',
        0x28: 'BT_TX_POWER',
        0x2C: 'LOW_POWER_MODE',
      };

  @override
  List<String> get atCommandTemplates => [
        'AT+VERSION?',
        'AT+BATTERY?',
        'AT+SLEEP',
        'AT+WAKEUP',
        'AT+CALIBRATION=START',
        'AT+CALIBRATION=STOP',
        'AT+CALIBRATION=READ',
        'AT+TOUCH_TEST',
        'AT+MIC_TEST=START',
        'AT+MIC_TEST=STOP',
        'AT+CHARGE_TEST',
        'AT+PRODUCTION=ENTER',
        'AT+PRODUCTION=EXIT',
        'AT+OTA_BEGIN',
        'AT+OTA_DATA=',
        'AT+OTA_END',
        'AT+RESET',
      ];

  @override
  int get otaChunkSize => 512;
}

/// 物奇微专用适配器
class WqAdapter extends StandardBluetoothAdapter {
  /// 物奇微 OTA 通道（与 BES 同属 ffe0 段的私有数据服务，
  /// 但 OTA 数据特征走 ffe2，日志/透传走 ffe1）
  static const String wqServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String wqOtaChar = '0000ffe2-0000-1000-8000-00805f9b34fb';
  static const String wqNotifyChar = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// 复用通用传输骨架。
  ///
  /// 未实现的差异化能力：产线模式进入、烧录后校验与版本回读——
  /// 需拿到物奇微私有升级协议文档后补，目前按裸分片传输执行，
  /// 无 ACK 与 CRC，仅建议在已确认通道正确的情况下使用。
  @override
  String get otaServiceUuid => wqServiceUuid;

  @override
  String get otaWriteCharUuid => wqOtaChar;

  @override
  String get otaNotifyCharUuid => wqNotifyChar;
}
