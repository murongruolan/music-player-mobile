// 网易云音乐（wy）。对齐桌面端 platform-service.ts 的 searchNetease / leaderboardsNetease / collectionNetease /
// lyricNetease / mvUrl / normalizeNetease / neteaseQualities 等。接口地址、payload 字段与桌面端保持一致。
//
// 三种加密通道（见 netease_crypto.dart）：
//   weapi    → https://music.163.com/weapi/...           网页端接口
//   eapi     → https://interface*.music.163.com/eapi/... 客户端接口；加密的是 `/api/...` 路径，请求的是 `/eapi/...` 地址
//   linuxapi → https://music.163.com/api/linux/forward   把真正的 url + params 整体加密后转发
import 'dart:convert';

import '../net/json.dart';
import 'lyric_parse.dart';
import 'models.dart';
import 'netease_crypto.dart';
import 'platform.dart';

class NeteasePlatform extends MusicPlatform {
  /// [fetchQualityDetails]：列表接口常缺 Hi-Res / 杜比 / 母带信息，桌面端会对每首歌再请求一次
  /// `/api/song/music/detail/get` 补全音质（失败静默忽略）。关掉可以少很多请求。
  /// [secret]：固定 weapi 随机密钥，仅测试用。
  NeteasePlatform(super.http, {this.fetchQualityDetails = true, String Function()? secret}) : _secret = secret;

  final bool fetchQualityDetails;
  final String Function()? _secret;
  final _qualityRequests = <String, Future<Json>>{};

  static const _referer = {'Referer': 'https://music.163.com/'};
  static const _origin = {'Origin': 'https://music.163.com', 'Referer': 'https://music.163.com/'};
  static const _batch = 'https://interface.music.163.com/eapi/batch';

  @override
  String get code => Plat.wy;

  @override
  Set<SearchType> get searchTypes => const {SearchType.song, SearchType.playlist, SearchType.artist, SearchType.album, SearchType.mv};

  @override
  Set<CatalogType> get collectionTypes => const {CatalogType.playlist, CatalogType.leaderboard, CatalogType.album, CatalogType.artist};

  // ---------------------------------------------------------------- 请求

  Future<Json> _weapi(String url, Object? payload) async =>
      asJson(await http.postForm(code, url, weapi(payload, secret: _secret?.call()), headers: _origin));

  Future<Json> _eapi(String url, String api, Object? payload) async => asJson(await http.postForm(code, url, eapi(api, payload), headers: _origin));

  /// 带用户 Cookie 的个性化接口：weapi 优先；被拦（部分网络对 /weapi 一律回 200 空体）时退回明文 /api。
  /// [path] 形如 `/v3/discovery/recommend/songs`（weapi 与 api 共用）。
  Future<Json> _userPost(String path, Map<String, Object?> payload, String cookie) async {
    final csrf = RegExp(r'(?:^|;\s*)__csrf=([^;]+)').firstMatch(cookie)?.group(1) ?? '';
    final h = {..._origin, if (cookie.isNotEmpty) 'Cookie': cookie};
    final body = {...payload, 'csrf_token': csrf};
    try {
      final j = asJson(await http.postForm(code, 'https://music.163.com/weapi$path?csrf_token=$csrf', weapi(body, secret: _secret?.call()), headers: h));
      if (j.isNotEmpty) return j;
    } on PlatformException catch (e) {
      if (e.message.contains('HTTP')) rethrow;
    }
    final form = {for (final e in body.entries) e.key: e.value is String ? e.value as String : jsonEncode(e.value)};
    return asJson(await http.postForm(code, 'https://music.163.com/api$path', form, headers: h));
  }

  Json _okUser(Json j, String message) {
    final c = j.integer('code');
    if (c == 301 || c == 302) throw const NeteaseAuthException();
    return _ok(j, message);
  }

  /// 每日歌曲推荐（需要登录 Cookie，含 MUSIC_U）。登录失效抛 [NeteaseAuthException]。
  Future<List<PTrack>> dailySongs(String cookie) async {
    final j = _okUser(await _userPost('/v3/discovery/recommend/songs', {'offset': 0, 'total': true, 'limit': 30}, cookie), '每日推荐暂时拿不到');
    final rows = j.obj('data')['dailySongs'];
    return [for (final r in rows is List ? rows : const []) neteaseSong(asJson(r))].nonNulls.toList();
  }

