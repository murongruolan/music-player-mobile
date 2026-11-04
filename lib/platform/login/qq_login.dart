// QQ音乐登录：只支持导入 Cookie（原版 App 也只有这一种）。
// 流程：规范化 Cookie → 取 uin / euin → 用 Cookie 请求个人主页接口验证并拿昵称头像 → 生成凭证。
import '../../net/json.dart';
import '../credentials.dart';
import '../http.dart';
import '../models.dart';

// 原版的三个正则（区分大小写）
final _reUin = RegExp(r'(?:^|;)\s*uin=(\d+|o[A-Za-z0-9_-]+)');
final _reWx = RegExp(r'(?:^|;)\s*(?:wxUin|wxuin)=(\d+|[A-Za-z0-9_-]+)');
final _reEuin = RegExp(r'(?:^|;)\s*euin=([^;]+)');

/// 原版 normalizeQqCookie：按 `;` 分段 → trim → 跳过没有 `=` 的段 → 用 `; ` 拼回。
String normalizeQqCookie(String raw) => [
      for (final p in raw.split(';'))
        if (p.trim().contains('=') && p.trim().indexOf('=') > 0) p.trim(),
    ].join('; ');

/// Cookie 里的 uin：`o0123456` 这种形式去掉前缀 o 和前导 0。微信登录的 wxuin 原样返回。
String? qqUinOf(String cookie) {
  final m = _reUin.firstMatch(cookie)?.group(1);
  if (m != null) {
    final n = m.startsWith('o') ? m.substring(1) : m;
    final d = n.replaceFirst(RegExp(r'^0+'), '');
    return d.isEmpty ? null : d;
  }
  return _reWx.firstMatch(cookie)?.group(1);
}

String? qqEuinOf(String cookie) => _reEuin.firstMatch(cookie)?.group(1)?.trim();

/// 会员取链要用的登录 key：新版 Cookie 叫 qm_keyst，旧版叫 qqmusic_key。
String? qqKeystOf(String cookie) {
  for (final name in const ['qm_keyst', 'qqmusic_key']) {
    final m = RegExp('(?:^|;)\\s*$name=([^;]+)').firstMatch(cookie)?.group(1)?.trim();
    if (m != null && m.isNotEmpty) return m;
  }
  return null;
}

class QqLogin {
  final PlatformHttp http;
  QqLogin(this.http);

  /// 验证 Cookie 并生成凭证。无效时抛 [PlatformException]（文案沿用原版）。
  Future<PlatformCredential> credentialFrom(String rawCookie) async {
    final cookie = normalizeQqCookie(rawCookie);
    final uin = qqUinOf(cookie);
    if (uin == null) throw const PlatformException(Plat.tx, 'QQ Music Cookie 中未找到 UIN');
    final euin = qqEuinOf(cookie);
    final keyst = qqKeystOf(cookie);
    final url = Uri.https('c.y.qq.com', '/rsc/fcgi-bin/fcg_get_profile_homepage.fcg', {
      'format': 'json',
      'cid': '205360838',
      'userid': uin,
      'reqfrom': '1',
      'loginUin': uin,
      'hostUin': '0',
    });
    final j = asJson(await http.json(Plat.tx, 'GET', url, headers: {'Referer': 'https://y.qq.com/', 'Cookie': cookie}));
    final code = j.integer('code', -1);
    // 1000 = 未登录 / Cookie 失效
    if (code == 1000) throw const PlatformException(Plat.tx, 'QQ Music 登录已过期，请重新登录');
    if (code != 0) throw PlatformException(Plat.tx, '验证失败（返回码 $code）');
    final creator = asJson(asJson(j['data'])['creator']);
    final nick = creator.str('nick');
    final head = creator.str('headpic');
    final euinFinal = euin ?? creator.str('encrypt_uin');
    if (euinFinal.isEmpty) throw const PlatformException(Plat.tx, 'QQ Music Cookie 中缺少 euin');
    return PlatformCredential(
      platform: Plat.tx,
      cookie: cookie,
      userId: uin,
      nickname: nick.isEmpty ? 'QQ $uin' : nick,
      avatarUrl: head.isEmpty ? null : head.replaceFirst('http://', 'https://'),
      // 个人主页接口不返回会员状态；直链层按 qm_keyst 是否存在决定能不能取会员链接
      isVip: false,
      extra: {CredKey.txUin: uin, CredKey.txEuin: euinFinal, if (keyst != null) CredKey.txKeyst: keyst},
      savedAt: DateTime.now(),
    );
  }
}
