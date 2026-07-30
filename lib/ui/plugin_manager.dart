import 'package:flutter/material.dart';
import '../plugins/base_plugin.dart';
import '../plugins/qcc_ar_plugin.dart';
import '../plugins/bes_tws_plugin.dart';
import '../plugins/wq_bluetooth_plugin.dart';

/// ============================================================
/// 插件管理页面
/// 动态加载/卸载芯片适配插件，导入自定义协议配置
/// ============================================================

class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  final _registry = PluginRegistry();
  final _allPlugins = <BaseChipPlugin>[
    QccArPlugin(),
    BesTwsPlugin(),
    WqBluetoothPlugin(),
  ];

  @override
  void initState() {
    super.initState();
    // 自动注册所有插件
    for (final p in _allPlugins) {
      _registry.register(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: '导入协议配置',
            onPressed: _importConfig,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _allPlugins.length,
        itemBuilder: (ctx, i) {
          final plugin = _allPlugins[i];
          final isRegistered = _registry.plugins.contains(plugin);
          return Card(
            child: ListTile(
              leading: Icon(
                isRegistered ? Icons.check_circle : Icons.circle_outlined,
                color: isRegistered ? Colors.green : Colors.grey,
              ),
              title: Text(plugin.name),
              subtitle: Text(plugin.description),
              trailing: Switch(
                value: isRegistered,
                onChanged: (v) {
                  setState(() {
                    if (v) {
                      _registry.register(plugin);
                    } else {
                      _registry.unregister(plugin);
                    }
                  });
                },
              ),
              onTap: () => _showPluginDetail(plugin),
            ),
          );
        },
      ),
    );
  }

  void _showPluginDetail(BaseChipPlugin plugin) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plugin.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(plugin.description),
            const SizedBox(height: 16),
            const Text('AT 指令模板:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...plugin.atCommandTemplates.take(5).map(
                  (cmd) => Text('• $cmd',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
            if (plugin.atCommandTemplates.length > 5)
              Text('... 共 ${plugin.atCommandTemplates.length} 条'),
            const SizedBox(height: 16),
            const Text('寄存器映射:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...plugin.registerMap.entries.take(5).map(
                  (e) => Text(
                      '• 0x${e.key.toRadixString(16).toUpperCase().padLeft(4, '0')} = ${e.value}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
            if (plugin.registerMap.length > 5)
              Text('... 共 ${plugin.registerMap.length} 个'),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('OTA 分片: '),
                Text('${plugin.otaChunkSize} B'),
                const SizedBox(width: 16),
                const Text('断点续传: '),
                Text(plugin.otaSupportResume ? '✅' : '❌'),
                const SizedBox(width: 16),
                const Text('双通道: '),
                Text(plugin.otaSupportDualChannel ? '✅' : '❌'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _importConfig() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('协议配置导入功能待实现')),
    );
  }
}
