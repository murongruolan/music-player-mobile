// 真实播放引擎：封装 just_audio（Android=Media3/ExoPlayer，iOS=AVPlayer）+ 音频焦点 + 均衡器 + 媒体通知。
//
// 使用规则（与 AppState 的约定）：
// - 测试 / 截图（无平台通道）不创建引擎，AppState 走模拟时钟；
// - 引擎模式下 AppState 的 pos / playing / 时长全部由本引擎的回调驱动；
// - 队列逻辑（下一首是谁）仍归 AppState，引擎只负责「把给定的曲目播出来」。
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
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
        if (s == ProcessingState.completed) onCompleted?.call();
      }),
    ]);
  }

  /// 加载并（可选）播放一首。解析不到地址 / 格式不支持 / 加载失败都会走 [onError]，
  /// 不抛异常——调用方（AppState）不该为播放失败写 try-catch。
  Future<void> playSong(Song song, {required bool autoplay, required bool loopOne}) async {
    // 解析要几百毫秒到几秒；期间用户可能已经切到别的歌，旧的结果直接丢掉
    final seq = ++_seq;
    if (_loaded) {
      _loaded = false;
      unawaited(_player.stop());
    }
    Uri? uri;
    try {
      uri = await _resolver.resolve(song);
    } catch (e) {
      if (seq == _seq) onError?.call('${song.title}：${_short(e)}');
      return;
    }
    if (seq != _seq) return;
    if (uri == null) {
      onError?.call('无法解析播放地址：${song.title}');
      return;
    }
    if (!isLikelySupported(uri)) {
      onError?.call('暂不支持 ${formatLabel(formatOfUri(uri))} 格式：${song.title}');
      return;
    }
    _current = song;
    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      if (seq != _seq) return;
      _loaded = true;
      await _player.setLoopMode(loopOne ? LoopMode.one : LoopMode.off);
      await applyEq(_eqOn, _eqCurve); // 换源后重新套用 EQ 曲线
      // just_audio 的 play() 返回的 Future 要到播放完成/被打断时才 complete，
      // await 会把 playSong 挂到曲终——通知同步与 AppState 的加载收尾（速度/EQ/收藏态）
      // 全部永远不执行（实测通知栏因此无媒体卡片）。这里只负责启动播放，不等待。
      if (autoplay) unawaited(_player.play());
      _syncNotification(playing: autoplay);
    } catch (e) {
      _loaded = false;
      onError?.call('播放失败：${_short(e)}');
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> seek(double seconds) => _player.seek(Duration(milliseconds: (seconds * 1000).round()));
  Future<void> setSpeed(double v) => _player.setSpeed(v.clamp(0.5, 3.0));

  /// 变速的音高：1.0 = 不变调（「保持音调」开），跟速变调时传与速度相同的值。
  /// 平台不支持时 just_audio 内部忽略，调用方无需区分。
  Future<void> setPitch(double v) => _player.setPitch(v.clamp(0.5, 2.0));

  /// 引擎侧音量（0..1），睡眠定时淡出用；用户音量条（AppState.vol）目前不经引擎。
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));
  Future<void> setLoopOne(bool one) => _player.setLoopMode(one ? LoopMode.one : LoopMode.off);

  /// 通知栏按钮触发的播放/暂停（ AppState 已算好目标状态后调用）。
  Future<void> setPlaying(bool play) => play ? _player.play() : _player.pause();

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
