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

  /// 执行脚本
  Future<bool> execute(
    TestScript script, {
    required Future<String> Function(String cmd) onSendAt,
    required Future Function(int addr, List<int> data) onWriteReg,
    required Future<List<int>> Function(int addr) onReadReg,
  }) async {
    _running = true;
    var stepIndex = 0;
    final totalSteps = script.steps.length;

    for (final step in script.steps) {
      if (!_running) break;

      final repeatCount = step.repeat ?? 1;
      for (var r = 0; r < repeatCount && _running; r++) {
        _outputController.add('[Step ${stepIndex + 1}] ${step.name ?? 'unnamed'}'
            '${r > 0 ? " (repeat ${r + 1})" : ""}');

        for (final action in step.actions) {
          if (!_running) break;

          switch (action.type) {
            case ScriptActionType.delay:
              final ms = action.params['ms'] as int;
              await Future.delayed(Duration(milliseconds: ms));
              break;

            case ScriptActionType.sendAt:
              final cmd = action.params['cmd'] as String;
              _outputController.add('>> AT: $cmd');
              final result = await onSendAt(cmd);
              _outputController.add('<< $result');
              break;

            case ScriptActionType.writeReg:
              final addr = action.params['addr'] as int;
              final data = action.params['data'] as List<int>;
              await onWriteReg(addr, data);
              _outputController.add(
                  '>> REG_WR: 0x${addr.toRadixString(16)} = $data');
              break;

            case ScriptActionType.log:
              _outputController.add('[LOG] ${action.params['msg']}');
              break;

            case ScriptActionType.assertResult:
              // TODO: 校验上一条指令的返回值
              break;

            default:
              break;
          }
        }
      }

      stepIndex++;
      _progressController.add((stepIndex / totalSteps).clamp(0.0, 1.0));
    }

    _running = false;
    return true;
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
