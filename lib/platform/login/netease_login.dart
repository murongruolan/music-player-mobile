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
  /// 游客 Cookie（MUSIC_A），有的话带上，请求看起来更像正常客户端。
  final String? Function()? anonCookie;

  /// 登录过程日志（写进应用日志；不含 Cookie 原文）。
  void Function(String msg)? log;

  NeteaseLogin(this.http, {Random? random, this.anonCookie, this.log}) : _random = random ?? Random.secure();

  static const _host = 'https://music.163.com';
  static const _eapiHost = 'https://interface.music.163.com';
  static const _headers = {'Origin': 'https://music.163.com', 'Referer': 'https://music.163.com/'};
  static const _pcUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.17.204416 Safari/537.36';

  /// 本次运行的设备 id：二维码 chainId 和 eapi 请求头里都用它，同一次扫码必须一致。
  late final String deviceId = List.generate(32, (_) => _random.nextInt(16).toRadixString(16).toUpperCase()).join();

  /// 这次取 key 走的通道（轮询必须用同一条）：true = eapi（PC 客户端风格），false = 旧 weapi。
  bool _eapiQr = true;

  /// 二维码内容（网易云 App 扫这个）。eapi 通道要带 chainId，
  /// 不带的话扫码确认后会被风控拦下（8821「请切换其他登录方式或升级新版本再试」）。
  String qrContent(String unikey) => _eapiQr
      ? 'https://music.163.com/login?codekey=$unikey&chainId=v1_${deviceId}_pc_login_${DateTime.now().millisecondsSinceEpoch}'
      : 'https://music.163.com/login?codekey=$unikey';

  /// PC 客户端风格的 eapi 请求：客户端信息同时放进 Cookie 和 payload.header。返回（响应 JSON，Set-Cookie 原文）。
  Future<(Json, String)> _eapiPost(String api, Map<String, Object?> payload) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final musicA = RegExp(r'MUSIC_A=([^;]+)').firstMatch(anonCookie?.call() ?? '')?.group(1);
    final header = <String, String>{
      'os': 'pc',
      'appver': '3.1.17.204416',
      'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
      'deviceId': deviceId,
      'sDeviceId': deviceId,
      'versioncode': '140',
      'buildver': '${now ~/ 1000}',
      'resolution': '1920x1080',
      'channel': 'netease',
      '__csrf': '',
      'requestId': '${now}_${_random.nextInt(1000).toString().padLeft(4, '0')}',
      if (musicA != null) 'MUSIC_A': musicA,
    };
    final res = await http.send(Plat.wy, 'POST', Uri.parse('$_eapiHost/eapi${api.substring(4)}'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': _pcUa,
          'Cookie': header.entries.map((e) => '${e.key}=${e.value}').join('; '),
        },
        body: eapi(api, {...payload, 'header': header, 'e_r': false}));
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    return (asJson(PlatformHttp.decodeJson(Plat.wy, text)), res.headers['set-cookie'] ?? '');
  }

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
    // 先走 eapi（PC 客户端 type=3，现在官方客户端用的方式）；空体 / 失败再退回旧 weapi（type=1）
    try {
      final (j, _) = await _eapiPost('/api/login/qrcode/unikey', {'type': 3});
      final key = j.str('unikey', asJson(j['data']).str('unikey'));
      log?.call('取二维码 key（eapi）：code=${j['code']}${key.isEmpty ? '' : '，成功'}');
      if (key.isNotEmpty) {
        _eapiQr = true;
        return key;
      }
    } catch (e) {
      log?.call('取二维码 key（eapi）失败：$e');
    }
    final j = await _post('/login/qrcode/unikey', {'type': 1});
    final key = j.str('unikey', asJson(j['data']).str('unikey'));
    log?.call('取二维码 key（weapi）：code=${j['code']}${key.isEmpty ? '' : '，成功'}');
    if (key.isEmpty) throw const PlatformException(Plat.wy, '获取二维码 key 失败');
    _eapiQr = false;
    return key;
  }

  /// ② 轮询一次扫码状态（建议 2~3 秒一次）。
  Future<NeteaseQrPoll> qrCheck(String key) async {
    Json j;
    var setCookie = '';
    if (_eapiQr) {
      (j, setCookie) = await _eapiPost('/api/login/qrcode/client/login', {'key': key, 'type': 3});
    } else {
      j = await _post('/login/qrcode/client/login', {'key': key, 'type': 1});
    }
    final code = int.tryParse('${j['code']}');
    final msg = j.str('message', j.str('msg'));
    if (code != 801) log?.call('扫码状态（${_eapiQr ? 'eapi' : 'weapi'}）：code=$code${msg.isEmpty ? '' : ' $msg'}');
    // 803 时 Cookie 可能只在 Set-Cookie 头里（eapi 通道常见）
    if (code == 803 && !hasNeteaseMusicU(j.str('cookie')) && setCookie.isNotEmpty) {
      j = {...j, 'cookie': setCookie.replaceAll(RegExp(r',(?=\s*[A-Za-z_][A-Za-z0-9_]*=)'), ';')};
    }
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
