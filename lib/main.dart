import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 当前连接的适配器
  BaseBluetoothAdapter? _adapter;
  BaseBluetoothAdapter? get adapter => _adapter;

  /// GATT 服务树
  final List<GattService> _services = [];
  List<GattService> get services => List.unmodifiable(_services);

  /// adapter 日志桥接 subscription
  StreamSubscription? _logSub;

  /// 开始扫描
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;
    _scanning = true;
    _scanResults.clear();
    notifyListeners();

    _logParser.addLog(LogItem(
      timestamp: DateTime.now(),
      deviceMac: '',
      type: LogType.system,
      dir: LogDirection.send,
      rawHex: '',
      decodeText: '开始扫描 BLE 设备...',
    ));

    final stdAdapter = StandardBluetoothAdapter();
    try {
      final stream = stdAdapter.scanDevicesStream(timeout: timeout);
      await for (final device in stream) {
        // 去重
        final idx = _scanResults.indexWhere((d) => d.mac == device.mac);
        if (idx >= 0) {
          _scanResults[idx] = device;
        } else {
          _scanResults.add(device);
        }
        notifyListeners();
      }
    } catch (e) {
      _logParser.addLog(LogItem(
        timestamp: DateTime.now(),
        deviceMac: '',
        type: LogType.system,
        dir: LogDirection.recv,
        rawHex: '',
        decodeText: '扫描出错: $e',
      ));
    } finally {
      await stdAdapter.stopScan();
    }

    _scanning = false;
    notifyListeners();

    _logParser.addLog(LogItem(
      timestamp: DateTime.now(),
      deviceMac: '',
      type: LogType.system,
      dir: LogDirection.recv,
      rawHex: '',
      decodeText: '扫描完成，发现 ${_scanResults.length} 个设备',
    ));
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await _deviceManager.broadcastCommand((adapter) async {
      if (adapter is StandardBluetoothAdapter) {
        await adapter.stopScan();
      }
    });
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
      _logParser.addLog(LogItem(
        timestamp: DateTime.now(),
        deviceMac: device.mac,
        type: LogType.system,
        dir: LogDirection.recv,
        rawHex: '',
        decodeText: '连接失败',
      ));
    }

    notifyListeners();
    return ok;
  }

  /// 断开当前设备
  Future<void> disconnect() async {
    if (_selectedDevice == null) return;

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
  ];

  final labels = [
    '扫描',
    'GATT',
    '日志',
    'OTA',
    '寄存器',
    '音频',
    '插件',
  ];

  final icons = [
    Icons.bluetooth_searching_rounded,
    Icons.account_tree_rounded,
    Icons.terminal_rounded,
    Icons.system_update_rounded,
    Icons.memory_rounded,
    Icons.graphic_eq_rounded,
    Icons.extension_rounded,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
