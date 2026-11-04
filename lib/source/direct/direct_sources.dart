import 'dart:convert';
// 各平台直链取地址实现。每个平台一个函数，签名统一：
//
//   Future<DirectUrl?> fetch(PlatformHttp http, Json track, String lxQuality, {…})
//
// 约定：
// - 返回 null = 「拿不到」（没登录 / 非会员 / 无权限 / 响应里没有可用地址），编排层回退音源脚本；
// - 抛 DirectAuthException = 登录态失效，编排层 markExpired 后回退；
// - 网络错误抛 PlatformException（编排层原样回退，不特殊处理）；
// - 一律不绕过会员限制：VIP 歌拿不到完整地址就返回 null。

import '../../net/json.dart';
import '../../platform/credentials.dart';
import '../../platform/http.dart';
import '../../platform/models.dart';
import '../../platform/netease_crypto.dart';
import 'direct_url.dart';

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

/// 曲目的平台歌曲 id（去 `平台:` 前缀；酷我再去掉 MUSIC_）。
String directNativeId(Json track) {
  final platform = '${track['platform']}';
  final identity = asJson(track['identity']);
  final v = '${identity['id'] ?? track['id'] ?? ''}';
  var out = v.toLowerCase().startsWith('$platform:') ? v.substring(platform.length + 1) : v;
  while (out.toLowerCase().startsWith('$platform:')) {
    out = out.substring(platform.length + 1);
  }
  if (platform == 'kw') out = out.replaceFirst(RegExp(r'^MUSIC_', caseSensitive: false), '');
  return out.trim();
}

/// 曲目某个音质对应的文件 hash（酷狗用），没有返回空串。
String directHash(Json track, String lxQuality) {
  final identity = asJson(track['identity']);
  final hashes = asJson(identity['qualityHashes']);
  return '${hashes[lxQuality] ?? identity['hash'] ?? ''}'.trim();
}

/// 浏览器 UA：网易 / QQ / 酷我 / 咪咕的网页接口对 Dart 默认 UA 有拦截。
const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

Json? _asMap(Object? v) => v is Map ? asJson(v) : null;

// ---------------------------------------------------------------------------
// 网易云：eapi song/enhance/player/url
// ---------------------------------------------------------------------------

