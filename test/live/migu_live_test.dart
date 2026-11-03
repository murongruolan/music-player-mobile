// 咪咕真实联网冒烟测试。LIVE=1 时运行：LIVE=1 flutter test test/live/migu_live_test.dart
// 咪咕接口在桌面端也没有实测通过，所有接口失败都只打印原因，不算测试失败。suggest 未实现，固定返回空列表。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/migu.dart';
import 'live_util.dart';

void main() {
  test('migu live', () async {
    final p = MiguPlatform(liveHttp());
    String first<T>(List<T> l) => l.isEmpty ? '0 条' : '${l.length} 条，第一条 ${l.first}';

    final songs = await probe('search song 知我', () => p.search('知我', SearchType.song), (r) => '${first(r.songs)} total=${r.total}');
    final playlists = await probe('search playlist 知我', () => p.search('知我', SearchType.playlist), (r) => '${first(r.items)} total=${r.total}');
    await probe('suggest 知我', () => p.suggest('知我'), (l) => first(l));
    await probe('hotSearch', p.hotSearch, (l) => first(l));
    final cats = await probe('playlistCategories', p.playlistCategories, (l) => '${l.length} 个：${l.take(5).map((c) => '${c.name}(${c.id})').join(',')}');
    final square = await probe('playlists', () => p.playlists(), (r) => '${first(r.items)} total=${r.total} hasMore=${r.hasMore}');
    final cat = cats?.where((c) => c.group != '排序' && c.id != '全部' && c.id != 'recommend').firstOrNull;
    if (cat != null) {
      await probe('playlists ${cat.name}', () => p.playlists(category: cat.id), (r) => '${first(r.items)} total=${r.total} hasMore=${r.hasMore}');
    }
    final boards = await probe('leaderboards', p.leaderboards, (l) => first(l));

    final playlistId = square?.items.firstOrNull?.id ?? playlists?.items.firstOrNull?.id;
    if (playlistId != null) {
      await probe('collection playlist $playlistId', () => p.collection(CatalogType.playlist, playlistId, limit: 20), (c) => '${c.title} total=${c.total} ${first(c.tracks)}');
    }
    final boardId = boards?.firstOrNull?.id;
    if (boardId != null) {
      await probe('collection leaderboard $boardId', () => p.collection(CatalogType.leaderboard, boardId, limit: 20), (c) => '${c.title} total=${c.total} ${first(c.tracks)}');
    }

    final song = songs?.songs.firstOrNull;
    if (song != null) {
      await probe('lyric ${song.title}', () => p.lyric(song), (l) => 'lrc ${l.lrc.length} 字，翻译 ${l.translation != null}，逐字 ${l.words?.length ?? 0} 行');
    }
  }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));
}
