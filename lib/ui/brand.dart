// 品牌：App 图标（竖琴 + 织女星，8 款）与登录流程的环境光背景。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/state.dart';

class AppIcon extends StatelessWidget {
  final String id;
  final double size;
  const AppIcon(this.id, {super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _IconPainter(id)));
}

/// 当前设置里选中的图标，可选漂浮动画。
class AppLogo extends StatefulWidget {
  final double size;
  final bool float;
  const AppLogo({super.key, this.size = 64, this.float = false});
  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      transitionBuilder: (ch, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: const Cubic(.3, 1.5, .5, 1)), child: RotationTransition(turns: Tween(begin: -.04, end: 0.0).animate(a), child: ch)),
      child: Container(
        key: ValueKey(context.app.appIcon),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.size * .23), boxShadow: [BoxShadow(color: const Color(0xFFF4D28A).withValues(alpha: .28), blurRadius: 30, offset: const Offset(0, 12))]),
        child: AppIcon(context.app.appIcon, size: widget.size),
      ),
    );
    if (!widget.float) return icon;
    return AnimatedBuilder(
      animation: c,
      child: icon,
      builder: (_, ch) => Transform.translate(offset: Offset(0, math.sin(c.value * math.pi * 2) * 5), child: Transform.rotate(angle: math.sin(c.value * math.pi * 2 + 1) * .03, child: ch)),
    );
  }
}

class _IconPainter extends CustomPainter {
  final String id;
  _IconPainter(this.id);

  Path _lyreStrokes() => Path()
    ..moveTo(31, 74)
    ..cubicTo(21, 55, 24, 36, 38, 27)
    ..moveTo(69, 74)
    ..cubicTo(79, 55, 76, 36, 62, 27);
  Path _bar() => Path()
    ..moveTo(33, 39)
    ..lineTo(67, 39);
  Path _base() => Path()
    ..moveTo(30, 74)
    ..quadraticBezierTo(50, 84, 70, 74);
  Path _strings() => Path()
    ..moveTo(44, 40)
    ..lineTo(44, 74)
    ..moveTo(50, 40)
    ..lineTo(50, 76)
    ..moveTo(56, 40)
    ..lineTo(56, 74);
  Path _star() => Path()
    ..moveTo(50, 9)
    ..lineTo(53, 17)
    ..lineTo(61, 20)
    ..lineTo(53, 23)
    ..lineTo(50, 31)
    ..lineTo(47, 23)
    ..lineTo(39, 20)
    ..lineTo(47, 17)
    ..close();

