import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'adapter/base_bluetooth.dart';
import 'adapter/bluetooth_impl.dart';
import 'core/device_manager.dart';
import 'core/log_parser.dart';
import 'core/protocol_registry.dart';
import 'plugins/base_plugin.dart';
import 'plugins/bes_tws_plugin.dart';
import 'plugins/qcc_ar_plugin.dart';
import 'plugins/wq_bluetooth_plugin.dart';
import 'ui/scan_page.dart';
import 'ui/log_console.dart';
import 'ui/gatt_view.dart';
import 'ui/ota_page.dart';
import 'ui/register_debug.dart';
import 'ui/plugin_manager.dart';
import 'ui/audio_debug.dart';
import 'ui/automation_page.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// 启动时预加载三套内置协议
  await _loadBuiltinProtocols();

  /// 注册内置插件
  _registerBuiltinPlugins();

  runApp(const BleDebugApp());
}

/// 从 assets/protocols/ 加载内置厂商协议定义
Future<void> _loadBuiltinProtocols() async {
  final registry = ProtocolRegistry();
  const protocols = [
    'assets/protocols/bes_v2.json',
    'assets/protocols/ar1_v1.json',
    'assets/protocols/wq_v1.json',
    'assets/protocols/unisoc_w517.json',
    'assets/protocols/realtek_rtl8763e.json',
    'assets/protocols/actions_ats3089.json',
    'assets/protocols/nordic_nrf54.json',
  ];

  for (final path in protocols) {
    try {
      final jsonStr = await rootBundle.loadString(path);
      registry.loadFromJson(jsonStr);
    } catch (e) {
      debugPrint('[ProtocolLoader] 加载失败 $path: $e');
    }
  }

  debugPrint(
      '[ProtocolLoader] 已加载 ${registry.all.length} 套协议: ${registry.ids.join(", ")}');
}

/// 注册内置插件
void _registerBuiltinPlugins() {
  final reg = PluginRegistry();
  reg.register(BesTwsPlugin());
  reg.register(QccArPlugin());
  reg.register(WqBluetoothPlugin());
}

/// 设置状态栏样式
void _setSystemUIStyle(Brightness brightness) {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness:
        brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor:
        brightness == Brightness.dark ? AppTheme.darkBg : Colors.white,
    systemNavigationBarIconBrightness:
        brightness == Brightness.dark ? Brightness.light : Brightness.dark,
  ));
}

class BleDebugApp extends StatelessWidget {
  const BleDebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BleState>.value(value: BleState()),
        Provider<DeviceManager>.value(value: DeviceManager()),
        Provider<LogParser>.value(value: LogParser()),
      ],
      child: MaterialApp(
        title: 'BLE Debug Tools',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const MainPage(),
      ),
    );
  }
}

/// ============================================================
/// 全局 BLE 状态管理（ChangeNotifier）
/// 统一管理扫描结果、连接状态、当前设备
/// ============================================================
class BleState extends ChangeNotifier {
  final DeviceManager _deviceManager = DeviceManager();
  final LogParser _logParser = LogParser();

  /// 扫描状态
  bool _scanning = false;
  bool get scanning => _scanning;

  /// 扫描到的设备列表
  final List<DeviceInfo> _scanResults = [];
  List<DeviceInfo> get scanResults => List.unmodifiable(_scanResults);

  /// 当前选中的设备
  DeviceInfo? _selectedDevice;
  DeviceInfo? get selectedDevice => _selectedDevice;

  /// 当前连接状态
  bool _connected = false;
  bool get connected => _connected;

  /// 最近一次连接失败原因（供 UI 提示）
  String? get lastConnectError =>
      _selectedDevice != null ? _deviceManager.lastConnectError(_selectedDevice!.mac) : null;

  /// 当前连接的适配器
  BaseBluetoothAdapter? _adapter;
  BaseBluetoothAdapter? get adapter => _adapter;

  /// GATT 服务树
  final List<GattService> _services = [];
  List<GattService> get services => List.unmodifiable(_services);

  /// adapter 日志桥接 subscription
  StreamSubscription? _logSub;

  /// adapter 连接状态桥接 subscription（用于感知底层断连）
  StreamSubscription? _connStateSub;

  /// 扫描期间使用的 adapter（用于 stopScan 精确停止）
  StandardBluetoothAdapter? _scanAdapter;

