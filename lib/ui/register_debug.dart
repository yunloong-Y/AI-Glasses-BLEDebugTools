import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../plugins/base_plugin.dart';

/// ============================================================
/// 寄存器 & AT 指令调试面板
/// 寄存器地址映射表、批量读写、AT 指令快捷发送
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

  /// 寄存器映射表（从匹配的插件获取）
  Map<int, String> _registerMap = {};

  /// AT 历史记录
  final List<_AtHistoryItem> _atHistory = [];

  /// AT 响应监听
  String? _lastAtResponse;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRegisterMap();
  }

  void _loadRegisterMap() {
    // 从已注册插件中获取寄存器映射
    final bleState = context.read<BleState>();
    final reg = PluginRegistry();
    final device = bleState.selectedDevice;

    if (device != null) {
      final plugin = reg.matchPlugin(device);
      if (plugin != null) {
        setState(() {
          _registerMap = plugin.registerMap;
        });
        return;
      }
    }

    // 没有匹配到特定插件时，合并所有已注册插件的映射表
    final merged = <int, String>{};
    for (final p in reg.plugins) {
      merged.addAll(p.registerMap);
    }
    setState(() {
      _registerMap = merged;
    });
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
      _showSnack('请先连接设备', Colors.red);
      return;
    }

    final addrStr = _regAddrController.text.trim();
    if (addrStr.isEmpty) {
      _showSnack('请输入寄存器地址', Colors.orange);
      return;
    }

    final addr = _parseAddress(addrStr);
    if (addr == null) {
      _showSnack('地址格式无效，请使用 0x 或十进制', Colors.red);
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
      setState(() {
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: 'ERROR: $e',
          type: 'ERR',
        ));
      });
    }
  }

  Future<void> _writeRegister() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null) {
      _showSnack('请先连接设备', Colors.red);
      return;
    }

    final addrStr = _regAddrController.text.trim();
    final valStr = _regValueController.text.trim();
    if (addrStr.isEmpty || valStr.isEmpty) {
      _showSnack('请输入地址和写入值', Colors.orange);
      return;
    }

    final addr = _parseAddress(addrStr);
    if (addr == null) {
      _showSnack('地址格式无效', Colors.red);
      return;
    }

    // 解析 hex 值
    final hex = valStr.replaceAll(' ', '');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      try {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      } catch (_) {
        _showSnack('HEX 格式无效', Colors.red);
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
      setState(() {
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: 'OK',
          type: 'REG',
        ));
      });
    } catch (e) {
      setState(() {
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: 'ERROR: $e',
          type: 'ERR',
        ));
      });
    }
  }

  Future<void> _sendAtCommand() async {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    final cmd = _atInputController.text.trim();
    if (cmd.isEmpty) return;

    if (adapter == null) {
      _showSnack('请先连接设备', Colors.red);
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
      setState(() {
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: result,
          type: 'AT',
        ));
      });
    } catch (e) {
      setState(() {
        _atHistory.add(_AtHistoryItem(
          direction: 'RX',
          text: 'ERROR: $e',
          type: 'ERR',
        ));
      });
    }
  }

  /// 快捷发送 AT 指令（从模板列表点击）
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

    // 连接状态变化时重新加载寄存器映射
    if (connected && _registerMap.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRegisterMap());
    }

    // 获取当前设备的 AT 模板
    final plugin = bleState.selectedDevice != null
        ? PluginRegistry().matchPlugin(bleState.selectedDevice!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('寄存器 / AT 调试'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.memory), text: '寄存器'),
            Tab(icon: Icon(Icons.terminal), text: 'AT 指令'),
          ],
        ),
      ),
      body: !connected
          ? _buildNotConnected()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRegisterTab(),
                _buildAtTab(plugin?.atCommandTemplates ?? []),
              ],
            ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.usb_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('请先连接设备',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          Text('连接后在寄存器和 AT 标签页中可发送指令',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRegisterTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 地址输入
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _regAddrController,
                  decoration: const InputDecoration(
                    labelText: '寄存器地址 (0x...)',
                    hintText: '例如 0x10',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _regValueController,
                  decoration: const InputDecoration(
                    labelText: '值 (hex)',
                    hintText: '例如 01 FF',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _readRegister,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('读取'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _writeRegister,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('写入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 寄存器映射表
          Expanded(
            child: _registerMap.isEmpty
                ? Center(
                    child: Text('无寄存器映射',
                        style: TextStyle(color: Colors.grey.shade400)),
                  )
                : ListView.builder(
                    itemCount: _registerMap.length,
                    itemBuilder: (ctx, i) {
                      final entry = _registerMap.entries.elementAt(i);
                      return ListTile(
                        dense: true,
                        leading: Text(
                          '0x${entry.key.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                        title: Text(entry.value),
                        onTap: () {
                          _regAddrController.text =
                              '0x${entry.key.toRadixString(16)}';
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtTab(List<String> templates) {
    return Column(
      children: [
        // AT 模板快捷按钮
        if (templates.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: templates.map((cmd) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ActionChip(
                    label: Text(cmd, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    onPressed: () => _sendQuickAt(cmd),
                  ),
                );
              }).toList(),
            ),
          ),
        // AT 历史
        Expanded(
          child: _atHistory.isEmpty
              ? Center(
                  child: Text('无 AT 指令历史',
                      style: TextStyle(color: Colors.grey.shade400)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _atHistory.length,
                  itemBuilder: (ctx, i) {
                    final item = _atHistory[i];
                    final color = item.type == 'ERR'
                        ? Colors.red
                        : item.direction == 'TX'
                            ? Colors.blue
                            : Colors.green;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Icon(
                              item.direction == 'TX'
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 14,
                              color: color,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.text,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: item.type == 'ERR' ? Colors.red : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // AT 输入框
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Text('AT+', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _atInputController,
                  decoration: const InputDecoration(
                    hintText: '输入指令...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onSubmitted: (_) => _sendAtCommand(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendAtCommand,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// AT 历史记录项
class _AtHistoryItem {
  final String direction; // TX / RX
  final String text;
  final String type; // AT / REG / ERR

  _AtHistoryItem({
    required this.direction,
    required this.text,
    required this.type,
  });
}
