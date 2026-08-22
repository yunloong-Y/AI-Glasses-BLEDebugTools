/// AI-Glasses-BLEDebugTools Protocol Editor
///
/// 协议编辑器页面 - 支持：
///   1. 可视化查看已加载的协议定义
///   2. 从 JSON 文件导入自定义协议
///   3. 导出协议为 JSON
///   4. 协议校验与对比

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../core/protocol_parser.dart';
import '../core/protocol_registry.dart';
import 'dart:convert';
import 'dart:io';

class ProtocolEditorPage extends StatefulWidget {
  const ProtocolEditorPage({super.key});

  @override
  State<ProtocolEditorPage> createState() => _ProtocolEditorPageState();
}

class _ProtocolEditorPageState extends State<ProtocolEditorPage> {
  final ProtocolRegistry _registry = ProtocolRegistry();
  String? _selectedProtocolId;
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final protocols = _registry.all;
    final selectedProtocol = _registry.get(_selectedProtocolId ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('协议编辑器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: '导入协议 JSON',
            onPressed: _importProtocol,
          ),
          if (selectedProtocol != null)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '导出协议 JSON',
              onPressed: () => _exportProtocol(selectedProtocol),
            ),
        ],
      ),
      body: Row(
        children: [
          // 左侧协议列表
          SizedBox(
            width: 200,
            child: _buildProtocolList(protocols),
          ),
          const VerticalDivider(width: 1),
          // 右侧协议详情
          Expanded(
            child: selectedProtocol != null
                ? _buildProtocolDetail(selectedProtocol)
                : const Center(child: Text('选择左侧协议查看详情')),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolList(List<ProtocolDef> protocols) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Text(
            '已加载协议',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: protocols.length,
            itemBuilder: (context, index) {
              final p = protocols[index];
              final isSelected = p.id == _selectedProtocolId;
              return ListTile(
                selected: isSelected,
                dense: true,
                title: Text(p.name, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  '${p.vendor.vendorName} · v${p.vendor.protocolVersion}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
                onTap: () => setState(() => _selectedProtocolId = p.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProtocolDetail(ProtocolDef protocol) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 协议头部信息
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(protocol.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: protocol.vendor.vendorName),
                  const TextSpan(text: ' | '),
                  TextSpan(
                      text: protocol.vendor.chipSeries,
                      style: TextStyle(color: Colors.grey[600])),
                  const TextSpan(text: ' | v'),
                  TextSpan(
                      text: protocol.vendor.protocolVersion,
                      style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500)),
                ]),
                style: const TextStyle(fontSize: 12),
              ),
              if (protocol.notes != null) ...[
                const SizedBox(height: 8),
                Text(protocol.notes!,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ],
          ),
        ),
        // Tab 切换
        _buildTabBar(),
        // 内容区
        Expanded(
          child: _buildTabContent(protocol),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    const tabs = ['GATT 服务', '帧格式', '命令集', '寄存器', 'AT命令'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = _selectedTab == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? Colors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.blue : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent(ProtocolDef protocol) {
    switch (_selectedTab) {
      case 0:
        return _buildGattTab(protocol);
      case 1:
        return _buildFrameTab(protocol);
      case 2:
        return _buildCommandTab(protocol);
      case 3:
        return _buildRegisterTab(protocol);
      case 4:
        return _buildAtCommandTab(protocol);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGattTab(ProtocolDef protocol) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: protocol.services.length,
      itemBuilder: (context, index) {
        final svc = protocol.services[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(svc.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(_shortUuid(svc.uuid),
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            children: [
              if (svc.description != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(svc.description!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ),
              ...svc.characteristics.map((ch) => ListTile(
                    dense: true,
                    leading: _directionIcon(ch.direction),
                    title: Text(ch.name, style: const TextStyle(fontSize: 12)),
                    subtitle: Text(_shortUuid(ch.uuid),
                        style: TextStyle(
                            fontSize: 10, fontFamily: 'monospace')),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFrameTab(ProtocolDef protocol) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: protocol.frameFormats.length,
      itemBuilder: (context, index) {
        final fmt = protocol.frameFormats[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title:
                Text(fmt.name, style: const TextStyle(fontFamily: 'monospace')),
            subtitle: Text(fmt.description ?? '',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            children: [
              // 帧头信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (fmt.magicByte != null)
                      _buildChip(
                          '魔术字: 0x${fmt.magicByte!.toRadixString(16).toUpperCase().padLeft(2, '0')}'),
                    if (fmt.magicBytes != null)
                      _buildChip('魔术字[${fmt.magicBytes!.length}B]'),
                    if (fmt.checksumType != ChecksumType.none)
                      _buildChip('校验: ${fmt.checksumType.name}'),
                  ],
                ),
              ),
              // 字段列表
              ...fmt.fields.map((field) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.data_object, size: 16),
                    title: Text('${field.name}  ',
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace')),
                    subtitle: Text(
                      '${field.encoding.name} | ${field.byteLength > 0 ? "${field.byteLength}B" : "var"}${field.description != null ? " | ${field.description}" : ""}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommandTab(ProtocolDef protocol) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: protocol.commandGroups.length,
      itemBuilder: (context, index) {
        final group = protocol.commandGroups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(group.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text('${group.commands.length} 条命令',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            children: group.commands.map((cmd) {
              return ListTile(
                dense: true,
                leading: _directionIcon(cmd.direction,
                    size: 14),
                title: Text(cmd.name,
                    style: const TextStyle(
                        fontSize: 11, fontFamily: 'monospace')),
                subtitle: Text(
                  '0x${cmd.opCode.toRadixString(16).toUpperCase().padLeft(4, '0')}${cmd.description != null ? " | ${cmd.description}" : ""}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRegisterTab(ProtocolDef protocol) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: protocol.registers.length,
      itemBuilder: (context, index) {
        final reg = protocol.registers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            leading: _buildChip(
                '0x${reg.address.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            title: Text(reg.name,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace')),
            subtitle: Text(
              '${reg.size}B | ${reg.access.toUpperCase()}${reg.description != null ? " | ${reg.description}" : ""}',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAtCommandTab(ProtocolDef protocol) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: protocol.atCommands.length,
      itemBuilder: (context, index) {
        final at = protocol.atCommands[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            title: Text(at.command,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace')),
            subtitle: Text(at.description ?? '',
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ),
        );
      },
    );
  }

  Widget _buildChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _directionIcon(String direction, {double size = 16}) {
    switch (direction) {
      case 'send':
      case 'write':
        return Icon(Icons.arrow_upward, size: size, color: Colors.orange);
      case 'receive':
      case 'notify':
      case 'read':
        return Icon(Icons.arrow_downward, size: size, color: Colors.green);
      default:
        return Icon(Icons.swap_vert, size: size, color: Colors.blue);
    }
  }

  String _shortUuid(String uuid) {
    // 提取 UUID 后 4 位作为短标识
    final parts = uuid.split('-');
    if (parts.length >= 5) {
      return '...${parts[4].substring(0, 4).toUpperCase()}';
    }
    // 尝试提取前8位
    final clean = uuid.replaceAll('-', '');
    if (clean.length >= 8) {
      return '${clean.substring(0, 8).toUpperCase()}...';
    }
    return uuid.toUpperCase();
  }

  Future<void> _importProtocol() async {
    // 实际使用时，这里调用 file_picker 或系统文件选择器
    // 现在模拟一个简单的导入对话框
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入协议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('粘贴协议 JSON 内容或选择文件路径：',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '输入 JSON 或 /path/to/protocol.json',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        String jsonStr;
        if (result.trimLeft().startsWith('{')) {
          jsonStr = result;
        } else {
          // 从文件读取
          final file = File(result);
          jsonStr = await file.readAsString();
        }

        final protocol = _registry.loadFromJson(jsonStr);
        setState(() {
          _selectedProtocolId = protocol.id;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('协议 "${protocol.name}" 加载成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('协议加载失败: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _exportProtocol(ProtocolDef protocol) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(protocol.toJson());
    // 实际使用时调用 share_plus 或保存到文件
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导出 ${protocol.name}'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
