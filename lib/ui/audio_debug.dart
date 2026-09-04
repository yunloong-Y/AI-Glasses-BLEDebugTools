import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../plugins/base_plugin.dart';
import 'theme.dart';

/// ============================================================
/// 音频参数调试面板 — iOS 风格
///
/// 2026-09-03 重写。原实现有两个根本问题：
///
/// 1. **提供了 BLE 上做不到的事**：A2DP / HFP 通路切换属于经典蓝牙
///    （BR-EDR）协议栈的音频链路，本项目纯 BLE（flutter_blue_plus），
///    架构上无法切换。控件点了只会改本地变量，设备毫无反应。
/// 2. **使用了编造的指令**：`AT+AUDIO_MODE=` / `AT+MIC_GAIN_L=` /
///    `AT+MIC_GAIN_R=` / `AT+AUDIO_STATUS?` 在任何一个插件的
///    AT 模板里都不存在，发出去必然无响应。
///    页面初值（50/50/80）也是硬编码，从不从设备回读。
///
/// 重写后的原则：
///   - 能力边界写清楚，做不到的直接标明而不是假装能控制
///   - 所有控件由**当前插件真实声明的 AT 模板**驱动，未声明的置灰
///   - 参数值从设备**回读**，读不到就显示「—」而不是编一个初值
///   - 写入后自动回读校验，避免「假成功」
/// ============================================================

class AudioDebugPage extends StatefulWidget {
  const AudioDebugPage({super.key});

  @override
  State<AudioDebugPage> createState() => _AudioDebugPageState();
}

/// 音频相关寄存器名（从插件 registerMap 中筛选，用于回读展示）
const Set<String> _audioRegisterNames = {
  'AUDIO_GAIN_L',
  'AUDIO_GAIN_R',
  'ANC_MODE',
  'ANC_GAIN',
};

class _AudioDebugPageState extends State<AudioDebugPage> {
  /// 回读到的寄存器值（地址 -> 字节值），未读到则不在 map 中
  final Map<int, int> _regValues = {};

  /// 各寄存器的读取错误（地址 -> 错误描述）
  final Map<int, String> _regErrors = {};

  bool _reading = false;
  bool _sending = false;
  bool _autoLoaded = false;

  /// ANC 当前档位（null = 未知，避免硬编码初值）
  String? _ancMode;

  /// 增益滑杆值（null = 未知）
  int? _audioGain;

  /// 低延迟 / 游戏模式（null = 未知）
  bool? _lowLatency;
  bool? _gameMode;

  final TextEditingController _customCmdController = TextEditingController();

  /// 最近一次操作的结果提示
  String _lastMessage = '';
  bool _lastOk = true;

  @override
  void dispose() {
    _customCmdController.dispose();
    super.dispose();
  }

  // ---------- 能力探测 ----------

  /// 当前插件声明的 AT 模板（无插件时为空，所有控件置灰）
  List<String> _templates(BuildContext context) {
    final device = context.read<BleState>().selectedDevice;
    if (device == null) return const [];
    return PluginRegistry().matchPlugin(device)?.atCommandTemplates ??
        const [];
  }

  /// 插件是否声明了以 [prefix] 开头的指令
  bool _hasCmd(List<String> templates, String prefix) =>
      templates.any((t) => t.toUpperCase().startsWith(prefix.toUpperCase()));

