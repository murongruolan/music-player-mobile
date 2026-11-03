// 酷我音乐（kw）。对齐桌面端 platform-service.ts 的 *Kuwo / normalizeKuwo* / collectKuwoBoards / kuwoImage，
// 以及 platform-crypto.ts 的 kuwoBoardParams / kuwoDecode / parseKuwoObject / buildKuwoLyricParams / parseKuwoLyric。
import 'dart:convert';
import 'dart:typed_data';
import '../net/json.dart';
import 'crypto_util.dart';
import 'http.dart';
import 'models.dart';
import 'platform.dart';

const _kw = Plat.kw;

/// 桌面端公共请求头里的 Referer 是 y.qq.com（所有平台共用），只带 `{ headers }` 的酷我接口也是这样发的，保持一致。
const _baseHeaders = {'Referer': 'https://y.qq.com/'};
const _kuwoReferer = {'Referer': 'https://www.kuwo.cn/'};

/// 榜单接口（wbd.kuwo.cn）的 AES-128-ECB 密钥。
const _kuwoAesKey = [112, 87, 39, 61, 199, 250, 41, 191, 57, 68, 45, 114, 221, 94, 140, 228];
const _kuwoAppId = 'y67sprxhhpws';

/// 榜单详情请求参数：JSON → AES-128-ECB(PKCS7) → base64；sign = MD5(appId + 密文 + 毫秒时间戳) 大写。
/// [time] 不传时用当前毫秒时间（测试时固定）。
String kuwoBoardParams(String id, int page, int limit, {int? time}) {
  final data = jsonEncode({'uid': '', 'devId': '', 'sFrom': 'kuwo_sdk', 'user_type': 'AP', 'carSource': 'kwplayercar_ar_6.0.1.0_apk_keluze.apk', 'id': id, 'pn': page - 1, 'rn': limit});
  final encoded = base64.encode(aesEcbEncrypt(data, _kuwoAesKey));
  final t = time ?? DateTime.now().millisecondsSinceEpoch;
  final sign = md5Hex('$_kuwoAppId$encoded$t').toUpperCase();
  return 'data=${Uri.encodeComponent(encoded)}&time=$t&appId=$_kuwoAppId&sign=$sign';
}

/// 榜单详情响应：整个 body 是（可能 URL 编码过的）base64 密文，AES-128-ECB 解密后是 JSON。
dynamic kuwoDecode(String body) {
  try {
    var t = body.trim();
    if (t.contains('%')) t = Uri.decodeComponent(t);
    t = t.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    final plain = aesEcbDecrypt(base64.decode(base64.normalize(t)), _kuwoAesKey);
    return jsonDecode(utf8.decode(plain, allowMalformed: true));
  } catch (e) {
    throw PlatformException(_kw, '酷我榜单数据解析失败', e);
  }
}

/// 酷我搜索（mbox 版）返回单引号「JSON」：按桌面端同一条正则把结构位置的 ' 换成 "。
dynamic parseKuwoObject(String value) {
  final fixed = value.replaceAll(RegExp(r"('(?=(,\s*')))|('(?=:))|((?<=([:,]\s*))')|((?<=\{)')|('(?=\}))"), '"');
  try {
    return jsonDecode(fixed);
  } catch (e) {
    throw PlatformException(_kw, '平台返回的数据格式不对', e);
  }
}

/// 先按标准 JSON 解析，失败再按单引号格式解析（酷我不同接口两种都有）。
dynamic _kuwoJson(String text) {
  try {
    return PlatformHttp.decodeJson(_kw, text);
  } on PlatformException {
    return parseKuwoObject(text.trim());
  }
}

/// 歌词请求参数：明文按字节与 'yeelion' 循环异或后 base64。
String buildKuwoLyricParams(String id) {
  final input = utf8.encode('user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_$id&lrcx=1');
  const key = [121, 101, 101, 108, 105, 111, 110]; // 'yeelion'
  return base64.encode([for (var i = 0; i < input.length; i++) input[i] ^ key[i % key.length]]);
}

/// 歌词响应体解码：`tp=content…\r\n\r\n` 之后是 zlib 数据 → 文本是 base64 → 与 'yeelion' 异或 → GB18030 文本。
String decodeKuwoLyricBody(Uint8List raw) {
  if (raw.length < 10 || ascii.decode(raw.sublist(0, 10), allowInvalid: true) != 'tp=content') throw const PlatformException(_kw, '酷我没有歌词');
  final offset = _indexOf(raw, const [13, 10, 13, 10]);
  if (offset < 0) throw const PlatformException(_kw, '酷我没有歌词');
  final Uint8List encoded = () {
    try {
      final inflated = utf8.decode(inflateZlib(raw.sublist(offset + 4)), allowMalformed: true).trim();
      return base64.decode(base64.normalize(inflated.replaceAll(RegExp(r'\s'), '')));
    } catch (e) {
      throw PlatformException(_kw, '酷我歌词解码失败', e);
    }
  }();
  const key = [121, 101, 101, 108, 105, 111, 110];
  for (var i = 0; i < encoded.length; i++) {
    encoded[i] ^= key[i % key.length];
  }
  return gb18030Decode(encoded).replaceAll('\r', '');
}

