// 听歌识曲（联网模式，真实）：录音 → 本机算指纹 → 网易识别接口 → 命中就能直接播。
// 每 3 秒的录音试一次，最多试 3 次（约 10 秒）；只上传指纹，不上传录音。
//
// 界面参照 QQ 音乐 / 网易云：
// - 识别中：跟主题走的浅底，中间一圈圈随音量呼吸的波纹 + 麦克风，「识别中 Ns」，点中间停止；
// - 结果：封面取色的深色背景，旋转唱片 + 歌名歌手 + 收藏 / 播放，下面三行歌词从识别到的位置开始滚动，
//   再往下是「其他识别结果」（接口一次可能返回好几首：原唱、伴奏、翻唱…）；
// - 右上角时钟：本机识别记录。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../audio/fingerprint.dart';
import '../core/app_log.dart';
import '../core/lyric_store.dart' show toLyricLines;
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart' show previewLyrics;
import '../data/models.dart';
import '../platform/audio_match.dart';
import '../platform/models.dart' show PlatformException, PTrack;
import '../sync/cloud_models.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'remote.dart' show registerTrack;

enum _St { prepare, listen, stopped, nomatch, hit, denied, error }

class AudioMatchView extends StatefulWidget {
  /// 截图预览：'listen' / 'hit'。不开麦克风、不加载指纹组件，用假数据把界面摆出来。
  final String? preview;
  const AudioMatchView({super.key, this.preview});
  @override
  State<AudioMatchView> createState() => _AudioMatchViewState();
}

class _AudioMatchViewState extends State<AudioMatchView> with TickerProviderStateMixin {
  static const _rate = 8000, _window = 3, _tries = 3;
  static const _windowBytes = _rate * 2 * _window; // 16 位单声道

  final fp = FingerprintEngine();
  final rec = AudioRecorder();
  late final ringC = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final discC = AnimationController(vsync: this, duration: const Duration(seconds: 18));
  StreamSubscription<Uint8List>? _sub;
  final _buf = BytesBuilder(copy: false);
  int _consumed = 0, _try = 0;
  bool _querying = false;
  _St st = _St.prepare;
  String msg = '';
  List<AudioMatchHit> hits = const [];
  int sel = 0; // 当前展示的是第几个结果
  double level = 0; // 音量（波纹动画用）
  final _clock = Stopwatch();