  /// 私人 FM 的一批（一次 3 首左右）。没登录时用游客 Cookie（MUSIC_A），推荐按热门走。
  Future<List<PTrack>> personalFm(String cookie) async {
    final j = _okUser(await _userPost('/v1/radio/get', const {}, cookie), '私人 FM 暂时拿不到');
    final rows = j['data'];
    return [for (final r in rows is List ? rows : const []) neteaseSong(asJson(r))].nonNulls.toList();
  }

  /// 网易接口业务码在 body.code，200 才算成功；没有 code 字段的不检查。
  Json _ok(Json j, String message) {
    if (j.containsKey('code') && j.integer('code') != 200) throw PlatformException(code, message);
    return j;
  }

  // ---------------------------------------------------------------- 搜索

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    final clean = _clip(keyword.trim(), 100);
    if (clean.isEmpty) return const SearchResult();
    if (type == SearchType.song) {
      final r = await _searchSongs(clean, page, limit);
      return SearchResult(songs: r.tracks, total: r.total, hasMore: r.hasMore);
    }
    final typeCode = switch (type) { SearchType.album => 10, SearchType.artist => 100, SearchType.playlist => 1000, _ => 1004 };
    final (listKey, countKey) = switch (type) {
      SearchType.album => ('albums', 'albumCount'),
      SearchType.artist => ('artists', 'artistCount'),
      SearchType.playlist => ('playlists', 'playlistCount'),
      _ => ('mvs', 'mvCount'),
    };
    Future<Json> cloud() async => _ok(
        await _eapi(_batch, '/api/cloudsearch/pc', {'s': clean, 'type': typeCode, 'limit': limit, 'total': page == 1, 'offset': limit * (page - 1)}),
        '网易云搜索暂时不可用');
    Future<Json> web() async {
      // `/api/search/get/web` 对 MV（1004）返回 {"code":400}，只有不带 /web 的接口给 mvs 列表
      final url = type == SearchType.mv ? 'https://music.163.com/api/search/get' : 'https://music.163.com/api/search/get/web';
      final form = {'s': clean, 'type': '$typeCode', 'limit': '$limit', 'offset': '${(page - 1) * limit}'};
      return _ok(asJson(await http.postForm(code, url, form, headers: _referer)), '网易云搜索暂时不可用');
    }

