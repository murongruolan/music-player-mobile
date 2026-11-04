// 底部导航：9 种形态（液态玻璃 / 浮岛 / 胶囊 / 磨砂一体 / 经典 / 凹槽 / 程序坞 / 气泡 / 纯文字）。
// 指示器液态拉伸、图标微动画、按住拖动水滴、滚动收起。位置规格见 [NavGeom]。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

const navItems = [('compass', '发现'), ('search', '搜索'), ('sun', '每日'), ('library', '音乐库'), ('user', '我的')];

/// 每种形态的几何参数（基于 390×844 画布，bottom 已含 34 的 Home 指示条）。
class NavGeom {
  final double left, right, bottom, height, radius;
  final bool attached, centered;
  final double? width;
  final double miniL, miniR, miniB, miniR2;
  const NavGeom(this.left, this.right, this.bottom, this.height, this.radius, this.miniL, this.miniR, this.miniB, this.miniR2, {this.attached = false, this.centered = false, this.width});
  static NavGeom of(String bar) => switch (bar) {
        'island' => const NavGeom(12, 12, 28, 64, 32, 12, 12, 102, 20),
        'capsule' => const NavGeom(14, 90, 28, 62, 31, 14, 14, 100, 20),
        'frosted' => const NavGeom(0, 0, 0, 83, 0, 0, 0, 83, 22, attached: true),
        'classic' => const NavGeom(0, 0, 0, 83, 0, 8, 8, 91, 16, attached: true),
        'cutout' => const NavGeom(12, 12, 24, 64, 24, 12, 12, 126, 20),
        'dock' => const NavGeom(0, 0, 26, 62, 22, 24, 24, 98, 20, centered: true, width: 300),
        'bubble' => const NavGeom(14, 14, 26, 56, 28, 14, 14, 94, 28),
        'text' => const NavGeom(0, 0, 0, 78, 0, 8, 8, 86, 16, attached: true),
        _ => const NavGeom(14, 14, 26, 66, 33, 12, 12, 102, 20),
      };
}

