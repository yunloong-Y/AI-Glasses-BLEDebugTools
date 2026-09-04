import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../adapter/base_bluetooth.dart';
import '../core/glass_protocol.dart';
import '../core/log_parser.dart';
import '../core/sn_binding_coordinator.dart';
import '../core/sn_binding_service.dart';
import '../main.dart';
import 'theme.dart';/// ============================================================
/// SN 绑定页（从 BesAPP MoonixSnBindingActivity 移植，iOS 风格）
///
/// 流程：输入 SN(12位Base36) → 查询后台状态
///   - 已绑定：展示绑定详情，可解绑
///   - 未绑定：确认后执行 完整绑定（读身份→后台绑定→0x000E写→0x0009回读）
/// 失败恢复：后台已绑定但设备侧失败 → 仅重试设备写入
/// ============================================================

enum _SnPageMode { input, checking, boundInfo, binding, success, failure, clearing }

class SnBindingPage extends StatefulWidget {
  const SnBindingPage({super.key});

  @override
  State<SnBindingPage> createState() => _SnBindingPageState();
}

class _SnBindingPageState extends State<SnBindingPage> {
  final _snController = TextEditingController();
  final _snFocus = FocusNode();

  _SnPageMode _mode = _SnPageMode.input;
  SnBindingRecord? _record;
  SnBindingResult? _bindResult;
  SnBindingException? _bindError;
  Object? _otherError;
  SnBindingStage? _currentStage;

  GlassCommandClient? _commandClient;
  SnBindingService? _service;
  SnBindingCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    _snController.addListener(() {
      final text = _snController.text.toUpperCase();
      if (text != _snController.text) {
        _snController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      setState(() {}); // 刷新按钮可用态
    });
  }

