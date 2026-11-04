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
import '../source/failure.dart';
import 'equalizer.dart';
import 'formats.dart';
import 'media_handler.dart';
import 'track_resolver.dart';

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class AudioEngine {
  AudioEngine({required TrackResolver resolver}) : _resolver = resolver;

  final TrackResolver _resolver;
  // EQ 只在 Android 有系统实现；iOS/Web 静默跳过（见 docs/audio/README.md 限制一节）
  static final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
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

  /// 初始化：音频焦点 + 通知通道。必须在 runApp 之前调用（audio_service 的要求）。
  /// [handler] 由 main.dart 先行创建并传入。
  Future<void> init(LyraMediaHandler handler) async {
    _handler = handler;
    _handler!.onAction = (a) => onMediaAction?.call(a);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _subs.addAll([
      _player.positionStream.listen((p) => onPosition?.call(p.inMicroseconds / 1e6)),
      _player.durationStream.listen((d) {
        if (d != null) onDuration?.call(d.inMicroseconds / 1e6);
      }),
      _player.playingStream.listen((p) => onPlaying?.call(p)),
      _player.processingStateStream.listen((s) {
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
  Future<void> playSong(Song song, {required bool autoplay, required bool loopOne}) async {
    // 解析要几百毫秒到几秒；期间用户可能已经切到别的歌，旧的结果直接丢掉
    final seq = ++_seq;
    _tried.clear();
    _loopOne = loopOne;
    if (_loaded) {
      _loaded = false;
      unawaited(_player.stop());
    }
    await _load(song, seq, autoplay: autoplay);
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
      if (_cacheOn && reason == ResolveReason.play && _cacheDir != null && _cacheDir!.isNotEmpty && !rp.uri.isScheme('file')) {
        // 边听边缓存：just_audio 的锁定缓存源。文件按歌曲 key 命名（播放地址带时效签名，按地址命名几乎不会命中）；
        // 重新取链 / 试听换源时不走缓存，避免把试听片段或坏链接缓存下来。
        final key = base64Url.encode(utf8.encode(cacheKey)).replaceAll('=', '');
        // ignore: experimental_member_use
        source = LockCachingAudioSource(rp.uri, cacheFile: File('$_cacheDir/$key.audio'), headers: rp.headers);
      } else {
        source = AudioSource.uri(rp.uri, headers: rp.headers);
      }
      final d = await _player.setAudioSource(source, initialPosition: at);
      if (seq != _seq) return;
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
      if (!_tried.contains(ResolveReason.reload)) {
        // 链接可能已过期 / 被拒（403）：不用缓存重新取一次
        return _load(song, seq, autoplay: autoplay, reason: ResolveReason.reload, at: at);
      }
      onError?.call('播放失败：${describePlayError(e)}');
    }
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

  Future<void> _rampVolume(double from, double to) async {
    const steps = 6, stepMs = Duration(milliseconds: 66);
    for (var i = 1; i <= steps; i++) {
      await _player.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(stepMs);
    }
  }

  Future<void> pause() async {
    if (_fade) {
      await _rampVolume(_vol, 0);
      await _player.pause();
      await _player.setVolume(_vol); // 恢复音量，下次播放正常响度
    } else {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    if (_fade) {
      await _player.setVolume(0);
      await _player.play();
      await _rampVolume(0, _vol);
    } else {
      await _player.play();
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
