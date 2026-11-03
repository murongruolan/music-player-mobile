// 主界面外壳：内容区（嵌套 Navigator，二级页右侧推入 + 左缘右滑返回）+ 迷你播放条 + 底栏。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../pages/daily.dart';
import '../pages/discover.dart';
import '../pages/library.dart';
import '../pages/me.dart';
import '../pages/search.dart';
import '../ui/kit.dart';
import '../widgets/announce.dart';
import 'clip_banner.dart';
import 'mini.dart';
import 'nav.dart';

final contentNav = GlobalKey<NavigatorState>();
final tabScroll = List.generate(5, (_) => ScrollController());

/// 二级页：在内容区内推入（保留迷你播放条与底栏）。
Future<T?> push<T>(BuildContext context, Widget page) {
  final nav = contentNav.currentState;
  if (nav == null) return Future.value();
  return nav.push<T>(CupertinoPageRoute(builder: (_) => page));
}

/// 全屏页：盖住迷你播放条与底栏（扫一扫、识曲、登录流程）。
Future<T?> pushFull<T>(BuildContext context, Widget page) =>
    rootNav.currentState!.push<T>(CupertinoPageRoute(fullscreenDialog: false, builder: (_) => page));

void popToRoot() => contentNav.currentState?.popUntil((r) => r.isFirst);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      await context.appRead.anns.load(); // 演示模式下直接返回
      if (mounted && context.appRead.autoPopups) showAnnouncementPopups(context);
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) detectClipboard(context.appRead);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) detectClipboard(context.appRead);
  }

  void _onTab(int i) {
    final app = context.appRead;
    final canPop = contentNav.currentState?.canPop() ?? false;
    if (i == app.tab && !canPop) {
      final c = tabScroll[i];
      if (c.positions.length == 1) c.animateTo(0, duration: const Duration(milliseconds: 520), curve: Tk.out);
      app.update(() => app.navMin = false);
      return;
    }
    popToRoot();
    app.update(() {
      app.tab = i;
      app.navMin = false;
      app.searchFocus = false;
    });
  }

  bool _onScroll(ScrollNotification n) {
    final app = context.appRead;
    if (n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) return false;
    if (!app.set.navAutoMin || app.tab == 1 || !const ['liquid', 'island', 'classic', 'frosted', 'text'].contains(app.bar)) return false;
    final y = n.metrics.pixels, dy = n.scrollDelta ?? 0;
    final want = y > 140 && dy > 4 ? true : (dy < -6 || y < 60) ? false : app.navMin;
    if (want != app.navMin) app.update(() => app.navMin = want);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final hideChrome = app.searchFocus;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = contentNav.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (app.tab != 0) {
          _onTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: pal.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: HeroControllerScope.none(
                child: Navigator(
                  key: contentNav,
                  onGenerateRoute: (_) => PageRouteBuilder(pageBuilder: (_, __, ___) => const TabsHost(), transitionDuration: Duration.zero),
                ),
              ),
            ),
          ),
          if (app.tab != 1) const MiniPlayer(),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Tk.out,
            left: 0,
            right: 0,
            bottom: hideChrome ? -140 : 0,
            height: 220,
            child: AnimatedOpacity(
              duration: Tk.base,
              opacity: hideChrome ? 0 : 1,
              child: BottomNav(tab: app.tab, onTab: _onTab),
            ),
          ),
          if (app.clipSong != null) const ClipBanner(),
        ]),
      ),
    );
  }
}

class TabsHost extends StatefulWidget {
  const TabsHost({super.key});
  @override
  State<TabsHost> createState() => _TabsHostState();
}

/// 已访问过的 Tab 常驻（Offstage + 关闭 Ticker），切换时只做 200ms 淡入，
/// 避免每次切 Tab 都整页重建导致底栏指示器掉帧。
class _TabsHostState extends State<TabsHost> with SingleTickerProviderStateMixin {
  final _built = <int>[];
  int _last = -1;
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 1);

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Widget _page(int t) => switch (t) {
        1 => const SearchPage(),
        2 => const DailyPage(),
        3 => const LibraryPage(),
        4 => const MePage(),
        _ => const DiscoverPage(),
      };

  @override
  Widget build(BuildContext context) {
    final tab = context.app.tab;
    if (!_built.contains(tab)) _built.add(tab);
    if (tab != _last) {
      if (_last >= 0 && !context.appRead.set.reduceMotion) _fade.forward(from: 0);
      _last = tab;
    }
    return Stack(children: [
      for (final t in _built)
        Offstage(
          key: ValueKey(t),
          offstage: t != tab,
          child: TickerMode(
            enabled: t == tab,
            child: FadeTransition(opacity: t == tab ? _fade : kAlwaysCompleteAnimation, child: _page(t)),
          ),
        ),
    ]);
  }
}