  @override
  void dispose() {
    _commandClient?.stop();
    _service?.shutdown();
    _snController.dispose();
    _snFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _snController.text.trim().length == 12 && !_isBusy;

  bool get _isBusy =>
      _mode == _SnPageMode.checking ||
      _mode == _SnPageMode.binding ||
      _mode == _SnPageMode.clearing;

  /// 初始化命令通道与编排器（懒加载，需设备已连接）
  String? _ensureCoordinator() {
    final bleState = context.read<BleState>();
    final adapter = bleState.adapter;
    if (adapter == null || !adapter.isConnected) {
      return '请先在扫描页连接设备';
    }
    if (bleState.selectedDevice == null) {
      return '设备信息缺失，请重新连接';
    }

    _commandClient ??= GlassCommandClient(
      adapter: adapter,
      onLog: _pushSystemLog,
    );
    _service ??= SnBindingService();
    _coordinator ??= SnBindingCoordinator(
      device: GlassInfoApi(_commandClient!),
      backend: _service!,
      macProvider: () => bleState.selectedDevice!.mac,
      onLog: _pushSystemLog,
    );
    return null;
  }

  void _pushSystemLog(String message) {
    LogParser().addLog(LogItem(
      timestamp: DateTime.now(),
      deviceMac: context.read<BleState>().selectedDevice?.mac ?? '',
      type: LogType.atCmd,
      dir: LogDirection.send,
      rawHex: '',
      decodeText: '[SN] $message',
      logLevel: 0,
    ));
  }

  Future<void> _startCommandChannel() async {
    final client = _commandClient;
    if (client == null) return;
    try {
      await client.start();
    } catch (e) {
      _pushSystemLog('命令通道启动失败: $e');
    }
  }

  // ---------- 动作 ----------

  Future<void> _lookup() async {
    if (!_canSubmit) return;
    final error = _ensureCoordinator();
    if (error != null) {
      _showSnack(error, AppTheme.iosOrange);
      return;
    }
    FocusScope.of(context).unfocus();

    final sn = SnBindingCoordinator.normalizeSerialNumberSafe(
        _snController.text);
    if (sn == null) {
      _showSnack('SN 必须是 12 位数字或大写字母', AppTheme.iosRed);
      return;
    }

    await _startCommandChannel();

    setState(() {
      _mode = _SnPageMode.checking;
      _record = null;
      _bindResult = null;
      _bindError = null;
      _otherError = null;
    });
    _pushSystemLog('查询 SN 绑定状态: $sn');

    try {
      final record = await _service!.lookup(sn);
      if (!mounted) return;
      setState(() {
        _record = record;
        _mode = _SnPageMode.boundInfo;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otherError = e;
        _mode = _SnPageMode.failure;
        _bindError = null;
      });
    }
  }

  Future<void> _confirmAndBind() async {
    final sn = _snController.text.trim().toUpperCase();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认绑定'),
        content: Text(
            '将把 SN $sn 绑定到当前设备。\n\n'
            '流程：读取设备身份 → 后台绑定 → 写入 SN → 回读验证',
            style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始绑定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _bind();
    }
  }

  Future<void> _bind() async {
    setState(() {
      _mode = _SnPageMode.binding;
      _currentStage = SnBindingStage.readDeviceIdentity;
      _bindError = null;
      _otherError = null;
    });

    try {
      final result = await _coordinator!.bind(_snController.text);
      if (!mounted) return;
      setState(() {
        _bindResult = result;
        _mode = _SnPageMode.success;
      });
    } on SnBindingException catch (e) {
      if (!mounted) return;
      setState(() {
        _bindError = e;
        _mode = _SnPageMode.failure;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otherError = e;
        _mode = _SnPageMode.failure;
      });
    }
  }

  Future<void> _retryDeviceWrite() async {
    setState(() {
      _mode = _SnPageMode.binding;
      _currentStage = SnBindingStage.deviceWrite;
      _bindError = null;
      _otherError = null;
    });
    try {
      final result =
          await _coordinator!.retryDeviceWrite(_snController.text);
      if (!mounted) return;
      setState(() {
        _bindResult = result;
        _mode = _SnPageMode.success;
      });
    } on SnBindingException catch (e) {
      if (!mounted) return;
      setState(() {
        _bindError = e;
        _mode = _SnPageMode.failure;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otherError = e;
        _mode = _SnPageMode.failure;
      });
    }
  }

  Future<void> _confirmClear() async {
    final sn = _snController.text.trim().toUpperCase();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('解除绑定'),
        content: Text(
            '将删除后台 SN $sn 的绑定记录。\n'
            '设备固件中的 SN 不会被清除。',
            style: const TextStyle(fontSize: 14)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _clearBinding();
    }
  }

  Future<void> _clearBinding() async {
    setState(() => _mode = _SnPageMode.clearing);
    _pushSystemLog('删除后台绑定');
    try {
      final record =
          await _service!.clearBinding(_snController.text.trim());
      if (!mounted) return;
      setState(() {
        _record = record;
        _mode = _SnPageMode.boundInfo;
      });
      _showSnack('已解绑 ${record.serialNumber}', AppTheme.iosGreen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mode = _SnPageMode.boundInfo);
      _showSnack('解绑失败：$e', AppTheme.iosRed);
    }
  }

  void _resetToInput() {
    setState(() {
      _mode = _SnPageMode.input;
      _record = null;
      _bindResult = null;
      _bindError = null;
      _otherError = null;
      _currentStage = null;
    });
    _snController.clear();
    _snFocus.requestFocus();
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
    ));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SN 绑定'),
        centerTitle: true,
        toolbarHeight: 44,
        actions: [
          if (_mode != _SnPageMode.input)
            TextButton(
              onPressed: _isBusy ? null : _resetToInput,
              child: const Text('重新输入'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConnectionBanner(bleState, isDark),
              if (_mode == _SnPageMode.input) ..._buildInputSection(),
              if (_mode == _SnPageMode.checking)
                _buildChecking(isDark),
              if (_mode == _SnPageMode.boundInfo)
                ..._buildBoundInfo(isDark),
              if (_mode == _SnPageMode.binding) _buildBinding(isDark),
              if (_mode == _SnPageMode.success)
                ..._buildSuccess(isDark),
              if (_mode == _SnPageMode.failure)
                ..._buildFailure(isDark),
              if (_mode == _SnPageMode.clearing)
                _buildClearing(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(BleState bleState, bool isDark) {
    final connected = bleState.connected && bleState.adapter != null;
    final device = bleState.selectedDevice;
    return IosCard(
      child: ListTile(
        leading: Icon(
          connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
          color: connected ? AppTheme.iosGreen : AppTheme.iosGray,
        ),
        title: Text(
          connected ? (device?.name ?? '已连接设备') : '设备未连接',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          connected
              ? 'MAC ${device?.mac ?? '—'}\n协议通道 0x0009 / 0x000E'
              : 'SN 绑定需要先连接设备（读写设备 SN 与固件信息）',
          style: TextStyle(fontSize: 12, color: AppTheme.iosGray, height: 1.4),
        ),
        isThreeLine: true,
      ),
    );
  }

  List<Widget> _buildInputSection() {
    return [
      IosSectionHeader(
        title: '输入 SN',
        trailing: Text(
          '${_snController.text.trim().length}/12',
          style: TextStyle(fontSize: 12, color: AppTheme.iosGray),
        ),
      ),
      IosCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              TextField(
                controller: _snController,
                focusNode: _snFocus,
                enabled: !_isBusy,
                maxLength: 12,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z]')),
                ],
                decoration: const InputDecoration(
                  hintText: '12 位 SN（数字或大写字母）',
                  counterText: '',
                  prefixIcon: Icon(Icons.qr_code_rounded),
                ),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2),
                onSubmitted: (_) => _lookup(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _canSubmit ? _lookup : null,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('查询绑定状态'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          '绑定流程：校验 SN → 读取设备身份(MAC/固件SN/版本) → 后台绑定 → '
          '0x000E 写入设备 → 0x0009 回读验证',
          style: TextStyle(
              fontSize: 12, color: AppTheme.iosGray, height: 1.5),
        ),
      ),
    ];
  }

  Widget _buildChecking(bool isDark) {
    return const IosCard(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          CupertinoActivityIndicator(radius: 16),
          SizedBox(height: 16),
          Text('正在查询后台绑定状态...',
              style: TextStyle(fontSize: 15, color: AppTheme.iosGray)),
        ],
      ),
    );
  }

