import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../adapter/base_bluetooth.dart';
import '../plugins/base_plugin.dart';
import 'theme.dart';

/// ============================================================
/// OTA 固件升级 — iOS 风格
/// ============================================================

class OtaPage extends StatefulWidget {
  const OtaPage({super.key});

  @override
  State<OtaPage> createState() => _OtaPageState();
}

class _OtaPageState extends State<OtaPage> {
  String? _firmwarePath;
  String _firmwareName = '';
  int _firmwareSize = 0;
  String _md5Hash = '';
  double _progress = 0;
  bool _uploading = false;
  bool _paused = false;
  int _chunkSize = 512;
  String _statusText = '';

  Future<void> _selectFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin', 'img', 'dat', 'hex', 'zip'],
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    final file = File(path);
    final bytes = file.readAsBytesSync();

    setState(() {
      _firmwarePath = path;
      _firmwareName = result.files.first.name;
      _firmwareSize = bytes.length;
      _md5Hash = _computeMd5(bytes);
    });
  }

  String _computeMd5(Uint8List bytes) {
    return md5.convert(bytes).toString();
  }

  Future<void> _startOta() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _showSnack('请先连接设备', AppTheme.iosRed);
      return;
    }

    if (_firmwarePath == null) {
      _showSnack('请先选择固件文件', AppTheme.iosRed);
      return;
    }

    final plugin = bleState.selectedDevice != null
        ? PluginRegistry().matchPlugin(bleState.selectedDevice!)
        : null;
    if (plugin != null) {
      _chunkSize = plugin.otaChunkSize;
    }

    setState(() {
      _uploading = true;
      _progress = 0;
      _paused = false;
      _statusText = '准备升级...';
    });

    try {
      // AT+OTA_BEGIN 只是「进入升级模式」的触发指令，并非所有固件都实现。
      // 改造前这里裸 await 且无保护，一旦设备不响应就会抛异常，
      // 导致固件一个字节都发不出去。改为尽力而为：失败只记录，不阻断传输。
      await _tryAtCommand(adapter, 'AT+OTA_BEGIN');

      setState(() => _statusText = '正在传输固件...');

      final result = await adapter.startOta(
        _firmwarePath!,
        chunkSize: _chunkSize,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _statusText =
                '传输中 ${_formatBytes((_firmwareSize * p).round())} / ${_formatBytes(_firmwareSize)}';
          });
        },
      );

      if (result.success) {
        await _tryAtCommand(adapter, 'AT+OTA_END');
      }

      if (!mounted) return;
      setState(() {
        _statusText = result.message;
        _uploading = false;
      });

      _showSnack(
        result.message,
        result.success ? AppTheme.iosGreen : AppTheme.iosRed,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _statusText = '升级失败: $e';
      });
      _showSnack('OTA 失败: $e', AppTheme.iosRed);
    }
  }

  /// 尽力而为地发一条 AT 指令：失败只记录日志，不阻断主流程
  ///
  /// 用于 OTA_BEGIN / OTA_END 这类「有最好、没有也能跑」的触发指令。
  Future<void> _tryAtCommand(
      BaseBluetoothAdapter adapter, String command) async {
    try {
      await adapter.sendAtCommand(command);
    } catch (e) {
      // 设备未实现该指令属正常情况，不该让整次升级失败
      debugPrint('$command 未生效（忽略）: $e');
    }
  }

  Future<void> _pauseOta() async {
    final adapter = context.read<BleState>().adapter;
    if (adapter == null) return;

    if (!_paused) {
      await adapter.pauseOta();
      if (!mounted) return;
      setState(() {
        _paused = true;
        _uploading = false;
        _statusText = '已暂停（断点 ${_formatBytes(adapter.otaTransferredBytes)}，'
            '点击继续从断点续传）';
      });
    } else {
      // 续传必须重启传输循环：协议层的断点已经记录在 adapter 内，
      // 这里重新调用 _startOta 会自动从断点接着发。
      await adapter.resumeOta();
      if (!mounted) return;
      setState(() {
        _paused = false;
      });
      await _startOta();
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final connected = bleState.connected;
    final plugin = bleState.selectedDevice != null
        ? PluginRegistry().matchPlugin(bleState.selectedDevice!)
        : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('OTA 固件升级'),
            actions: [
              if (connected)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.iosBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    plugin?.name ?? bleState.selectedDevice?.name ?? '',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.iosBlue),
                  ),
                ),
            ],
          ),
          if (!connected)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: IosEmptyState(
                icon: Icons.system_update_rounded,
                title: '请先连接设备',
                subtitle: '连接后在面板中选择固件开始升级',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Firmware info section
                  _buildSectionHeader('固件信息'),
                  IosCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('固件文件',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ),
                            ElevatedButton.icon(
                              onPressed:
                                  _uploading ? null : _selectFirmware,
                              icon: const Icon(Icons.folder_open_rounded,
                                  size: 18),
                              label: const Text('选择'),
                            ),
                          ],
                        ),
                        if (_firmwarePath != null) ...[
                          const SizedBox(height: 12),
                          _infoRow('文件名', _firmwareName),
                          _infoRow('大小', _formatBytes(_firmwareSize)),
                          _infoRow('MD5', _md5Hash, mono: true),
                        ] else ...[
                          const SizedBox(height: 16),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.file_present_rounded,
                                    size: 40, color: AppTheme.iosGray3),
                                const SizedBox(height: 8),
                                Text(
                                  '支持 .bin / .img / .dat / .hex / .zip',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.iosGray),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Config section
                  _buildSectionHeader('传输配置'),
                  IosCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Text('分片大小'),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.iosGray6,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<int>(
                                  value: _chunkSize,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.iosBlue,
                                      fontWeight: FontWeight.w600),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 128, child: Text('128 B')),
                                    DropdownMenuItem(
                                        value: 256, child: Text('256 B')),
                                    DropdownMenuItem(
                                        value: 512, child: Text('512 B')),
                                    DropdownMenuItem(
                                        value: 1024, child: Text('1024 B')),
                                    DropdownMenuItem(
                                        value: 4096, child: Text('4096 B')),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _chunkSize = v ?? 512),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                            height: 1, indent: 14, color: AppTheme.iosGray6),
                        SwitchListTile(
                          title: const Text('双通道并行传输'),
                          subtitle: Text(
                            plugin != null && plugin.otaSupportDualChannel
                                ? '设备声明支持，但传输层尚未实现（BLE 单链路无法真并行）'
                                : '此设备不支持双通道',
                            style: TextStyle(
                                fontSize: 13, color: AppTheme.iosGray),
                          ),
                          // 传输层未实现，开关保持关闭且不可操作，
                          // 避免出现「打开了但没生效」的假象。
                          value: false,
                          onChanged: null,
                        ),
                        if (plugin != null)
                          Divider(
                              height: 1, indent: 14, color: AppTheme.iosGray6),
                        if (plugin != null)
                          ListTile(
                            dense: true,
                            title: Text(
                                '断点续传: ${plugin.otaSupportResume ? "支持" : "不支持"}',
                                style: const TextStyle(fontSize: 14)),
                            trailing: Icon(
                              plugin.otaSupportResume
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 18,
                              color: plugin.otaSupportResume
                                  ? AppTheme.iosGreen
                                  : AppTheme.iosGray,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Progress
                  if (_uploading || _progress > 0) ...[
                    _buildSectionHeader('升级进度'),
                    IosCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _statusText.isEmpty
                                      ? '升级进度'
                                      : _statusText,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.iosGray),
                                ),
                              ),
                              Text(
                                '${(_progress * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: _progress >= 1.0
                                        ? AppTheme.iosGreen
                                        : AppTheme.iosBlue),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 8,
                              backgroundColor: AppTheme.iosGray5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _progress >= 1.0
                                    ? AppTheme.iosGreen
                                    : AppTheme.iosBlue,
                              ),
                            ),
                          ),
                          if (_uploading &&
                              _progress > 0 &&
                              _progress < 1) ...[
                            const SizedBox(height: 8),
                            Text(
                              '已传输 ${_formatBytes((_firmwareSize * _progress).round())} / ${_formatBytes(_firmwareSize)}',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.iosGray),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_firmwarePath == null || _uploading)
                              ? null
                              : _startOta,
                          icon: const Icon(Icons.upload_rounded),
                          label: const Text('开始升级'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _uploading ? _pauseOta : null,
                          icon: Icon(_paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded),
                          label: Text(_paused ? '恢复' : '暂停'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Success message
                  if (_progress >= 1.0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.iosGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.iosGreen.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppTheme.iosGreen),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '固件升级完成！设备将自动重启。',
                              style: TextStyle(
                                  color: AppTheme.iosGreen,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6, top: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.iosGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: AppTheme.iosGray)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