  /// 最近一次扫描的错误原因（供 UI 展示，成功时为 null）
  String? _scanError;
  String? get scanError => _scanError;

  /// 上次刷新 UI 的时间（扫描结果高频回调时节流用）
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 节流刷新：continuousUpdates 下每收到一批广播包就会回调，
  /// 不做节流会每帧重建整个设备列表导致卡顿。
  /// 扫描结束时另有一次无条件 notifyListeners，保证最终状态一定被渲染。
  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 200)) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _addSystemLog(String text) {
    _logParser.addLog(LogItem(
      timestamp: DateTime.now(),
      deviceMac: '',
      type: LogType.system,
      dir: LogDirection.recv,
      rawHex: '',
      decodeText: text,
    ));
  }

  /// 扫描前置检查：硬件支持 → 蓝牙已开启 → 运行时权限
  /// 返回 null 表示可以扫描，否则返回给用户的失败原因
  Future<String?> _checkScanPrerequisites() async {
    // 1. 硬件是否支持 BLE
    if (!await fbp.FlutterBluePlus.isSupported) {
      return '当前设备不支持蓝牙低功耗 (BLE)';
    }

    // 2. 蓝牙是否开启（首次调用时 adapterStateNow 可能为 unknown，需拉一次流）
    var state = fbp.FlutterBluePlus.adapterStateNow;
    if (state == fbp.BluetoothAdapterState.unknown) {
      state = await fbp.FlutterBluePlus.adapterState.first;
    }
    if (state != fbp.BluetoothAdapterState.on) {
      return '蓝牙未开启（当前状态：${state.name}）';
    }

    // 3. Android 运行时权限
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      // Android 11 及以下没有 BLUETOOTH_SCAN/CONNECT，退化为位置权限
      final locStatus = await Permission.locationWhenInUse.status;

      final scanOk =
          statuses[Permission.bluetoothScan]!.isGranted || locStatus.isGranted;
      final connOk =
          statuses[Permission.bluetoothConnect]!.isGranted || locStatus.isGranted;

      if (!scanOk || !connOk) {
        return '蓝牙权限未授予（扫描=${scanOk ? '已授权' : '被拒绝'}，'
            '连接=${connOk ? '已授权' : '被拒绝'}），请在系统设置中允许后重试';
      }
    }

    return null;
  }

  /// 开始扫描
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;

    _scanError = null;
    _scanning = true;
    _scanResults.clear();
    notifyListeners();

    _addSystemLog('开始扫描 BLE 设备...');

    // 前置检查：不通过时直接告诉用户原因，而不是转圈 10 秒后给个空列表
    final blocked = await _checkScanPrerequisites();
    if (blocked != null) {
      _scanning = false;
      _scanError = blocked;
      notifyListeners();
      _addSystemLog('扫描中止：$blocked');
      return;
    }

    final stdAdapter = StandardBluetoothAdapter();
    _scanAdapter = stdAdapter;
    try {
      final stream = stdAdapter.scanDevicesStream(timeout: timeout);
      await for (final device in stream) {
        // 按 mac 去重并刷新 RSSI
        final idx = _scanResults.indexWhere((d) => d.mac == device.mac);
        if (idx >= 0) {
          _scanResults[idx] = device;
        } else {
          _scanResults.add(device);
        }
        _notifyThrottled();
      }
    } catch (e) {
      _scanError = '扫描出错：$e';
      _addSystemLog('扫描出错: $e');
    } finally {
      await stdAdapter.stopScan();
      _scanAdapter = null;
    }

    _scanning = false;
    notifyListeners();

    _addSystemLog('扫描完成，发现 ${_scanResults.length} 个设备');
  }

  /// 停止扫描
  Future<void> stopScan() async {
    // 注意：不要走 DeviceManager.broadcastCommand —— 扫描用的 adapter
    // 并未注册进 DeviceManager 的连接池，遍历它永远拿不到，stopScan 会静默失效。
    await _scanAdapter?.stopScan();
    _scanAdapter = null;
    _scanning = false;
    notifyListeners();
  }

  /// 连接设备
  Future<bool> connectDevice(DeviceInfo device) async {
    _selectedDevice = device;
    notifyListeners();

    _logParser.addLog(LogItem(
      timestamp: DateTime.now(),
      deviceMac: device.mac,
      type: LogType.system,
      dir: LogDirection.send,
      rawHex: '',
      decodeText: '正在连接 ${device.name} (${device.mac})...',
    ));

    final ok = await _deviceManager.connectDevice(device);

    if (ok) {
      _adapter = _deviceManager.getAdapter(device.mac);
      _connected = true;

      // 桥接 adapter 日志流到全局 LogParser
      _logSub?.cancel();
      _logSub = _adapter!.getDeviceLogStream().listen((item) {
        _logParser.addLog(item);
      });

      // 桥接底层连接状态：设备掉线时把 _connected 真实地回写为 false，
      // 否则 UI 会一直显示「已连接」但所有操作静默失败。
      _connStateSub?.cancel();
      _connStateSub = _adapter!.connectionStateStream.listen((isConn) {
        if (!isConn && _connected) _onAdapterDisconnected(device.mac);
      });

      // 自动发现 GATT 服务
      try {
        _services.clear();
        _services.addAll(await _adapter!.discoverServices());
      } catch (e) {
        _logParser.addLog(LogItem(
          timestamp: DateTime.now(),
          deviceMac: device.mac,
          type: LogType.system,
          dir: LogDirection.recv,
          rawHex: '',
          decodeText: 'GATT 服务发现失败: $e',
        ));
      }

      _logParser.addLog(LogItem(
        timestamp: DateTime.now(),
        deviceMac: device.mac,
        type: LogType.system,
        dir: LogDirection.recv,
        rawHex: '',
        decodeText: '已连接 ${device.name}，发现 ${_services.length} 个服务',
      ));
    } else {
      final err = _deviceManager.lastConnectError(device.mac);
      _logParser.addLog(LogItem(
        timestamp: DateTime.now(),
        deviceMac: device.mac,
        type: LogType.system,
        dir: LogDirection.recv,
        rawHex: '',
        decodeText: '连接失败${err != null ? ': $err' : ''}',
      ));
    }

    notifyListeners();
    return ok;
  }

  /// 底层 BLE 断连回调：把连接状态真实地回写为未连接
  void _onAdapterDisconnected(String mac) {
    _connected = false;
    _adapter = null;
    _services.clear();
    _connStateSub?.cancel();
    _connStateSub = null;
    _logSub?.cancel();
    _logSub = null;
    notifyListeners();
    _addSystemLog('设备已断开: $mac');
  }

  /// 断开当前设备
  Future<void> disconnect() async {
    if (_selectedDevice == null) return;

    _connStateSub?.cancel();
    _connStateSub = null;
    await _deviceManager.disconnectDevice(_selectedDevice!.mac);
    _logSub?.cancel();
    _connected = false;
    _adapter = null;
    _services.clear();
    _selectedDevice = null;

    notifyListeners();
  }

  /// 刷新 GATT 服务
  Future<void> refreshServices() async {
    if (_adapter == null) return;
    _services.clear();
    _services.addAll(await _adapter!.discoverServices());
    notifyListeners();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final pages = const [
    ScanPage(),
    GattView(),
    LogConsole(),
    OtaPage(),
    RegisterDebugPage(),
    AudioDebugPage(),
    PluginManagerPage(),
    AutomationPage(),
  ];

  final labels = [
    '扫描',
    'GATT',
    '日志',
    'OTA',
    '寄存器',
    '音频',
    '插件',
    '自动化',
  ];

  final icons = [
    Icons.bluetooth_searching_rounded,
    Icons.account_tree_rounded,
    Icons.terminal_rounded,
    Icons.system_update_rounded,
    Icons.memory_rounded,
    Icons.graphic_eq_rounded,
    Icons.extension_rounded,
    Icons.playlist_play_rounded,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setSystemUIStyle(Theme.of(context).brightness);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: List.generate(labels.length, (i) {
          final isConnected = bleState.connected;
          if (i == 0 && isConnected) {
            return NavigationDestination(
              icon: Badge(
                backgroundColor: AppTheme.iosGreen,
                child: Icon(icons[i]),
              ),
              label: labels[i],
            );
          }
          return NavigationDestination(
            icon: Icon(icons[i]),
            label: labels[i],
          );
        }),
      ),
    );
  }
}
