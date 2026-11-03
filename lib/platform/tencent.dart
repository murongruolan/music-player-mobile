// QQ 音乐（tx）。逐个对齐桌面端 platform-service.ts 的 *Tencent 方法、normalizeTencent* 与质量辅助函数，
// 以及 platform-crypto.ts 的 zzcSign / decodeTencentLyric（QRC 行解析）。
//
// 与桌面端的差异：
// - 歌词请求用 crypt=0。桌面端 crypt=1 拿到的是 QRC 3DES 加密的十六进制串，靠 smart-lyric 解密；
//   该算法无法在本仓库用桌面端实现校验，所以移动端不解密，只用接口给的明文 / base64 文本。
// - MV 搜索结果放在 SearchResult.songs（PTrack.mvId = vid），因为 CatalogType 没有 MV。
import 'dart:convert';
import 'dart:math';
import '../net/json.dart';
import 'crypto_util.dart';
import 'models.dart';
import 'platform.dart';

const _ua = 'Mozilla/5.0 Sollin/0.1';

/// 桌面端 platform-service.ts 的 `headers`（所有 QQ 请求默认带 y.qq.com 的 Referer）。
const _headers = {'User-Agent': _ua, 'Referer': 'https://y.qq.com/'};
const _musicu = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

/// 桌面端隐藏的榜单（国乐 / 有声等）。
const _hiddenBoardIds = {'64', '65', '75'};
const _hiddenBoardNames = {'国乐榜', '国风热歌榜', '有声榜', '综艺新歌榜'};

/// 手机版搜索（musics.fcg）要求的 comm 块，字段原样照抄桌面端，缺字段会被风控。
const _mobileComm = {
  'ct': '11',
  'cv': '14090508',
  'v': '14090508',
  'tmeAppID': 'qqmusic',
  'phonetype': 'EBG-AN10',
  'deviceScore': '553.47',
  'devicelevel': '50',
  'newdevicelevel': '20',
  'rom': 'HuaWei/EMOTION/EmotionUI_14.2.0',
  'os_ver': '12',
  'OpenUDID': '0',
  'OpenUDID2': '0',
  'QIMEI36': '0',
  'udid': '0',
  'chid': '0',
  'aid': '0',
  'oaid': '0',
  'taid': '0',
  'tid': '0',
  'wid': '0',
  'uid': '0',
  'sid': '0',
  'modeSwitch': '6',
  'teenMode': '0',
  'ui_mode': '2',
  'nettype': '1020',
  'v4ip': '',
};
const _mobileUa = 'QQMusic 14090508(android 12)';

// ───────────────────────────── 签名 ─────────────────────────────

/// QQ 音乐 musics.fcg 的 sign 参数（桌面端 zzcSign）：对请求体 JSON 原文做 SHA1 后挑位 + 异或 + base64。
String zzcSign(String text) {
  final h = sha1Hex(text);
  String pick(List<int> indexes) => indexes.map((i) => h[i]).join();
  final part1 = pick(const [23, 14, 6, 36, 16, 40, 7, 19]);
  final part2 = pick(const [16, 1, 32, 12, 19, 27, 8, 5]);
  const scramble = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179];
  final bytes = [for (var i = 0; i < scramble.length; i++) scramble[i] ^ int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)];
  final encoded = base64.encode(bytes).replaceAll(RegExp(r'[\\/+=]'), '');
  return 'zzc$part1$encoded$part2'.toLowerCase();
}

/// QQ 的 hash33（g_tk / ptqrtoken 用）。按 JS 语义：`hash << 5` 先截成 int32，最后 `& 0x7fffffff`。
int hash33(String s, [int init = 0]) {
  var h = init;
  for (final c in s.codeUnits) {
    h += (h.toSigned(32) << 5).toSigned(32) + c;
  }
  return h.toSigned(32) & 0x7fffffff;
}

// ───────────────────────────── 规范化 ─────────────────────────────

/// 歌曲封面：优先接口直给的图，其次专辑图（albumMid 为「空」时无专辑），最后歌手图。
String? qqSongCover(Object? direct, Object? albumMid, Object? singerMid) {
  final existing = _image(direct);
  if (existing != null) return existing;
  final album = _s(albumMid).trim();
  if (album.isNotEmpty && album != '空') return 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$album.jpg';
  final singer = _s(singerMid).trim();
  return singer.isNotEmpty ? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$singer.jpg' : null;
}

/// 每档音质的文件大小。size_new 依次是 [master, atmos, atmos_plus]。
Json tencentQualityDetails(Json raw) {
  final file = asJson(raw['file']);
  final sizeNew = _arr(file['size_new']);
  Object? at(int i) => i < sizeNew.length ? sizeNew[i] : null;
  return _qualityDetails([
    ('128k', file['size_128mp3']),
    ('320k', file['size_320mp3']),
    ('flac', file['size_flac']),
    ('hires', file['size_hires']),
    ('atmos', at(1)),
    ('atmos_plus', at(2)),
    ('master', at(0)),
  ]);
}