int _indexOf(List<int> data, List<int> marker) {
  outer:
  for (var i = 0; i + marker.length <= data.length; i++) {
    for (var k = 0; k < marker.length; k++) {
      if (data[i + k] != marker[k]) continue outer;
    }
    return i;
  }
  return -1;
}

class _Row {
  String time, text;
  _Row(this.time, this.text);
}

final _wordTag = RegExp(r'<-?\d+,-?\d+(?:,-?\d+)?>');

/// 酷我 lrcx 歌词解析（对齐桌面端 parseKuwoLyric）。
/// 翻译行和下一句原文同一时间戳：遇到重复时间戳时，把上一行当作前一句的翻译挪走。
/// 逐字标签 `<a,b>` 用 `[kuwo:八进制]` 里的两个系数还原成「行内相对毫秒」。
Lyric parseKuwoLyric(String text) {
  final timeTag = RegExp(r'^\[([\d:.]+)\]');
  final metadataTag = RegExp(r'^\[(?:ver|ti|ar|al|offset|by|kuwo):', caseSensitive: false);
  final tags = <String>[];
  final rows = <_Row>[];
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    final m = timeTag.firstMatch(line);
    if (m != null) {
      rows.add(_Row(m[1]!, line.substring(m[0]!.length).trim()));
    } else if (metadataTag.hasMatch(line)) {
      tags.add(line);
    }
  }
  final lyricRows = <_Row>[];
  final translationRows = <_Row>[];
  final seen = <String>{};
  var hasWordTiming = false;
  final leadingWord = RegExp(r'^<-?\d+,-?\d+(?:,-?\d+)?>');
  for (final row in rows) {
    if (seen.contains(row.time)) {
      if (lyricRows.length < 2) continue;
      final translation = lyricRows.removeLast();
      translation.time = lyricRows.last.time;
      translationRows.add(translation);
      lyricRows.add(_Row(row.time, row.text));
    } else {
      lyricRows.add(_Row(row.time, row.text));
      seen.add(row.time);
    }
    if (!hasWordTiming && leadingWord.hasMatch(row.text)) hasWordTiming = true;
  }
  if (!hasWordTiming && translationRows.length > lyricRows.length * 0.3 && lyricRows.length - translationRows.length > 6) {
    throw const PlatformException(_kw, '酷我歌词格式不可用');
  }
  String render(List<_Row> values) => [...tags, ...values.map((r) => '[${r.time}]${r.text}')].join('\n');
  final lyric = render(lyricRows).replaceAll(_wordTag, '');
  final translation = translationRows.isNotEmpty ? render(translationRows).replaceAll(_wordTag, '') : null;
  final words = _kuwoWordTiming(tags, lyricRows);
  return Lyric(lyric, translation: translation, words: words);
}

/// JS parseInt(value, 8)：跳过前导空白，可带符号，取最长的八进制数字前缀；没有数字时为 null（NaN）。
int? _parseOctal(String value) {
  final m = RegExp(r'^\s*([+-]?)([0-7]+)').firstMatch(value);
  if (m == null) return null;
  final v = int.parse(m[2]!, radix: 8);
  return m[1] == '-' ? -v : v;
}

