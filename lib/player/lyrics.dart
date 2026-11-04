// 歌词引擎：瀑布弹簧切行（每行延迟 46ms，带过冲）、逐字填充 + 辉光、距离模糊、点按跳转、
// 手动拖动 → 「回到当前」+ 4s 自动回弹、波浪漂浮模式。所有带歌词的皮肤共用。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../ui/kit.dart';

class LyricView extends StatefulWidget {
  final double anchor; // 当前行中心所在高度比例
  final double? fontSize;
  final TextAlign align;
  final Color? fillColor;
  final bool wave, compact;
  final EdgeInsets padding;
  const LyricView({super.key, this.anchor = .36, this.fontSize, this.align = TextAlign.left, this.fillColor, this.wave = false, this.compact = false, this.padding = const EdgeInsets.symmetric(horizontal: 26)});
  @override
  State<LyricView> createState() => _LyricViewState();
}

/// 一行歌词的排版缓存。各种透明度 / 模糊程度的画笔按需创建，之后播放期间只画不排。
class _LineLay {
  final String text, trans;
  final double top, height, mainH;
  final TextPainter base; // 白色，用于测量和当前行的已唱部分
  final _variants = <int, TextPainter>{}; // 距离档位 → 画笔
  TextPainter? bright, dimCur, transCur, transDim;
  List<ui.LineMetrics>? metrics;
  _LineLay(this.text, this.trans, this.top, this.height, this.mainH, this.base);
}