List<String> tencentQualities(Json raw) => _normalizeQualities(tencentQualityDetails(raw).keys);

/// 桌面端 normalizeTencent(raw, 'song')。兼容新版 songInfo、搜索 new_json、歌单 new_format 以及包了一层 content 的结构。
PTrack? normalizeTencent(Json raw) {
  final nested = asJson(raw['content']);
  final base = nested.isNotEmpty ? nested : raw;
  final id = _s(base['mid'] ?? base['id'] ?? base['songmid']);
  if (id.isEmpty) return null;
  final singerList = _arr(base['singer']);
  final singers = singerList.map((a) => _s(asJson(a)['name'])).where((n) => n.isNotEmpty).join(' / ');
  final album = asJson(base['album']);
  final title = _s(base['title'] ?? base['name']);
  final singerMid = singerList.isEmpty ? null : asJson(singerList.first)['mid'];
  final cover = qqSongCover(base['picurl'] ?? album['picUrl'], album['mid'], singerMid);
  final details = tencentQualityDetails(base);
  final qualities = _normalizeQualities(details.keys);
  final vid = _s(asJson(base['mv'])['vid']);
  return PTrack(
    platform: Plat.tx,
    nativeId: id,
    title: title,
    artist: singers,
    album: _s(album['name']),
    duration: _duration(base['interval']),
    cover: cover,
    qualities: qualities.isEmpty ? const ['128k'] : qualities,
    identity: {
      'songId': _s(base['id'] ?? id),
      'songMid': id,
      'albumMid': _s(album['mid']),
      'strMediaMid': _s(asJson(base['file'])['media_mid']),
    },
    qualityDetails: details,
    mvId: vid.isEmpty ? null : vid,
  );
}

/// 桌面端 normalizeTencentLegacy 的专辑 / 歌手分支（client_search_cp 的老字段名）。歌曲用 [normalizeTencent]，MV 用 [normalizeTencentMv]。
CatalogItem? normalizeTencentLegacy(Json raw, SearchType type) {
  if (type == SearchType.album) {
    final albumMid = _s(raw['albumMID'] ?? raw['albumID']);
    if (albumMid.isEmpty) return null;
    final singer = _s(raw['singerName']);
    return CatalogItem(
      platform: Plat.tx,
      id: albumMid,
      type: CatalogType.album,
      title: _s(raw['albumName']),
      subtitle: singer,
      creator: singer.isEmpty ? null : singer,
      cover: _image(raw['albumPic']) ?? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
      date: _date(raw['publicTime']),
    );
  }
  if (type == SearchType.artist) {
    final singerMid = _s(raw['singerMID'] ?? raw['singerID']);
    if (singerMid.isEmpty) return null;
    return CatalogItem(
      platform: Plat.tx,
      id: singerMid,
      type: CatalogType.artist,
      title: _stripHtml(_s(raw['singerName'])),
      subtitle: '${_num(raw['songNum'])} 首歌曲',
      cover: _image(raw['singerPic']) ?? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$singerMid.jpg',
      trackCount: _num(raw['songNum']).toInt(),
    );
  }
  return null;
}

/// MV 搜索结果（桌面端 normalizeTencentLegacy 的 mv 分支）。nativeId / mvId 都是 vid。
PTrack? normalizeTencentMv(Json raw) {
  final vid = _s(raw['vid'] ?? raw['id']);
  if (vid.isEmpty) return null;
  final pic = raw['picurl'] ?? raw['pic'];
  return PTrack(
    platform: Plat.tx,
    nativeId: vid,
    title: _stripHtml(_s(raw['title'] ?? raw['name'])),
    artist: _s(raw['singer_name'] ?? raw['singerName']),
    cover: _image(pic) ?? (pic is String && pic.isNotEmpty ? pic : null),
    qualities: const [],
    identity: {'vid': vid, 'mv': true},
    mvId: vid,
  );
}

/// 桌面端 normalizeTencentPlaylist（搜索结果里的歌单）。
CatalogItem? normalizeTencentPlaylist(Json raw) {
  final id = _s(raw['dissid'] ?? raw['docid']);
  if (id.isEmpty) return null;
  final nick = _stripHtml(_s(raw['nickname']));
  final count = _num(raw['song_count'] ?? raw['songnum']).toInt();
  return CatalogItem(
    platform: Plat.tx,
    id: id,
    type: CatalogType.playlist,
    title: _stripHtml(_s(raw['dissname'] ?? raw['name'] ?? '歌单')),
    subtitle: nick,
    creator: nick.isEmpty ? null : nick,
    cover: _image(raw['logo']),
    playCount: _num(raw['listennum'] ?? raw['listennum_long']),
    trackCount: count == 0 ? null : count,
  );
}

// ───────────────────────────── 歌词（QRC 行解析，桌面端 decodeTencentLyric） ─────────────────────────────

