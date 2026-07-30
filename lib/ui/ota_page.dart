import 'package:flutter/material.dart';

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
  double _progress = 0;
  bool _uploading = false;
  bool _dualChannel = false;
  int _chunkSize = 512;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OTA 固件升级')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 固件选择
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_present),
                title: Text(_firmwarePath ?? '选择固件文件'),
                subtitle: _firmwarePath != null
                    ? const Text('MD5: 计算中...')
                    : const Text('支持 .bin / .img / .dat 格式'),
                trailing: ElevatedButton(
                  onPressed: _uploading ? null : _selectFirmware,
                  child: const Text('选择'),
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
                    const Text('传输配置', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('双通道并行传输 (AR 眼镜)'),
                      value: _dualChannel,
                      onChanged: (v) =>
                          setState(() => _dualChannel = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 进度条
            if (_uploading || _progress > 0) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 16)),
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
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? _pauseOta : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('暂停'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectFirmware() {
    // TODO: 接入 file_picker 选择固件
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件选择功能待接入')),
    );
  }

  void _startOta() {
    setState(() => _uploading = true);
    // TODO: 调用 adapter.startOta
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先连接设备')),
    );
    setState(() => _uploading = false);
  }

  void _pauseOta() {
    // TODO: 调用 adapter.pauseOta
  }
}
