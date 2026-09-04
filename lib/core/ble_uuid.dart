/// ============================================================
/// BLE UUID 归一化工具
///
/// 致命坑（2026-09-02 定位）：flutter_blue_plus 的 `Guid.str` 返回的是
/// **最短表示** —— 16-bit UUID `0000ffe1-0000-1000-8000-00805f9b34fb`
/// 会被压成 `"ffe1"`（见 flutter_blue_plus_platform_interface 的 guid.dart）。
/// 而项目常量通常写成完整 128-bit 形式，两者直接字符串比较必然失配，
/// 后果是 `_findChar` 永远返回 null、厂商插件 `canHandle()` 永远匹配不上。
///
/// 因此全项目任何 UUID 比较前都必须先过这个函数。
/// ============================================================

/// 蓝牙基准 UUID 模板：xxxxxxxx-0000-1000-8000-00805f9b34fb
const String _bluetoothBaseSuffix = '-0000-1000-8000-00805f9b34fb';

/// 把任意写法归一化为 128-bit 小写形式
///
/// 支持输入：
/// - 16-bit：`"ffe1"` / `"0xFFE1"`
/// - 32-bit：`"ffffffff"`
/// - 完整 128-bit：`"0000ffe1-0000-1000-8000-00805f9b34fb"`
/// - 任意自定义 128-bit：`"6e400001-b5a3-f393-e0a9-e50e24dcca9e"`（原样返回）
String normalizeUuid(String uuid) {
  var s = uuid.trim().toLowerCase();
  if (s.startsWith('0x')) s = s.substring(2);
  s = s.replaceAll(' ', '');
  if (s.length == 4 || s.length == 8) {
    // 16-bit / 32-bit → 展开到蓝牙基准 UUID
    s = '${s.padLeft(8, '0')}$_bluetoothBaseSuffix';
  }
  return s;
}

/// 归一化后比较两个 UUID 是否等价
bool uuidEquals(String a, String b) =>
    normalizeUuid(a) == normalizeUuid(b);

/// 取 UUID 的短码显示形式（16-bit UUID 显示 4 位，其余显示前 8 位）
String uuidShort(String uuid) {
  final n = normalizeUuid(uuid);
  if (n.endsWith(_bluetoothBaseSuffix)) {
    return n.substring(4, 8);
  }
  return n.substring(0, 8);
}