/// 有凭证走 eapi（会员歌可完整取）；没凭证用游客 Cookie（MUSIC_A）取免费歌。
/// 歌曲 fee=1（VIP 专享）且会员无效时直接返回 null。
Future<DirectUrl?> wyDirect(
  PlatformHttp http,
  Json track,
  String lxQuality, {
  PlatformCredential? cred,
  String? anonCookie,
}) async {
  final id = directNativeId(track);
  if (id.isEmpty) return null;
  final vipActive = cred?.vipActive ?? false;
  // VIP 专享歌在非会员下必然只给试听或不给：直接返回 null，省一次请求
  final qualities = [for (final q in (track['qualities'] as List? ?? const [])) '$q'];
  final feeOnly = qualities.isNotEmpty && qualities.every((q) => q == 'flac24bit' || q == 'hires') && !vipActive;
  if (feeOnly) return null;

  final cookie = cred?.cookie ?? anonCookie ?? '';
  final payload = {
    'ids': '[$id]',
    'br': DirectQuality.wyBr(lxQuality),
    'header': {'os': 'pc'},
    // e_r=false：要明文响应。eapi 响应解密没有接线，置 true 会让响应解析失败、
    // 免费 / 游客取流永远回退脚本（请求本身已由 eapi() 加密，不受影响）。
    'e_r': false,
  };
  final body = eapi('/api/song/enhance/player/url', payload);
  final res = await http.json('wy', 'POST', Uri.parse('https://interface3.music.163.com/eapi/song/enhance/player/url'),
      headers: {
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'User-Agent': _ua,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body);
  final j = _asMap(res);
  final code = (j?['code'] as num?)?.toInt() ?? 0;
  if (code == 301 || code == 302) throw const DirectAuthException('网易云登录已过期');
  if (code != 200) return null;
  final data = (j?['data'] as List? ?? const []).cast<Map>();
  if (data.isEmpty) return null;
  final first = asJson(data.first);
  final fee = (first['fee'] as num?)?.toInt() ?? 0;
  if (fee == 1 && !vipActive) return null; // VIP 专享
  final url = '${first['url'] ?? ''}';
  if (url.isEmpty) return null;
  final level = '${first['level'] ?? ''}';
  final trial = first['freeTrialInfo'] != null;
  return DirectUrl(
    url: url,
    quality: trial ? DirectQuality.clamp(lxQuality) : _wyLevelToApp(level.isEmpty ? DirectQuality.wyLevel(lxQuality) : level),
    platform: 'wy',
    trial: trial,
  );
}

String _wyLevelToApp(String level) => switch (level) {
      'standard' => '128k',
      'higher' => 'HQ',
      'exhigh' => 'HQ',
      'lossless' => 'SQ',
      'hires' => 'Hi-Res',
      'jymaster' => 'Hi-Res',
      _ => 'HQ',
    };

// ---------------------------------------------------------------------------
// QQ 音乐：musicu.fcg vkey.GetEVkey（必须有登录凭证）
// ---------------------------------------------------------------------------

/// 匿名请求 100% 失败（vkey invalidq），所以只在有凭证且带 qm_keyst 时取。
Future<DirectUrl?> txDirect(
  PlatformHttp http,
  Json track,
  String lxQuality, {
  PlatformCredential? cred,
}) async {
  final c = cred;
  if (c == null) return null;
  final uin = c.extra[CredKey.txUin] ?? c.userId ?? '';
  final keyst = c.extra[CredKey.txKeyst] ?? c.cookieValue('qm_keyst') ?? '';
  if (uin.isEmpty || keyst.isEmpty) return null;
  final identity = asJson(track['identity']);
  final mid = '${identity['strMediaMid'] ?? identity['albumMid'] ?? ''}';
  final songmid = '${identity['songId'] ?? identity['id'] ?? directNativeId(track)}';
  if (mid.isEmpty || songmid.isEmpty) return null;
  final (prefix, ext) = DirectQuality.txPrefix(lxQuality);
  final filename = '${prefix}00$mid.$ext'; // RS02/F000/M800 前缀 + 00 + mediaMid + 扩展名
  final payload = {
    'comm': {'uin': uin, 'format': 'json', 'ct': 24, 'cv': 0},
    'req_1': {
      'module': 'vkey.GetEVkey',
      'method': 'CgiGetVkey',
      'param': {
        'guid': '1',
        'songmid': [songmid],
        'filename': [filename],
        'songtype': [0],
        'uin': uin,
        'loginflag': 1,
        'platform': '20',
      },
    },
  };
  final res = await http.json('tx', 'POST', Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {'Cookie': c.cookie, 'Referer': 'https://y.qq.com/', 'User-Agent': _ua, 'Content-Type': 'application/json'}, body: jsonEncode(payload));
  final j = _asMap(res);
  final req1 = _asMap(j?['req_1']);
  final data = _asMap(req1?['data']);
  final infos = (data?['midurlinfo'] as List? ?? const []).cast<Map>();
  if (infos.isEmpty) return null;
  final info = asJson(infos.first);
  final purl = '${info['purl'] ?? ''}';
  if (purl.isEmpty) return null; // vkey 拿不到（非会员 / 无版权）
  final url = purl.startsWith('http') ? purl : 'http://ws.stream.qqmusic.qq.com/$purl';
  return DirectUrl(url: url, quality: DirectQuality.appQuality(ext == 'flac' ? 'flac' : (prefix == 'M800' ? '320k' : '128k')), platform: 'tx');
}

// ---------------------------------------------------------------------------
// 酷狗：m.kugou.com getSongInfo.php（免费歌；登录稍后接入）
// ---------------------------------------------------------------------------

Future<DirectUrl?> kgDirect(
  PlatformHttp http,
  Json track,
  String lxQuality, {
  PlatformCredential? cred,
}) async {
  final q = DirectQuality.clamp(lxQuality);
  var hash = directHash(track, q);
  if (hash.isEmpty && q != '128k') hash = directHash(track, '128k');
  if (hash.isEmpty) return null;
  final res = await http.json('kg', 'GET', Uri.parse('https://m.kugou.com/app/i/getSongInfo.php?cmd=play&hash=$hash'),
      headers: {'Referer': 'https://m.kugou.com/', 'User-Agent': _ua});
  final j = _asMap(res);
  if ((j?['status'] as num?)?.toInt() != 1) return null;
  final url = '${j?['url'] ?? ''}';
  if (url.isEmpty || !url.startsWith('http')) return null;
  // 接口不给档位回显：按请求的 hash 档位记（免费歌一般 128k / 320k）
  return DirectUrl(url: url, quality: DirectQuality.appQuality(q), platform: 'kg');
}

// ---------------------------------------------------------------------------
// 酷我：www.kuwo.cn playUrl（免登录，免费歌）
// ---------------------------------------------------------------------------

Future<DirectUrl?> kwDirect(PlatformHttp http, Json track, String lxQuality) async {
  final id = directNativeId(track);
  if (id.isEmpty) return null;
  final res = await http.json(
      'kw',
      'GET',
      Uri.parse('https://www.kuwo.cn/api/v1/www/music/playUrl?mid=$id&type=music&httpsStatus=1&reqId=0'),
      headers: {'Referer': 'https://www.kuwo.cn/', 'User-Agent': _ua, 'csrf': 'TOKEN', 'Cookie': 'Hm_lvt_vvtoken=; kw_token=TOKEN'});
  final j = _asMap(res);
  final code = (j?['code'] as num?)?.toInt() ?? 0;
  if (code != 200) return null; // VIP 歌 / 无版权：非 200
  final data = _asMap(j?['data']);
  final url = '${data?['url'] ?? ''}';
  if (url.isEmpty || !url.startsWith('http')) return null;
  // 该接口不回显档位；免费取到的通常为 128k
  return DirectUrl(url: url, quality: '128k', platform: 'kw', headers: {'Referer': 'https://www.kuwo.cn/'});
}

// ---------------------------------------------------------------------------
// 咪咕：resourceinfo 解析（免登录，免费歌；200002 = 无权限）
// ---------------------------------------------------------------------------

Future<DirectUrl?> mgDirect(PlatformHttp http, Json track, String lxQuality) async {
  final identity = asJson(track['identity']);
  final copyrightId = '${identity['copyrightId'] ?? identity['contentId'] ?? directNativeId(track)}';
  if (copyrightId.isEmpty) return null;
  final res = await http.json(
      'mg',
      'GET',
      Uri.parse('https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2&copyrightId=$copyrightId'),
      headers: {'Referer': 'https://app.c.nf.migu.cn/', 'User-Agent': _ua});
  final j = _asMap(res);
  final code = '${j?['code'] ?? ''}';
  if (code == '200002') return null; // 无权限（VIP / 无版权）
  if (code != '000000') return null;
  final data = _asMap(j?['data']);
  final resources = (data?['resourceList'] as List? ?? const []).cast<Map>();
  for (final r in resources) {
    final rl = asJson(r);
    final contents = (rl['contentList'] as List? ?? const []).cast<Map>();
    for (final c in contents) {
      final cl = asJson(c);
      final item = _asMap(cl['item']);
      final url = '${item?['url'] ?? item?['audioUrl'] ?? cl['itemLink'] ?? ''}';
      if (url.startsWith('http')) {
        return DirectUrl(
          url: url,
          quality: DirectQuality.appQuality(DirectQuality.clamp(lxQuality)),
          platform: 'mg',
          headers: {'Referer': 'https://app.c.nf.migu.cn/'},
        );
      }
    }
  }
  return null;
}

/// 直链 URL 的去重键（缓存 / 试听黑名单用）。
String directTrackKey(Json track) => '${track['platform']}:${directNativeId(track)}';

/// 直链缓存键（含音质）。
String directCacheKey(Json track, String lxQuality) => '${directTrackKey(track)}:$lxQuality';
