// 访问各音乐平台的 HTTP 工具（不走 Lyra 后端的 ApiClient）。
// 行为对齐桌面端：单请求超时 8 秒；只对连接类错误（断网、DNS、超时）重试，最多 3 次，退避 320 / 640 ms；
// HTTP 429 / 403 等状态码不重试（越重试越容易被封）。全局最多 3 个并发请求。
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

class PlatformHttp {
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;
  final int maxConcurrent;
  final Duration timeout;
  final void Function(String)? log;
  int _running = 0;
  final _waiters = Queue<Completer<void>>();

  /// 桌面端默认 UA。各平台会按需覆盖。
  static const defaultUa = 'Mozilla/5.0 Sollin/0.1';

  PlatformHttp({http.Client? client, Future<void> Function(Duration)? sleep, this.maxConcurrent = 3, this.timeout = const Duration(seconds: 8), void Function(String)? log})
      : _client = client ?? http.Client(),
        _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        log = log ?? (kDebugMode ? debugPrint : null);

  Future<T> _limit<T>(Future<T> Function() f) async {
    if (_running >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await f();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
    }
  }

  /// 发请求并返回原始字节。[platform] 只用于错误信息。
  Future<http.Response> send(String platform, String method, Uri url, {Map<String, String>? headers, Object? body, Duration? timeout}) {
    return _limit(() async {
      Object? last;
      for (var attempt = 0; attempt < 3; attempt++) {
        final req = http.Request(method, url)..headers.addAll({'User-Agent': defaultUa, ...?headers});
        if (body is String) {
          req.body = body;
        } else if (body is List<int>) {
          req.bodyBytes = body;
        } else if (body is Map<String, String>) {
          req.bodyFields = body;
        }
        try {
          final res = await _client.send(req).then(http.Response.fromStream).timeout(timeout ?? this.timeout);
          log?.call('[$platform] $method ${url.host}${url.path} → ${res.statusCode}');
          if (res.statusCode < 200 || res.statusCode >= 300) throw PlatformException(platform, '请求失败（HTTP ${res.statusCode}）');
          return res;
        } on PlatformException {
          rethrow;
        } catch (e) {
          // 连接类错误（断网 / DNS / 超时）：退避后重试
          last = e;
          if (attempt < 2) await _sleep(Duration(milliseconds: 320 * (1 << attempt)));
        }
      }
      throw PlatformException(platform, '网络连接失败，请检查网络后重试', last);
    });
  }

  Future<Uint8List> bytes(String platform, String method, Uri url, {Map<String, String>? headers, Object? body, Duration? timeout}) async =>
      (await send(platform, method, url, headers: headers, body: body, timeout: timeout)).bodyBytes;

  /// 文本（按 UTF-8 解码，容错）。
  Future<String> text(String platform, String method, Uri url, {Map<String, String>? headers, Object? body, Duration? timeout}) async =>
      utf8.decode(await bytes(platform, method, url, headers: headers, body: body, timeout: timeout), allowMalformed: true);

  /// JSON。兼容 JSONP（`callback({...})`）和 BOM。解析失败抛 [PlatformException]。
  Future<dynamic> json(String platform, String method, Uri url, {Map<String, String>? headers, Object? body, Duration? timeout}) async {
    final t = await text(platform, method, url, headers: headers, body: body, timeout: timeout);
    return decodeJson(platform, t);
  }

  Future<dynamic> getJson(String platform, String url, {Map<String, String>? headers}) => json(platform, 'GET', Uri.parse(url), headers: headers);

  Future<dynamic> postJson(String platform, String url, Object payload, {Map<String, String>? headers}) =>
      json(platform, 'POST', Uri.parse(url), headers: {'Content-Type': 'application/json', ...?headers}, body: jsonEncode(payload));

  /// application/x-www-form-urlencoded；[form] 可以是已经编码好的字符串。
  Future<dynamic> postForm(String platform, String url, Object form, {Map<String, String>? headers}) => json(platform, 'POST', Uri.parse(url),
      headers: {'Content-Type': 'application/x-www-form-urlencoded', ...?headers}, body: form is String ? form : (form as Map<String, String>).entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));

  static dynamic decodeJson(String platform, String raw) {
    var t = raw.trim();
    if (t.startsWith('\uFEFF')) t = t.substring(1);
    if (t.isNotEmpty && t[0] != '{' && t[0] != '[') {
      final a = t.indexOf('('), b = t.lastIndexOf(')');
      if (a > 0 && b > a) t = t.substring(a + 1, b);
    }
    try {
      return jsonDecode(t);
    } catch (e) {
      throw PlatformException(platform, '平台返回的数据格式不对', e);
    }
  }

  void close() => _client.close();
}
