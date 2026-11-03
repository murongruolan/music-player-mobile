// 咪咕音乐（mg）。对齐桌面端 platform-service.ts 的 *Migu / normalizeMigu* / collectMiguBoards / collectMiguPlaylists / miguImage，
// 以及 platform-crypto.ts 的 decodeMiguMrc（MRC 歌词 TEA 解密）和搜索签名。
// 注意：咪咕接口在桌面端也从未实测通过，字段名按桌面端代码照搬。
import 'dart:convert';
import 'dart:math' show max, min;
import '../net/json.dart';
import 'crypto_util.dart';
import 'models.dart';
import 'platform.dart';

const _mg = Plat.mg;

const _baseHeaders = {'Referer': 'https://y.qq.com/'};
const _mobileReferer = {'Referer': 'https://m.music.migu.cn/'};
const _appHeaders = {'Referer': 'https://app.c.nf.migu.cn/', 'channel': '0146921'};

/// 搜索用的固定设备 ID（桌面端写死）。
const miguDeviceId = '963B7AA0D21511ED807EE5846EC87D20';

/// 搜索签名：MD5(关键词 + 固定盐 + deviceId + 毫秒时间戳字符串)，小写 hex。
String miguSearchSign(String keyword, String deviceId, String time) =>
    md5Hex('${keyword}6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50$deviceId$time');

// ───────────────────────── MRC 解密（XXTEA 变体，64 位有符号长整型运算） ─────────────────────────

final _teaKey = [
  BigInt.parse('27303562373562475'),
  BigInt.parse('18014862372307051'),
  BigInt.parse('22799692160172081'),
  BigInt.parse('34058940340699235'),
  BigInt.parse('30962724186095721'),
  BigInt.parse('27303523720101991'),
  BigInt.parse('27303523720101998'),
  BigInt.parse('31244139033526382'),
  BigInt.parse('28992395054481524'),
];
final _delta = BigInt.from(2654435769);
final _three = BigInt.from(3);

/// 桌面端 toMiguLong：超出 int64 范围时按 2^64 回绕（Java long 语义）。用 BigInt 以便 Web 上结果一致。
BigInt _long(BigInt v) => v.toSigned(64);

/// 咪咕 MRC 歌词解密：内容是 hex 文本，每 16 个字符一个 64 位字，XXTEA 解密后按小端取字节，UTF-16LE 解码。
/// 返回带逐字时间的原文（`[起始,时长]字(起始,时长)…`）；不足 32 个字符或不是 hex 时原样返回。
String decodeMiguMrc(String content) {
  if (content.length < 32) return content;
  final values = <BigInt>[];
  try {
    for (var i = 0; i + 16 <= content.length; i += 16) {
      values.add(_long(BigInt.parse(content.substring(i, i + 16), radix: 16)));
    }
  } on FormatException {
    return content;
  }
  final n = values.length;
  if (n > 0) {
    var previous = values[0];
    var sum = _long(BigInt.from(6 + 52 ~/ n) * _delta);
    while (sum != BigInt.zero) {
      final selector = _three & (sum >> 2);
      for (var i = n - 1; i > 0; i--) {
        final prior = values[i - 1];
        final key = _teaKey[((_three & BigInt.from(i)) ^ selector).toInt()];
        previous = _long(values[i] - (_long((previous ^ sum) + (prior ^ key)) ^ _long(((prior >> 5) ^ (previous << 2)) + ((previous >> 3) ^ (prior << 4)))));
        values[i] = previous;
      }
      final last = values[n - 1];
      final key = _teaKey[selector.toInt()];
      previous = _long(values[0] - (_long((key ^ last) + (previous ^ sum)) ^ _long(((last >> 5) ^ (previous << 2)) + ((previous >> 3) ^ (last << 4)))));
      values[0] = previous;
      sum = _long(sum - _delta);
    }
  }
  final mask = BigInt.from(0xff);
  final bytes = <int>[];
  for (final value in values) {
    var current = value;
    for (var k = 0; k < 8; k++) {
      bytes.add((current & mask).toInt());
      current = current >> 8;
    }
  }
  final units = [for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8)];
  return String.fromCharCodes(units).replaceFirst(RegExp(r'\x00+$'), '');
}

