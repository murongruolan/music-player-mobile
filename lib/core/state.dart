// 全局状态（对应原型 core.js 的 S 与 ACT）。所有页面通过 context.app 读取，修改后 notifyListeners。
// 接口对接时：把 mock 读取换成 Repository 调用即可，UI 不需要改。
import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import '../audio/audio_engine.dart';
import '../cast/cast_controller.dart';
import '../cast/dlna.dart' show CastException;
import '../source/source_manager.dart' show ResolveException;
import '../download/downloads.dart';
import '../source/music_resolver.dart';
import '../data/mock.dart';
import '../api/update_api.dart';
import '../data/models.dart';
import '../net/net.dart';
import '../platform/credentials.dart';
import '../platform/login/netease_login.dart';
import '../platform/login/kugou_login.dart';
import '../platform/login/qq_login.dart';
import '../platform/models.dart' show Plat;
import '../platform/prefetch.dart';
import '../platform/registry.dart';
import 'announcements.dart';
import 'cloud.dart';
import 'library_store.dart';
import 'lyric_store.dart';
import 'script_store.dart';
import 'taste.dart';
import 'telemetry.dart';
import 'tokens.dart';

class Settings {
  bool trans = true, roma = false, conv = false, blur = true, glow = true;
  double lfs = 26, ltfs = 15, lgap = 10, loff = 0;
  bool fade = true, autoplay = false, autoOpen = false, keepAwake = true;
  bool smart = true, gradual = true, crossScript = true, crossPlat = true, autoNext = true;
  bool nQ = true, nS = true, nA = false, allowDown = true;
  bool floatLyric = false, floatLock = false, btLyric = true, sbLyric = false;
  double dlConc = 3;
  bool dlCover = true, dlLyric = true, wifiOnly = true, cache = true, vinylSpin = true, haptics = true, pitch = true;
  bool finishSong = true, fadeStop = true, cloudSync = true, autoBackup = true, crash = true, navAutoMin = true, clipDetect = true;
  /// 减少模糊效果：玻璃 / 毛玻璃导航栏等背景模糊（BackdropFilter）改成不透明底色，老机型上明显更流畅。
  bool reduceBlur = false;
  bool reduceMotion = false, standbyAuto = true, autoDowngrade = true, mobileLow = true;
  String onlineQ = 'SQ', dlQ = 'Hi-Res', mode = '列表循环', fontSize = '标准';
}

class AppState extends ChangeNotifier {
  // ---------- 鉴权 ----------
  bool authed = false, agreed = false, seenDisclaimer = false;
  String authPage = 'disclaimer'; // disclaimer | login | register | forgot | versionDisabled

  // ---------- 外观 ----------
  ThemeMode themeMode = ThemeMode.dark;
  int accent = 0;
  String bar = 'liquid', skin = 'spring', bg = 'flow', tone = 'dark', appIcon = 'gold', font = 'system';
  double dim = 45;
  String amWave = 'spring', particle = 'galaxy';
  final homeMods = <MapEntry<String, bool>>[
    const MapEntry('custom', true), const MapEntry('mypl', true), const MapEntry('quick', true),
    const MapEntry('tabs', true), const MapEntry('platrec', true),
  ];
  final set = Settings();

  // ---------- 导航 ----------
  int tab = 0; // 0 发现 1 搜索 2 每日 3 音乐库 4 我的
  bool navMin = false, searchFocus = false;
  int? clipSong; // 剪贴板里识别到的分享口令（歌曲 id）

  // ---------- 播放 ----------
  int cur = 0;
  bool playing = true;
  double vol = .7, speed = 1;
  String mode = 'loop'; // loop | one | shuffle | order
  String quality = 'SQ';
  int timer = 0; // 睡眠定时设定值（分钟）；0 = 未开启
  List<int> queue = List.generate(16, (i) => i);
  String queueName = '深夜城市漫游 · 霓虹与雨';
  final liked = <int>{0, 4, 7, 12, 17};
  final pos = ValueNotifier<double>(31);
  Timer? _clock;
  DateTime _last = DateTime.now();

  // ---------- 内容 ----------
  String plat = 'netease', script = 'auto';
  final platLogin = <String, String>{'netease': '小栗子'};
  final scripts = [...scriptsSeed];
  final myPlaylists = [...myPlaylistsSeed];
  final history = <String>['夜航星图', '雾港', 'Lo-fi', '玻璃海'];
  final disliked = <int>{};
  bool loading = false;
  String homeTab = '精选', libSeg = '我喜欢';
  int myPlSeg = 0;
  final crossOrder = <String>['qq', 'kugou', 'kuwo', 'migu'];
  final scriptOrder = <String, List<String>>{};
  List<double> eq = [...eqPresets['流行']!];
  String eqPreset = '流行';
  bool eqOn = true;
  bool autoPopups = true; // 进入主界面时自动弹出未读的弹窗公告（测试 / 截图时关闭）
  late final anns = Announcements(net, notifyListeners);

