// 测试用的假平台：固定数据，记录调用次数，可以让指定方法失败。
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/platform.dart';
import 'package:lyra/platform/registry.dart';

class FakePlatform extends MusicPlatform {
  @override
  final String code;
  final calls = <String, int>{};
  final Set<String> fail;
  FakePlatform(this.code, {this.fail = const {}}) : super(PlatformHttp());

  void _hit(String m) {
    calls[m] = (calls[m] ?? 0) + 1;
    if (fail.contains(m)) throw PlatformException(code, '$m 失败');
  }

  PTrack track(int i) => PTrack(platform: code, nativeId: 's$i', title: '$code 歌曲 $i', artist: '歌手 ${i % 3}', album: '专辑', duration: 200 + i);
  CatalogItem item(CatalogType t, int i) => CatalogItem(platform: code, id: '${t.name}$i', title: '$code ${t.name} $i', type: t, playCount: 12345 * (i + 1), trackCount: 20, creator: '官方');

  @override
  Set<SearchType> get searchTypes => const {SearchType.song, SearchType.playlist, SearchType.album, SearchType.artist, SearchType.mv};

  @override
  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30}) async {
    _hit('search');
    if (type == SearchType.song) return SearchResult(songs: [for (var i = 0; i < 5; i++) track(page * 100 + i)], total: 10, hasMore: page < 2);
    if (type == SearchType.mv) return SearchResult(songs: [PTrack(platform: code, nativeId: 'mv1', title: '$keyword MV', artist: 'A', mvId: 'mv1')], total: 1);
    final t = switch (type) { SearchType.album => CatalogType.album, SearchType.artist => CatalogType.artist, _ => CatalogType.playlist };
    return SearchResult(items: [for (var i = 0; i < 3; i++) item(t, i)], total: 3);
  }

  @override
  Future<List<String>> suggest(String keyword) async {
    _hit('suggest');
    return ['$keyword 现场', '$keyword 伴奏'];
  }

  @override
  Future<List<String>> hotSearch() async {
    _hit('hotSearch');
    return ['热搜一', '热搜二', '热搜三'];
  }

  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    _hit('playlistCategories');
    return const [PlaylistCategory('全部', '全部'), PlaylistCategory('c1', '华语'), PlaylistCategory('c2', '摇滚')];
  }

  @override
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30}) async {
    _hit('playlists');
    return Page([for (var i = 0; i < limit.clamp(0, 12); i++) item(CatalogType.playlist, (page - 1) * 100 + i)], page: page, limit: limit, total: 24);
  }

  @override
  Future<List<CatalogItem>> leaderboards() async {
    _hit('leaderboards');
    return [for (var i = 0; i < 12; i++) item(CatalogType.leaderboard, i)];
  }

  @override
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100}) async {
    _hit('collection');
    final n = limit.clamp(0, 10);
    return Collection(platform: code, id: id, type: type, title: '$code 详情 $id', description: '简介', tracks: [for (var i = 0; i < n; i++) track(page * 1000 + i)], total: 20, page: page, limit: limit, hasMore: page * limit < 20);
  }

  @override
  Future<Lyric> lyric(PTrack track) async => const Lyric('[00:01.00]hi');
}

/// 五个平台都是假平台的 PlatformHub。
PlatformHub fakeHub({Map<String, Set<String>> fail = const {}}) => PlatformHub.of({for (final c in Plat.all) c: FakePlatform(c, fail: fail[c] ?? const {})});
