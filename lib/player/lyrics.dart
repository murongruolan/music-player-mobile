// 歌词引擎：瀑布弹簧切行（每行延迟 46ms，带过冲）、逐字填充 + 辉光、距离模糊、点按跳转、
// 手动拖动 → 「回到当前」+ 4s 自动回弹、波浪漂浮模式。所有带歌词的皮肤共用。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

class _LyricViewState extends State<LyricView> with TickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720 + 46 * 9));
  // 波浪漂浮只在 wave 模式下运行；之前常驻循环会让每一行歌词每帧重建。
  late final waveC = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  AppState? _app;
  double _h = 0;

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
      _app = a..pos.addListener(_onPos);
    }
  }

  // 只有换行时才重建整块歌词；行内逐字进度由当前行自己的监听器刷新。
  void _onPos() {
    if (!mounted || _h == 0 || tops.isEmpty) return;
    final nk = _app!.lyricIndex;
    if (nk != k) setState(() => _retarget(nk, _h));
  }
  int k = -1;
  List<double> from = [], to = [];
  double manual = 0;
  bool manualMode = false;
  Timer? back;
  List<double> tops = [], hs = [];
  double lastW = 0;

  @override
  void dispose() {
    _app?.pos.removeListener(_onPos);
    c.dispose();
    waveC.dispose();
    back?.cancel();
    super.dispose();
  }

  double _visual(int i) {
    if (to.isEmpty || i >= to.length) return 0;
    final total = c.duration!.inMilliseconds.toDouble();
    final d = math.max(0, i - k).clamp(0, 9) * 46.0;
    final t = c.isAnimating || c.value > 0 ? ((c.value * total - d) / 720).clamp(0.0, 1.0) : 1.0;
    final e = context.appRead.set.reduceMotion ? t : Tk.softSpring.transform(t);
    return ui.lerpDouble(from[i], to[i], e)!;
  }

  void _layout(double w, TextStyle main, TextStyle tr, bool trans, double gap) {
    tops = [];
    hs = [];
    var y = 0.0;
    for (final l in lyrics) {
      final tp = TextPainter(text: TextSpan(text: l.text, style: main), textDirection: TextDirection.ltr, textAlign: widget.align)..layout(maxWidth: w);
      var h = tp.height;
      if (trans) {
        final t2 = TextPainter(text: TextSpan(text: l.trans, style: tr), textDirection: TextDirection.ltr, textAlign: widget.align)..layout(maxWidth: w);
        h += t2.height + 4;
      }
      tops.add(y);
      hs.add(h);
      y += h + gap + 14;
    }
  }

  void _retarget(int nk, double viewH) {
    final anchorY = viewH * widget.anchor;
    final off = anchorY - (tops[nk] + hs[nk] / 2);
    final n = lyrics.length;
    from = [for (var i = 0; i < n; i++) to.isEmpty ? off : _visual(i)];
    to = List.filled(n, off);
    k = nk;
    c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.set;
    final fs = widget.fontSize ?? s.lfs;
    final main = ts(fs, w: FontWeight.w800, h: 1.28);
    final tr = ts(s.ltfs, w: FontWeight.w500, h: 1.3);
    return LayoutBuilder(builder: (context, cs) {
      final w = cs.maxWidth - widget.padding.horizontal;
      if (w != lastW || tops.isEmpty) {
        _layout(w, main, tr, s.trans, s.lgap);
        lastW = w;
        to = [];
        k = -1;
      }
      _h = cs.maxHeight;
      return Builder(
        builder: (_) {
          final nk = app.lyricIndex;
          if (nk != k) _retarget(nk, cs.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              back?.cancel();
              setState(() => manualMode = true);
            },
            onVerticalDragUpdate: (d) => setState(() => manual += d.delta.dy),
            onVerticalDragEnd: (_) {
              back?.cancel();
              back = Timer(const Duration(seconds: 4), _recenter);
            },
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, .18, .72, 1]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: AnimatedBuilder(
                animation: Listenable.merge([c, waveC]),
                builder: (_, __) => Stack(clipBehavior: Clip.hardEdge, children: [
                  for (var i = 0; i < lyrics.length; i++)
                    if (_visible(i, cs.maxHeight)) _line(context, i, nk, main, tr, pal),
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
              ),
            ),
          );
        },
      );
    });
  }

  bool _visible(int i, double h) {
    final y = tops[i] + _visual(i) + manual;
    return y + hs[i] > -40 && y < h + 40;
  }

  void _recenter() {
    back?.cancel();
    if (!mounted) return;
    setState(() {
      manual = 0;
      manualMode = false;
    });
  }

  Widget _line(BuildContext context, int i, int cur, TextStyle main, TextStyle tr, Pal pal) {
    final app = context.appRead;
    final s = app.set;
    final l = lyrics[i];
    final d = (i - cur).abs();
    final isCur = i == cur;
    var y = tops[i] + _visual(i) + manual;
    var x = 0.0, rot = 0.0;
    if (widget.wave && !isCur && !s.reduceMotion) {
      final ph = waveC.value * math.pi * 2 + i * 1.3;
      y += math.sin(ph) * 6;
      x = math.cos(ph * .8) * 6;
      rot = math.sin(ph) * .007;
    }
    final fill = widget.fillColor ?? Colors.white;
    Widget text = Text(l.text, textAlign: widget.align, style: main.copyWith(color: Colors.white));
    if (isCur) {
      final plain = text;
      final glowText = s.glow ? RepaintBoundary(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: Text(l.text, textAlign: widget.align, style: main.copyWith(color: fill)))) : null;
      text = ValueListenableBuilder<double>(
        valueListenable: app.pos,
        builder: (_, __, ___) {
          final lp = app.lineProgress;
          final fillText = ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(colors: [fill, fill, Colors.white.withValues(alpha: .38), Colors.white.withValues(alpha: .38)], stops: [0, lp, lp, 1]).createShader(r),
            child: plain,
          );
          if (glowText == null) return fillText;
          return Stack(children: [
            Opacity(opacity: .5 * lp, child: glowText),
            Transform.translate(offset: Offset(0, -2.5 * lp), child: fillText),
          ]);
        },
      );
    }
    Widget body = Column(crossAxisAlignment: widget.align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
      if (s.roma && isCur) Text('ye hang de xing tu', style: ts(12.5, c: const Color(0x99FFFFFF))),
      text,
      if (s.trans) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.trans, textAlign: widget.align, style: tr.copyWith(color: Colors.white.withValues(alpha: isCur ? .78 : .5)))),
    ]);
    if (!isCur && s.blur && d <= 3) {
      body = RepaintBoundary(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: d * .55, sigmaY: d * .55), child: body));
    }
    return Positioned(
      left: widget.padding.left + x,
      right: widget.padding.right - x,
      top: y,
      child: GestureDetector(
        onTap: () {
          app.seek(l.t + .05);
          _recenter();
          toast('跳转到 ${fmtTime(l.t)}', 'lyric');
        },
        child: Transform.rotate(
          angle: rot,
          child: AnimatedScale(
            scale: isCur ? (widget.wave ? 1.03 : 1.02) : 1,
            duration: const Duration(milliseconds: 300),
            alignment: widget.align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
            child: AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: isCur ? 1 : math.max(.14, .5 - d * .06), child: body),
          ),
        ),
      ),
    );
  }
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
    return ValueListenableBuilder<double>(
      valueListenable: app.pos,
      builder: (_, __, ___) {
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
        dim(lyrics[5].text),
        SizedBox(height: s.lgap),
        if (s.roma) Text('ye hang de xing tu', style: ts(12, c: const Color(0x99FFFFFF))),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Colors.white, Color(0x61FFFFFF), Color(0x61FFFFFF)], stops: [0, .55, .55, 1]).createShader(r),
          child: Text(lyrics[6].text, style: main.copyWith(shadows: s.glow ? const [Shadow(color: Color(0x99FFFFFF), blurRadius: 12)] : null)),
        ),
        if (s.trans) Text(lyrics[6].trans, style: ts(s.ltfs, c: const Color(0xB3FFFFFF))),
        SizedBox(height: s.lgap),
        dim(lyrics[7].text),
      ]),
    );
  }
}