    Json data;
    if (type == SearchType.artist) {
      // 艺术家搜索走明文 /web 接口：eapi cloudsearch/pc 的 artist 结果不带头像
      // （实测 picUrl / img1v1Url 全空，搜索页最佳匹配与艺术家 tab 全是渐变占位），
      // 明文接口的 artists 带 picUrl；失败时再退 eapi。
      try {
        data = await web();
      } catch (_) {
        data = await cloud();
      }
    } else if (type == SearchType.album) {
      data = await cloud();
    } else if (type == SearchType.playlist) {
      // 桌面端歌单走明文接口；失败时退到 eapi cloudsearch
      try {
        data = await web();
      } catch (_) {
        data = await cloud();
      }
    } else {
      data = await web();
    }
    final result = data.obj('result');
    final rows = result.list(listKey, (e) => e);
    final total = result.integer(countKey);
    if (type == SearchType.mv) {
      final mvs = rows.map(neteaseMv).nonNulls.toList();
      final (mvTotal, mvMore) = _paging(mvs.length, page, limit, total);
      return SearchResult(songs: mvs, total: mvTotal, hasMore: mvMore);
    }
    final catalog = switch (type) { SearchType.album => CatalogType.album, SearchType.artist => CatalogType.artist, _ => CatalogType.playlist };
    final items = rows.map((r) => neteaseCatalogItem(r, catalog)).nonNulls.toList();
    final (t, more) = _paging(items.length, page, limit, total);
    return SearchResult(items: items, total: t, hasMore: more);
  }

  /// 单曲搜索：eapi `/api/search/song/list/page`；失败（网络 / 业务码）时退到明文 `/api/search/get/web`。
  Future<({List<PTrack> tracks, int total, bool hasMore})> _searchSongs(String keyword, int page, int limit, {bool enrich = true}) async {
    List<Json> rows;
    int total;
    try {
      final data = _ok(
          await _eapi(_batch, '/api/search/song/list/page', {
            'keyword': keyword,
            'needCorrect': '1',
            'channel': 'typing',
            'offset': limit * (page - 1),
            'scene': 'normal',
            'total': page == 1,
            'limit': limit,
          }),
          '网易云搜索暂时不可用');
      final result = data.obj('data');
      rows = result.list('resources', (e) => e);
      total = result.integer('totalCount');
    } catch (_) {
      final form = {'s': keyword, 'type': '1', 'limit': '$limit', 'offset': '${(page - 1) * limit}'};
      final data = _ok(asJson(await http.postForm(code, 'https://music.163.com/api/search/get/web', form, headers: _referer)), '网易云搜索暂时不可用');
      final result = data.obj('result');
      rows = result.list('songs', (e) => e);
      total = result.integer('songCount');
    }
    var tracks = rows.map(neteaseSong).nonNulls.toList();
    if (enrich) tracks = await enrichTracks(tracks);
    final (t, more) = _paging(tracks.length, page, limit, total);
    return (tracks: tracks, total: t, hasMore: more);
  }

  @override
  Future<List<String>> suggest(String keyword) async {
    final clean = _clip(keyword.trim(), 40);
    if (clean.isEmpty) return const [];
    final data = asJson(await http.getJson(code, 'https://music.163.com/api/search/suggest/web?s=${Uri.encodeComponent(clean)}', headers: _origin));
    final words = _uniqueWords(data.obj('result').list('songs', (s) {
      final artists = _names(s['artists']);
      return artists.isEmpty ? s.str('name') : '${s.str('name')} - $artists';
    }));
    if (words.isNotEmpty) return words;
    // 联想接口没给歌曲时，用搜索前 10 条兜底
    final fallback = await _searchSongs(clean, 1, 10, enrich: false);
    return _uniqueWords(fallback.tracks.map((t) {
      final sub = t.artist.isNotEmpty ? t.artist : t.album;
      return sub.isEmpty ? t.title : '${t.title} - $sub';
    }));
  }

  /// 热搜。与桌面端一样失败时返回空列表。
  @override
  Future<List<String>> hotSearch() async {
    try {
      final data = await _eapi(_batch, '/api/search/chart/detail', {'id': 'HOT_SEARCH_SONG#@#'});
      return _uniqueWords(data.obj('data').list('itemList', (e) => e['searchWord']));
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------- 歌单广场 / 榜单

  /// 第一项「推荐」(id = recommend)，第二项「全部」，其余 id 就是分类名（直接作为 cat 传给歌单列表）。
  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final data = _ok(await _weapi('https://music.163.com/weapi/playlist/catalogue', const {}), '网易云歌单分类暂时不可用');
    final all = data.obj('all');
    final groups = data.obj('categories'); // {"0": "语种", "1": "风格", ...}
    return [
      const PlaylistCategory('recommend', '推荐'),
      PlaylistCategory('全部', all.str('name', '全部'), group: '默认'),
      ...data.list('sub', (s) => PlaylistCategory(s.str('name'), s.str('name'), group: groups.str(s.str('category'), '分类'))).where((c) => c.name.isNotEmpty),
    ];
  }

  /// [category]：分类名，或桌面端的 `sort::tag` 形式；null / recommend / 全部 都按「全部」请求（按热度）。
  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    var tag = category ?? '';
    final parts = tag.split('::');
    if (parts.length > 1) tag = parts[1];
    if (tag == '全部' || tag == 'recommend') tag = '';
    final data = _ok(
        await _weapi('https://music.163.com/weapi/playlist/list', {'cat': tag.isEmpty ? '全部' : tag, 'order': 'hot', 'limit': limit, 'offset': limit * (page - 1), 'total': true}),
        '网易云歌单暂时不可用');
    final items = data
        .list('playlists', (p) => _catalog(p['id'], p['name'], p.obj('creator')['nickname'], p['coverImgUrl'], p['playCount'], p['trackCount'], p['createTime'] ?? p['updateTime'] ?? p['create_time'], CatalogType.playlist))
        .nonNulls
        .toList();
    final total = data.integer('total');
    return Page(items, page: page, limit: limit, total: total, hasMore: data.boolean('more') || page * limit < total);
  }

  @override
  Future<List<CatalogItem>> leaderboards() async {
    final data = _ok(await _weapi('https://music.163.com/weapi/toplist', const {}), '网易云榜单暂时不可用');
    return data
        .list('list', (b) => _catalog(b['id'], b['name'], b['updateFrequency'] ?? '网易云音乐实时榜单', b['coverImgUrl'], null, b['trackCount'], null, CatalogType.leaderboard))
        .nonNulls
        .toList();
  }

  // ---------------------------------------------------------------- 详情

  @override
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100}) async {
    final rawId = id.trim();
    if (rawId.isEmpty) throw PlatformException(code, '音乐详情缺少 ID');
    final numericId = rawId.replaceFirst(RegExp(r'^wy__'), '');
    var title = '', description = '';
    String? cover, creator;
    var songs = <Json>[];
    var total = 0;
    var paged = false; // true：songs 已经是当前页
    bool? hasMoreOverride;

    switch (type) {
      case CatalogType.playlist || CatalogType.leaderboard:
        // 歌单详情只拿 trackIds（n 给大值拿全量 id），再按页去 v3/song/detail 换完整歌曲信息
        final data = _ok(
            asJson(await http.postForm(
                code,
                'https://music.163.com/api/linux/forward',
                linuxapi({
                  'method': 'POST',
                  'url': 'https://music.163.com/api/v3/playlist/detail',
                  'params': {'id': numericId, 'n': 100000, 's': 8},
                }),
                headers: {..._referer, 'Cookie': 'MUSIC_U='})),
            '歌单不存在或暂时无法访问');
        final pl = data.obj('playlist');
        title = pl.str('name', '歌单');
        description = pl.str('description');
        cover = _image(pl['coverImgUrl']);
        creator = pl.obj('creator').str('nickname');
        final trackIds = pl.list('trackIds', (t) => _num(t['id']).toInt()).where((v) => v > 0).toList();
        songs = pl.list('tracks', (e) => e);
        if (trackIds.isNotEmpty) {
          final pageIds = trackIds.sublist(_min((page - 1) * limit, trackIds.length), _min(page * limit, trackIds.length));
          songs = await _songDetails(pageIds);
          paged = true;
        }
        total = trackIds.isNotEmpty ? trackIds.length : songs.length;
      case CatalogType.album:
        final albumData = _ok(await _weapi('https://music.163.com/weapi/v1/album/$numericId', const {}), '专辑不存在或暂时无法访问');
        final album = albumData.obj('album');
        title = album.str('name', '专辑');
        description = album.str('description');
        cover = _image(album['picUrl']);
        creator = album.list('artists', (a) => a.str('name')).join(' / ');
        songs = albumData.list('songs', (e) => e);
        total = songs.length;
      case CatalogType.artist:
        // 桌面端第一页还会拉歌手专辑列表（hotAlbums），Collection 模型没有专辑字段，这里不请求
        final results = await Future.wait([
          _weapi('https://music.163.com/weapi/artist/head/info/get', {'id': numericId}),
          _weapi('https://music.163.com/weapi/v1/artist/songs', {'id': numericId, 'private_cloud': 'true', 'work_type': 1, 'order': 'hot', 'offset': (page - 1) * limit, 'limit': limit}),
        ]);
        final detail = _ok(results[0], '歌手不存在或暂时无法访问').obj('data');
        final songBody = _ok(results[1], '歌手歌曲暂时不可用');
        final artist = detail.obj('artist');
        title = artist.str('name', '歌手');
        description = artist.str('briefDesc');
        cover = _image(detail.obj('user')['avatarUrl'] ?? artist['picUrl'] ?? artist['img1v1Url']);
        creator = artist.strings('alias').where((a) => a.isNotEmpty).join(' / ');
        songs = songBody.list('songs', (e) => e);
        total = songBody.integer('total');
        paged = true;
        if (songBody['more'] is bool) hasMoreOverride = songBody['more'] as bool;
    }

    final rows = paged ? songs : songs.sublist(_min((page - 1) * limit, songs.length), _min(page * limit, songs.length));
    final tracks = await enrichTracks(rows.map(neteaseSong).nonNulls.toList());
    if (total <= 0) total = songs.length;
    return Collection(
      platform: code,
      id: rawId,
      type: type,
      title: title,
      description: description,
      cover: cover,
      creator: creator.isEmpty ? null : creator,
      tracks: tracks,
      total: total,
      page: page,
      limit: limit,
      hasMore: hasMoreOverride ?? page * limit < total,
    );
  }

  /// weapi v3/song/detail：c 和 ids 都是 JSON 字符串。分批（每批 200）并发请求，保持原顺序。
  Future<List<Json>> _songDetails(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final chunks = [for (var i = 0; i < ids.length; i += 200) ids.sublist(i, _min(i + 200, ids.length))];
    final results = await Future.wait(chunks.map((c) => _weapi('https://music.163.com/weapi/v3/song/detail', {
          'c': _jsonString([for (final id in c) {'id': id}]),
          'ids': _jsonString(c),
        })));
    return [for (final r in results) ..._ok(r, '歌曲详情暂时不可用').list('songs', (e) => e)];
  }

  // ---------------------------------------------------------------- 歌词 / MV

  /// lrc 原文；translation = ytlrc（逐字翻译）或 tlyric；romanization = yromalrc 或 romalrc；words = yrc 逐字。
  @override
  Future<Lyric> lyric(PTrack track) async {
    final id = '${track.identity['id'] ?? track.nativeId}';
    final data = _ok(
        await _eapi('https://interface3.music.163.com/eapi/song/lyric/v1', '/api/song/lyric/v1', {
          'id': id,
          'cp': false,
          'tv': 0,
          'lv': 0,
          'rv': 0,
          'kv': 0,
          'yv': 0,
          'ytv': 0,
          'yrv': 0,
          'yromalrc': true,
        }),
        '网易云歌词暂时不可用');
    String field(String name) => data.obj(name).str('lyric');
    String? either(String a, String b) {
      final v = field(a).isNotEmpty ? field(a) : field(b);
      return v.trim().isEmpty ? null : v;
    }

    final lrc = either('lrc', 'klyric');
    if (lrc == null) throw PlatformException(code, '网易云没有歌词');
    final yrc = field('yrc');
    final words = yrc.isEmpty ? const <LyricLineWords>[] : parseYrc(yrc);
    return Lyric(lrc, translation: either('ytlrc', 'tlyric'), romanization: either('yromalrc', 'romalrc'), words: words.isEmpty ? null : words);
  }

  /// MV 播放地址（weapi `/song/enhance/play/mv/url`，参数 {id, r}）。平台拒绝（无地址）返回 null。
  Future<String?> mvUrl(String id, {int resolution = 1080}) async {
    final mvId = id.trim();
    if (mvId.isEmpty) throw PlatformException(code, 'MV 播放缺少 MV 标识');
    final data = _ok(await _weapi('https://music.163.com/weapi/song/enhance/play/mv/url', {'id': mvId, 'r': resolution}), '获取 MV 播放地址失败');
    final url = data.obj('data').str('url').trim();
    return url.isEmpty ? null : url;
  }

  // ---------------------------------------------------------------- 音质补全

  /// 逐首请求 `/api/song/music/detail/get` 补全音质档位和大小（桌面端 enrichNeteaseTracks）。
  /// 另外：搜索的精简结果（eapi simpleSongData 与明文 /web 的 album）都不带专辑图，
  /// 对没有封面的歌批量走 v3/song/detail 补 al.picUrl——列表与播放器的真实封面靠它；
  /// 详情请求失败时保持原样（渐变兜底）。失败的保持原样。
  Future<List<PTrack>> enrichTracks(List<PTrack> tracks) async {
    final covers = <int, String>{};
    final missing = <int>[];
    for (final t in tracks) {
      if (t.cover != null) continue;
      final id = int.tryParse('${t.identity['id'] ?? t.nativeId}');
      if (id != null) missing.add(id);
    }
    if (missing.isNotEmpty) {
      try {
        for (final d in await _songDetails(missing)) {
          final url = _image(asJson(d['al'] ?? d['album'])['picUrl']);
          final id = _num(d['id']).toInt();
          if (url != null && id > 0) covers[id] = url;
        }
      } catch (_) {}
    }
    PTrack applyCovers(PTrack t) {
      final id = int.tryParse('${t.identity['id'] ?? t.nativeId}');
      final cover = id != null ? (t.cover ?? covers[id]) : t.cover;
      if (cover == t.cover) return t;
      return PTrack(
        platform: t.platform,
        nativeId: t.nativeId,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        cover: cover,
        qualities: t.qualities,
        identity: t.identity,
        qualityDetails: t.qualityDetails,
        mvId: t.mvId,
      );
    }

    final done = tracks.map(applyCovers).toList();
    if (!fetchQualityDetails) return done;
    return Future.wait(done.map((t) async {
      final id = '${t.identity['id'] ?? t.nativeId}';
      if (!RegExp(r'^\d+$').hasMatch(id)) return t;
      try {
        final details = await _qualityDetail(id);
        if (details.isEmpty) return t;
        return PTrack(
          platform: t.platform,
          nativeId: t.nativeId,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: t.duration,
          cover: t.cover,
          qualities: normalizeQualities([...t.qualities, ...details.keys]),
          identity: t.identity,
          qualityDetails: {...t.qualityDetails, ...details},
          mvId: t.mvId,
        );
      } catch (_) {
        return t;
      }
    }));
  }

  /// 同一首歌并发请求合并；失败不缓存。
  Future<Json> _qualityDetail(String id) {
    final cached = _qualityRequests[id];
    if (cached != null) return cached;
    final request = http.getJson(code, 'https://music.163.com/api/song/music/detail/get?songId=${Uri.encodeComponent(id)}', headers: _origin).then((body) {
      final j = asJson(body);
      if (j.integer('code') != 200) throw PlatformException(code, '网易云歌曲音质详情暂时不可用');
      return neteaseQualityDetails(j.obj('data'));
    });
    _qualityRequests[id] = request;
    request.then<void>((_) {}, onError: (Object _) {
      if (identical(_qualityRequests[id], request)) _qualityRequests.remove(id);
    });
    return request;
  }
}

