// 接口地址与超时。
//
// 默认地址可在构建时覆盖：flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api/v1
// 运行时也可以改（设置 → 开发者选项之类的入口调用 [ApiConfig.setOverride]），会持久化。
import 'storage.dart';

class ApiConfig {
  static const defaultBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://player-api.0996996.xyz/api/v1');
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
  static const buildNumber = String.fromEnvironment('BUILD_NUMBER', defaultValue: '1');
  static const _overrideKey = 'api.baseUrl.override.v1';

  final KvStore _store;
  String _baseUrl;

  /// 单次请求的总超时（连接 + 等待响应 + 读完响应体）。
  final Duration timeout;

  ApiConfig(this._store, {String? baseUrl, this.timeout = const Duration(seconds: 15)}) : _baseUrl = _normalize(baseUrl ?? defaultBaseUrl);

  String get baseUrl => _baseUrl;
  bool get isOverridden => _baseUrl != _normalize(defaultBaseUrl);

  /// 启动时读取运行时覆盖的地址。
  Future<void> load() async {
    final v = await _store.read(_overrideKey);
    if (v != null && _valid(v)) _baseUrl = _normalize(v);
  }

  /// 传 null 恢复默认。地址不合法时抛 [FormatException]。
  Future<void> setOverride(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _store.delete(_overrideKey);
      _baseUrl = _normalize(defaultBaseUrl);
      return;
    }
    if (!_valid(url.trim())) throw FormatException('接口地址不合法', url);
    _baseUrl = _normalize(url.trim());
    await _store.write(_overrideKey, _baseUrl);
  }

  /// 拼出完整地址。[path] 以 / 开头，相对于 baseUrl（如 '/auth/login'）。
  Uri uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{
      if (query != null)
        for (final e in query.entries)
          if (e.value != null) e.key: e.value.toString(),
    };
    final u = Uri.parse('$_baseUrl${path.startsWith('/') ? path : '/$path'}');
    return q.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  static bool _valid(String s) {
    final u = Uri.tryParse(s);
    return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
  }

  static String _normalize(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