/// 对齐桌面端 convertKuwoWordTiming；输出直接是逐字模型（行 / 字的 start 都是绝对毫秒）。
List<LyricLineWords>? _kuwoWordTiming(List<String> tags, List<_Row> rows) {
  final kuwoTag = tags.firstWhere((t) => RegExp(r'^\[kuwo:', caseSensitive: false).hasMatch(t), orElse: () => '');
  final kuwoValue = RegExp(r'^\[kuwo:\s*([^\]]+)', caseSensitive: false).firstMatch(kuwoTag)?[1];
  final encoded = _parseOctal(kuwoValue?.split('][').first ?? '');
  if (encoded == null) return null;
  final offset = encoded ~/ 10, offset2 = encoded.remainder(10);
  if (offset == 0 || offset2 == 0) return null;
  final marker = RegExp(r'<(-?\d+),(-?\d+)(?:,-?\d+)?>');
  final out = <LyricLineWords>[];
  for (final row in rows) {
    final matches = marker.allMatches(row.text).toList();
    if (matches.isEmpty) continue;
    final words = <({double start, double end, String text})>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final left = int.parse(m[1]!), right = int.parse(m[2]!);
      final start = ((left + right) / (offset * 2)).abs();
      final end = ((left - right) / (offset2 * 2)).abs() + start;
      final textEnd = i + 1 < matches.length ? matches[i + 1].start : row.text.length;
      words.add((start: start, end: end, text: row.text.substring(m.end, textEnd)));
    }
    // 后一个字开始得比前一个字结束早时，截短前一个字
    for (var i = 1; i < words.length; i++) {
      var prev = words[i - 1];
      if (words[i].start < prev.end) {
        prev = (start: prev.start, end: words[i].start, text: prev.text);
        if (prev.start > prev.end) prev = (start: prev.end, end: prev.end, text: prev.text);
        words[i - 1] = prev;
      }
    }
    final lineStart = _lrcTimeMs(row.time);
    final parts = <({int start, int duration, String text})>[];
    var lineEnd = 0;
    for (final w in words) {
      if (w.text.isEmpty) continue;
      final s = _jsRound(w.start), e = _jsRound(w.end);
      final d = e - s < 0 ? 0 : e - s;
      parts.add((start: lineStart + s, duration: d, text: w.text));
      if (s + d > lineEnd) lineEnd = s + d;
    }
    if (parts.isEmpty) continue;
    out.add(LyricLineWords(lineStart, lineEnd, parts.map((p) => p.text).join().trim(), parts));
  }
  return out.isEmpty ? null : out;
}

/// JS Math.round（.5 向正无穷）。
int _jsRound(double v) => (v + 0.5).floor();

/// "mm:ss.xx" → 毫秒。
int _lrcTimeMs(String time) {
  final parts = time.split(':');
  var total = 0.0;
  for (final p in parts) {
    total = total * 60 + (double.tryParse(p) ?? 0);
  }
  return (total * 1000).round();
}

class KuwoPlatform extends MusicPlatform {
  KuwoPlatform(super.http);

  @override
  String get code => _kw;