/// 解码 QQ 歌词字段：明文直接用；base64 解码；QRC 3DES 十六进制串（crypt=1）无法解，返回空串。
String decodeTencentText(Object? value) {
  if (value is! String || value.isEmpty) return '';
  final t = value.trim();
  // 纯十六进制长串 = crypt=1 的 QRC 密文，移动端不解
  if (t.length >= 32 && t.length.isEven && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(t)) return '';
  // 含 base64 字母表之外的字符（[ < 汉字等）就是明文
  if (RegExp(r'[^A-Za-z0-9+/=_\-\s\\]').hasMatch(t)) return t.replaceFirst('\uFEFF', '').replaceAll('\r', '');
  return _decodeBase64Text(t).replaceAll('\r', '');
}

String _decodeBase64Text(String value) {
  // 对齐 Buffer.from(x, 'base64') 的宽松解码：去掉字面量 \n、URL-safe 字符换回、忽略非法字符、补齐 padding
  var v = value.replaceAll(r'\n', '').replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'[^A-Za-z0-9+/]'), '');
  if (v.length % 4 == 1) v = v.substring(0, v.length - 1);
  if (v.length % 4 != 0) v = v.padRight(v.length + 4 - v.length % 4, '=');
  try {
    final s = utf8.decode(base64.decode(v), allowMalformed: true);
    return s.startsWith('\uFEFF') ? s.substring(1) : s;
  } catch (_) {
    return '';
  }
}

/// QRC 解析结果：[lyric] 标准 LRC；[extended] 桌面端格式的逐字（`[mm:ss.xxx]<相对ms,时长>字`）；[words] 逐字（绝对毫秒）。
typedef TencentLyricText = ({String lyric, String? extended, List<LyricLineWords> words});

/// 桌面端 decodeTencentLyric：QRC XML（LyricContent="..."）或 `[start,dur]字(start,dur)` 行转 LRC；都不是就原样当 LRC。
TencentLyricText decodeTencentLyric(Object? value) {
  final text = decodeTencentText(value);
  if (text.isEmpty) return (lyric: '', extended: null, words: const <LyricLineWords>[]);
  final content = RegExp(r'^\s*<').hasMatch(text) ? _extractQrcContent(text) : text;
  return _parseQrcLines(content) ?? (lyric: text, extended: null, words: const <LyricLineWords>[]);
}