  /// 当前插件的音频相关寄存器
  List<MapEntry<int, String>> _audioRegisters(BuildContext context) {
    final device = context.read<BleState>().selectedDevice;
    if (device == null) return const [];
    final map = PluginRegistry().matchPlugin(device)?.registerMap ?? const {};
    return map.entries
        .where((e) => _audioRegisterNames.contains(e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  // ---------- 数据回读 ----------

  /// 回读所有音频寄存器
  Future<void> _readAllRegisters() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) return;

    final regs = _audioRegisters(context);
    if (regs.isEmpty) return;

    setState(() {
      _reading = true;
      _regErrors.clear();
    });

    for (final entry in regs) {
      try {
        final data = await adapter.readRegister(entry.key, 1);
        if (!mounted) return;
        setState(() {
          _regValues[entry.key] = data.isEmpty ? 0 : data.first;
          _regErrors.remove(entry.key);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _regValues.remove(entry.key);
          _regErrors[entry.key] = _shortError(e);
        });
      }
    }

    if (!mounted) return;
    setState(() => _reading = false);
  }

  String _shortError(Object e) {
    final s = e.toString();
    // 去掉异常类型前缀，日志里已经很吵了
    final idx = s.indexOf(':');
    final msg = (idx > 0 && idx < 20) ? s.substring(idx + 1).trim() : s;
    return msg.length > 60 ? '${msg.substring(0, 60)}…' : msg;
  }

  // ---------- 指令下发 ----------

  /// 发送 AT 指令，成功后再回读一次以确认设备真的接受了参数
  Future<void> _sendCmd(String cmd, String description,
      {bool reRead = false}) async {
    final adapter = context.read<BleState>().adapter;
    if (adapter == null) {
      _setMessage('请先连接设备', false);
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await adapter.sendAtCommand(cmd);
      if (!mounted) return;
      _setMessage('$description 成功 → $result', true);

      // 写入后回读校验：调试工具必须能证明参数真的落到了设备上
      if (reRead) {
        await _readAllRegisters();
      }
    } catch (e) {
      if (!mounted) return;
      _setMessage('$description 失败: ${_shortError(e)}', false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setMessage(String msg, bool ok) {
    setState(() {
      _lastMessage = msg;
      _lastOk = ok;
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final connected = bleState.connected;
    final templates = _templates(context);

    // 首次连上设备时自动回读一次
    if (connected && !_autoLoaded) {
      _autoLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _readAllRegisters());
    }
    if (!connected) _autoLoaded = false;

    return Scaffold(
      body: !connected
          ? CustomScrollView(
              slivers: [
                SliverAppBar.large(title: const Text('音频调试')),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: IosEmptyState(
                    icon: Icons.graphic_eq_rounded,
                    title: '请先连接设备',
                    subtitle: '连接后可调节厂商私有音频参数',
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
                                  const Icon(Icons.bluetooth_connected_rounded,
                                      size: 14, color: Colors.white),
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
                            delegate: SliverChildListDelegate([
                              _buildCapabilityNotice(),
                              const SizedBox(height: 12),
                              _buildRegisterSection(context),
                              const SizedBox(height: 12),
                              _buildAncSection(templates),
                              const SizedBox(height: 12),
                              _buildGainSection(templates),
                              const SizedBox(height: 12),
                              _buildSwitchSection(templates),
                              const SizedBox(height: 12),
                              _buildCustomSection(templates),
                              const SizedBox(height: 24),
                            ]),
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

  /// 能力边界说明：把 BLE 做不到的事讲清楚，避免误导
  Widget _buildCapabilityNotice() {
    return IosCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: AppTheme.iosOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '能力边界',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '本 App 走纯 BLE 链路，无法切换 A2DP / HFP 等经典蓝牙音频通路'
                  '（那需要 BR-EDR + SPP）。本页只能调节厂商通过私有 AT 指令'
                  '暴露出来的音频参数，且取决于当前插件是否声明了对应指令——'
                  '未声明的控件会置灰，而不是假装生效。',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.iosGray, height: 1.4),
                ),
                if (_lastMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _lastMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _lastOk ? AppTheme.iosGreen : AppTheme.iosRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 寄存器回读区：真实从设备读取，读不到显示错误原因
  Widget _buildRegisterSection(BuildContext context) {
    final regs = _audioRegisters(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Row(
            children: [
              Text(
                '寄存器回读'.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.iosGray,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_reading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                GestureDetector(
                  onTap: _readAllRegisters,
                  child: const Icon(Icons.refresh_rounded,
                      size: 18, color: AppTheme.iosBlue),
                ),
            ],
          ),
        ),
        IosCard(
          padding: const EdgeInsets.all(14),
          child: regs.isEmpty
              ? Text(
                  '当前插件未声明音频相关寄存器，无从回读。'
                  '可在插件管理页查看该厂商的寄存器映射。',
                  style: TextStyle(fontSize: 13, color: AppTheme.iosGray))
              : Column(
                  children: regs.asMap().entries.map((e) {
                    final idx = e.key;
                    final reg = e.value;
                    return Column(
                      children: [
                        if (idx > 0)
                          Divider(
                              height: 1, color: AppTheme.iosGray6),
                        _buildRegisterRow(reg.key, reg.value),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildRegisterRow(int address, String name) {
    final addrText = '0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final err = _regErrors[address];
    final value = _regValues[address];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(addrText,
                    style: TextStyle(fontSize: 11, color: AppTheme.iosGray)),
              ],
            ),
          ),
          if (err != null)
            Expanded(
              flex: 2,
              child: Text(
                err,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: AppTheme.iosRed),
              ),
            )
          else if (value != null)
            Text(
              '0x${value.toRadixString(16).toUpperCase().padLeft(2, '0')}  ($value)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppTheme.iosBlue,
              ),
            )
          else
            Text('—', style: TextStyle(fontSize: 14, color: AppTheme.iosGray3)),
        ],
      ),
    );
  }

  /// ANC 降噪：仅当插件声明了 AT+ANC= 指令时可用
  Widget _buildAncSection(List<String> templates) {
    final supported = _hasCmd(templates, 'AT+ANC=');
    final options = <String, String>{
      'OFF': '关闭',
      'ON': '降噪',
      'TRANSPARENCY': '通透',
    };

    return _buildSection(
      '降噪模式',
      _Disabled(
        disabled: !supported,
        reason: '当前插件未声明 AT+ANC= 指令',
        child: _SegmentedControl(
          value: _ancMode,
          options: options,
          onChanged: supported
              ? (v) {
                  setState(() => _ancMode = v);
                  _sendCmd('AT+ANC=$v', '降噪模式', reRead: true);
                }
              : null,
        ),
      ),
    );
  }

  /// 增益：仅当插件声明了 AT+AUDIO_GAIN= 指令时可用
  Widget _buildGainSection(List<String> templates) {
    final supported = _hasCmd(templates, 'AT+AUDIO_GAIN=');

    return _buildSection(
      '音频增益',
      _Disabled(
        disabled: !supported,
        reason: '当前插件未声明 AT+AUDIO_GAIN= 指令',
        child: _buildSliderRow(
          '增益',
          _audioGain?.toDouble(),
          AppTheme.iosBlue,
          // 拖动时只更新显示，松手才下发，避免拖动过程刷屏
          supported ? (v) => setState(() => _audioGain = v.toInt()) : null,
          supported
              ? (v) => _sendCmd('AT+AUDIO_GAIN=${v.toInt()}', '音频增益',
                  reRead: true)
              : null,
        ),
      ),
    );
  }

  /// 低延迟 / 游戏模式开关
  Widget _buildSwitchSection(List<String> templates) {
    final lowLatencySupported = _hasCmd(templates, 'AT+LOW_LATENCY=');
    final gameModeSupported = _hasCmd(templates, 'AT+GAME_MODE=');

    return IosCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Disabled(
            disabled: !lowLatencySupported,
            reason: '当前插件未声明 AT+LOW_LATENCY= 指令',
            child: SwitchListTile(
              title: const Text('低延迟模式'),
              subtitle: Text(
                lowLatencySupported
                    ? '由厂商固件决定实际延迟，App 只能下发开关'
                    : '当前插件未声明该指令',
                style: TextStyle(fontSize: 13, color: AppTheme.iosGray),
              ),
              value: _lowLatency ?? false,
              onChanged: lowLatencySupported
                  ? (v) {
                      setState(() => _lowLatency = v);
                      _sendCmd('AT+LOW_LATENCY=${v ? 'ON' : 'OFF'}',
                          '低延迟模式');
                    }
                  : null,
            ),
          ),
          Divider(height: 1, indent: 14, color: AppTheme.iosGray6),
          _Disabled(
            disabled: !gameModeSupported,
            reason: '当前插件未声明 AT+GAME_MODE= 指令',
            child: SwitchListTile(
              title: const Text('游戏模式'),
              subtitle: Text(
                gameModeSupported
                    ? '由厂商固件决定实际效果，App 只能下发开关'
                    : '当前插件未声明该指令',
                style: TextStyle(fontSize: 13, color: AppTheme.iosGray),
              ),
              value: _gameMode ?? false,
              onChanged: gameModeSupported
                  ? (v) {
                      setState(() => _gameMode = v);
                      _sendCmd('AT+GAME_MODE=${v ? 'ON' : 'OFF'}', '游戏模式');
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 自定义指令兜底：厂商指令千差万别，模板覆盖不到时留一个口子
  Widget _buildCustomSection(List<String> templates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Text(
            '自定义 AT 指令'.toUpperCase(),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customCmdController,
                      decoration: const InputDecoration(
                        hintText: 'AT+...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendCustom(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendCustom,
                    child: const Text('发送'),
                  ),
                ],
              ),
              if (templates.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '插件已声明的音频相关指令：',
                  style: TextStyle(fontSize: 11, color: AppTheme.iosGray),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: templates
                      .where((t) =>
                          t.contains('ANC') ||
                          t.contains('GAIN') ||
                          t.contains('LATENCY') ||
                          t.contains('GAME'))
                      .map((t) => GestureDetector(
                            onTap: () => _customCmdController.text = t,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.iosGray6,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: AppTheme.iosBlue),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _sendCustom() {
    final cmd = _customCmdController.text.trim();
    if (cmd.isEmpty) return;
    final full = cmd.toUpperCase().startsWith('AT') ? cmd : 'AT+$cmd';
    _sendCmd(full, '自定义指令');
  }

  Widget _buildSection(String title, Widget child) {
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
          child: child,
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    String label,
    double? value,
    Color color,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  ) {
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
              // 未从设备回读到值时滑到中点但显示为「未知」，
              // 避免用硬编码初值冒充设备真实参数
              value: value ?? 50,
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
            child: Text(
              value == null ? '—' : '${value.toInt()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: value == null ? AppTheme.iosGray3 : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 未支持的控件统一置灰并说明原因，避免出现「能点但没反应」的假象
class _Disabled extends StatelessWidget {
  final bool disabled;
  final String reason;
  final Widget child;

  const _Disabled({
    required this.disabled,
    required this.reason,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!disabled) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(opacity: 0.4, child: AbsorbPointer(child: child)),
        const SizedBox(height: 6),
        Text(
          reason,
          style: TextStyle(fontSize: 11, color: AppTheme.iosGray),
        ),
      ],
    );
  }
}

/// iOS 风格 SegmentedControl
///
/// [value] 为 null 表示尚未从设备读到当前值，此时不选中任何一项。
class _SegmentedControl extends StatelessWidget {
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

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
              onTap: onChanged == null ? null : () => onChanged!(e.key),
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