  Future<dynamic> _get(String url, [Map<String, String> headers = _baseHeaders]) => http.getJson(_kw, url, headers: headers);
  Future<String> _text(String url, [Map<String, String> headers = _baseHeaders]) => http.text(_kw, 'GET', Uri.parse(url), headers: headers);

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    final clean = _clip(keyword.trim(), 100);
    if (clean.isEmpty) return const SearchResult();
    final w = Uri.encodeComponent(clean);
    if (type == SearchType.playlist) {
      // PC 版搜索接口返回单引号 JSON（_kuwoJson 先按标准 JSON 试，失败再走 parseKuwoObject）
      final text = await _text(
          'http://search.kuwo.cn/r.s?all=$w&pn=${page - 1}&rn=$limit&rformat=json&encoding=utf8&ver=mbox&vipver=MUSIC_8.7.7.0_BCS37&plat=pc&devid=28156413&ft=playlist&pay=0&needliveshow=0',
          _kuwoReferer);
      final data = asJson(_kuwoJson(text));
      final items = _arr(data['abslist']).map((raw) => normalizeKuwoPlaylist(asJson(raw))).whereType<CatalogItem>().toList();
      return _result(items: items, page: page, limit: limit, total: _num(data['TOTAL']).toInt());
    }
    if (type != SearchType.song) return const SearchResult();
    final text = await _text(
        'https://search.kuwo.cn/r.s?client=kt&all=$w&pn=${page - 1}&rn=$limit&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1',
        _kuwoReferer);
    final data = asJson(_kuwoJson(text));
    final songs = _tracks(data['abslist']);
    return _result(songs: songs, page: page, limit: limit, total: _num(data['TOTAL']).toInt());
  }

  @override
  Future<List<String>> suggest(String keyword) async {
    final clean = _clip(keyword.trim(), 40);
    if (clean.isEmpty) return const [];
    final data = asJson(await _get('https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0&c=mbox&w=${Uri.encodeComponent(clean)}&encoding=utf8&rformat=json', _kuwoReferer));
    return _uniqueWords(_arr(data['WORDITEMS']).map((e) => asJson(e)['RELWORD']));
  }

  @override
  Future<List<String>> hotSearch() async {
    final data = asJson(await _get(
        'https://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1',
        {..._baseHeaders, 'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9;)'}));
    return _uniqueWords(_arr(data['tagvalue']).map((e) => asJson(e)['key']));
  }

  /// 前三项对齐桌面端：排序（'new::' / 'hot::'）和「全部」；其余分类 id 是 `<id>-<digest>`，原样传给 [playlists]。
  /// [playlists] 也接受 'sort::<id>-<digest>' 组合、单独的 'new' / 'hot'，null 等同「全部」。
  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final data = asJson(await _get(
        'http://wapi.kuwo.cn/api/pc/classify/playlist/getTagList?cmd=rcm_keyword_playlist&user=0&prod=kwplayer_pc_9.0.5.0&vipver=9.0.5.0&source=kwplayer_pc_9.0.5.0&loginUid=0&loginSid=0&appUid=76039576'));
    return [
      const PlaylistCategory('new::', '最新', group: '排序'),
      const PlaylistCategory('hot::', '最热', group: '排序'),
      const PlaylistCategory('全部', '全部', group: '默认'),
      for (final g in _arr(data['data']))
        for (final raw in _arr(asJson(g)['data']))
          if (_s(asJson(raw)['name']).isNotEmpty) PlaylistCategory('${_s(asJson(raw)['id'])}-${_s(asJson(raw)['digest'])}', _s(asJson(raw)['name']), group: _s(asJson(g)['name'] ?? '分类')),
    ];
  }

  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    // 对齐 parsePlaylistQuery：'sort::tag' 或单独的 tag
    var sort = 'hot', tag = '';
    final c = category?.trim() ?? '';
    if (c.contains('::')) {
      final i = c.indexOf('::');
      sort = c.substring(0, i).isEmpty ? 'hot' : c.substring(0, i);
      tag = c.substring(i + 2);
    } else if (c == 'hot' || c == 'new') {
      sort = c;
    } else {
      tag = c;
    }
    if (tag == '全部') tag = '';
    final parts = tag.isEmpty ? const ['', ''] : tag.split('-');
    final id = parts[0], digest = parts.length > 1 ? parts[1] : '';
    if (id.isNotEmpty && digest != '10000') {
      // digest 不是 10000 的分类走「专区」接口：按分组返回，不分页
      final grouped = await _get('http://mobileinterfaces.kuwo.cn/er.s?type=get_pc_qz_data&f=web&id=${Uri.encodeComponent(id)}&prod=pc');
      final items = [for (final g in _arr(grouped)) for (final raw in _arr(asJson(g)['list'])) _kuwoPlaylistItem(asJson(raw))].whereType<CatalogItem>().toList();
      return Page(items, page: page, limit: limit, total: items.length, hasMore: false);
    }
    final url = id.isNotEmpty
        ? 'http://wapi.kuwo.cn/api/pc/classify/playlist/getTagPlayList?loginUid=0&appUid=76039576&pn=$page&id=${Uri.encodeComponent(id)}&rn=$limit'
        : 'http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&user=0&appUid=76039576&pn=$page&rn=$limit&order=${Uri.encodeComponent(sort)}';
    final body = asJson(await _get(url)).obj('data');
    final items = _arr(body['data']).map((raw) => _kuwoPlaylistItem(asJson(raw))).whereType<CatalogItem>().toList();
    final total = _num(body['total']).toInt();
    final t = total == 0 ? items.length : total;
    return Page(items, page: page, limit: limit, total: t, hasMore: page * limit < t || items.length == limit);
  }

  CatalogItem? _kuwoPlaylistItem(Json item) => _catalogItem(item['id'], item['name'], item['uname'], item['img'], item['listencnt'], item['total'], item['publish_time'] ?? item['publishtime'] ?? item['create_time'] ?? item['createTime']);

  @override
  Future<List<CatalogItem>> leaderboards() async {
    final data = asJson(await _get('https://qukudata.kuwo.cn/q.k?op=query&cont=tree&node=2&pn=0&rn=1000&fmt=json&level=2', _kuwoReferer));
    final rows = <Json>[];
    collectKuwoBoards(data['child'], rows);
    return [
      for (final item in rows)
        if (_s(item['sourceid']).isNotEmpty)
          CatalogItem(platform: _kw, id: _s(item['sourceid']), title: _s(item['name'] ?? '歌单'), subtitle: _s(item['info'] ?? '酷我音乐实时榜单'), type: CatalogType.leaderboard, cover: kuwoImage(item['pic'])),
    ];
  }

  @override
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100}) async {
    final clean = id.trim();
    if (clean.isEmpty) throw const PlatformException(_kw, '音乐详情缺少 ID');
    if (type == CatalogType.leaderboard) {
      final body = await _text('https://wbd.kuwo.cn/api/bd/bang/bang_info?${kuwoBoardParams(clean, page, limit)}');
      final data = asJson(kuwoDecode(body)).obj('data');
      final tracks = _tracks(data['musiclist']);
      final total = _num(data['total']).toInt();
      return Collection(platform: _kw, id: clean, type: type, title: '酷我榜单 $clean', tracks: tracks, total: total, page: page, limit: limit, hasMore: page * limit < total);
    }
    if (type == CatalogType.playlist) {
      final data = asJson(_kuwoJson(await _text(
          'http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=${Uri.encodeComponent(clean)}&pn=${page - 1}&rn=$limit&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1')));
      final tracks = _tracks(data['musiclist']);
      final total = _num(data['total']).toInt();
      return Collection(
          platform: _kw,
          id: clean,
          type: type,
          title: _s(data['title'] ?? '酷我歌单'),
          description: _s(data['info'] ?? ''),
          cover: kuwoImage(data['pic']),
          creator: _s(data['uname'] ?? ''),
          tracks: tracks,
          total: total,
          page: page,
          limit: limit,
          hasMore: page * limit < total);
    }
    throw const PlatformException(_kw, '酷我音乐暂不支持此类型详情');
  }

  @override
  Future<Lyric> lyric(PTrack track) async {
    final id = _s(track.identity['id'] ?? track.nativeId);
    if (id.isEmpty) throw const PlatformException(_kw, '酷我歌曲 ID 不可用');
    final raw = await http.bytes(_kw, 'GET', Uri.parse('http://newlyric.kuwo.cn/newlyric.lrc?${buildKuwoLyricParams(id)}'), headers: _kuwoReferer);
    final text = decodeKuwoLyricBody(raw);
    if (!RegExp(r'\[\d{1,3}[:.,]').hasMatch(text)) throw const PlatformException(_kw, '酷我歌词格式不可用');
    return parseKuwoLyric(text);
  }
}