// ================================================================== 规范化（normalizeNetease）

/// 歌曲：兼容 search/song/list/page（resources[].baseInfo.simpleSongData）、v3/song/detail（ar/al/dt）、
/// 旧接口（artists/album/duration）。时长统一成秒，歌手用 ' / ' 连接。
PTrack? neteaseSong(Json raw) {
  if (raw['baseInfo'] != null) raw = raw.obj('baseInfo').obj('simpleSongData');
  final id = raw.str('id');
  if (id.isEmpty) return null;
  final album = asJson(raw['album'] ?? raw['al']);
  final qualities = neteaseQualities(raw);
  final mv = _num(raw['mv'] ?? raw['mvid']).toInt();
  return PTrack(
    platform: Plat.wy,
    nativeId: id,
    title: raw.str('name'),
    artist: _names(raw['artists'] ?? raw['ar']),
    album: album.str('name'),
    duration: _duration(raw['duration'] ?? raw['dt']),
    cover: _image(album['picUrl']),
    qualities: qualities.isEmpty ? const ['128k'] : qualities,
    identity: {'id': id},
    qualityDetails: neteaseQualityDetails(raw),
    mvId: mv > 0 ? '$mv' : null,
  );
}

/// MV 搜索结果。Collection / CatalogType 没有 MV 类型，这里用 PTrack 承载：
/// nativeId = mvId = MV id，identity = {'id': MV id, 'type': 'mv'}，qualities 为空；播放用 [NeteasePlatform.mvUrl]。
PTrack? neteaseMv(Json raw) {
  final id = raw.str('id');
  if (id.isEmpty) return null;
  final artists = _names(raw['artists']);
  return PTrack(
    platform: Plat.wy,
    nativeId: id,
    title: raw.str('name'),
    artist: artists.isNotEmpty ? artists : raw.str('artistName'),
    duration: _duration(raw['duration']),
    cover: _image(raw['cover']),
    qualities: const [],
    identity: {'id': id, 'type': 'mv'},
    mvId: id,
  );
}

