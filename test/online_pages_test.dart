// 联网模式（真实数据、没有 mock 内容）下逐个打开 Tab、二级页和 Sheet，确认不会因为 mock 下标越界等崩溃。
// 后端用 MockClient 模拟；歌曲目录先放两首来自「云同步」的真实歌曲和一个歌单。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/data/mock.dart';
import 'package:lyra/main.dart';
import 'package:lyra/net/net.dart';
import 'package:lyra/pages/detail.dart';
import 'package:lyra/pages/misc.dart';
import 'package:lyra/pages/settings.dart';
import 'package:lyra/player/player.dart';
import 'package:lyra/shell/mini.dart';
import 'package:lyra/shell/shell.dart';
import 'package:lyra/sync/cloud_models.dart';
import 'package:lyra/ui/kit.dart';
import 'package:lyra/widgets/sheets.dart';
import 'package:lyra/pages/remote.dart';
import 'package:lyra/pages/search.dart';
import 'package:lyra/platform/models.dart' show CatalogType, PlaylistCategory;
import 'package:lyra/pages/discover.dart';
import 'support/fake_platform.dart';

http.Response ok(Object? data) => http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'r', 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Future<AppState> _boot(WidgetTester tester, {bool withLibrary = true}) async {
  registerSheets();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  final net = await Net.memory(
    baseUrl: 'https://api.test/api/v1',
    sleep: (_) async {},
    httpClient: MockClient((r) async => switch (r.url.path) {
          '/api/v1/announcements' => ok({'items': []}),
          '/api/v1/auth/devices' => ok({'devices': [], 'maxDevices': 10}),
          '/api/v1/updates/check' => ok({'versionDisabled': false, 'hasUpdate': false, 'latest': null}),
          _ => ok(null),
        }),
  );
  await net.session.save(AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(hours: 2))));
  final app = AppState(net: net, content: fakeHub())
    ..authed = true
    ..autoPopups = false;
  if (withLibrary) {
    final now = DateTime.utc(2026, 11, 1);
    app.library.write(CloudLibrary(
      favorites: const [
        CloudTrack(id: 'wy:1', platform: 'wy', songId: '1', title: '雾港', artist: 'Ari', durationSec: 205),
        CloudTrack(id: 'tx:2', platform: 'tx', songId: '2', title: 'Midnight', artist: 'Nova', durationSec: 180),
      ],
      playlists: [
        CloudPlaylist(id: 'p1', name: '夜跑', tracks: const [CloudTrack(id: 'wy:1', platform: 'wy', songId: '1', title: '雾港', artist: 'Ari')], updatedAt: now, createdAt: now),
        CloudPlaylist(id: 'p2', name: '收藏的平台歌单', kind: 'collected', platform: 'wy', externalId: '7741029', total: 42, updatedAt: now, createdAt: now),
      ],
    ));
  }
  await tester.pumpWidget(LyraApp(state: app));
  await tester.pump(const Duration(seconds: 1));
  return app;
}

Future<void> _done(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  app.dispose();
  tester.view.resetPhysicalSize();
}

/// 多跑几帧：异步加载完成后的 setState 要下一帧才显示。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 没有异常；有的话把完整诊断（出错的组件和源码位置）放进失败信息。
void _noError(WidgetTester tester, [String? what]) {
  final e = tester.takeException();
  expect(e, isNull, reason: '${what ?? ''}\n${e is FlutterError ? e.toStringDeep() : e}');
}

BuildContext _ctx(WidgetTester tester) => tester.element(find.byType(Shell));

