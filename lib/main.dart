// Lyra（暂名）· Flutter 移动端（mock 数据版）
// 入口：AppScope（全局状态）→ MaterialApp（主题随设置实时切换）→ 鉴权流程 / 主界面。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth/auth.dart';
import 'core/shots.dart';
import 'core/state.dart';
import 'core/tokens.dart';
import 'shell/shell.dart';
import 'ui/kit.dart';
import 'widgets/sheets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerSheets();
  SystemChrome.setSystemUIOverlayStyle(overlayStyle(true));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final app = AppState();
  final shot = shotFromUrl();
  if (shot != null) applyShotState(app, shot);
  runApp(LyraApp(state: app, shot: shot));
}

/// 系统栏全透明（沿用 .light/.dark 预设会把 Android 导航条刷成黑色）。
SystemUiOverlayStyle overlayStyle(bool dark) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

class LyraApp extends StatelessWidget {
  final AppState state;
  final String? shot;
  const LyraApp({super.key, required this.state, this.shot});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final app = context.app;
        final pal = app.pal(MediaQuery.platformBrightnessOf(context));
        final family = app.font == 'system' ? null : fontFamilyOf(app.font);
        final fallback = fontFallbackOf(app.font);
        return MaterialApp(
          title: 'Lyra',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNav,
          themeMode: pal.dark ? ThemeMode.dark : ThemeMode.light,
          theme: _theme(pal, family, fallback),
          darkTheme: _theme(pal, family, fallback),
          builder: (context, child) => PalScope(
            pal: pal,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle(pal.dark),
              // 显式给出默认文字样式：没有 Material 祖先的浮层（Toast、音源面板）也不会出现黄色双下划线
              child: DefaultTextStyle(
                style: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 14, color: pal.t1, decoration: TextDecoration.none),
                child: child!,
              ),
            ),
          ),
          home: Root(shot: shot),
        );
      }),
    );
  }

  ThemeData _theme(Pal pal, String? family, List<String>? fallback) {
    final dark = pal.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: pal.bg,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      fontFamily: family,
      fontFamilyFallback: fallback,
      colorScheme: ColorScheme.fromSeed(seedColor: pal.acc, brightness: dark ? Brightness.dark : Brightness.light, surface: pal.bg),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      textSelectionTheme: TextSelectionThemeData(cursorColor: pal.acc, selectionColor: (pal.acc).withValues(alpha: .3), selectionHandleColor: pal.acc),
    );
    return base.copyWith(textTheme: base.textTheme.apply(bodyColor: pal.t1, displayColor: pal.t1, fontFamily: family));
  }
}

class Root extends StatefulWidget {
  final String? shot;
  const Root({super.key, this.shot});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  @override
  void initState() {
    super.initState();
    if (widget.shot != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 400), () => applyShotUi(context, widget.shot!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: app.authed ? const Shell(key: ValueKey('shell')) : const AuthFlow(key: ValueKey('auth')),
    );
  }
}
