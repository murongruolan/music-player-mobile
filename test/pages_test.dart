// 逐个打开二级页、播放器皮肤和 Sheet，确认没有布局溢出或运行时异常。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/data/mock.dart';
import 'package:lyra/main.dart';
import 'package:lyra/pages/detail.dart';
import 'package:lyra/pages/misc.dart';
import 'package:lyra/pages/scan.dart';
import 'package:lyra/pages/settings.dart';
import 'package:lyra/player/player.dart';
import 'package:lyra/shell/shell.dart';
import 'package:lyra/ui/kit.dart';
import 'package:lyra/widgets/sheets.dart';

Future<AppState> _boot(WidgetTester tester) async {
  registerSheets();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  final app = AppState()..authed = true..autoPopups = false;
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

BuildContext _ctx(WidgetTester tester) => tester.element(find.byType(Shell));

void main() {
  testWidgets('secondary pages', (tester) async {
    final app = await _boot(tester);
    final pages = <Widget>[
      const PlaylistPage(id: 0), const PlaylistPage(id: 100), const ArtistPage(id: 3), const StatsPage(),
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
    pushFull(_ctx(tester), const ScanPage());
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull, reason: 'scan');
    await _done(tester, app);
  });

  testWidgets('player skins', (tester) async {
    final app = await _boot(tester);
    for (final s in skins) {
      app.update(() => app.skin = s.id);
      openPlayer(_ctx(tester));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: s.id);
      rootNav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await _done(tester, app);
  });

  testWidgets('sheets', (tester) async {
    final app = await _boot(tester);
    final opens = <String, void Function(BuildContext)>{
      'more': (c) => openSongMore(c, 0, 'daily'),
      'add': (c) => openAddToPlaylist(c, 0),
      'new': openNewPlaylist,
      'import': openImportPlaylist,
      'platLogin': (c) => openPlatLogin(c, 'qq', mode: '手机号'),
      'share': (c) => openShareCode(c, songId: 1),
      'timer': openTimer,
      'eq': openEq,
      'quality': openQuality,
      'speed': openSpeed,
      'cast': openCast,
      'lyricCard': openLyricCard,
      'trace': openTrace,
      'queue': openQueue,
      'bars': openBarStyles,
      'icons': openAppIcons,
      'fonts': openFonts,
      'skins': openSkins,
      'bg': openBg,
      'home': openHomeOrder,
      'importSource': openImportSource,
    };
    for (final e in opens.entries) {
      e.value(_ctx(tester));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: e.key);
      rootNav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _done(tester, app);
  });

  testWidgets('light theme + every tab', (tester) async {
    final app = await _boot(tester);
    app.update(() => app.themeMode = ThemeMode.light);
    for (var t = 0; t < 5; t++) {
      app.update(() => app.tab = t);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: 'tab $t');
    }
    app.update(() => app.platLogin.clear());
    app.update(() => app.tab = 0);
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull, reason: 'discover logged out');
    await _done(tester, app);
  });
}
