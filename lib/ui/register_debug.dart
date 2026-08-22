import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../plugins/base_plugin.dart';
import 'theme.dart';

/// ============================================================
/// 寄存器 & AT 指令调试面板 — iOS 风格
/// ============================================================

class RegisterDebugPage extends StatefulWidget {
  const RegisterDebugPage({super.key});

  @override
  State<RegisterDebugPage> createState() => _RegisterDebugPageState();
}

class _RegisterDebugPageState extends State<RegisterDebugPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _atInputController = TextEditingController();
  final _regAddrController = TextEditingController();
  final _regValueController = TextEditingController();
  Map<int, String> _registerMap = {};
  final List<_AtHistoryItem> _atHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRegisterMap();
  }

  void _loadRegisterMap() {
    final bleState = context.read<BleState>();
    final reg = PluginRegistry();
    final device = bleState.selectedDevice;

    if (device != null) {
      final plugin = reg.matchPlugin(device);
      if (plugin != null) {
        setState(() => _registerMap = plugin.registerMap);
        return;
      }
    }

    final merged = <int, String>{};
    for (final p in reg.plugins) {
      merged.addAll(p.registerMap);
    }
    setState(() => _registerMap = merged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _atInputController.dispose();
    _regAddrController.dispose();
    _regValueController.dispose();
    super.dispose();
  }

  Future<void> _readRegister() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _showSnack('请先连接设备', AppTheme.iosRed);
      return;
    }

    final addrStr = _regAddrController.text.trim();
    if (addrStr.isEmpty) {
      _showSnack('请输入寄存器地址', AppTheme.iosOrange);
      return;
    }

    final addr = _parseAddress(addrStr);
    if (addr == null) {
      _showSnack('地址格式无效', AppTheme.iosRed);
      return;
    }

    setState(() => _atHistory.add(_AtHistoryItem(
      direction: 'TX',
      text: 'READ 0x${addr.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      type: 'REG',
    )));

    try {
      final data = await adapter.readRegister(addr, 1);
      final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      setState(() {
        _regValueController.text = hex;
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: '0x${addr.toRadixString(16).toUpperCase().padLeft(4, '0')} = $hex',
          type: 'REG',
        ));
      });
    } catch (e) {
      setState(() => _atHistory.add(_AtHistoryItem(
        direction: 'RX',
        text: 'ERROR: $e',
        type: 'ERR',
      )));
    }
  }

  Future<void> _writeRegister() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _showSnack('请先连接设备', AppTheme.iosRed);
      return;
    }

    final addrStr = _regAddrController.text.trim();
    final valStr = _regValueController.text.trim();
    if (addrStr.isEmpty || valStr.isEmpty) {
      _showSnack('请输入地址和写入值', AppTheme.iosOrange);
      return;
    }

    final addr = _parseAddress(addrStr);
    if (addr == null) {
      _showSnack('地址格式无效', AppTheme.iosRed);
      return;
    }

    final hex = valStr.replaceAll(' ', '');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      try {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      } catch (_) {
        _showSnack('HEX 格式无效', AppTheme.iosRed);
        return;
      }
    }

    setState(() => _atHistory.add(_AtHistoryItem(
      direction: 'TX',
      text: 'WRITE 0x${addr.toRadixString(16).toUpperCase().padLeft(4, '0')} <- $valStr',
      type: 'REG',
    )));

    try {
      await adapter.writeRegister(addr, Uint8List.fromList(bytes));
      setState(() => _atHistory.add(_AtHistoryItem(
        direction: 'RX',
        text: 'OK',
        type: 'REG',
      )));
    } catch (e) {
      setState(() => _atHistory.add(_AtHistoryItem(
        direction: 'RX',
        text: 'ERROR: $e',
        type: 'ERR',
      )));
    }
  }

  Future<void> _sendAtCommand() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    final cmd = _atInputController.text.trim();
    if (cmd.isEmpty) return;

    if (adapter == null) {
      _showSnack('请先连接设备', AppTheme.iosRed);
      return;
    }

    final fullCmd = cmd.startsWith('AT') ? cmd : 'AT+$cmd';

    setState(() {
      _atHistory.add(_AtHistoryItem(
        direction: 'TX',
        text: fullCmd,
        type: 'AT',
      ));
      _atInputController.clear();
    });

    try {
      final result = await adapter.sendAtCommand(fullCmd);
      setState(() => _atHistory.add(_AtHistoryItem(
        direction: 'RX',
        text: result,
        type: 'AT',
      )));
    } catch (e) {
      setState(() => _atHistory.add(_AtHistoryItem(
        direction: 'RX',
        text: 'ERROR: $e',
        type: 'ERR',
      )));
    }
  }

  Future<void> _sendQuickAt(String template) async {
    _atInputController.text = template;
    await _sendAtCommand();
  }

  int? _parseAddress(String s) {
    s = s.trim();
    if (s.toLowerCase().startsWith('0x')) {
      return int.tryParse(s.substring(2), radix: 16);
    }
    return int.tryParse(s);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final connected = bleState.connected;

    if (connected && _registerMap.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRegisterMap());
    }

    final plugin = bleState.selectedDevice != null
        ? PluginRegistry().matchPlugin(bleState.selectedDevice!)
        : null;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, bottom: 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '寄存器 / AT 调试',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Cupertino style segmented control
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.iosGray6,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                _buildTabSegment(0, Icons.memory_rounded, '寄存器'),
                _buildTabSegment(1, Icons.terminal_rounded, 'AT 指令'),
              ],
            ),
          ),
          Expanded(
            child: !connected
                ? IosEmptyState(
                    icon: Icons.usb_off_rounded,
                    title: '请先连接设备',
                    subtitle: '连接后可发送寄存器和 AT 指令',
                  )
                : AnimatedBuilder(
                    animation: _tabController,
                    builder: (ctx, _) {
                      if (_tabController.index == 0) {
                        return _buildRegisterTab();
                      }
                      return _buildAtTab(plugin?.atCommandTemplates ?? []);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSegment(int index, IconData icon, String label) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
          setState(() {});
        },
        child: Container(
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? AppTheme.iosBlue : AppTheme.iosGray),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTheme.iosBlue : AppTheme.iosGray,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Input card
        IosCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regAddrController,
                      decoration: const InputDecoration(
                        labelText: '地址',
                        hintText: '0x10',
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _regValueController,
                      decoration: const InputDecoration(
                        labelText: '值 (hex)',
                        hintText: '01 FF',
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _readRegister,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('读取'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _writeRegister,
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: const Text('写入'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.iosOrange),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IosSectionHeader(title: '寄存器映射表'),
        if (_registerMap.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text('无寄存器映射',
                  style: TextStyle(color: AppTheme.iosGray)),
            ),
          )
        else
          IosCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: _registerMap.entries.map((entry) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.iosBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '0x${entry.key.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.iosBlue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(entry.value,
                            style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAtTab(List<String> templates) {
    return Column(
      children: [
        // Template shortcuts
        if (templates.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: templates.map((cmd) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _sendQuickAt(cmd),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.iosBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.iosBlue.withOpacity(0.2)),
                      ),
                      child: Center(
                        child: Text(cmd,
                            style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: AppTheme.iosBlue,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        // History
        Expanded(
          child: _atHistory.isEmpty
              ? IosEmptyState(
                  icon: Icons.terminal_rounded,
                  title: '无指令历史',
                  subtitle: '发送的指令将显示在此处',
                )
              : Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _atHistory.length,
                    itemBuilder: (ctx, i) {
                      final item = _atHistory[i];
                      final color = item.type == 'ERR'
                          ? AppTheme.iosRed
                          : item.direction == 'TX'
                              ? AppTheme.iosBlue
                              : AppTheme.iosGreen;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: AppTheme.iosGray6, width: 0.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                item.direction == 'TX'
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 14,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.text,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: item.type == 'ERR'
                                      ? AppTheme.iosRed
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
        // Input bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AT+',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.iosBlue,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _atInputController,
                  decoration: const InputDecoration(
                    hintText: '输入指令...',
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  onSubmitted: (_) => _sendAtCommand(),
                ),
              ),
              GestureDetector(
                onTap: _sendAtCommand,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.iosBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AtHistoryItem {
  final String direction;
  final String text;
  final String type;

  _AtHistoryItem({
    required this.direction,
    required this.text,
    required this.type,
  });
}
