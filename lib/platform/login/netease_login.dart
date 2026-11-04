// 网易云音乐登录：扫码（unikey 轮询）、导入 Cookie、游客 Cookie（MUSIC_A）。
// 流程对齐原版 App（netease_cloud_api / netease_anonymous_cookie_service / netease_cookie_utils）。
//
// 网络注意：部分出口会把 /weapi、/eapi 整条路径拦掉（返回 200 空体，桌面端 2026-11-01 实测），
// 明文 /api 不受影响。所以扫码的两个接口先走 weapi，返回空体 / 非 JSON 时退回明文 /api；
// 账号信息只走明文 /api。
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' show md5;
import '../../net/json.dart';
import '../credentials.dart';
import '../http.dart';
import '../models.dart';
import '../netease_crypto.dart';

/// 扫码登录轮询状态。
enum NeteaseQrState {
  /// 等待扫码（801）。
  waiting,

  /// 已扫码，等手机上确认（802）。
  scanned,

  /// 授权成功（803），[NeteaseQrPoll.cookie] 有值。
  ok,

  /// 二维码过期（800），需要重新取。
  expired,

  /// 其它返回码。
  failed,
}

class NeteaseQrPoll {
  final NeteaseQrState state;
  final String cookie, message, nickname, avatarUrl;
  const NeteaseQrPoll(this.state, {this.cookie = '', this.message = '', this.nickname = '', this.avatarUrl = ''});
}

/// Set-Cookie 属性名：清洗时丢掉（原版黑名单 11 项，精确匹配）。
const _cookieAttrs = {'path', 'domain', 'max-age', 'expires', 'secure', 'httponly', 'samesite', 'priority', 'partitioned', 'comment', 'version'};

/// 原版 sanitizeNeteaseCookie：按 `;` 分段 → 去掉段首逗号 → 按第一个 `=` 切 → 丢掉 Set-Cookie 属性 → 用 `; ` 拼回。
String sanitizeNeteaseCookie(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final out = <String>[];
  final seen = <String>{};
  for (var part in s.split(';')) {
    part = part.trim();
    if (part.startsWith(',')) part = part.substring(1).trim();
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final k = part.substring(0, i).trim(), v = part.substring(i + 1).trim();
    if (_cookieAttrs.contains(k.toLowerCase())) continue;
    // Set-Cookie 串里同名项会出现多次（各个域名），只留第一个
    if (!seen.add(k)) continue;
    out.add('$k=$v');
  }
  return out.join('; ');
}

/// 登录态判定：清洗后带 MUSIC_U。
bool hasNeteaseMusicU(String cookie) => RegExp(r'(?:^|;\s*)MUSIC_U=[^;]+').hasMatch(sanitizeNeteaseCookie(cookie));

class NeteaseLogin {
  final PlatformHttp http;
  final Random _random;
  NeteaseLogin(this.http, {Random? random}) : _random = random ?? Random.secure();

  static const _host = 'https://music.163.com';
  static const _headers = {'Origin': 'https://music.163.com', 'Referer': 'https://music.163.com/'};

  /// 二维码内容（网易云 App 扫这个）。
  static String qrContent(String unikey) => 'https://music.163.com/login?codekey=$unikey';

  /// weapi 优先，被拦截（空体 / 非 JSON）时退回明文 /api。[path] 形如 `/login/qrcode/unikey`。
  Future<Json> _post(String path, Map<String, Object?> payload, {String? cookie}) async {
    final h = {..._headers, if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie};
    try {
      final j = asJson(await http.postForm(Plat.wy, '$_host/weapi$path', weapi(payload), headers: h));
      if (j.isNotEmpty) return j;
    } on PlatformException catch (e) {
      // HTTP 错误码直接抛；格式错误（空体）才退回明文
      if (!e.message.contains('格式')) rethrow;
    }
    final form = {for (final e in payload.entries) e.key: '${e.value}'};
    return asJson(await http.postForm(Plat.wy, '$_host/api$path', form, headers: h));
  }

  /// ① 取二维码 key。
  Future<String> qrKey() async {
    final j = await _post('/login/qrcode/unikey', {'type': 1});
    final key = j.str('unikey', asJson(j['data']).str('unikey'));
    if (key.isEmpty) throw const PlatformException(Plat.wy, '获取二维码 key 失败');
    return key;
  }

