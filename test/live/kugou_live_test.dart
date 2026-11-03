// 酷狗真实联网冒烟测试（LIVE=1 时运行）。只有歌曲搜索是必须成功的，其余失败只打印原因。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/kugou.dart';
import 'package:lyra/platform/models.dart';
import 'live_util.dart';

String _first(List<Object?> list) => list.isEmpty ? '无' : '${list.first}';

void main() {
  test('酷狗 live', () async {
    final p = KugouPlatform(liveHttp());
    final songs = await probe('kg search song', () => p.search('知我', SearchType.song, limit: 20), (r) => '${r.songs.length} 首 / total ${r.total}，首条 ${_first(r.songs)}', required: true);
    for (final type in [SearchType.album, SearchType.artist, SearchType.playlist]) {
      await probe('kg search ${type.name}', () => p.search('知我', type, limit: 20), (r) => '${r.items.length} 条 / total ${r.total}，首条 ${_first(r.items)}');
    }
    await probe('kg suggest', () => p.suggest('知我'), (r) => '${r.length} 条：${r.take(5).join('，')}');
    await probe('kg hotSearch', p.hotSearch, (r) => '${r.length} 条：${r.take(5).join('，')}');
    await probe('kg playlistCategories', p.playlistCategories, (r) => '${r.length} 个，首个标签 ${r.length > 6 ? '${r[6].id} ${r[6].name}' : '无'}');
    final plaza = await probe('kg playlists', () => p.playlists(limit: 20), (r) => '${r.items.length} 个，首个 ${_first(r.items)}');
    final boards = await probe('kg leaderboards', p.leaderboards, (r) => '${r.length} 个，首个 ${_first(r)}');
    if (plaza != null && plaza.items.isNotEmpty) {
      await probe('kg playlist detail', () => p.collection(CatalogType.playlist, plaza.items.first.id, limit: 20), (c) => '${c.title}：${c.tracks.length}/${c.total} 首，首条 ${_first(c.tracks)}');
    }
    if (boards != null && boards.isNotEmpty) {
      await probe('kg leaderboard detail', () => p.collection(CatalogType.leaderboard, boards.first.id, limit: 20), (c) => '${c.title}：${c.tracks.length}/${c.total} 首，首条 ${_first(c.tracks)}');
    }
    if (songs != null && songs.songs.isNotEmpty) {
      final first = songs.songs.first;
      final albumId = '${first.identity['albumId']}';
      if (albumId.isNotEmpty && albumId != '0') {
        await probe('kg album detail', () => p.collection(CatalogType.album, albumId, limit: 20), (c) => '${c.title}：${c.tracks.length} 首');
      }
      await probe('kg lyric', () => p.lyric(first), (l) => '${l.lrc.split('\n').length} 行，逐字 ${l.words?.length ?? 0} 行，翻译 ${l.translation != null}，首行 ${l.lrc.split('\n').first}');
    }
  }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));
}
