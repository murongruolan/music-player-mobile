// 平台登录凭证：登录层（lib/platform/login/、平台账号页）写入，直链层（lib/source/direct/）等只读。
//
// 这是两边的接口约定：
// - 本文件归登录层维护；直链层需要新字段时在 PR 里提出，由登录层添加。
// - 凭证存系统钥匙串（Net.store），只留在本机：不进日志、埋点、云同步、备份。
//   需要在界面 / 日志里显示 Cookie 时用 [maskSecret]。
// - 平台代码见 Plat：wy 网易云、tx QQ音乐、kg 酷狗。酷我 / 咪咕没有登录。
import 'dart:async';
import 'dart:convert';
import '../net/storage.dart';
import 'registry.dart' show PlatformHub;

/// [PlatformCredential.extra] 里各平台的字段名。登录层负责填，直链层按需读。
abstract final class CredKey {
  /// 网易云：Cookie 里的 __csrf（weapi 请求体的 csrf_token）。
  static const wyCsrf = '__csrf';

  /// QQ：uin（数字或 o 开头）、euin、qm_keyst（会员取链要用）。
  static const txUin = 'uin', txEuin = 'euin', txKeyst = 'qm_keyst';

  /// 酷狗：登录返回的 token / vip_token，以及登录时用的设备参数 dfid / mid。
  static const kgToken = 'token', kgVipToken = 'vip_token', kgDfid = 'dfid', kgMid = 'mid';
}

/// 一个平台的登录凭证。
class PlatformCredential {
  /// 平台代码（wy / tx / kg）。
  final String platform;

  /// 发请求时整串放进 Cookie 头的值（已清洗，形如 `a=1; b=2`）。
  final String cookie;

  final String? userId, nickname, avatarUrl;

  /// 是否平台会员（登录或刷新资料时由平台接口给出；不确定时为 false）。
  final bool isVip;

  /// 会员名称（如「黑胶 VIP」「绿钻」）和到期时间，可能为空。
  final String? vipLabel;
  final DateTime? vipExpiresAt;

  /// 各平台的额外字段，键见 [CredKey]。
  final Map<String, String> extra;

  /// 保存时间。
  final DateTime savedAt;

  const PlatformCredential({
    required this.platform,
    required this.cookie,
    this.userId,
    this.nickname,
    this.avatarUrl,
    this.isVip = false,
    this.vipLabel,
    this.vipExpiresAt,
    this.extra = const {},
    required this.savedAt,
  });

  /// 会员是否仍在有效期内（没有到期时间时按 [isVip] 算）。
  bool get vipActive => isVip && (vipExpiresAt == null || vipExpiresAt!.isAfter(DateTime.now()));

  /// 从 [cookie] 里取某一项的值（区分大小写）。
  String? cookieValue(String name) {
    for (final part in cookie.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      if (part.substring(0, i).trim() == name) return part.substring(i + 1).trim();
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'platform': platform,
        'cookie': cookie,
        if (userId != null) 'userId': userId,
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'isVip': isVip,
        if (vipLabel != null) 'vipLabel': vipLabel,
        if (vipExpiresAt != null) 'vipExpiresAt': vipExpiresAt!.toIso8601String(),
        if (extra.isNotEmpty) 'extra': extra,
        'savedAt': savedAt.toIso8601String(),
      };

  static PlatformCredential? fromJson(Object? j) {
    if (j is! Map) return null;
    final platform = '${j['platform'] ?? ''}', cookie = '${j['cookie'] ?? ''}';
    if (platform.isEmpty || cookie.isEmpty) return null;
    String? s(String k) => j[k] == null ? null : '${j[k]}';
    final ex = j['extra'];
    return PlatformCredential(
      platform: platform,
      cookie: cookie,
      userId: s('userId'),
      nickname: s('nickname'),
      avatarUrl: s('avatarUrl'),
      isVip: j['isVip'] == true,
      vipLabel: s('vipLabel'),
      vipExpiresAt: DateTime.tryParse(s('vipExpiresAt') ?? ''),
      extra: ex is Map ? {for (final e in ex.entries) '${e.key}': '${e.value}'} : const {},
      savedAt: DateTime.tryParse(s('savedAt') ?? '') ?? DateTime.now(),
    );
  }
}

/// 读取凭证的接口。直链层只用这几个方法。
abstract class CredentialStore {
  /// 某个平台（平台代码或 App 平台 id 都行）当前可用的凭证；没登录或已被标记失效时返回 null。
  PlatformCredential? of(String platform);

