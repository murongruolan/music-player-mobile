// 封面：按色相 + 变体生成渐变（原型 coverStyle 的 Canvas 版）。接口对接后可换成网络图片，
// 但保留本组件作为占位 / 加载失败的兜底。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../data/models.dart';

class Cover extends StatelessWidget {
  final double hue;
  final int variant;
  final double size;
  final double? width, height;
  final double radius;
  final Widget? child;
  final bool shadow;
  const Cover({super.key, required this.hue, this.variant = 0, this.size = 48, this.width, this.height, this.radius = 10, this.child, this.shadow = false});
  factory Cover.song(Song s, {double size = 48, double radius = 10, bool shadow = false, Widget? child}) =>
      Cover(hue: s.hue, variant: s.variant, size: size, radius: radius, shadow: shadow, child: child);
  factory Cover.pl(Playlist p, {double size = 140, double radius = 16, Widget? child}) =>
      Cover(hue: p.hue, variant: p.variant, size: size, radius: radius, child: child);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? (size > 0 ? size : double.infinity),
      height: height ?? (size > 0 ? size : double.infinity),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? [const BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 18))] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: CoverPainter(hue, variant),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

Offset _dirPts(Size s, double deg, bool start) {
  // CSS 线性渐变角度：0deg 向上，顺时针。
  final r = (deg - 90) * math.pi / 180;
  final dx = math.cos(r), dy = math.sin(r);
  final half = (s.width * dx.abs() + s.height * dy.abs()) / 2;
  final c = s.center(Offset.zero);
  return start ? c - Offset(dx, dy) * half : c + Offset(dx, dy) * half;
}

ui.Shader cssLinear(Size s, double deg, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.linear(_dirPts(s, deg, true), _dirPts(s, deg, false), colors, stops);

class CoverPainter extends CustomPainter {
  final double h;
  final int v;
  CoverPainter(this.h, this.v);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final a = hsl(h, .72, .62), b = hsl(h + 40, .62, .34), c = hsl(h + 320, .70, .14);
    final p = Paint();
    switch (v % 4) {
      case 0:
        p.shader = cssLinear(s, 140, [b, c]);
        canvas.drawRect(rect, p);
        final far = math.sqrt(s.width * s.width + s.height * s.height);
        p.shader = ui.Gradient.radial(Offset(s.width * .7, s.height * .75), far * .62, [a, a, a.withValues(alpha: 0)], [0, .3 / .62, 1]);
        canvas.drawRect(rect, p);
        p.shader = null;
        p.color = hsl(h, .9, .82);
        canvas.drawCircle(Offset(s.width * .3, s.height * .28), far * .13 * .72, p);
        break;
      case 1:
        p.shader = cssLinear(s, 160, [a, c]);
        canvas.drawRect(rect, p);
        p
          ..shader = null
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = hsl(h, .8, .7, .45);
        final o = Offset(s.width * .72, s.height * .78);
        final maxR = math.sqrt(math.pow(math.max(o.dx, s.width - o.dx), 2) + math.pow(math.max(o.dy, s.height - o.dy), 2));
        for (double r = 2.5; r < maxR + 13; r += 13) {
          canvas.drawCircle(o, r, p);
        }
        break;
      case 2:
        final cc = Offset(s.width * .62, s.height * .40);
        final start = (210 - 90) * math.pi / 180;
        p.shader = ui.Gradient.sweep(cc, [a, b, c, hsl(h, .8, .72), a], [0, .25, .5, .75, 1], TileMode.clamp, start, start + math.pi * 2);
        canvas.drawRect(rect, p);
        break;
      default:
        p.shader = cssLinear(s, 20, [b, c]);
        canvas.drawRect(rect, p);
        final far = math.sqrt(s.width * s.width + s.height * s.height);
        final g = hsl(h + 60, .8, .6, .7);
        p.shader = ui.Gradient.radial(Offset(s.width * .8, s.height * .85), far * .5, [g, g.withValues(alpha: 0)]);
        canvas.drawRect(rect, p);
        final t = hsl(h, .74, .66);
        p.shader = cssLinear(s, 162, [t, t, t.withValues(alpha: 0), t.withValues(alpha: 0)], [0, .38, .385, 1]);
        canvas.drawRect(rect, p);
    }
  }

  @override
  bool shouldRepaint(CoverPainter o) => o.h != h || o.v != v;
}

/// 封面取色：返回 4 个用于流光背景的颜色（替代 palette_generator）。
List<Color> coverColors(double h) => [hsl(h, .72, .55), hsl(h + 40, .62, .38), hsl(h + 320, .7, .3), hsl(h + 180, .5, .4)];
