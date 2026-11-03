// 音乐平台接口（未登录可用的公开能力）。每个平台一个实现：netease.dart / tencent.dart / kugou.dart / kuwo.dart / migu.dart。
// 对齐桌面端 PlatformService（src/main/services/platform-service.ts，desktop 分支）。
import 'http.dart';
import 'models.dart';

abstract class MusicPlatform {
  final PlatformHttp http;
  MusicPlatform(this.http);

  /// 平台代码（wy / tx / kg / kw / mg）。
  String get code;

  Future<SearchResult> search(String keyword, SearchType type, {int page = 1, int limit = 30});
  Future<List<String>> suggest(String keyword);
  Future<List<String>> hotSearch();

  Future<List<PlaylistCategory>> playlistCategories();

  /// 歌单广场。[category] 为 null 时是推荐 / 全部。
  Future<Page<CatalogItem>> playlists({String? category, int page = 1, int limit = 30});
  Future<List<CatalogItem>> leaderboards();

  /// 详情。不支持的类型抛 [PlatformException]。
  Future<Collection> collection(CatalogType type, String id, {int page = 1, int limit = 100});
  Future<Lyric> lyric(PTrack track);

  /// 这个平台支持的搜索类型。
  Set<SearchType> get searchTypes => const {SearchType.song, SearchType.playlist};

  /// 这个平台支持的详情类型。
  Set<CatalogType> get collectionTypes => const {CatalogType.playlist, CatalogType.leaderboard};
}
