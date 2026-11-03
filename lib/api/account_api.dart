// 账号中心：资料、QQ 绑定、激活码（AccountPage / MePage 顶部账号卡）。
// 用户模型复用网络层的 [Account]（登录 / 注册 / 刷新 / 资料接口共用同一结构）。
import '../net/net.dart';

class AccountApi {
  final ApiClient _c;
  AccountApi(this._c);

  /// 当前用户资料。变化少：缓存 30 秒，断网 / 服务器错误时回退旧值。
  Future<Account> profile() => _c.get(
        '/auth/profile',
        cacheTtl: const Duration(seconds: 30),
        staleOnError: true,
        decode: (d) => Account.fromJson(asJson(d)),
      );

  /// 修改资料，返回更新后的用户。
  /// [nickname] ≤ 64 字符；[uid] 仅赞助用户可改且仅一次（5-16 位数字），传 null 表示不改。
  Future<Account> updateProfile({String? nickname, String? uid}) async {
    final d = await _c.put('/auth/profile', body: {
      if (nickname != null) 'nickname': nickname,
      if (uid != null) 'uid': uid,
    });
    return Account.fromJson(asJson(d));
  }

  /// 绑定 / 更新 QQ（≤12 位数字）；传 null 解绑。返回更新后的用户。
  Future<Account> bindQQ(String? qq) async {
    final d = qq == null ? await _c.delete('/auth/profile/qq') : await _c.put('/auth/profile/qq', body: {'qq': qq});
    return Account.fromJson(asJson(d));
  }

  /// 兑换激活码 / 升级码（码的类型由服务端按码决定，走同一个端点）。返回更新后的用户。
  /// 无效 / 已被使用会抛 business 错误，直接展示 e.userMessage。
  Future<Account> redeemCode(String code) async {
    final d = await _c.post('/codes/activate', body: {'code': code.trim()});
    _c.clearCache('/auth/profile');
    return Account.fromJson(asJson(d).obj('user'));
  }
}