// ───────────────────────── 规范化（对齐 normalizeKuwo / normalizeKuwoPlaylist / collectKuwoBoards） ─────────────────────────

/// 单曲。id 取 rid / musicrid / MUSICRID / id，去掉 `MUSIC_` 前缀；字段名大小写两套都有（搜索接口是大写）。
PTrack? normalizeKuwo(Json raw) {
  final id = _s(raw['rid'] ?? raw['musicrid'] ?? raw['MUSICRID'] ?? raw['id'] ?? '').replaceFirst(RegExp(r'^MUSIC_'), '');
  if (id.isEmpty) return null;
  final title = _stripHtml(_s(raw['name'] ?? raw['songName'] ?? raw['SONGNAME'] ?? raw['NAME'] ?? ''));
  final artist = _stripHtml(_s(raw['artist'] ?? raw['artistName'] ?? raw['ARTIST'] ?? ''));
  final album = _stripHtml(_s(raw['album'] ?? raw['albumName'] ?? raw['ALBUM'] ?? ''));
  final cover = kuwoImage(raw['pic'] ?? raw['img'] ?? raw['albumPic'] ?? raw['albumpic'] ?? raw['ALBUMPIC'] ?? raw['album_pic'] ?? raw['web_albumpic_short']);
  final details = kuwoQualityDetails(raw);
  final qualities = _normalizeQualities(details.keys);
  return PTrack(
    platform: _kw,
    nativeId: id,
    title: title,
    artist: artist,
    album: album,
    // 桌面端只读 songTimeMinutes / duration；搜索接口的时长在大写 DURATION 里，这里补上
    duration: _parseDuration(raw['songTimeMinutes'] ?? raw['duration'] ?? raw['DURATION']),
    cover: cover,
    qualities: qualities.isEmpty ? const ['128k'] : qualities,
    identity: {'id': id},
    qualityDetails: details,
  );
}

List<PTrack> _tracks(Object? rows) => _arr(rows).map((raw) => normalizeKuwo(asJson(raw))).whereType<PTrack>().toList();

/// 搜索结果里的歌单。
CatalogItem? normalizeKuwoPlaylist(Json raw) {
  final id = _s(raw['playlistid'] ?? raw['id'] ?? '');
  if (id.isEmpty) return null;
  final count = _num(raw['playcnt']);
  return CatalogItem(platform: _kw, id: id, title: _stripHtml(_s(raw['name'] ?? '歌单')), subtitle: _stripHtml(_s(raw['nickname'] ?? '')), creator: _stripHtml(_s(raw['nickname'] ?? '')), type: CatalogType.playlist, cover: kuwoImage(raw['pic']), playCount: count == 0 ? null : count);
}

/// 榜单树：source == "1" 且有 sourceid 的节点是榜单，递归 child。
void collectKuwoBoards(Object? value, List<Json> output) {
  if (value is! List) return;
  for (final raw in value) {
    final item = asJson(raw);
    if (_s(item['source'] ?? '') == '1' && _s(item['sourceid'] ?? '').isNotEmpty) output.add(item);
    collectKuwoBoards(item['child'], output);
  }
}

