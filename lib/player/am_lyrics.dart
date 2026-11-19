// Apple Music 风格歌词（律动皮肤专用，Android / iOS 共用）。
//
// 与通用 LyricView 的区别：
// - 按「块」排版：本句 + 翻译为一块；没有翻译时，同段落且间隔 < 3s 的相邻两句合成一块。
// - 模糊只作用在「非当前块」：统一强度，不再按距离做多档模糊（那正是旧版看起来一团糟的原因）。
// - 手滑看词时全清晰；停手 1.3s 后自动恢复模糊；位置保持不动，点「回到当前」才回位。
// - 点块：块底出现半透明圆角底并渐隐，同时跳到块首时间。
// - 手滑方向回调给皮肤：往下看后面的词 → 收起控制台；往上看前面的词 → 唤起控制台。
//
// 性能：整块歌词是一个 CustomPainter，换歌 / 改字号才排版；播放中只改两个字——当前行填充宽度、
// 各行位移。模糊用文字自带的 MaskFilter（按档位缓存 TextPainter），不给每个块套 ImageFiltered。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../ui/kit.dart';

class AmLyricView extends StatefulWidget {
  /// 当前块中心所在高度比例。
  final double anchor;
  final EdgeInsets padding;

  /// 波浪漂浮（歌词设置里的「波浪漂浮」）。
  final bool wave;

  /// 点在歌词块之外的空白处。
  final VoidCallback? onBlankTap;

  /// 手滑方向：true = 往上看更早的词（向下拖），false = 往下看后面的词（向上拖）。
  final ValueChanged<bool>? onScrollUp;

  const AmLyricView({
    super.key,
    this.anchor = .3,
    this.padding = const EdgeInsets.symmetric(horizontal: 26),
    this.wave = false,
    this.onBlankTap,
    this.onScrollUp,
  });

  @override
  State<AmLyricView> createState() => _AmLyricViewState();
}

class _Block {
  final int index, first, last;
  final double start;
  const _Block(this.index, this.first, this.last, this.start);
}

/// 一行歌词的排版缓存：主句、翻译、以及三档模糊画笔。
class _Line {
  final String text, trans;
  final double top, height, mainH;
  final Map<int, TextPainter> blurMain = {};
  final Map<int, TextPainter> blurTrans = {};
  TextPainter? bright, dim, sharp, transCur;
  List<ui.LineMetrics>? metrics;
  _Line(this.text, this.trans, this.top, this.height, this.mainH);
}

