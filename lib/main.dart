import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'ui/scan_page.dart';
import 'ui/log_console.dart';
import 'ui/gatt_view.dart';
import 'ui/ota_page.dart';
import 'ui/register_debug.dart';
import 'ui/plugin_manager.dart';
import 'ui/audio_debug.dart';
import 'core/protocol_registry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// 启动时预加载三套内置协议
  await _loadBuiltinProtocols();

  runApp(const BlueDebugApp());
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

class BlueDebugApp extends StatelessWidget {
  const BlueDebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueDebug',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
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
    'Scan',
    'GATT',
    'Log',
    'OTA',
    'Register',
    'Audio',
    'Plugins',
  ];

  final icons = [
    Icons.bluetooth_searching,
    Icons.account_tree,
    Icons.terminal,
    Icons.system_update,
    Icons.memory,
    Icons.graphic_eq,
    Icons.extension,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: List.generate(labels.length, (i) {
          return NavigationDestination(
            icon: Icon(icons[i]),
            label: labels[i],
          );
        }),
      ),
    );
  }
}
