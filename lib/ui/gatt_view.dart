import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../main.dart';

/// ============================================================
/// GATT 服务树面板
/// 自动解析 Service/Characteristic, 支持读写/通知
/// ============================================================

class GattView extends StatefulWidget {
  const GattView({super.key});

  @override
  State<GattView> createState() => _GattViewState();
}

class _GattViewState extends State<GattView> {
  final _expandedServices = <String>{};

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final services = bleState.services;
    final connected = bleState.connected;
    final deviceName = bleState.selectedDevice?.name ?? '未连接';

    return Scaffold(
      appBar: AppBar(
        title: Text(connected ? 'GATT - $deviceName' : 'GATT 服务树'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: connected
                ? () async {
                    await bleState.refreshServices();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '已发现 ${services.length} 个服务'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                : null,
          ),
        ],
      ),
      body: !connected
          ? _buildNotConnected()
          : services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('正在发现服务...',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: services.length,
                  itemBuilder: (ctx, i) {
                    final svc = services[i];
                    final expanded = _expandedServices.contains(svc.uuid);
                    return ExpansionTile(
                      title: Text(
                        svc.displayName ?? svc.uuid,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${svc.characteristics.length} characteristics',
                        style: const TextStyle(fontSize: 12),
                      ),
                      leading: Icon(
                        _getServiceIcon(svc.uuid),
                        color: Colors.blue,
                        size: 20,
                      ),
                      initiallyExpanded: expanded,
                      onExpansionChanged: (v) {
                        setState(() {
                          if (v) {
                            _expandedServices.add(svc.uuid);
                          } else {
                            _expandedServices.remove(svc.uuid);
                          }
                        });
                      },
                      children: svc.characteristics.map((ch) {
                        return _CharTile(
                          characteristic: ch,
                          serviceUuid: svc.uuid,
                        );
                      }).toList(),
                    );
                  },
                ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_tree, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('未发现服务',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          Text('请先在扫描页连接设备',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.contains('180a')) return Icons.info;
    if (lower.contains('180f')) return Icons.battery_charging_full;
    if (lower.contains('ff00') || lower.contains('ffe0')) return Icons.settings;
    return Icons.account_tree;
  }
}

/// 单个特征值条目
class _CharTile extends StatefulWidget {
  final GattCharacteristic characteristic;
  final String serviceUuid;

  const _CharTile({
    required this.characteristic,
    required this.serviceUuid,
  });

  @override
  State<_CharTile> createState() => _CharTileState();
}

class _CharTileState extends State<_CharTile> {
  bool _subscribed = false;
  Uint8List? _notifyValue;

  @override
  Widget build(BuildContext context) {
    final ch = widget.characteristic;
    final canRead = ch.properties.contains('read');
    final canWrite = ch.properties.contains('write') ||
        ch.properties.contains('writeNoResp');
    final canNotify =
        ch.properties.contains('notify') || ch.properties.contains('indicate');

    final displayValue = _notifyValue ?? ch.lastValue;

    return ListTile(
      dense: true,
      leading: Icon(
        canNotify
            ? Icons.notifications_active
            : canWrite
                ? Icons.edit
                : Icons.read_more,
        size: 20,
        color: canNotify
            ? Colors.orange
            : canWrite
                ? Colors.blue
                : Colors.green,
      ),
      title: Text(
        ch.displayName ?? ch.uuid,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ch.properties.join(', '),
            style: const TextStyle(fontSize: 11),
          ),
          if (displayValue != null)
            Text(
              _formatBytes(displayValue),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: _buildTrailingWidget(canRead, canWrite, canNotify),
      onTap: () => _showCharDetail(ch, canRead, canWrite, canNotify),
    );
  }

  Widget _buildTrailingWidget(bool canRead, bool canWrite, bool canNotify) {
    final value = _notifyValue ?? widget.characteristic.lastValue;
    if (value != null) {
      return Text(
        '${value.length}B',
        style: const TextStyle(fontSize: 12),
      );
    }
    return const Text('--', style: TextStyle(fontSize: 12));
  }

  void _showCharDetail(GattCharacteristic ch, bool canRead, bool canWrite, bool canNotify) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CharDetailSheet(
        characteristic: ch,
        serviceUuid: widget.serviceUuid,
        canRead: canRead,
        canWrite: canWrite,
        canNotify: canNotify,
        onNotifyValue: (val) {
          setState(() => _notifyValue = val);
        },
        onSubscribeChange: (subscribed) {
          setState(() => _subscribed = subscribed);
        },
      ),
    );
  }

  String _formatBytes(Uint8List data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    // 同时尝试 ASCII
    final ascii = String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));
    if (ascii.isNotEmpty && ascii.length == data.length) {
      return 'HEX: $hex\nASCII: $ascii';
    }
    return 'HEX: $hex';
  }
}

