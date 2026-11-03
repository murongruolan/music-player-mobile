// 平台内容入口：每个平台一个实例（共用一个 PlatformHttp），外加一层内存缓存。
// 页面只通过 AppState.content 取平台数据，测试里可以整体换成假平台。
import 'dart:async';
import 'http.dart';
import 'kugou.dart';
import 'kuwo.dart';
import 'migu.dart';
import 'models.dart';
import 'netease.dart';
import 'platform.dart';
import 'tencent.dart';

/// 首页聚合数据（对齐桌面端 publicPlatform：此刻热门 / 推荐歌单 / 排行榜）。
class DiscoverFeed {
  final List<PTrack> hot;
  final CatalogItem? hotBoard;
  final List<CatalogItem> playlists, boards;

  /// 部分接口失败时的说明（全部失败时直接抛错）。
  final List<String> errors;
  const DiscoverFeed({this.hot = const [], this.hotBoard, this.playlists = const [], this.boards = const [], this.errors = const []});
  bool get isEmpty => hot.isEmpty && playlists.isEmpty && boards.isEmpty;
}

class _Entry {
  final Future<Object?> value;
  final DateTime at;
  _Entry(this.value, this.at);
}

class PlatformHub {
  final Map<String, MusicPlatform> _p;
  final Duration ttl;
  final DateTime Function() _now;
  final _cache = <String, _Entry>{};

  PlatformHub._(this._p, this.ttl, this._now);

  /// 真实平台。网易不逐首补全音质（列表页每首歌多一个请求太慢）。
  factory PlatformHub({PlatformHttp? http, Duration ttl = const Duration(minutes: 10), DateTime Function()? now}) {
    final h = http ?? PlatformHttp();
    return PlatformHub._({
      Plat.wy: NeteasePlatform(h, fetchQualityDetails: false),
      Plat.tx: TencentPlatform(h),
      Plat.kg: KugouPlatform(h),
      Plat.kw: KuwoPlatform(h),
      Plat.mg: MiguPlatform(h),
    }, ttl, now ?? DateTime.now);
  }

  /// 测试用：指定每个平台的实现。
  PlatformHub.of(Map<String, MusicPlatform> platforms, {this.ttl = const Duration(minutes: 10), DateTime Function()? now})
      : _p = platforms,
        _now = now ?? DateTime.now;

  /// App 平台 id（netease / qq / …）或平台代码（wy / tx / …）→ 平台代码。
  static String codeOf(String id) => Plat.fromAppId[id] ?? id;

  MusicPlatform? of(String id) => _p[codeOf(id)];
  MusicPlatform _req(String id) => of(id) ?? (throw PlatformException(id, '不支持的平台'));
  bool supports(String id) => of(id) != null;

  /// 带缓存地执行。失败的结果不缓存。
  Future<T> _cached<T>(String key, Future<T> Function() f) {
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.value.then((v) => v as T);
    final fut = f();
    _cache[key] = _Entry(fut, _now());
    fut.then((_) {}, onError: (Object _) {
      if (identical(_cache[key]?.value, fut)) _cache.remove(key);
    });
    return fut;
  }

  /// 清掉某个平台（或全部）的缓存。下拉刷新用。
  void invalidate([String? id]) {
    if (id == null) return _cache.clear();
    final c = codeOf(id);
    _cache.removeWhere((k, _) => k.startsWith('$c|'));
  }

  // ---------------------------------------------------------------- 首页

  Future<DiscoverFeed> discover(String id) {
    final c = codeOf(id);
    return _cached('$c|discover', () => _discover(c));
  }