String _extractQrcContent(String value) {
  final m = RegExp(r'''LyricContent\s*=\s*(["'])([\s\S]*?)\1''', caseSensitive: false).firstMatch(value);
  if (m == null) return value;
  return m
      .group(2)!
      .replaceAll(RegExp('&quot;', caseSensitive: false), '"')
      .replaceAll(RegExp('&apos;', caseSensitive: false), "'")
      .replaceAll(RegExp('&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp('&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp('&amp;', caseSensitive: false), '&');
}

TencentLyricText? _parseQrcLines(String value) {
  final lyricLines = <String>[], extendedLines = <String>[];
  final allWords = <LyricLineWords>[];
  var found = false;
  final lineRe = RegExp(r'^\[\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*\d+)?\s*\](.*)$');
  final marker = RegExp(r'\(\s*(\d+)\s*,\s*(\d+)\s*\)');
  for (final source in value.replaceAll('\r', '').split('\n')) {
    final line = source.trim();
    if (line.isEmpty) continue;
    final m = lineRe.firstMatch(line);
    if (m == null) {
      if (RegExp(r'^\[[a-z]+\s*:', caseSensitive: false).hasMatch(line)) lyricLines.add(line);
      continue;
    }
    found = true;
    final lineStart = int.parse(m.group(1)!), lineDuration = int.parse(m.group(2)!);
    final lineEnd = lineStart + max(0, lineDuration);
    final rest = m.group(3) ?? '';
    final words = <({int start, int duration, String text})>[];
    var cursor = 0;
    for (final mm in marker.allMatches(rest)) {
      final part = rest.substring(cursor, mm.start);
      if (part.isNotEmpty) words.add((text: part, start: max(lineStart, int.parse(mm.group(1)!)), duration: max(0, int.parse(mm.group(2)!))));
      cursor = mm.end;
    }
    final tail = rest.substring(cursor);
    if (tail.isNotEmpty) {
      final prev = words.isEmpty ? null : words.last;
      final int start = prev == null ? lineStart : max(lineStart, prev.start + max(prev.duration, 0));
      words.add((text: tail, start: start, duration: max<int>(0, lineEnd - start)));
    }
    final visible = words.map((w) => w.text).join().trim();
    if (visible.isEmpty) continue;
    final stamp = _lrcStamp(lineStart);
    lyricLines.add('$stamp$visible');
    if (words.isNotEmpty) {
      extendedLines.add('$stamp${words.map((w) => '<${max(0, w.start - lineStart)},${max(0, w.duration)}>${w.text}').join()}');
      allWords.add(LyricLineWords(lineStart, max(0, lineDuration), visible, words));
    }
  }
  if (!found || lyricLines.isEmpty) return null;
  return (lyric: lyricLines.join('\n'), extended: extendedLines.isEmpty ? null : extendedLines.join('\n'), words: allWords);
}

/// 毫秒 → `[mm:ss.xxx]`（桌面端 qrcTimestamp）。
String _lrcStamp(int ms) {
  final v = max(0, ms);
  final m = v ~/ 60000, rest = v % 60000;
  return '[${'$m'.padLeft(2, '0')}:${'${rest ~/ 1000}'.padLeft(2, '0')}.${'${rest % 1000}'.padLeft(3, '0')}]';
}

// ───────────────────────────── 平台实现 ─────────────────────────────

class TencentPlatform extends MusicPlatform {
  TencentPlatform(super.http);

  @override
  String get code => Plat.tx;

  @override
  Set<SearchType> get searchTypes => const {SearchType.song, SearchType.playlist, SearchType.artist, SearchType.album, SearchType.mv};

  @override
  Set<CatalogType> get collectionTypes => const {CatalogType.playlist, CatalogType.leaderboard, CatalogType.album, CatalogType.artist};

  static const _typeMap = {SearchType.song: 0, SearchType.album: 8, SearchType.artist: 9, SearchType.playlist: 3, SearchType.mv: 12};

  Future<Json> _get(String url, {Map<String, String> headers = _headers}) async => asJson(await http.getJson(code, url, headers: headers));

  Future<Json> _post(Object payload, {Map<String, String> headers = _headers}) async => asJson(await http.postJson(code, _musicu, payload, headers: headers));

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    var clean = keyword.trim();
    if (clean.length > 100) clean = clean.substring(0, 100);
    if (clean.isEmpty) return const SearchResult();
    if (type != SearchType.playlist) return _searchLegacy(clean, type, page, limit);
    return _searchPlaylist(clean, page, limit);
  }

  /// 歌曲 / 专辑 / 歌手 / MV：c.y.qq.com 老接口 client_search_cp（不用签名）。
  Future<SearchResult> _searchLegacy(String keyword, SearchType type, int page, int limit) async {
    final url = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&p=$page&n=$limit&w=${Uri.encodeComponent(keyword)}'
        '&cr=1&new_json=1&aggr=1&lossless=1&sem=1&remoteplace=txt.mqq.all&searchid=&t=${_typeMap[type]}';
    final data = await _get(url, headers: {..._headers, 'Referer': 'https://y.qq.com/'});
    final body = asJson(data['data']);
    const keys = {SearchType.song: 'song', SearchType.album: 'album', SearchType.artist: 'singer', SearchType.playlist: 'songlist', SearchType.mv: 'mv'};
    final section = asJson(body[keys[type]]);
    final rows = _arr(section['list']).map(asJson);
    final total = _num(section['totalnum']).toInt();
    switch (type) {
      case SearchType.song:
        return _result(page, limit, total, songs: rows.map(normalizeTencent).whereType<PTrack>().toList());
      case SearchType.mv:
        return _result(page, limit, total, songs: rows.map(normalizeTencentMv).whereType<PTrack>().toList());
      default:
        return _result(page, limit, total, items: rows.map((r) => normalizeTencentLegacy(r, type)).whereType<CatalogItem>().toList());
    }
  }

  /// 歌单搜索：u.y.qq.com musics.fcg（手机端协议，sign = zzcSign(请求体)）；失败退回不签名的 musicu.fcg?data=。
  Future<SearchResult> _searchPlaylist(String keyword, int page, int limit) async {
    final payload = {
      'comm': _mobileComm,
      'req': {
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicMobile',
        'param': {
          'num_per_page': limit,
          'page_num': page,
          'query': keyword,
          'search_type': _typeMap[SearchType.playlist],
          'searchid': _searchId(),
          'highlight': 0,
          'nqc_flag': 0,
          'multi_zhida': 0,
          'cat': 2,
          'grp': 1,
          'sin': 0,
          'sem': 0,
        },
      },
    };
    // 签名必须对发出去的同一份 JSON 原文计算
    final body = jsonEncode(payload);
    final legacyUrl = '$_musicu?data=${Uri.encodeComponent(jsonEncode({'req_0': payload['req']}))}';
    Json data = {};
    var req = <String, dynamic>{};
    var usedLegacy = false;
    try {
      data = asJson(await http.json(code, 'POST', Uri.parse('https://u.y.qq.com/cgi-bin/musics.fcg?sign=${zzcSign(body)}'),
          headers: {..._headers, 'User-Agent': _mobileUa, 'Content-Type': 'application/json'}, body: body));
      req = asJson(data['req']);
    } on PlatformException {
      data = {'code': -1};
    }
    if (_num(data['code']) != 0 || _num(req['code']) != 0) {
      data = await _get(legacyUrl);
      req = asJson(data['req_0']);
      usedLegacy = true;
    }
    if (_num(data['code']) != 0 || _num(req['code']) != 0) throw PlatformException(code, 'QQ 音乐搜索暂时不可用');
    final result = asJson(asJson(req['data'])['body']);
    final items = _arr(result['item_songlist']).map(asJson).map(normalizeTencentPlaylist).whereType<CatalogItem>().toList();
    // 桌面端：asRecord(body.item_songlist).sum —— item_songlist 是数组时拿不到，等于 0
    final total = _num(asJson(result['meta'])['estimate_sum'] ?? asJson(result['item_songlist'])['sum']).toInt();
    if (items.isEmpty && !usedLegacy) {
      // 签名接口返回空列表时再用老接口试一次（桌面端同样逻辑）
      final legacy = await _get(legacyUrl);
      final legacyBody = asJson(asJson(asJson(legacy['req_0'])['data'])['body']);
      final legacyItems = _arr(legacyBody['item_songlist']).map(asJson).map(normalizeTencentPlaylist).whereType<CatalogItem>().toList();
      return _result(page, limit, _num(asJson(legacyBody['meta'])['estimate_sum']).toInt(), items: legacyItems);
    }
    return _result(page, limit, total, items: items);
  }

  static String _searchId() {
    final r = Random();
    return List.generate(17, (i) => i == 0 ? 1 + r.nextInt(9) : r.nextInt(10)).join();
  }

  @override
  Future<List<String>> suggest(String keyword) async {
    var clean = keyword.trim();
    if (clean.length > 40) clean = clean.substring(0, 40);
    if (clean.isEmpty) return const [];
    final data = await _get(
      'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?is_xml=0&format=json&key=${Uri.encodeComponent(clean)}&loginUin=0&hostUin=0&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0',
      headers: {..._headers, 'Referer': 'https://y.qq.com/portal/player.html'},
    );
    final body = data['data'] is Map ? asJson(data['data']) : data;
    final words = _uniqueWords(_arr(asJson(body['song'])['itemlist']).map((e) {
      final song = asJson(e);
      return '${_s(song['name'])} - ${_s(song['singer'])}'.replaceFirst(RegExp(r' - $'), '');
    }));
    if (words.isNotEmpty) return words;
    // 联想为空：用搜索结果补
    final fallback = await _searchLegacy(clean, SearchType.song, 1, 10);
    return _uniqueWords(fallback.songs.map((t) {
      final sub = t.artist.isNotEmpty ? t.artist : t.album;
      return sub.isNotEmpty ? '${t.title} - $sub' : t.title;
    }));
  }

  @override
  Future<List<String>> hotSearch() async {
    try {
      final data = await _post({
        'comm': {'ct': '19', 'cv': '1803', 'guid': '0', 'patch': '118', 'tmeAppID': 'qqmusic', 'tmeLoginType': 0, 'uin': '0', 'wid': '0'},
        'hotkey': {'method': 'GetHotkeyForQQMusicPC', 'module': 'tencent_musicsoso_hotkey.HotkeyService', 'param': {'search_id': '', 'uin': 0}},
      }, headers: {..._headers, 'Referer': 'https://y.qq.com/portal/player.html'});
      return _uniqueWords(_arr(asJson(asJson(data['hotkey'])['data'])['vec_hotkey']).map((e) => asJson(e)['query']));
    } catch (_) {
      return const [];
    }
  }

  /// 分类 id：排序项是 `排序::`（2 最新 / 5 最热），「全部」是 `全部`，标签是数字 id。传回 [playlists]。
  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final data = await _get('$_musicu?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${Uri.encodeComponent(jsonEncode({
          'tags': {'method': 'get_all_categories', 'param': {'qq': ''}, 'module': 'playlist.PlaylistAllCategoriesServer'},
        }))}');
    final groups = _arr(asJson(asJson(data['tags'])['data'])['v_group']).map(asJson);
    return [
      const PlaylistCategory('2::', '最新', group: '排序'),
      const PlaylistCategory('5::', '最热', group: '排序'),
      const PlaylistCategory('全部', '全部', group: '默认'),
      for (final g in groups)
        for (final item in _arr(g['v_item']).map(asJson))
          if (_s(item['name']).isNotEmpty) PlaylistCategory('${_num(item['id']).toInt()}', _s(item['name']), group: _s(g['group_name'] ?? '分类')),
    ];
  }

  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    final (sort: sort, tag: tag) = _parsePlaylistQuery(category ?? '');
    final id = int.tryParse(tag);
    final tagged = tag.isNotEmpty && id != null && id > 0;
    final payload = tagged
        ? {
            'comm': {'cv': 1602, 'ct': 20},
            'playlist': {
              'method': 'get_category_content',
              'param': {'titleid': id, 'caller': '0', 'category_id': id, 'size': limit, 'page': page - 1, 'use_page': 1},
              'module': 'playlist.PlayListCategoryServer',
            },
          }
        : {
            'comm': {'cv': 1602, 'ct': 20},
            'playlist': {
              'method': 'get_playlist_by_tag',
              'param': {'id': 10000000, 'sin': limit * (page - 1), 'size': limit, 'order': (int.tryParse(sort) ?? 0) == 0 ? 5 : int.parse(sort), 'cur_page': page},
              'module': 'playlist.PlayListPlazaServer',
            },
          };
    final data = await _get('$_musicu?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${Uri.encodeComponent(jsonEncode(payload))}');
    final body = asJson(asJson(data['playlist'])['data']);
    final rows = tagged ? _arr(asJson(body['content'])['v_item']) : _arr(body['v_playlist']);
    final items = <CatalogItem>[];
    for (final raw in rows.map(asJson)) {
      final basic = asJson(raw['basic']);
      final source = basic.isNotEmpty ? basic : raw;
      final songIds = _arr(source['song_ids']).length;
      final item = _catalog(
        source['tid'],
        source['title'],
        asJson(source['creator_info'])['nick'],
        source['cover_url_medium'] ?? asJson(source['cover'])['medium_url'],
        source['access_num'] ?? source['play_cnt'],
        songIds != 0 ? songIds : source['song_count'],
        source['modify_time'] ?? source['create_time'] ?? source['createtime'] ?? source['createTime'],
      );
      if (item != null) items.add(item);
    }
    final total = _num(body['total'] ?? body['total_cnt']).toInt();
    return Page(items, page: page, limit: limit, total: total, hasMore: page * limit < total || items.length == limit);
  }

  @override
  Future<List<CatalogItem>> leaderboards() async {
    final data = await _get(
      'https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg?g_tk=1928093487&inCharset=utf-8&outCharset=utf-8&notice=0&format=json&uin=0&needNewCode=1&platform=h5',
      headers: {..._headers, 'Referer': 'https://y.qq.com/'},
    );
    final out = <CatalogItem>[];
    for (final item in _arr(asJson(data['data'])['topList']).map(asJson)) {
      final id = _s(item['id']);
      final name = _stripHtml(_s(item['topTitle'] ?? item['name'] ?? '排行榜')).replaceFirst(RegExp(r'^巅峰榜[·・]?'), '');
      if (_num(item['id']) == 201 || _hiddenBoardIds.contains(id) || _hiddenBoardNames.contains(name)) continue;
      final board = _catalog(item['id'], name, 'QQ 音乐实时榜单', item['picUrl'], null, null, null, type: CatalogType.leaderboard);
      if (board != null) out.add(board);
    }
    return out;
  }

  @override
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100}) async {
    final clean = id.trim();
    if (clean.isEmpty) throw PlatformException(code, '音乐详情缺少 ID');
    switch (type) {
      case CatalogType.leaderboard:
        return _leaderboard(clean, page, limit);
      case CatalogType.playlist:
        return _playlist(clean, page, limit);
      case CatalogType.album:
      case CatalogType.artist:
        return _albumOrArtist(type, clean, page, limit);
    }
  }

  Future<Collection> _playlist(String id, int page, int limit) async {
    final data = await _get(
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=${Uri.encodeComponent(id)}&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0',
      headers: {..._headers, 'Referer': 'https://y.qq.com/'},
    );
    final cdlist = _arr(data['cdlist']);
    if (cdlist.isEmpty) throw PlatformException(code, 'QQ 音乐歌单不存在或暂时不可用');
    final playlist = asJson(cdlist.first);
    // 接口一次给全部歌曲，本地分页
    final all = _arr(playlist['songlist']);
    final rows = all.skip((page - 1) * limit).take(limit).map(asJson);
    final tracks = rows.map(normalizeTencent).whereType<PTrack>().toList();
    final total = _num(playlist['total_song_num'] ?? playlist['songnum'] ?? all.length).toInt();
    final creator = _s(playlist['nickname'] ?? playlist['nick']);
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.playlist,
      title: _s(playlist['dissname'] ?? '歌单'),
      description: _s(playlist['desc']),
      cover: _image(playlist['logo']),
      creator: creator.isEmpty ? null : creator,
      tracks: tracks,
      total: total,
      page: page,
      limit: limit,
      hasMore: page * limit < total,
    );
  }

  /// 榜单两步走：先从 top.html 抠出这个榜当前的期数（data-date），再用 ToplistInfoServer.GetDetail 拿歌。
  /// 期数拿不到时桌面端直接报错（没有兜底），这里一致。
  Future<Collection> _leaderboard(String id, int page, int limit) async {
    final html = await http.text(code, 'GET', Uri.parse('https://c.y.qq.com/node/pc/wk_v15/top.html'), headers: _headers, timeout: const Duration(seconds: 15));
    final m = RegExp('data-listname="(.+?)" data-tid=".*?/${RegExp.escape(id)}" data-date="(.+?)"').firstMatch(html);
    final period = m?.group(2);
    if (period == null || period.isEmpty) throw PlatformException(code, 'QQ 榜单周期不可用');
    final data = await _post({
      'comm': {'uin': 0, 'format': 'json', 'ct': 20, 'cv': 1859},
      'toplist': {
        'module': 'musicToplist.ToplistInfoServer',
        'method': 'GetDetail',
        'param': {'topid': int.tryParse(id), 'num': limit, 'period': period},
      },
    });
    final tracks = _arr(asJson(asJson(data['toplist'])['data'])['songInfoList']).map(asJson).map(normalizeTencent).whereType<PTrack>().toList();
    // 桌面端的正则在同一行有多个榜单时 group(1) 会跨榜，名字单独用严格的正则取（期数仍按桌面端）
    final nameMatch = RegExp('data-listname="([^"]*)" data-tid="[^"]*/${RegExp.escape(id)}"').firstMatch(html);
    final listName = _stripHtml(nameMatch?.group(1) ?? '').trim();
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.leaderboard,
      title: listName.isNotEmpty ? listName : 'QQ 音乐榜单 $id',
      tracks: tracks,
      total: tracks.length,
      page: page,
      limit: limit,
    );
  }

  Future<Collection> _albumOrArtist(CatalogType type, String id, int page, int limit) async {
    final artist = type == CatalogType.artist;
    final begin = (page - 1) * limit;
    const comm = {'ct': 24, 'cv': 4747474, 'format': 'json', 'uin': 0};
    final payload = artist
        ? {
            'comm': comm,
            'songs': {'module': 'musichall.song_list_server', 'method': 'GetSingerSongList', 'param': {'singerMid': id, 'begin': begin, 'num': limit, 'order': 1}},
            if (page == 1) 'albums': {'module': 'music.musichallAlbum.AlbumListServer', 'method': 'GetAlbumList', 'param': {'singerMid': id, 'begin': 0, 'num': 100, 'order': 0}},
          }
        : {
            'comm': comm,
            'album': {'module': 'music.musichallAlbum.AlbumSongList', 'method': 'GetAlbumSongList', 'param': {'albumMid': id, 'begin': begin, 'num': limit}},
          };
    final data = await _post(payload);
    final body = asJson(asJson(data[artist ? 'songs' : 'album'])['data']);
    final rows = _arr(body['songList'] ?? body['songlist'] ?? body['list']).map(asJson).toList();
    final tracks = rows.map((r) => normalizeTencent(asJson(r['songInfo'] ?? r))).whereType<PTrack>().toList();
    final firstSong = rows.isEmpty ? <String, dynamic>{} : asJson(rows.first['songInfo'] ?? rows.first);
    final firstAlbum = asJson(firstSong['album']);
    final singers = _arr(firstSong['singer']);
    final firstSinger = singers.isEmpty ? <String, dynamic>{} : asJson(singers.first);
    final albumList = _arr(asJson(asJson(data['albums'])['data'])['albumList']);
    final total = _num(body['totalNum'] ?? body['total_num']).toInt();
    final realTotal = total != 0 ? total : tracks.length;
    final title = artist
        ? _s(firstSinger['name'] ?? (albumList.isEmpty ? null : asJson(albumList.first)['singerName']) ?? 'QQ 音乐歌手')
        : _s(firstAlbum['name'] ?? 'QQ 音乐专辑');
    final creator = artist ? '' : _s(firstSinger['name']);
    return Collection(
      platform: code,
      id: id,
      type: type,
      title: title,
      cover: artist ? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$id.jpg' : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$id.jpg',
      creator: creator.isEmpty ? null : creator,
      tracks: tracks,
      total: realTotal,
      page: page,
      limit: limit,
      hasMore: page * limit < realTotal,
    );
  }

  /// 歌词：mid → 数字 songID（get_song_detail_yqq；identity 里已有数字 songId 就跳过），
  /// 再调 PlayLyricInfo.GetPlayLyricInfo。crypt=0 拿明文 / base64；qrc=1 没给出可用歌词时用 qrc=0 再要一次。
  @override
  Future<Lyric> lyric(PTrack track) async {
    final mid = track.nativeId;
    var songId = int.tryParse(_s(track.identity['songId'])) ?? 0;
    if (songId == 0) {
      final detail = await _post({
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {'module': 'music.pf_song_detail_svr', 'method': 'get_song_detail_yqq', 'param': {'song_type': 0, 'song_mid': mid}},
      }, headers: {..._headers, 'Content-Type': 'application/json'});
      songId = _num(asJson(asJson(asJson(detail['req'])['data'])['track_info'])['id']).toInt();
      if (songId == 0) throw PlatformException(code, 'QQ 音乐歌曲 ID 不可用');
    }
    Future<Json> fetch(int qrc) async {
      final data = await _post({
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'GetPlayLyricInfo',
          'module': 'music.musichallSong.PlayLyricInfo',
          'param': {
            'format': 'json',
            'crypt': 0,
            'ct': 19,
            'cv': 1873,
            'interval': max(0, track.duration),
            'lrc_t': 0,
            'qrc': qrc,
            'qrc_t': 0,
            'roma': 1,
            'roma_t': 0,
            'songID': songId,
            'trans': 1,
            'trans_t': 0,
            'type': -1,
          },
        },
      }, headers: {..._headers, 'Referer': 'https://y.qq.com', 'Content-Type': 'application/json'});
      return asJson(asJson(data['req'])['data']);
    }

    var res = await fetch(1);
    var main = decodeTencentLyric(res['lyric']);
    if (main.lyric.trim().isEmpty) {
      res = await fetch(0);
      main = decodeTencentLyric(res['lyric']);
    }
    if (main.lyric.trim().isEmpty) throw PlatformException(code, 'QQ 音乐没有歌词');
    String? side(Object? v) {
      final t = decodeTencentLyric(v).lyric;
      return t.trim().isEmpty ? null : t;
    }

    return Lyric(main.lyric, translation: side(res['trans']), romanization: side(res['roma']), words: main.words.isEmpty ? null : main.words);
  }
}

