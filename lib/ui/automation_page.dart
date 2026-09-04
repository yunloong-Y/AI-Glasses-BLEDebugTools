import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/script_engine.dart';
import '../main.dart';
import 'theme.dart';

/// ============================================================
/// 产线自动化 — iOS 风格
/// 用脚本引擎跑内置示例脚本，绑定已连接设备的真实 BLE 通路
/// ============================================================

class _SampleScript {
  final String name;
  final String description;
  final TestScript Function() build;
  const _SampleScript(this.name, this.description, this.build);
}

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  final _engine = ScriptEngine();
  final List<String> _outputs = [];
  double _progress = 0;
  bool _running = false;
  int _selected = 0;

  late final List<_SampleScript> _samples;
  StreamSubscription<String>? _outSub;
  StreamSubscription<double>? _progSub;

  @override
  void initState() {
    super.initState();
    _samples = _buildSamples();
    _outSub = _engine.output.listen((line) {
      if (mounted) setState(() => _outputs.add(line));
    });
    _progSub = _engine.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  void dispose() {
    _outSub?.cancel();
    _progSub?.cancel();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _toast('请先在「扫描」页连接设备', AppTheme.iosRed);
      return;
    }

    setState(() {
      _outputs.clear();
      _progress = 0;
      _running = true;
    });

    final script = _samples[_selected].build();
    final allPassed = await _engine.execute(
      script,
      onSendAt: (cmd) => adapter.sendAtCommand(cmd),
      onWriteReg: (addr, data) =>
          adapter.writeRegister(addr, Uint8List.fromList(data)),
      onReadReg: (addr) => adapter.readRegister(addr, 4),
      onConnect: () async {
        if (!bleState.connected && bleState.selectedDevice != null) {
          await adapter.connect(bleState.selectedDevice!.mac);
        }
      },
      onDisconnect: () => adapter.disconnect(),
    );

    if (mounted) {
      setState(() => _running = false);
      _toast(
        allPassed ? '全部断言通过' : '存在失败断言，见输出',
        allPassed ? AppTheme.iosGreen : AppTheme.iosRed,
      );
    }
  }

  void _stop() {
    _engine.stop();
    setState(() => _running = false);
  }

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final deviceName = bleState.selectedDevice?.name ?? '未连接';

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '产线自动化',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5),
                  ),
                ),
                if (_running)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_rounded),
                    color: AppTheme.iosRed,
                    onPressed: _stop,
                    tooltip: '停止',
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.play_circle_rounded),
                    color: AppTheme.iosBlue,
                    onPressed: _run,
                    tooltip: '运行',
                  ),
              ],
            ),
          ),
          // 设备状态条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  bleState.connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_rounded,
                  size: 16,
                  color: bleState.connected
                      ? AppTheme.iosGreen
                      : AppTheme.iosGray,
                ),
                const SizedBox(width: 6),
                Text(
                  deviceName,
                  style: TextStyle(
                      fontSize: 13,
                      color: bleState.connected
                          ? AppTheme.iosGray
                          : AppTheme.iosGray),
                ),
                const Spacer(),
                if (_running)
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: AppTheme.iosGray4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.iosBlue),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('示例脚本',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._samples.asMap().entries.map((e) => _ScriptCard(
                      sample: e.value,
                      selected: _selected == e.key,
                      enabled: !_running,
                      onTap: () => setState(() => _selected = e.key),
                    )),
                const SizedBox(height: 16),
                const Text('运行输出',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildOutput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutput() {
    if (_outputs.isEmpty) {
      return IosEmptyState(
        icon: Icons.terminal_rounded,
        title: '暂无输出',
        subtitle: _running ? '脚本运行中…' : '选择脚本后点击右上角运行',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        _outputs.join('\n'),
        style: const TextStyle(
            fontFamily: 'monospace', fontSize: 12, height: 1.4),
      ),
    );
  }

  List<_SampleScript> _buildSamples() => [
        _SampleScript(
          '通用冒烟测试',
          '连接 → 查询版本/电量 → 读寄存器 → 校验响应 → 断开',
          () => TestScript(
            name: '通用冒烟测试',
            description: '连接后查询版本/电量并读寄存器',
            steps: [
              ScriptStep([ScriptAction.connect()], name: '连接设备'),
              ScriptStep([
                ScriptAction.sendAt('AT+VERSION?'),
                ScriptAction.delay(300),
              ], name: '查询固件版本'),
              ScriptStep([
                ScriptAction.sendAt('AT+BATTERY?'),
                ScriptAction.delay(300),
              ], name: '查询电量'),
              ScriptStep([ScriptAction.readReg(0x00, 4)], name: '读芯片ID'),
              ScriptStep([
                ScriptAction.assertResult('OK'),
                ScriptAction.log('冒烟测试完成'),
              ], name: '校验响应'),
              ScriptStep([ScriptAction.disconnect()], name: '断开'),
            ],
          ),
        ),
        _SampleScript(
          '寄存器批量回读',
          '连续读取多个寄存器地址，验证读写通路',
          () => TestScript(
            name: '寄存器批量回读',
            description: '连续读取多个寄存器地址',
            steps: [
              ScriptStep([ScriptAction.connect()], name: '连接'),
              for (final addr in [0x00, 0x10, 0x20, 0x30])
                ScriptStep([ScriptAction.readReg(addr, 4)],
                    name: '读 0x${addr.toRadixString(16).padLeft(2, '0')}'),
              ScriptStep([ScriptAction.disconnect()], name: '断开'),
            ],
          ),
        ),
        _SampleScript(
          'AT 指令序列',
          '发送一组标准 AT 指令，验证 AT 通道',
          () => TestScript(
            name: 'AT 指令序列',
            description: '发送一组标准 AT 指令',
            steps: [
              ScriptStep([ScriptAction.connect()], name: '连接'),
              ScriptStep([
                ScriptAction.sendAt('AT+VERSION?'),
                ScriptAction.delay(200),
                ScriptAction.sendAt('AT+NAME?'),
                ScriptAction.delay(200),
                ScriptAction.sendAt('AT+BATTERY?'),
                ScriptAction.delay(200),
              ], name: '发送指令组'),
              ScriptStep([ScriptAction.disconnect()], name: '断开'),
            ],
          ),
        ),
      ];
}

/// 脚本选择卡片
class _ScriptCard extends StatelessWidget {
  final _SampleScript sample;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ScriptCard({
    required this.sample,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.iosBlue.withOpacity(0.10)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: AppTheme.iosBlue, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppTheme.iosBlue : AppTheme.iosGray,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sample.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sample.description,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.iosGray),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
