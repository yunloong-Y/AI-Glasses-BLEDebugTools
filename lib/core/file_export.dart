import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// ============================================================
/// 文件持久化模块
/// 日志、固件、测试报告本地存储
/// ============================================================

class FileExporter {
  /// 导出文本日志
  static Future<String> exportLogFile(String content, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/ble_log_${deviceMac}_$ts.log');
    await file.writeAsString(content);
    return file.path;
  }

  /// 导出 PCAP 抓包文件
  static Future<String> exportPcapFile(
      List<int> data, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/ble_capture_${deviceMac}_$ts.pcap');
    await file.writeAsBytes(data);
    return file.path;
  }

  /// 导出测试报告 CSV
  static Future<String> exportTestReport(String csv, String deviceMac) async {
    final dir = await _getExportDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/ble_report_${deviceMac}_$ts.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  /// 获取导出目录（使用应用文档目录）
  static Future<Directory> _getExportDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/ble_debug_exports');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