  /// 云同步 / 云备份 / 听歌统计。
  late final cloud = Cloud(this);

  /// 埋点（演示模式不上报）。
  late final telemetry = Telemetry(net);

  /// 本机音乐库（联网模式）：我喜欢、歌单、搜索历史，持久化并参与云同步。
  late final library = LibraryStore(this, net?.prefs);

  /// 当前歌曲的真实歌词（联网模式）。
  late final lyricStore = LyricStore(this);

  /// 关注的歌手、不感兴趣的歌（本机）。
  late final taste = TasteStore(net?.prefs, notifyListeners);

  /// 导入的音源脚本（联网模式），持久化并可经 lx_sources 云同步。
  late final sources = ScriptStore(this, net?.prefs);

  /// 下载库（联网模式）：已完成清单持久化，进行中在内存；已下载的歌 resolver 离线优先。
  late final downloads = DownloadStore(this, net?.prefs);

  /// 最近一次检查更新的结果；[versionBlock] 非空时整个 App 显示「版本停用」页。
  UpdateCheck? updateInfo, versionBlock;

  /// 启动时检查更新（不需要登录）。失败静默。
  Future<void> checkUpdate() async {
    final n = net;
    if (n == null) return;
    try {
      final r = await UpdateApi(n.client).check();
      updateInfo = r;
      versionBlock = r.versionDisabled ? r : null;
      notifyListeners();
    } on ApiException catch (_) {}
  }

  /// 给用户的一句话提示（main 里接到 toast）。AppState 不直接依赖 UI。
  void Function(String msg, String icon)? notice;
  int get unread => anns.unread;
  bool isRead(Announcement a) => anns.isRead(a);

  /// 网络层。测试 / 截图不传（为 null），页面里通过 [api] 取用。
  final Net? net;
  StreamSubscription<SessionEnd>? _sessionSub;
  StreamSubscription<Json?>? _userSub;
  Net get api => net ?? (throw StateError('AppState 没有注入 Net'));

  /// 是否连着真实后端（false = mock 演示模式：测试、截图）。
  bool get online => net != null;

  /// 真实播放引擎。测试 / 截图不传（为 null），走模拟时钟；页面无感知。
  final AudioEngine? engine;
  double engineDuration = 0; // 引擎返回的实际曲目时长（秒）；0 = 尚未加载

  /// 播放链路解析器：取流记录（播放链路页）与投放取流的入口。与引擎共用同一实例。
  final MusicResolver? resolver;

  /// DLNA 投放控制器。测试 / 截图为 null；有 resolver 即创建。
  CastController? cast;
  String? castDev; // 当前投放到的设备名（null = 未投放，本地播放）

  /// 是否正在投放（声音走 DLNA 渲染端，本地引擎暂停）。
  bool get casting => cast?.connected == true;
  bool _suppressEnginePlaying = false; // 投放接管期间忽略本地引擎的播放态回调


  /// 歌词列表内容版本：换歌写入新词时 +1。歌词视图据此重建布局缓存，
  /// 防止旧歌的 tops/hs 布局数组被新歌词按旧长度索引（RangeError 崩溃）。
  int lyricsVersion = 0;

  /// 播放链路错误出口（气泡提示等），由 main.dart 注入；state 不直接依赖 UI。
  void Function(String message)? onEngineError;

  /// 引擎已加载音源，进度 / 时长 / 播放态以引擎为准。
  bool get engineActive => engine != null && engine!.loaded;

  /// 当前登录的 Lyra 账号；未登录或 mock 模式下为 null。
  Account? account;

  /// 赞助用户才能用云同步 / 云备份 / 云端统计。mock 模式下视为已赞助，方便演示。
  bool get isSponsor => net == null || (account?.isSponsor ?? false);

  /// 各音乐平台的公开内容（发现页、搜索、歌单 / 榜单详情）。测试可以注入假平台。
  final PlatformHub content;

  /// 平台登录凭证（网易云 / QQ / 酷狗），存系统钥匙串，只留在本机。
  /// 登录层写入，直链层等只经 [CredentialStore] 接口读。测试 / 演示模式只在内存里。
  late final platCreds = PlatformCredentials(net?.store);

  /// 平台登录流程（网易云扫码 / Cookie，QQ Cookie）。
  late final neteaseLogin = NeteaseLogin(content.http);
  late final qqLogin = QqLogin(content.http);
  late final kugouLogin = KugouLogin(content.http);

  /// 有登录入口的平台（App 平台 id）。酷我 / 咪咕没有账号体系。
  static const loginPlatforms = {'netease', 'qq', 'kugou'};