void main() {
  testWidgets('联网模式：mock 内容全部清空，没有正在播放的歌', (tester) async {
    final app = await _boot(tester, withLibrary: false);
    // 歌曲目录里只有平台返回的真实歌曲（发现页的此刻热门），没有 mock
    expect(songs.every((s) => s.key != null && s.key!.startsWith('wy:')), isTrue);
    expect(app.hasSong, isFalse);
    expect(app.platLogin, isEmpty);
    expect(app.scripts, isEmpty);
    expect(app.myPlaylists, isEmpty);
    expect(find.byType(MiniPlayer), findsNothing);
    app.playAll('hot');
    expect(app.hasSong, isFalse);
    await _done(tester, app);
  });

  for (final withLibrary in [false, true]) {
    testWidgets('联网模式：每个 Tab（${withLibrary ? '有' : '空'}音乐库）', (tester) async {
      final app = await _boot(tester, withLibrary: withLibrary);
      for (var t = 0; t < 5; t++) {
        app.update(() => app.tab = t);
        await tester.pump(const Duration(milliseconds: 800));
        expect(tester.takeException(), isNull, reason: 'tab $t');
      }
      for (final seg in ['我喜欢', '歌单', '最近', '本地']) {
        app.update(() {
          app.tab = 3;
          app.libSeg = seg;
        });
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: 'library $seg');
      }
      await _done(tester, app);
    });

    testWidgets('联网模式：二级页（${withLibrary ? '有' : '空'}音乐库）', (tester) async {
      final app = await _boot(tester, withLibrary: withLibrary);
      final pl = app.myPlaylists.isEmpty ? 999 : app.myPlaylists.first.id;
      final pages = <Widget>[
        const PlaylistPage(id: 100), PlaylistPage(id: pl), if (withLibrary) PlaylistPage(id: app.myPlaylists.last.id), const ArtistPage(id: 0), const StatsPage(),
        const AppearancePage(), const LyricsSettingsPage(), const SysLyricsPage(), const PlaybackPage(), const SmartPage(), const SourcesPage(),
        const AnnouncementsPage(), const PlatAccountsPage(), const DownloadPage(), const AccountPage(), const DevicesPage(), const BackupPage(), const CloudPage(), const AboutPage(),
      ];
      for (final p in pages) {
        push(_ctx(tester), p);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: p.runtimeType.toString());
        contentNav.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 600));
      }
      await _done(tester, app);
    });
  }

  testWidgets('联网模式：Sheet', (tester) async {
    final app = await _boot(tester);
    final opens = <String, void Function(BuildContext)>{
      'more': (c) => openSongMore(c, 0, ''),
      'add': (c) => openAddToPlaylist(c, 0),
      'new': openNewPlaylist,
      'import': openImportPlaylist,
      'platLogin': (c) => openPlatLogin(c, 'qq'),
      'share': (c) => openShareCode(c, songId: 0),
      'quality': openQuality,
      'queue': openQueue,
    };
    for (final e in opens.entries) {
      e.value(_ctx(tester));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: e.key);
      rootNav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 500));
    }
    // 没有歌时打不开播放器
    openPlayer(_ctx(tester));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PlayerScreen), findsNothing);
    await _done(tester, app);
  });

  testWidgets('联网模式：收藏 / 歌单修改写入本机音乐库', (tester) async {
    final app = await _boot(tester);
    expect(app.liked.length, 2);
    final id = app.liked.first;
    app.toggleLike(id);
    expect(app.library.read().favorites.length, 1);
    final p = app.library.createPlaylist('新歌单', 120);
    expect(app.library.addToPlaylist(p.id, [id]), 1);
    expect(app.library.addToPlaylist(p.id, [id]), 0);
    expect(app.library.read().playlists.firstWhere((x) => x.id == p.key).tracks.single.id, songs[id].key);
    await _done(tester, app);
  });

  testWidgets('联网模式：发现页按原型结构显示平台内容', (tester) async {
    final app = await _boot(tester);
    await _settle(tester);
    // 原型：登录卡 + Banner + 快捷入口 + 精选 / 榜单 / 歌单 + 平台推荐区
    // （快捷入口的「每日混音」已改为「歌单广场」，见 fix/discover-interactions）
    expect(find.text('登录网易云音乐'), findsOneWidget);
    expect(find.byType(BannerCarousel), findsOneWidget);
    expect(find.text('歌单广场'), findsOneWidget);
    expect(find.text('精选'), findsOneWidget);
    expect(find.text('wy 歌曲 1000', skipOffstage: false), findsWidgets);
    // 热门歌曲登记进了歌曲目录，可以收藏
    final id = songs.indexWhere((s) => s.key == 'wy:s1000');
    expect(id, greaterThanOrEqualTo(0));
    app.toggleLike(id);
    expect(app.library.read().favorites.any((t) => t.id == 'wy:s1000'), isTrue);
    for (final t in ['榜单', '歌单', '精选']) {
      app.update(() => app.homeTab = t);
      await _settle(tester);
      _noError(tester, t);
    }
    // 滚到底，平台推荐区全部构建一遍
    await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
    await _settle(tester);
    _noError(tester);
    // 切平台
    app.switchPlatform('kuwo');
    await _settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, 8000));
    await _settle(tester);
    expect(find.text('kw 歌曲 1000', skipOffstage: false), findsWidgets);
    _noError(tester);
    await _done(tester, app);
  });

  testWidgets('联网模式：平台详情 / 歌单广场 / 排行榜，收藏平台歌单', (tester) async {
    final app = await _boot(tester);
    final pages = <Widget>[
      const RemoteCollectionPage(platform: 'tx', type: CatalogType.playlist, id: 'p9', title: '歌单'),
      const RemoteCollectionPage(platform: 'kg', type: CatalogType.leaderboard, id: 'b1'),
      const RemoteCollectionPage(platform: 'wy', type: CatalogType.artist, id: 'a1'),
      const PlaylistSquarePage(platform: 'wy'),
      const PlaylistSquarePage(platform: 'tx', category: PlaylistCategory('c2', '摇滚')),
      const LeaderboardsPage(platform: 'mg'),
    ];
    for (final p in pages) {
      push(_ctx(tester), p);
      await _settle(tester);
      _noError(tester, p.runtimeType.toString());
      if (p is LeaderboardsPage) expect(find.byType(BoardBigCard), findsWidgets);
      if (p is RemoteCollectionPage && p.id == 'p9') {
        expect(find.text('tx 详情 p9'), findsWidgets);
        expect(find.text('tx 歌曲 1000'), findsOneWidget);
        await tester.tap(find.byWidgetPredicate((w) => w is IBtn && w.icon == 'heart' && w.size == 48));
        await _settle(tester);
        final c = app.library.collectedOf('tx', 'p9');
        expect(c, isNotNull);
        expect(app.library.read().playlists.firstWhere((x) => x.externalId == 'p9').kind, 'collected');
      }
      if (p is PlaylistSquarePage && p.category == null) {
        expect(find.text('华语'), findsOneWidget);
        await tester.tap(find.text('华语'));
        await _settle(tester);
        _noError(tester);
      }
      contentNav.currentState!.pop();
      await _settle(tester);
    }
    await _done(tester, app);
  });

  testWidgets('联网模式：搜索按原型结构（全部平台 · 综合 · 各类型）', (tester) async {
    final app = await _boot(tester);
    app.update(() => app.tab = 1);
    await _settle(tester);
    expect(find.text('热搜一'), findsOneWidget);
    await tester.tap(find.text('热搜一'));
    await _settle(tester);
    // 默认「全部平台 · 综合」：五个平台的结果交替合并
    expect(find.text('最佳匹配 · 艺术家'), findsOneWidget);
    expect(find.text('wy 歌曲 100'), findsOneWidget);
    expect(find.text('tx 歌曲 100'), findsOneWidget);
    for (final t in ['歌曲', '专辑', '艺术家', 'MV', '综合']) {
      await tester.tap(find.text(t).first);
      await _settle(tester);
      _noError(tester, t);
    }
    // 单个平台
    await tester.tap(find.text('QQ').first);
    await _settle(tester);
    expect(find.text('tx 歌曲 100'), findsOneWidget);
    expect(find.text('wy 歌曲 100'), findsNothing);
    // 切类型
    await tester.tap(find.text('歌单').first);
    await _settle(tester);
    expect(find.text('tx playlist 0'), findsOneWidget);
    expect(find.byType(SearchPage), findsOneWidget);
    _noError(tester);
    await _done(tester, app);
  });
}