/// 封面：相对路径补成 img1.kuwo.cn/star/albumcover/…；img*.kuwo.cn 的 /120/、/500/ 路径补 /star/albumcover 前缀；120 尺寸换 500。
String? kuwoImage(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final direct = _imageUrl(value);
  if (direct == null) {
    final path = value.trim().replaceFirst(RegExp(r'^/+'), '');
    return 'https://img1.kuwo.cn/star/albumcover/$path'.replaceFirst('/120/', '/500/');
  }
  var out = direct;
  final uri = Uri.tryParse(direct);
  if (uri != null && RegExp(r'^img\d*\.kuwo\.cn$', caseSensitive: false).hasMatch(uri.host) && RegExp(r'^/(?:120|500)/').hasMatch(uri.path)) {
    final at = direct.indexOf(uri.path, direct.indexOf(uri.host) + uri.host.length);
    if (at >= 0) out = '${direct.substring(0, at)}/star/albumcover${direct.substring(at)}';
  }
  return out.replaceFirst('/120/', '/500/');
}

/// 音质：N_MINFO = "level:ff,bitrate:2000,format:flac,size:31.31Mb;level:p,bitrate:320,…"。
/// size 换算成字节数（桌面端存的是格式化字符串）；没有 size 的档位保留空对象。
Json kuwoQualityDetails(Json raw) {
  final info = _s(raw['N_MINFO'] ?? raw['n_minfo'] ?? '');
  final out = <String, dynamic>{};
  for (final row in info.split(';')) {
    final quality = kuwoBitrateQuality(RegExp(r'bitrate:(\d+)').firstMatch(row)?[1]);
    if (quality == null) continue;
    final size = _kuwoSize(RegExp(r'size:([\w.]+)').firstMatch(row)?[1]);
    out[quality] = size == null ? <String, dynamic>{} : {'size': size};
  }
  return out;
}

List<String> kuwoQualities(Json raw) => _normalizeQualities(kuwoQualityDetails(raw).keys);

String? kuwoBitrateQuality(String? value) => const {'128': '128k', '320': '320k', '2000': 'flac', '4000': 'hires', '20201': 'atmos', '20501': 'atmos_plus', '20900': 'master'}[value ?? ''];

/// "31.31Mb" / "980Kb" / "1.2Gb" / "123456" → 字节。
int? _kuwoSize(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d+(?:\.\d+)?)([KMG]?)B?$', caseSensitive: false).firstMatch(value);
  if (m == null) return null;
  final n = double.parse(m[1]!);
  final unit = switch (m[2]!.toUpperCase()) { 'K' => 1024, 'M' => 1024 * 1024, 'G' => 1024 * 1024 * 1024, _ => 1 };
  final bytes = (n * unit).round();
  return bytes > 0 ? bytes : null;
}

// ───────────────────────── 通用小工具（对齐桌面端 asNumber / duration / parseDuration / makeCatalogItem 等） ─────────────────────────

/// JS String(v)：整数值的 double 不带 ".0"。
String _s(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

List<dynamic> _arr(Object? v) => v is List ? v : const [];

/// JS Number(v)，非有限数时为 0。
num _num(Object? v) {
  if (v is num) return v.isFinite ? v : 0;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    final n = num.tryParse(t) ?? (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(t) ? int.parse(t.substring(2), radix: 16) : null);
    return n != null && n.isFinite ? n : 0;
  }
  return 0;
}

/// 秒；大于 10000 的按毫秒处理。
int _duration(Object? v) {
  final n = _num(v);
  return n > 1e4 ? (n / 1000).round() : n.round();
}

/// "mm:ss"（以及 "hh:mm:ss"）或数字。
int _parseDuration(Object? v) {
  if (v is String && v.contains(':')) {
    final p = v.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (p.length >= 3) return p[0] * 3600 + p[1] * 60 + p[2];
    return p[0] * 60 + p[1];
  }
  return _duration(v);
}

String _stripHtml(String v) => v.replaceAll(RegExp(r'<[^>]+>'), '');

String _clip(String v, int n) => v.length > n ? v.substring(0, n) : v;

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

List<String> _normalizeQualities(Iterable<String> values) {
  final set = values.toSet();
  return [for (final q in qualityOrder) if (set.contains(q)) q];
}

String? _imageUrl(Object? value, [String size = '500']) {
  if (value is! String) return null;
  final url = value.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:${url.replaceFirst('{size}', size)}';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return null;
  return url.replaceFirst('{size}', size);
}