  // 结果页歌词：从识别到的位置开始，按真实时间往前走
  List<LyricLine> _lines = const [];
  bool _lyricLoading = false;
  DateTime _hitAt = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) return _fakePreview(widget.preview!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _fakePreview(String mode) {
    if (mode == 'listen') {
      st = _St.listen;
      level = .12;
      _clock.start();
      return;
    }
    PTrack t(String id, String title, String artist, String album) => PTrack(platform: 'wy', nativeId: id, title: title, artist: artist, album: album, duration: 240);
    hits = [AudioMatchHit(t('1', '命运火焰', 'Faye 詹雯婷', '命运火焰'), 60020), AudioMatchHit(t('2', '命运火焰 (和声伴奏)', 'Faye 詹雯婷', '命运火焰'), 60020), AudioMatchHit(t('3', '命运火焰 (Live)', 'Faye 詹雯婷', '现场'), 58000)];
    st = _St.hit;
    _lines = [for (final (i, l) in previewLyrics.indexed) LyricLine(55.0 + i * 4, 4, l.text, '', '')];
    _hitAt = DateTime.now();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _stopRec();
    rec.dispose();
    ringC.dispose();
    discC.dispose();
    super.dispose();
  }

  Future<void> _stopRec() async {
    if (st != _St.hit) _tick?.cancel();
    await _sub?.cancel();
    _sub = null;
    _clock.stop();
    try {
      if (await rec.isRecording()) await rec.stop();
    } catch (_) {}
  }

  Future<void> _start() async {
    await _stopRec();
    _tick?.cancel();
    discC.stop();
    _buf.clear();
    _consumed = 0;
    _try = 0;
    setState(() {
      st = _St.prepare;
      hits = const [];
      sel = 0;
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
      _clock
        ..reset()
        ..start();
      setState(() => st = _St.listen);
      // 「识别中 Ns」每秒走一下
      _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && st == _St.listen) setState(() {});
      });
      _sub = stream.listen(_onPcm, onError: (Object e) => _fail('录音出错：$e'));
      // 指纹组件同时在加载；第一段录满前通常已就绪
      unawaited(fp.ready.catchError((Object e) => _fail('$e')));
    } catch (e) {
      _fail('打不开麦克风：$e');
    }
  }

  /// 识别中点中间：停止。
  Future<void> _stop() async {
    await _stopRec();
    if (mounted && (st == _St.listen || st == _St.prepare)) setState(() => st = _St.stopped);
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
      final r = await AudioMatchApi(context.appRead.content.http).query(f, seconds: _window, times: n);
      if (!mounted || st != _St.listen) return;
      AppLog.instance.add('识曲', '第 $n 次：${r.isEmpty ? '没有识别出来' : '命中 ${r.length} 首，第一首「${r.first.track.title} - ${r.first.track.artist}」@${r.first.startMs}ms'}');
      if (r.isNotEmpty) {
        await _stopRec();
        // 同一首歌可能返回好几条（不同版本同 id 的去重）
        final seen = <String>{};
        final list = [for (final h in r) if (seen.add(h.track.id)) h];
        for (final h in list) {
          Cover.warm(h.track.cover);
        }
        setState(() {
          hits = list;
          sel = 0;
          st = _St.hit;
        });
        discC.repeat();
        unawaited(_history.add(context.appRead, list.first));
        _showLyrics();
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

  // ---------------------------------------------------------------- 结果

  AudioMatchHit get _hit => hits[sel];

  /// 歌曲里「现在」唱到哪（秒）：录音窗口的起点 + 窗口长度 + 识别完到现在过了多久。
  double get _songPos => _hit.startMs / 1000 + _window + DateTime.now().difference(_hitAt).inMilliseconds / 1000;

  Future<void> _showLyrics() async {
    if (widget.preview != null) return;
    _hitAt = DateTime.now();
    _tick?.cancel();
    final t = _hit.track;
    setState(() {
      _lines = const [];
      _lyricLoading = true;
    });
    try {
      final l = await context.appRead.content.lyric(t);
      if (!mounted || _hit.track.id != t.id) return;
      setState(() => _lines = toLyricLines(l, t.duration));
    } catch (_) {
      // 没有歌词：只显示歌名
    } finally {
      if (mounted && _hit.track.id == t.id) setState(() => _lyricLoading = false);
    }
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _pick(int i) {
    if (i == sel) return;
    setState(() => sel = i);
    _showLyrics();
  }

  void _play(PTrack t, {double? from}) {
    final app = context.appRead;
    final id = registerTrack(app, t);
    app.play(id, name: '听歌识曲', ids: [id]);
    if (from != null && from > 1) {
      // 等加载完再跳到现在唱到的位置
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (app.cur == id && app.engineActive) app.seek(from);
      });
    }
    Navigator.of(context).pop();
  }

  bool _liked(PTrack t) {
    final app = context.appRead;
    final id = app.library.idOfKey(t.id);
    return id != null && app.liked.contains(id);
  }

  void _toggleLike(PTrack t) {
    final app = context.appRead;
    final id = registerTrack(app, t);
    final on = app.toggleLike(id);
    toast(on ? '已收藏到「我喜欢」' : '已取消收藏', on ? 'heartf' : 'heart');
    setState(() {});
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final hit = st == _St.hit && hits.isNotEmpty;
    return Stack(children: [
      if (widget.preview == null) Positioned(left: 0, top: 0, child: fp.view()),
      Positioned.fill(child: AnimatedSwitcher(duration: const Duration(milliseconds: 420), child: hit ? _hitView() : _listenView())),
      Positioned(left: 0, right: 0, top: 0, child: _bar(hit)),
    ]);
  }

  Widget _bar(bool hit) {
    final pal = context.pal;
    final c = hit ? Colors.white : pal.t1;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Row(children: [
          const SizedBox(width: 4),
          IBtn('left', color: c, onTap: () => Navigator.of(context).pop()),
          Expanded(child: Text(hit ? (hits.length > 1 ? '识别结果（${hits.length} 个）' : '识别结果') : '听歌识曲', textAlign: TextAlign.center, style: ts(17, w: FontWeight.w700, c: c))),
          IBtn('history', color: c, onTap: () => _openHistory(context)),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }

  Widget _listenView() {
    final pal = context.pal;
    final active = st == _St.listen || st == _St.prepare;
    final secs = _clock.elapsed.inSeconds;
    final (title, sub) = switch (st) {
      _St.prepare => ('准备中…', '正在打开麦克风'),
      _St.listen => ('识别中 ${secs}s', _try == 0 ? '保持外界安静，靠近音源，识别更准确' : '还在听，再给我几秒…'),
      _St.stopped => ('已停止识别', '点一下重新开始'),
      _St.nomatch => ('没有识别出来', '换个更清晰的片段（避开前奏和嘈杂处）再试一次'),
      _St.denied => ('需要麦克风权限', '在系统设置里允许 Lyra 使用麦克风后再试'),
      _St.error => ('识别失败', msg),
      _St.hit => ('', ''),
    };
    return Container(
      key: const ValueKey('listen'),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pal.bg, Color.lerp(pal.bg, pal.acc, pal.dark ? .06 : .08)!])),
      child: Column(children: [
        const Spacer(flex: 3),
        SizedBox(
          width: 320,
          height: 320,
          child: AnimatedBuilder(
            animation: ringC,
            builder: (_, __) => CustomPaint(
              painter: _Ripple(t: ringC.value, color: pal.acc, level: active ? level : 0, active: st == _St.listen),
              child: Center(
                child: Press(
                  onTap: active ? _stop : _start,
                  scale: .94,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(pal.acc, Colors.white, .12)!, Color.lerp(pal.acc, Colors.black, .18)!]),
                      boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 36, offset: const Offset(0, 12))],
                    ),
                    child: CustomPaint(painter: _MicWave(level: active ? level : 0, t: ringC.value, color: pal.ink), child: Icon(ic(active ? 'mic' : 'refresh'), size: 52, color: pal.ink)),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(title, style: ts(19, w: FontWeight.w700, c: st == _St.listen ? pal.accText : pal.t1, num: true)),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(sub, textAlign: TextAlign.center, style: ts(13, c: pal.t2, h: 1.5))),
        if (st == _St.listen) ...[
          const SizedBox(height: 6),
          Text('点击停止识别', style: ts(12, c: pal.t3)),
        ],
        if (!active && st != _St.stopped) ...[
          const SizedBox(height: 18),
          Btn(st == _St.denied ? '重新申请权限' : '再试一次', icon: 'refresh', small: true, onTap: _start),
        ],
        const Spacer(flex: 4),
        Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 18),
          child: Text('只在本机计算声音指纹，不上传录音 · 识别结果来自网易云音乐', style: ts(11.5, c: pal.t3)),
        ),
      ]),
    );
  }

  Widget _hitView() {
    final app = context.app;
    final h = _hit;
    final t = h.track;
    final mq = MediaQuery.of(context);
    final liked = _liked(t);
    final others = [for (final (i, x) in hits.indexed) if (i != sel) (i, x)];
    final hue = (t.id.hashCode.abs() % 360).toDouble();
    return Stack(key: const ValueKey('hit'), children: [
      // 背景：封面放大模糊 + 压暗（网易云同款）
      Positioned.fill(child: BlurCover(hue: hue, variant: 2, url: t.cover, px: 16)),
      Positioned.fill(child: Container(color: const Color(0xB3101218))),
      Positioned.fill(
        child: ListView(
          padding: EdgeInsets.only(top: mq.padding.top + 64, bottom: mq.padding.bottom + 30),
          children: [
            Center(child: _Disc(spin: discC, url: t.cover, hue: hue, size: math.min(280.0, mq.size.width - 110))),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(22, w: FontWeight.w800, c: Colors.white)),
                    const SizedBox(height: 4),
                    Text([t.artist, if (t.album.isNotEmpty) t.album].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, c: const Color(0xB3FFFFFF))),
                  ]),
                ),
                IBtn(liked ? 'heartf' : 'heart', color: liked ? const Color(0xFFFF4D6D) : Colors.white, onTap: () => _toggleLike(t)),
                const SizedBox(width: 6),
                Press(
                  onTap: () => _play(t),
                  child: Container(width: 52, height: 52, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33FFFFFF)), child: Icon(ic('play'), color: Colors.white, size: 28)),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            _lyrics(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(child: Btn('从这里接着听', icon: 'play', onTap: () => _play(t, from: _songPos))),
                const SizedBox(width: 10),
                Expanded(child: Btn('再识别一首', icon: 'mic', kind: BtnKind.glass, onTap: _start)),
              ]),
            ),
            if (others.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.fromLTRB(24, 26, 24, 6), child: Text('其他识别结果', style: ts(14, w: FontWeight.w700, c: const Color(0xCCFFFFFF)))),
              for (final (i, x) in others) _otherRow(app, i, x),
            ],
          ],
        ),
      ),
    ]);
  }

  /// 三行歌词：上一句（淡）· 当前句（亮）· 下一句（淡），从识别到的位置开始按时间走。
  Widget _lyrics() {
    final lines = _lines;
    Widget line(String s, {bool cur = false}) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: ts(cur ? 16 : 13.5, w: cur ? FontWeight.w700 : FontWeight.w400, c: cur ? Colors.white : const Color(0x66FFFFFF)));
    Widget body;
    if (lines.isEmpty) {
      body = _lyricLoading
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white70)), const SizedBox(width: 8), Text('歌词加载中', style: ts(13.5, c: const Color(0xB3FFFFFF)))])
          : Text('暂无歌词', style: ts(13.5, c: const Color(0x80FFFFFF)));
    } else {
      final p = _songPos;
      var k = 0;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].t <= p) k = i;
      }
      body = AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        transitionBuilder: (ch, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: ch)),
        child: Column(key: ValueKey(k), children: [
          line(k > 0 ? lines[k - 1].text : ''),
          const SizedBox(height: 8),
          line(lines[k].text, cur: true),
          const SizedBox(height: 8),
          line(k + 1 < lines.length ? lines[k + 1].text : ''),
        ]),
      );
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: SizedBox(height: 86, child: Center(child: body)));
  }

  Widget _otherRow(AppState app, int i, AudioMatchHit x) {
    final t = x.track;
    final liked = _liked(t);
    return Press(
      onTap: () => _pick(i),
      hl: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 12, 6),
        child: Row(children: [
          Cover(hue: (t.id.hashCode.abs() % 360).toDouble(), variant: 2, size: 48, radius: 10, url: t.cover),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w600, c: Colors.white)),
              const SizedBox(height: 2),
              Text([t.artist, if (t.album.isNotEmpty) t.album].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: const Color(0x99FFFFFF))),
            ]),
          ),
          IBtn(liked ? 'heartf' : 'heart', color: liked ? const Color(0xFFFF4D6D) : const Color(0xCCFFFFFF), onTap: () => _toggleLike(t)),
          IBtn('play', color: const Color(0xCCFFFFFF), onTap: () => _play(t)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- 识别记录

  static final _history = _MatchHistory();

  Future<void> _openHistory(BuildContext context) async {
    final app = context.appRead;
    await _history.load(app);
    if (!context.mounted) return;
    showLSheet(context, title: '识别记录', sub: '只保存在本机', builder: (c) {
      final pal = c.pal;
      return StatefulBuilder(builder: (c, set) {
        final list = _history.items;
        if (list.isEmpty) {
          return Padding(padding: const EdgeInsets.all(30), child: Text('还没有识别过的歌', textAlign: TextAlign.center, style: ts(13.5, c: pal.t3)));
        }
        return Column(children: [
          for (final e in list)
            Press(
              hl: true,
              onTap: () {
                Navigator.of(c).pop();
                _play(e.track);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Tk.pad, 6, 8, 6),
                child: Row(children: [
                  Cover(hue: (e.track.id.hashCode.abs() % 360).toDouble(), variant: 2, size: 46, radius: 10, url: e.track.cover),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w600, c: pal.t1)),
                      Text('${e.track.artist} · ${_ago(e.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t3)),
                    ]),
                  ),
                  IBtn('play', color: pal.t2, onTap: () {
                    Navigator.of(c).pop();
                    _play(e.track);
                  }),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 8, Tk.pad, 0),
            child: Btn.sec('清空记录', icon: 'trash', block: true, onTap: () async {
              await _history.clear(app);
              set(() {});
            }),
          ),
        ]);
      });
    });
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// 本机识别记录（最多 50 条，同一首只留最近一次）。
class _MatchHistory {
  static const _k = 'audio_match.history.v1', _max = 50;
  final items = <({PTrack track, DateTime at})>[];
  bool _loaded = false;
  AppState? _app;

