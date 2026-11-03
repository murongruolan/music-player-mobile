// 粒子舞台：桌面端 3D 点云预设的移动端精简版（Canvas，2600 点）——星系 / 事件视界 / 全息地球 / 陀螺核心。
// 单指拖动 360° 旋转；「朝向相机」的光环在屏幕空间绘制，任何角度都正对镜头。
// 正式版建议改用 FragmentProgram 复用桌面端 GLSL（docs/design/fx-presets/presets.three.vert.glsl）。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';

class _Fx {
  static final rnd = () {
    var a = 1234567;
    double r() => (a = (a * 16807) % 2147483647) / 2147483647;
    return List.generate(2600, (_) => [r(), r(), r(), r()]);
  }();
}

class ParticleView extends StatefulWidget {
  final String preset;
  final bool interactive;
  final double cyFrac;
  final bool animate;
  const ParticleView({super.key, required this.preset, this.interactive = true, this.cyFrac = .4, this.animate = true});
  @override
  State<ParticleView> createState() => _ParticleViewState();
}

class _ParticleViewState extends State<ParticleView> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(days: 1));
  @override
  void initState() {
    super.initState();
    if (widget.animate) c.forward();
  }

  double yaw = .3, pitch = .32;
  bool dragging = false;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    if (!widget.animate) {
      return RepaintBoundary(child: CustomPaint(painter: _PPainter(widget.preset, 3, .4, .32, 20, false, app.song.hue, pal.acc, .5), size: Size.infinite));
    }
    final view = AnimatedBuilder(
      animation: c,
      builder: (_, __) {
        final t = c.lastElapsedDuration == null ? 0.0 : c.lastElapsedDuration!.inMicroseconds / 1e6;
        if (!dragging && widget.interactive && !app.set.reduceMotion) yaw += .05 / 60;
        return CustomPaint(painter: _PPainter(widget.preset, t, yaw, pitch, app.pos.value, app.playing, app.song.hue, pal.acc, widget.interactive ? widget.cyFrac : .5), size: Size.infinite);
      },
    );
    if (!widget.interactive) return view;
    return GestureDetector(
      onPanStart: (_) => dragging = true,
      onPanUpdate: (d) {
        yaw += d.delta.dx * .008;
        pitch = (pitch + d.delta.dy * .008).clamp(-1.4, 1.4);
      },
      onPanEnd: (_) => dragging = false,
      child: view,
    );
  }
}

