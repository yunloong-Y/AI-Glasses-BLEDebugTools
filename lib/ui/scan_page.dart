import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../main.dart';
import 'sn_binding_page.dart';
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

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 按名称 / MAC / 厂商 / 设备类型 / 服务 UUID 过滤扫描结果，并按信号强弱（RSSI 降序）排序
  List<DeviceInfo> _filterDevices(List<DeviceInfo> devices, String q) {
    final lower = q.toLowerCase();
    final result = devices.where((d) {
      if (q.isEmpty) return true;
      if (d.name.toLowerCase().contains(lower)) return true;
      if (d.mac.toLowerCase().contains(lower)) return true;
      if (d.vendorId.name.toLowerCase().contains(lower)) return true;
      if (d.deviceType.name.toLowerCase().contains(lower)) return true;
      if (d.bleServices.any((s) => s.toLowerCase().contains(lower))) {
        return true;
      }
      return false;
    }).toList();
    result.sort((a, b) => b.rssi.compareTo(a.rssi));
    return result;
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
        content: Text(ok
            ? '已连接 ${device.name}'
            : '连接失败${bleState.lastConnectError != null ? ': ${bleState.lastConnectError}' : ''}'),
        backgroundColor: ok ? AppTheme.iosGreen : AppTheme.iosRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final devices = bleState.scanResults;
    final filtered = _filterDevices(devices, _query);
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
              if (bleState.connected)
                IconButton(
                  tooltip: 'SN 绑定',
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SnBindingPage()),
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
          // Search bar（仅在有设备时显示）
          if (devices.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: '搜索 名称 / MAC / 厂商 / 服务 UUID',
                  style: const TextStyle(fontSize: 15),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
              ),
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
                  : (bleState.scanError != null)
                      ? IosEmptyState(
                          icon: Icons.error_outline_rounded,
                          title: '扫描失败',
                          subtitle: bleState.scanError!,
                        )
                      : IosEmptyState(
                          icon: Icons.bluetooth_disabled_rounded,
                          title: '暂无设备',
                          subtitle: '点击下方按钮开始扫描 BLE 设备',
                        ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: IosEmptyState(
                icon: Icons.search_off_rounded,
                title: '无匹配设备',
                subtitle: '没有设备匹配「$_query」',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final dev = filtered[i];
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
                  childCount: filtered.length,
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
