import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../adapter/base_bluetooth.dart';
import '../core/file_export.dart';
import '../core/log_parser.dart';
import '../core/protocol_parser.dart';
import '../core/protocol_registry.dart';
import '../core/gaia_protocol.dart';
import '../main.dart';
import 'theme.dart';

/// ============================================================
/// 实时日志控制台 — iOS 风格
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

  /// 报文解码缓存：key 为日志条目（每次新建唯一对象），value 为解码后的可读文本
  final Map<LogItem, String?> _decoded = {};

  final _logTypeLabels = {
    LogType.hci: ('HCI', AppTheme.iosBlue),
    LogType.vendorLog: ('VENDOR', AppTheme.iosPurple),
    LogType.audio: ('AUDIO', AppTheme.iosOrange),
    LogType.ota: ('OTA', AppTheme.iosTeal),
    LogType.atCmd: ('AT', AppTheme.iosRed),
    LogType.system: ('SYS', AppTheme.iosGray),
  };

  @override
  void initState() {
    super.initState();
    final logParser = context.read<LogParser>();
    _logSub = logParser.logStream.listen((item) {
      if (!mounted) return;
      // 一次性尝试用已加载的厂商协议帧格式解码，缓存结果
      if (item.rawHex.isNotEmpty) {
        _decoded[item] = _tryDecode(item);
      }
      setState(() {
        _logs.add(item);
        if (_logs.length > 5000) {
          _logs.removeRange(0, _logs.length - 5000);
        }
      });
      if (_autoScroll) _scrollToBottom();
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
        final kw = _filterKeyword.toLowerCase();
        return log.decodeText.toLowerCase().contains(kw) ||
            log.rawHex.toLowerCase().contains(kw) ||
            (_decoded[log]?.toLowerCase().contains(kw) ?? false);
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
              textColor: AppTheme.iosBlue,
              onPressed: () {
                Share.shareXFiles([XFile(path)]);
              },
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: AppTheme.iosRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final logs = _filteredLogs;

    return Scaffold(
      body: Column(
        children: [
          // iOS style large title header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '实时日志 ${bleState.connected ? "(${_logs.length})" : ""}',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        context.read<LogParser>().clear();
                        setState(() {
                          _logs.clear();
                          _decoded.clear();
                        });
                      },
                      tooltip: '清空',
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: _exportLogs,
                      tooltip: '导出',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Filter bar
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: '搜索关键字...',
                            prefixIcon: Icon(Icons.search_rounded, size: 18),
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setState(() => _filterKeyword = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Type filter chips
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTypeChip(null, '全部'),
                            ..._logTypeLabels.entries.map((e) =>
                                _buildTypeChip(e.key, e.value.$1, e.value.$2)),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _autoScroll
                            ? Icons.vertical_align_bottom_rounded
                            : Icons.vertical_align_top_rounded,
                        size: 20,
                        color: _autoScroll ? AppTheme.iosBlue : AppTheme.iosGray,
                      ),
                      onPressed: () {
                        setState(() => _autoScroll = !_autoScroll);
                        if (_autoScroll) _scrollToBottom();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Log list
          Expanded(
            child: logs.isEmpty
                ? IosEmptyState(
                    icon: Icons.terminal_rounded,
                    title: '暂无日志',
                    subtitle: bleState.connected
                        ? null
                        : '连接设备后将自动记录 BLE 通信日志',
                  )
                : Container(
                    color: Theme.of(context).cardTheme.color,
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: logs.length,
                      itemBuilder: (ctx, i) {
                        final log = logs[i];
                        final label = _logTypeLabels[log.type]!;
                        final isTx = log.dir == LogDirection.send;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppTheme.iosGray6,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Type badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: label.$2.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(label.$1,
                                    style: TextStyle(
                                        color: label.$2,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              // Direction icon
                              Icon(
                                isTx
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 14,
                                color: isTx
                                    ? AppTheme.iosBlue
                                    : AppTheme.iosGreen,
                              ),
                              const SizedBox(width: 6),
                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      log.decodeText.isNotEmpty
                                          ? log.decodeText
                                          : log.rawHex,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_formatTime(log.timestamp)}  ${log.deviceMac.isNotEmpty ? log.deviceMac : ""}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.iosGray),
                                    ),
                                    // 厂商协议解码结果（自动尝试，匹配不上不显示）
                                    if (_decoded[log] != null) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color:
                                              AppTheme.iosPurple.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _decoded[log]!,
                                          style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: AppTheme.iosPurple),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(LogType? type, String label, [Color? color]) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _filterType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? (color ?? AppTheme.iosBlue)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? (color ?? AppTheme.iosBlue)
                  : AppTheme.iosGray4,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.iosGray,
            ),
          ),
        ),
      ),
    );
  }

  /// 尝试用已加载的厂商协议帧格式解码一段原始 hex 日志。
  /// 解码成功返回可读文本，匹配不上（AT 文本指令、无魔术字等）返回 null。
  String? _tryDecode(LogItem item) {
    if (item.rawHex.isEmpty) return null;
    try {
      final bytes = ProtocolParser.hexToBytes(item.rawHex);
      if (bytes.isEmpty) return null;
      final frame = ProtocolParser.parseAuto(
          bytes, ProtocolRegistry().getAllFrameFormats());
      if (frame != null) {
        final buf = StringBuffer();
        buf.write('[${frame.formatName}]');
        if (!frame.checksumValid) buf.write(' ⚠️校验失败');
        for (final f in frame.fields) {
          buf.write(' ${f.name}=${f.displayValue}');
          if (f.enumLabel != null) buf.write('(${f.enumLabel})');
        }
        if (frame.error != null) buf.write(' · ${frame.error}');
        return buf.toString().trim();
      }
      // 通用帧格式未命中 → 尝试 Qualcomm GAIA 逆向协议解码
      // （MOONDROP Space Travel 等 TWS 设备，来源 SpaceTravel-Protocol）
      final gaia = GaiaDecoder.tryDecode(bytes);
      if (gaia != null) return gaia.format();
      return null;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }
}
