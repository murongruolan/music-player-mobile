// 网易云真实联网冒烟测试。LIVE=1 时运行：LIVE=1 flutter test test/live/netease_live_test.dart
// 只有单曲搜索失败算测试失败，其它接口失败只打印原因（海外 runner 上部分接口可能被限制）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/netease.dart';
import 'live_util.dart';

void main() {
  test('netease live', () async {
    final p = NeteasePlatform(liveHttp());
    String first<T>(List<T> l) => l.isEmpty ? '0 条' : '${l.length} 条，第一条 ${l.first}';

    final songs = await probe('search song 知我', () => p.search('知我', SearchType.song), (r) => '${first(r.songs)} total=${r.total}', required: true);
    final playlists = await probe('search playlist 知我', () => p.search('知我', SearchType.playlist), (r) => '${first(r.items)} total=${r.total}');
    await probe('search artist 知我', () => p.search('知我', SearchType.artist), (r) => first(r.items));
    await probe('search album 知我', () => p.search('知我', SearchType.album), (r) => first(r.items));
    await probe('search mv 知我', () => p.search('知我', SearchType.mv), (r) => first(r.songs));
    await probe('suggest 知我', () => p.suggest('知我'), (l) => first(l));
    await probe('hotSearch', p.hotSearch, (l) => first(l));
    await probe('playlistCategories', p.playlistCategories, (l) => '${l.length} 个：${l.take(5).map((c) => c.name).join(',')}');
    final square = await probe('playlists', () => p.playlists(), (r) => '${first(r.items)} total=${r.total} hasMore=${r.hasMore}');
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
    final withMv = songs?.songs.where((s) => s.mvId != null).firstOrNull;
    if (withMv != null) {
      await probe('mvUrl ${withMv.mvId}', () => p.mvUrl(withMv.mvId!), (u) => '$u');
    }
  }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));
}
