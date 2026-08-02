import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../main.dart';

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

  @override
  void initState() {
    super.initState();
    // 启动时请求蓝牙权限
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> _toggleScan() async {
    final bleState = context.read<BleState>();

    if (bleState.scanning) {
      await bleState.stopScan();
    } else {
      await _requestPermissions();
      await bleState.startScan();
    }
  }

  Future<void> _onDeviceTap(DeviceInfo device) async {
    final bleState = context.read<BleState>();

    // 如果已连接此设备，则断开
    if (bleState.connected && bleState.selectedDevice?.mac == device.mac) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('断开连接'),
          content: Text('确定断开 ${device.name}？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('断开')),
          ],
        ),
      );
      if (confirmed == true) {
        await bleState.disconnect();
      }
      return;
    }

    // 否则连接设备
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在连接...'),
          ],
        ),
      ),
    );

    final ok = await bleState.connectDevice(device);

    if (!mounted) return;
    Navigator.pop(context); // 关闭 loading

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已连接 ${device.name}' : '连接失败'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final devices = bleState.scanResults;
    final scanning = bleState.scanning;
    final connectedMac = bleState.selectedDevice?.mac;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备扫描'),
        actions: [
          // 连接状态指示
          if (bleState.connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.bluetooth_connected,
                    size: 18, color: Colors.white),
                label: Text(
                  bleState.selectedDevice?.name ?? 'Connected',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade700,
                labelStyle: const TextStyle(color: Colors.white),
                deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                onDeleted: () => bleState.disconnect(),
              ),
            ),
          IconButton(
            icon: Icon(scanning ? Icons.stop : Icons.search),
            onPressed: _toggleScan,
          ),
        ],
      ),
      body: devices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (scanning) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                  ] else ...[
                    Icon(Icons.bluetooth_disabled,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    scanning ? '正在搜索设备...' : '点击右下角按钮开始扫描',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (ctx, i) {
                final dev = devices[i];
                final isConnected = dev.mac == connectedMac;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        Icon(
                          _vendorIcons[dev.vendorId],
                          color: _vendorColors[dev.vendorId],
                          size: 32,
                        ),
                        if (isConnected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      dev.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green.shade700 : null,
                      ),
                    ),
                    subtitle: Text(
                      '${dev.mac}  |  ${dev.vendorId.name}'
                      '${dev.deviceType != DeviceType.unknown ? "  |  ${dev.deviceType.name}" : ""}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${dev.rssi} dBm',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(
                          '${_rssiQuality(dev.rssi)}',
                          style: TextStyle(
                              fontSize: 10, color: _rssiColor(dev.rssi)),
                        ),
                      ],
                    ),
                    onTap: () => _onDeviceTap(dev),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan',
        onPressed: _toggleScan,
        icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(scanning ? '停止扫描' : '扫描设备'),
      ),
    );
  }

  String _rssiQuality(int rssi) {
    if (rssi >= -50) return '极佳';
    if (rssi >= -70) return '良好';
    if (rssi >= -90) return '一般';
    return '较弱';
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.lightGreen;
    if (rssi >= -90) return Colors.orange;
    return Colors.red;
  }
}