class BottomNav extends StatefulWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const BottomNav({super.key, required this.tab, required this.onTab});
  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> with TickerProviderStateMixin {
  late final stretch = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  // 镜面高光：每 7s 扫一次、每次 1.4s，其余时间不产生帧（之前常驻循环会让底栏每帧重绘毛玻璃）。
  late final spec = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _specT;
  int from = 0;

  @override
  void initState() {
    super.initState();
    _specT = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted && context.appRead.bar == 'liquid' && !context.appRead.set.reduceMotion) spec.forward(from: 0);
    });
  }
  double? dragX; // 拖动水滴时的中心 x
  int? justTapped;

  @override
  void didUpdateWidget(BottomNav o) {
    super.didUpdateWidget(o);
    if (o.tab != widget.tab) {
      from = o.tab;
      stretch.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _specT?.cancel();
    stretch.dispose();
    spec.dispose();
    super.dispose();
  }

  List<int> get _tabs => context.appRead.bar == 'capsule' ? [0, 2, 3, 4] : [0, 1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final g = NavGeom.of(app.bar);
    final mq = MediaQuery.of(context);
    final adj = mq.padding.bottom - 34;
    final collapse = app.navMin && (app.bar == 'liquid' || app.bar == 'island');
    final sink = app.navMin && (app.bar == 'classic' || app.bar == 'frosted' || app.bar == 'text');
    final w = mq.size.width;
    final tabs = _tabs;
    final navW = collapse ? 58.0 : (g.width ?? (w - g.left - g.right));
    final left = g.centered ? (w - navW) / 2 : g.left;
    final bottom = g.attached ? 0.0 : math.max(10.0, g.bottom + adj);
    final height = g.attached ? math.max(56.0, g.height + adj) : (collapse ? 58.0 : g.height);

    Widget bar = AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Tk.out,
      width: navW,
      height: height,
      child: LayoutBuilder(builder: (_, cs) => _body(app, pal, tabs, cs.maxWidth, cs.maxHeight, collapse, g)),
    );

    final children = <Widget>[
      AnimatedPositioned(
        duration: const Duration(milliseconds: 420),
        curve: Tk.out,
        left: left,
        bottom: bottom - (sink ? 30 : 0),
        width: navW,
        height: height,
        child: bar,
      ),
    ];
    if (app.bar == 'capsule') {
      final on = widget.tab == 1;
      children.add(Positioned(
        right: 14,
        bottom: bottom,
        child: Press(
          onTap: () => widget.onTab(1),
          scale: .9,
          radius: BorderRadius.circular(31),
          child: Glass(
            radius: 31,
            color: on ? pal.acc : pal.glassStrong,
            shadow: [BoxShadow(color: on ? pal.accGlow : const Color(0x33000000), blurRadius: 20, offset: const Offset(0, 8))],
            child: SizedBox(width: 62, height: 62, child: Icon(ic('search'), color: on ? pal.ink : pal.t1)),
          ),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _body(AppState app, Pal pal, List<int> tabs, double navW, double h, bool collapse, NavGeom g) {
    final bar = app.bar;
    final n = tabs.length;
    final sel = math.max(0, tabs.indexOf(widget.tab));
    final fromI = math.max(0, tabs.indexOf(from));
    final padX = bar == 'dock' ? 10.0 : bar == 'cutout' ? 4.0 : bar == 'text' ? 6.0 : 0.0;
    final innerW = navW - padX * 2;
    final itemW = innerW / n;
    final topPad = g.attached ? 0.0 : 0.0;
    final itemH = g.attached ? (bar == 'text' ? 50.0 : 56.0) : h;

    if (collapse) {
      return Glass(
        radius: 29,
        color: bar == 'liquid' ? pal.glass : pal.glassStrong,
        child: Press(onTap: () => app.update(() => app.navMin = false), child: Center(child: Icon(ic(navItems[widget.tab].$1), color: pal.accText))),
      );
    }

    // ---------- 指示器几何 ----------
    Rect indRect(int i) {
      final x = padX + itemW * i;
      switch (bar) {
        case 'classic':
          return Rect.fromLTWH(x + itemW / 2 - 14, 0, 28, 3);
        case 'frosted':
          return Rect.fromLTWH(x + itemW / 2 - 28, 7, 56, 30);
        case 'island':
          return Rect.fromLTWH(x + 4, 8, itemW - 8, h - 16);
        case 'capsule':
          return Rect.fromLTWH(x + 4, 5, itemW - 8, h - 10);
        case 'cutout':
          return Rect.fromLTWH(x + itemW / 2 - 27, -29, 54, 54);
        case 'dock':
          return Rect.fromLTWH(x + itemW / 2 - 3, h - 11, 6, 6);
        case 'bubble':
          return Rect.fromLTWH(x + 4, 2, itemW - 8, 48 + 4);
        case 'text':
          return Rect.fromLTWH(x + itemW / 2 - 9, 38, 18, 3);
        default:
          return Rect.fromLTWH(x + 4, 5, itemW - 8, h - 10);
      }
    }

    Widget indicator = AnimatedBuilder(
      animation: stretch,
      builder: (_, __) {
        final a = indRect(fromI), b = indRect(sel);
        var t = stretch.isAnimating || stretch.value < 1 ? stretch.value : 1.0;
        if (stretch.status == AnimationStatus.dismissed) t = 1;
        double l, wd, sy;
        if (app.set.reduceMotion || bar == 'cutout' || bar == 'dock' || bar == 'text' || bar == 'classic') {
          final e = Tk.softSpring.transform(t);
          l = ui.lerpDouble(a.left, b.left, e)!;
          wd = ui.lerpDouble(a.width, b.width, e)!;
          sy = 1;
        } else {
          // 液态拉伸：前沿先冲向目标、后沿随后跟上，两条边都单调前进，中途不停顿；
          // 移动中纵向轻微压扁，到达时一次很小的回弹。
          final fwd = b.left >= a.left;
          final lead = Curves.easeOutCubic.transform((t / .7).clamp(0.0, 1.0));
          final trail = Curves.easeInOutCubic.transform(((t - .08) / .92).clamp(0.0, 1.0));
          final double left, right;
          if (fwd) {
            right = ui.lerpDouble(a.right, b.right, lead)!;
            left = ui.lerpDouble(a.left, b.left, trail)!;
          } else {
            left = ui.lerpDouble(a.left, b.left, lead)!;
            right = ui.lerpDouble(a.right, b.right, trail)!;
          }
          l = left;
          wd = math.max(b.width * .6, right - left);
          sy = 1 - .12 * math.sin(math.pi * math.min(1, t / .85));
          if (t > .85) sy += .035 * math.sin((t - .85) / .15 * math.pi);
        }
        var rect = Rect.fromLTWH(l, b.top, wd, b.height);
        var sx = 1.0;
        if (dragX != null) {
          rect = Rect.fromCenter(center: Offset(dragX!.clamp(padX + itemW / 2, navW - padX - itemW / 2), b.center.dy), width: b.width, height: b.height);
          sx = 1.14;
          sy = 1.2;
        }
        return Positioned.fromRect(
          rect: rect,
          child: Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(sx, sy, 1), child: _indicatorDeco(bar, pal, rect.height)),
        );
      },
    );

    // ---------- 图标 ----------
    final row = Row(children: [
      for (var k = 0; k < n; k++) Expanded(child: _item(app, pal, tabs[k], tabs[k] == widget.tab, itemW, itemH, bar)),
    ]);

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: padX),
      child: SizedBox(height: itemH, child: row),
    );

    final stack = Stack(clipBehavior: Clip.none, children: [
      if (bar != 'bubble' && bar != 'dock') indicator,
      if (bar == 'bubble')
        for (var k = 0; k < n; k++)
          Positioned(left: padX + itemW * k + 4, top: 2, width: itemW - 8, height: 52, child: Glass(radius: 26, color: pal.glassStrong, child: const SizedBox())),
      if (bar == 'bubble') indicator,
      Positioned(left: 0, right: 0, top: topPad, child: content),
      if (bar == 'dock') indicator,
    ]);

    final drag = (bar == 'liquid' || bar == 'island' || bar == 'capsule')
        ? GestureDetector(
            onHorizontalDragStart: (d) => setState(() => dragX = d.localPosition.dx),
            onHorizontalDragUpdate: (d) => setState(() => dragX = d.localPosition.dx),
            onHorizontalDragEnd: (_) {
              final i = (((dragX ?? 0) - padX) / itemW).floor().clamp(0, n - 1);
              setState(() => dragX = null);
              if (tabs[i] != widget.tab) widget.onTab(tabs[i]);
            },
            child: stack,
          )
        : stack;

    switch (bar) {
      case 'classic':
      case 'text':
        return Container(
          decoration: BoxDecoration(color: pal.bgElev, border: Border(top: BorderSide(color: pal.line))),
          child: Align(alignment: Alignment.topCenter, child: SizedBox(height: itemH, child: drag)),
        );
      case 'frosted':
        return ClipRect(
          child: backdrop(
            context,
            ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13),
            Container(color: reduceBlur(context) ? pal.bgElev : pal.glassStrong, child: Align(alignment: Alignment.topCenter, child: SizedBox(height: itemH, child: drag))),
          ),
        );
      case 'bubble':
        return drag;
      case 'cutout':
        return CustomPaint(
          painter: _CutoutPainter(indRect(sel).center.dx, pal, stretch, indRect(fromI).center.dx),
          child: drag,
        );
      case 'liquid':
        return Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(33), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 12))]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(33),
            child: backdrop(
              context,
              ui.ImageFilter.compose(outer: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6), inner: const ColorFilter.matrix(_saturate)),
              CustomPaint(
                foregroundPainter: _LiquidRim(spec, pal.dark),
                child: Container(color: reduceBlur(context) ? pal.bgElev : pal.dark ? const Color(0x8A14151E) : const Color(0xA6FFFFFF), child: drag),
              ),
            ),
          ),
        );
      default:
        return Glass(
          radius: g.radius,
          color: bar == 'dock' ? pal.glass : pal.glassStrong,
          shadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 10))],
          child: drag,
        );
    }
  }

  Widget _indicatorDeco(String bar, Pal pal, double h) {
    switch (bar) {
      case 'classic':
        return Container(decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 8)]));
      case 'text':
        return Container(decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(2)));
      case 'frosted':
        return Container(decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(15)));
      case 'island':
        return Container(decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(h / 2)));
      case 'capsule':
      case 'bubble':
      case 'cutout':
        return Container(decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(h / 2), boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 18, offset: const Offset(0, 6))]));
      case 'dock':
        return Container(decoration: BoxDecoration(color: pal.acc, shape: BoxShape.circle, boxShadow: [BoxShadow(color: pal.acc, blurRadius: 8)]));
      default: // liquid 水滴：顶部径向高光 + 内阴影 + 呼吸
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h / 2),
            gradient: RadialGradient(center: const Alignment(0, -1.2), radius: 1.3, colors: [
              Colors.white.withValues(alpha: pal.dark ? .24 : .52),
              Colors.white.withValues(alpha: pal.dark ? .06 : .18),
            ]),
            border: Border.all(color: Colors.white.withValues(alpha: pal.dark ? .18 : .6)),
            boxShadow: [BoxShadow(color: pal.accGlow.withValues(alpha: .24), blurRadius: 16)],
          ),
        );
    }
  }

  Widget _item(AppState app, Pal pal, int tab, bool on, double w, double h, String bar) {
    final (icon, label) = navItems[tab];
    final inkOn = bar == 'capsule' || bar == 'bubble' || bar == 'cutout';
    final color = on ? (inkOn ? pal.ink : pal.accText) : pal.t2;
    final showText = !(bar == 'dock' || bar == 'bubble') && !(bar == 'island' && !on) && !(app.navMin && (bar == 'classic' || bar == 'frosted'));
    final iconW = bar == 'text'
        ? const SizedBox()
        : _IconAnim(
            key: ValueKey('$tab-$on'),
            tab: tab,
            play: on && justTapped == tab,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 460),
              curve: const Cubic(.3, 1.4, .5, 1),
              offset: bar == 'cutout' && on ? const Offset(0, -1.25) : (bar == 'dock' && on ? const Offset(0, -.12) : Offset.zero),
              child: Icon(ic(icon), size: bar == 'dock' ? 26 : 23, color: color),
            ),
          );
    Widget inner;
    if (bar == 'island' && on) {
      inner = Center(child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [iconW, const SizedBox(width: 5), Text(label, maxLines: 1, style: ts(12.5, w: FontWeight.w700, c: color))]))));
    } else if (bar == 'text') {
      inner = Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 300), curve: Tk.spring, style: ts(on ? 15.5 : 14, w: on ? FontWeight.w800 : FontWeight.w500, c: on ? pal.t1 : pal.t2), child: Text(label)));
    } else {
      inner = Column(mainAxisAlignment: bar == 'cutout' ? MainAxisAlignment.end : MainAxisAlignment.center, children: [
        iconW,
        if (showText) ...[
          const SizedBox(height: 3),
          AnimatedOpacity(duration: Tk.fast, opacity: bar == 'cutout' && on ? 0 : 1, child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: ts(10.5, w: FontWeight.w600, c: color))),
        ],
        if (bar == 'cutout') const SizedBox(height: 9),
      ]);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        haptic(context);
        setState(() => justTapped = tab);
        widget.onTab(tab);
      },
      child: SizedBox(height: h, child: inner),
    );
  }
}