SearchResult _result({List<PTrack> songs = const [], List<CatalogItem> items = const [], required int page, required int limit, required int total}) {
  final count = songs.length + items.length;
  return SearchResult(songs: songs, items: items, total: total == 0 ? count : total, hasMore: total != 0 ? page * limit < total : count == limit);
}

/// 对齐 makeCatalogItem（歌单广场）。
CatalogItem? _catalogItem(Object? id, Object? title, Object? subtitle, Object? cover, Object? playCount, Object? trackCount, Object? date) {
  final value = _s(id);
  if (value.isEmpty) return null;
  final tc = _num(trackCount).toInt();
  return CatalogItem(
    platform: _kw,
    id: value,
    title: _s(title ?? '歌单'),
    subtitle: _s(subtitle ?? '未知创建者'),
    creator: _s(subtitle ?? ''),
    type: CatalogType.playlist,
    cover: kuwoImage(cover),
    playCount: _catalogPlayCount(playCount),
    trackCount: tc == 0 ? null : tc,
    date: _catalogDate(date),
  );
}

/// 播放量：数字原样；字符串能转数字就转，否则保留文案（「1.2万」）。
Object? _catalogPlayCount(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is! String) {
    final n = _num(v);
    return n == 0 ? null : n;
  }
  final t = v.trim();
  if (t.isEmpty) return null;
  return num.tryParse(t) ?? t;
}

/// 秒 / 毫秒时间戳或日期字符串 → 本地日期 yyyy-MM-dd。
String? _catalogDate(Object? v) {
  if (v == null || v == '') return null;
  final n = v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
  final DateTime? d = n != null ? DateTime.fromMillisecondsSinceEpoch((n < 1e12 ? n * 1000 : n).toInt()) : DateTime.tryParse(_s(v))?.toLocal();
  if (d == null) return null;
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

// ───────────────────────── GB18030 解码（酷我歌词是 GB18030 编码；Dart 没有内置解码器） ─────────────────────────

Uint16List? _gbTwo;

Uint16List _gbTwoByte() {
  final cached = _gbTwo;
  if (cached != null) return cached;
  final raw = inflateZlib(base64.decode(_gbTwoByteTable));
  final out = Uint16List(23940);
  var i = 0, prev = 0, k = 0;
  while (i < raw.length && k < out.length) {
    var z = 0, shift = 0, b = 0;
    do {
      b = raw[i++];
      z |= (b & 0x7f) << shift;
      shift += 7;
    } while ((b & 0x80) != 0);
    prev += (z & 1) != 0 ? -((z + 1) >> 1) : z >> 1;
    out[k++] = prev;
  }
  return _gbTwo = out;
}

int _gbFourByte(int pointer) {
  if (pointer >= 189000 && pointer <= 1237575) return 0x10000 + pointer - 189000;
  if (pointer < 0 || pointer > 39419) return 0xFFFD;
  var lo = 0, hi = _gbFourByteRanges.length ~/ 2 - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (_gbFourByteRanges[mid * 2] <= pointer) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return _gbFourByteRanges[lo * 2 + 1] + pointer - _gbFourByteRanges[lo * 2];
}

/// GB18030 → String（行为对齐 WHATWG / Node TextDecoder('gb18030')，非法字节输出 U+FFFD）。
String gb18030Decode(List<int> bytes) {
  final sb = StringBuffer();
  final n = bytes.length;
  var i = 0;
  while (i < n) {
    final b = bytes[i];
    if (b < 0x80) {
      sb.writeCharCode(b);
      i++;
      continue;
    }
    if (b == 0x80) {
      sb.writeCharCode(0x20AC);
      i++;
      continue;
    }
    if (b == 0xFF || i + 1 >= n) {
      sb.writeCharCode(0xFFFD);
      i++;
      continue;
    }
    final b2 = bytes[i + 1];
    if (b2 >= 0x30 && b2 <= 0x39) {
      if (i + 3 < n && bytes[i + 2] >= 0x81 && bytes[i + 2] <= 0xFE && bytes[i + 3] >= 0x30 && bytes[i + 3] <= 0x39) {
        final pointer = (((b - 0x81) * 10 + (b2 - 0x30)) * 126 + (bytes[i + 2] - 0x81)) * 10 + (bytes[i + 3] - 0x30);
        sb.writeCharCode(_gbFourByte(pointer));
        i += 4;
      } else {
        sb.writeCharCode(0xFFFD);
        i++;
      }
      continue;
    }
    if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
      sb.writeCharCode(_gbTwoByte()[(b - 0x81) * 190 + (b2 < 0x7F ? b2 - 0x40 : b2 - 0x41)]);
      i += 2;
      continue;
    }
    // 非法尾字节：ASCII 尾字节留给下一轮处理
    sb.writeCharCode(0xFFFD);
    i += b2 < 0x80 ? 1 : 2;
  }
  return sb.toString();
}

