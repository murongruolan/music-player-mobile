// 酷狗音乐（kg）。逐个对齐桌面端 platform-service.ts 的 *Kugou 方法、normalizeKugou* 与质量 / hash 辅助函数，
// 以及 platform-crypto.ts 的 requestKugouSongSearch / requestKugouAlbumInfo / kugouCollectionHeaders /
// parseEmbeddedJson* / decodeKrc，platform-account-crypto.ts 的 kugouWebSignature / kugouAndroidSignature。
//
// 注意：榜单 / 歌单广场 / 歌手 / 专辑等接口桌面端就是 http://（酷狗没有对应 https 域名），
// Android 需要在网络安全配置里放行这些域名的明文流量。
import 'dart:convert';
import 'dart:math';
import '../net/json.dart';
import 'crypto_util.dart';
import 'models.dart';
import 'platform.dart';

const _ua = 'Mozilla/5.0 Sollin/0.1';

/// 桌面端 platform-service.ts 的 `headers`（桌面端所有平台共用同一个默认 Referer）。
const _headers = {'User-Agent': _ua, 'Referer': 'https://y.qq.com/'};
const _kugouHeaders = {'User-Agent': _ua, 'Referer': 'https://www.kugou.com/'};

/// 歌词服务要伪装成 PC 客户端的搜索模块。
const _lyricHeaders = {'User-Agent': 'KuGou2012-9020-ExpandSearchManager', 'Referer': 'https://y.qq.com/', 'KG-RC': '1', 'KG-THash': 'expand_search_manager.cpp:852736169:451'};

/// KRC 解密用的 16 字节异或表。
const _krcKey = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105];

// ───────────────────────────── 签名 ─────────────────────────────