// ───────────────────────────── 桌面端通用小函数（私有副本） ─────────────────────────────

/// 桌面端 parsePlaylistQuery：`排序::标签`，或单独的标签（默认排序 5）；「全部」= 不限标签。
({String sort, String tag}) _parsePlaylistQuery(String value) {
  final parts = value.split('::');
  if (parts.length > 1) return (sort: parts[0].isEmpty ? '5' : parts[0], tag: parts[1] == '全部' ? '' : parts[1]);
  return (sort: '5', tag: value == '全部' ? '' : value);
}

/// JS 的 String(value ?? '')。
String _s(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v is String ? v : v.toString();
}

/// JS 的 asNumber：Number(value)，非有限数给 0。
num _num(Object? v) {
  if (v is num) return v.isFinite ? v : 0;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    final n = num.tryParse(t);
    return n != null && n.isFinite ? n : 0;
  }
  return 0;
}

List<dynamic> _arr(Object? v) => v is List ? v : const [];

/// 秒；大于 10000 视为毫秒。
int _duration(Object? v) {
  final n = _num(v);
  return n > 10000 ? (n / 1000).round() : n.round();
}

String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

String? _image(Object? value) {
  if (value is! String) return null;
  final url = value.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:${url.replaceFirst('{size}', '500')}';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return null;
  return url.replaceFirst('{size}', '500');
}