/// 搜索结果里的歌单 / 歌手 / 专辑卡片。
CatalogItem? neteaseCatalogItem(Json raw, CatalogType type) {
  final id = raw.str('id');
  if (id.isEmpty) return null;
  switch (type) {
    case CatalogType.artist:
      final albums = _num(raw['albumSize']).toInt();
      return CatalogItem(
        platform: Plat.wy,
        id: id,
        type: type,
        title: raw.str('name'),
        subtitle: albums > 0 ? '$albums 张专辑' : '歌手',
        cover: _listCover(_image(raw['picUrl'] ?? raw['img1v1Url'] ?? raw['avatarUrl'])),
        trackCount: _intOrNull(raw['musicSize']),
      );
    case CatalogType.album:
      final artists = _names(raw['artists']);
      return CatalogItem(
        platform: Plat.wy,
        id: id,
        type: type,
        title: raw.str('name'),
        subtitle: artists.isNotEmpty ? artists : raw.obj('artist').str('name', '专辑'),
        creator: artists.isNotEmpty ? artists : raw.obj('artist').strOrNull('name'),
        cover: _listCover(_image(raw['picUrl'] ?? raw['blurPicUrl'])),
        trackCount: _intOrNull(raw['size']),
        date: formatCatalogDate(raw['publishTime']),
      );
    case CatalogType.playlist || CatalogType.leaderboard:
      final creator = raw.obj('creator').strOrNull('nickname');
      return CatalogItem(
        platform: Plat.wy,
        id: id,
        type: type,
        title: raw.str('name'),
        subtitle: creator ?? '',
        creator: creator,
        cover: _listCover(_image(raw.obj('album')['picUrl'] ?? raw['coverImgUrl'])),
        playCount: _playCount(raw['playCount']),
        trackCount: _intOrNull(raw['trackCount']),
      );
  }
}

