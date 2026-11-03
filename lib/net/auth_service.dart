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

  /// 邮箱 + 密码登录。失败时抛 [ApiException]：
  /// 密码错误 business/40001；连续失败被锁 rateLimited/42901；设备数超限或账号禁用 business/40301。
  Future<Account> login(String account, String password) async {
    final data = await _c.post('/auth/login', auth: false, body: {'account': account.trim(), 'password': password, 'device': _c.device.toJson()});
    return signedIn(data);
  }

  /// 任何返回 {accessToken, refreshToken, expiresIn, user} 的接口（登录、注册、旧版登录）成功后都调用它：
  /// 保存令牌、清掉上一个账号的缓存，返回用户信息。
  Future<Account> signedIn(Object? data) async {
    final j = asJson(data);
    final t = AuthTokens.fromLogin(j);
    if (!t.isValid) throw const ApiException(ApiErrorKind.parse, '登录返回的数据不完整');
    _c.clearCache();
    await session.save(t);
    return Account.fromJson(j.obj('user'));
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
