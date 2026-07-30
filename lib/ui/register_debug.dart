import 'package:flutter/material.dart';

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

  final Map<int, String> _registerMap = {};
  final List<String> _atHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _atInputController.dispose();
    _regAddrController.dispose();
    _regValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: TabBarView(
        controller: _tabController,
        children: [
          // 寄存器面板
          _buildRegisterTab(),
          // AT 指令面板
          _buildAtTab(),
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
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _regValueController,
                  decoration: const InputDecoration(
                    labelText: '写入值 (hex)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
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
                        leading: Text('0x${entry.key.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
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

  Widget _buildAtTab() {
    return Column(
      children: [
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
                    return Text(
                      _atHistory[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
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

  void _readRegister() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先连接设备')),
    );
  }

  void _writeRegister() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先连接设备')),
    );
  }

  void _sendAtCommand() {
    final cmd = _atInputController.text.trim();
    if (cmd.isEmpty) return;
    setState(() {
      _atHistory.add('>> AT+$cmd');
      _atInputController.clear();
    });
    // TODO: 发送 AT 指令
  }
}
