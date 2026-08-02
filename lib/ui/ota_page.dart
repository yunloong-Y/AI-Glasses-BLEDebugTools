import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../plugins/base_plugin.dart';

/// ============================================================
/// OTA 固件升级面板
/// 支持固件校验、分片传输、断点续传、进度可视化
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
  bool _dualChannel = false;
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
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<void> _startOta() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _showSnack('请先连接设备', Colors.red);
      return;
    }

    if (_firmwarePath == null) {
      _showSnack('请先选择固件文件', Colors.red);
      return;
    }

    // 获取匹配插件的 OTA 分片大小
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

    // 发送 OTA 开始指令
    try {
      await adapter.sendAtCommand('AT+OTA_BEGIN');
      _statusText = '正在传输固件...';

      final result = await adapter.startOta(
        _firmwarePath!,
        onProgress: (p) {
          setState(() {
            _progress = p;
            _statusText = '传输中 ${_formatBytes((_firmwareSize * p).round())} / ${_formatBytes(_firmwareSize)}';
          });
        },
      );

      // 发送 OTA 结束指令
      if (result.success) {
        await adapter.sendAtCommand('AT+OTA_END');
      }

      setState(() {
        _statusText = result.message;
        _uploading = false;
      });

      _showSnack(
        result.message,
        result.success ? Colors.green : Colors.red,
      );
    } catch (e) {
      setState(() {
        _uploading = false;
        _statusText = '升级失败: $e';
      });
      _showSnack('OTA 失败: $e', Colors.red);
    }
  }

  Future<void> _pauseOta() async {
    final adapter = context.read<BleState>().adapter;
    if (adapter == null) return;

    if (!_paused) {
      await adapter.pauseOta();
      setState(() {
        _paused = true;
        _statusText = '已暂停';
      });
    } else {
      await adapter.resumeOta();
      setState(() {
        _paused = false;
        _statusText = '已恢复';
      });
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

    // 获取插件 OTA 配置
    final plugin = bleState.selectedDevice != null
        ? PluginRegistry().matchPlugin(bleState.selectedDevice!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OTA 固件升级'),
        actions: [
          if (connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(plugin?.name ?? bleState.selectedDevice?.name ?? '',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.blue.shade100,
              ),
            ),
        ],
      ),
      body: !connected
          ? _buildNotConnected()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 固件信息卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('固件信息',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Spacer(),
                              ElevatedButton.icon(
                                onPressed: _uploading ? null : _selectFirmware,
                                icon: const Icon(Icons.folder_open, size: 18),
                                label: const Text('选择'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_firmwarePath != null) ...[
                            _infoRow('文件名', _firmwareName),
                            _infoRow('大小', _formatBytes(_firmwareSize)),
                            _infoRow('MD5', _md5Hash,
                                isMonospace: true, maxLines: 1),
                            _infoRow('路径', _firmwarePath!,
                                isMonospace: true, maxLines: 1),
                          ] else ...[
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Icon(Icons.file_present,
                                        size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text('支持 .bin / .img / .dat / .hex / .zip 格式',
                                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 配置选项
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('传输配置',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('分片大小'),
                              const SizedBox(width: 16),
                              DropdownButton<int>(
                                value: _chunkSize,
                                items: const [
                                  DropdownMenuItem(value: 128, child: Text('128 B')),
                                  DropdownMenuItem(value: 256, child: Text('256 B')),
                                  DropdownMenuItem(value: 512, child: Text('512 B')),
                                  DropdownMenuItem(value: 1024, child: Text('1024 B')),
                                  DropdownMenuItem(value: 4096, child: Text('4096 B')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _chunkSize = v ?? 512),
                              ),
                              const Spacer(),
                              if (plugin != null) ...[
                                const Text('推荐: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text('${plugin.otaChunkSize} B',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ]
                            ],
                          ),
                          SwitchListTile(
                            title: const Text('双通道并行传输 (AR 眼镜)'),
                            subtitle: Text(
                              plugin != null && plugin.otaSupportDualChannel
                                  ? '此设备支持双通道'
                                  : '此设备不支持双通道',
                              style: TextStyle(
                                fontSize: 12,
                                color: plugin != null && plugin.otaSupportDualChannel
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            value: _dualChannel && (plugin?.otaSupportDualChannel ?? false),
                            onChanged: (plugin?.otaSupportDualChannel ?? false)
                                ? (v) => setState(() => _dualChannel = v)
                                : null,
                          ),
                          if (plugin != null)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.info_outline, size: 18),
                              title: Text('断点续传: ${plugin.otaSupportResume ? "支持" : "不支持"}',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 进度条
                  if (_uploading || _progress > 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _statusText.isEmpty ? '升级进度' : _statusText,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700),
                                ),
                                Text(
                                  '${(_progress * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _progress,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _progress >= 1.0 ? Colors.green : Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 传输速度估算
                            if (_uploading && _progress > 0 && _progress < 1)
                              Text(
                                _estimateSpeed(),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 操作按钮
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_firmwarePath == null || _uploading)
                              ? null
                              : _startOta,
                          icon: const Icon(Icons.upload),
                          label: const Text('开始升级'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _uploading ? _pauseOta : null,
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          label: Text(_paused ? '恢复' : '暂停'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 升级完成后显示重启提示
                  if (_progress >= 1.0) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.green.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '固件升级完成！设备将自动重启，请等待重新连接。',
                                style: TextStyle(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.system_update, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('请先连接设备',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          Text('连接后在面板中选择固件开始升级',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value,
      {bool isMonospace = false, int maxLines = 2}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: isMonospace ? 'monospace' : null,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _estimateSpeed() {
    if (_firmwareSize == 0 || _progress == 0) return '';
    final sent = (_firmwareSize * _progress).round();
    return '已传输 ${_formatBytes(sent)} / ${_formatBytes(_firmwareSize)}';
  }
}