  void _lyre(Canvas c, Color stroke, Color star, {Shader? shader, double glow = 0}) {
    Paint p(double w) {
      final pt = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = stroke;
      if (shader != null) pt.shader = shader;
      if (glow > 0) pt.maskFilter = MaskFilter.blur(BlurStyle.solid, glow);
      return pt;
    }

    c.drawPath(_lyreStrokes(), p(7));
    c.drawPath(_bar(), p(5.5));
    c.drawPath(_base(), p(6.5));
    c.drawPath(_strings(), p(3));
    c.drawPath(_star(), Paint()..color = star);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(23));
    canvas.clipRRect(rr);
    final bg = Paint();
    switch (id) {
      case 'night':
        bg.shader = ui.Gradient.radial(const Offset(50, 10), 100, [const Color(0xFF2A2C3E), const Color(0xFF07080D)]);
        canvas.drawRRect(rr, bg);
        final sp = Paint()..color = const Color(0xAAFFFFFF);
        for (final o in const [Offset(18, 20), Offset(82, 16), Offset(76, 58), Offset(16, 62), Offset(88, 84)]) {
          canvas.drawCircle(o, 1.1, sp);
        }
        _lyre(canvas, const Color(0xFFFFF1C9), const Color(0xFFFFF1C9), shader: ui.Gradient.linear(const Offset(0, 20), const Offset(0, 85), [const Color(0xFFFFF1C9), const Color(0xFFC9A04A)]));
        break;
      case 'aurora':
        bg.shader = ui.Gradient.linear(Offset.zero, const Offset(100, 100), [const Color(0xFF6EE7C8), const Color(0xFF3D7BE0), const Color(0xFF7B4FD6)], [0, .55, 1]);
        canvas.drawRRect(rr, bg);
        _lyre(canvas, Colors.white, Colors.white);
        break;
      case 'vinyl':
        canvas.drawRRect(rr, bg..color = const Color(0xFF101114));
        final g = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9
          ..color = const Color(0xFF2A2C33);
        for (final r in const <double>[44, 40, 36, 32, 28, 24]) {
          canvas.drawCircle(const Offset(50, 50), r, g);
        }
        canvas.drawCircle(const Offset(50, 50), 20, Paint()..color = const Color(0xFFF4D28A));
        canvas.save();
        canvas.translate(50, 50);
        canvas.scale(.36);
        canvas.translate(-50, -50);
        _lyre(canvas, const Color(0xFF1B1508), const Color(0xFF1B1508));
        canvas.restore();
        break;
      case 'mono':
        canvas.drawRRect(rr, bg..color = const Color(0xFFF6F6F4));
        _lyre(canvas, const Color(0xFF111111), const Color(0xFF111111));
        break;
      case 'neon':
        canvas.drawRRect(rr, bg..color = const Color(0xFF0B0814));
        _lyre(canvas, const Color(0xFFFF5FD2), const Color(0xFF7DF9FF), glow: 3);
        _lyre(canvas, const Color(0xFFFF8FE0), const Color(0xFF7DF9FF));
        break;
      case 'glass':
        canvas.drawRRect(rr, bg..color = const Color(0xFF2B2E3D));
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(1, 1, 98, 98), const Radius.circular(22)),
            Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(100, 100), [const Color(0x8CFFFFFF), const Color(0x1FFFFFFF)]));
        _lyre(canvas, const Color(0xFFF4D28A), Colors.white);
        break;
      case 'pixel':
        canvas.drawRRect(rr, bg..color = const Color(0xFF1B1532));
        final px = Paint()..color = const Color(0xFFF4D28A);
        const pts = [[44, 12], [50, 6], [50, 12], [56, 12], [50, 18], [26, 30], [26, 36], [26, 42], [32, 48], [32, 54], [38, 60], [68, 30], [68, 36], [68, 42], [62, 48], [62, 54], [56, 60], [32, 30], [38, 30], [44, 30], [50, 30], [56, 30], [62, 30], [38, 66], [44, 72], [50, 72], [56, 66], [44, 36], [44, 42], [44, 48], [44, 54], [56, 36], [56, 42], [56, 48], [56, 54]];
        for (final q in pts) {
          canvas.drawRect(Rect.fromLTWH(q[0].toDouble(), q[1].toDouble(), 6, 6), px);
        }
        break;
      default: // gold
        bg.shader = ui.Gradient.radial(const Offset(32, 24), 90, [const Color(0xFFFFF4D6), const Color(0xFFF4D28A), const Color(0xFF9A6B12)], [0, .42, 1]);
        canvas.drawRRect(rr, bg);
        _lyre(canvas, const Color(0xFF1B1508), const Color(0xFF1B1508));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter o) => o.id != id;
}

/// 环境光：3 个大模糊光斑在近黑底上漂移呼吸（登录 / 注册 / 使用须知共用）。
class Ambient extends StatefulWidget {
  final Widget child;
  const Ambient({super.key, required this.child});
  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: Container(color: const Color(0xFF07080D))),
      Positioned.fill(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) => CustomPaint(painter: _AmbientPainter(c.value * 60, context.appRead.set.reduceMotion)),
        ),
      ),
      Positioned.fill(
        child: Container(
          decoration: const BoxDecoration(gradient: RadialGradient(radius: 1.1, colors: [Colors.transparent, Color(0xB3000000)], stops: [.45, 1])),
        ),
      ),
      Positioned.fill(child: widget.child),
    ]);
  }
}

class _AmbientPainter extends CustomPainter {
  final double t;
  final bool still;
  _AmbientPainter(this.t, this.still);
  @override
  void paint(Canvas canvas, Size s) {
    final blobs = [
      (const Color(0xFFF4D28A), 340.0, .15, .18, 13.0),
      (const Color(0xFFB79CFF), 300.0, .85, .42, 17.0),
      (const Color(0xFF8AB4FF), 280.0, .3, .78, 15.0),
    ];
    for (final (col, d, x, y, per) in blobs) {
      final k = still ? 0.0 : t / per * math.pi * 2;
      final o = Offset(s.width * x + math.sin(k) * 40, s.height * y + math.cos(k * .8) * 50);
      final r = d / 2 * (1.03 + math.sin(k * 1.3) * .09);
      canvas.drawCircle(o, r, Paint()
        ..color = col.withValues(alpha: .42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t;
}
