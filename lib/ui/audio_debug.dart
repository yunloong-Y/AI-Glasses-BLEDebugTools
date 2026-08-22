import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import 'theme.dart';

/// ============================================================
/// 音频调试面板 — iOS 风格
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
        SnackBar(
            content: const Text('请先连接设备'),
            backgroundColor: AppTheme.iosRed),
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
            backgroundColor:
                result.startsWith('OK') ? AppTheme.iosGreen : AppTheme.iosOrange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$description 失败: $e'),
              backgroundColor: AppTheme.iosRed),
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
      body: !connected
          ? CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  title: const Text('音频调试'),
                ),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: IosEmptyState(
                    icon: Icons.graphic_eq_rounded,
                    title: '请先连接设备',
                    subtitle: '连接后可在面板中控制音频参数',
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                AbsorbPointer(
                  absorbing: _sending,
                  child: Opacity(
                    opacity: _sending ? 0.6 : 1.0,
                    child: CustomScrollView(
                      slivers: [
                        SliverAppBar.large(
                          title: const Text('音频调试'),
                          actions: [
                            if (connected)
                              Container(
                                margin: const EdgeInsets.only(right: 16),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppTheme.iosGreen,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                        Icons.bluetooth_connected_rounded,
                                        size: 14,
                                        color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      bleState.selectedDevice?.name ?? '',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              [
                                // Audio mode
                                _buildSection('音频模式', [
                                  _SegmentedControl(
                                    value: _audioMode,
                                    options: const {
                                      'A2DP': 'A2DP',
                                      'HFP': 'HFP',
                                    },
                                    onChanged: (v) {
                                      setState(() => _audioMode = v);
                                      _sendAudioCmd(
                                          'AT+AUDIO_MODE=$v', '音频模式');
                                    },
                                  ),
                                ]),
                                const SizedBox(height: 12),

                                // ANC mode
                                _buildSection('降噪模式', [
                                  _SegmentedControl(
                                    value: _ancMode,
                                    options: const {
                                      'OFF': '关闭',
                                      'ANC': '降噪',
                                      'TRANSPARENCY': '通透',
                                    },
                                    onChanged: (v) {
                                      setState(() => _ancMode = v);
                                      final cmd = v == 'OFF'
                                          ? 'AT+ANC=OFF'
                                          : 'AT+ANC=$v';
                                      _sendAudioCmd(cmd, '降噪模式');
                                    },
                                  ),
                                ]),
                                const SizedBox(height: 12),

                                // Gain controls
                                _buildSection('麦克风增益', [
                                  _buildSliderRow(
                                      '左耳', _micGainL, AppTheme.iosBlue, (v) {
                                    setState(() => _micGainL = v);
                                  }, (v) {
                                    _sendAudioCmd(
                                        'AT+MIC_GAIN_L=${v.toInt()}', '左耳增益');
                                  }),
                                  Divider(
                                      height: 1,
                                      indent: 14,
                                      color: AppTheme.iosGray6),
                                  _buildSliderRow(
                                      '右耳', _micGainR, AppTheme.iosPurple,
                                      (v) {
                                    setState(() => _micGainR = v);
                                  }, (v) {
                                    _sendAudioCmd(
                                        'AT+MIC_GAIN_R=${v.toInt()}', '右耳增益');
                                  }),
                                  Divider(
                                      height: 1,
                                      indent: 14,
                                      color: AppTheme.iosGray6),
                                  _buildSliderRow(
                                      '音量', _audioVolume, AppTheme.iosTeal,
                                      (v) {
                                    setState(() => _audioVolume = v);
                                  }, (v) {
                                    _sendAudioCmd(
                                        'AT+AUDIO_GAIN=${v.toInt()}', '音量');
                                  }),
                                ]),
                                const SizedBox(height: 12),

                                // Low latency switch
                                IosCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    children: [
                                      SwitchListTile(
                                        title: const Text('低延迟模式 (游戏)'),
                                        subtitle: Text(
                                          '降低蓝牙音频延迟至 ~40ms',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.iosGray),
                                        ),
                                        value: _lowLatency,
                                        onChanged: (v) {
                                          setState(() => _lowLatency = v);
                                          _sendAudioCmd(
                                            'AT+LOW_LATENCY=${v ? 'ON' : 'OFF'}',
                                            '低延迟模式',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Read status
                                IosCard(
                                  padding: EdgeInsets.zero,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _sendAudioCmd(
                                        'AT+AUDIO_STATUS?', '读取状态'),
                                    child: const ListTile(
                                      leading: Icon(Icons.sync_rounded,
                                          color: AppTheme.iosBlue),
                                      title: Text('读取当前音频状态'),
                                      subtitle: Text('从设备读取 ANC、增益等寄存器值'),
                                      trailing: Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppTheme.iosGray3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_sending)
                  const Center(child: CupertinoActivityIndicator(radius: 16)),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.iosGray,
              letterSpacing: 0.5,
            ),
          ),
        ),
        IosCard(
          padding: const EdgeInsets.all(14),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSliderRow(
      String label, double value, Color color, ValueChanged<double> onChanged, ValueChanged<double> onChangeEnd) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 100,
              activeColor: color,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text('${value.toInt()}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ),
        ],
      ),
    );
  }
}

/// iOS 风格 SegmentedControl
class _SegmentedControl extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _SegmentedControl({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.iosGray6,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: options.entries.map((e) {
          final selected = e.key == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTheme.iosBlue : AppTheme.iosGray,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