// 实现说明（为什么不卡）：
// - 整块歌词是一个 CustomPainter，不是一列 Text 组件。换歌 / 改宽度 / 改样式时排版一次，播放中零排版。
// - 每帧只变两个量：当前行已唱宽度、各行的位移；由 Ticker 驱动重画，组件树不重建。
// - 逐字填充：先画未唱的暗色，再 clipRect 到已唱宽度画亮色（换行的长句按行分段），没有 ShaderMask 图层。
// - 远处行的「距离模糊」用文字自带的 MaskFilter，不再给每行套 ImageFiltered。
// - 进度用 AppState.smoothPos：引擎约 200ms 报一次，两次之间按时间往前推，填充是连续的。
class _LyricViewState extends State<LyricView> with TickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720 + 46 * 9));
  late final waveC = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  late final Ticker _ticker = createTicker((_) => _frame());
  final _repaint = _Ping();
  AppState? _app;
  double _h = 0, _w = 0;

  int k = -1, prevK = -1;
  int _lyricsVersion = -1;
  String _styleKey = '';
  List<double> from = [], to = [];
  List<_LineLay> lays = [];
  double manual = 0;
  bool manualMode = false;
  Timer? back;
  double progress = 0; // 当前行已唱比例

  /// 测试观测口：排版缓存覆盖的歌词行数（应恒等于 lyrics.length）。
  @visibleForTesting
  int get layoutLines => lays.length;

  /// 测试观测口：上一帧画出来的行号。
  @visibleForTesting
  final paintedLines = <int>[];

  @override
  void initState() {
    super.initState();
    if (widget.wave) waveC.repeat();
  }

  @override
  void didUpdateWidget(LyricView o) {
    super.didUpdateWidget(o);
    if (widget.wave && !waveC.isAnimating) waveC.repeat();
    if (!widget.wave) waveC.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = context.appRead;
    if (a != _app) {
      _app?.pos.removeListener(_onPos);
      _app?.removeListener(_onApp);
      _app = a
        ..pos.addListener(_onPos)
        ..addListener(_onApp);
      _syncTicker();
    }
  }

  void _onApp() => _syncTicker();

  /// 播放中逐帧刷新；暂停时只在进度变化（拖动 / 点歌词跳转）时刷新。
  void _syncTicker() {
    final run = _app?.playing ?? false;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  void _onPos() {
    if (!_ticker.isActive) _frame();
  }

  void _frame() {
    if (!mounted || lays.isEmpty || _h == 0) return;
    final app = _app!;
    final p = app.smoothPos + app.set.loff;
    final nk = app.lyricIndexAt(p).clamp(0, lays.length - 1);
    if (nk != k) _retarget(nk);
    progress = nk < lyrics.length ? lyrics[nk].progressAt(p) : 0;
    _repaint.ping();
  }

  @override
  void dispose() {
    _app?.pos.removeListener(_onPos);
    _app?.removeListener(_onApp);
    _ticker.dispose();
    c.dispose();
    waveC.dispose();
    back?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  double _visual(int i) {
    if (to.isEmpty || i >= to.length || i >= from.length) return 0;
    final total = c.duration!.inMilliseconds.toDouble();
    final d = math.max(0, i - k).clamp(0, 9) * 46.0;
    final t = c.isAnimating || c.value > 0 ? ((c.value * total - d) / 720).clamp(0.0, 1.0) : 1.0;
    final e = _app!.set.reduceMotion ? t : Tk.softSpring.transform(t);
    return ui.lerpDouble(from[i], to[i], e)!;
  }

  void _layout(double w, TextStyle main, TextStyle tr, bool trans, double gap) {
    lays = [];
    var y = 0.0;
    for (final l in lyrics) {
      final tp = TextPainter(text: TextSpan(text: l.text, style: main.copyWith(color: Colors.white)), textDirection: TextDirection.ltr, textAlign: widget.align)..layout(maxWidth: w);
      var h = tp.height;
      if (trans && l.trans.isNotEmpty) {
        final t2 = TextPainter(text: TextSpan(text: l.trans, style: tr), textDirection: TextDirection.ltr, textAlign: widget.align)..layout(maxWidth: w);
        h += t2.height + 4;
      }
      lays.add(_LineLay(l.text, l.trans, y, h, tp.height, tp));
      y += h + gap + 14;
    }
    from = [];
    to = [];
    k = -1;
    prevK = -1;
  }

  void _retarget(int nk) {
    if (nk < 0 || nk >= lays.length) return;
    final off = _h * widget.anchor - (lays[nk].top + lays[nk].height / 2);
    final n = lays.length;
    from = [for (var i = 0; i < n; i++) to.isEmpty ? off : _visual(i)];
    to = List.filled(n, off);
    prevK = k;
    k = nk;
    c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.set;
    final fs = widget.fontSize ?? s.lfs;
    final main = ts(fs, w: FontWeight.w800, h: 1.28);
    final tr = ts(s.ltfs, w: FontWeight.w500, h: 1.3);
    final fill = widget.fillColor ?? Colors.white;
    return LayoutBuilder(builder: (context, cs) {
      final w = cs.maxWidth - widget.padding.horizontal;
      final key = '$fs|${s.ltfs}|${s.lgap}|${s.trans}|${s.glow}|${s.blur}|${fill.toARGB32()}';
      if (w != _w || lays.isEmpty || app.lyricsVersion != _lyricsVersion || key != _styleKey) {
        _layout(w, main, tr, s.trans, s.lgap);
        _lyricsVersion = app.lyricsVersion;
        _styleKey = key;
        _w = w;
      }
      final hChanged = _h != cs.maxHeight;
      _h = cs.maxHeight;
      if (k < 0 || hChanged) {
        final p = app.smoothPos + s.loff;
        if (lays.isNotEmpty) {
          to = [];
          k = -1;
          _retarget(app.lyricIndexAt(p).clamp(0, lays.length - 1));
          c.value = 1;
          progress = lyrics.isEmpty ? 0 : lyrics[k].progressAt(p);
        }
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _tapAt(d.localPosition.dy),
        onVerticalDragStart: (_) {
          back?.cancel();
          setState(() => manualMode = true);
        },
        onVerticalDragUpdate: (d) {
          manual += d.delta.dy;
          _repaint.ping();
        },
        onVerticalDragEnd: (_) {
          back?.cancel();
          back = Timer(const Duration(seconds: 4), _recenter);
        },
        child: Stack(children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, .18, .72, 1]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _LyricPainter(this, main, tr, fill, s.glow, s.blur, s.trans, Listenable.merge([_repaint, c, waveC])),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          if (manualMode)
            Positioned(
              right: 16,
              bottom: 12,
              child: Press(
                onTap: _recenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(16)),
                  child: Text('回到当前', style: ts(12.5, w: FontWeight.w600, c: Colors.white)),
                ),
              ),
            ),
        ]),
      );
    });
  }

  double lineY(int i) => lays[i].top + _visual(i) + manual;

  void _tapAt(double y) {
    for (var i = 0; i < lays.length && i < lyrics.length; i++) {
      final top = lineY(i);
      if (y >= top - 6 && y <= top + lays[i].height + 6) {
        final l = lyrics[i];
        _app!.seek(l.t + .05);
        _recenter();
        toast('跳转到 ${fmtTime(l.t)}', 'lyric');
        return;
      }
    }
  }

  void _recenter() {
    back?.cancel();
    if (!mounted) return;
    setState(() {
      manual = 0;
      manualMode = false;
    });
  }
}

class _LyricPainter extends CustomPainter {
  final _LyricViewState st;
  final TextStyle main, tr;
  final Color fill;
  final bool glow, blur, trans;
  _LyricPainter(this.st, this.main, this.tr, this.fill, this.glow, this.blur, this.trans, Listenable repaint) : super(repaint: repaint);