/// MRC 原文 → 标准 LRC + 逐字。行头可能是 `[起始毫秒,时长]` 或 `[mm:ss.xx]`；字标记 `(绝对起始,时长)` 写在字后面（也兼容写在字前面）。
({String lrc, List<LyricLineWords>? words}) parseMiguMrc(String text) {
  final msTag = RegExp(r'^\[(\d+),(\d+)(?:,\d+)?\]');
  final lrcTag = RegExp(r'^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final marker = RegExp(r'\((-?\d+),(-?\d+)\)');
  final lines = <String>[];
  final words = <LyricLineWords>[];
  for (final raw in text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final ms = msTag.firstMatch(line);
    final lrc = ms == null ? lrcTag.firstMatch(line) : null;
    if (ms == null && lrc == null) {
      lines.add(line.replaceAll(marker, ''));
      continue;
    }
    final int start;
    int? lineDuration;
    final String head;
    if (ms != null) {
      start = int.parse(ms[1]!);
      lineDuration = int.parse(ms[2]!);
      head = _lrcStamp(start);
    } else {
      final l = lrc!;
      final frac = (l[3] ?? '0').padRight(3, '0').substring(0, 3);
      start = (int.parse(l[1]!) * 60 + int.parse(l[2]!)) * 1000 + int.parse(frac);
      head = l[0]!;
    }
    final body = line.substring((ms ?? lrc)!.end);
    final value = body.replaceAll(marker, '').trim();
    if (value.isEmpty) continue;
    lines.add('$head$value');
    final matches = marker.allMatches(body).toList();
    if (matches.isEmpty) continue;
    final prefixed = matches.first.start == 0;
    final parts = <({int start, int duration, String text})>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final from = prefixed ? m.end : (i == 0 ? 0 : matches[i - 1].end);
      final to = prefixed ? (i + 1 < matches.length ? matches[i + 1].start : body.length) : m.start;
      final word = body.substring(from, to);
      if (word.isEmpty) continue;
      final d = int.parse(m[2]!);
      parts.add((start: int.parse(m[1]!), duration: d < 0 ? 0 : d, text: word));
    }
    if (parts.isEmpty) continue;
    final end = parts.map((p) => p.start + p.duration).reduce((a, b) => a > b ? a : b);
    words.add(LyricLineWords(start, lineDuration ?? (end - start < 0 ? 0 : end - start), value, parts));
  }
  return (lrc: lines.join('\n'), words: words.isEmpty ? null : words);
}

/// 毫秒 → `[mm:ss.sss]`（对齐 qrcTimestamp）。
String _lrcStamp(int ms) {
  final total = (ms < 0 ? 0 : ms) / 1000;
  final m = total ~/ 60;
  final s = total - m * 60;
  return '[${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(3).padLeft(6, '0')}]';
}

class MiguPlatform extends MusicPlatform {
  MiguPlatform(super.http);

  @override
  String get code => _mg;