Json _qualityDetails(List<(String, Object?)> pairs) {
  final out = <String, dynamic>{};
  for (final (q, v) in pairs) {
    final n = _num(v);
    if (n > 0) out[q] = {'size': n.toInt()};
  }
  return out;
}

List<String> _normalizeQualities(Iterable<String> values) {
  final set = values.toSet();
  return qualityOrder.where(set.contains).toList();
}

List<String> _uniqueWords(Iterable<Object?> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in values) {
    final w = _s(v).trim();
    if (w.isEmpty || !seen.add(w)) continue;
    out.add(w);
    if (out.length >= 20) break;
  }
  return out;
}

/// 桌面端 response()：total 为 0 时用条数代替；hasMore 有 total 就按页数算，否则看是否满页。
SearchResult _result(int page, int limit, int total, {List<PTrack> songs = const [], List<CatalogItem> items = const []}) {
  final count = songs.length + items.length;
  return SearchResult(songs: songs, items: items, total: total != 0 ? total : count, hasMore: total != 0 ? page * limit < total : count == limit);
}

/// 桌面端 formatCatalogDate：秒 / 毫秒时间戳或日期字符串 → yyyy-MM-dd。
String? _date(Object? value) {
  if (value == null || value == '') return null;
  DateTime? d;
  final n = value is num ? value : (value is String ? num.tryParse(value.trim()) : null);
  try {
    if (n != null) {
      d = DateTime.fromMillisecondsSinceEpoch((n < 1e12 ? n * 1000 : n).round());
    } else {
      d = DateTime.tryParse(_s(value))?.toLocal();
    }
  } catch (_) {
    d = null;
  }
  if (d == null) return null;
  return '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
}

/// 桌面端 normalizeCatalogPlayCount：数字或数字字符串转成数，「1.2万」这类文案原样保留。
Object? _playCount(Object? value) {
  if (value is num) return value.isFinite ? value : null;
  if (value is! String) {
    final n = _num(value);
    return n == 0 ? null : n;
  }
  final t = value.trim();
  if (t.isEmpty) return null;
  return num.tryParse(t) ?? t;
}

/// 桌面端 makeCatalogItem / makeLeaderboardItem。
CatalogItem? _catalog(Object? id, Object? title, Object? subtitle, Object? cover, Object? playCount, Object? trackCount, Object? date, {CatalogType type = CatalogType.playlist}) {
  final v = _s(id);
  if (v.isEmpty) return null;
  final creator = _s(subtitle);
  final count = _num(trackCount).toInt();
  return CatalogItem(
    platform: Plat.tx,
    id: v,
    type: type,
    title: title == null ? '歌单' : _s(title),
    subtitle: subtitle == null ? '未知创建者' : creator,
    creator: creator.isEmpty ? null : creator,
    cover: _image(cover),
    playCount: _playCount(playCount),
    trackCount: count == 0 ? null : count,
    date: _date(date),
  );
}