/// 酷狗 Web / H5 接口签名：`k=v` 整体排序后拼接，前后加盐取 MD5。值按原样参与（不做 URL 编码）。
String kugouWebSignature(Map<String, String> params) {
  const salt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  final content = (params.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join();
  return md5Hex('$salt$content$salt');
}

/// 酷狗 Android 客户端签名：按 key 排序拼 `k=v`，再接请求体，前后加盐取 MD5。
String kugouAndroidSignature(Map<String, String> params, [String body = '']) {
  const salt = 'OIlwieks28dk2k092lksi2UIkp';
  final keys = params.keys.toList()..sort();
  final content = keys.map((k) => '$k=${params[k]}').join();
  return md5Hex('$salt$content$body$salt');
}

/// 桌面端 kugouCollectionHeaders：H5 分享页的伪装头，mid / clienttime 要和 query 里的一致。
Map<String, String> kugouCollectionHeaders(String clienttime) => {
      'mid': clienttime,
      'Referer': 'https://m3ws.kugou.com/share/index.php',
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1',
      'dfid': '-',
      'clienttime': clienttime,
    };

// ───────────────────────────── KRC ─────────────────────────────

/// 桌面端 decodeKrc 的原样结果：[lyric] / [extended] 仍是 KRC 行格式（`[start,dur]<off,dur,0>字`），
/// [translation] / [romanization] 来自 `[language:base64(JSON)]`，已是 LRC。
typedef KrcText = ({String lyric, String? translation, String? romanization, String extended});

/// base64 → 跳过 4 字节头 `krc1` → 循环异或 [_krcKey] → zlib 解压。
KrcText decodeKrc(String content) {
  final List<int> input;
  try {
    input = base64.decode(_padBase64(content.replaceAll(RegExp(r'\s'), '')));
  } catch (e) {
    throw PlatformException(Plat.kg, '酷狗歌词解码失败', e);
  }
  if (input.length <= 4) throw const PlatformException(Plat.kg, '酷狗歌词解码失败');
  final body = [for (var i = 4; i < input.length; i++) input[i] ^ _krcKey[(i - 4) % _krcKey.length]];
  final String decoded;
  try {
    decoded = utf8.decode(inflateZlib(body), allowMalformed: true).replaceAll('\r', '');
  } catch (e) {
    throw PlatformException(Plat.kg, '酷狗歌词解码失败', e);
  }
  // archive 的 zlib 遇到坏数据会返回空而不是抛错（Node 的 inflateSync 会抛）
  if (decoded.trim().isEmpty) throw const PlatformException(Plat.kg, '酷狗歌词解码失败');
  var translation = '', romanization = '';
  final language = RegExp(r'\[language:([\w=\\/+]+)\]').firstMatch(decoded);
  if (language != null) {
    try {
      final entries = _arr(asJson(jsonDecode(utf8.decode(base64.decode(_padBase64(language.group(1)!)))))['content']).map(asJson).toList();
      // 翻译 / 音译按行序对齐原文的 [毫秒,…] 行
      final lineTags = RegExp(r'^\[(\d+),', multiLine: true).allMatches(decoded).map((m) => _lrcStamp(int.parse(m.group(1)!))).toList();
      String languageLines(Json entry) {
        final lines = _arr(entry['lyricContent']);
        return [
          for (var i = 0; i < lines.length; i++)
            '${i < lineTags.length ? lineTags[i] : ''}${(lines[i] is List ? (lines[i] as List).map(_s).join() : _s(lines[i])).replaceAll(RegExp(r'\(\d+,\d+(?:,\d+)?\)'), '')}',
        ].where((l) => l.trim().isNotEmpty).join('\n');
      }

      Json find(int type) => entries.firstWhere((e) => e['type'] == type, orElse: () => <String, dynamic>{});
      translation = languageLines(find(1));
      romanization = languageLines(find(0));
    } catch (_) {
      // language 段损坏不影响原文
    }
  }
  final extended = decoded.replaceFirst(RegExp(r'\[language:[^\]]+\]\n?'), '').replaceFirst(RegExp(r'^.*\[id:\$\w+\]\n'), '');
  return (
    lyric: extended.replaceAll(RegExp(r'\(\d+,\d+(?:,\d+)?\)'), ''),
    translation: translation.isEmpty ? null : translation,
    romanization: romanization.isEmpty ? null : romanization,
    extended: extended,
  );
}

/// KRC 行（`[start,dur]<off,dur,0>字…`，off 相对行首）转标准 LRC + 逐字；元数据行（[ar:] 等）原样保留。
Lyric krcToLyric(KrcText krc) {
  final lrc = <String>[];
  final lines = <LyricLineWords>[];
  final lineRe = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final marker = RegExp(r'<(\d+),(\d+)(?:,-?\d+)?>');
  for (final raw in krc.extended.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = lineRe.firstMatch(line);
    if (m == null) {
      if (RegExp(r'^\[[A-Za-z#]+:').hasMatch(line)) lrc.add(line);
      continue;
    }
    final start = int.parse(m.group(1)!), dur = int.parse(m.group(2)!);
    final rest = m.group(3)!;
    final marks = marker.allMatches(rest).toList();
    final words = <({int start, int duration, String text})>[];
    for (var i = 0; i < marks.length; i++) {
      final text = rest.substring(marks[i].end, i + 1 < marks.length ? marks[i + 1].start : rest.length);
      if (text.isEmpty) continue;
      words.add((start: start + int.parse(marks[i].group(1)!), duration: int.parse(marks[i].group(2)!), text: text));
    }
    final visible = rest.replaceAll(marker, '').trim();
    if (visible.isEmpty) continue;
    lrc.add('${_lrcStamp(start)}$visible');
    if (words.isNotEmpty) lines.add(LyricLineWords(start, dur, visible, words));
  }
  return Lyric(lrc.join('\n'), translation: krc.translation, romanization: krc.romanization, words: lines.isEmpty ? null : lines);
}

String _lrcStamp(int ms) {
  final v = max(0, ms);
  final m = v ~/ 60000, rest = v % 60000;
  return '[${'$m'.padLeft(2, '0')}:${'${rest ~/ 1000}'.padLeft(2, '0')}.${'${rest % 1000}'.padLeft(3, '0')}]';
}

String _padBase64(String s) => s.length % 4 == 0 ? s : s.padRight(s.length + 4 - s.length % 4, '=');

// ───────────────────────────── 网页内嵌 JSON ─────────────────────────────

/// 桌面端 parseEmbeddedJsonArray：找 `var name = [` 并按括号配对（跳过字符串里的括号）截出 JSON。
List<dynamic> parseEmbeddedJsonArray(String html, String name) {
  final v = _parseEmbeddedJson(html, name, '[', ']');
  return v is List ? v : const [];
}

Json? parseEmbeddedJsonObject(String html, String name) {
  final v = _parseEmbeddedJson(html, name, '{', '}');
  return v is Map ? v.cast<String, dynamic>() : null;
}

Object? _parseEmbeddedJson(String html, String name, String open, String close) {
  final assignment = RegExp('(?:var\\s+)?$name\\s*=\\s*\\$open').firstMatch(html);
  if (assignment == null) return null;
  final start = html.indexOf(open, assignment.start);
  var depth = 0;
  var quote = '';
  var escaped = false;
  for (var i = start; i < html.length; i++) {
    final ch = html[i];
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == quote) {
        quote = '';
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == open) {
      depth++;
    } else if (ch == close && --depth == 0) {
      try {
        return jsonDecode(html.substring(start, i + 1));
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

// ───────────────────────────── 规范化 ─────────────────────────────

/// 每档音质的文件大小。
Json kugouQualityDetails(Json raw) => _qualityDetails([
      ('128k', raw['FileSize'] ?? raw['filesize']),
      ('320k', raw['HQFileSize'] ?? raw['320filesize']),
      ('flac', raw['SQFileSize'] ?? raw['sqfilesize']),
      ('hires', raw['ResFileSize'] ?? raw['filesize_high']),
    ]);

/// 每档音质对应的文件 hash（播放解析按 hash 取链接）。
Map<String, String> kugouQualityHashes(Json raw) {
  final pairs = [
    ('128k', raw['FileHash'] ?? raw['hash']),
    ('320k', raw['HQFileHash'] ?? raw['320hash']),
    ('flac', raw['SQFileHash'] ?? raw['sqhash']),
    ('hires', raw['ResFileHash'] ?? raw['hash_high']),
  ];
  return {for (final (q, v) in pairs) if (v is String && v.isNotEmpty) q: v};
}

List<String> kugouQualities(Json raw) => _normalizeQualities([...kugouQualityDetails(raw).keys, ...kugouQualityHashes(raw).keys]);

/// 桌面端 normalizeKugou(raw, 'song')：搜索 v2（大写字段）与网页内嵌数据（小写字段）通用。nativeId = hash。
PTrack? normalizeKugou(Json raw) {
  final hash = _s(raw['FileHash'] ?? raw['EMixSongID'] ?? raw['Hash'] ?? raw['hash']);
  if (hash.isEmpty) return null;
  final title = _stripHtml(_s(raw['SongName'] ?? raw['songname'] ?? raw['specialname']));
  final artist = _s(raw['SingerName'] ?? raw['singername'] ?? raw['nickname']);
  final album = _s(raw['AlbumName'] ?? raw['album_name']);
  final cover = _image(raw['Image'] ?? raw['img'] ?? raw['imgurl'] ?? raw['AlbumImage'] ?? raw['album_sizable_cover'] ?? asJson(raw['trans_param'])['union_cover']);
  final qualities = kugouQualities(raw);
  return PTrack(
    platform: Plat.kg,
    nativeId: hash,
    title: title,
    artist: artist,
    album: album,
    duration: _duration(raw['Duration'] ?? raw['duration']),
    cover: cover,
    qualities: qualities.isEmpty ? const ['128k'] : qualities,
    identity: {
      'hash': hash,
      'albumId': _s(raw['AlbumID']),
      'albumAudioId': _s(raw['ID'] ?? raw['Audioid'] ?? raw['audio_id']),
      'qualityHashes': kugouQualityHashes(raw),
    },
    qualityDetails: kugouQualityDetails(raw),
  );
}

/// singer/info 的 data → 歌手卡片。
CatalogItem? normalizeKugouArtist(Json raw) {
  final id = _s(raw['singerid']).trim();
  final name = _s(raw['singername']).trim();
  if (id.isEmpty || name.isEmpty) return null;
  final albums = _num(raw['albumcount']).toInt(), songs = _num(raw['songcount']).toInt();
  return CatalogItem(
    platform: Plat.kg,
    id: id,
    type: CatalogType.artist,
    title: name,
    subtitle: albums != 0 ? '$albums 张专辑' : '$songs 首歌曲',
    cover: _image(raw['imgurl']),
    trackCount: songs == 0 ? null : songs,
  );
}

/// 专辑搜索（song_search_v2 filter=4）的一行 → 专辑卡片；AlbumID 为 0 的是单曲，跳过。
CatalogItem? normalizeKugouAlbum(Json raw) {
  final id = _s(raw['AlbumID'] ?? raw['albumid']).trim();
  final name = _s(raw['AlbumName'] ?? raw['albumname'] ?? raw['album_name']).trim();
  if (id.isEmpty || id == '0' || name.isEmpty) return null;
  final singer = _s(raw['SingerName'] ?? raw['singername'] ?? raw['author_name']);
  return CatalogItem(
    platform: Plat.kg,
    id: id,
    type: CatalogType.album,
    title: name,
    subtitle: singer,
    creator: singer.isEmpty ? null : singer,
    cover: _image(raw['Image'] ?? raw['img'] ?? raw['AlbumImage'] ?? raw['album_sizable_cover']),
  );
}

/// mobiles.kugou.com 详情接口（歌单 song_v2 / 歌手 / 专辑）的歌曲：filename 是「歌手 - 歌名」。
PTrack? normalizeKugouDetailSong(Json raw) {
  final filename = _stripHtml(_s(raw['filename'] ?? raw['FileName']));
  final sep = filename.indexOf(' - ');
  final artist = sep > 0 ? filename.substring(0, sep) : _s(raw['singername']);
  final title = sep > 0 ? filename.substring(sep + 3) : _s(raw['songname'] ?? filename);
  return normalizeKugou({
    'FileHash': raw['hash'] ?? raw['FileHash'],
    'FileSize': raw['filesize'] ?? raw['FileSize'],
    'HQFileHash': raw['320hash'] ?? raw['HQFileHash'],
    'HQFileSize': raw['320filesize'] ?? raw['HQFileSize'],
    'SQFileHash': raw['sqhash'] ?? raw['SQFileHash'],
    'SQFileSize': raw['sqfilesize'] ?? raw['SQFileSize'],
    'ResFileHash': raw['hash_high'] ?? raw['ResFileHash'],
    'ResFileSize': raw['filesize_high'] ?? raw['ResFileSize'],
    'SongName': title,
    'SingerName': artist,
    'AlbumID': raw['album_id'] ?? raw['AlbumID'],
    'AlbumName': raw['album_name'] ?? raw['AlbumName'],
    'Duration': raw['duration'] ?? raw['Duration'],
    'Image': asJson(raw['trans_param'])['union_cover'] ?? raw['imgurl'] ?? raw['Image'],
    'ID': raw['album_audio_id'] ?? raw['audio_id'] ?? raw['ID'],
  });
}

/// 歌单搜索（msearchretry special）的一行。
CatalogItem? normalizeKugouPlaylist(Json raw) {
  final id = _s(raw['specialid'] ?? raw['id']);
  if (id.isEmpty) return null;
  final nick = _stripHtml(_s(raw['nickname']));
  final count = _num(raw['songcount'] ?? raw['song_count']).toInt();
  return CatalogItem(
    platform: Plat.kg,
    id: id,
    type: CatalogType.playlist,
    title: _stripHtml(_s(raw['specialname'] ?? raw['name'] ?? '歌单')),
    subtitle: nick,
    creator: nick.isEmpty ? null : nick,
    cover: _image(raw['imgurl'] ?? raw['img']),
    playCount: _num(raw['playcount']),
    trackCount: count == 0 ? null : count,
  );
}

/// 榜单歌曲（rank/song）：歌手在 authors[]，专辑名放在 remark。
PTrack? normalizeKugouRank(Json raw) => normalizeKugou({
      'Audioid': raw['audio_id'],
      'FileHash': raw['hash'],
      'FileSize': raw['filesize'],
      'HQFileHash': raw['320hash'],
      'HQFileSize': raw['320filesize'],
      'SQFileHash': raw['sqhash'],
      'SQFileSize': raw['sqfilesize'],
      'ResFileHash': raw['hash_high'],
      'ResFileSize': raw['filesize_high'],
      'SongName': raw['songname'],
      'SingerName': _arr(raw['authors']).map((a) => _s(asJson(a)['author_name'])).join(' / '),
      'AlbumID': raw['album_id'],
      'AlbumName': raw['remark'],
      'Duration': raw['duration'],
      'Image': raw['album_sizable_cover'] ?? asJson(raw['trans_param'])['union_cover'] ?? raw['imgurl'] ?? raw['img'] ?? raw['Image'] ?? raw['album_img'] ?? raw['album_imgurl'],
    });

// ───────────────────────────── 平台实现 ─────────────────────────────

class KugouPlatform extends MusicPlatform {
  KugouPlatform(super.http);

  @override
  String get code => Plat.kg;

  @override
  Set<SearchType> get searchTypes => const {SearchType.song, SearchType.playlist, SearchType.artist, SearchType.album};

  @override
  Set<CatalogType> get collectionTypes => const {CatalogType.playlist, CatalogType.leaderboard, CatalogType.album, CatalogType.artist};

  Future<Json> _get(String url, {Map<String, String> headers = _headers}) async => asJson(await http.getJson(code, url, headers: headers));

  /// 桌面端 requestKugouSongSearch：song_search_v2，filter=2 歌曲 / 4 专辑。
  Future<Json> _songSearch(String keyword, int page, int limit, int filter) async {
    final data = await _get(
      'https://songsearch.kugou.com/song_search_v2?keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$limit&userid=0&clientver=&platform=WebFilter&filter=$filter&iscorrection=1&privilege_filter=0&area_code=1',
      headers: _kugouHeaders,
    );
    if (_num(data['error_code']) != 0) throw PlatformException(code, '酷狗音乐搜索暂时不可用');
    return data;
  }

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    var clean = keyword.trim();
    if (clean.length > 100) clean = clean.substring(0, 100);
    if (clean.isEmpty) return const SearchResult();
    switch (type) {
      case SearchType.playlist: {
        final data = await _get(
          'https://msearchretry.kugou.com/api/v3/search/special?keyword=${Uri.encodeComponent(clean)}&page=$page&pagesize=$limit&showtype=10&filter=0&version=7910&sver=2',
          headers: _kugouHeaders,
        );
        final body = asJson(data['data']);
        final items = _arr(body['info']).map(asJson).map(normalizeKugouPlaylist).whereType<CatalogItem>().toList();
        return _result(page, limit, _num(body['total']).toInt(), items: items);
      }
      case SearchType.artist: {
        // 酷狗没有可用的歌手搜索：从歌曲搜索结果里收集歌手 id，再逐个查 singer/info
        final size = max(limit, 30);
        final body = asJson((await _songSearch(clean, page, size, 2))['data']);
        final lists = _arr(body['lists']);
        final ids = _uniqueValues(lists.expand((r) => _arr(asJson(r)['Singers']).map((s) => asJson(s)['id']))).take(limit).toList();
        final details = await Future.wait(ids.map((id) async {
          try {
            return await _get('http://mobiles.kugou.com/api/v5/singer/info?singerid=${Uri.encodeComponent(id)}');
          } catch (_) {
            return <String, dynamic>{};
          }
        }));
        final items = details.map((d) => normalizeKugouArtist(asJson(d['data']))).whereType<CatalogItem>().toList();
        return SearchResult(items: items, total: items.length, hasMore: lists.length >= size && items.length == limit);
      }
      case SearchType.album: {
        final body = asJson((await _songSearch(clean, page, limit, 4))['data']);
        final seen = <String>{};
        final items = _arr(body['lists']).map(asJson).map(normalizeKugouAlbum).whereType<CatalogItem>().where((i) => seen.add(i.id)).toList();
        return _result(page, limit, _num(body['total']).toInt(), items: items);
      }
      case SearchType.song: {
        final body = asJson((await _songSearch(clean, page, limit, 2))['data']);
        final songs = _arr(body['lists']).map(asJson).map(normalizeKugou).whereType<PTrack>().toList();
        return _result(page, limit, _num(body['total']).toInt(), songs: songs);
      }
      case SearchType.mv:
        return const SearchResult();
    }
  }

  @override
  Future<List<String>> suggest(String keyword) async {
    var clean = keyword.trim();
    if (clean.length > 40) clean = clean.substring(0, 40);
    if (clean.isEmpty) return const [];
    try {
      final raw = await http.getJson(code, 'https://searchtip.kugou.com/getSearchTip?MusicTipCount=10&keyword=${Uri.encodeComponent(clean)}', headers: _kugouHeaders);
      final list = _arr(asJson(raw)['data']);
      final rows = list.isEmpty ? const [] : _arr(asJson(list.first)['RecordDatas']);
      return _uniqueWords(rows.map((e) => asJson(e)['HintInfo']));
    } catch (_) {
      return const [];
    }
  }

  /// 热搜：gateway hot_tab，签名 / dfid / mid / clienttime 是桌面端抓包得到的固定值（必须成套使用）。
  @override
  Future<List<String>> hotSearch() async {
    try {
      final data = await _get(
        'https://gateway.kugou.com/api/v3/search/hot_tab?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0',
        headers: {
          'Referer': 'https://www.kugou.com/',
          'dfid': '1ssiv93oVqMp27cirf2CvoF1',
          'mid': '156798703528610303473757548878786007104',
          'clienttime': '1584257267',
          'x-router': 'msearch.kugou.com',
          'User-Agent': 'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi',
          'kg-rc': '1',
        },
      );
      final groups = _arr(asJson(data['data'])['list']);
      return _uniqueWords(groups.expand((g) => _arr(asJson(g)['keywords']).map((k) => asJson(k)['keyword'])));
    } catch (_) {
      return const [];
    }
  }

  /// 分类 id：排序项是 `排序::`（5 推荐 / 7 最新 / 6 最热 / 3 最热收藏 / 8 飙升），「全部」是 `全部`，标签是数字 id。
  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final data = await _get('http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_smarty=1&cdn=cdn&t=5&c=');
    final raw = asJson(data['data']);
    final hotData = asJson(raw['hotTag'])['data'];
    final hot = hotData is Map ? hotData.values : _arr(hotData);
    return [
      const PlaylistCategory('5::', '推荐', group: '排序'),
      const PlaylistCategory('7::', '最新', group: '排序'),
      const PlaylistCategory('6::', '最热', group: '排序'),
      const PlaylistCategory('3::', '最热收藏', group: '排序'),
      const PlaylistCategory('8::', '飙升', group: '排序'),
      const PlaylistCategory('全部', '全部', group: '默认'),
      for (final item in hot.map(asJson))
        if (_s(item['special_name']).isNotEmpty) PlaylistCategory(_s(item['special_id']), _s(item['special_name']), group: '热门标签'),
      for (final MapEntry(key: group, value: value) in asJson(raw['tagids']).entries)
        for (final item in _arr(asJson(value)['data']).map(asJson))
          if (_s(item['name']).isNotEmpty) PlaylistCategory(_s(item['id']), _s(item['name']), group: group),
    ];
  }

  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    final (sort: sort, tag: tag) = _parsePlaylistQuery(category ?? '');
    final data = await _get(
      'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_ajax=1&cdn=cdn&t=${Uri.encodeComponent(sort.isEmpty ? '5' : sort)}&c=${tag.isEmpty ? '' : Uri.encodeComponent(tag)}&p=$page',
    );
    final items = <CatalogItem>[];
    for (final item in _arr(data['special_db']).take(limit).map(asJson)) {
      final c = _catalog(item['specialid'], item['specialname'], item['nickname'], item['img'], item['total_play_count'], item['song_count'],
          item['publish_time'] ?? item['publishtime'] ?? item['create_time'] ?? item['createTime']);
      if (c != null) items.add(c);
    }
    // 接口不给总数：满页就认为还有下一页
    return Page(items, page: page, limit: limit, total: items.length, hasMore: items.length == limit);
  }

  @override
  Future<List<CatalogItem>> leaderboards() async {
    final data = await _get(
      'http://mobilecdnbj.kugou.com/api/v5/rank/list?version=9108&plat=0&showtype=2&parentid=0&apiver=6&area_code=1&withsong=1',
      headers: _kugouHeaders,
    );
    final out = <CatalogItem>[];
    for (final item in _arr(asJson(data['data'])['info']).map(asJson)) {
      // isvol == 1 才是有期刊的正式榜单
      if (_num(item['isvol']) != 1) continue;
      final c = _catalog(item['rankid'], item['rankname'], '酷狗音乐实时榜单', item['img_9'], null, null, null, type: CatalogType.leaderboard);
      if (c != null) out.add(c);
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
        return clean.startsWith('collection_') ? _collectionPlaylist(clean, page, limit) : _specialPlaylist(clean, page, limit);
      case CatalogType.artist:
        return _artist(clean, page, limit);
      case CatalogType.album:
        return _album(clean, page, limit);
    }
  }

  Future<Collection> _leaderboard(String id, int page, int limit) async {
    final data = await _get(
        'http://mobilecdnbj.kugou.com/api/v3/rank/song?version=9108&ranktype=1&plat=0&pagesize=$limit&area_code=1&page=$page&rankid=${Uri.encodeComponent(id)}&with_res_tag=0&show_portrait_mv=1');
    if (_num(data['errcode']) != 0) throw PlatformException(code, '酷狗榜单暂时不可用');
    final body = asJson(data['data']);
    final tracks = _arr(body['info']).map(asJson).map(normalizeKugouRank).whereType<PTrack>().toList();
    final total = _num(body['total']).toInt();
    return Collection(platform: code, id: id, type: CatalogType.leaderboard, title: '酷狗榜单 $id', tracks: tracks, total: total, page: page, limit: limit, hasMore: page * limit < total);
  }

  /// 数字 specialid 歌单：抓 www2 的歌单页，歌曲在 `global.data = [...]`，名字 / 封面在 `global = {...}`。
  Future<Collection> _specialPlaylist(String id, int page, int limit) async {
    final html = await http.text(code, 'GET', Uri.parse('http://www2.kugou.kugou.com/yueku/v9/special/single/${Uri.encodeComponent(id)}-5-9999.html'),
        headers: {..._headers, 'Referer': 'http://www2.kugou.kugou.com/'});
    final dataMatch = RegExp(r'global\.data = (\[.+\]);').firstMatch(html);
    if (dataMatch == null) throw PlatformException(code, '酷狗歌单暂时不可用');
    final List<dynamic> rawTracks;
    try {
      rawTracks = _arr(jsonDecode(dataMatch.group(1)!));
    } catch (e) {
      throw PlatformException(code, '酷狗歌单暂时不可用', e);
    }
    final all = rawTracks.map(asJson).map((item) => normalizeKugou({
          'FileHash': item['hash'],
          'SongName': item['songname'],
          'SingerName': item['singername'],
          'AlbumName': item['album_name'],
          'Duration': item['duration'],
          'Image': asJson(item['trans_param'])['union_cover'] ?? item['imgurl'] ?? item['img'] ?? item['AlbumImage'],
          'AlbumID': item['album_id'],
          'ID': item['audio_id'],
        })).whereType<PTrack>().toList();
    final info = RegExp(r'global = \{[\s\S]+?name: "([^"]*)"[\s\S]+?pic: "([^"]*)"[\s\S]+?\};').firstMatch(html);
    final name = info?.group(1) ?? '';
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.playlist,
      title: name.isNotEmpty ? name : '酷狗歌单',
      cover: _image(info?.group(2)),
      tracks: all.skip((page - 1) * limit).take(limit).toList(),
      total: all.length,
      page: page,
      limit: limit,
      hasMore: page * limit < all.length,
    );
  }

  /// collection_ 开头的新歌单：先走 H5 的 special/info_v2 + song_v2（Web 签名，固定 clienttime），
  /// 拿不到再抓 www.kugou.com 歌单页里的 `var data = [...]` / `specialInfo = {...}`。
  Future<Collection> _collectionPlaylist(String id, int page, int limit) async {
    try {
      const infoTime = '1586163242519', songTime = '1586163263991';
      final infoParams = {
        'appid': '1058',
        'specialid': '0',
        'global_specialid': id,
        'format': 'jsonp',
        'srcappid': '2919',
        'clientver': '20000',
        'clienttime': infoTime,
        'mid': infoTime,
        'uuid': infoTime,
        'dfid': '-',
      };
      final songParams = {
        'appid': '1058',
        'global_specialid': id,
        'specialid': '0',
        'plat': '0',
        'version': '8000',
        'page': '$page',
        'pagesize': '$limit',
        'srcappid': '2919',
        'clientver': '20000',
        'clienttime': songTime,
        'mid': songTime,
        'uuid': songTime,
        'dfid': '-',
      };
      final results = await Future.wait([
        _get('https://mobiles.kugou.com/api/v5/special/info_v2?${_query(infoParams)}&signature=${kugouWebSignature(infoParams)}', headers: kugouCollectionHeaders(infoTime)),
        _get('https://mobiles.kugou.com/api/v5/special/song_v2?${_query(songParams)}&signature=${kugouWebSignature(songParams)}', headers: kugouCollectionHeaders(songTime)),
      ]);
      final info = asJson(results[0]['data']);
      final songs = asJson(results[1]['data']);
      final rawTracks = _arr(songs['info']);
      final total = _num(songs['total'] ?? info['songcount']).toInt();
      final pageStartsAfterTotal = (page - 1) * limit >= total;
      if (info.isNotEmpty && (rawTracks.isNotEmpty || total == 0 || pageStartsAfterTotal)) {
        final creator = _s(info['nickname']);
        return Collection(
          platform: code,
          id: id,
          type: CatalogType.playlist,
          title: _s(info['specialname'] ?? '酷狗歌单'),
          description: _s(info['intro']),
          cover: _image(info['imgurl']),
          creator: creator.isEmpty ? null : creator,
          tracks: rawTracks.map(asJson).map(normalizeKugouDetailSong).whereType<PTrack>().toList(),
          total: total,
          page: page,
          limit: limit,
          hasMore: page * limit < total,
        );
      }
    } catch (_) {
      // H5 接口失败：走网页兜底
    }
    final html = await http.text(code, 'GET', Uri.parse('https://www.kugou.com/yy/special/single/${Uri.encodeComponent(id)}.html'), headers: _kugouHeaders);
    final rawTracks = parseEmbeddedJsonArray(html, 'data');
    final info = parseEmbeddedJsonObject(html, 'specialInfo');
    if (rawTracks.isEmpty || info == null) throw PlatformException(code, '酷狗歌单暂时不可用');
    final all = rawTracks.map(asJson).map(normalizeKugou).whereType<PTrack>().toList();
    final creator = _s(info['nickname']);
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.playlist,
      title: _s(info['name'] ?? info['class_name'] ?? '酷狗歌单'),
      description: _s(info['intro']),
      cover: _image(info['image']),
      creator: creator.isEmpty ? null : creator,
      tracks: all.skip((page - 1) * limit).take(limit).toList(),
      total: all.length,
      page: page,
      limit: limit,
      hasMore: page * limit < all.length,
    );
  }

  Future<Collection> _artist(String id, int page, int limit) async {
    final enc = Uri.encodeComponent(id);
    final results = await Future.wait([
      _get('http://mobiles.kugou.com/api/v5/singer/info?singerid=$enc'),
      _get('http://mobiles.kugou.com/api/v5/singer/song?singerid=$enc&page=$page&pagesize=$limit'),
    ]);
    final info = asJson(results[0]['data']);
    final songBody = asJson(results[1]['data']);
    final tracks = _arr(songBody['info']).map(asJson).map(normalizeKugouDetailSong).whereType<PTrack>().toList();
    final total = _num(songBody['total'] ?? info['songcount']).toInt();
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.artist,
      title: _s(info['singername'] ?? '酷狗歌手'),
      description: _stripHtml(_s(info['profile'] ?? info['intro'])),
      cover: _image(info['imgurl']),
      tracks: tracks,
      total: total,
      page: page,
      limit: limit,
      hasMore: page * limit < total,
    );
  }

  /// 桌面端 requestKugouAlbumInfo：kmrserviceretry container/v1/album（固定 key / mid / clienttime）。
  Future<Json> _albumInfo(String id) async => asJson(await http.postJson(
        code,
        'http://kmrserviceretry.kugou.com/container/v1/album?dfid=1tT5He3kxrNC4D29ad1MMb6F&mid=22945702112173152889429073101964063697&userid=0&appid=1005&clientver=11589',
        {
          'appid': 1005,
          'clienttime': 1681833686,
          'clientver': 11589,
          'data': [
            {'album_id': id},
          ],
          'fields':
              'language,grade_count,intro,mix_intro,heat,category,sizable_cover,cover,album_name,type,quality,publish_company,grade,special_tag,author_name,publish_date,language_id,album_id,exclusive,is_publish,trans_param,authors,album_tag',
          'isBuy': 0,
          'key': 'e6f3306ff7e2afb494e89fbbda0becbf',
          'mid': '22945702112173152889429073101964063697',
          'show_album_tag': 0,
        },
        headers: _headers,
      ));

  Future<Collection> _album(String id, int page, int limit) async {
    final songsF = _get('http://mobiles.kugou.com/api/v3/album/song?version=9108&albumid=${Uri.encodeComponent(id)}&plat=0&pagesize=$limit&area_code=0&page=$page&with_res_tag=0');
    final infoF = page == 1 ? _albumInfo(id).then<Json?>((v) => v, onError: (Object _) => null) : Future<Json?>.value(null);
    final songsData = await songsF;
    final infoData = await infoF;
    final songBody = asJson(songsData['data']);
    final tracks = _arr(songBody['info']).map(asJson).map(normalizeKugouDetailSong).whereType<PTrack>().toList();
    final infoList = _arr(infoData?['data']);
    final info = infoList.isEmpty ? <String, dynamic>{} : asJson(infoList.first);
    final first = tracks.isEmpty ? null : tracks.first;
    final total0 = _num(songBody['total']).toInt();
    final total = total0 != 0 ? total0 : tracks.length;
    var creator = _s(info['author_name']);
    if (creator.isEmpty) creator = _arr(info['authors']).map((a) => _s(asJson(a)['author_name'])).where((n) => n.isNotEmpty).join(' / ');
    if (creator.isEmpty) creator = first?.artist ?? '';
    return Collection(
      platform: code,
      id: id,
      type: CatalogType.album,
      title: _s(info['album_name'] ?? first?.album ?? '酷狗专辑'),
      description: _stripHtml(_s(info['intro'] ?? info['mix_intro'])),
      cover: _image(info['sizable_cover'] ?? info['cover']) ?? first?.cover,
      creator: creator.isEmpty ? null : creator,
      tracks: tracks,
      total: total,
      page: page,
      limit: limit,
      hasMore: page * limit < total,
    );
  }

  /// 歌词：lyrics.kugou.com 按「歌名 - 歌手」+ hash + 时长搜候选，取第一条下载。
  /// krctype=1 且 contenttype≠1 时下 KRC（逐字 + [language:] 翻译 / 音译），否则下 base64 LRC。
  @override
  Future<Lyric> lyric(PTrack track) async {
    final hash = _s(track.identity['hash']).isNotEmpty ? _s(track.identity['hash']) : track.nativeId;
    if (hash.isEmpty) throw PlatformException(code, '酷狗歌曲 hash 不可用');
    final length = max(0, track.duration * 1000);
    final search = await _get(
      'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=${Uri.encodeComponent('${track.title} - ${track.artist}')}&hash=$hash&timelength=$length&lrctxt=1',
      headers: _lyricHeaders,
    );
    final candidates = _arr(search['candidates']);
    final candidate = candidates.isEmpty ? <String, dynamic>{} : asJson(candidates.first);
    final cid = _s(candidate['id']), key = _s(candidate['accesskey']);
    if (cid.isEmpty || cid == '0' || key.isEmpty) throw PlatformException(code, '酷狗没有歌词');
    final fmt = _num(candidate['krctype']) == 1 && _num(candidate['contenttype']) != 1 ? 'krc' : 'lrc';
    final data = await _get(
      'https://lyrics.kugou.com/download?ver=1&client=pc&id=${Uri.encodeComponent(cid)}&accesskey=${Uri.encodeComponent(key)}&fmt=$fmt&charset=utf8',
      headers: _lyricHeaders,
    );
    final content = _s(data['content']);
    if (content.isEmpty) throw PlatformException(code, '酷狗歌词内容为空');
    if (fmt == 'lrc') {
      final List<int> bytes;
      try {
        bytes = base64.decode(_padBase64(content.trim()));
      } catch (e) {
        throw PlatformException(code, '酷狗歌词解码失败', e);
      }
      return Lyric(utf8.decode(bytes, allowMalformed: true));
    }
    return krcToLyric(decodeKrc(content));
  }
}