/// 特征值详情面板
class _CharDetailSheet extends StatefulWidget {
  final GattCharacteristic characteristic;
  final String serviceUuid;
  final bool canRead;
  final bool canWrite;
  final bool canNotify;
  final Function(Uint8List) onNotifyValue;
  final Function(bool) onSubscribeChange;

  const _CharDetailSheet({
    required this.characteristic,
    required this.serviceUuid,
    required this.canRead,
    required this.canWrite,
    required this.canNotify,
    required this.onNotifyValue,
    required this.onSubscribeChange,
  });

  @override
  State<_CharDetailSheet> createState() => _CharDetailSheetState();
}

class _CharDetailSheetState extends State<_CharDetailSheet> {
  final _writeController = TextEditingController();
  bool _isHexMode = true;
  bool _loading = false;
  Uint8List? _readValue;

  @override
  void dispose() {
    _writeController.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) return;

    setState(() => _loading = true);
    try {
      final data = await adapter.readChar(widget.serviceUuid, widget.characteristic.uuid);
      setState(() => _readValue = data);
    } catch (e) {
      _showError('读取失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _write() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) return;

    Uint8List data;
    if (_isHexMode) {
      // 解析 HEX 输入
      final hex = _writeController.text.trim().replaceAll(' ', '');
      final bytes = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      data = Uint8List.fromList(bytes);
    } else {
      data = Uint8List.fromList(_writeController.text.codeUnits);
    }

    setState(() => _loading = true);
    try {
      await adapter.writeChar(widget.serviceUuid, widget.characteristic.uuid, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写入成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _showError('写入失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleNotify() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) return;

    setState(() => _loading = true);
    try {
      if (widget.canNotify) {
        await adapter.subscribeNotify(
          widget.serviceUuid,
          widget.characteristic.uuid,
          (data) {
            setState(() => _readValue = data);
            widget.onNotifyValue(data);
          },
        );
        widget.onSubscribeChange(true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已订阅 Notify'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      _showError('订阅失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.characteristic;
    final value = _readValue ?? ch.lastValue;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Expanded(
                child: Text(
                  ch.displayName ?? ch.uuid,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(ch.uuid,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: ch.properties.map((p) {
              return Chip(
                label: Text(p, style: const TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
          const Divider(),

          // 当前值
          if (value != null) ...[
            const Text('当前值:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _formatValue(value),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // 操作按钮
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else ...[
            Wrap(
              spacing: 8,
              children: [
                if (widget.canRead)
                  ElevatedButton.icon(
                    onPressed: _read,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('读取'),
                  ),
                if (widget.canNotify)
                  ElevatedButton.icon(
                    onPressed: _toggleNotify,
                    icon: const Icon(Icons.notifications, size: 18),
                    label: const Text('订阅 Notify'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
              ],
            ),
          ],

          // 写入区域
          if (widget.canWrite) ...[
            const SizedBox(height: 12),
            const Text('写入数据:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('HEX')),
                    ButtonSegment(value: false, label: Text('ASCII')),
                  ],
                  selected: {_isHexMode},
                  onSelectionChanged: (s) => setState(() => _isHexMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _writeController,
              decoration: InputDecoration(
                hintText: _isHexMode ? '01 02 FF...' : '输入文本',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _write,
                ),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onSubmitted: (_) => _write(),
            ),
          ],
        ],
      ),
    );
  }

  String _formatValue(Uint8List data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii = String.fromCharCodes(
      data.map((b) => (b >= 32 && b <= 126) ? b : 0x2E), // 非可见字符用 . 代替
    );
    return 'HEX ($data bytes): $hex\nASCII: $ascii';
  }
}
