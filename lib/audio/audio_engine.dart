// 真实播放引擎：封装 just_audio（Android=Media3/ExoPlayer，iOS=AVPlayer）+ 音频焦点 + 均衡器 + 媒体通知。
//
// 使用规则（与 AppState 的约定）：
// - 测试 / 截图（无平台通道）不创建引擎，AppState 走模拟时钟；
// - 引擎模式下 AppState 的 pos / playing / 时长全部由本引擎的回调驱动；
// - 队列逻辑（下一首是谁）仍归 AppState，引擎只负责「把给定的曲目播出来」。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import '../core/app_log.dart';
import '../source/failure.dart';
import 'equalizer.dart';
import 'formats.dart';
import 'media_handler.dart';
import 'track_resolver.dart';

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class AudioEngine {
  AudioEngine({required TrackResolver resolver}) : _resolver = resolver;

  final TrackResolver _resolver;
  // EQ 只在 Android 有系统实现；iOS/Web 静默跳过（见 docs/audio/README.md 限制一节）
  static final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AudioPlayer _player = AudioPlayer(
    // 均衡器只挂在 Android 上：iOS 的 just_audio 没有 androidEqualizer* 方法，挂上后每次加载音源都会去取
    // 均衡器参数，抛 MissingPluginException，导致所有歌都「播放失败」。
    audioPipeline: AudioPipeline(androidAudioEffects: _isAndroid ? [_equalizer] : const []),
    // 带请求头的音源（云盘 Basic 认证、直链 Referer）不走 just_audio 的本机代理（127.0.0.1）：
    // Android 上 ExoPlayer 原生支持请求头；代理按「路径?查询」查表，查不到直接崩，请求根本出不去。
    useProxyForRequestHeaders: false,
  );
  LyraMediaHandler? _handler;
  final List<StreamSubscription<dynamic>> _subs = [];

  Song? _current;
  bool _loaded = false;
  int _seq = 0;
  bool _cacheOn = false; // 边听边缓存：LockCachingAudioSource 边播边落盘
  String? _cacheDir;
  bool _fade = false; // 暂停 / 恢复的音量淡入淡出
  bool _eqOn = false;
  List<double> _eqCurve = List.filled(10, 0);

  /// 是否已加载可播放音源（决定 AppState 用真实进度还是模拟时钟）。
  bool get loaded => _loaded;

  /// 引擎此刻的真实播放态（加载期间的 UI 竞态以它为准对齐）。
  bool get playingNow => _player.playing;
  Song? get current => _current;

  // —— 状态回调（AppState 订阅；全部可空，按需挂） ——
  void Function(double seconds)? onPosition;
  void Function(double seconds)? onDuration;
  void Function(bool playing)? onPlaying;
  void Function()? onCompleted;
  void Function(String message)? onError;

  /// 自动补救（换音源 / 重新取链）时给用户的提示。
  void Function(String message)? onNotice;

  /// 媒体通知 / 耳机线控的动作（play/pause/next/prev/like），由 AppState 路由。
  void Function(String action)? onMediaAction;

  /// 通知栏 / 锁屏 / 蓝牙拖进度（秒）。挂了就由 AppState 处理，不挂时直接拖本地播放器。
  void Function(double seconds)? onSeekRequest;

  /// 投放中手机音量键：设到某个值 / 加减一档。
  void Function(int volume)? onRemoteVolume;
  void Function(int direction)? onRemoteAdjust;

  /// 初始化：音频焦点 + 通知通道。必须在 runApp 之前调用（audio_service 的要求）。
  /// [handler] 由 main.dart 先行创建并传入。
  Future<void> init(LyraMediaHandler handler) async {
    _handler = handler;
    _handler!.onAction = (a) => onMediaAction?.call(a);
    // 通知栏 / 锁屏拖进度条（原来 seek 没有实现，拖了会弹回去）
    // 交给 AppState 时它会按投放 / 本地分流（投放中本地引擎没加载，原来拖了没反应）
    _handler!.onSeekTo = (p) {
      final r = onSeekRequest;
      if (r != null) {
        r(p.inMilliseconds / 1000);
      } else if (_loaded) {
        unawaited(_player.seek(p));
      }
    };
    _handler!.onRemoteVolume = (v) => onRemoteVolume?.call(v);
    _handler!.onRemoteAdjust = (d) => onRemoteAdjust?.call(d);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 音频焦点打断（来电 / 导航播报 / 其它应用）：just_audio 默认就处理（handleInterruptions: true），
    // 暂时性打断结束后自动恢复，永久失去焦点（别的音乐 App 开始放）不恢复。这里不再重复监听。

    _subs.addAll([
      _player.positionStream.listen((p) {
        onPosition?.call(p.inMicroseconds / 1e6);
        _watchPosition(p);
      }),
      _player.durationStream.listen((d) {
        if (d != null) onDuration?.call(d.inMicroseconds / 1e6);
      }),
      // 切歌时 stop() 会先发一次 playing=false：那不是用户暂停，不转给 AppState，
      // 否则 AppState 以为暂停了，加载完又把刚开始播的歌暂停掉（「下一曲不自动播放 / 播几秒自己停」）
      _player.playingStream.listen((p) {
        if (!_loaded) return;
        onPlaying?.call(p);
      }),
      _player.processingStateStream.listen((s) {
        if (s != _lastState) AppLog.instance.add('播放', '状态 ${_lastState?.name ?? '-'} → ${s.name}${_loaded ? '' : '（加载中）'}');
        _lastState = s;
        if (s == ProcessingState.completed) _completed();
      }),
      // 播放中途出错（链接过期、403、断流）：从当前位置重新取一次地址续播，还不行再报错
      _player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) => _streamError(e)),
    ]);
  }

  /// 加载并（可选）播放一首。解析不到地址 / 格式不支持 / 加载失败都会走 [onError]，
  /// 不抛异常——调用方（AppState）不该为播放失败写 try-catch。
  ///
  /// 自动补救（每首歌各一次）：
  /// - 加载失败（多为 403 / 链接过期）→ 不用缓存重新取地址再试；
  /// - 加载后时长明显短于歌曲时长（< 85%）→ 判定为试听片段，换音源；
  /// - 播放中途出错 → 从当前位置重新取地址续播；
  /// - 没播到歌曲时长的 85% 就结束了 → 判定为试听片段，换音源后从结束处接着播。
  /// [startAt]：从这个位置（秒）开始（恢复上次播放进度用）。
  Future<void> playSong(Song song, {required bool autoplay, required bool loopOne, double? startAt}) async {
    // 解析要几百毫秒到几秒；期间用户可能已经切到别的歌，旧的结果直接丢掉
    final seq = ++_seq;
    _posLogged = false;
    _playSince = null;
    _tried.clear();
    _interruptRetried = false;
    _loopOne = loopOne;
    if (_loaded) {
      _loaded = false;
      // 必须等 stop() 完成：它是异步停用平台播放器，没停完就开始下一首的 setAudioSource，
      // just_audio 会判定为被打断，抛「Loading interrupted」（请求都没发出去）。
      // 平台歌曲解析要几百毫秒，碰巧躲过去了；云盘 / 已下载的歌地址是本地拼的，每次都撞上。
      await _player.stop().catchError((Object _) {});
      if (seq != _seq) return;
    }
    await _load(song, seq, autoplay: autoplay, at: startAt == null || startAt < 1 ? null : Duration(milliseconds: (startAt * 1000).round()));
  }

  /// 本首歌已经用过的补救方式（每种一次，避免来回重试）。
  final _tried = <ResolveReason>{};
  bool _loopOne = false;

  /// 播放时长低于歌曲时长的这个比例，认为是试听片段。
  static const trialRatio = .85;

  bool _shortOf(Song song, Duration? d) => d != null && song.dur >= 30 && d.inMilliseconds > 0 && d.inMilliseconds < song.dur * 1000 * trialRatio;

  Future<void> _load(Song song, int seq, {required bool autoplay, ResolveReason reason = ResolveReason.play, Duration? at, bool ended = false}) async {
    if (reason != ResolveReason.play) _tried.add(reason);
    ResolvedPlay? rp;
    try {
      rp = await _resolver.resolve(song, reason: reason);
    } catch (e) {
      if (seq != _seq) return;
      if (reason == ResolveReason.trial) return _trialFallback(song, seq, autoplay: autoplay, ended: ended, why: _short(e));
      onError?.call('${song.title}：${_short(e)}');
      return;
    }
    if (seq != _seq) return;
    if (rp == null) {
      if (reason == ResolveReason.trial) return _trialFallback(song, seq, autoplay: autoplay, ended: ended);
      onError?.call('无法解析播放地址：${song.title}');
      return;
    }
    if (!isLikelySupported(rp.uri)) {
      onError?.call('暂不支持 ${formatLabel(formatOfUri(rp.uri))} 格式：${song.title}');
      return;
    }
    _current = song;
    try {
      _loaded = false;
      final AudioSource source;
      final cacheKey = song.key ?? rp.uri.toString();
      // 需要请求头的音源不走锁定缓存：缓存源必须经本机代理转发，带头时有已知问题（just_audio #832）
      // iOS 不走锁定缓存：它要经 just_audio 的本机代理转发，代理边下边回、不带完整长度，
      // AVPlayer 拿不到时长（日志「时长 0s」），进度也一直停在 0。iOS 上直接播原地址。
      if (_cacheOn && !_isIOS && rp.headers.isEmpty && reason == ResolveReason.play && _cacheDir != null && _cacheDir!.isNotEmpty && !rp.uri.isScheme('file')) {
        // 边听边缓存：just_audio 的锁定缓存源。文件按歌曲 key 命名（播放地址带时效签名，按地址命名几乎不会命中）；
        // 重新取链 / 试听换源时不走缓存，避免把试听片段或坏链接缓存下来。
        final key = base64Url.encode(utf8.encode(cacheKey)).replaceAll('=', '');
        // ignore: experimental_member_use
        source = LockCachingAudioSource(rp.uri, cacheFile: File('$_cacheDir/$key.audio'), headers: rp.headers);
      } else {
        source = AudioSource.uri(rp.uri, headers: rp.headers);
      }
      final sw = Stopwatch()..start();
      final d = await _player.setAudioSource(source, initialPosition: at);
      if (seq != _seq) return;
      _interruptRetried = false;
      AppLog.instance.add('播放', '加载成功 ${sw.elapsedMilliseconds}ms · ${_describe(rp)}${d == null ? '' : ' · 时长 ${d.inSeconds}s'}');
      if (_shortOf(song, d) && !_tried.contains(ResolveReason.trial)) {
        // 时长明显不对：多半是试听片段，换音源
        _trialUri = rp;
        return await _load(song, seq, autoplay: autoplay, reason: ResolveReason.trial, at: at);
      }
      _loaded = true;
      await _player.setLoopMode(_loopOne ? LoopMode.one : LoopMode.off);
      await applyEq(_eqOn, _eqCurve); // 换源后重新套用 EQ 曲线
      // just_audio 的 play() 返回的 Future 要到播放完成/被打断时才 complete，
      // await 会把 playSong 挂到曲终——通知同步与 AppState 的加载收尾（速度/EQ/收藏态）
      // 全部永远不执行（实测通知栏因此无媒体卡片）。这里只负责启动播放，不等待。
      if (autoplay) unawaited(_player.play());
      _syncNotification(playing: autoplay);
    } catch (e) {
      // 快速切歌时旧加载被新请求打断（「Loading interrupted」）是正常竞态：
      // 已经有更新代际的加载介入时，旧结果静默丢弃，不弹错误也不踩新歌的状态。
      if (seq != _seq) return;
      _loaded = false;
      AppLog.instance.add('播放', '加载失败（${reason.name}）· ${_describe(rp)} · ${_errDetail(e)}');
      // 被打断（不是链接问题）：等一下用同一个地址再加载一次，不算作「重新取链」
      if (e is PlayerInterruptedException && !_interruptRetried) {
        _interruptRetried = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (seq != _seq) return;
        return _load(song, seq, autoplay: autoplay, reason: reason, at: at, ended: ended);
      }
      if (!_tried.contains(ResolveReason.reload)) {
        // 链接可能已过期 / 被拒（403）：不用缓存重新取一次
        return _load(song, seq, autoplay: autoplay, reason: ResolveReason.reload, at: at);
      }
      onError?.call('播放失败：${describePlayError(e)}');
    }
  }

  ProcessingState? _lastState;

  // 进度诊断：每首歌播放 5 秒后记一次进度，进度不走时日志里能看出来（不用再猜）
  DateTime? _playSince;
  bool _posLogged = false;
  void _watchPosition(Duration p) {
    if (!_loaded || !_player.playing) {
      _playSince = null;
      return;
    }
    _playSince ??= DateTime.now();
    if (_posLogged || DateTime.now().difference(_playSince!) < const Duration(seconds: 5)) return;
    _posLogged = true;
    AppLog.instance.add('播放', p.inMilliseconds < 1000 ? '播放 5 秒后进度仍为 ${p.inMilliseconds}ms（引擎没有上报进度）' : '进度正常 ${p.inSeconds}s');
  }

  /// 本首歌是否已经因为「被打断」重试过一次。
  bool _interruptRetried = false;

  /// 日志用：地址只留协议 + 主机 + 扩展名，请求头只列名字（不记认证内容）。
  static String _describe(ResolvedPlay rp) {
    final u = rp.uri;
    final ext = formatOfUri(u);
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}${ext.isEmpty ? '' : ' .$ext'}${rp.headers.isEmpty ? '' : ' · 头 ${rp.headers.keys.join(',')}'}';
  }

  static String _errDetail(Object e) {
    if (e is PlayerException) return 'PlayerException(code=${e.code}, ${e.message})';
    if (e is PlayerInterruptedException) return 'PlayerInterruptedException(${e.message})';
    final s = '$e';
    return s.length > 160 ? s.substring(0, 160) : s;
  }

  /// 被判定为试听的地址（换源失败时退回来播它）。
  ResolvedPlay? _trialUri;

  /// 换音源没成功：加载阶段发现的试听片段就照样播，并告诉用户；曲终发现的直接走下一首。
  Future<void> _trialFallback(Song song, int seq, {required bool autoplay, required bool ended, String? why}) async {
    final u = _trialUri;
    _trialUri = null;
    if (ended || u == null) {
      onNotice?.call('「${song.title}」只找到试听片段${why == null ? '' : '（$why）'}');
      if (ended) onCompleted?.call();
      return;
    }
    onNotice?.call('「${song.title}」只找到试听片段，先播试听版');
    try {
      await _player.setAudioSource(AudioSource.uri(u.uri, headers: u.headers));
      if (seq != _seq) return;
      _loaded = true;
      await _player.setLoopMode(_loopOne ? LoopMode.one : LoopMode.off);
      await applyEq(_eqOn, _eqCurve);
      if (autoplay) unawaited(_player.play());
      _syncNotification(playing: autoplay);
    } catch (e) {
      if (seq == _seq) onError?.call('播放失败：${describePlayError(e)}');
    }
  }

  /// 播放结束：没播到歌曲时长的 85% 就结束了，判定为试听，换音源从结束处续播。
  void _completed() {
    // 没加载成功（加载失败 / 切歌中）时的 completed 不是「播完了」：不切下一首。
    // 原来会转给 AppState 切下一首，下一首加载又把上一首打断，失败就一路跑完整张列表。
    if (!_loaded) {
      AppLog.instance.add('播放', '忽略未加载状态下的 completed');
      return;
    }
    final s = _current;
    final p = _player.position;
    if (s != null && _loaded && !_tried.contains(ResolveReason.trial) && s.dur >= 30 && p.inMilliseconds < s.dur * 1000 * trialRatio) {
      _trialUri = null;
      unawaited(_load(s, _seq, autoplay: true, reason: ResolveReason.trial, at: p, ended: true));
      return;
    }
    onCompleted?.call();
  }

  void _streamError(Object e) {
    final s = _current;
    if (s == null || !_loaded) return; // 加载阶段的错误由 _load 的 catch 处理
    if (!_tried.contains(ResolveReason.reload)) {
      final at = _player.position;
      onNotice?.call('播放中断，正在重新获取播放地址');
      unawaited(_load(s, _seq, autoplay: true, reason: ResolveReason.reload, at: at));
      return;
    }
    _loaded = false;
    onError?.call('播放中断：${describePlayError(e)}');
  }


  /// 边听边缓存：开关 + 缓存目录（path_provider 临时目录）。
  Future<void> setCache({required bool enabled, String? dir}) async {
    _cacheOn = enabled;
    _cacheDir = dir;
  }

  /// 暂停 / 恢复的音量淡入淡出开关（400ms）。
  void setFade(bool on) => _fade = on;

  /// 每次淡入 / 淡出 +1：新的一次开始后，旧的那次立刻停下（快速连点暂停 / 播放时不会互相打架，音量不会停在半路）。
  int _rampGen = 0;

  /// 返回 false 表示被新的淡入 / 淡出打断了。
  Future<bool> _rampVolume(double from, double to) async {
    final gen = ++_rampGen;
    const steps = 6, stepMs = Duration(milliseconds: 66);
    for (var i = 1; i <= steps; i++) {
      if (gen != _rampGen) return false;
      await _player.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(stepMs);
    }
    return gen == _rampGen;
  }

  Future<void> pause() async {
    _wantPlaying = false;
    if (_fade) {
      await _rampVolume(_vol, 0);
      if (_wantPlaying) return; // 淡出途中用户又点了播放：不暂停（被拖音量 / 睡眠淡出打断时照样暂停）
      await _player.pause();
      await _player.setVolume(_vol); // 恢复音量，下次播放正常响度
    } else {
      await _player.pause();
    }
  }

  /// 最近一次是要播放还是暂停（淡出途中按了播放，淡出结束后就不再暂停）。
  bool _wantPlaying = true;

  Future<void> resume() async {
    _wantPlaying = true;
    // just_audio 的 play() 要到播放结束 / 被暂停才返回：不能 await，
    // 否则淡入永远不执行，音量停在 0（「手动开始后没声音，拖一下音量条才有」）
    if (_fade) {
      final from = _player.playing ? _player.volume : 0.0; // 淡出途中继续：从当前音量接着淡入
      await _player.setVolume(from);
      unawaited(_player.play());
      if (!await _rampVolume(from, _vol)) return;
      await _player.setVolume(_vol);
    } else {
      unawaited(_player.play());
    }
  }
  Future<void> seek(double seconds) => _player.seek(Duration(milliseconds: (seconds * 1000).round()));
  Future<void> setSpeed(double v) => _player.setSpeed(v.clamp(0.5, 3.0));

  /// 变速的音高：1.0 = 不变调（「保持音调」开），跟速变调时传与速度相同的值。
  /// 平台不支持时 just_audio 内部忽略，调用方无需区分。
  Future<void> setPitch(double v) => _player.setPitch(v.clamp(0.5, 2.0)).catchError((Object _) {}); // 部分平台不支持变调，静默忽略

  /// 引擎侧音量（0..1）：用户音量条（AppState.vol）和睡眠定时淡出都经这里。
  Future<void> setVolume(double v) {
    _vol = v.clamp(0.0, 1.0);
    _rampGen++; // 用户拖音量条 / 睡眠淡出：以它为准，停掉正在进行的淡入淡出
    return _player.setVolume(_vol);
  }

  /// 当前目标音量（用户音量条 / 睡眠淡出），淡入淡出以它为终点。
  double _vol = 1;
  Future<void> setLoopOne(bool one) {
    _loopOne = one;
    return _player.setLoopMode(one ? LoopMode.one : LoopMode.off);
  }

  /// 通知栏按钮触发的播放/暂停（ AppState 已算好目标状态后调用）。
  Future<void> setPlaying(bool play) => play ? resume() : pause();

  /// 卸载当前音源（退出登录 / 清空队列等场景）。
  Future<void> unload() async {
    _seq++;
    _loaded = false;
    _current = null;
    await _player.stop();
    _handler?.clearNowPlaying();
  }

  // ---------------------------------------------------------------- 均衡器

  /// 把 UI 的 10 段曲线套到设备 EQ 上。仅 Android 有效；iOS / Web 静默跳过
  /// （iOS 的 EQ 需要自建 AVAudioEngine 链路，见 docs/audio/README.md 的限制一节）。
  Future<void> applyEq(bool on, List<double> curve10) async {
    _eqOn = on;
    _eqCurve = [...curve10];
    if (!_isAndroid) return;
    try {
      await _equalizer.setEnabled(on);
      if (!on) return;
      final params = await _equalizer.parameters;
      final gains = mapCurveToBands(curve10, [for (final b in params.bands) b.centerFrequency]);
      for (var i = 0; i < params.bands.length; i++) {
        await params.bands[i].setGain(round1(gains[i]));
      }
    } catch (_) {
      // 设备拒绝（正在通话 / EQ 被系统占用等），静默放弃，不影响播放。
    }
  }

  // ---------------------------------------------------------------- 通知

  /// 蓝牙歌词推送：把当前歌词行写进媒体信息（投放中也推，卡片由 [showNowPlaying] 维护）。
  void pushLyric(String title, String artist) => _handler?.setMediaText(title, artist);

  /// 不经本地播放器直接刷新通知卡片：切歌加载中、加载失败、投放中（本地引擎没加载）都靠它，
  /// 否则卡片停在上一首 / 播放态不变。
  void showNowPlaying(Song song, {required bool playing, required bool liked, required Duration position, required Duration duration, bool loading = false}) {
    final h = _handler;
    if (h == null) return;
    unawaited(h.setNowPlaying(song, playing: playing, liked: liked, position: position, duration: duration, loading: loading));
  }

  /// 投放中：媒体会话切成远程音量（0..100）；null 回到本机音量。
  void setRemoteVolume(int? volume) => _handler?.setRemoteVolume(volume);

  /// 播放状态 / 收藏状态变化后刷新通知栏（收藏按钮图标随 liked 切换）。
  void updateNotification({required bool playing, required bool liked}) {
    final s = _current;
    if (s == null || _handler == null || !_loaded) return;
    unawaited(_handler!.setNowPlaying(
      s,
      playing: playing,
      liked: liked,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      speed: _player.speed,
    ));
  }

  void _syncNotification({required bool playing}) {
    final s = _current;
    if (s == null || _handler == null) return;
    unawaited(_handler!.setNowPlaying(
      s,
      playing: playing,
      liked: false, // 引擎不知道收藏状态；AppState 在 play 流程后会带真实 liked 再刷一次
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      speed: _player.speed,
    ));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player.dispose();
  }

  static String _short(Object e) {
    final m = e.toString().trim();
    return m.length > 120 ? m.substring(0, 120) : m;
  }
}
