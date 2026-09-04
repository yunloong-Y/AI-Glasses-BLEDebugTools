import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// ============================================================
/// 正式环境仓库登录与预生成 SN 绑定客户端
/// （从 BesAPP MoonixSnBindingService.java 移植）
///
/// - 登录: POST /v1/admin/auth/login → token（需 warehouse:view + warehouse:write 权限）
/// - 查询: GET  /api/leg-device-sns/{sn}
/// - 绑定: POST /api/leg-device-sns/{sn}/bind
/// - 解绑: DELETE /api/leg-device-sns/{sn}/binding
/// ============================================================

/// SN 绑定记录（后台返回）
class SnBindingRecord {
  final String serialNumber;
  final String bindingStatus; // BOUND / UNBOUND
  final String? mac;
  final String? firmwareSn;
  final String? firmwareVersion;
  final String? macBoundAt;

  const SnBindingRecord({
    required this.serialNumber,
    required this.bindingStatus,
    this.mac,
    this.firmwareSn,
    this.firmwareVersion,
    this.macBoundAt,
  });

  bool get isBound => bindingStatus == 'BOUND';
}

/// SN 后台服务客户端（dart:io HttpClient，8s 超时）
class SnBindingService {
  static const String productionBaseUrl = 'https://admin.moonix.cn';
  static const String _warehouseView = 'warehouse:view';
  static const String _warehouseWrite = 'warehouse:write';
  static const Duration _timeout = Duration(seconds: 8);

  final String baseUrl;
  final String username;
  final String password;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = _timeout;

  SnBindingService({
    this.baseUrl = productionBaseUrl,
    this.username = 'warehouse',
    this.password = 'warehouse123',
  });

  String get _root => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  /// 登录并校验仓库权限，返回 Bearer token
  Future<String> _login() async {
    if (baseUrl.isEmpty) {
      throw const SocketException('正式环境地址未配置');
    }
    final body = jsonEncode({'username': username, 'password': password});
    final response = await _execute(
        'POST', '$_root/v1/admin/auth/login', body, null);
    final token = (_jsonField(response, 'token') as String? ?? '').trim();
    if (token.isEmpty) {
      throw const HttpException('登录响应缺少 token');
    }
    final permissions = response['permissions'];
    final canView = permissions is List &&
        permissions.any((p) => p == _warehouseView);
    final canWrite = permissions is List &&
        permissions.any((p) => p == _warehouseWrite);
    if (!canView) {
      throw const HttpException('仓库账号缺少 warehouse:view 权限');
    }
    if (!canWrite) {
      throw const HttpException('仓库账号缺少 warehouse:write 权限');
    }
    return token;
  }

  /// 查询 SN 绑定状态
  Future<SnBindingRecord> lookup(String serialNumber) async {
    final token = await _login();
    final response = await _execute(
        'GET', '$_root/api/leg-device-sns/$serialNumber', null, token);
    final record = _parseRecord(response);
    if (record.serialNumber != serialNumber) {
      throw const HttpException('SN 查询响应 SN 不一致');
    }
    return record;
  }

  /// 绑定 SN（mac / firmwareSn / firmwareVersion 上报后台）
  Future<void> bind(
      String serialNumber, String mac, String firmwareSn,
      String firmwareVersion) async {
    final normalizedMac = normalizeMac(mac);
    final token = await _login();
    final body = jsonEncode({
      'mac': normalizedMac,
      'firmwareSn': firmwareSn,
      'firmwareVersion': firmwareVersion,
    });
    final response = await _execute(
        'POST', '$_root/api/leg-device-sns/$serialNumber/bind', body, token);
    final record = _parseRecord(response);
    if (record.serialNumber != serialNumber) {
      throw const HttpException('绑定响应 SN 不一致');
    }
    if (!record.isBound) {
      throw const HttpException('绑定响应状态不是 BOUND');
    }
    if (normalizeMac(record.mac) != normalizedMac) {
      throw const HttpException('绑定响应 MAC 不一致');
    }
  }

  /// 解除绑定
  Future<SnBindingRecord> clearBinding(String serialNumber) async {
    final token = await _login();
    final response = await _execute('DELETE',
        '$_root/api/leg-device-sns/$serialNumber/binding', null, token);
    final record = _parseRecord(response);
    if (record.serialNumber != serialNumber) {
      throw const HttpException('删除绑定响应 SN 不一致');
    }
    if (record.isBound) {
      throw const HttpException('删除绑定响应状态不是 UNBOUND');
    }
    if (record.mac != null ||
        record.firmwareSn != null ||
        record.firmwareVersion != null ||
        record.macBoundAt != null) {
      throw const HttpException('删除绑定响应仍包含绑定信息');
    }
    return record;
  }

  // ---------- HTTP 基础设施 ----------

  Future<dynamic> _execute(
      String method, String url, String? body, String? bearerToken) async {
    try {
      final uri = Uri.parse(url);
      final request = await _http.openUrl(method, uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
            HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      if (body != null) {
        final bytes = utf8.encode(body);
        request.headers.set(HttpHeaders.contentTypeHeader,
            'application/json; charset=UTF-8');
        request.headers.contentLength = bytes.length;
        request.add(bytes);
      }
      final response =
          await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_httpErrorMessage(text, response.statusCode));
      }
      if (text.isEmpty) {
        throw const HttpException('响应体为空');
      }
      return jsonDecode(text);
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on HttpException {
      rethrow;
    } on FormatException catch (e) {
      throw HttpException('响应 JSON 解析失败: ${e.message}');
    }
  }

  String _httpErrorMessage(String text, int code) {
    try {
      final object = jsonDecode(text);
      if (object is Map) {
        var message = (object['message'] ?? '').toString().trim();
        if (message.isEmpty) {
          message = (object['detail'] ?? '').toString().trim();
        }
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'HTTP $code';
  }

  Object? _jsonField(dynamic json, String key) {
    if (json is Map) return json[key];
    return null;
  }

  SnBindingRecord _parseRecord(dynamic json) {
    if (json is! Map) {
      throw const HttpException('SN 响应格式无效');
    }
    final sn = (json['sn'] ?? '').toString().trim().toUpperCase();
    final status = (json['bindingStatus'] ?? '').toString().trim().toUpperCase();
    if (sn.isEmpty || status.isEmpty) {
      throw const HttpException('SN 响应缺少字段');
    }
    if (status != 'BOUND' && status != 'UNBOUND') {
      throw HttpException('SN 响应绑定状态无效: $status');
    }
    return SnBindingRecord(
      serialNumber: sn,
      bindingStatus: status,
      mac: _optionalText(json, 'mac'),
      firmwareSn: _optionalText(json, 'firmwareSn'),
      firmwareVersion: _optionalText(json, 'firmwareVersion'),
      macBoundAt: _optionalText(json, 'macBoundAt'),
    );
  }

  String? _optionalText(Map json, String key) {
    final value = json[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// MAC 归一化为 AA:BB:CC:DD:EE:FF 大写格式
  static String normalizeMac(String? mac) {
    if (mac == null) {
      throw const HttpException('设备 MAC 为空');
    }
    final compact = mac
        .trim()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(compact)) {
      throw const HttpException('设备 MAC 格式无效');
    }
    final builder = StringBuffer();
    for (var i = 0; i < compact.length; i += 2) {
      if (i > 0) builder.write(':');
      builder.write(compact.substring(i, i + 2));
    }
    return builder.toString();
  }

  void shutdown() {
    _http.close(force: true);
  }
}
