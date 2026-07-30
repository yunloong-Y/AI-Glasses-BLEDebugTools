import 'package:flutter/material.dart';
import '../adapter/base_bluetooth.dart';

/// ============================================================
/// GATT 服务树面板
/// 自动解析 Service/Characteristic, 支持读写/通知
/// ============================================================

class GattView extends StatefulWidget {
  const GattView({super.key});

  @override
  State<GattView> createState() => _GattViewState();
}

class _GattViewState extends State<GattView> {
  final List<GattService> _services = [];
  final _expandedServices = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GATT 服务树'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // TODO: 刷新 GATT 服务
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先连接设备')),
              );
            },
          ),
        ],
      ),
      body: _services.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_tree,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('未发现服务',
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text('请先在扫描页连接设备',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _services.length,
              itemBuilder: (ctx, i) {
                final svc = _services[i];
                final expanded = _expandedServices.contains(svc.uuid);
                return ExpansionTile(
                  title: Text(svc.displayName ?? svc.uuid),
                  subtitle: Text('${svc.characteristics.length} characteristics'),
                  initiallyExpanded: expanded,
                  onExpansionChanged: (v) {
                    setState(() {
                      if (v) {
                        _expandedServices.add(svc.uuid);
                      } else {
                        _expandedServices.remove(svc.uuid);
                      }
                    });
                  },
                  children: svc.characteristics.map((ch) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        ch.properties.contains('notify')
                            ? Icons.notifications
                            : ch.properties.contains('write')
                                ? Icons.edit
                                : Icons.read_more,
                        size: 20,
                      ),
                      title: Text(ch.displayName ?? ch.uuid,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(ch.properties.join(', '),
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        ch.lastValue != null
                            ? '${ch.lastValue!.length} bytes'
                            : '--',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        // TODO: 打开特征值详情面板
                      },
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