  Future<void> load(AppState app) async {
    _app = app;
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await app.net?.prefs.read(_k);
      if (raw == null || raw.isEmpty) return;
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final ct = CloudTrack.fromDesktop(Map<String, dynamic>.from(j['track'] as Map));
        final identity = ct.raw['identity'] is Map ? Map<String, dynamic>.from(ct.raw['identity'] as Map) : <String, dynamic>{'id': ct.songId};
        items.add((track: PTrack(platform: ct.platform, nativeId: ct.songId, title: ct.title, artist: ct.artist, album: ct.album, duration: ct.durationSec, cover: ct.cover, identity: identity), at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0)));
      }
    } catch (_) {}
  }

  Future<void> add(AppState app, AudioMatchHit h) async {
    await load(app);
    items.removeWhere((e) => e.track.id == h.track.id);
    items.insert(0, (track: h.track, at: DateTime.now()));
    if (items.length > _max) items.removeRange(_max, items.length);
    await _save();
  }

  Future<void> clear(AppState app) async {
    items.clear();
    await app.net?.prefs.delete(_k);
  }

  Future<void> _save() async {
    final p = _app?.net?.prefs;
    if (p == null) return;
    await p.write(_k, jsonEncode([for (final e in items) {'track': e.track.toCloud().toDesktop(), 'at': e.at.millisecondsSinceEpoch}]));
  }
}