// ───────────────────────────── 桌面端通用小函数（私有副本） ─────────────────────────────

String _query(Map<String, String> params) => params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

({String sort, String tag}) _parsePlaylistQuery(String value) {
  final parts = value.split('::');
  if (parts.length > 1) return (sort: parts[0].isEmpty ? '5' : parts[0], tag: parts[1] == '全部' ? '' : parts[1]);
  return (sort: '5', tag: value == '全部' ? '' : value);
}

String _s(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v is String ? v : v.toString();
}

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

int _duration(Object? v) {
  final n = _num(v);
  return n > 10000 ? (n / 1000).round() : n.round();
}

String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

/// 酷狗图片地址带 `{size}` 占位，换成 500。
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

/// 去重、去空、去 "0"。
List<String> _uniqueValues(Iterable<Object?> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in values) {
    final s = _s(v).trim();
    if (s.isEmpty || s == '0' || !seen.add(s)) continue;
    out.add(s);
  }
  return out;
}

SearchResult _result(int page, int limit, int total, {List<PTrack> songs = const [], List<CatalogItem> items = const []}) {
  final count = songs.length + items.length;
  return SearchResult(songs: songs, items: items, total: total != 0 ? total : count, hasMore: total != 0 ? page * limit < total : count == limit);
}

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

CatalogItem? _catalog(Object? id, Object? title, Object? subtitle, Object? cover, Object? playCount, Object? trackCount, Object? date, {CatalogType type = CatalogType.playlist}) {
  final v = _s(id);
  if (v.isEmpty) return null;
  final creator = _s(subtitle);
  final count = _num(trackCount).toInt();
  return CatalogItem(
    platform: Plat.kg,
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