  /// 启动时读完凭证后调用：同步「已登录」显示，并在后台准备网易云游客 Cookie。
  Future<void> initPlatformLogin() async {
    await platCreds.load();
    _platSub ??= platCreds.changes.listen((_) => _syncPlatLogin());
    _syncPlatLogin();
    if (online && platCreds.anonymousCookie(Plat.wy) == null) {
      // 后台取，不挡启动；游客 Cookie 只是锦上添花，失败不提示，下次启动再试
      unawaited(neteaseLogin.anonymousCookie().then((c) => platCreds.saveAnonymous(Plat.wy, c), onError: (Object _) {}));
    }
  }

  StreamSubscription<String>? _platSub;

  /// 联网模式：「已登录」显示（platLogin）以凭证为准；被标记失效的不算已登录。
  void _syncPlatLogin() {
    if (!online) return;
    platLogin
      ..clear()
      ..addAll({
        for (final c in platCreds.all)
          if (platCreds.of(c.platform) != null) Plat.toAppId[c.platform] ?? c.platform: (c.nickname?.isNotEmpty ?? false) ? c.nickname! : '已登录',
      });
    notifyListeners();
  }

  /// 平台登录成功：保存凭证（钥匙串）。
  Future<void> savePlatformLogin(PlatformCredential c) => platCreds.save(c);

  /// 空闲时预载其他平台的发现页（只在 Wi-Fi 下）。
  late final prefetch = IdlePrefetch(content);

  AppState({this.net, this.engine, this.resolver, PlatformHub? content}) : content = content ?? PlatformHub() {
    _sessionSub = net?.session.onEnd.listen(sessionEnded);
    _userSub = net?.session.onUser.listen((u) {
      if (u == null) return;
      account = Account.fromJson(u);
      notifyListeners();
    });
    if (net != null) _enterRealMode();
    for (final p in platforms) {
      scriptOrder[p.id] = scripts.where((s) => s.platforms.contains(p.id)).map((s) => s.id).toList();
    }
    _clock = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    pos.addListener(_posClock.reset); // 每次有新的进度上报，平滑位置从这里重新起算
    if (resolver != null) cast = CastController(); // 投放依赖 resolver 取流
    _bindEngine();
    _bindCast();
  }

  // ---------- 音频引擎（真实播放；测试 / 截图为 null，走模拟时钟） ----------
  void _bindEngine() {
    final e = engine;
    if (e == null) return;
    e.onPosition = (p) => pos.value = p;
    e.onDuration = (d) {
      if (engineDuration != d) update(() => engineDuration = d); // song getter 的实际时长变了
    };
    e.onPlaying = (p) {
      if (_suppressEnginePlaying) return; // 投放接管窗口：本地引擎的暂停不回写 UI
      if (playing != p) update(() => playing = p); // 通知栏 / 线控改的状态同步回 UI
    };
    e.onCompleted = _onEngineCompleted; // 单曲循环由引擎 LoopMode.one 自循环，不会走到这
    e.onNotice = (msg) => notice?.call(msg, 'refresh'); // 自动换源 / 重新取链的提示
    e.setFade(set.fade); // 淡入淡出开关联动引擎
    e.onError = (msg) {
      // 解析 / 加载失败：界面回到暂停态并提示原因
      if (playing) update(() => playing = false);
      notice?.call(msg, 'info');
      onEngineError?.call(msg);
    };
    e.onMediaAction = (a) {
      // 通知栏按钮 / 耳机线控 / 蓝牙控制统一路由
      switch (a) {
        case 'play':
          if (!playing) toggle();
        case 'pause':
          if (playing) toggle();
        case 'next':
          next();
        case 'prev':
          prev();
        case 'like':
          update(() => toggleLike(cur));
      }
    };
  }

  /// 投放控制器回调：进度 / 时长复用引擎通道（播放器 UI 无感知），播完走同一套切歌逻辑。
  void _bindCast() {
    final c = cast;
    if (c == null) return;
    c.onPosition = (p) => pos.value = p;
    c.onDuration = (d) {
      if (engineDuration != d) update(() => engineDuration = d);
    };
    c.onPlaying = (p) {
      if (playing != p) update(() => playing = p);
    };
    c.onEnded = () {
      // 单曲循环：重投当前曲目；其余走引擎播完的同一入口（睡眠定时 / 切歌）
      if (mode == 'one' && casting) {
        unawaited(_castPlayCurrent());
      } else {
        _onEngineCompleted();
      }
    };
    c.onError = (msg) {
      if (playing) update(() => playing = false);
      notice?.call(msg, 'info');
    };
  }

  /// 投放当前曲目（播放器 / 投放面板入口）：同一 resolver 取流，地址交给渲染端拉流。
  /// 本地引擎暂停并卸载（断开投放后按播放键会重新加载队列当前曲目）。
  Future<void> castPlayCurrent() => _castPlayCurrent();

