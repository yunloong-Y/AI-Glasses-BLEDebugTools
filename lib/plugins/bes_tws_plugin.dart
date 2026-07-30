import '../adapter/base_bluetooth.dart';
import '../adapter/bluetooth_impl.dart';
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
  static const _besLogChar = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const _besOtaChar = '0000ffe2-0000-1000-8000-00805f9b34fb';

  @override
  bool canHandle(DeviceInfo device) {
    final name = device.name.toUpperCase();
    if (name.contains('BES') || name.contains('BES2700') ||
        name.contains('BES2710') || name.contains('BES2800')) {
      return true;
    }
    for (final uuid in device.bleServices) {
      if (uuid.toLowerCase() == _besServiceUuid) return true;
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
class BesTwsAdapter extends StandardBluetoothAdapter {
  static const _besLogChar = 'ffe1';
  static const _besOtaChar = 'ffe2';

  @override
  Future<OtaResult> startOta(String filePath,
      {Function(double progress)? onProgress}) async {
    // BES OTA 流程:
    // 1. 进入 BES OTA 模式
    // 2. 512B 分片传输
    // 3. 左右耳同步升级
    // 4. CRC 校验 + 重启
    // TODO: 实现完整 OTA 逻辑
    throw UnimplementedError('BES OTA pending implementation');
  }

  @override
  Future<Uint8List> readRegister(int address, int length) async {
    // AT+REG_RD=0xADDR
    final cmd = 'AT+REG_RD=0x${address.toRadixString(16).toUpperCase()}';
    final result = await sendAtCommand(cmd);
    // TODO: 解析返回的十六进制数据
    return Uint8List(0);
  }

  @override
  Future<void> writeRegister(int address, Uint8List data) async {
    final hexData = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(',');
    final cmd = 'AT+REG_WR=0x${address.toRadixString(16).toUpperCase()},$hexData';
    await sendAtCommand(cmd);
  }
}