  Future<dynamic> _get(String url, [Map<String, String> headers = _baseHeaders]) => http.getJson(_mg, url, headers: headers);

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    final clean = keyword.trim().length > 100 ? keyword.trim().substring(0, 100) : keyword.trim();
    if (clean.isEmpty || (type != SearchType.song && type != SearchType.playlist)) return const SearchResult();
    final isPlaylist = type == SearchType.playlist;
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final searchSwitch = Uri.encodeComponent(jsonEncode({'song': isPlaylist ? 0 : 1, 'album': 0, 'singer': 0, 'tagSong': 1, 'mvSong': 0, 'bestShow': 1, 'songlist': isPlaylist ? 1 : 0, 'lyricSong': 0}));
    final data = asJson(await _get(
      'https://jadeite.migu.cn/music_search/v3/search/searchAll?isCorrect=0&isCopyright=1&searchSwitch=$searchSwitch&pageSize=$limit&text=${Uri.encodeComponent(clean)}&pageNo=$page&sort=0&sid=USS',
      {
        ..._baseHeaders,
        'uiVersion': 'A_music_3.6.1',
        'deviceId': miguDeviceId,
        'timestamp': time,
        'sign': miguSearchSign(clean, miguDeviceId, time),
        'channel': '0146921',
        'Referer': 'https://music.migu.cn/',
      },
    ));
    if (_s(data['code']) != '000000') throw PlatformException(_mg, _s(data['info'] ?? '咪咕音乐搜索暂时不可用'));
    final result = asJson(isPlaylist ? data['songListResultData'] : data['songResultData']);
    final rawRows = _arr(result['result'] ?? result['resultList']);
    // resultList 是二维数组（按分组），result 是一维
    final rows = rawRows.any((e) => e is List) ? [for (final g in rawRows) ..._arr(g)] : rawRows;
    final total = _num(result['totalCount']).toInt();
    if (isPlaylist) {
      final items = rows.map((raw) => normalizeMiguPlaylist(asJson(raw))).whereType<CatalogItem>().toList();
      return _result(items: items, page: page, limit: limit, total: total);
    }
    return _result(songs: _tracks(rows), page: page, limit: limit, total: total);
  }

  /// 桌面端没有独立的咪咕联想接口，这里不提供。
  @override
  Future<List<String>> suggest(String keyword) async => const [];

  @override
  Future<List<String>> hotSearch() async {
    final data = asJson(await _get('http://jadeite.migu.cn:7090/music_search/v3/search/hotword', {'Referer': 'https://music.migu.cn/v3'}));
    return _uniqueWords([
      for (final g in _arr(asJson(data['data'])['hotwords']))
        for (final item in _arr(asJson(g)['hotwordList']))
          if (_s(asJson(item)['resourceType']) == 'song') asJson(item)['word'],
    ]);
  }

  /// 前两项对齐桌面端：「推荐」「全部」（都走推荐歌单广场）；其余分类 id 是咪咕 tagId。
  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final data = asJson(await _get('https://app.c.nf.migu.cn/pc/v1.0/template/musiclistplaza-taglist/release', _mobileReferer));
    final out = <PlaylistCategory>[const PlaylistCategory('recommend', '推荐'), const PlaylistCategory('全部', '全部', group: '默认')];
    for (final row in _arr(data['data'])) {
      final r = asJson(row);
      for (final item in _arr(r['content'])) {
        final texts = _arr(asJson(item)['texts']);
        final name = texts.isNotEmpty ? _s(texts[0]) : '';
        if (name.isEmpty) continue;
        out.add(PlaylistCategory(texts.length > 1 ? _s(texts[1]) : '', name, group: _s(r['title'] ?? r['name'] ?? '分类')));
      }
    }
    return out;
  }

  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    var tag = category?.trim() ?? '';
    if (tag.contains('::')) tag = tag.substring(tag.indexOf('::') + 2);
    final tagged = tag.isNotEmpty && tag != '全部' && tag != 'recommend';
    final url = tagged
        ? 'https://app.c.nf.migu.cn/pc/v1.0/template/musiclistplaza-listbytag/release?pageNumber=$page&templateVersion=2&tagId=${Uri.encodeComponent(tag)}'
        : 'https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0?templateVersion=2&pageNo=$page';
    final data = asJson(await _get(url, _mobileReferer));
    final rows = <Json>[];
    collectMiguPlaylists(data['data'], rows);
    final items = rows
        .map((item) {
          final bar = _arr(item['barList']);
          return _catalogItem(item['resId'] ?? asJson(item['logEvent'])['contentId'], item['txt'] ?? item['title'], '', item['img'] ?? item['imageUrl'], bar.isEmpty ? null : asJson(bar[0])['title'],
              item['createTime'] ?? item['updateTime'] ?? item['create_time']);
        })
        .whereType<CatalogItem>()
        .take(limit)
        .toList();
    return Page(items, page: page, limit: limit, total: items.length, hasMore: items.length == limit);
  }

  @override
  Future<List<CatalogItem>> leaderboards() async {
    final data = asJson(await _get('https://app.c.nf.migu.cn/pc/bmw/rank/rank-index/v1.0', _appHeaders));
    final rows = <Json>[];
    collectMiguBoards(data['data'], rows);
    return [
      for (final item in rows)
        CatalogItem(platform: _mg, id: _s(item['rankId']), title: _s(item['rankName'] ?? '歌单'), subtitle: '咪咕音乐实时榜单', type: CatalogType.leaderboard, cover: miguImage(item['imageUrl'])),
    ];
  }

  @override
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100}) async {
    final clean = id.trim();
    if (clean.isEmpty) throw const PlatformException(_mg, '音乐详情缺少 ID');
    final q = Uri.encodeComponent(clean);
    if (type == CatalogType.playlist) {
      // 歌曲列表接口每页最多 50 首
      final pageSize = limit < 50 ? limit : 50;
      final res = await Future.wait([
        _get('https://c.musicapp.migu.cn/MIGUM3.0/resource/playlist/v2.0?playlistId=$q', _mobileReferer),
        _get('https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0?pageNo=$page&pageSize=$pageSize&playlistId=$q', _mobileReferer),
      ]);
      final detail = asJson(asJson(res[0])['data']);
      final songData = asJson(asJson(res[1])['data']);
      final total = _num(songData['totalCount']).toInt();
      return Collection(
        platform: _mg,
        id: clean,
        type: type,
        title: _s(detail['title'] ?? '咪咕歌单'),
        description: _s(detail['summary'] ?? ''),
        cover: miguImage(asJson(detail['imgItem'])['img']),
        creator: _s(detail['ownerName'] ?? ''),
        tracks: _tracks(_arr(songData['songList'])),
        total: total,
        page: page,
        limit: pageSize,
        hasMore: page * pageSize < total,
      );
    }
    if (type == CatalogType.leaderboard) {
      final data = asJson(await _get('https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do?columnId=$q&needAll=0', _appHeaders));
      if (_s(data['code']) != '000000') throw const PlatformException(_mg, '咪咕榜单暂时不可用');
      // 接口一次返回整榜，本地分页
      final all = _tracks(_arr(asJson(data['columnInfo'])['contents']).map((e) => asJson(e)['objectInfo']).toList());
      final from = max(0, min((page - 1) * limit, all.length)), to = max(from, min(page * limit, all.length));
      return Collection(platform: _mg, id: clean, type: type, title: '咪咕榜单 $clean', tracks: all.sublist(from, to), total: all.length, page: page, limit: limit, hasMore: page * limit < all.length);
    }
    throw const PlatformException(_mg, '咪咕音乐暂不支持此类型详情');
  }

  @override
  Future<Lyric> lyric(PTrack track) async {
    final id = _s(track.identity['copyrightId'] ?? track.identity['contentId'] ?? track.nativeId);
    if (id.isEmpty) throw const PlatformException(_mg, '咪咕歌曲 ID 不可用');
    final data = asJson(await http.postForm(_mg, 'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2', {'resourceId': id}, headers: {..._baseHeaders, 'Referer': 'https://music.migu.cn/'}));
    final resource = _arr(data['resource']);
    final info = resource.isEmpty ? <String, dynamic>{} : asJson(resource[0]);
    // 接口没给地址时退回到搜索结果里带的歌词地址
    String pick(String k) => _s(info[k]).isNotEmpty ? _s(info[k]) : _s(track.identity[k]);
    final mrcUrl = pick('mrcUrl'), lrcUrl = pick('lrcUrl'), trcUrl = pick('trcUrl');
    if (mrcUrl.isEmpty && lrcUrl.isEmpty) throw const PlatformException(_mg, '咪咕没有歌词');
    Future<String> get(String url) async => url.isEmpty ? '' : await http.text(_mg, 'GET', Uri.parse(url), headers: _appHeaders);
    final translation = await get(trcUrl);
    if (mrcUrl.isNotEmpty) {
      final parsed = parseMiguMrc(decodeMiguMrc((await get(mrcUrl)).trim()));
      return Lyric(parsed.lrc, translation: translation.isEmpty ? null : translation, words: parsed.words);
    }
    return Lyric(await get(lrcUrl), translation: translation.isEmpty ? null : translation);
  }
}