  /// ② 轮询一次扫码状态（建议 2~3 秒一次）。
  Future<NeteaseQrPoll> qrCheck(String key) async {
    final j = await _post('/login/qrcode/client/login', {'key': key, 'type': 1});
    final code = int.tryParse('${j['code']}');
    final msg = j.str('message', j.str('msg'));
    return switch (code) {
      800 => NeteaseQrPoll(NeteaseQrState.expired, message: msg.isEmpty ? '二维码已过期' : msg),
      801 => const NeteaseQrPoll(NeteaseQrState.waiting),
      802 => NeteaseQrPoll(NeteaseQrState.scanned, nickname: j.str('nickname'), avatarUrl: j.str('avatarUrl')),
      803 => NeteaseQrPoll(NeteaseQrState.ok, cookie: sanitizeNeteaseCookie(j.str('cookie')), nickname: j.str('nickname'), avatarUrl: j.str('avatarUrl')),
      _ => NeteaseQrPoll(NeteaseQrState.failed, message: msg.isEmpty ? '扫码登录失败（$code）' : msg),
    };
  }

  /// 用 Cookie 拉账号信息并生成凭证。Cookie 无效（没有 MUSIC_U / 接口说未登录）时抛 [PlatformException]。
  Future<PlatformCredential> credentialFrom(String rawCookie) async {
    final cookie = sanitizeNeteaseCookie(rawCookie);
    if (!hasNeteaseMusicU(cookie)) throw const PlatformException(Plat.wy, 'Cookie 里没有 MUSIC_U，请确认是登录后的网易云 Cookie');
    final j = asJson(await http.postForm(Plat.wy, '$_host/api/nuser/account/get', const <String, String>{}, headers: {..._headers, 'Cookie': cookie}));
    final profile = asJson(j['profile']), account = asJson(j['account']);
    if (j.integer('code') != 200 || profile.isEmpty) throw const PlatformException(Plat.wy, '网易云登录已失效，请重新登录');
    final vipType = account.integer('vipType', profile.integer('vipType'));
    final csrf = _cookieValue(cookie, '__csrf');
    return PlatformCredential(
      platform: Plat.wy,
      cookie: cookie,
      userId: profile.str('userId', account.str('id')),
      nickname: profile.str('nickname'),
      avatarUrl: profile.str('avatarUrl'),
      isVip: vipType > 0,
      vipLabel: vipType > 0 ? '黑胶 VIP' : null,
      extra: {if (csrf != null) CredKey.wyCsrf: csrf},
      savedAt: DateTime.now(),
    );
  }

  /// 游客 Cookie：随机设备 id（52 位大写十六进制）→ 用户名 = base64("设备id 编码id") → /register/anonimous。
  /// 编码 id = base64(md5(设备id 按 `3go8&$8*3*3h0k(2)2` 异或))，和开源客户端（NeteaseCloudMusicApi）一致；
  /// 直接把设备 id 当用户名会被拒（实测 code=400）。MUSIC_A 可能在响应体的 cookie 字段，也可能只在 Set-Cookie 头里。
  Future<String> anonymousCookie() async {
    final deviceId = List.generate(52, (_) => _random.nextInt(16).toRadixString(16).toUpperCase()).join();
    final username = anonymousUsername(deviceId);
    final res = await http.send(Plat.wy, 'POST', Uri.parse('$_host/weapi/register/anonimous'),
        headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}, body: weapi({'username': username}));
    final j = asJson(PlatformHttp.decodeJson(Plat.wy, utf8.decode(res.bodyBytes, allowMalformed: true)));
    // http 包把多个 Set-Cookie 用逗号拼在一起，清洗时会处理段首逗号
    final cookie = sanitizeNeteaseCookie([j.str('cookie'), res.headers['set-cookie'] ?? ''].where((x) => x.isNotEmpty).join('; ').replaceAll(RegExp(r',(?=\s*[A-Za-z_][A-Za-z0-9_]*=)'), ';'));
    if (_cookieValue(cookie, 'MUSIC_A') == null) throw PlatformException(Plat.wy, 'registerAnonymousCookie failed: code=${j['code']}');
    return cookie;
  }

  static String anonymousUsername(String deviceId) {
    const k = '3go8&\$8*3*3h0k(2)2';
    final xored = String.fromCharCodes([for (var i = 0; i < deviceId.length; i++) deviceId.codeUnitAt(i) ^ k.codeUnitAt(i % k.length)]);
    final encoded = base64Encode(md5.convert(utf8.encode(xored)).bytes);
    return base64Encode(utf8.encode('$deviceId $encoded'));
  }

  static String? _cookieValue(String cookie, String name) {
    for (final part in cookie.split(';')) {
      final i = part.indexOf('=');
      if (i > 0 && part.substring(0, i).trim() == name) return part.substring(i + 1).trim();
    }
    return null;
  }
}
