import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../main.dart';
import 'theme.dart';

/// ============================================================
/// 设备扫描页 — iOS 风格
/// ============================================================

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _vendorColors = {
    VendorId.bes: AppTheme.iosBlue,
    VendorId.qcc: AppTheme.iosPurple,
    VendorId.wq: AppTheme.iosTeal,
    VendorId.std: AppTheme.iosGray,
    VendorId.unknown: AppTheme.iosOrange,
  };

  final _vendorIcons = {
    VendorId.bes: Icons.headphones_rounded,
    VendorId.qcc: Icons.visibility_rounded,
    VendorId.wq: Icons.watch_rounded,
    VendorId.std: Icons.bluetooth_rounded,
    VendorId.unknown: Icons.help_outline_rounded,
  };

  @override
  void initState() {
    super.initState();
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

    if (bleState.connected && bleState.selectedDevice?.mac == device.mac) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('断开连接'),
          content: Text('确定断开 ${device.name}？'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('断开'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await bleState.disconnect();
      }
      return;
    }

    showCupertinoModalPopup(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: CupertinoAlertDialog(
          content: Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text('正在连接 ${device.name}...')),
            ],
          ),
        ),
      ),
    );

    final ok = await bleState.connectDevice(device);
    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已连接 ${device.name}' : '连接失败'),
        backgroundColor: ok ? AppTheme.iosGreen : AppTheme.iosRed,
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
      body: CustomScrollView(
        slivers: [
          // Large title AppBar
          SliverAppBar.large(
            title: const Text('设备扫描'),
            actions: [
              if (bleState.connected)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.iosGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bluetooth_connected_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          bleState.selectedDevice?.name ?? '已连接',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => bleState.disconnect(),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              IconButton(
                icon: Icon(scanning
                    ? Icons.stop_circle_rounded
                    : Icons.radar_rounded),
                onPressed: _toggleScan,
              ),
            ],
          ),
          // Content
          if (devices.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: scanning
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CupertinoActivityIndicator(radius: 16),
                          const SizedBox(height: 16),
                          Text('正在搜索设备...',
                              style: TextStyle(
                                  color: AppTheme.iosGray, fontSize: 15)),
                        ],
                      ),
                    )
                  : IosEmptyState(
                      icon: Icons.bluetooth_disabled_rounded,
                      title: '暂无设备',
                      subtitle: '点击下方按钮开始扫描 BLE 设备',
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final dev = devices[i];
                    final isConnected = dev.mac == connectedMac;
                    return _DeviceCard(
                      device: dev,
                      isConnected: isConnected,
                      vendorColor: _vendorColors[dev.vendorId]!,
                      vendorIcon: _vendorIcons[dev.vendorId]!,
                      rssi: dev.rssi,
                      onTap: () => _onDeviceTap(dev),
                    );
                  },
                  childCount: devices.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan',
        onPressed: _toggleScan,
        backgroundColor:
            scanning ? AppTheme.iosRed : AppTheme.iosBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: Icon(scanning
            ? Icons.stop_rounded
            : Icons.bluetooth_searching_rounded),
        label: Text(scanning ? '停止' : '扫描'),
      ),
    );
  }
}

/// 设备卡片
class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;
  final bool isConnected;
  final Color vendorColor;
  final IconData vendorIcon;
  final int rssi;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.isConnected,
    required this.vendorColor,
    required this.vendorIcon,
    required this.rssi,
    required this.onTap,
  });

  String _rssiQuality(int rssi) {
    if (rssi >= -50) return '极佳';
    if (rssi >= -70) return '良好';
    if (rssi >= -90) return '一般';
    return '较弱';
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -50) return AppTheme.iosGreen;
    if (rssi >= -70) return AppTheme.iosTeal;
    if (rssi >= -90) return AppTheme.iosOrange;
    return AppTheme.iosRed;
  }

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
          border: isConnected
              ? Border.all(color: AppTheme.iosGreen.withOpacity(0.3), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: vendorColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(vendorIcon, color: vendorColor, size: 24),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isConnected ? AppTheme.iosGreen : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: AppTheme.iosGreen),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${device.mac}  ·  ${device.vendorId.name}'
                    '${device.deviceType != DeviceType.unknown ? " · ${device.deviceType.name}" : ""}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.iosGray,
                    ),
                  ),
                ],
              ),
            ),
            // RSSI
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$rssi',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _rssiColor(rssi),
                  ),
                ),
                Text(
                  'dBm',
                  style: TextStyle(fontSize: 10, color: AppTheme.iosGray),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _rssiColor(rssi).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _rssiQuality(rssi),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _rssiColor(rssi),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
