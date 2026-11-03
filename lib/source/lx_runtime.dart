// 一个音源脚本的运行实例：QuickJS（flutter_qjs）+ lx 环境（lx_prelude.dart）。
//
// 生命周期对齐桌面端 SourceManager.start / requestRuntime：
//   start → 执行脚本 → 等脚本 lx.send('inited', {sources}) （10 秒超时）→ 得到各平台能力
//   request(action, platform, musicInfo, quality) → 调脚本的 request 处理器（默认 20 秒超时）
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'js_engine.dart';
import 'lx_native.dart';
import 'lx_prelude.dart';

/// 平台代码。
const lxPlatforms = {'kw', 'kg', 'tx', 'wy', 'mg', 'local'};
const lxQualities = ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'atmos_plus', 'master'];

/// 脚本在某个平台上的能力（inited 里声明的）。
class LxCapability {
  final String name;
  final List<String> actions, qualities;
  const LxCapability(this.name, this.actions, this.qualities);
  Map<String, dynamic> toJson() => {'name': name, 'actions': actions, 'qualities': qualities};
}

class LxScriptInfo {
  final String name, description, version, author, homepage;
  const LxScriptInfo({this.name = '', this.description = '', this.version = '', this.author = '', this.homepage = ''});
}

class LxException implements Exception {
  final String message;
  const LxException(this.message);
  @override
  String toString() => message;
}

/// 校验 inited 数据（桌面端 validateInit）。
Map<String, LxCapability> validateLxInit(Object? value) {
  if (value is! Map) throw const LxException('音源没有提供初始化信息');
  final raw = value['sources'];
  if (raw is! Map) throw const LxException('音源没有声明任何平台');
  final out = <String, LxCapability>{};
  for (final e in raw.entries) {
    final key = '${e.key}';
    final item = e.value;
    if (!lxPlatforms.contains(key) || item is! Map || item['type'] != 'music') continue;
    final allowed = key == 'local' ? const {'musicUrl', 'lyric', 'pic'} : const {'musicUrl'};
    final actions = [for (final a in (item['actions'] is List ? item['actions'] as List : const [])) if (a is String && allowed.contains(a)) a];
    final offered = item['qualitys'] is List ? item['qualitys'] as List : (item['qualities'] is List ? item['qualities'] as List : const []);
    final qualities = key == 'local' ? <String>[] : [for (final q in lxQualities) if (offered.contains(q)) q];
    final name = item['name'] is String ? (item['name'] as String) : key;
    out[key] = LxCapability(name.length > 80 ? name.substring(0, 80) : name, actions, qualities);
  }
  if (out.isEmpty) throw const LxException('音源没有提供支持的音乐平台');
  return out;
}

class LxRuntime {
  final JsEngine _qjs;
  final http.Client _http;
  final _inited = Completer<Map<String, LxCapability>>();
  final _cancelled = <String>{};
  bool _closed = false;

  /// 脚本发来的更新提示（{log, updateUrl?}）。
  void Function(Map<String, dynamic> alert)? onUpdateAlert;
  Map<String, dynamic>? updateAlert;

  LxRuntime._(this._qjs, this._http) {
    _inited.future.ignore(); // 启动失败后 dispose 再报错时没人监听
  }

  /// 启动脚本并等它初始化完成。失败（语法错误、超时、没声明平台）抛 [LxException]。
  static Future<LxRuntime> start(String script, {LxScriptInfo info = const LxScriptInfo(), http.Client? client, Duration initTimeout = const Duration(seconds: 10)}) async {
    // timeout：单次执行（eval / 回调 / 微任务）超过 5 秒就中断，防止脚本死循环卡住界面
    final JsEngine qjs;
    try {
      qjs = createJsEngine(timeoutMs: 5000);
    } on UnsupportedError catch (e) {
      throw LxException('${e.message}');
    }
    final rt = LxRuntime._(qjs, client ?? http.Client());
    try {
      rt._install(info, script);
      try {
        qjs.evaluate(script, name: 'custom-source.js');
      } catch (e) {
        throw LxException('脚本执行出错：${_short(e)}');
      }
      final caps = await rt._inited.future.timeout(initTimeout, onTimeout: () => throw const LxException('音源初始化超时（10 秒内没有完成 inited）'));
      return rt..capabilities = caps;
    } catch (e) {
      rt.dispose();
      if (e is LxException) rethrow;
      throw LxException(_short(e));
    }
  }

