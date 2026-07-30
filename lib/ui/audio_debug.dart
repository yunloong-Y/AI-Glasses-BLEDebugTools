import 'package:flutter/material.dart';

/// ============================================================
/// 音频调试面板 (TWS / AR 眼镜专用)
/// HFP/A2DP 通路切换、麦克风增益、ANC、左右耳同步
/// ============================================================

class AudioDebugPage extends StatefulWidget {
  const AudioDebugPage({super.key});

  @override
  State<AudioDebugPage> createState() => _AudioDebugPageState();
}

class _AudioDebugPageState extends State<AudioDebugPage> {
  double _micGainL = 50;
  double _micGainR = 50;
  double _audioVolume = 80;
  String _audioMode = 'A2DP'; // A2DP / HFP
  String _ancMode = 'OFF'; // OFF / ANC / TRANSPARENCY
  bool _lowLatency = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音频调试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音频模式切换
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('音频模式',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'A2DP', label: Text('A2DP (音乐)')),
                      ButtonSegment(value: 'HFP', label: Text('HFP (通话)')),
                    ],
                    selected: {_audioMode},
                    onSelectionChanged: (s) =>
                        setState(() => _audioMode = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ANC 模式
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('降噪模式',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'OFF', label: Text('关闭')),
                      ButtonSegment(value: 'ANC', label: Text('降噪')),
                      ButtonSegment(
                          value: 'TRANSPARENCY', label: Text('通透')),
                    ],
                    selected: {_ancMode},
                    onSelectionChanged: (s) =>
                        setState(() => _ancMode = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 增益控制
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('麦克风增益',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('左耳: ${_micGainL.toInt()}'),
                  Slider(
                    value: _micGainL,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _micGainL.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _micGainL = v),
                  ),
                  Text('右耳: ${_micGainR.toInt()}'),
                  Slider(
                    value: _micGainR,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _micGainR.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _micGainR = v),
                  ),
                  const Divider(),
                  Text('音量: ${_audioVolume.toInt()}'),
                  Slider(
                    value: _audioVolume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _audioVolume.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _audioVolume = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 低延迟模式
          Card(
            child: SwitchListTile(
              title: const Text('低延迟模式 (游戏)'),
              subtitle: const Text('降低蓝牙音频延迟至 ~40ms'),
              value: _lowLatency,
              onChanged: (v) => setState(() => _lowLatency = v),
            ),
          ),
        ],
      ),
    );
  }
}
