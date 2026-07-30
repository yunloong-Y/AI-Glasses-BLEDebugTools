import 'package:flutter/material.dart';
import '../adapter/base_bluetooth.dart';

/// ============================================================
/// 设备扫描页
/// 区分 BLE/BR-EDR, 自动识别芯片方案
/// ============================================================

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _scanning = false;
  final List<DeviceInfo> _devices = [];

  final _vendorColors = {
    VendorId.bes: Colors.blue,
    VendorId.qcc: Colors.purple,
    VendorId.wq: Colors.teal,
    VendorId.std: Colors.grey,
    VendorId.unknown: Colors.orange,
  };

  final _vendorIcons = {
    VendorId.bes: Icons.headphones,
    VendorId.qcc: Icons.visibility,
    VendorId.wq: Icons.watch,
    VendorId.std: Icons.bluetooth,
    VendorId.unknown: Icons.help_outline,
  };

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
    });
    // TODO: 接入 DeviceManager 扫描
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('扫描功能待接入 flutter_blue_plus')),
    );
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备扫描'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.stop : Icons.search),
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: _devices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(_scanning ? '正在搜索设备...' : '点击右上角开始扫描',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (ctx, i) {
                final dev = _devices[i];
                return ListTile(
                  leading: Icon(
                    _vendorIcons[dev.vendorId],
                    color: _vendorColors[dev.vendorId],
                  ),
                  title: Text(dev.name),
                  subtitle: Text('${dev.mac}  |  ${dev.vendorId.name}'
                      '${dev.deviceType != DeviceType.unknown ? "  |  ${dev.deviceType.name}" : ""}'),
                  trailing: Text('${dev.rssi} dBm'),
                  onTap: () {
                    // TODO: 连接设备
                  },
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: _scanning ? null : _startScan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('扫描设备'),
          ),
        ],
      ),
    );
  }
}