  Future<DiscoverFeed> _discover(String c) async {
    final errors = <String>[];
    Future<T?> soft<T>(Future<T> f, String what) async {
      try {
        return await f;
      } catch (e) {
        errors.add('$what：${_msg(e)}');
        return null;
      }
    }

    final pls = soft(playlists(c, limit: 12), '推荐歌单');
    final boards = soft(leaderboards(c), '排行榜');
    final b = await boards ?? const <CatalogItem>[];
    List<PTrack> hot = const [];
    CatalogItem? hotBoard;
    if (b.isNotEmpty) {
      hotBoard = b.first;
      final col = await soft(collection(c, CatalogType.leaderboard, b.first.id, limit: 10), '此刻热门');
      hot = (col?.tracks ?? const <PTrack>[]).take(10).toList();
    }
    final p = await pls;
    final feed = DiscoverFeed(hot: hot, hotBoard: hotBoard, playlists: (p?.items ?? const <CatalogItem>[]).take(12).toList(), boards: b.take(9).toList(), errors: errors);
    if (feed.isEmpty && errors.isNotEmpty) throw PlatformException(c, errors.first);
    return feed;
  }

  // ---------------------------------------------------------------- 透传 + 缓存

  Future<Page<CatalogItem>> playlists(String id, {String? category, int page = 1, int limit = 30}) {
    final c = codeOf(id);
    return _cached('$c|pl|$category|$page|$limit', () => _req(c).playlists(category: category, page: page, limit: limit));
  }

  Future<List<PlaylistCategory>> playlistCategories(String id) {
    final c = codeOf(id);
    return _cached('$c|cats', () => _req(c).playlistCategories());
  }

  Future<List<CatalogItem>> leaderboards(String id) {
    final c = codeOf(id);
    return _cached('$c|boards', () => _req(c).leaderboards());
  }

  Future<Collection> collection(String id, CatalogType type, String cid, {int page = 1, int limit = 100}) {
    final c = codeOf(id);
    return _cached('$c|col|${type.name}|$cid|$page|$limit', () => _req(c).collection(type, cid, page: page, limit: limit));
  }

  Future<List<String>> hotSearch(String id) {
    final c = codeOf(id);
    return _cached('$c|hot', () => _req(c).hotSearch());
  }

  /// 联想按关键词缓存。
  Future<List<String>> suggest(String id, String keyword) {
    final c = codeOf(id);
    return _cached('$c|sug|$keyword', () => _req(c).suggest(keyword));
  }

  /// 搜索。非网易平台失败时按桌面端的做法回退到网易，[SearchOutcome.fallback] 标出实际用的平台。
  Future<SearchOutcome> search(String id, String keyword, SearchType type, {int page = 1, int limit = 30, bool fallback = true}) async {
    final c = codeOf(id);
    try {
      final r = await _cached('$c|s|${type.name}|$keyword|$page|$limit', () => _req(c).search(keyword, type, page: page, limit: limit));
      return SearchOutcome(c, r);
    } catch (e) {
      final wy = of(Plat.wy);
      if (!fallback || c == Plat.wy || wy == null || !wy.searchTypes.contains(type)) rethrow;
      final r = await _cached('${Plat.wy}|s|${type.name}|$keyword|$page|$limit', () => wy.search(keyword, type, page: page, limit: limit));
      return SearchOutcome(Plat.wy, r, fallbackFrom: c, error: _msg(e));
    }
  }

  Future<Lyric> lyric(PTrack t) => _cached('${t.platform}|lrc|${t.nativeId}', () => _req(t.platform).lyric(t));

  static String _msg(Object e) => e is PlatformException ? e.message : '$e';
}

class SearchOutcome {
  /// 实际返回结果的平台代码。
  final String platform;
  final SearchResult result;

  /// 原平台失败、回退到网易时：原平台代码与失败原因。
  final String? fallbackFrom, error;
  const SearchOutcome(this.platform, this.result, {this.fallbackFrom, this.error});
}

/// 给界面用的错误文案。
String platformError(Object e) {
  if (e is PlatformException) return e.message;
  if (e is TimeoutException) return '请求超时，请检查网络';
  return '加载失败，请稍后再试';
}
