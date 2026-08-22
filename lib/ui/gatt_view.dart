import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../main.dart';
import 'theme.dart';

/// ============================================================
/// GATT 服务树面板 — iOS 风格
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(connected ? 'GATT' : 'GATT 服务'),
            actions: [
              if (connected)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () async {
                    await bleState.refreshServices();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已发现 ${services.length} 个服务'),
                          backgroundColor: AppTheme.iosGreen,
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
          if (!connected)
            SliverFillRemaining(
              hasScrollBody: false,
              child: IosEmptyState(
                icon: Icons.account_tree_rounded,
                title: '未连接设备',
                subtitle: '请先在扫描页连接设备',
              ),
            )
          else if (services.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CupertinoActivityIndicator(radius: 16),
                    const SizedBox(height: 16),
                    Text('正在发现服务...',
                        style:
                            TextStyle(color: AppTheme.iosGray, fontSize: 15)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList.builder(
                itemCount: services.length,
                itemBuilder: (ctx, i) {
                  final svc = services[i];
                  return _ServiceCard(
                    service: svc,
                    expanded: _expandedServices.contains(svc.uuid),
                    onToggle: () {
                      setState(() {
                        if (_expandedServices.contains(svc.uuid)) {
                          _expandedServices.remove(svc.uuid);
                        } else {
                          _expandedServices.add(svc.uuid);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          if (connected)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8, bottom: 16),
                child: Center(
                  child: Text('',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.contains('180a')) return Icons.info_rounded;
    if (lower.contains('180f')) return Icons.battery_charging_full_rounded;
    if (lower.contains('ff00') || lower.contains('ffe0')) return Icons.settings_rounded;
    return Icons.account_tree_rounded;
  }
}

/// 服务卡片（可展开）
class _ServiceCard extends StatelessWidget {
  final GattService service;
  final bool expanded;
  final VoidCallback onToggle;

  const _ServiceCard({
    required this.service,
    required this.expanded,
    required this.onToggle,
  });

  IconData _getServiceIcon(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.contains('180a')) return Icons.info_rounded;
    if (lower.contains('180f')) return Icons.battery_charging_full_rounded;
    if (lower.contains('ff00') || lower.contains('ffe0')) return Icons.settings_rounded;
    return Icons.account_tree_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.iosBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_getServiceIcon(service.uuid),
                        color: AppTheme.iosBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.displayName ?? service.uuid,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${service.characteristics.length} 个特征值',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.iosGray),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right_rounded,
                        color: AppTheme.iosGray3),
                  ),
                ],
              ),
            ),
          ),
          // Expanded children
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(height: 1, color: AppTheme.iosGray5),
                ...service.characteristics.map((ch) => _CharTile(
                      characteristic: ch,
                      serviceUuid: service.uuid,
                    )),
              ],
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// 特征值条目
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

    Color propColor = canNotify
        ? AppTheme.iosOrange
        : canWrite
            ? AppTheme.iosBlue
            : AppTheme.iosGreen;
    IconData propIcon = canNotify
        ? Icons.notifications_active_rounded
        : canWrite
            ? Icons.edit_rounded
            : Icons.download_rounded;

    return InkWell(
      onTap: () => _showCharDetail(ch, canRead, canWrite, canNotify),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(propIcon, size: 18, color: propColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ch.displayName ?? ch.uuid,
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500),
                  ),
                  if (displayValue != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _formatBytes(displayValue),
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.iosGray,
                            fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Property badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRead)
                  _propBadge('R', AppTheme.iosGreen),
                if (canWrite) ...[
                  const SizedBox(width: 3),
                  _propBadge('W', AppTheme.iosBlue),
                ],
                if (canNotify) ...[
                  const SizedBox(width: 3),
                  _propBadge('N', AppTheme.iosOrange),
                ],
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.iosGray3),
          ],
        ),
      ),
    );
  }

  Widget _propBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  void _showCharDetail(
      GattCharacteristic ch, bool canRead, bool canWrite, bool canNotify) {
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
      ),
    );
  }

  String _formatBytes(Uint8List data) {
    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final ascii =
        String.fromCharCodes(data.where((b) => b >= 32 && b <= 126));
    if (ascii.isNotEmpty && ascii.length == data.length) {
      return '$hex | "$ascii"';
    }
    return hex;
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

  const _CharDetailSheet({
    required this.characteristic,
    required this.serviceUuid,
    required this.canRead,
    required this.canWrite,
    required this.canNotify,
    required this.onNotifyValue,
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
      final data = await adapter.readChar(
          widget.serviceUuid, widget.characteristic.uuid);
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
      await adapter.writeChar(
          widget.serviceUuid, widget.characteristic.uuid, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('写入成功'),
              backgroundColor: AppTheme.iosGreen),
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
      await adapter.subscribeNotify(
        widget.serviceUuid,
        widget.characteristic.uuid,
        (data) {
          setState(() => _readValue = data);
          widget.onNotifyValue(data);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('已订阅 Notify'),
              backgroundColor: AppTheme.iosGreen),
        );
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
        SnackBar(content: Text(msg), backgroundColor: AppTheme.iosRed),
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
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grabber
          Center(
            child: Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.iosGray3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Title
          Row(
            children: [
              Expanded(
                child: Text(
                  ch.displayName ?? ch.uuid,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.iosGray5,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.iosGray),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(ch.uuid,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.iosGray, fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: ch.properties.map((p) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(p,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.iosBlue)),
              );
            }).toList(),
          ),
          const Divider(height: 24),

          // Current value
          if (value != null) ...[
            Text('当前值',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.iosGray)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.iosGray6,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _formatValue(value),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Actions
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else
            Row(
              children: [
                if (widget.canRead)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _read,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('读取'),
                    ),
                  ),
                if (widget.canRead && widget.canNotify) const SizedBox(width: 8),
                if (widget.canNotify)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleNotify,
                      icon: const Icon(Icons.notifications_rounded, size: 18),
                      label: const Text('订阅'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.iosOrange),
                    ),
                  ),
              ],
            ),

          // Write area
          if (widget.canWrite) ...[
            const SizedBox(height: 16),
            Text('写入数据',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.iosGray)),
            const SizedBox(height: 8),
            // HEX/ASCII toggle
            Row(
              children: [
                _buildToggleSegment('HEX', true),
                const SizedBox(width: 8),
                _buildToggleSegment('ASCII', false),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _writeController,
              decoration: InputDecoration(
                hintText: _isHexMode ? '01 02 FF...' : '输入文本',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 20),
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

  Widget _buildToggleSegment(String label, bool value) {
    final selected = (_isHexMode && value == true) || (!_isHexMode && value == false);
    return GestureDetector(
      onTap: () => setState(() => _isHexMode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.iosBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.iosBlue : AppTheme.iosGray4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.iosGray,
          ),
        ),
      ),
    );
  }

  String _formatValue(Uint8List data) {
    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final ascii = String.fromCharCodes(
      data.map((b) => (b >= 32 && b <= 126) ? b : 0x2E),
    );
    return 'HEX (${data.length} bytes): $hex\nASCII: $ascii';
  }
}
