// 导入平台歌单：链接 → 预览（第一页）→ 两种导入方式。
// - 保持同步（默认）：存成「收藏的平台歌单」，只记平台 + 歌单 id，打开时实时拉取。
//   云同步里就是 kind=collected，桌面端显示为「导入的歌单」（与桌面端 external 歌单互通）。
// - 复制一份：把全部歌曲拉下来存成自建歌单，之后与原歌单无关，可以自己增删。
import '../data/models.dart';
import '../platform/models.dart';
import '../platform/playlist_link.dart';
import '../platform/registry.dart' show platformError;
import 'state.dart';

class PlaylistImporter {
  PlaylistImporter(this.app);
  final AppState app;

  /// 复制模式最多拉这么多首（防止超大歌单一路翻页）。
  static const maxTracks = 3000;

  /// 解析输入。失败抛 [PlaylistLinkException]（文案可直接给用户看）。
  Future<PlaylistRef> resolve(String input, {required String fallbackPlatform}) async {
    try {
      final r = await resolvePlaylistInput(input, http: app.content.http, fallbackPlatform: fallbackPlatform);
      if (!app.content.supports(r.platform)) throw const PlaylistLinkException('暂不支持这个平台的歌单');
      return r;
    } on PlaylistLinkException {
      rethrow;
    } catch (e) {
      throw PlaylistLinkException(platformError(e));
    }
  }

  /// 第一页（标题 / 封面 / 总数）。
  Future<Collection> preview(PlaylistRef r) async {
    try {
      final c = await app.content.collection(r.platform, CatalogType.playlist, r.id, page: 1, limit: 100);
      if (c.tracks.isEmpty && c.total == 0 && c.title.isEmpty) throw const PlaylistLinkException('歌单不存在，或者是私密歌单');
      return c;
    } on PlaylistLinkException {
      rethrow;
    } catch (e) {
      throw PlaylistLinkException(platformError(e));
    }
  }

  /// 已经导入（收藏）过的同一个歌单。
  Playlist? existing(PlaylistRef r) => app.library.collectedOf(r.platform, r.id);

  /// 保持同步：存成平台歌单引用。
  Playlist link(PlaylistRef r, Collection head) => app.library.collect(
        platform: r.platform,
        externalId: r.id,
        name: head.title,
        cover: head.cover,
        description: head.description,
        total: head.total > 0 ? head.total : null,
      );

  /// 从第一页开始把剩下的页拉完。某页没有新歌 / 页码不前进就停（平台忽略分页时不会死循环）。
  Future<List<PTrack>> allTracks(PlaylistRef r, Collection head, {void Function(int got, int total)? onProgress, bool Function()? cancelled}) async {
    final seen = <String>{};
    final out = <PTrack>[];
    void add(Iterable<PTrack> ts) {
      for (final t in ts) {
        if (out.length >= maxTracks) return;
        if (seen.add(t.id)) out.add(t);
      }
    }

    add(head.tracks);
    var c = head;
    var page = 1;
    onProgress?.call(out.length, head.total);
    while (c.hasMore && out.length < maxTracks) {
      if (cancelled?.call() ?? false) break;
      final before = out.length;
      page++;
      c = await app.content.collection(r.platform, CatalogType.playlist, r.id, page: page, limit: c.limit > 0 ? c.limit : 100);
      add(c.tracks);
      onProgress?.call(out.length, head.total);
      if (out.length == before) break;
    }
    return out;
  }

  /// 复制一份：新建自建歌单并放进全部歌曲。返回 (歌单, 实际放进去的首数)。
  Future<(Playlist, int)> copy(PlaylistRef r, Collection head, {void Function(int got, int total)? onProgress, bool Function()? cancelled}) async {
    final tracks = await allTracks(r, head, onProgress: onProgress, cancelled: cancelled);
    final name = head.title.trim().isEmpty ? '导入的歌单' : head.title.trim();
    final hue = (name.hashCode.abs() % 360).toDouble();
    final p = app.library.createPlaylist(name, hue);
    final ids = [for (final t in tracks) app.library.register(t.toCloud())];
    final n = app.library.addToPlaylist(p.id, ids);
    app.notify();
    return (app.myPlaylists.firstWhere((x) => x.id == p.id, orElse: () => p), n);
  }
}