// ───────────────────────── 规范化（对齐 normalizeMigu / normalizeMiguPlaylist / collectMigu*） ─────────────────────────

List<PTrack> _tracks(List<dynamic> rows) => rows.map((raw) => normalizeMigu(asJson(raw))).whereType<PTrack>().toList();

/// 单曲。identity 带 copyrightId / contentId（播放、歌词都用），nativeId 用 copyrightId。
PTrack? normalizeMigu(Json raw) {
  final id = _s(raw['songId'] ?? raw['id'] ?? raw['copyrightId'] ?? raw['contentId'] ?? '');
  if (id.isEmpty) return null;
  final title = _s(raw['songName'] ?? raw['title'] ?? raw['name'] ?? '');
  var artist = _s(raw['singerName'] ?? raw['artist'] ?? '');
  if (artist.isEmpty) artist = _arr(raw['singerList']).map((e) => _s(asJson(e)['name'] ?? '')).where((e) => e.isNotEmpty).join(' / ');
  final album = _s(raw['albumName'] ?? raw['album'] ?? '');
  String? cover;
  for (final v in [raw['cover'], raw['img3'], raw['img2'], raw['img1'], raw['imgItems'], raw['albumImgs'], raw['imageUrl'], raw['imgUrl'], raw['albumPic'], raw['albumImg']]) {
    cover = miguImage(v);
    if (cover != null) break;
  }
  final copyrightId = _s(raw['copyrightId'] ?? id);
  String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
  final lrcUrl = str(raw['lrcUrl'] ?? raw['lyricUrl']), mrcUrl = str(raw['mrcUrl'] ?? raw['mrcurl']), trcUrl = str(raw['trcUrl']);
  final details = miguQualityDetails(raw);
  final qualities = miguQualities(raw);
  return PTrack(
    platform: _mg,
    nativeId: copyrightId,
    title: title,
    artist: artist,
    album: album,
    duration: _parseDuration(raw['length'] ?? raw['duration']),
    cover: cover,
    qualities: qualities.isEmpty ? const ['128k'] : qualities,
    identity: {
      'songId': id,
      'albumId': _s(raw['albumId'] ?? ''),
      'contentId': _s(raw['contentId'] ?? raw['songId'] ?? id),
      'copyrightId': copyrightId,
      if (lrcUrl != null) 'lrcUrl': lrcUrl,
      if (mrcUrl != null) 'mrcUrl': mrcUrl,
      if (trcUrl != null) 'trcUrl': trcUrl,
    },
    qualityDetails: details,
  );
}