/// 各档音质的文件大小（字节）和码率：l/m → 128k，h → 320k，sq → flac，hr → hires，je/db → atmos，jm → master。
Json neteaseQualityDetails(Json raw) {
  final out = <String, dynamic>{};
  // JS 里是 `l.size ?? m.size`：前一个没有 size 字段才看后一个
  Json pick(String a, [String? b]) => raw.obj(a)['size'] != null || b == null ? raw.obj(a) : raw.obj(b);
  void add(String quality, Json q) {
    final size = _num(q['size']);
    if (size <= 0) return;
    final br = _num(q['br']);
    out[quality] = {'size': size.round(), if (br > 0) 'bitrate': br.round()};
  }

  add('128k', pick('l', 'm'));
  add('320k', pick('h'));
  add('flac', pick('sq'));
  add('hires', pick('hr'));
  add('atmos', pick('je', 'db'));
  add('master', pick('jm'));
  return out;
}

/// 可用音质：有大小信息的档位 + privilege（maxBrLevel / maxbr）推断出的档位，按 [qualityOrder] 排序。
List<String> neteaseQualities(Json raw) {
  final q = <String>{...neteaseQualityDetails(raw).keys};
  final privilege = raw.obj('privilege');
  if (privilege['maxBrLevel'] == 'hires') q.add('hires');
  final max = _num(privilege['maxbr']);
  if (max >= 999000) q.add('flac');
  if (max >= 320000) q.add('320k');
  if (max >= 128000) q.add('128k');
  return normalizeQualities(q);
}