/// 识别中的波纹：三层同心的柔色圆（随音量呼吸）+ 向外扩散的细圈。
class _Ripple extends CustomPainter {
  final double t, level;
  final Color color;
  final bool active;
  _Ripple({required this.t, required this.color, required this.level, required this.active});
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final amp = (level * 3).clamp(0.0, 1.0);
    final breathe = math.sin(t * math.pi * 2) * .5 + .5;
    // 底层三圈：越外越淡，音量大时整体张开
    for (var i = 2; i >= 0; i--) {
      final r = 74.0 + (i + 1) * 22 + (active ? breathe * 4 + amp * 10 * (i + 1) : 0.0);
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: .10 + (2 - i) * .07));
    }
    if (!active) return;
    // 扩散细圈
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      canvas.drawCircle(c, 70 + k * 92, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: (1 - k) * .45));
    }
  }

  @override
  bool shouldRepaint(_Ripple o) => o.t != t || o.level != level || o.active != active;
}

/// 麦克风按钮上的音量条（底部三道，随音量伸缩，像 QQ 音乐的「声波」）。
class _MicWave extends CustomPainter {
  final double level, t;
  final Color color;
  _MicWave({required this.level, required this.t, required this.color});
  @override
  void paint(Canvas canvas, Size s) {
    if (level <= 0) return;
    final amp = (level * 4).clamp(.15, 1.0);
    final p = Paint()
      ..color = color.withValues(alpha: .55)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final cx = s.width / 2;
    for (var i = 0; i < 3; i++) {
      final w = (34 - i * 10) * (.6 + amp * .4) * (1 + .08 * math.sin((t + i * .2) * math.pi * 2));
      final y = s.height * .78 + i * 6;
      canvas.drawLine(Offset(cx - w / 2, y), Offset(cx + w / 2, y), p);
    }
  }

  @override
  bool shouldRepaint(_MicWave o) => o.level != level || o.t != t;
}

/// 结果页唱片：黑胶纹路 + 中间封面，慢慢转。
class _Disc extends StatelessWidget {
  final Animation<double> spin;
  final String? url;
  final double hue, size;
  const _Disc({required this.spin, required this.url, required this.hue, required this.size});
  @override
  Widget build(BuildContext context) {
    final inner = size * .66;
    return Container(
      width: size + 24,
      height: size + 24,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x14FFFFFF)),
      alignment: Alignment.center,
      child: RotationTransition(
        turns: spin,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _Grooves(),
            child: Center(child: ClipOval(child: Cover(hue: hue, variant: 2, size: inner, radius: inner / 2, url: url))),
          ),
        ),
      ),
    );
  }
}

class _Grooves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0B0B0D));
    final g = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = const Color(0x1AFFFFFF);
    for (var x = r * .68; x < r - 3; x += 3.2) {
      canvas.drawCircle(c, x, g);
    }
    // 高光
    canvas.drawCircle(c, r, Paint()
      ..shader = SweepGradient(colors: const [Color(0x00FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)]).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  @override
  bool shouldRepaint(_Grooves o) => false;
}
