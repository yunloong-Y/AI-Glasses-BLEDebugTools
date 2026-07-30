import 'package:flutter/material.dart';
import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 实时日志控制台
/// 分标签: HCI / 厂商日志 / 音频 / OTA / AT 指令
/// 支持过滤、搜索、导出
/// ============================================================

class LogConsole extends StatefulWidget {
  const LogConsole({super.key});

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final List<LogItem> _logs = [];
  final _scrollController = ScrollController();
  String _filterKeyword = '';
  LogType? _filterType;
  bool _autoScroll = true;

  final _logTypeLabels = {
    LogType.hci: ('HCI', Colors.blue),
    LogType.vendorLog: ('VENDOR', Colors.purple),
    LogType.audio: ('AUDIO', Colors.orange),
    LogType.ota: ('OTA', Colors.teal),
    LogType.atCmd: ('AT', Colors.red),
    LogType.system: ('SYS', Colors.grey),
  };

  List<LogItem> get _filteredLogs {
    if (_filterKeyword.isEmpty && _filterType == null) return _logs;
    return _logs.where((log) {
      if (_filterType != null && log.type != _filterType) return false;
      if (_filterKeyword.isNotEmpty) {
        return log.decodeText
                .toLowerCase()
                .contains(_filterKeyword.toLowerCase()) ||
            log.rawHex.toLowerCase().contains(_filterKeyword.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _logs.clear()),
            tooltip: '清空日志',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: 导出日志
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('导出功能待实现')),
              );
            },
            tooltip: '导出',
          ),
        ],
      ),
      body: Column(
        children: [
          // 过滤栏
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索关键字...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        setState(() => _filterKeyword = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<LogType?>(
                  value: _filterType,
                  hint: const Text('全部'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全部')),
                    ..._logTypeLabels.entries.map((e) =>
                        DropdownMenuItem(
                            value: e.key, child: Text(e.value.$1))),
                  ],
                  onChanged: (v) => setState(() => _filterType = v),
                ),
                IconButton(
                  icon: Icon(_autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_top),
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                  tooltip: '自动滚动',
                ),
              ],
            ),
          ),
          // 日志列表
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text('暂无日志',
                        style: TextStyle(color: Colors.grey.shade400)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (ctx, i) {
                      final log = logs[i];
                      final label = _logTypeLabels[log.type]!;
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: label.$2.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label.$1,
                              style: TextStyle(
                                  color: label.$2, fontSize: 10)),
                        ),
                        title: Text(
                          log.decodeText.isNotEmpty
                              ? log.decodeText
                              : log.rawHex,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                        subtitle: Text(
                          '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                          '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                          '${log.timestamp.second.toString().padLeft(2, '0')}.'
                          '${log.timestamp.millisecond.toString().padLeft(3, '0')} '
                          '${log.dir == LogDirection.send ? "TX" : "RX"} '
                          '${log.deviceMac}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