List<String> normalizeQualities(Iterable<String> values) {
  final set = values.toSet();
  return [for (final q in qualityOrder) if (set.contains(q)) q];
}

/// 秒或毫秒时间戳 → `yyyy-MM-dd`（本地时区）；无法识别返回 null。
String? formatCatalogDate(Object? value) {
  if (value == null || (value is String && value.trim().isEmpty)) return null;
  DateTime? date;
  final n = value is num ? value : num.tryParse('$value');
  try {
    if (n != null) {
      date = DateTime.fromMillisecondsSinceEpoch((n < 1e12 ? n * 1000 : n).round());
    } else {
      date = DateTime.tryParse('$value')?.toLocal();
    }
  } catch (_) {
    return null;
  }
  if (date == null) return null;
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

// ================================================================== 小工具

CatalogItem? _catalog(Object? id, Object? title, Object? subtitle, Object? cover, Object? playCount, Object? trackCount, Object? date, CatalogType type) {
  final value = '${id ?? ''}';
  if (value.isEmpty) return null;
  final creator = subtitle == null ? '' : '$subtitle';
  return CatalogItem(
    platform: Plat.wy,
    id: value,
    type: type,
    title: '${title ?? '歌单'}',
    subtitle: subtitle == null ? '未知创建者' : '$subtitle',
    creator: creator.isEmpty ? null : creator,
    cover: _listCover(_image(cover)),
    playCount: _playCount(playCount),
    trackCount: _intOrNull(trackCount),
    date: formatCatalogDate(date),
  );
}

/// JS Number() 语义的宽松数字：非法 → 0。
num _num(Object? v) {
  if (v is num) return v.isFinite ? v : 0;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  if (v is bool) return v ? 1 : 0;
  return 0;
}

int? _intOrNull(Object? v) => v == null ? null : _num(v).round();

/// 播放量：数字原样；数字字符串转数字；其它文案原样保留。
Object? _playCount(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t) ?? t;
  }
  final n = _num(v);
  return n == 0 ? null : n;
}