  Future<void> _castPlayCurrent() async {
    final c = cast, r = resolver;
    if (c == null || r == null || !hasSong) return;
    final autoplay = playing;
    try {
      final rp = await r.resolve(songs[cur]);
      if (rp == null) return;
      if (!casting) return; // 等待解析期间用户断开了投放
      _suppressEnginePlaying = true; // 本地引擎让位：暂停 / 卸载产生的回调不回写 UI
      if (engineActive) await engine!.setPlaying(false);
      await engine?.unload(); // 通知栏同步清空；断开投放后按播放键重载当前队列曲目
      await c.cast(songs[cur], rp.uri, autoplay: autoplay);
      _suppressEnginePlaying = false;
    } on ResolveException catch (e) {
      _suppressEnginePlaying = false;
      if (playing) update(() => playing = false);
      notice?.call(e.message, 'info');
    } on CastException catch (e) {
      _suppressEnginePlaying = false;
      if (playing) update(() => playing = false);
      notice?.call('投放失败：${e.message}', 'info');
    }
  }

  /// 边听边缓存：开关 + 缓存目录下发引擎（settings 切换与启动时调用）。
  String? _streamCacheDir;

  Future<void> applyCacheToEngine() async {
    final e = engine;
    if (e == null) return;
    String? dir;
    if (set.cache) {
      try {
        final d = await getTemporaryDirectory();
        dir = '${d.path}${io.Platform.pathSeparator}stream-cache';
        await io.Directory(dir).create(recursive: true);
        _streamCacheDir = dir;
      } catch (_) {
        dir = null; // 目录不可用：本次会话退回直连
      }
    }
    await e.setCache(enabled: set.cache, dir: dir);
  }

  /// 淡入淡出开关下发引擎（settings 切换时调用；启动由 _bindEngine 收尾处理）。
  void applyFadeToEngine() => engine?.setFade(set.fade);

  /// 「启动时自动播放」：恢复上次播放的歌并直接开播（脚本未就绪 / 无歌时静默跳过）。
  Future<void> autoplayLast() async {
    if (!online || engine == null || !set.autoplay || hasSong) return;
    // 存的是曲目 key（歌曲 id 是本次启动登记的顺序号，跨启动不稳定）
    final key = await net?.prefs.read('last.song.v1') ?? '';
    final id = key.isEmpty ? null : library.idOfKey(key);
    if (id == null || id >= songs.length) return;
    if (sources.forPlayback().isEmpty) return;
    play(id, ids: [id]);
  }

  /// 引擎加载完成后的收尾：套用速度 / 音调并刷新通知栏（带真实收藏态）。
  void _engineAfterLoad() {
    final e = engine!;
    if (!e.loaded) return;
    _restoreSleepVolume(); // 淡出中用户切了歌：恢复音量，淡出窗口由 _sleepTick 重新进入
    unawaited(e.setVolume(vol));
    applySpeedToEngine();
    if (e.playingNow != playing) unawaited(e.setPlaying(playing)); // 加载期间用户可能已按暂停/切歌
    e.updateNotification(playing: playing, liked: liked.contains(cur));
  }

  /// 引擎播完一首：睡眠定时「播完当前歌曲再停」挂起时到点停播，否则切下一首。
  void _onEngineCompleted() {
    if (_stopAfterSong) {
      unawaited(_sleepStop());
      return;
    }
    _step(1);
  }

  /// 把倍速 / 音调开关同步到正在播放的引擎（改倍速立即生效，不用等下一首）；
  /// 引擎加载完成后的收尾（_engineAfterLoad）也会走这里，保证换歌后速度不丢。
  /// 「保持音调」开启（默认）时音高不变；关闭时让音高跟随倍速。
  void applySpeedToEngine() {
    if (!engineActive) return;
    unawaited(engine!.setSpeed(speed));
    unawaited(engine!.setPitch(set.pitch ? 1.0 : speed));
  }

  /// 把 UI 均衡器（10 段曲线 + 开关）下发到设备 EQ；非 Android 平台引擎内部静默跳过。
  void applyEqToEngine() {
    if (engineActive) unawaited(engine!.applyEq(eqOn, eq));
  }

  // ---------- 睡眠定时 ----------

  DateTime? _sleepEnd;
  Timer? _sleepT;
  bool _stopAfterSong = false; // 「播完当前歌曲再停」：到点时若在播放，挂到引擎 completed
  bool _sleepFading = false; // 「停止前 30 秒淡出」进行中（音量正按剩余秒线性降低）
  double? _sleepVolBase; // 淡出前的用户音量，停止 / 取消后恢复

  /// 睡眠定时剩余秒数（未开启为 0）。
  int get sleepLeft {
    final e = _sleepEnd;
    if (e == null) return 0;
    final left = e.difference(DateTime.now()).inSeconds;
    return left <= 0 ? 0 : left;
  }

