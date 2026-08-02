import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../adapter/base_bluetooth.dart';
import '../core/file_export.dart';
import '../core/log_parser.dart';
import '../main.dart';

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
  final _scrollController = ScrollController();
  String _filterKeyword = '';
  LogType? _filterType;
  bool _autoScroll = true;
  StreamSubscription? _logSub;
  final List<LogItem> _logs = [];

  final _logTypeLabels = {
    LogType.hci: ('HCI', Colors.blue),
    LogType.vendorLog: ('VENDOR', Colors.purple),
    LogType.audio: ('AUDIO', Colors.orange),
    LogType.ota: ('OTA', Colors.teal),
    LogType.atCmd: ('AT', Colors.red),
    LogType.system: ('SYS', Colors.grey),
  };

  @override
  void initState() {
    super.initState();
    // 监听 LogParser 日志流
    final logParser = context.read<LogParser>();
    _logSub = logParser.logStream.listen((item) {
      if (!mounted) return;
      setState(() {
        _logs.add(item);
        // 限制 UI 缓存大小（LogParser 自身有 10 万缓存）
        if (_logs.length > 5000) {
          _logs.removeRange(0, _logs.length - 5000);
        }
      });
      if (_autoScroll) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

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

  Future<void> _exportLogs() async {
    final logParser = context.read<LogParser>();
    final bleState = context.read<BleState>();
    final deviceMac = bleState.selectedDevice?.mac ?? 'unknown';

    if (logParser.allLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有日志可导出')),
      );
      return;
    }

    final text = logParser.exportAsText();
    try {
      final path = await FileExporter.exportLogFile(text, deviceMac);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出 $path'),
            action: SnackBarAction(
              label: '分享',
              onPressed: () {
                Share.shareXFiles([XFile(path)]);
              },
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final logs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: Text('实时日志${bleState.connected ? " (${_logs.length})" : ""}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              context.read<LogParser>().clear();
              setState(() => _logs.clear());
            },
            tooltip: '清空日志',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportLogs,
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
                    onChanged: (v) => setState(() => _filterKeyword = v),
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
                  onPressed: () {
                    setState(() => _autoScroll = !_autoScroll);
                    if (_autoScroll) _scrollToBottom();
                  },
                  tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
                ),
              ],
            ),
          ),
          // 日志列表
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.terminal,
                            size: 64,
                            color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('暂无日志',
                            style: TextStyle(color: Colors.grey.shade400)),
                        if (!bleState.connected) ...[
                          const SizedBox(height: 8),
                          Text('连接设备后将自动记录 BLE 通信日志',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12)),
                        ],
                      ],
                    ),
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
                            color: label.$2.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label.$1,
                              style: TextStyle(
                                  color: label.$2,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          log.decodeText.isNotEmpty
                              ? log.decodeText
                              : log.rawHex,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                        subtitle: Text(
                          '${_formatTime(log.timestamp)} '
                          '${log.dir == LogDirection.send ? "TX" : "RX"} '
                          '${log.deviceMac.isNotEmpty ? log.deviceMac : ""}',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500),
                        ),
                        trailing: log.dir == LogDirection.send
                            ? const Icon(Icons.arrow_upward,
                                size: 14, color: Colors.blue)
                            : const Icon(Icons.arrow_downward,
                                size: 14, color: Colors.green),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }
}