  /// 免登录的游客 Cookie（目前只有网易云的 MUSIC_A）；没有时返回 null。
  String? anonymousCookie(String platform);

  /// 凭证变化（登录、退出、刷新、被标记失效）时发出平台代码。
  Stream<String> get changes;

  /// 使用方发现凭证失效（接口返回未登录 / 过期）时调用：之后 [of] 返回 null，
  /// 登录层据 [expiredReason] 提示用户重新登录。
  Future<void> markExpired(String platform, String reason);

  /// 被标记失效的原因；没有失效时为 null。
  String? expiredReason(String platform);
}

/// 凭证存储：登录层用 [save] / [remove] / [saveAnonymous] 写，其余模块只经 [CredentialStore] 读。
/// [store] 正式运行传系统钥匙串（Net.store），测试 / 演示传 MemoryKvStore 或 null（只在内存里）。
class PlatformCredentials implements CredentialStore {
  final KvStore? _store;
  PlatformCredentials(this._store);

  static const _k = 'platform.credentials.v1';
  final _creds = <String, PlatformCredential>{};
  final _anon = <String, String>{};
  final _expired = <String, String>{};
  final _changes = StreamController<String>.broadcast();

  static String _code(String p) => PlatformHub.codeOf(p);

  /// 启动时从钥匙串读回。
  Future<void> load() async {
    final s = _store;
    if (s == null) return;
    try {
      final j = jsonDecode(await s.read(_k) ?? '{}');
      if (j is! Map) return;
      for (final c in (j['creds'] as List? ?? const [])) {
        final x = PlatformCredential.fromJson(c);
        if (x != null) _creds[x.platform] = x;
      }
      final a = j['anon'];
      if (a is Map) _anon.addAll({for (final e in a.entries) '${e.key}': '${e.value}'});
      final e = j['expired'];
      if (e is Map) _expired.addAll({for (final x in e.entries) '${x.key}': '${x.value}'});
    } catch (_) {
      // 数据损坏：当作没登录
    }
  }

  /// 已保存的全部平台（含已失效的），平台账号页用。
  List<PlatformCredential> get all => _creds.values.toList();

  /// 不管是否失效，取保存的凭证（平台账号页显示「需要重新登录」用）。
  PlatformCredential? saved(String platform) => _creds[_code(platform)];

  @override
  PlatformCredential? of(String platform) {
    final c = _code(platform);
    return _expired.containsKey(c) ? null : _creds[c];
  }

  @override
  String? anonymousCookie(String platform) => _anon[_code(platform)];

  @override
  Stream<String> get changes => _changes.stream;

  @override
  String? expiredReason(String platform) => _expired[_code(platform)];

  @override
  Future<void> markExpired(String platform, String reason) async {
    final c = _code(platform);
    if (!_creds.containsKey(c) || _expired[c] == reason) return;
    _expired[c] = reason;
    await _persist(c);
  }

  /// 登录 / 刷新成功：保存并清除失效标记。
  Future<void> save(PlatformCredential cred) async {
    final c = _code(cred.platform);
    _creds[c] = cred;
    _expired.remove(c);
    await _persist(c);
  }

  /// 退出登录。
  Future<void> remove(String platform) async {
    final c = _code(platform);
    if (_creds.remove(c) == null && _expired.remove(c) == null) return;
    _expired.remove(c);
    await _persist(c);
  }

  /// 保存 / 清除游客 Cookie。
  Future<void> saveAnonymous(String platform, String? cookie) async {
    final c = _code(platform);
    if (cookie == null || cookie.isEmpty) {
      _anon.remove(c);
    } else {
      _anon[c] = cookie;
    }
    await _persist(c);
  }

  Future<void> _persist(String changed) async {
    _changes.add(changed);
    await _store?.write(_k, jsonEncode({'creds': [for (final c in _creds.values) c.toJson()], 'anon': _anon, 'expired': _expired}));
  }

  void dispose() => _changes.close();
}

/// 显示 / 记日志用：只留前 4 位和后 2 位，中间打码。
String maskSecret(String s) {
  if (s.length <= 8) return '*' * s.length;
  return '${s.substring(0, 4)}${'*' * 6}${s.substring(s.length - 2)}';
}