  List<Widget> _buildBoundInfo(bool isDark) {
    final record = _record!;
    return [
      IosSectionHeader(
          title: record.isBound ? '已绑定' : '未绑定'),
      IosCard(
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                record.isBound
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                color: record.isBound
                    ? AppTheme.iosGreen
                    : AppTheme.iosOrange,
              ),
              title: Text(record.serialNumber,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              subtitle: Text(record.isBound ? 'BOUND' : 'UNBOUND',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.iosGray)),
            ),
            if (record.isBound) ...[
              const Divider(indent: 16, endIndent: 16),
              _detailRow('绑定 MAC', record.mac),
              _detailRow('固件 SN', record.firmwareSn),
              _detailRow('固件版本', record.firmwareVersion),
              _detailRow('绑定时间', record.macBoundAt),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: record.isBound
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.iosRed),
                      onPressed:
                          _isBusy ? null : _confirmClear,
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('解除绑定'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _isBusy ? null : _confirmAndBind,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('绑定到当前设备'),
                    ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.iosGray)),
          ),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBinding(bool isDark) {
    final stages = [
      (SnBindingStage.readDeviceIdentity, '读取设备身份'),
      (SnBindingStage.backendBind, '后台绑定'),
      (SnBindingStage.deviceWrite, '写入设备 SN'),
      (SnBindingStage.deviceVerify, '回读验证'),
    ];
    return IosCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          const CupertinoActivityIndicator(radius: 14),
          const SizedBox(height: 16),
          ...stages.map((s) {
            final active = s.$1 == _currentStage;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    active
                        ? Icons.hourglass_top_rounded
                        : Icons.circle_outlined,
                    size: 16,
                    color: active ? AppTheme.iosBlue : AppTheme.iosGray3,
                  ),
                  const SizedBox(width: 10),
                  Text(s.$2,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: active
                              ? (isDark ? Colors.white : Colors.black)
                              : AppTheme.iosGray)),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            '绑定执行中，请保持设备连接...',
            style: TextStyle(
                fontSize: 12, color: AppTheme.iosGray),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSuccess(bool isDark) {
    final result = _bindResult!;
    return [
      IosCard(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.iosGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  size: 40, color: AppTheme.iosGreen),
            ),
            const SizedBox(height: 16),
            Text(
              '绑定成功',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 6),
            Text(result.serialNumber,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppTheme.iosGreen)),
            if (result.previousFirmwareSn != null &&
                result.previousFirmwareSn!.isNotEmpty &&
                result.previousFirmwareSn != result.serialNumber)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '原固件 SN：${result.previousFirmwareSn}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.iosGray),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _resetToInput,
                child: const Text('继续绑定下一台'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildFailure(bool isDark) {
    final bindingError = _bindError;
    final backendBound = bindingError?.backendBound ?? false;
    final message = bindingError != null
        ? bindingError.message
        : _otherError.toString();

    final stageText = switch (bindingError?.stage) {
      SnBindingStage.validateSn => '阶段：SN 校验',
      SnBindingStage.readDeviceIdentity => '阶段：读取设备身份',
      SnBindingStage.backendBind => '阶段：后台绑定',
      SnBindingStage.deviceWrite => '阶段：写入设备 SN',
      SnBindingStage.deviceVerify => '阶段：回读验证',
      _ => null,
    };

    return [
      IosCard(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.iosRed.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppTheme.iosRed),
            ),
            const SizedBox(height: 16),
            const Text('绑定失败',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            if (stageText != null) ...[
              const SizedBox(height: 4),
              Text(stageText,
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.iosGray)),
            ],
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (backendBound)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.iosOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '后台已绑定成功，仅需重试设备侧写入',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.iosOrange,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _resetToInput,
                child: const Text('重新输入'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: backendBound
                  ? ElevatedButton.icon(
                      onPressed: _retryDeviceWrite,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试设备写入'),
                    )
                  : ElevatedButton(
                      onPressed: _bind,
                      child: const Text('重试绑定'),
                    ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildClearing(bool isDark) {
    return const IosCard(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          CupertinoActivityIndicator(radius: 16),
          SizedBox(height: 16),
          Text('正在删除后台绑定...',
              style: TextStyle(fontSize: 15, color: AppTheme.iosGray)),
        ],
      ),
    );
  }
}
