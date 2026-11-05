// 投放编排：设备发现 → 连接（取 AVTransport 控制地址）→ 投放当前曲目 → 轮询进度/状态。
// 本地引擎与投放互斥：投放时本地引擎暂停，进度/时长经本控制器的回调驱动 AppState
// （复用 engineDuration / pos 通道，播放器 UI 无感知）。

import 'dart:async';

import '../data/models.dart';
import 'dlna.dart';

class CastController {
  DlnaDevice? device;
  String? _controlUrl;
  Song? current;
  Timer? _poll;
  bool _ended = false; // 每首歌只报一次「播完」

  /// 这首歌在渲染端真正播起来过（报过 PLAYING）：之前的 STOPPED 是加载中的转场，不算播完。
  bool _seenPlaying = false;
  DateTime _castAt = DateTime.now();

  // —— 回调（AppState 挂；与 AudioEngine 的回调语义一致） ——
  void Function(double seconds)? onPosition;
  void Function(double seconds)? onDuration;
  void Function(bool playing)? onPlaying;
  void Function()? onEnded;
  void Function(String message)? onError;

  /// 渲染端音量变了（本机调的、或电视遥控器调的被轮询发现）。
  void Function(int volume)? onVolume;

  String? _rcUrl;

  /// 渲染端当前音量 0..100；读不到时为 null（仍可设置）。
  int? volume;

  /// 设备描述里有 RenderingControl：可以远程调音量。
  bool get canVolume => connected && _rcUrl != null;

  bool get connected => device != null && _controlUrl != null;

  /// 扫描局域网内的 DLNA 渲染设备。
  Future<List<DlnaDevice>> discover() => Dlna.discover();

  /// 连接设备：拉设备描述确认 AVTransport 可用。
  Future<void> connect(DlnaDevice d) async {
    final desc = await Dlna.describe(d.location, fallbackUdn: d.udn); // 拿到 controlUrl
    device = desc;
    _controlUrl = desc.controlUrl;
    _rcUrl = desc.renderingUrl;
    volume = null;
    _pollN = 0;
    await _readVolume();
  }

  // —— 音量：拖动时只保留最新值，同一时间只发一个 SetVolume（局域网 SOAP 一次几十到几百毫秒） ——
  int? _wantVol;
  bool _volBusy = false;
  DateTime _volSetAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> setVolume(int v) async {
    final rc = _rcUrl;
    if (rc == null) return;
    _wantVol = v.clamp(0, 100);
    volume = _wantVol; // 界面先跟手
    if (_volBusy) return;
    _volBusy = true;
    try {
      while (_wantVol != null && _rcUrl == rc) {
        final x = _wantVol!;
        _wantVol = null;
        try {
          await Dlna.setVolume(controlUrl: rc, volume: x);
        } on CastException catch (e) {
          _wantVol = null;
          onError?.call('调节音量失败：${e.message}');
          break;
        }
      }
    } finally {
      _volBusy = false;
      _volSetAt = DateTime.now();
    }
    final now = volume;
    if (now != null) onVolume?.call(now);
  }

  Future<void> _readVolume() async {
    final rc = _rcUrl;
    if (rc == null) return;
    try {
      final v = await Dlna.getVolume(controlUrl: rc);
      // 读的过程中用户刚拖过音量：以用户的为准
      if (v == null || _volBusy || _rcUrl != rc || DateTime.now().difference(_volSetAt) < const Duration(seconds: 3)) return;
      if (v != volume) {
        volume = v;
        onVolume?.call(v);
      }
    } on CastException {
      // 部分设备只支持 SetVolume 不支持 GetVolume：保持可调，只是读不到初值
    }
  }

  int _pollN = 0;

  /// 投放一首：解析出的 [url] 交给渲染端拉流，本地进度轮询启动。
  Future<void> cast(Song song, Uri url, {required bool autoplay}) async {
    final ctl = _controlUrl;
    if (ctl == null) throw const CastException('尚未连接设备');
    _ended = false;
    _seenPlaying = false;
    _castAt = DateTime.now();
    current = song;
    await Dlna.cast(controlUrl: ctl, uri: url.toString(), title: song.title, artist: song.artist);
    if (autoplay) {
      await Dlna.play(ctl);
    } else {
      await Dlna.pause(ctl);
    }
    _startPoll(playing: autoplay);
  }

  Future<void> setPlaying(bool play) async {
    final ctl = _controlUrl;
    if (ctl == null) return;
    try {
      await (play ? Dlna.play(ctl) : Dlna.pause(ctl));
      onPlaying?.call(play);
    } on CastException catch (e) {
      onError?.call(e.message);
    }
  }

  Future<void> seek(double seconds) async {
    final ctl = _controlUrl;
    if (ctl == null) return;
    try {
      await Dlna.seek(ctl, seconds);
      onPosition?.call(seconds);
    } on CastException catch (e) {
      onError?.call(e.message);
    }
  }

  /// 断开：停止渲染端播放并清掉轮询。本地恢复播放由 AppState 决定。
  Future<void> disconnect() async {
    final ctl = _controlUrl;
    _poll?.cancel();
    _poll = null;
    if (ctl != null) {
      try {
        await Dlna.stop(ctl);
      } catch (_) {
        // 设备已关机 / 离线：断开本身就是清理，静默
      }
    }
    device = null;
    _controlUrl = null;
    _rcUrl = null;
    volume = null;
    _wantVol = null;
    current = null;
  }

  void dispose() {
    _poll?.cancel();
    _poll = null;
  }

  // ------------------------------------------------------------ 内部

  void _startPoll({required bool playing}) {
    _poll?.cancel();
    onPlaying?.call(playing);
    // 立即取一次，随后每 2 秒轮询（局域网开销可忽略）
    unawaited(_pollOnce());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    final ctl = _controlUrl;
    if (ctl == null) return;
    try {
      final r = await Dlna.pollInfo(ctl);
      if (++_pollN % 5 == 0) unawaited(_readVolume()); // 约 10 秒对一次音量（电视遥控器也会改）
      if (r.duration > 0) onDuration?.call(r.duration);
      if (r.position > 0) onPosition?.call(r.position);
      switch (r.state) {
        case 'PLAYING':
          _seenPlaying = true;
          onPlaying?.call(true);
        case 'PAUSED_PLAYBACK':
          onPlaying?.call(false);
        case 'STOPPED' || 'NO_MEDIA_PRESENT':
          // 投放后渲染端短暂处于 STOPPED 属正常（转场），只有播完一轮才回调 onEnded
          // 没播起来过、而且投放还不到 15 秒：当作转场，不切歌（原来一投放就可能连环跳下一首）
          if (!_seenPlaying && DateTime.now().difference(_castAt) < const Duration(seconds: 15)) return;
          if (!_ended && current != null) {
            _ended = true;
            onPlaying?.call(false);
            onEnded?.call();
          }
      }
    } on CastException catch (e) {
      // 设备离线 / 网络抖动：停掉轮询并上报，AppState 决定断开
      _poll?.cancel();
      _poll = null;
      onError?.call('投放设备失联：${e.message}');
    }
  }
}
