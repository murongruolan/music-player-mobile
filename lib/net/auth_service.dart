// 会话相关的接口：登录、刷新、退出。它们直接决定令牌的存取，所以放在网络层里；
// 注册、验证码、资料、设备管理等普通接口放在 lib/api/ 下，按页面 / 模块拆分。
import 'api_client.dart';
import 'api_error.dart';
import 'json.dart';
import 'session.dart';

/// 后端 user 对象（登录 / 注册 / 刷新 / 资料接口共用）。
class Account {
  final String uid, email, nickname;
  final String? avatarUrl, qq;
  final bool isActivated;
  final int membershipRank;
  final String membershipName;
  final DateTime? membershipExpiresAt, createdAt;

  const Account({
    required this.uid,
    required this.email,
    required this.nickname,
    this.avatarUrl,
    this.qq,
    this.isActivated = false,
    this.membershipRank = 0,
    this.membershipName = '',
    this.membershipExpiresAt,
    this.createdAt,
  });

  /// 赞助用户（已激活且会员等级 ≥ 1）。云同步、云备份、云端听歌统计都需要它，与后端 requireSponsor 一致。
  bool get isSponsor => isActivated && membershipRank >= 1;

  factory Account.fromJson(Json j) {
    final m = j.obj('membership');
    return Account(
      uid: j.str('uid'),
      email: j.str('email'),
      nickname: j.str('nickname'),
      avatarUrl: j.strOrNull('avatarUrl'),
      qq: j.strOrNull('qq'),
      isActivated: j.boolean('isActivated'),
      membershipRank: j.integer('membershipRank', m.integer('rank')),
      membershipName: m.str('name'),
      membershipExpiresAt: m.time('expiresAt'),
      createdAt: j.time('createdAt'),
    );
  }
}

class AuthService {
  final ApiClient _c;
  AuthService(this._c);

  Session get session => _c.session;

  /// 本地缓存的账号信息（启动恢复、离线时用）。
  Account? get cached {
    final u = session.user;
    return session.isLoggedIn && u != null ? Account.fromJson(u) : null;
  }

  /// 邮箱 + 密码登录。[remember] = 保持登录（令牌写入钥匙串）。失败时抛 [ApiException]：
  /// 密码错误 business/40001；连续失败被锁 rateLimited/42901；设备数超限或账号禁用 business/40301。
  Future<Account> login(String email, String password, {bool remember = true}) async {
    final data = await _c.post('/auth/login', auth: false, body: {'account': email.trim(), 'password': password, 'device': _c.device.toJson()});
    return signedIn(data, remember: remember);
  }

  /// 任何返回 {accessToken, refreshToken, expiresIn, user} 的接口（登录、注册、旧版登录）成功后都调用它：
  /// 保存令牌和用户信息、清掉上一个账号的缓存，返回用户信息。
  Future<Account> signedIn(Object? data, {bool remember = true}) async {
    final j = asJson(data);
    final t = AuthTokens.fromLogin(j);
    if (!t.isValid) throw const ApiException(ApiErrorKind.parse, '登录返回的数据不完整');
    _c.clearCache();
    await session.save(t, persist: remember);
    final user = j.obj('user');
    await session.saveUser(user);
    return Account.fromJson(user);
  }

  /// 启动时恢复会话：本地有令牌就刷新一次（顺便拿到最新的会员状态）。
  /// 返回最新账号信息；刷新令牌失效时会话被清掉（[Session.onEnd] 会通知 expired）并返回 null；
  /// 断网 / 服务器错误时保留会话，返回本地缓存的账号信息。
  Future<Account?> resume() async {
    if (!session.isLoggedIn) return null;
    try {
      await _c.refreshTokens();
    } on ApiException catch (e) {
      if (e.isUnauthorized) return null;
    }
    return cached;
  }

  /// 资料接口等拿到新的 user 对象后调用，让各处的账号信息保持一致。
  Future<Account> updateUser(Json user) async {
    await session.saveUser(user);
    return Account.fromJson(user);
  }

  /// 退出登录：通知服务端作废刷新令牌（失败也无所谓），本地一定清掉。
  Future<void> logout() async {
    final rt = session.tokens?.refreshToken;
    if (rt != null) {
      try {
        await _c.post('/auth/logout', auth: false, body: {'refreshToken': rt}, timeout: const Duration(seconds: 5));
      } on ApiException catch (_) {}
    }
    await session.clear(SessionEnd.logout);
  }
}
