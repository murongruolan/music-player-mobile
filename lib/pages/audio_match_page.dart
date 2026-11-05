// 听歌识曲（联网模式，真实）：录音 → 本机算指纹 → 网易识别接口 → 命中就能直接播。
// 每 3 秒的录音试一次，最多试 3 次（约 10 秒）；只上传指纹，不上传录音。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../audio/fingerprint.dart';
import '../core/app_log.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../platform/audio_match.dart';
import '../platform/models.dart' show PlatformException;
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'remote.dart' show registerTrack;

enum _St { prepare, listen, nomatch, hit, denied, error }

class AudioMatchView extends StatefulWidget {
  const AudioMatchView({super.key});
  @override
  State<AudioMatchView> createState() => _AudioMatchViewState();
}

class _AudioMatchViewState extends State<AudioMatchView> with SingleTickerProviderStateMixin {
  static const _rate = 8000, _window = 3, _tries = 3;
  static const _windowBytes = _rate * 2 * _window; // 16 位单声道

  final fp = FingerprintEngine();
  final rec = AudioRecorder();
  late final ringC = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  StreamSubscription<Uint8List>? _sub;
  final _buf = BytesBuilder(copy: false);
  int _consumed = 0, _try = 0;
  bool _querying = false;
  _St st = _St.prepare;
  String msg = '';
  AudioMatchHit? hit;
  double level = 0; // 音量（波形动画用）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _stopRec();
    rec.dispose();
    ringC.dispose();
    super.dispose();
  }

  Future<void> _stopRec() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (await rec.isRecording()) await rec.stop();
    } catch (_) {}
  }

  Future<void> _start() async {
    await _stopRec();
    _buf.clear();
    _consumed = 0;
    _try = 0;
    setState(() {
      st = _St.prepare;
      hit = null;
      msg = '';
    });
    try {
      if (!await rec.hasPermission()) {
        AppLog.instance.add('识曲', '没有麦克风权限');
        return setState(() => st = _St.denied);
      }
      final stream = await rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _rate, numChannels: 1, autoGain: false, echoCancel: false, noiseSuppress: false));
      AppLog.instance.add('识曲', '开始录音');
      if (!mounted) return;
      setState(() => st = _St.listen);
      _sub = stream.listen(_onPcm, onError: (Object e) => _fail('录音出错：$e'));
      // 指纹组件同时在加载；第一段录满前通常已就绪
      unawaited(fp.ready.catchError((Object e) => _fail('$e')));
    } catch (e) {
      _fail('打不开麦克风：$e');
    }
  }

  void _onPcm(Uint8List chunk) {
    _buf.add(chunk);
    // 音量：取这一块的峰值
    var peak = 0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      var v = chunk[i] | (chunk[i + 1] << 8);
      if (v >= 0x8000) v -= 0x10000;
      peak = math.max(peak, v.abs());
    }
    level = level * .6 + (peak / 32768) * .4;
    if (_buf.length - _consumed >= _windowBytes && !_querying && st == _St.listen) {
      final all = _buf.toBytes();
      final win = Uint8List.sublistView(all, all.length - _windowBytes); // 最近 3 秒
      _consumed = all.length;
      unawaited(_query(win));
    }
  }

  Future<void> _query(Uint8List win) async {
    _querying = true;
    _try++;
    final n = _try;
    try {
      final f = await fp.compute(win);
      final hits = await AudioMatchApi(context.appRead.content.http).query(f, seconds: _window, times: n);
      if (!mounted || st != _St.listen) return;
      AppLog.instance.add('识曲', '第 $n 次：${hits.isEmpty ? '没有识别出来' : '命中「${hits.first.track.title} - ${hits.first.track.artist}」@${hits.first.startMs}ms'}');
      if (hits.isNotEmpty) {
        await _stopRec();
        setState(() {
          hit = hits.first;
          st = _St.hit;
        });
        Cover.warm(hits.first.track.cover);
      } else if (n >= _tries) {
        await _stopRec();
        setState(() => st = _St.nomatch);
      }
    } catch (e) {
      AppLog.instance.add('识曲', '第 $n 次失败：$e');
      _fail(e is PlatformException ? e.message : '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      _querying = false;
    }
  }

  void _fail(String m) {
    if (!mounted || st == _St.hit) return;
    unawaited(_stopRec());
    setState(() {
      st = _St.error;
      msg = m;
    });
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal.forceDark;
    return Stack(children: [
      Positioned(left: 0, top: 0, child: fp.view()),
      Positioned.fill(child: AnimatedSwitcher(duration: const Duration(milliseconds: 360), child: st == _St.hit ? _hitView(pal) : _listenView(pal))),
    ]);
  }

  Widget _hitView(Pal pal) {
    final app = context.app;
    final h = hit!;
    final t = h.track;
    void play({bool fromHit = false}) {
      final id = registerTrack(app, t);
      app.play(id, name: '听歌识曲', ids: [id]);
      if (fromHit && h.startMs > 0) {
        // 等加载完再跳到识别到的位置
        Future<void>.delayed(const Duration(milliseconds: 1500), () {
          if (app.cur == id && app.engineActive) app.seek(h.startMs / 1000);
        });
      }
      Navigator.of(context).pop();
    }

    return Column(key: const ValueKey('hit'), children: [
      const Spacer(),
      TweenAnimationBuilder<double>(tween: Tween(begin: .4, end: 1), duration: const Duration(milliseconds: 620), curve: Tk.spring, builder: (_, v, ch) => Transform.scale(scale: v, child: ch), child: Cover(hue: 200, size: 200, radius: 26, shadow: true, url: t.cover)),
      const SizedBox(height: 18),
      Badge2('匹配位置 ${_fmt(h.startMs)}', acc: true),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: Text(t.title, textAlign: TextAlign.center, maxLines: 2, style: ts(24, w: FontWeight.w800, c: Colors.white))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: Text([t.artist, t.album].where((x) => x.isNotEmpty).join(' · '), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, c: const Color(0x99FFFFFF)))),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(children: [
          Expanded(child: Btn('从头播放', icon: 'play', onTap: () => play())),
          const SizedBox(width: 10),
          Expanded(child: Btn.sec('从这里接着听', icon: 'next', onTap: () => play(fromHit: true))),
        ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Press(
          onTap: () {
            final id = registerTrack(app, t);
            if (!app.liked.contains(id)) app.toggleLike(id);
            toast('已收藏到「我喜欢」', 'heartf');
          },
          child: Padding(padding: const EdgeInsets.all(12), child: Text('收藏', style: ts(14, w: FontWeight.w600, c: pal.acc))),
        ),
        Press(onTap: _start, child: Padding(padding: const EdgeInsets.all(12), child: Text('再识别一首', style: ts(14, w: FontWeight.w600, c: pal.acc)))),
      ]),
      const Spacer(),
      const SizedBox(height: 90),
    ]);
  }

  Widget _listenView(Pal pal) {
    final (title, sub) = switch (st) {
      _St.prepare => ('准备中…', '正在打开麦克风'),
      _St.listen => (_try == 0 ? '正在聆听…' : '还在听，再给我几秒…', '把手机靠近音源 · 只在本机计算指纹，不上传录音'),
      _St.nomatch => ('没有识别出来', '换个更清晰的片段（避开前奏和人声嘈杂处）再试一次'),
      _St.denied => ('需要麦克风权限', '在系统设置里允许 Lyra 使用麦克风后再试'),
      _St.error => ('识别失败', msg),
      _St.hit => ('', ''),
    };
    final active = st == _St.listen || st == _St.prepare;
    final progress = st == _St.listen ? ((_try + (_buf.length - _consumed) / _windowBytes) / _tries).clamp(0.0, 1.0) : 0.0;
    return Column(key: ValueKey('l$st'), children: [
      const Spacer(flex: 2),
      SizedBox(
        width: 280,
        height: 280,
        child: AnimatedBuilder(
          animation: ringC,
          builder: (_, __) => CustomPaint(
            painter: active ? _Rings(ringC.value, pal.acc, 1 + level * 2) : null,
            child: Center(
              child: Press(
                onTap: active ? null : _start,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [pal.acc, Color.lerp(pal.acc, Colors.black, .35)!]), boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 40, spreadRadius: 6)]),
                  child: Icon(ic(active ? 'mic' : 'refresh'), size: 46, color: pal.ink),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(title, style: ts(20, w: FontWeight.w700, c: Colors.white)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 36), child: Text(sub, textAlign: TextAlign.center, style: ts(13, c: const Color(0x99FFFFFF), h: 1.5))),
      const SizedBox(height: 18),
      if (st == _St.listen)
        SizedBox(width: 160, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: progress, minHeight: 3, color: pal.acc, backgroundColor: const Color(0x22FFFFFF))))
      else if (!active)
        Btn(st == _St.denied ? '重新申请权限' : '再试一次', icon: 'refresh', small: true, onTap: _start),
      const Spacer(flex: 3),
    ]);
  }
}

class _Rings extends CustomPainter {
  final double t, amp;
  final Color c;
  _Rings(this.t, this.c, this.amp);
  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      canvas.drawCircle(s.center(Offset.zero), 60 + k * 80 * amp.clamp(1.0, 1.6), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = c.withValues(alpha: (1 - k) * .6));
    }
  }

  @override
  bool shouldRepaint(_Rings o) => o.t != t || o.amp != amp;
}
