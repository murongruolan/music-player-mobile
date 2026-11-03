import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/registry.dart';
import '../support/fake_platform.dart';

void main() {
  test('App 平台 id 和平台代码都能找到平台', () {
    final hub = fakeHub();
    expect(PlatformHub.codeOf('netease'), 'wy');
    expect(PlatformHub.codeOf('kg'), 'kg');
    expect(hub.of('qq')!.code, 'tx');
    expect(hub.supports('local'), isFalse);
  });

  test('缓存：TTL 内复用，过期或 invalidate 后重新请求', () async {
    var now = DateTime(2026, 11, 2);
    final wy = FakePlatform('wy');
    final hub = PlatformHub.of({'wy': wy}, ttl: const Duration(minutes: 10), now: () => now);
    await hub.leaderboards('netease');
    await hub.leaderboards('wy');
    expect(wy.calls['leaderboards'], 1);
    now = now.add(const Duration(minutes: 11));
    await hub.leaderboards('wy');
    expect(wy.calls['leaderboards'], 2);
    hub.invalidate('netease');
    await hub.leaderboards('wy');
    expect(wy.calls['leaderboards'], 3);
  });

  test('失败的结果不缓存', () async {
    final kg = FakePlatform('kg', fail: {'hotSearch'});
    final hub = PlatformHub.of({'kg': kg});
    await expectLater(hub.hotSearch('kg'), throwsA(isA<PlatformException>()));
    await expectLater(hub.hotSearch('kg'), throwsA(isA<PlatformException>()));
    expect(kg.calls['hotSearch'], 2);
  });

  test('首页：第一个榜单的前 10 首 + 12 个歌单 + 9 个榜单', () async {
    final hub = fakeHub();
    final d = await hub.discover('qq');
    expect(d.hotBoard!.id, 'leaderboard0');
    expect(d.hot.length, 10);
    expect(d.playlists.length, 12);
    expect(d.boards.length, 9);
    expect(d.errors, isEmpty);
  });

  test('首页：部分失败照常返回并带说明，全部失败才抛错', () async {
    final partial = await fakeHub(fail: {'kw': {'playlists'}}).discover('kw');
    expect(partial.playlists, isEmpty);
    expect(partial.hot, isNotEmpty);
    expect(partial.errors.single, contains('推荐歌单'));
    await expectLater(fakeHub(fail: {'mg': {'playlists', 'leaderboards'}}).discover('mg'), throwsA(isA<PlatformException>()));
  });

  test('搜索：非网易平台失败时回退到网易', () async {
    final hub = fakeHub(fail: {'kg': {'search'}});
    final o = await hub.search('kugou', '晴天', SearchType.song);
    expect(o.platform, 'wy');
    expect(o.fallbackFrom, 'kg');
    expect(o.error, contains('失败'));
    expect(o.result.songs.first.platform, 'wy');
    final direct = await hub.search('qq', '晴天', SearchType.song);
    expect(direct.platform, 'tx');
    expect(direct.fallbackFrom, isNull);
  });

  test('搜索：网易自己失败直接报错', () async {
    final hub = fakeHub(fail: {'wy': {'search'}});
    await expectLater(hub.search('wy', 'x', SearchType.song), throwsA(isA<PlatformException>()));
  });
}