const _saturate = <double>[
  1.6, -.3, -.3, 0, 8, //
  -.3, 1.6, -.3, 0, 8,
  -.3, -.3, 1.6, 0, 8,
  0, 0, 0, 1, 0,
];

/// 液态玻璃的折射边缘（上亮下暗）+ 每 7s 一道镜面高光。
class _LiquidRim extends CustomPainter {
  final Animation<double> a;
  final bool dark;
  _LiquidRim(this.a, this.dark) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height / 2));
    canvas.drawRRect(
        rr.deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height), [Colors.white.withValues(alpha: dark ? .32 : .8), Colors.white.withValues(alpha: .04), Colors.black.withValues(alpha: .12)], [0, .5, 1]));
    final t = a.value;
    if (t > 0 && t < 1) {
      final x = -s.width * .3 + (s.width * 1.6) * Curves.easeInOut.transform(t);
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(
          Rect.fromLTWH(x, 0, s.width * .25, s.height),
          Paint()..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + s.width * .25, 0), [Colors.transparent, Colors.white.withValues(alpha: dark ? .16 : .4), Colors.transparent], [0, .5, 1]));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LiquidRim o) => o.dark != dark || o.a != a;
}

/// 凹槽：底栏在选中圆正下方挖出凹口，凹口随指示器一起滑动。
class _CutoutPainter extends CustomPainter {
  final double x, fromX;
  final Pal pal;
  final Animation<double> anim;
  _CutoutPainter(this.x, this.pal, this.anim, this.fromX) : super(repaint: anim);
  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.status == AnimationStatus.dismissed ? 1.0 : Tk.softSpring.transform(anim.value);
    final cx = ui.lerpDouble(fromX, x, t)! + 4;
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(24)));
    final hole = Path()..addOval(Rect.fromCircle(center: Offset(cx, -2), radius: 34));
    final p = Path.combine(PathOperation.difference, body, hole);
    canvas.drawShadow(p, Colors.black, 10, false);
    canvas.drawPath(p, Paint()..color = pal.dark ? const Color(0xF0181922) : const Color(0xF5FFFFFF));
  }

  @override
  bool shouldRepaint(_CutoutPainter o) => o.x != x || o.pal != pal;
}

