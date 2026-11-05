// 歌单分享链接 / ID → (平台代码, 平台歌单 id)。规则对齐桌面端 PlatformService.resolvePlaylistUrl，
// 另外补了手机上常见的情况：分享文案里夹着链接、短链（163cn.tv / c6.y.qq.com / t.kugou.com 等）、
// 酷狗 gcid_ 链接解码成 collection_ id。
import 'dart:convert';

import '../net/json.dart';
import 'crypto_util.dart';
import 'http.dart';
import 'models.dart';

class PlaylistRef {
  final String platform; // wy / tx / kg / kw / mg
  final String id;
  const PlaylistRef(this.platform, this.id);
  @override
  bool operator ==(Object o) => o is PlaylistRef && o.platform == platform && o.id == id;
  @override
  int get hashCode => Object.hash(platform, id);
  @override
  String toString() => '$platform:$id';
}

/// 文本里的第一个 http(s) 链接（分享文案通常是「分享xxx的歌单《…》https://163cn.tv/abc (@网易云音乐)」）。
String? firstUrlIn(String text) {
  final m = RegExp(r'''https?://[^\s<>"'，。！？、（）()【】「」]+''', caseSensitive: false).firstMatch(text);
  if (m != null) return m[0];
  // 没写协议的：music.163.com/playlist?id=1
  final bare = RegExp(r'''(?:^|\s)((?:[a-z0-9-]+\.)+(?:com|cn|tv|net)/[^\s<>"'，。]*)''', caseSensitive: false).firstMatch(text);
  return bare == null ? null : 'https://${bare[1]}';
}

/// 平台前缀写法：`wy:123` / `tx：123` / `kg collection_3_...`。
PlaylistRef? parsePrefixedId(String input) {
  final m = RegExp(r'^(wy|tx|kw|kg|mg)\s*[:：\s]\s*([\w-]+)$', caseSensitive: false).firstMatch(input.trim());
  return m == null ? null : PlaylistRef(m[1]!.toLowerCase(), m[2]!);
}

/// 纯函数：从一个（已经展开短链的）链接里认出平台和歌单 id。认不出返回 null。
/// 酷狗 gcid_ 链接返回 `PlaylistRef('kg', 'gcid_xxx')`，由 [resolvePlaylistInput] 再解码。
PlaylistRef? parsePlaylistUrl(String raw) {
  final url = Uri.tryParse(raw.trim());
  if (url == null || url.host.isEmpty) return null;
  final host = url.host.toLowerCase();
  final path = '${url.path}${url.hasFragment ? '#${url.fragment}' : ''}';
  final q = url.queryParameters;
  String? digits(String? v) => v != null && RegExp(r'^\d+$').hasMatch(v) ? v : null;
  String? inPath(String pattern) => RegExp(pattern, caseSensitive: false).firstMatch(path)?.group(1);

  if (host.endsWith('163.com')) {
    // https://music.163.com/#/playlist?id=1 · /m/playlist?id=1 · /playlist/1
    final hash = RegExp(r'playlist\?(.*)$', caseSensitive: false).firstMatch(url.fragment);
    final hashId = hash == null ? null : digits(Uri.splitQueryString(hash[1]!)['id']);
    final id = hashId ?? (path.contains('playlist') ? digits(q['id']) : null) ?? inPath(r'playlist[/?#=&]+(\d+)');
    return id == null ? null : PlaylistRef(Plat.wy, id);
  }
  if (host.endsWith('qq.com')) {
    // y.qq.com/n/ryqq/playlist/1 · i.y.qq.com/n2/m/share/details/taoge.html?id=1 · ?disstid=1
    final id = inPath(r'playlist[/:]+(\d+)') ?? digits(q['id']) ?? digits(q['disstid']);
    return id == null ? null : PlaylistRef(Plat.tx, id);
  }
  if (host.endsWith('kuwo.cn')) {
    // www.kuwo.cn/playlist_detail/1 · m.kuwo.cn/newh5app/playlist_detail/1 · ?pid=1
    final id = inPath(r'playlist_detail[/:]+(\d+)') ?? digits(q['pid']) ?? digits(q['id']);
    return id == null ? null : PlaylistRef(Plat.kw, id);
  }
  if (host.endsWith('kugou.com')) {
    final collection = RegExp(r'(collection_[a-z0-9_]+)', caseSensitive: false).firstMatch(raw)?.group(1);
    if (collection != null) return PlaylistRef(Plat.kg, collection);
    final gcid = RegExp(r'(?:^|/)(gcid_[a-z0-9_]+)(?:/|$)', caseSensitive: false).firstMatch(url.path)?.group(1);
    if (gcid != null) return PlaylistRef(Plat.kg, gcid);
    final id = inPath(r'(?:special|songlist)[^\d]*(\d+)') ?? digits(q['specialid']) ?? digits(q['id']);
    return id == null ? null : PlaylistRef(Plat.kg, id);
  }
  if (host.endsWith('migu.cn')) {
    // music.migu.cn/v3/music/playlist/1 · h5.nf.migu.cn/...?id=1 · ?playlistId=1
    final id = inPath(r'playlist[/:]+(\d+)') ?? digits(q['playlistId']) ?? digits(q['id']);
    return id == null ? null : PlaylistRef(Plat.mg, id);
  }
  return null;
}

