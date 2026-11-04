import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
// Lyra（暂名）· Flutter 移动端（mock 数据版）
// 入口：AppScope（全局状态）→ MaterialApp（主题随设置实时切换）→ 鉴权流程 / 主界面。
import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio/audio_engine.dart';
import 'audio/media_handler.dart';
import 'auth/auth.dart';
import 'core/app_log.dart';
import 'core/shots.dart';
import 'core/state.dart';
import 'core/tokens.dart';
import 'net/api_config.dart';
import 'net/net.dart';
import 'player/player.dart';
import 'shell/shell.dart';
import 'source/direct/direct.dart';
import 'source/music_resolver.dart';
import 'ui/cover_tint.dart';
import 'ui/kit.dart';
import 'widgets/sheets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnostics();
  registerSheets();
  SystemChrome.setSystemUIOverlayStyle(overlayStyle(true));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final shot = shotFromUrl();
  // 截图模式不连后端，页面全部用 mock 数据
  final net = shot != null ? null : await Net.create();
  await AppLog.instance.attach(net?.prefs); // 读本机保存的崩溃记录
  net?.session.onEnd.where((r) => r == SessionEnd.expired).listen((_) => toast('登录已失效，请重新登录', 'lock'));
  // 音频引擎：截图模式不创建（无平台通道，保持模拟时钟），正式运行才有真实播放 + 通知栏
  AudioEngine? engine;
  final resolver = MusicResolver();
  if (shot == null) {
    final handler = LyraMediaHandler();
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.lyra.mobile.playback',
        androidNotificationChannelName: '正在播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    // 播放地址由导入的洛雪音源脚本解析（lib/source/）
    engine = AudioEngine(resolver: resolver);
    await engine.init(handler);
  }
  final app = AppState(net: net, engine: engine, resolver: resolver)
    ..notice = (msg, icon) {
      AppLog.instance.add('提示', msg); // 提示气泡（含播放失败原因）都记进应用日志
      toast(msg, icon);
    };
  // 「自动上报崩溃」开着才上报；本机记录不受开关影响
  AppLog.instance.onCrash = (c) {
    if (app.set.crash) app.telemetry.track('app_crash', {'message': c.message.length > 500 ? c.message.substring(0, 500) : c.message, 'stack': c.stack.length > 3000 ? c.stack.substring(0, 3000) : c.stack, 'version': ApiConfig.appVersion});
  };
  AppLog.instance.add('启动', 'v${ApiConfig.appVersion} (${ApiConfig.buildNumber}) · ${net == null ? '演示模式' : '联网模式'}');
  resolver.app = app;
  resolver.direct = DirectLinkResolver(app.platCreds); // 平台直链（凭证只读 platCreds）
  CoverTint.onReady = app.notify; // 封面取色完成后播放器背景重绘
  await app.cloud.init(); // 读本地听歌统计
  await app.taste.load(); // 关注的歌手、不感兴趣的歌
  await app.initPlatformLogin(); // 平台登录凭证（钥匙串）；网易云游客 Cookie 在后台取
  await app.telemetry.init(); // 读上次没发完的埋点
  await app.downloads.init(); // 下载清单 + 目录
  unawaited(app.applyCacheToEngine()); // 边听边缓存开关联动引擎
  app.restoreSession();
  if (app.authed) unawaited(app.autoplayLast()); // 「启动时自动播放」：音乐库和音源脚本已在 cloud.init 里读好
  app.telemetry.track('app_launch', {'source': 'normal', 'loggedIn': app.authed});
  unawaited(app.checkUpdate());
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
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.app;
      if (app.set.autoOpen && app.hasSong) openPlayer(context); // 「启动时打开播放页」
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: app.versionBlock != null
          ? VersionDisabledPage(key: const ValueKey('vd'), info: app.versionBlock)
          : app.authed
              ? const Shell(key: ValueKey('shell'))
              : const AuthFlow(key: ValueKey('auth')),
    );
  }
}

/// 崩溃 / 错误收集：框架错误、未捕获的异步错误记进 [AppLog]（设置 → 关于与更新 → 诊断），debugPrint 也顺带记一份。
void _installDiagnostics() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    AppLog.instance.crash(d.exception, d.stack);
    prev?.call(d);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    AppLog.instance.crash(e, st);
    return false; // 交回默认处理（打印），只是多记一份
  };
  final print0 = debugPrint;
  debugPrint = (m, {wrapWidth}) {
    if (m != null) AppLog.instance.add('debug', m);
    print0(m, wrapWidth: wrapWidth);
  };
}
