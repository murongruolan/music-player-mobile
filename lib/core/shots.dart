// 截图 / 演示入口：Web 端 `?shot=<id>` 直接跳到某个页面或状态（CI 截图、设计走查用）。
// 移动端没有 URL 参数，不受影响。
import 'package:flutter/material.dart';
import '../auth/auth.dart';
import '../pages/detail.dart';
import '../pages/misc.dart';
import '../pages/audio_match_page.dart';
import '../pages/scan.dart';
import '../pages/settings.dart';
import '../player/player.dart';
import '../shell/shell.dart';
import '../widgets/picker.dart';
import '../widgets/sheets.dart';
import 'state.dart';

String? shotFromUrl() {
  try {
    return Uri.base.queryParameters['shot'];
  } catch (_) {
    return null;
  }
}

/// 第一帧之前就能决定的状态。格式：`页面[.修饰]`，例如 `discover.light`、`player.vinyl`。
void applyShotState(AppState app, String id) {
  final parts = id.split('.');
  app.authed = true;
  app.playing = true;
  app.autoPopups = parts.first == 'popup';
  for (final m in parts.skip(1)) {
    if (m == 'light') app.themeMode = ThemeMode.light;
    if (m.startsWith('acc')) app.accent = int.tryParse(m.substring(3)) ?? 0;
    if (m.startsWith('bar-')) app.bar = m.substring(4);
    if (m == 'qq' || m == 'kugou' || m == 'kuwo' || m == 'migu') app.plat = m;
    if (m == 'nologin') app.platLogin.clear();
    if (m == 'paused') app.playing = false;
    if (m == 'clip') app.clipSong = 7;
  }
  switch (parts.first) {
    case 'disclaimer':
    case 'login':
    case 'register':
    case 'forgot':
    case 'version':
      app.authed = false;
      app.authPage = const {'version': 'versionDisabled', 'register': 'login'}[parts.first] ?? parts.first;
      break;
    case 'search':
      app.tab = 1;
      break;
    case 'daily':
      app.tab = 2;
      break;
    case 'library':
      app.tab = 3;
      if (parts.length > 1 && const ['歌单', '最近', '本地'].contains(parts[1])) app.libSeg = parts[1];
      if (parts.contains('pl')) app.libSeg = '歌单';
      if (parts.contains('local')) app.libSeg = '本地';
      if (parts.contains('recent')) app.libSeg = '最近';
      break;
    case 'me':
      app.tab = 4;
      break;
    case 'charts':
      app.homeTab = '榜单';
      break;
    case 'player':
      if (parts.length > 1) app.skin = parts[1];
      break;
  }
  app.pos.value = 34;
}

/// 第一帧之后的界面动作：推入二级页、打开播放器 / Sheet。
void applyShotUi(BuildContext context, String id) {
  final parts = id.split('.');
  void p(Widget w) => push(context, w);
  switch (parts.first) {
    case 'playlist':
      p(const PlaylistPage(id: 0));
      break;
    case 'artist':
      p(const ArtistPage(id: 0));
      break;
    case 'stats':
      p(const StatsPage());
      break;
    case 'appearance':
      p(const AppearancePage());
      break;
    case 'lyricset':
      p(const LyricsSettingsPage());
      break;
    case 'playback':
      p(const PlaybackPage());
      break;
    case 'smart':
      p(const SmartPage());
      break;
    case 'sources':
      p(const SourcesPage());
      break;
    case 'accounts':
      p(const PlatAccountsPage());
      break;
    case 'account':
      p(const AccountPage());
      break;
    case 'cloud':
      p(const CloudPage());
      break;
    case 'about':
      p(const AboutPage());
      break;
    case 'notice':
      p(const AnnouncementsPage());
      break;
    case 'download':
      p(const DownloadPage());
      break;
    case 'scan':
      pushFull(context, const ScanPage());
      break;
    case 'match':
      pushFull(context, const ScanPage(match: true));
      break;
    case 'am': // 联网听歌识曲：am.listen 识别中 / am.hit 结果
      pushFull(context, Scaffold(body: AudioMatchView(preview: parts.length > 1 ? parts[1] : 'listen')));
      break;
    case 'player':
      openPlayer(context);
      break;
    case 'picker':
      showPicker(context, Rect.fromLTWH(20, MediaQuery.of(context).padding.top + 76, MediaQuery.of(context).size.width - 40, 54));
      break;
    case 'sheet':
      final k = parts.length > 1 ? parts[1] : 'more';
      switch (k) {
        case 'more':
          openSongMore(context, 0, 'daily');
          break;
        case 'import':
          openImportPlaylist(context);
          break;
        case 'platlogin':
          openPlatLogin(context, 'qq');
          break;
        case 'eq':
          openEq(context);
          break;
        case 'skins':
          openSkins(context);
          break;
        case 'bars':
          openBarStyles(context);
          break;
        case 'icons':
          openAppIcons(context);
          break;
        case 'queue':
          openQueue(context);
          break;
        case 'home':
          openHomeOrder(context);
          break;
        case 'quality':
          openQuality(context);
          break;
      }
      break;
  }
  if (parts.first == 'register') {
    // 注册页需要切 Tab：用 LoginPage 内部状态无法直接设置，交给演示时手动点击
  }
  if (parts.first == 'version' && context.appRead.authed) pushFull(context, const VersionDisabledPage());
}
