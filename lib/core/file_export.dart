import 'dart:io';

/// ============================================================
/// 文件持久化模块
/// 日志、固件、测试报告本地存储
/// ============================================================

class FileExporter {
  /// 导出文本日志
  static Future<String> exportLogFile(String content, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/aiglasses_bledebugtools_log_${deviceMac}_$ts.log');
    await file.writeAsString(content);
    return file.path;
  }

  /// 导出 PCAP 抓包文件
  static Future<String> exportPcapFile(
      List<int> data, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/aiglasses_bledebugtools_capture_${deviceMac}_$ts.pcap');
    await file.writeAsBytes(data);
    return file.path;
  }

  /// 导出测试报告 CSV
  static Future<String> exportTestReport(String csv, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/aiglasses_bledebugtools_report_${deviceMac}_$ts.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  /// 获取导出目录
  static Future<Directory> _getExportDir() async {
    // TODO: 使用 path_provider 获取应用文档目录
    final dir = Directory('/tmp/aiglasses_bledebugtools_exports');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