class _AmLyricViewState extends State<AmLyricView>
    with TickerProviderStateMixin {
  /// 换行弹簧：每行延迟 46ms 依次追上。
  late final _spring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 720 + 46 * 9));

  /// 模糊强度 0..1：0 = 全清晰（手滑），1 = 非当前块模糊。
  late final _blurC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  /// 点击块的底色渐隐。
  late final _tapC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));

  /// 手滑惯性 / 回位。
  late final _fling = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  late final _waveC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800));

  late final Ticker _ticker = createTicker((_) => _frame());
  final _repaint = _Ping();

  AppState? _app;
  double _h = 0, _w = 0;

  int k = -1, prevK = -1;
  int _lyricsVersion = -1;
  String _styleKey = '';
  List<_Line> _lines = [];
  List<_Block> _blocks = [];
  final _lineBlock = <int>[];
  List<double> from = [], to = [];

  double manual = 0, _flingFrom = 0, _flingTo = 0;
  bool manualMode = false;
  bool? _lastUp;
  Timer? _blurTimer;

  int _tapBlock = -1;
  double progress = 0;

  @visibleForTesting
  int get layoutLines => _lines.length;

  @visibleForTesting
  final paintedLines = <int>[];

  @override
  void initState() {
    super.initState();
    if (widget.wave) _waveC.repeat();
    _fling.addListener(() {
      manual = ui.lerpDouble(
          _flingFrom, _flingTo, Curves.decelerate.transform(_fling.value))!;
      _repaint.ping();
    });
  }

  @override
  void didUpdateWidget(AmLyricView o) {
    super.didUpdateWidget(o);
    if (widget.wave && !_waveC.isAnimating) _waveC.repeat();
    if (!widget.wave) _waveC.stop();
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
      _frame();
    }
  }

  void _onApp() {
    _syncTicker();
    if (_app!.lyricsVersion != _lyricsVersion) setState(() {});
  }

  void _syncTicker() {
    final run = _app?.playing ?? false;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  void _onPos() {
    if (!_ticker.isActive) _frame();
  }

  void _frame() {
    if (!mounted || _lines.isEmpty || _h == 0 || lyrics.isEmpty) return;
    final app = _app!;
    final p = app.smoothPos + app.set.loff;
    final nk = app.lyricIndexAt(p).clamp(0, _lines.length - 1);
    if (nk != k) {
      if (manualMode) {
        // 用户正在自己翻歌词：只更新当前行（模糊/高亮），不把画面拽回去。
        prevK = k;
        k = nk;
      } else {
        _retarget(nk);
      }
    }
    progress = lyrics[nk].progressAt(p);
    _repaint.ping();
  }

  @override
  void dispose() {
    _app?.pos.removeListener(_onPos);
    _app?.removeListener(_onApp);
    _ticker.dispose();
    _spring.dispose();
    _blurC.dispose();
    _tapC.dispose();
    _fling.dispose();
    _waveC.dispose();
    _blurTimer?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  double _visual(int i) {
    if (to.isEmpty || i >= to.length || i >= from.length) return 0;
    final total = _spring.duration!.inMilliseconds.toDouble();
    final d = math.max(0, i - k).clamp(0, 9) * 46.0;
    final t = _spring.isAnimating || _spring.value > 0
        ? ((_spring.value * total - d) / 720).clamp(0.0, 1.0)
        : 1.0;
    final e = _app!.set.reduceMotion ? t : Tk.softSpring.transform(t);
    return ui.lerpDouble(from[i], to[i], e)!;
  }

  double lineY(int i) => _lines[i].top + _visual(i) + manual;

  double _wavePhase(int i) => _waveC.value * math.pi * 2 + i * 1.3;

  _Block? blockOf(int line) {
    if (line < 0 || line >= _lineBlock.length) return null;
    final bi = _lineBlock[line];
    return bi >= 0 && bi < _blocks.length ? _blocks[bi] : null;
  }

  // ---------------------------------------------------------------- 排版

  void _layout(double w, TextStyle main, TextStyle tr, bool trans, double gap) {
    _lines = [];
    _blocks = [];
    _lineBlock.clear();
    from = [];
    to = [];
    final n = lyrics.length;
    var y = 0.0;
    var i = 0;
    while (i < n) {
      final first = lyrics[i];
      final hasTrans = trans && first.trans.isNotEmpty;
      var last = i;
      if (!hasTrans && i + 1 < n) {
        final next = lyrics[i + 1];
        final nextHasTrans = trans && next.trans.isNotEmpty;
        // 同段落、间隔 < 3s、下一句本身没有翻译挂载 → 两句并成一块
        if (!nextHasTrans &&
            next.section == first.section &&
            (next.t - (first.t + first.d)) < 3) {
          last = i + 1;
        }
      }
      for (var j = i; j <= last; j++) {
        final l = lyrics[j];
        final tp = TextPainter(
            text: TextSpan(
                text: l.text, style: main.copyWith(color: Colors.white)),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left)
          ..layout(maxWidth: w);
        var h = tp.height;
        if (trans && l.trans.isNotEmpty) {
          final t2 = TextPainter(
              text: TextSpan(text: l.trans, style: tr),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left)
            ..layout(maxWidth: w);
          h += t2.height + 4;
        }
        _lines.add(_Line(l.text, l.trans, y, h, tp.height));
        _lineBlock.add(_blocks.length);
        y += h;
        if (j < last) y += gap; // 块内两句贴得近一点
      }
      _blocks.add(_Block(_blocks.length, i, last, first.t));
      y += gap + 20; // 块与块之间留白
      i = last + 1;
    }
    k = -1;
    prevK = -1;
    manual = 0;
    manualMode = false;
  }

  void _retarget(int nk) {
    if (nk < 0 || nk >= _lines.length) return;
    final off = _h * widget.anchor - (_lines[nk].top + _lines[nk].height / 2);
    final n = _lines.length;
    from = [for (var i = 0; i < n; i++) to.isEmpty ? off : _visual(i)];
    to = List.filled(n, off);
    prevK = k;
    k = nk;
    _spring.forward(from: 0);
    _repaint.ping();
  }

  // ---------------------------------------------------------------- 交互

  void _onDragStart(DragStartDetails _) {
    _blurTimer?.cancel();
    _fling.stop();
    _lastUp = null;
    setState(() => manualMode = true);
    _blurC.animateTo(0,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    manual = _clampManual(manual + d.delta.dy);
    _repaint.ping();
    if (d.delta.dy.abs() > 1) {
      final up = d.delta.dy > 0;
      if (up != _lastUp) {
        _lastUp = up;
        widget.onScrollUp?.call(up);
      }
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() > 60) {
      _flingFrom = manual;
      _flingTo = _clampManual(manual + v * .22);
      _fling.forward(from: 0);
    }
    _blurTimer?.cancel();
    _blurTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted)
        _blurC.animateTo(1,
            duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    });
  }

  double _clampManual(double v) {
    final contentH =
        _lines.isEmpty ? 0.0 : _lines.last.top + _lines.last.height;
    final min = math.min(0.0, _h - contentH - 40);
    final max = math.max(0.0, _h * .5);
    return v.clamp(min, max);
  }

  void _tapAt(double y) {
    for (var i = 0; i < _lines.length; i++) {
      final top = lineY(i);
      if (y >= top - 8 && y <= top + _lines[i].height + 8) {
        final b = blockOf(i);
        if (b == null) return;
        setState(() => _tapBlock = b.index);
        _tapC.forward(from: 0);
        Timer(const Duration(milliseconds: 360), () {
          if (mounted) setState(() => _tapBlock = -1);
        });
        _app!.seek(b.start + .05);
        toast('跳转到 ${fmtTime(b.start)}', 'lyric');
        _recenter();
        return;
      }
    }
    widget.onBlankTap?.call();
  }

  void _recenter() {
    if (!mounted) return;
    _flingFrom = manual;
    _flingTo = 0;
    _fling.forward(from: 0);
    setState(() => manualMode = false);
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.set;
    final fs = s.lfs;
    final main = ts(fs, w: FontWeight.w700, h: 1.26);
    final tr = ts(s.ltfs, w: FontWeight.w500, h: 1.28);
    return LayoutBuilder(builder: (context, cs) {
      final w = cs.maxWidth - widget.padding.horizontal;
      final key =
          '$fs|${s.ltfs}|${s.lgap}|${s.trans}|${s.glow}|${s.blur}|${s.reduceMotion}';
      if (w != _w ||
          _lines.isEmpty ||
          app.lyricsVersion != _lyricsVersion ||
          key != _styleKey) {
        _layout(w, main, tr, s.trans, s.lgap);
        _lyricsVersion = app.lyricsVersion;
        _styleKey = key;
        _w = w;
      }
      final hChanged = _h != cs.maxHeight;
      _h = cs.maxHeight;
      if (k < 0 || hChanged) {
        final p = app.smoothPos + s.loff;
        if (_lines.isNotEmpty) {
          k = -1;
          _retarget(app.lyricIndexAt(p).clamp(0, _lines.length - 1));
          _spring.value = 1;
          progress = lyrics.isEmpty ? 0 : lyrics[k].progressAt(p);
        }
      }
      if (_lines.isEmpty) {
        return Center(
            child: Text('暂无歌词', style: ts(15, c: const Color(0x66FFFFFF))));
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _tapAt(d.localPosition.dy),
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => _onDragEnd(DragEndDetails()),
        child: Stack(children: [
          Positioned.fill(
            child: ClipRect(
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent
                  ],
                  stops: [0, .14, .8, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AmPainter(
                        this,
                        main,
                        tr,
                        fs,
                        s.glow,
                        s.trans,
                        s.blur,
                        Listenable.merge(
                            [_repaint, _spring, _blurC, _tapC, _waveC])),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          if (manualMode)
            Positioned(
              right: 16,
              bottom: 10,
              child: Press(
                onTap: _recenter,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text('回到当前',
                      style: ts(12.5, w: FontWeight.w600, c: Colors.white)),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _AmPainter extends CustomPainter {
  final _AmLyricViewState st;
  final TextStyle main, tr;
  final double fs;
  final bool glow, trans, blurOn;
  _AmPainter(this.st, this.main, this.tr, this.fs, this.glow, this.trans,
      this.blurOn, Listenable repaint)
      : super(repaint: repaint);

  /// 三档：清晰 / 半糊 / 全糊。手滑时用 0，停手后回到 2。
  static const _alpha = [.78, .5, .34];
  static const _sigma = [0.0, .11, .2];

  TextPainter _mk(String text, TextStyle style, double maxW, {Paint? fg}) =>
      TextPainter(
        text: TextSpan(
            text: text,
            style: fg == null
                ? style
                : style.copyWith(foreground: fg, color: null)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      )..layout(maxWidth: maxW);

  TextPainter _variant(_Line l, int lvl, double w) {
    final level = lvl.clamp(0, 2);
    return l.blurMain.putIfAbsent(level, () {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: _alpha[level]);
      final sigma = _sigma[level] * fs;
      if (sigma > 0.1)
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
      return _mk(l.text, main, w, fg: paint);
    });
  }

  TextPainter _variantTrans(_Line l, int lvl, double w) {
    final level = lvl.clamp(0, 2);
    return l.blurTrans.putIfAbsent(level, () {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: _alpha[level] * .86);
      final sigma = _sigma[level] * fs * .7;
      if (sigma > 0.1)
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
      return _mk(l.trans, tr, w, fg: paint);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    st.paintedLines.clear();
    final lines = st._lines;
    final blocks = st._blocks;
    if (lines.isEmpty || blocks.isEmpty) return;
    final w = st._w;
    final left = st.widget.padding.left;
    final cur = st.k;
    final curBlock = st.blockOf(cur)?.index ?? -1;
    final wave = st.widget.wave && !st._app!.set.reduceMotion;
    final blurT = blurOn ? st._blurC.value : 0.0;
    final lvl = blurT < .25 ? 0 : (blurT < .7 ? 1 : 2);

    final sw = st._spring.duration!.inMilliseconds;
    final scaleT =
        Curves.easeOut.transform((st._spring.value * sw / 300).clamp(0.0, 1.0));
    final tapT = st._tapC.value;

    for (final b in blocks) {
      // 点击块底色（画在文字下面）
      if (b.index == st._tapBlock && tapT < 1) {
        final top = st.lineY(b.first) - 9;
        final bottom = st.lineY(b.last) + lines[b.last].height + 9;
        if (bottom > -20 && top < size.height + 20) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(left - 12, top, left + w + 12, bottom),
                const Radius.circular(14)),
            Paint()..color = Colors.white.withValues(alpha: .17 * (1 - tapT)),
          );
        }
      }
      for (var i = b.first; i <= b.last; i++) {
        final l = lines[i];
        var y = st.lineY(i);
        if (y + l.height < -50 || y > size.height + 50) continue;
        st.paintedLines.add(i);
        var x = left, rot = 0.0;
        if (wave && i != cur) {
          final ph = st._wavePhase(i);
          y += math.sin(ph) * 5;
          x += math.cos(ph * .8) * 5;
          rot = math.sin(ph) * .006;
        }
        final maxScale = st.widget.wave ? .03 : .02;
        final scale = i == cur
            ? 1 + maxScale * scaleT
            : i == st.prevK
                ? 1 + maxScale * (1 - scaleT)
                : 1.0;
        canvas.save();
        final pivot = Offset(x + w / 2, y + l.mainH / 2);
        canvas.translate(pivot.dx, pivot.dy);
        if (rot != 0) canvas.rotate(rot);
        if (scale != 1) canvas.scale(scale);
        canvas.translate(-pivot.dx, -pivot.dy);
        final o = Offset(x, y);

        final inCurrentBlock = b.index == curBlock;
        if (i == cur) {
          _paintCurrent(canvas, l, o, w);
        } else if (inCurrentBlock) {
          final tp = l.sharp ??= _mk(l.text,
              main.copyWith(color: Colors.white.withValues(alpha: .86)), w);
          tp.paint(canvas, o);
        } else {
          _variant(l, lvl, w).paint(canvas, o);
        }

        if (trans && l.trans.isNotEmpty) {
          final tpv = inCurrentBlock
              ? (l.transCur ??= _mk(l.trans,
                  tr.copyWith(color: Colors.white.withValues(alpha: .72)), w))
              : _variantTrans(l, lvl, w);
          tpv.paint(canvas, Offset(x, y + l.mainH + 4));
        }
        canvas.restore();
      }
    }
  }

  /// 当前行：暗色底 + 按已唱位置裁剪的亮色（逐字时间优先）。
  void _paintCurrent(Canvas canvas, _Line l, Offset o, double w) {
    final dim = l.dim ??= _mk(
        l.text, main.copyWith(color: Colors.white.withValues(alpha: .4)), w);
    final bright = l.bright ??= _mk(
        l.text,
        main.copyWith(
            color: Colors.white,
            shadows: glow
                ? [const Shadow(color: Color(0x8CFFFFFF), blurRadius: 14)]
                : null),
        w);
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
    final caretX =
        (c1.dy - c0.dy).abs() < 1 ? c0.dx + (c1.dx - c0.dx) * f : c0.dx;
    final caretY = c0.dy;
    final metrics = l.metrics ??= bright.computeLineMetrics();
    for (final m in metrics) {
      final top = m.baseline - m.ascent;
      final bottom = top + m.height;
      double right;
      if (caretY > top + m.height / 2) {
        right = m.left + m.width;
      } else if (caretY >= top - 1 && caretY < bottom) {
        right = caretX;
      } else {
        break;
      }
      if (right <= m.left) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(o.dx + m.left - 16, o.dy + top - 16,
          o.dx + right, o.dy + bottom + 16));
      bright.paint(canvas, o);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AmPainter o) => true;
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}
