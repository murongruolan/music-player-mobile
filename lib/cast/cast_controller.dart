// 投放编排：设备发现 → 连接（取 AVTransport 控制地址）→ 投放当前曲目 → 轮询进度/状态。
// 本地引擎与投放互斥：投放时本地引擎暂停，进度/时长经本控制器的回调驱动 AppState
// （复用 engineDuration / pos 通道，播放器 UI 无感知）。

import 'dart:async';

import 'package:flutter/services.dart';

import '../data/models.dart';
import 'dlna.dart';

class CastController {
  DlnaDevice? device;
  String? _controlUrl;
  Song? current;
  Timer? _poll;
  bool _ended = false; // 每首歌只报一次「播完」

  // 轮询间隙的位置外推：GetPositionInfo 每 2 秒一次，直接回写会让进度条两秒一跳
  // （本地播放是引擎 ~200ms 一报）。两次轮询之间按流逝秒数本地推进，下轮轮询对表。
  Timer? _extrapolate;
  double _lastPos = 0;
  DateTime _lastPosAt = DateTime.now();
  bool _playingNow = false;
  double _lastDur = 0;

  /// 轮询代际：切歌 / 重投 / 断开时 +1，进行中的旧请求回来后发现代际变了就丢掉结果
  /// （只取消定时器不够：已经发出去的 GetPositionInfo 回来照样会把旧位置写回进度条）。
  int _gen = 0;

  /// 以某个位置为基准重新开始外推（轮询对表、拖动、暂停 / 继续、换歌都要调）。
  void _anchor(double pos, {bool? playing}) {
    _lastPos = pos;
    _lastPosAt = DateTime.now();
    if (playing != null) _playingNow = playing;
  }

  void _stopTimers() {
    _poll?.cancel();
    _poll = null;
    _extrapolate?.cancel();
    _extrapolate = null;
  }

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

  static const _native = MethodChannel('lyra/native');

  /// 扫描局域网内的 DLNA 渲染设备。Android 上扫描期间持有 Wi-Fi 组播锁
  /// （不少机型的 Wi-Fi 驱动默认丢弃组播 / 省电过滤，SSDP 发现会收不到包）。
  Future<List<DlnaDevice>> discover() async {
    await _multicast(true);
    try {
      return await Dlna.discover();
    } finally {
      await _multicast(false);
    }
  }

  Future<void> _multicast(bool on) async {
    try {
      await _native.invokeMethod<void>('net.multicast', on);
    } catch (_) {
      // 非 Android / 测试环境没有这个通道：忽略
    }
  }

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
    _anchor(0, playing: false); // 新的一首从 0 开始外推（原来沿用上一首的位置）
    _lastDur = 0;
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
      // 暂停：立刻停止外推（原来要等下一轮轮询，最多多走 2 秒再跳回）；继续：从当前位置重新计时
      _anchor(_playingNow ? _lastPos + DateTime.now().difference(_lastPosAt).inMilliseconds / 1000 : _lastPos, playing: play);
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
      _anchor(seconds); // 拖动后从新位置外推（原来会跳回拖动前的位置直到下一轮轮询）
      onPosition?.call(seconds);
    } on CastException catch (e) {
      onError?.call(e.message);
    }
  }

  /// 投放切歌 / 重投前暂停轮询与外推：解析期间旧一轮的进度回调不再回写。
  /// 否则切歌后进度条先被旧位置顶满，等新一轮轮询才开始才归零（实测现象）。
  void suspendPolling() {
    _gen++;
    _stopTimers();
  }

  /// 切歌失败（取不到地址等）后恢复轮询：渲染端还在放上一首，界面要继续跟着它。
  void resumePolling() {
    if (!connected || _poll != null) return;
    _startPoll(playing: _playingNow);
  }

  /// 断开：停止渲染端播放并清掉轮询。本地恢复播放由 AppState 决定。
  Future<void> disconnect() async {
    final ctl = _controlUrl;
    _gen++;
    _stopTimers();
    // 先清掉连接状态再发 Stop：Stop 可能被 Wi-Fi 省电拖几秒，这期间 connected 还是 true 的话，
    // App 仍认为在投放，按播放键会把 Play 发给电视而不是本地播放（「断开后第一次点播放被吞」）
    device = null;
    _controlUrl = null;
    _rcUrl = null;
    volume = null;
    _wantVol = null;
    current = null;
    if (ctl != null) {
      try {
        await Dlna.stop(ctl);
      } catch (_) {
        // 设备已关机 / 离线：断开本身就是清理，静默
      }
    }
  }

  void dispose() {
    _gen++;
    _stopTimers();
  }

  // ------------------------------------------------------------ 内部

  void _startPoll({required bool playing}) {
    _stopTimers();
    _gen++;
    _anchor(_lastPos, playing: playing);
    onPlaying?.call(playing);
    // 立即取一次，随后每 2 秒轮询（局域网开销可忽略）；间隙由外推定时器补齐
    unawaited(_pollOnce());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_pollOnce()));
    _extrapolate?.cancel();
    _extrapolate = Timer.periodic(const Duration(milliseconds: 500), (_) => _extrapolateOnce());
  }

  /// 两次轮询之间按流逝秒数推进进度，只在渲染端确实在播时推进（暂停 / 转场冻结）。
  void _extrapolateOnce() {
    if (!_playingNow || !connected || onPosition == null) return;
    final dt = DateTime.now().difference(_lastPosAt).inMilliseconds / 1000;
    if (dt <= 0) return;
    final p = _lastPos + dt;
    onPosition?.call(_lastDur > 0 && p > _lastDur ? _lastDur : p); // 不外推到时长以外
  }

  Future<void> _pollOnce() async {
    final ctl = _controlUrl;
    if (ctl == null) return;
    final g = _gen;
    try {
      final r = await Dlna.pollInfo(ctl);
      if (g != _gen || ctl != _controlUrl) return; // 请求期间切了歌 / 断开了：旧结果丢掉
      if (++_pollN % 5 == 0) unawaited(_readVolume()); // 约 10 秒对一次音量（电视遥控器也会改）
      if (r.duration > 0) {
        _lastDur = r.duration;
        onDuration?.call(r.duration);
      }
      if (r.position > 0) {
        _anchor(r.position);
        onPosition?.call(r.position);
      }
      _playingNow = r.state == 'PLAYING';
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
      if (g != _gen) return;
      // 设备离线 / 网络抖动：停掉轮询和外推并上报（原来外推还在走，进度条自己往前跑），AppState 决定断开
      _stopTimers();
      _playingNow = false;
      onError?.call('投放设备失联：${e.message}');
    }
  }
}
