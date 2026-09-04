import '../adapter/base_bluetooth.dart';
import '../adapter/bluetooth_impl.dart';
import 'base_plugin.dart';

/// ============================================================
/// 高通 QCC / AR1 插件
/// 适配: QCC3040 / QCC512X / AR1
/// 核心能力: AR1 大文件 OTA、视频流透传、双链路音频
/// ============================================================

class QccArPlugin extends BaseChipPlugin {
  @override
  VendorId get vendorId => VendorId.qcc;

  @override
  String get name => 'Qualcomm QCC / AR1';

  @override
  String get description => '高通 QCC 系列 & AR1 AI 眼镜调试插件';

  /// 高通厂商 UUID 前缀
  static const _qccUuidPrefix = '0000fe'; // Qualcomm Service
  static const _ar1ServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';

  @override
  bool canHandle(DeviceInfo device) {
    // 通过设备名称或服务 UUID 匹配
    if (device.name.toUpperCase().contains('QCC') ||
        device.name.toUpperCase().contains('AR1') ||
        device.name.toUpperCase().contains('AR-GLASS')) {
      return true;
    }
    for (final uuid in device.bleServices) {
      if (uuid.toLowerCase().startsWith(_qccUuidPrefix) ||
          uuid.toLowerCase() == _ar1ServiceUuid) {
        return true;
      }
    }
    return false;
  }

  @override
  BaseBluetoothAdapter createAdapter() => QccArAdapter();

  @override
  Map<int, String> get registerMap => {
        0x0000: 'CHIP_ID',
        0x0004: 'FW_VERSION',
        0x0010: 'AUDIO_MODE',
        0x0014: 'ANC_ENABLE',
        0x0018: 'MIC_GAIN_L',
        0x001C: 'MIC_GAIN_R',
        0x0020: 'BT_TX_POWER',
        0x0024: 'AR_DISPLAY_CTRL',
        0x0028: 'AR_IMU_CTRL',
        0x002C: 'AR_CAMERA_CTRL',
      };

  @override
  List<String> get atCommandTemplates => [
        'AT+VERSION?',
        'AT+BATTERY?',
        'AT+AR_DISPLAY=ON',
        'AT+AR_DISPLAY=OFF',
        'AT+AR_IMU=START',
        'AT+AR_IMU=STOP',
        'AT+AR_CAMERA=SNAP',
        'AT+AUDIO_MODE=HFP',
        'AT+AUDIO_MODE=A2DP',
        'AT+ANC=ON',
        'AT+ANC=OFF',
        'AT+OTA_BEGIN',
        'AT+OTA_DATA=',
        'AT+OTA_END',
        'AT+RESET',
      ];

  @override
  int get otaChunkSize => 4096; // AR 固件较大

  @override
  bool get otaSupportDualChannel => true; // AR1 支持双通道并行 OTA
}

/// 高通专用适配器
class QccArAdapter extends StandardBluetoothAdapter {
  // 高通私有 BLE 服务/特征值 UUID
  static const _otaServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const _otaWriteChar = '0000ff01-0000-1000-8000-00805f9b34fb';
  static const _otaNotifyChar = '0000ff02-0000-1000-8000-00805f9b34fb';

  /// 直接复用通用传输骨架，仅覆盖通道 UUID。
  ///
  /// 未实现的差异化能力（相对 BES 的完整协议流程）：
  ///   - 握手/分包协商/CRC 校验：QCC 走的是 GAIA 或厂商私有升级协议，
  ///     与本项目已移植的眼镜 OTA 帧格式不同，需拿到高通 GAIA 文档后补。
  ///   - 双通道并行：BLE 单链路下无法真正并行，需要厂商确认其通道模型。
  ///   - 4096B 分片：超出 BLE 单包上限，基类会按 MTU 自动收敛。
  @override
  String get otaServiceUuid => _otaServiceUuid;

  @override
  String get otaWriteCharUuid => _otaWriteChar;

  @override
  String get otaNotifyCharUuid => _otaNotifyChar;
}