/// 图标微动画：发现 指南针转入；搜索 摆动；每日 旋入；音乐库 倾斜；我的 小跳。
class _IconAnim extends StatefulWidget {
  final int tab;
  final bool play;
  final Widget child;
  const _IconAnim({super.key, required this.tab, required this.play, required this.child});
  @override
  State<_IconAnim> createState() => _IconAnimState();
}

class _IconAnimState extends State<_IconAnim> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  @override
  void initState() {
    super.initState();
    if (widget.play) c.forward();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (_, ch) {
          if (!c.isAnimating) return ch!;
          final t = c.value, d = math.sin(t * math.pi) * (1 - t);
          switch (widget.tab) {
            case 0:
              return Transform.rotate(angle: (1 - Tk.softSpring.transform(t)) * -math.pi, child: ch);
            case 1:
              return Transform.rotate(angle: math.sin(t * math.pi * 4) * .25 * (1 - t), child: ch);
            case 2:
              return Transform.rotate(angle: (1 - Curves.easeOutBack.transform(t)) * math.pi * .8, child: Transform.scale(scale: .8 + .2 * t, child: ch));
            case 3:
              return Transform.rotate(angle: -d * .5, child: ch);
            default:
              return Transform.translate(offset: Offset(0, -d * 10), child: ch);
          }
        },
      );
}
