// 登录会话：访问令牌 / 刷新令牌 / 过期时间 + 本地持久化。
//
// 后端规则（music-player-server/src/auth.ts）：
// - 访问令牌 HS256 JWT，默认 2 小时；刷新令牌 30 天。
// - 刷新会「轮换」：旧刷新令牌立刻作废；再拿旧令牌刷新 = 重放 → 服务端吊销该用户全部会话。
//   所以客户端必须保证同一时刻只有一个刷新请求，并且拿到新令牌后先落盘再用（见 ApiClient）。
import 'dart:async';
import 'dart:convert';
import 'json.dart';
import 'storage.dart';

class AuthTokens {
  final String accessToken, refreshToken;

  /// 访问令牌过期的本地时间。
  final DateTime expiresAt;
  const AuthTokens({required this.accessToken, required this.refreshToken, required this.expiresAt});

  /// 登录 / 注册 / 刷新接口的 data：{accessToken, refreshToken, expiresIn, user}
  factory AuthTokens.fromLogin(Json j, {DateTime? now}) => AuthTokens(
        accessToken: j.str('accessToken'),
        refreshToken: j.str('refreshToken'),
        expiresAt: (now ?? DateTime.now()).add(Duration(seconds: j.integer('expiresIn', 7200))),
      );

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  /// 离过期不到 [margin] 就提前刷新，避免请求发出去时刚好过期。
  bool expiresWithin(Duration margin, DateTime now) => !expiresAt.isAfter(now.add(margin));

  Json toJson() => {'a': accessToken, 'r': refreshToken, 'e': expiresAt.millisecondsSinceEpoch};
  static AuthTokens? fromStored(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = asJson(jsonDecode(raw));
      final t = AuthTokens(accessToken: j.str('a'), refreshToken: j.str('r'), expiresAt: DateTime.fromMillisecondsSinceEpoch(j.integer('e')));
      return t.isValid ? t : null;
    } catch (_) {
      return null;
    }
  }
}

enum SessionEnd {
  /// 用户主动退出。
  logout,

  /// 刷新令牌失效 / 被吊销（其他设备改了密码、被移除设备、重放侦测等）。
  expired,
}

class Session {
  static const _key = 'auth.tokens.v1';
  final KvStore _store;
  AuthTokens? _tokens;
  final _ended = StreamController<SessionEnd>.broadcast();
  final _changed = StreamController<AuthTokens?>.broadcast();

  Session(this._store);

  AuthTokens? get tokens => _tokens;
  bool get isLoggedIn => _tokens?.isValid ?? false;

  /// 会话结束（退出 / 失效）。上层监听它跳回登录页。
  Stream<SessionEnd> get onEnd => _ended.stream;

  /// 令牌变化（登录、刷新、清除）。
  Stream<AuthTokens?> get onChanged => _changed.stream;

  /// 启动时从本地恢复。
  Future<void> restore() async => _tokens = AuthTokens.fromStored(await _store.read(_key));

  /// 登录成功 / 刷新成功后调用；先落盘再生效。
  Future<void> save(AuthTokens t) async {
    await _store.write(_key, jsonEncode(t.toJson()));
    _tokens = t;
    _changed.add(t);
  }

  Future<void> clear(SessionEnd reason) async {
    final had = _tokens != null;
    _tokens = null;
    await _store.delete(_key);
    _changed.add(null);
    if (had || reason == SessionEnd.logout) _ended.add(reason);
  }

  void dispose() {
    _ended.close();
    _changed.close();
  }
}