class PlaylistLinkException implements Exception {
  final String message;
  const PlaylistLinkException(this.message);
  @override
  String toString() => message;
}

/// 用户输入（链接 / 分享文案 / 带前缀的 id / 纯 id）→ 歌单引用。
/// 纯 id 用 [fallbackPlatform]。需要联网的步骤：短链展开、酷狗 gcid 解码。
Future<PlaylistRef> resolvePlaylistInput(String input, {required PlatformHttp http, required String fallbackPlatform}) async {
  final text = input.trim();
  if (text.isEmpty) throw const PlaylistLinkException('请粘贴歌单链接或输入歌单 ID');
  final prefixed = parsePrefixedId(text);
  if (prefixed != null) return _finish(prefixed, http);
  final url = firstUrlIn(text);
  if (url == null) {
    if (RegExp(r'^[\w-]+$').hasMatch(text)) return _finish(PlaylistRef(fallbackPlatform, text), http);
    throw const PlaylistLinkException('没有找到歌单链接，请粘贴完整的分享链接或歌单 ID');
  }
  var current = url;
  for (var hop = 0; hop < 4; hop++) {
    final hit = parsePlaylistUrl(current);
    if (hit != null) return _finish(hit, http);
    final u = Uri.tryParse(current);
    if (u == null) break;
    // 认不出来：可能是短链 / 中转页，跟一次跳转（不跟就认不出的才请求网络）
    final next = await http.redirectOf(_platformOfHost(u.host), u);
    if (next == null || next.toString() == current) break;
    current = next.toString();
  }
  throw const PlaylistLinkException('暂不支持此链接，请粘贴网易云、QQ、酷狗、酷我或咪咕的歌单链接');
}

String _platformOfHost(String host) {
  host = host.toLowerCase();
  if (host.contains('163')) return Plat.wy;
  if (host.contains('qq')) return Plat.tx;
  if (host.contains('kugou')) return Plat.kg;
  if (host.contains('kuwo')) return Plat.kw;
  if (host.contains('migu')) return Plat.mg;
  return 'link';
}

Future<PlaylistRef> _finish(PlaylistRef r, PlatformHttp http) async {
  if (r.platform == Plat.kg && r.id.toLowerCase().startsWith('gcid_')) return PlaylistRef(Plat.kg, await decodeKugouGcid(http, r.id));
  return r;
}

/// 酷狗 gcid_xxx → collection_xxx（t.kugou.com songlist/batch_decode，签名同桌面端）。
Future<String> decodeKugouGcid(PlatformHttp http, String gcid) async {
  const params = 'dfid=-&appid=1005&mid=0&clientver=20109&clienttime=640612895&uuid=-';
  final body = jsonEncode({
    'ret_info': 1,
    'data': [
      {'id': gcid, 'id_type': 2}
    ]
  });
  const key = 'OIlwieks28dk2k092lksi2UIkp';
  final sorted = (params.split('&')..sort()).join();
  final sig = md5Hex('$key$sorted$body$key');
  final res = await http.json(Plat.kg, 'POST', Uri.parse('https://t.kugou.com/v1/songlist/batch_decode?$params&signature=$sig'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; HUAWEI HMA-AL00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Mobile Safari/537.36',
        'Referer': 'https://m.kugou.com/',
      },
      body: body);
  final list = asJson(asJson(res)['data'])['list'];
  final first = list is List && list.isNotEmpty ? asJson(list.first) : const <String, dynamic>{};
  final id = '${first['global_collection_id'] ?? ''}';
  if (!RegExp(r'^collection_[a-z0-9_]+$', caseSensitive: false).hasMatch(id)) throw const PlaylistLinkException('酷狗歌单链接解析失败');
  return id;
}
