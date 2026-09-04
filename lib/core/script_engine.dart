import 'dart:async';

/// ============================================================
/// 轻量自动化脚本引擎
/// 支持延时、循环、条件判断、指令下发、结果校验
/// ============================================================

enum ScriptActionType {
  delay,
  connect,
  disconnect,
  sendAt,
  writeReg,
  readReg,
  ota,
  log,
  assertResult,
}

class ScriptAction {
  final ScriptActionType type;
  final Map<String, dynamic> params;

  ScriptAction(this.type, this.params);

  factory ScriptAction.delay(int ms) =>
      ScriptAction(ScriptActionType.delay, {'ms': ms});

  factory ScriptAction.sendAt(String cmd) =>
      ScriptAction(ScriptActionType.sendAt, {'cmd': cmd});

  factory ScriptAction.writeReg(int addr, List<int> data) =>
      ScriptAction(ScriptActionType.writeReg, {'addr': addr, 'data': data});

  factory ScriptAction.readReg(int addr, [int len = 1]) =>
      ScriptAction(ScriptActionType.readReg, {'addr': addr, 'len': len});

  factory ScriptAction.ota(String file) =>
      ScriptAction(ScriptActionType.ota, {'file': file});

  factory ScriptAction.connect() =>
      ScriptAction(ScriptActionType.connect, const {});

  factory ScriptAction.disconnect() =>
      ScriptAction(ScriptActionType.disconnect, const {});

  factory ScriptAction.log(String msg) =>
      ScriptAction(ScriptActionType.log, {'msg': msg});

  factory ScriptAction.assertResult(String expected) =>
      ScriptAction(ScriptActionType.assertResult, {'expected': expected});
}

class ScriptStep {
  final String? name;
  final List<ScriptAction> actions;
  final int? repeat; // 循环次数, null = 不循环
  final String? condition; // 条件表达式

  ScriptStep(this.actions, {this.name, this.repeat, this.condition});
}

class TestScript {
  final String name;
  final String description;
  final List<ScriptStep> steps;
  final Map<String, dynamic> variables;

  TestScript({
    required this.name,
    required this.description,
    required this.steps,
    this.variables = const {},
  });
}

/// 脚本执行引擎
class ScriptEngine {
  bool _running = false;
  bool get isRunning => _running;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  Stream<String> get output => _outputController.stream;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  Stream<double> get progress => _progressController.stream;

  /// 累积本次运行的所有输出行，供 assertResult 做全量匹配（而非仅最后一行），
  /// 这样「读寄存器」等动作覆盖 lastResult 后，早先的 AT 响应仍可被断言命中。
  final StringBuffer _transcript = StringBuffer();

  void _log(String line) {
    _outputController.add(line);
    _transcript.writeln(line);
  }


  /// 执行脚本
  ///
  /// 返回 true 表示所有 assertResult 校验通过（无断言或全 PASS）。
  Future<bool> execute(
    TestScript script, {
    required Future<String> Function(String cmd) onSendAt,
    required Future Function(int addr, List<int> data) onWriteReg,
    required Future<List<int>> Function(int addr) onReadReg,
    Future<void> Function()? onConnect,
    Future<void> Function()? onDisconnect,
    Future<String> Function(String filePath)? onOta,
  }) async {
    _running = true;
    _transcript.clear();
    var stepIndex = 0;
    final totalSteps = script.steps.length;
    var assertFailures = 0;
    String lastResult = '';

    for (final step in script.steps) {
      if (!_running) break;

      final repeatCount = step.repeat ?? 1;
      for (var r = 0; r < repeatCount && _running; r++) {
        _log('[Step ${stepIndex + 1}] ${step.name ?? 'unnamed'}'
            '${r > 0 ? " (repeat ${r + 1})" : ""}');

        for (final action in step.actions) {
          if (!_running) break;

          try {
          switch (action.type) {
            case ScriptActionType.delay:
              final ms = action.params['ms'] as int? ?? 0;
              await Future.delayed(Duration(milliseconds: ms));
              break;

            case ScriptActionType.connect:
              if (onConnect != null) {
                _log('>> CONNECT');
                await onConnect();
                _log('<< 已连接');
              } else {
                _log('[SKIP] connect 未绑定回调');
              }
              break;

            case ScriptActionType.disconnect:
              if (onDisconnect != null) {
                _log('>> DISCONNECT');
                await onDisconnect();
                _log('<< 已断开');
              } else {
                _log('[SKIP] disconnect 未绑定回调');
              }
              break;

            case ScriptActionType.sendAt:
              final cmd = action.params['cmd'] as String;
              _log('>> AT: $cmd');
              final result = await onSendAt(cmd);
              lastResult = result;
              _log('<< $result');
              break;

            case ScriptActionType.writeReg:
              final addr = action.params['addr'] as int;
              final data = (action.params['data'] as List?)?.cast<int>() ?? const [];
              await onWriteReg(addr, data);
              _log(
                  '>> REG_WR: 0x${addr.toRadixString(16)} = $data');
              break;

            case ScriptActionType.readReg:
              final addr = action.params['addr'] as int;
              final data = await onReadReg(addr);
              final hex = data
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(' ');
              lastResult = hex;
              _log(
                  '>> REG_RD: 0x${addr.toRadixString(16)} = [$hex]');
              break;

            case ScriptActionType.ota:
              final file = action.params['file'] as String? ?? '';
              if (onOta != null) {
                _log('>> OTA: $file');
                final result = await onOta(file);
                lastResult = result;
                _log('<< $result');
              } else {
                _log('[SKIP] ota 未绑定回调');
              }
              break;

            case ScriptActionType.log:
              _log('[LOG] ${action.params['msg']}');
              break;

            case ScriptActionType.assertResult:
              final expected = (action.params['expected'] as String?) ?? '';
              final pass = _transcript
                  .toString()
                  .toLowerCase()
                  .contains(expected.toLowerCase());
              if (pass) {
                _log('[ASSERT] PASS — 含 "$expected"');
              } else {
                assertFailures++;
                _log(
                    '[ASSERT] FAIL — 期望含 "$expected"，实际: $lastResult');
              }
              break;
          }
          } catch (e) {
            _log('[ERROR] ${action.type.name}: $e');
          }
        }
      }

      stepIndex++;
      _progressController.add((stepIndex / totalSteps).clamp(0.0, 1.0));
    }

    _running = false;
    return assertFailures == 0;
  }

  void stop() {
    _running = false;
  }

  void dispose() {
    _outputController.close();
    _progressController.close();
  }
}

/// 产线测试报告
class TestReport {
  final String deviceMac;
  final DateTime startTime;
  final DateTime endTime;
  final List<TestStepResult> results;
  final bool allPassed;

  TestReport({
    required this.deviceMac,
    required this.startTime,
    required this.endTime,
    required this.results,
    required this.allPassed,
  });

  /// 导出为 CSV
  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Device,Step,Status,Duration(ms),Detail');
    for (final r in results) {
      buffer.writeln(
          '$deviceMac,${r.stepName},${r.passed ? "PASS" : "FAIL"},'
          '${r.durationMs},${r.detail}');
    }
    return buffer.toString();
  }
}

class TestStepResult {
  final String stepName;
  final bool passed;
  final int durationMs;
  final String detail;

  TestStepResult({
    required this.stepName,
    required this.passed,
    required this.durationMs,
    required this.detail,
  });
}
