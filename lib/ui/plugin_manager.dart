import 'package:flutter/material.dart';
import '../plugins/base_plugin.dart';
import '../plugins/qcc_ar_plugin.dart';
import '../plugins/bes_tws_plugin.dart';
import '../plugins/wq_bluetooth_plugin.dart';
import 'protocol_editor.dart';
import 'theme.dart';

/// ============================================================
/// 插件管理页面 — iOS 风格
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

  final _pluginColors = [
    AppTheme.iosPurple,
    AppTheme.iosBlue,
    AppTheme.iosTeal,
  ];

  final _pluginIcons = [
    Icons.visibility_rounded,
    Icons.headphones_rounded,
    Icons.watch_rounded,
  ];

  @override
  void initState() {
    super.initState();
    for (final p in _allPlugins) {
      _registry.register(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('插件管理'),
            actions: [
              IconButton(
                icon: const Icon(Icons.schema_rounded),
                tooltip: '协议编辑器',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProtocolEditorPage(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.upload_file_rounded),
                tooltip: '导入',
                onPressed: _importConfig,
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: _allPlugins.length,
              itemBuilder: (ctx, i) {
                final plugin = _allPlugins[i];
                // 按 vendorId 判断注册状态（页面持有的实例与注册中心内的不是同一对象）
                final isRegistered = _registry.plugins
                    .any((p) => p.vendorId == plugin.vendorId);
                return _PluginCard(
                  plugin: plugin,
                  isRegistered: isRegistered,
                  color: _pluginColors[i % _pluginColors.length],
                  icon: _pluginIcons[i % _pluginIcons.length],
                  onToggle: (v) {
                    setState(() {
                      if (v) {
                        _registry.register(plugin);
                      } else {
                        _registry.unregister(plugin);
                      }
                    });
                  },
                  onTap: () => _showPluginDetail(plugin),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 24),
          ),
        ],
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
            // Grabber
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.iosGray3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(plugin.name,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(plugin.description,
                style: TextStyle(fontSize: 14, color: AppTheme.iosGray)),
            const SizedBox(height: 20),
            const Text('AT 指令模板',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.iosGray)),
            const SizedBox(height: 8),
            ...plugin.atCommandTemplates.take(5).map(
                  (cmd) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                              color: AppTheme.iosBlue, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(cmd,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            if (plugin.atCommandTemplates.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('共 ${plugin.atCommandTemplates.length} 条',
                    style: TextStyle(fontSize: 12, color: AppTheme.iosGray)),
              ),
            const SizedBox(height: 16),
            const Text('OTA 配置',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.iosGray)),
            const SizedBox(height: 8),
            Row(
              children: [
                _otaTag('分片 ${plugin.otaChunkSize}B', AppTheme.iosBlue),
                const SizedBox(width: 8),
                _otaTag(
                    plugin.otaSupportResume ? '断点续传' : '无断点续传',
                    plugin.otaSupportResume
                        ? AppTheme.iosGreen
                        : AppTheme.iosGray),
                const SizedBox(width: 8),
                _otaTag(
                    plugin.otaSupportDualChannel ? '双通道' : '单通道',
                    plugin.otaSupportDualChannel
                        ? AppTheme.iosGreen
                        : AppTheme.iosGray),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _otaTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  void _importConfig() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('协议配置导入功能待实现')),
    );
  }
}

/// 插件卡片
class _PluginCard extends StatelessWidget {
  final BaseChipPlugin plugin;
  final bool isRegistered;
  final Color color;
  final IconData icon;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _PluginCard({
    required this.plugin,
    required this.isRegistered,
    required this.color,
    required this.icon,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plugin.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(plugin.description,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.iosGray),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // iOS style toggle
            GestureDetector(
              onTap: () => onToggle(!isRegistered),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 26,
                decoration: BoxDecoration(
                  color: isRegistered ? AppTheme.iosGreen : AppTheme.iosGray4,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: isRegistered
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