/// 搜索结果里的歌单。
CatalogItem? normalizeMiguPlaylist(Json raw) {
  final id = _s(raw['id'] ?? raw['contentId'] ?? '');
  if (id.isEmpty) return null;
  final count = _num(raw['playNum']);
  return CatalogItem(platform: _mg, id: id, title: _s(raw['name'] ?? ''), subtitle: _s(raw['userName'] ?? ''), creator: _s(raw['userName'] ?? ''), type: CatalogType.playlist, cover: miguImage(raw['musicListPicUrl']), playCount: count == 0 ? null : count);
}

/// 歌单广场：递归找 resType（或 logEvent.resourceType / contentType）为 "2021" 的节点。
void collectMiguPlaylists(Object? value, List<Json> output) {
  if (value is List) {
    for (final item in value) {
      collectMiguPlaylists(item, output);
    }
    return;
  }
  if (value is! Map) return;
  final record = asJson(value);
  final log = asJson(record['logEvent']);
  if (_s(record['resType'] ?? log['resourceType'] ?? log['contentType'] ?? 'undefined') == '2021') output.add(record);
  for (final key in const ['contents', 'contentItemList', 'content', 'itemList']) {
    if (_truthy(record[key])) collectMiguPlaylists(record[key], output);
  }
}

/// 榜单首页：递归找带 rankId 的节点，按 rankId 去重。
void collectMiguBoards(Object? value, List<Json> output, [Set<String>? seen]) {
  seen ??= <String>{};
  if (value is List) {
    for (final item in value) {
      collectMiguBoards(item, output, seen);
    }
    return;
  }
  if (value is! Map) return;
  final item = asJson(value);
  final id = _s(item['rankId'] ?? '');
  if (id.isNotEmpty && seen.add(id)) output.add(item);
  for (final key in const ['contents', 'contentItemList', 'itemList']) {
    if (_truthy(item[key])) collectMiguBoards(item[key], output, seen);
  }
}