/// 大于 1 万视为毫秒，否则视为秒（桌面端 duration()）。
int _duration(Object? v) {
  final n = _num(v);
  return n > 10000 ? (n / 1000).round() : n.round();
}

String _names(Object? list) => list is List ? [for (final a in list) if (a is Map) asJson(a).str('name')].where((n) => n.isNotEmpty).join(' / ') : '';

/// 桌面端 imageUrl：只接受 http(s) 和 `//` 开头；移动端把网易图床的 http 升级成 https（iOS ATS / Android 明文限制）。
String? _image(Object? value) {
  if (value is! String) return null;
  var url = value.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) url = 'https:$url';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return null;
  url = url.replaceAll('{size}', '500');
  if (url.startsWith('http://') && Uri.tryParse(url)?.host.endsWith('.music.126.net') == true) url = 'https://${url.substring(7)}';
  return url;
}

/// 列表封面加 `?param=300y300` 让网易图床返回缩略图。
String? _listCover(String? url) => url == null || url.contains('?') ? url : '$url?param=300y300';

/// 去重去空，最多 20 个。
List<String> _uniqueWords(Iterable<Object?> values) {
  final seen = <String>{};
  for (final v in values) {
    final w = (v ?? '').toString().trim();
    if (w.isEmpty) continue;
    seen.add(w);
    if (seen.length >= 20) break;
  }
  return seen.toList();
}

/// 桌面端 response()：total 为 0 时按本页条数推断。
(int, bool) _paging(int count, int page, int limit, int total) => total > 0 ? (total, page * limit < total) : (count, count == limit);

String _clip(String s, int n) {
  if (s.length <= n) return s;
  var end = n;
  // 不切断代理对（emoji 等）
  final c = s.codeUnitAt(end - 1);
  if (c >= 0xD800 && c <= 0xDBFF) end--;
  return s.substring(0, end);
}

int _min(int a, int b) => a < b ? a : b;

String _jsonString(Object v) => jsonEncode(v);

/// 网易云登录已失效（接口回 301）。
class NeteaseAuthException implements Exception {
  const NeteaseAuthException();
  @override
  String toString() => '网易云登录已过期，请重新登录';
}
