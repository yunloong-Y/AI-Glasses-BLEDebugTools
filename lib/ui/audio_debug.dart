import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';

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
  String _audioMode = 'A2DP';
  String _ancMode = 'OFF';
  bool _lowLatency = false;
  bool _sending = false;

  Future<void> _sendAudioCmd(String cmd, String description) async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先连接设备'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await adapter.sendAtCommand(cmd);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$description: $result'),
            backgroundColor: result.startsWith('OK') ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$description 失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final connected = bleState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音频调试'),
        actions: [
          if (connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(bleState.selectedDevice?.name ?? '',
                    style: const TextStyle(fontSize: 12)),
                avatar: const Icon(Icons.bluetooth_connected,
                    size: 18, color: Colors.white),
                backgroundColor: Colors.green.shade700,
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: !connected
          ? _buildNotConnected()
          : Stack(
              children: [
                AbsorbPointer(
                  absorbing: _sending,
                  child: Opacity(
                    opacity: _sending ? 0.6 : 1.0,
                    child: ListView(
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
                                  onSelectionChanged: (s) {
                                    setState(() => _audioMode = s.first);
                                    _sendAudioCmd('AT+AUDIO_MODE=$s.first', '音频模式');
                                  },
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
                                    ButtonSegment(value: 'TRANSPARENCY', label: Text('通透')),
                                  ],
                                  selected: {_ancMode},
                                  onSelectionChanged: (s) {
                                    setState(() => _ancMode = s.first);
                                    final cmd = s.first == 'OFF' ? 'AT+ANC=OFF' : 'AT+ANC=$s.first';
                                    _sendAudioCmd(cmd, '降噪模式');
                                  },
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
                                Row(
                                  children: [
                                    const SizedBox(width: 60, child: Text('左耳:')),
                                    Expanded(
                                      child: Slider(
                                        value: _micGainL,
                                        min: 0,
                                        max: 100,
                                        divisions: 100,
                                        label: _micGainL.toStringAsFixed(0),
                                        onChanged: (v) => setState(() => _micGainL = v),
                                        onChangeEnd: (v) =>
                                            _sendAudioCmd('AT+MIC_GAIN_L=${v.toInt()}', '左耳增益'),
                                      ),
                                    ),
                                    SizedBox(
                                        width: 40,
                                        child: Text('${_micGainL.toInt()}',
                                            textAlign: TextAlign.right)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const SizedBox(width: 60, child: Text('右耳:')),
                                    Expanded(
                                      child: Slider(
                                        value: _micGainR,
                                        min: 0,
                                        max: 100,
                                        divisions: 100,
                                        label: _micGainR.toStringAsFixed(0),
                                        onChanged: (v) => setState(() => _micGainR = v),
                                        onChangeEnd: (v) =>
                                            _sendAudioCmd('AT+MIC_GAIN_R=${v.toInt()}', '右耳增益'),
                                      ),
                                    ),
                                    SizedBox(
                                        width: 40,
                                        child: Text('${_micGainR.toInt()}',
                                            textAlign: TextAlign.right)),
                                  ],
                                ),
                                const Divider(),
                                Row(
                                  children: [
                                    const SizedBox(width: 60, child: Text('音量:')),
                                    Expanded(
                                      child: Slider(
                                        value: _audioVolume,
                                        min: 0,
                                        max: 100,
                                        divisions: 100,
                                        label: _audioVolume.toStringAsFixed(0),
                                        onChanged: (v) => setState(() => _audioVolume = v),
                                        onChangeEnd: (v) =>
                                            _sendAudioCmd('AT+AUDIO_GAIN=${v.toInt()}', '音量'),
                                      ),
                                    ),
                                    SizedBox(
                                        width: 40,
                                        child: Text('${_audioVolume.toInt()}',
                                            textAlign: TextAlign.right)),
                                  ],
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
                            onChanged: (v) {
                              setState(() => _lowLatency = v);
                              _sendAudioCmd(
                                'AT+LOW_LATENCY=${v ? 'ON' : 'OFF'}',
                                '低延迟模式',
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 读取当前状态按钮
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.sync, color: Colors.blue),
                            title: const Text('读取当前音频状态'),
                            subtitle: const Text('从设备读取 ANC、增益等寄存器值'),
                            onTap: () => _sendAudioCmd('AT+AUDIO_STATUS?', '读取状态'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_sending)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('请先连接设备',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          Text('连接后可在面板中控制音频参数',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}