  /// 设置睡眠定时（分钟；0 = 取消）。到点后按「播完当前歌曲再停」
  /// 与「停止前 30 秒淡出」两个开关执行；开启时若在播放立即生效。
  void setSleepTimer(int minutes) {
    _sleepT?.cancel();
    _sleepT = null;
    _stopAfterSong = false;
    _restoreSleepVolume();
    if (minutes <= 0) {
      _sleepEnd = null;
      timer = 0;
      notifyListeners();
      return;
    }
    timer = minutes;
    _sleepEnd = DateTime.now().add(Duration(minutes: minutes));
    _sleepT = Timer.periodic(const Duration(seconds: 1), (_) => _sleepTick());
    notifyListeners();
  }

  void _sleepTick() {
    final left = sleepLeft;
    if (left <= 0) {
      // 时间到：在播且开了「播完当前歌」就挂到曲末，否则立即停止。
      _sleepT?.cancel();
      _sleepT = null;
      if (playing && set.finishSong) {
        // 等这首播完再停：先把淡出压低的音量恢复，否则剩下的部分会静音播完
        _restoreSleepVolume();
        _stopAfterSong = true;
        return;
      }
      unawaited(_sleepStop());
      return;
    }
    // 淡出期间用户暂停了就先把音量恢复回来，别把静音留在下一首。
    if (_sleepFading && !playing) _restoreSleepVolume();
    // 停止前 30 秒淡出：引擎音量随剩余秒线性降到 0（不动用户设置的 vol）。
    if (set.fadeStop && playing && left <= 30) {
      if (!_sleepFading) {
        _sleepFading = true;
        _sleepVolBase = vol;
        notifyListeners();
      }
      if (engineActive) unawaited(engine!.setVolume(vol * left / 30));
    }
    // 剩余分钟跨过整分（以及最后 5 秒）时刷新一次界面上的剩余显示。
    if (left % 60 == 0 || left <= 5) notifyListeners();
  }