class _PPainter extends CustomPainter {
  final String preset;
  final double t, yaw, pitch, pos, hue, cyF;
  final bool playing;
  final Color acc;
  _PPainter(this.preset, this.t, this.yaw, this.pitch, this.pos, this.playing, this.hue, this.acc, this.cyF);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF05060A));
    final beatPh = (pos * 112 / 60) % 1;
    final beat = playing ? math.exp(-beatPh * 6) : 0.0;
    final bass = playing ? .35 + .4 * beat : .1;
    final cy = math.cos(yaw), sy = math.sin(yaw), cp = math.cos(pitch), sp = math.sin(pitch);
    final f = math.min(w, h) * 1.05, cx0 = w / 2, cy0 = h * cyF;
    final cols = [hsl(hue, .75, .66), acc, const Color(0xFFFFF4DE)];
    final paints = [for (final c in cols) Paint()..blendMode = BlendMode.plus..color = c];
    List<double>? proj(double x, double y, double z) {
      final x1 = cy * x + sy * z, z1 = -sy * x + cy * z, y1 = cp * y - sp * z1, z2 = sp * y + cp * z1;
      final d = z2 + 8;
      final k = f / d;
      return [cx0 + x1 * k, cy0 - y1 * k, k, z2];
    }

    final o = proj(0, 0, 0)!;
    void dot(double x, double y, double z, int ci, double a, [double sz = 1]) {
      final p = proj(x, y, z)!;
      if (p[3] < -7) return;
      final size = math.max(1.0, sz * p[2] * .03);
      final pt = paints[ci]..color = cols[ci].withValues(alpha: math.min(1, math.max(0, a * 1.5)));
      canvas.drawRect(Rect.fromLTWH(p[0], p[1], size, size), pt);
    }

    final tt = t * (playing ? 1 : .25), front = beatPh * 4;
    final R = _Fx.rnd;
    for (var i = 0; i < R.length; i++) {
      final r1 = R[i][0], r2 = R[i][1], r3 = R[i][2], r4 = R[i][3];
      switch (preset) {
        case 'disk':
          if (i < 2000) {
            final r = 1.15 + math.pow(r1, .75) * 2.6;
            final th = r2 * 6.283 + tt * .9 * math.pow(r, -1.5);
            final x = math.cos(th) * r, z = math.sin(th) * r, y = (r3 - .5) * .05 * r;
            final p = proj(x, y, z)!;
            final dd = math.sqrt(math.pow(p[0] - o[0], 2) + math.pow(p[1] - o[1], 2));
            if (p[3] > 0 && dd < 1.08 * o[2]) continue;
            final heat = 1 - math.min(1, (r - 1.15) / 2);
            dot(x, y, z, heat > .55 ? 2 : heat > .25 ? 1 : 0, (.25 + .55 * heat) * (1 + bass * heat) + math.exp(-(r - 1.15 - front * .6).abs() * 3) * beat * .5);
          } else {
            final ph = r2 * 6.283;
            final ring = i > 2420;
            final rr = (ring ? 1.08 + (r1 - .5) * .02 : 1.25 + math.pow(r1, 2) * .6) * o[2];
            final up = math.sin(ph) * (sp == 0 ? 1 : sp.sign) > 0 ? 1.0 : .35;
            final flat = ring ? 1.0 : .92;
            final a = ring ? .8 * (1 + beat) : .5 * up * (1 - r1 * .6);
            canvas.drawRect(Rect.fromLTWH(o[0] + math.cos(ph) * rr, o[1] - math.sin(ph) * rr * flat, 1.8, 1.8), paints[2]..color = cols[2].withValues(alpha: math.min(1, a)));
          }
          break;
        case 'globe':
          final yy = r1 * 2 - 1, an = r2 * 6.283 + tt * .1, q = math.sqrt(1 - yy * yy), x = q * math.cos(an), z = q * math.sin(an);
          final rad = 2 * (1 + bass * .04);
          final land = math.sin(3 * x + 1) * math.sin(4 * yy + .5) * math.sin(3 * z + 2) + math.sin(7 * x + z * 5) * .3;
          final back = (sp * yy + cp * (-sy * x + cy * z)) > 0;
          final city = math.pow(math.sin(i * 12.9 + (tt * 7).floor()).abs(), 40) * 3;
          if (land > .08) {
            dot(x * rad, yy * rad, z * rad, city > .5 ? 2 : 0, (back ? .12 : .6) + city * .4);
          } else if (((yy * 6 + 6.5) % 1 - .5).abs() < .03 || ((r2 * 24 + .5) % 1 - .5).abs() < .03) {
            dot(x * rad, yy * rad, z * rad, 1, back ? .06 : .3);
          } else {
            final k = 1.04 + r3 * .12;
            dot(x * rad * k, yy * rad * k, z * rad * k, 0, .05);
          }
          if (i < 260) {
            final u = i / 260 * 6.283, ys = math.sin(tt * .4) * .9, rr = math.sqrt(1 - ys * ys) * rad * 1.02;
            dot(math.cos(u) * rr, ys * rad, math.sin(u) * rr, 1, .55 + beat);
          }
          break;
        case 'gyro':
          if (i < 360) {
            final yy = r1 * 2 - 1, an = r2 * 6.283, q = math.sqrt(1 - yy * yy), rr = .5 * (1 + bass * .3) * (.7 + .3 * r3);
            dot(q * math.cos(an) * rr, yy * rr, q * math.sin(an) * rr, 2, .5 + beat * .4);
            continue;
          }
          final k = i % 4, rad = 1.2 + k * .5, u = r1 * 6.283 + tt * (.25 + .1 * k) * (k.isOdd ? -1 : 1);
          if (((r1 * 6 + k * .37) % 1) <= .08) continue;
          final x = math.cos(u) * rad, y = (r2 - .5) * .14, z = math.sin(u) * rad;
          final ang = (tt * (.3 + .13 * k) + beat * .5) * (k.isOdd ? -1 : 1) + k, ca = math.cos(ang), sa = math.sin(ang);
          final y2 = y * ca - z * sa, z2 = y * sa + z * ca;
          final b = k * .7, cb = math.cos(b), sb = math.sin(b);
          final chase = math.pow((((r1 * 2 - tt * (.5 + .2 * k)) % 1) + 1) % 1, 20) * 2;
          dot(x * cb - y2 * sb, x * sb + y2 * cb, z2, chase > .4 ? 2 : (k.isOdd ? 1 : 0), .35 + chase);
          break;
        default: // galaxy
          if (i < 320) {
            final yy = r1 * 2 - 1, an = r2 * 6.283, q = math.sqrt(1 - yy * yy), rr = math.pow(r3, 1.8) * .9 * (1 + bass * .15);
            dot(q * math.cos(an) * rr, yy * rr * .6, q * math.sin(an) * rr, 2, .5 + beat * .3);
            continue;
          }
          final r = .4 + math.pow(r1, .85) * 3.8, arm = i % 2, spd = r2 + r3 - 1, inArm = r4 > .28;
          final th = (inArm ? arm * math.pi + math.log(r) * 2.3 + spd * (.6 + .1 * r) : r2 * 6.283) + tt * .3 / (.5 + .45 * r);
          final ring = math.exp(-(r - front).abs() * 2) * beat;
          dot(math.cos(th) * r, (r3 - .5) * .16 * math.exp(-r * .2), math.sin(th) * r, inArm && spd.abs() < .25 ? 2 : (inArm ? 0 : 1), (inArm ? .55 : .25) * (1 - r / 5) + ring * .6);
      }
    }
  }

  @override
  bool shouldRepaint(_PPainter o) => true;
}