/// 封面：数组取第一个可用的；对象依次看 img / webpImg / url / imageUrl；相对路径补 d.musicapp.migu.cn；http 升级为 https。
String? miguImage(Object? value) {
  if (value is List) {
    for (final item in value) {
      final r = miguImage(item);
      if (r != null) return r;
    }
    return null;
  }
  if (value is Map) {
    for (final key in const ['img', 'webpImg', 'url', 'imageUrl']) {
      final r = miguImage(value[key]);
      if (r != null) return r;
    }
    return null;
  }
  final direct = _imageUrl(value);
  if (direct != null) return direct.replaceFirst(RegExp(r'^http://d\.musicapp\.migu\.cn/', caseSensitive: false), 'https://d.musicapp.migu.cn/');
  if (value is! String) return null;
  final path = value.trim();
  if (path.isEmpty) return null;
  return 'https://d.musicapp.migu.cn/${path.replaceFirst(RegExp(r'^/+'), '')}';
}

/// 音质：audioFormats / newRateFormats 的 formatType（PQ / HQ / SQ / ZQ / ZQ24）；size 存字节数，没有大小时保留空对象。
Json miguQualityDetails(Json raw) {
  final out = <String, dynamic>{};
  for (final value in _arr(raw['audioFormats'] ?? raw['newRateFormats'])) {
    final item = asJson(value);
    final quality = miguFormatQuality(_s(item['formatType'] ?? ''));
    if (quality == null) continue;
    final size = _num(item['asize'] ?? item['isize'] ?? item['size'] ?? item['androidSize']).toInt();
    out[quality] = size > 0 ? {'size': size} : <String, dynamic>{};
  }
  return out;
}

/// 没有音质信息但有 contentId / copyrightId 时默认 128k。
List<String> miguQualities(Json raw) {
  final values = miguQualityDetails(raw).keys.toList();
  if (values.isEmpty && (_truthy(raw['contentId']) || _truthy(raw['copyrightId']))) values.add('128k');
  final set = values.toSet();
  return [for (final q in qualityOrder) if (set.contains(q)) q];
}

String? miguFormatQuality(String value) => const {'PQ': '128k', 'HQ': '320k', 'SQ': 'flac', 'ZQ': 'hires', 'ZQ24': 'hires'}[value];

// ───────────────────────── 通用小工具（对齐桌面端 asNumber / duration / parseDuration / makeCatalogItem 等） ─────────────────────────

String _s(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

/// JS 真值判断（用于 `if (record[key])`）。
bool _truthy(Object? v) => v != null && v != false && v != 0 && v != '';

List<dynamic> _arr(Object? v) => v is List ? v : const [];

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

int _duration(Object? v) {
  final n = _num(v);
  return n > 1e4 ? (n / 1000).round() : n.round();
}

/// "mm:ss" / "hh:mm:ss"（咪咕榜单的 length 是 "00:03:58"，桌面端按 mm:ss 取前两段会算错，这里按三段处理）或数字。
int _parseDuration(Object? v) {
  if (v is String && v.contains(':')) {
    final p = v.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (p.length >= 3) return p[0] * 3600 + p[1] * 60 + p[2];
    return p[0] * 60 + p[1];
  }
  return _duration(v);
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

CatalogItem? _catalogItem(Object? id, Object? title, Object? subtitle, Object? cover, Object? playCount, Object? date) {
  final value = _s(id);
  if (value.isEmpty) return null;
  return CatalogItem(
    platform: _mg,
    id: value,
    title: _s(title ?? '歌单'),
    subtitle: _s(subtitle ?? '未知创建者'),
    creator: _s(subtitle ?? ''),
    type: CatalogType.playlist,
    cover: miguImage(cover),
    playCount: _catalogPlayCount(playCount),
    date: _catalogDate(date),
  );
}

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

String? _catalogDate(Object? v) {
  if (v == null || v == '') return null;
  final n = v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
  final DateTime? d = n != null ? DateTime.fromMillisecondsSinceEpoch((n < 1e12 ? n * 1000 : n).toInt()) : DateTime.tryParse(_s(v))?.toLocal();
  if (d == null) return null;
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
