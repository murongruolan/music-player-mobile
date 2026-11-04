// 电台：私人电台（收藏 + 此刻热门 + 新歌 / 飙升榜，打乱）和歌手电台（平台上这位歌手的歌，打乱）。
// 平台没有公开的「相似歌曲」接口，这里不假装推荐，只用能拿到的真实列表拼队列；「不感兴趣」的歌一律排除。
import 'dart:math' as math;
import '../core/state.dart';
import '../data/mock.dart';
import '../platform/models.dart';
import '../platform/registry.dart';
import '../source/source_manager.dart' show normalizeSinger;
import 'remote.dart' show registerTrack, boardTracks;

/// 私人电台：[liked] 收藏、[hot] 此刻热门、[boards] 里每个榜单的前 10 首，去重、去掉不感兴趣的，打乱后播放。
Future<void> playPersonalRadio(AppState app, {List<int> hot = const [], List<CatalogItem> boards = const []}) async {
  final lists = await Future.wait([for (final b in boards.take(2)) boardTracks(app, b).catchError((Object _) => <int>[])]);
  final pool = <int>{...app.liked, ...hot, for (final l in lists) ...l}.where((id) => id < songs.length && !app.isDisliked(id)).toList()..shuffle(math.Random());
  if (pool.isEmpty) return app.notice?.call('暂时没有可以放进电台的歌', 'info');
  final ids = pool.take(60).toList();
  app.play(ids.first, name: '私人电台', ids: ids);
}

/// 歌手电台：在歌手所在平台搜这位歌手的歌（只留歌手名对得上的），加上音乐库里这位歌手的歌，打乱后播放。
Future<void> playArtistRadio(AppState app, String artist, {String? platform}) async {
  final name = artist.trim();
  if (name.isEmpty) return;
  final target = normalizeSinger(name);
  bool match(String a) {
    final n = normalizeSinger(a);
    return n == target || n.split('、').contains(target) || target.split('、').any((x) => x.isNotEmpty && n.split('、').contains(x));
  }

  app.notice?.call('正在生成「$name」电台…', 'wave');
  final plat = platform ?? app.plat;
  final found = <int>[];
  try {
    final o = await app.content.search(plat, name, SearchType.song, limit: 40);
    for (final t in o.result.songs) {
      if (match(t.artist)) found.add(registerTrack(app, t));
    }
  } catch (_) {
    // 搜索失败就只用音乐库里的
  }
  final lib = [for (final s in songs) if (s.key != null && match(s.artist)) s.id];
  final ids = <int>{...found, ...lib}.where((id) => !app.isDisliked(id)).toList()..shuffle(math.Random());
  if (ids.length < 2) return app.notice?.call('没找到「$name」的更多歌曲', 'info');
  app.play(ids.first, name: '$name 电台', ids: ids);
}

/// 当前队列是不是电台（歌曲菜单据此显示「不感兴趣」）。
bool isRadioQueue(AppState app) => app.queueName == '私人电台' || app.queueName.endsWith(' 电台');

/// 平台代码：从歌曲 key（`wy:123`）里取。
String? platformOfSong(int id) {
  if (id < 0 || id >= songs.length) return null;
  final k = songs[id].key;
  if (k == null || !k.contains(':')) return null;
  final c = k.substring(0, k.indexOf(':'));
  return Plat.all.contains(c) ? c : PlatformHub.codeOf(c);
}