  static const _alpha = [1.0, .44, .38, .32, .26, .2, .14];

  TextPainter _mk(String text, TextStyle style, double maxW) => TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textAlign: st.widget.align)..layout(maxWidth: maxW);

  /// 距离当前行 d 行时用的画笔：透明度随距离降低，近处 3 行带轻微模糊（文字自身的 MaskFilter）。
  TextPainter _variant(_LineLay l, int d, double w) {
    final b = d.clamp(1, 6);
    return l._variants.putIfAbsent(b, () {
      final paint = Paint()..color = Colors.white.withValues(alpha: _alpha[b]);
      if (blur && b <= 3) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, b * .55);
      return _mk(l.text, main.copyWith(color: null, foreground: paint), w);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    st.paintedLines.clear();
    final lays = st.lays;
    if (lays.isEmpty) return;
    final w = st._w;
    final left = st.widget.padding.left;
    final cur = st.k;
    final wave = st.widget.wave && !st._app!.set.reduceMotion;
    final center = st.widget.align == TextAlign.center;
    // 换行后 300ms 内当前行放大到 1.02、上一行缩回
    final sw = st.c.duration!.inMilliseconds;
    final scaleT = Curves.easeOut.transform((st.c.value * sw / 300).clamp(0.0, 1.0));
    for (var i = 0; i < lays.length; i++) {
      final l = lays[i];
      var y = st.lineY(i);
      if (y + l.height < -40 || y > size.height + 40) continue;
      st.paintedLines.add(i);
      final d = (i - cur).abs();
      var x = left, rot = 0.0;
      if (wave && i != cur) {
        final ph = st.waveC.value * math.pi * 2 + i * 1.3;
        y += math.sin(ph) * 6;
        x += math.cos(ph * .8) * 6;
        rot = math.sin(ph) * .007;
      }
      final maxScale = st.widget.wave ? .03 : .02;
      final scale = i == cur ? 1 + maxScale * scaleT : i == st.prevK ? 1 + maxScale * (1 - scaleT) : 1.0;
      canvas.save();
      final pivot = Offset(center ? x + w / 2 : x, y + l.mainH / 2);
      canvas.translate(pivot.dx, pivot.dy);
      if (rot != 0) canvas.rotate(rot);
      if (scale != 1) canvas.scale(scale);
      canvas.translate(-pivot.dx, -pivot.dy);
      final o = Offset(x, y);
      if (i == cur) {
        _paintCurrent(canvas, l, o, w);
      } else {
        _variant(l, d, w).paint(canvas, o);
      }
      if (trans && l.trans.isNotEmpty) {
        final tp = i == cur
            ? (l.transCur ??= _mk(l.trans, tr.copyWith(color: Colors.white.withValues(alpha: .78)), w))
            : (l.transDim ??= _mk(l.trans, tr.copyWith(color: Colors.white.withValues(alpha: .5)), w));
        tp.paint(canvas, Offset(x, y + l.mainH + 4));
      }
      canvas.restore();
    }
  }

  /// 当前行：先画未唱的暗色，再按已唱位置逐行裁剪画亮色。
  void _paintCurrent(Canvas canvas, _LineLay l, Offset o, double w) {
    final dim = l.dimCur ??= _mk(l.text, main.copyWith(color: Colors.white.withValues(alpha: .38)), w);
    final bright = l.bright ??= _mk(l.text, main.copyWith(color: fill, shadows: glow ? [Shadow(color: fill.withValues(alpha: .55), blurRadius: 12)] : null), w);
    dim.paint(canvas, o);
    final p = st.progress;
    if (p <= 0) return;
    if (p >= 1) {
      bright.paint(canvas, o);
      return;
    }
    final len = l.text.length;
    final at = p * len;
    final i0 = at.floor().clamp(0, len), i1 = (i0 + 1).clamp(0, len);
    final c0 = bright.getOffsetForCaret(TextPosition(offset: i0), Rect.zero);
    final c1 = bright.getOffsetForCaret(TextPosition(offset: i1), Rect.zero);
    final f = at - i0;
    final caretX = (c1.dy - c0.dy).abs() < 1 ? c0.dx + (c1.dx - c0.dx) * f : c0.dx;
    final caretY = c0.dy;
    final lines = l.metrics ??= bright.computeLineMetrics();
    for (final m in lines) {
      final top = m.baseline - m.ascent;
      final bottom = top + m.height;
      double right;
      if (caretY > top + m.height / 2) {
        right = m.left + m.width; // 已唱完的整行
      } else if (caretY >= top - 1 && caretY < bottom) {
        right = caretX;
      } else {
        break;
      }
      if (right <= m.left) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(o.dx + m.left - 16, o.dy + top - 16, o.dx + right, o.dy + bottom + 16));
      bright.paint(canvas, o);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LyricPainter o) => true;
}