  late Map<String, LxCapability> capabilities;

  void _install(LxScriptInfo info, String script) {
    final e = _qjs;
    e.setGlobal('__lx_native', (String op, String arg) => lxNative(op, arg));
    e.setGlobal('__lx_http', (String id, String url, String opts) => _httpCall(id, url, opts));
    e.setGlobal('__lx_http_cancel', (String id) => _cancelled.add(id));
    e.setGlobal('__lx_zlib', (String op, String data) => Future(() => lxZlib(op, data)));
    e.setGlobal('__lx_sleep', (dynamic ms) => Future<void>.delayed(Duration(milliseconds: ms is num ? ms.toInt() : 0)));
    e.setGlobal('__lx_event', (String name, String json) => _event(name, json));
    e.setGlobal('__lx_script_info', {'name': info.name, 'description': info.description, 'version': info.version, 'author': info.author, 'homepage': info.homepage, 'rawScript': script});
    e.evaluate(lxPrelude, name: 'lx-prelude.js');
  }

  Future<String> _httpCall(String id, String url, String opts) async {
    Map<String, dynamic> o;
    try {
      o = (jsonDecode(opts) as Map).cast<String, dynamic>();
    } catch (_) {
      o = {};
    }
    final r = await lxHttp(_http, url, o);
    if (_closed || _cancelled.remove(id)) return jsonEncode({'error': '请求已取消'});
    return r;
  }

  void _event(String name, String json) {
    Object? data;
    try {
      data = jsonDecode(json);
    } catch (_) {}
    if (name == 'inited') {
      if (_inited.isCompleted) return;
      try {
        _inited.complete(validateLxInit(data));
      } catch (e) {
        _inited.completeError(e is LxException ? e : LxException('$e'));
      }
    } else if (name == 'updateAlert' && data is Map && data['log'] is String && (data['log'] as String).trim().isNotEmpty) {
      final log = data['log'] as String;
      final url = data['updateUrl'];
      updateAlert = {
        'log': log.length > 1024 ? log.substring(0, 1024) : log,
        if (url is String && RegExp(r'^https?://\S+$').hasMatch(url) && url.length <= 1024) 'updateUrl': url,
      };
      onUpdateAlert?.call(updateAlert!);
    }
  }

  /// 调用脚本的 request 处理器。musicUrl / pic 返回 http(s) 地址；lyric 返回 {lyric, tlyric, rlyric, lxlyric}。
  Future<Object?> request(String action, String platform, Map<String, dynamic> musicInfo, {String? quality, Duration timeout = const Duration(seconds: 20)}) async {
    if (_closed) throw const LxException('音源已停止');
    final info = action == 'musicUrl' ? {'type': quality, 'musicInfo': musicInfo} : {'musicInfo': musicInfo};
    final payload = jsonEncode({'source': platform, 'action': action, 'info': info});
    Object? r;
    try {
      r = _qjs.evaluate('__lx_dispatch(${jsonEncode(payload)})');
      if (r is Future) r = await r.timeout(timeout, onTimeout: () => throw const LxException('音源请求超时'));
    } on LxException {
      rethrow;
    } catch (e) {
      throw LxException(_short(e));
    }
    final value = r is String ? (jsonDecode(r) as Map)['value'] : r;
    if (action == 'musicUrl' || action == 'pic') {
      if (value is! String || value.length > 2048 || !RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
        throw LxException(action == 'pic' ? '音源返回的封面地址无效' : '音源返回的播放地址无效');
      }
      return value;
    }
    if (value is! Map || value['lyric'] is! String) throw const LxException('音源返回的歌词无效');
    return value;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    if (!_inited.isCompleted) _inited.completeError(const LxException('音源已停止'));
    try {
      _qjs.close();
    } catch (_) {
      // 关闭时的引用泄漏检查（JSError）不影响使用
    }
  }

  static String _short(Object e) {
    var m = e.toString().trim();
    m = m.replaceFirst(RegExp(r'^(JSError|Exception|Error):\s*'), '');
    return m.length > 160 ? '${m.substring(0, 160)}…' : m;
  }
}