/// GB18030 双字节区码表（lead 0x81–0xFE × trail 0x40–0xFE，跳过 0x7F，共 23940 项）：
/// 码点差值 zigzag varint 编码后 zlib 压缩再 base64，由 Node TextDecoder('gb18030') 生成。
const String _gbTwoByteTable =
    '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';

/// GB18030 四字节 BMP 区：分段线性映射 [线性下标, 起始码点, …]。
const List<int> _gbFourByteRanges = [
  0, 128, 36, 165, 38, 169, 45, 178, 50, 184, 81, 216, 89, 226, 95, 235,
  96, 238, 100, 244, 103, 248, 104, 251, 105, 253, 109, 258, 126, 276, 133, 284,
  148, 300, 172, 325, 175, 329, 179, 334, 208, 364, 306, 463, 307, 465, 308, 467,
  309, 469, 310, 471, 311, 473, 312, 475, 313, 477, 341, 506, 428, 594, 443, 610,
  544, 712, 545, 716, 558, 730, 741, 930, 742, 938, 749, 962, 750, 970, 805, 1026,
  819, 1104, 820, 1106, 7457, 59335, 7458, 7744, 7922, 8209, 7924, 8215, 7925, 8218, 7927, 8222,
  7934, 8231, 7943, 8241, 7944, 8244, 7945, 8246, 7950, 8252, 8062, 8365, 8148, 8452, 8149, 8454,
  8152, 8458, 8164, 8471, 8174, 8482, 8236, 8556, 8240, 8570, 8262, 8596, 8264, 8602, 8374, 8713,
  8380, 8720, 8381, 8722, 8384, 8726, 8388, 8731, 8390, 8737, 8392, 8740, 8393, 8742, 8394, 8748,
  8396, 8751, 8401, 8760, 8406, 8766, 8416, 8777, 8419, 8781, 8424, 8787, 8437, 8802, 8439, 8808,
  8445, 8816, 8482, 8854, 8485, 8858, 8496, 8870, 8521, 8896, 8603, 8979, 8936, 9322, 8946, 9372,
  9046, 9548, 9050, 9588, 9063, 9616, 9066, 9622, 9076, 9634, 9092, 9652, 9100, 9662, 9108, 9672,
  9111, 9676, 9113, 9680, 9131, 9702, 9162, 9735, 9164, 9738, 9218, 9793, 9219, 9795, 11329, 11906,
  11331, 11909, 11334, 11913, 11336, 11917, 11346, 11928, 11361, 11944, 11363, 11947, 11366, 11951, 11370, 11956,
  11372, 11960, 11375, 11964, 11389, 11979, 11682, 12284, 11686, 12292, 11687, 12312, 11692, 12319, 11694, 12330,
  11714, 12351, 11716, 12436, 11723, 12447, 11725, 12535, 11730, 12543, 11736, 12586, 11982, 12842, 11989, 12850,
  12102, 12964, 12336, 13200, 12348, 13215, 12350, 13218, 12384, 13253, 12393, 13263, 12395, 13267, 12397, 13270,
  12510, 13384, 12553, 13428, 12851, 13727, 12962, 13839, 12973, 13851, 13738, 14617, 13823, 14703, 13919, 14801,
  13933, 14816, 14080, 14964, 14298, 15183, 14585, 15471, 14698, 15585, 15583, 16471, 15847, 16736, 16318, 17208,
  16434, 17325, 16438, 17330, 16481, 17374, 16729, 17623, 17102, 17997, 17122, 18018, 17315, 18212, 17320, 18218,
  17402, 18301, 17418, 18318, 17859, 18760, 17909, 18811, 17911, 18814, 17915, 18820, 17916, 18823, 17936, 18844,
  17939, 18848, 17961, 18872, 18664, 19576, 18703, 19620, 18814, 19738, 18962, 19887, 19043, 40870, 33469, 59244,
  33470, 59336, 33471, 59367, 33484, 59413, 33485, 59417, 33490, 59423, 33497, 59431, 33501, 59437, 33505, 59443,
  33513, 59452, 33520, 59460, 33536, 59478, 33550, 59493, 37845, 63789, 37921, 63866, 37948, 63894, 38029, 63976,
  38038, 63986, 38064, 64016, 38065, 64018, 38066, 64021, 38069, 64025, 38075, 64034, 38076, 64037, 38078, 64042,
  39108, 65074, 39109, 65093, 39113, 65107, 39114, 65112, 39115, 65127, 39116, 65132, 39265, 65375, 39394, 65510,
];