  /// 到点停止播放：淡出收尾（如在进行中）→ 暂停 → 恢复音量 → 提示。
  Future<void> _sleepStop() async {
    _stopAfterSong = false;
    _sleepEnd = null;
    _sleepT?.cancel();
    _sleepT = null;
    if (engineActive && _sleepFading && playing) {
      final e = engine!;
      for (var i = 1; i <= 10; i++) {
        await e.setVolume((_sleepVolBase ?? vol) * (1 - i / 10));
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    _restoreSleepVolume();
    timer = 0;
    if (playing) update(() => playing = false);
    if (engine != null) unawaited(engine!.setPlaying(false));
    if (engineActive) engine!.updateNotification(playing: false, liked: liked.contains(cur));
    notice?.call('睡眠定时时间到，已停止播放', 'moon');
  }

  void _restoreSleepVolume() {
    if (_sleepFading) {
      _sleepFading = false;
      if (engineActive) unawaited(engine!.setVolume(vol));
    }
    _sleepVolBase = null;
  }

  /// 播放器音量条（0..1，相对系统音量）。睡眠淡出进行中时只记下新值，淡出结束后生效。
  void setVolume(double v) {
    vol = v.clamp(0.0, 1.0);
    if (engineActive && !_sleepFading) unawaited(engine!.setVolume(vol));
    notifyListeners();
  }

  // ---------- 口味 ----------

  /// 被标记为不感兴趣（本次会话的 id，或本机记录的曲目 key）。
  bool isDisliked(int id) {
    if (disliked.contains(id)) return true;
    final k = id >= 0 && id < songs.length ? songs[id].key : null;
    return k != null && taste.disliked.contains(k);
  }

  /// 不感兴趣：记下来（电台以后不再放），并从当前队列里拿掉；正在放的就切下一首。
  void dislike(int id) {
    disliked.add(id);
    final k = id >= 0 && id < songs.length ? songs[id].key : null;
    if (k != null) taste.dislike(k);
    if (id == cur && queue.length > 1) {
      _step(1, notify: false);
      queue.remove(id);
    } else if (id != cur) {
      queue.remove(id);
    }
    notifyListeners();
  }

  // ---------- 缓存 ----------

  /// 内存里的图片缓存大小（字节）。列表 / 歌词等数据缓存没有可靠的大小，不计入。
  int get imageCacheBytes => PaintingBinding.instance.imageCache.currentSizeBytes;

  /// 清除缓存：图片、平台列表 / 详情 / 歌词、接口缓存。返回清掉的图片字节数。
  int clearCaches() {
    final bytes = imageCacheBytes;
    final ic = PaintingBinding.instance.imageCache;
    ic.clear();
    ic.clearLiveImages();
    content.invalidate();
    lyricStore.clear();
    net?.client.clearCache();
    final dir = _streamCacheDir;
    if (dir != null) {
      // 边听边缓存的音频文件；正在播放的那个可能被占用，删不掉就留着
      unawaited(io.Directory(dir).list().forEach((f) async {
        try {
          await f.delete();
        } catch (_) {}
      }).catchError((Object _) {}));
    }
    notifyListeners();
    return bytes;
  }

  /// 加载当前曲目到引擎（engineActive 时才调）。
  void _enginePlayCurrent() {
    if (online) lyricStore.load(cur);
    unawaited(engine!.playSong(songs[cur], autoplay: playing, loopOne: mode == 'one').then((_) => _engineAfterLoad()));
  }

  // ---------- 派生 ----------
  Pal pal(Brightness platformBrightness) {
    final dark = themeMode == ThemeMode.system ? platformBrightness == Brightness.dark : themeMode == ThemeMode.dark;
    return Pal.of(dark, accents[accent]);
  }

  /// 联网模式：清掉所有 mock 内容，从空的本机数据开始（音乐库、歌单、脚本、平台登录、播放队列）。
  /// 全局 `songs` 变成真实歌曲目录（见 [LibraryStore]）。
  void _enterRealMode() {
    songs.clear();
    lyrics.clear();
    lyricsVersion++; // 歌词视图的布局缓存失效
    queue = [];
    queueName = '';
    cur = -1;
    playing = false;
    pos.value = 0;
    vol = 1; // 真实播放：音量条默认满格（相对系统音量）
    liked.clear();
    myPlaylists.clear();
    scripts.clear();
    history.clear();
    platLogin.clear();
    clipSong = null;
  }

  /// 有没有正在播放 / 暂停中的歌。没有时迷你播放条隐藏、播放器打不开。
  bool get hasSong => cur >= 0 && cur < songs.length;

  /// 当前歌曲；没有时返回占位（只用于预览，不会出现在列表里）。
  /// 真实播放：用引擎返回的实际时长替换 mock 时长，进度条 / 歌词换算才不会越界。
  Song get song {
    final s = hasSong ? songs[cur] : Song.placeholder;
    final d = engineDuration.round();
    if (engineActive && d > 0 && d != s.dur) return s.copyWith(dur: d);
    return s;
  }

  Song songById(int id) => id >= 0 && id < songs.length ? songs[id] : Song.placeholder;

  /// 能不能真正播放。联网模式下音源解析（脚本运行时 / 平台取流）还没接入，先拦下来并提示，
  /// 不再用计时器假装在播放。
  bool get canPlay => !online || (engine != null && sources.sources.isNotEmpty);
  bool _blockPlay() {
    if (canPlay) return false;
    notice?.call(engine == null ? '当前环境不支持播放' : '还没有导入音源脚本：在「设置 → 平台与解析脚本」导入后就能播放', 'info');
    return true;
  }

  /// 给 [Cloud] 等协作对象用的 notifyListeners。
  void notify() => notifyListeners();

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (net != null) {
      cloud.onAppChanged(); // 设置变了 → 防抖推送
      cloud.evaluate(); // 登录 / 会员 / 开关变了 → 开关实时同步
    }
  }
  Platform get platform => platformBy(plat);
  bool isIn(String pid) => platLogin.containsKey(pid);
  List<Script> scriptsOf(String pid) {
    final order = scriptOrder[pid] ?? [];
    final l = scripts.where((s) => s.platforms.contains(pid)).toList();
    l.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    return l;
  }

  ({String name, int ms, int ok}) get curScript {
    if (script == 'auto') {
      final l = scriptsOf(plat);
      return (name: '自动选择', ms: l.isEmpty ? 0 : l.first.ms, ok: 99);
    }
    final s = scripts.where((x) => x.id == script).firstOrNull ?? scripts.firstOrNull;
    if (s == null) return (name: '自动选择', ms: 0, ok: 0);
    return (name: s.name, ms: s.ms, ok: s.ok);
  }

  /// 平滑的播放位置：引擎大约每 200ms 才报一次进度，逐帧动画（歌词填充）在两次上报之间
  /// 按经过的时间 × 倍速往前推，最多推 0.6 秒（防止卡顿 / 缓冲时跑过头）。
  double get smoothPos {
    final p = pos.value;
    if (!playing || !hasSong && online) return p;
    final dt = math.min(_posClock.elapsedMicroseconds / 1e6, 0.6);
    return p + dt * speed;
  }

  final _posClock = Stopwatch()..start();

  int get lyricIndex => lyricIndexAt(smoothPos + set.loff);

  int lyricIndexAt(double p) {
    var k = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].t <= p) k = i;
    }
    return k;
  }

  /// 当前行内进度 0..1：有逐字时间按字走，否则按估算的演唱时长插值（见 [LyricLine.progressAt]）。
  double get lineProgress {
    if (lyrics.isEmpty) return 0;
    final p = smoothPos + set.loff;
    final k = lyricIndexAt(p);
    if (k >= lyrics.length) return 0;
    return lyrics[k].progressAt(p);
  }

  /// 模拟节拍包络 0..1（112 BPM）。
  double beat([double? at]) {
    final t = at ?? pos.value;
    final ph = (t * 112 / 60) % 1;
    return math.pow(1 - ph, 3).toDouble();
  }

  List<int> listOf(String k) {
    if (online) {
      // 联网模式：只有真实数据。热门 / 每日推荐 / 本地音乐要等平台和本地扫描接入
      return switch (k) { 'like' => liked.toList(), 'hot' || 'daily' || 'local' => <int>[], _ => List.generate(songs.length, (i) => i) };
    }
    switch (k) {
      case 'hot':
        return [0, 2, 4, 5, 17, 7, 11, 16, 14, 12];
      case 'daily':
        final l = List.generate(songs.length, (i) => i)..sort((a, b) => ((a * 37 + 11) % 24).compareTo((b * 37 + 11) % 24));
        return l.where((i) => !disliked.contains(i)).toList();
      case 'like':
        return liked.toList();
      case 'local':
        final l = [...songs]..sort((a, b) => a.title.compareTo(b.title));
        return l.map((s) => s.id).toList();
      default:
        return List.generate(songs.length, (i) => i);
    }
  }

  // ---------- 播放控制 ----------
  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (!playing || !hasSong) return;
    cloud.onPlayTick(cur, dt);
    if (engineActive) return; // 真实进度由引擎回调驱动，这里只负责听歌统计
    var p = pos.value + dt * speed;
    if (p >= song.dur) {
      if (mode == 'one') {
        p = 0;
      } else {
        _step(1, notify: true);
        return;
      }
    }
    pos.value = p;
  }

  /// [ids]：明确的播放队列（平台歌单 / 榜单 / 搜索结果）；不给时按 [list] 取。
  void play(int id, {String? list, String? name, List<int>? ids}) {
    if (_blockPlay()) return;
    if (ids != null) {
      queue = [...ids];
      if (name != null) queueName = name;
    } else if (list != null) {
      queue = listOf(list);
      if (name != null) queueName = name;
    }
    if (!queue.contains(id)) queue.insert(math.min(queue.indexOf(cur) + 1, queue.length), id);
    cur = id;
    pos.value = 0;
    engineDuration = 0;
    playing = true;
    final lastKey = songs[id].key;
    if (lastKey != null) unawaited(net?.prefs.write('last.song.v1', lastKey)); // 「启动时自动播放」恢复用
    notifyListeners();
    if (casting) {
      unawaited(_castPlayCurrent()); // 投放中：解析后交给渲染端播放
    } else if (engine != null) {
      _enginePlayCurrent(); // 引擎存在即下发：engineActive 门控会让第一首歌永远无法加载
    }
  }

  void playAll(String list, {bool shuffle = false, String? name}) {
    if (_blockPlay()) return;
    queue = listOf(list);
    if (shuffle) queue.shuffle(math.Random(7));
    if (name != null) queueName = name;
    if (queue.isEmpty) return;
    cur = queue.first;
    pos.value = 0;
    engineDuration = 0;
    playing = true;
    if (shuffle) mode = 'shuffle';
    notifyListeners();
    if (casting) {
      unawaited(_castPlayCurrent());
    } else if (engine != null) {
      _enginePlayCurrent(); // 同 play()：不能以「尚未加载」为由拒绝第一次加载
    }
  }

  void toggle() {
    if (!hasSong) return;
    playing = !playing;
    notifyListeners();
    if (casting) {
      unawaited(cast!.setPlaying(playing));
      return;
    }
    if (engine == null) return;
    if (engineActive) {
      unawaited(engine!.setPlaying(playing));
      // 通知栏 / 线控 / 蓝牙的键路由依据 playbackState.playing；不刷新的话
      // audio_service 会与真实状态脱节（实测 PLAY 键被当 pause 处理、按钮图标不切换）
      engine!.updateNotification(playing: playing, liked: liked.contains(cur));
    } else if (playing) {
      _enginePlayCurrent(); // 引擎还没加载过任何曲目：按播放 = 从当前歌开始真实播放
    }
  }

  void next() => _step(1);
  void prev() {
    if (pos.value > 3) {
      if (casting) {
        unawaited(cast!.seek(0)); // 投放中：渲染端回到曲目开头
      } else if (engineActive) {
        engine!.seek(0); // 真实播放：回到曲目开头（进度由引擎回调刷新）
      } else {
        pos.value = 0;
      }
      notifyListeners();
      return;
    }
    _step(-1);
  }

  void _step(int d, {bool notify = true}) {
    if (queue.isEmpty) return;
    final i = queue.indexOf(cur);
    if (mode == 'shuffle') {
      cur = queue[(i + 3 + math.Random().nextInt(math.max(1, queue.length - 2))) % queue.length];
    } else {
      cur = queue[(i + d + queue.length) % queue.length];
    }
    pos.value = 0;
    engineDuration = 0;
    if (casting) {
      unawaited(_castPlayCurrent()); // 单曲循环时投放端自循环，不会走到这
    } else if (engine != null) {
      _enginePlayCurrent(); // 单曲循环时引擎自循环，不会走到这
    }
    if (notify) notifyListeners();
  }

  void seek(double sec) {
    if (!hasSong) return;
    final d = song.dur.toDouble();
    if (casting) {
      unawaited(cast!.seek(sec.clamp(0, d))); // 进度由投放轮询刷新
      return;
    }
    if (engineActive) {
      unawaited(engine!.seek(sec.clamp(0, d))); // 进度由引擎回调刷新
      return;
    }
    pos.value = sec.clamp(0, d);
  }

  void cycleMode() {
    const order = ['loop', 'one', 'shuffle', 'order'];
    mode = order[(order.indexOf(mode) + 1) % order.length];
    if (engineActive) unawaited(engine!.setLoopOne(mode == 'one'));
    notifyListeners();
  }

  String get modeName => const {'loop': '列表循环', 'one': '单曲循环', 'shuffle': '随机播放', 'order': '顺序播放'}[mode]!;

  bool toggleLike(int id) {
    final on = !liked.contains(id);
    on ? liked.add(id) : liked.remove(id);
    notifyListeners();
    if (online) library.favoritesChanged();
    // 通知栏收藏按钮图标跟随收藏态
    if (engineActive && id == cur) engine!.updateNotification(playing: playing, liked: on);
    return on;
  }

  void playNext(int id) {
    if (_blockPlay()) return;
    queue.remove(id);
    queue.insert(math.min(queue.indexOf(cur) + 1, queue.length), id);
    notifyListeners();
  }

  void reorderQueue(int from, int to) {
    final id = queue.removeAt(from);
    queue.insert(to > from ? to - 1 : to, id);
    notifyListeners();
  }

  // ---------- 通用修改 ----------
  void update(VoidCallback f) {
    f();
    notifyListeners();
  }

  Future<void> switchPlatform(String id) async {
    if (id == plat) return;
    plat = id;
    script = 'auto';
    loading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 750));
    loading = false;
    notifyListeners();
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 750));
    loading = false;
    notifyListeners();
  }

  void moveHomeMod(int from, int to) {
    final e = homeMods.removeAt(from);
    homeMods.insert(to, e);
    notifyListeners();
  }

  bool homeOn(String k) => homeMods.firstWhere((e) => e.key == k).value;
  void setHomeMod(String k, bool v) {
    final i = homeMods.indexWhere((e) => e.key == k);
    homeMods[i] = MapEntry(k, v);
    notifyListeners();
  }

  void login(String pid, String name) {
    platLogin[pid] = name;
    notifyListeners();
  }

  void logout(String pid) {
    platLogin.remove(pid);
    notifyListeners();
    if (online) unawaited(platCreds.remove(pid)); // 联网模式：删掉钥匙串里的凭证
  }

  // ---------- Lyra 账号会话 ----------
  /// 启动时本地有令牌：直接进主界面（用缓存的账号信息），后台刷新一次令牌。
  /// 刷新令牌失效 → [sessionEnded] 回登录页；断网 → 保持离线登录状态。
  void restoreSession() {
    final n = net;
    if (n == null || !n.session.isLoggedIn) return;
    account = n.auth.cached;
    authed = true;
    agreed = seenDisclaimer = true;
    if (authPage == 'disclaimer') authPage = 'login';
    notifyListeners();
    unawaited(n.auth.resume());
  }

  /// 登录 / 注册成功。
  void signedIn(Account a) {
    account = a;
    authed = true;
    notifyListeners();
  }

  /// 退出登录：通知服务端作废刷新令牌，本地清掉会话（经 [sessionEnded] 回登录页）。
  Future<void> signOut() async {
    final n = net;
    if (n == null) {
      authed = false;
      authPage = 'login';
      notifyListeners();
      return;
    }
    await n.auth.logout();
  }

  /// 会话结束（主动退出或令牌失效）→ 回到登录页。失效提示由 main.dart 弹出。
  void sessionEnded(SessionEnd reason) {
    account = null;
    unawaited(anns.reset());
    unawaited(cloud.reset());
    if (online) unawaited(library.reset());
    if (!authed) return notifyListeners();
    authed = false;
    authPage = 'login';
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _userSub?.cancel();
    anns.dispose();
    cloud.dispose();
    telemetry.dispose();
    library.dispose();
    _clock?.cancel();
    _sleepT?.cancel();
    prefetch.stop();
    _platSub?.cancel();
    platCreds.dispose();
    pos.dispose();
    super.dispose();
  }
}

/// 让任意子树拿到 AppState，并在其变化时重建。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// 配色作用域：播放器、深色 Sheet 用 [Pal.forceDark] 覆盖。
class PalScope extends InheritedWidget {
  final Pal pal;
  const PalScope({super.key, required this.pal, required super.child});
  @override
  bool updateShouldNotify(PalScope old) => old.pal.dark != pal.dark || old.pal.accent != pal.accent;
}

extension Ctx on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
  Pal get pal => dependOnInheritedWidgetOfExactType<PalScope>()!.pal;
}