/// 播放中逐帧重建 [builder]（配合 AppState.smoothPos 让填充连续）；暂停时只跟着进度变化重建。
class FrameBuilder extends StatefulWidget {
  final WidgetBuilder builder;
  const FrameBuilder({super.key, required this.builder});
  @override
  State<FrameBuilder> createState() => _FrameBuilderState();
}

class _FrameBuilderState extends State<FrameBuilder> with SingleTickerProviderStateMixin {
  late final Ticker _t = createTicker((_) => setState(() {}));
  AppState? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = context.app; // 依赖 AppScope：播放 / 暂停变化时会走到这里
    if (a != _app) {
      _app?.pos.removeListener(_onPos);
      _app = a..pos.addListener(_onPos);
    }
    if (a.playing && !_t.isActive) _t.start();
    if (!a.playing && _t.isActive) _t.stop();
  }

  void _onPos() {
    if (!_t.isActive && mounted) setState(() {});
  }

  @override
  void dispose() {
    _app?.pos.removeListener(_onPos);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// 3 行歌词（上一句 / 当前 / 下一句），用于唱片、声波、粒子、舞台等皮肤。
class Lyric3 extends StatelessWidget {
  final double size;
  final Color? fill;
  final bool stage;
  const Lyric3({super.key, this.size = 20, this.fill, this.stage = false});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return FrameBuilder(
      builder: (_) {
        if (lyrics.isEmpty) return const SizedBox.shrink(); // 换歌窗口期 / 空歌词
        final k = app.lyricIndex, p = app.lineProgress;
        final f = fill ?? Colors.white;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(k > 0 ? lyrics[k - 1].text : '', textAlign: TextAlign.center, style: ts(size * .72, w: FontWeight.w600, c: const Color(0x66FFFFFF))),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: Duration(milliseconds: stage ? 600 : 300),
            transitionBuilder: (ch, a) => stage
                ? SlideTransition(position: Tween(begin: const Offset(0, .6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Tk.spring)), child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: ch)))
                : FadeTransition(opacity: a, child: ch),
            child: ShaderMask(
              key: ValueKey(k),
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(colors: [f, f, const Color(0x61FFFFFF), const Color(0x61FFFFFF)], stops: [0, p, p, 1]).createShader(r),
              child: Text(lyrics[k].text, textAlign: TextAlign.center, style: ts(size, w: FontWeight.w800, c: Colors.white, h: 1.3)),
            ),
          ),
          if (app.set.trans) Padding(padding: const EdgeInsets.only(top: 4), child: Text(lyrics[k].trans, textAlign: TextAlign.center, style: ts(size * .58, c: const Color(0x99FFFFFF)))),
          const SizedBox(height: 8),
          Text(k + 1 < lyrics.length ? lyrics[k + 1].text : '', textAlign: TextAlign.center, style: ts(size * .72, w: FontWeight.w600, c: const Color(0x66FFFFFF))),
        ]);
      },
    );
  }
}

/// 歌词设置页顶部的预览。
class LyricPreview extends StatelessWidget {
  const LyricPreview({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app.set;
    final main = ts(s.lfs * .8, w: FontWeight.w800, c: Colors.white);
    Widget dim(String t) => Opacity(opacity: .4, child: s.blur ? ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2), child: Text(t, style: main)) : Text(t, style: main));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        dim(previewLyrics[5].text),
        SizedBox(height: s.lgap),
        if (s.roma) Text('ye hang de xing tu', style: ts(12, c: const Color(0x99FFFFFF))),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Colors.white, Color(0x61FFFFFF), Color(0x61FFFFFF)], stops: [0, .55, .55, 1]).createShader(r),
          child: Text(previewLyrics[6].text, style: main.copyWith(shadows: s.glow ? const [Shadow(color: Color(0x99FFFFFF), blurRadius: 12)] : null)),
        ),
        if (s.trans) Text(previewLyrics[6].trans, style: ts(s.ltfs, c: const Color(0xB3FFFFFF))),
        SizedBox(height: s.lgap),
        dim(previewLyrics[7].text),
      ]),
    );
  }
}

/// 只用来通知 CustomPainter 重画（ChangeNotifier.notifyListeners 是 protected）。
class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}
