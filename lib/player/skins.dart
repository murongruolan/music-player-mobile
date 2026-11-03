// 播放器皮肤（15 套）：律动 · 待机 · 粒子 · 声波 · 唱片 · 磁带 · 胶片 · 像素 · 舞台 · 写真 · 霓虹 · 终端 · 杂志 · 表盘 · 极简。
// 所有循环动效随暂停停下，恢复时从停下的位置继续。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../main.dart' show overlayStyle;
import '../widgets/sheets.dart';
import '../pages/settings.dart';
import 'lyrics.dart';
import 'particles.dart';
import 'player.dart';

class SkinHost extends StatelessWidget {
  final String skin;
  const SkinHost({super.key, required this.skin});
  @override
  Widget build(BuildContext context) {
    final w = switch (skin) {
      'standby' => const StandbySkin(),
      'particles' => const ParticlesSkin(),
      'pulse' => const PulseSkin(),
      'vinyl' => const VinylSkin(),
      'cassette' => const CassetteSkin(),
      'film' => const FilmSkin(),
      'pixel' => const PixelSkin(),
      'stage' => const StageSkin(),
      'poster' => const PosterSkin(),
      'neon' => const NeonSkin(),
      'terminal' => const TerminalSkin(),
      'magazine' => const MagazineSkin(),
      'dial' => const DialSkin(),
      'minimal' => const MinimalSkin(),
      _ => const SpringSkin(),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: KeyedSubtree(key: ValueKey(skin), child: w));
  }
}

/// 播放时持续旋转、暂停时停在原位。
class Spin extends StatefulWidget {
  final Widget child;
  final Duration period;
  final bool on;
  const Spin({super.key, required this.child, this.period = const Duration(seconds: 7), required this.on});
  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: widget.period);
  @override
  void initState() {
    super.initState();
    if (widget.on) c.repeat();
  }

  @override
  void didUpdateWidget(Spin o) {
    super.didUpdateWidget(o);
    if (widget.on && !c.isAnimating) c.repeat();
    if (!widget.on) c.stop();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: c, child: widget.child);
}

/// 每帧重建（跟随播放进度 / 节拍）。
class Beat extends StatelessWidget {
  final Widget Function(BuildContext, double beat, double pos) builder;
  const Beat({super.key, required this.builder});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ValueListenableBuilder<double>(valueListenable: app.pos, builder: (c, p, _) => builder(c, app.playing ? app.beat() : 0, p));
  }
}

/// 帧驱动（不依赖播放进度，用于闪烁、颗粒等）。
class Ticker2 extends StatefulWidget {
  final Widget Function(BuildContext, double t) builder;
  const Ticker2({super.key, required this.builder});
  @override
  State<Ticker2> createState() => _Ticker2State();
}

class _Ticker2State extends State<Ticker2> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, builder: (ctx, _) => widget.builder(ctx, (c.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6));
}

/// 封面左右滑切歌：跟手平移 + 轻微旋转（0.02°/px），松手切歌，新封面从反方向弹入。
class SwipeCover extends StatefulWidget {
  final Widget child;
  const SwipeCover({super.key, required this.child});
  @override
  State<SwipeCover> createState() => _SwipeCoverState();
}

class _SwipeCoverState extends State<SwipeCover> with SingleTickerProviderStateMixin {
  double dx = 0;
  int dir = 0;
  late final inC = AnimationController(vsync: this, duration: const Duration(milliseconds: 460))..value = 1;
  @override
  void dispose() {
    inC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appRead;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => dx += d.delta.dx),
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (dx.abs() > 70 || v.abs() > 600) {
          dir = (dx < 0 || v < 0) ? 1 : -1;
          dir > 0 ? app.next() : app.prev();
          inC.forward(from: 0);
        }
        setState(() => dx = 0);
      },
      child: AnimatedBuilder(
        animation: inC,
        child: widget.child,
        builder: (_, ch) {
          final t = Tk.softSpring.transform(inC.value);
          final off = dx + (1 - t) * 90 * dir;
          return Opacity(opacity: inC.value.clamp(0, 1), child: Transform.translate(offset: Offset(off, 0), child: Transform.rotate(angle: dx * .02 * math.pi / 180, child: Transform.scale(scale: .9 + .1 * t, child: ch))));
        },
      ),
    );
  }
}

// ============================ 律动（Apple Music 风格，默认） ============================
class SpringSkin extends StatefulWidget {
  const SpringSkin({super.key});
  @override
  State<SpringSkin> createState() => _SpringSkinState();
}

class _SpringSkinState extends State<SpringSkin> {
  String view = 'cover';
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    return LayoutBuilder(builder: (context, cs) {
      final W = cs.maxWidth, H = cs.maxHeight;
      final big = math.min(334.0, W - 56);
      final small = view != 'cover';
      const dur = Duration(milliseconds: 620);
      const curve = Cubic(.3, 1.2, .5, 1);
      const bottomH = 262.0;
      return Stack(children: [
        Positioned(top: 6, left: 0, right: 0, child: Center(child: GestureDetector(onTap: () => Navigator.of(context).pop(), child: Container(width: 38, height: 5, decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(3)))))),
        AnimatedPositioned(
          duration: dur,
          curve: curve,
          left: small ? 24 : (W - big) / 2,
          top: small ? 28 : 44,
          width: small ? 58 : big,
          height: small ? 58 : big,
          child: SwipeCover(
            child: AnimatedScale(
              scale: app.playing || small ? 1 : .82,
              duration: const Duration(milliseconds: 520),
              curve: Tk.spring,
              child: Hero(tag: 'cover', child: Cover.song(s, size: 0, radius: small ? 10 : 18, shadow: true)),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: dur,
          curve: curve,
          left: small ? 24 + 58 + 12 : 28,
          right: 14,
          top: small ? 28 : H - bottomH - 70,
          height: 58,
          child: Row(children: [
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Marquee(s.title, style: ts(small ? 17 : 20, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 2),
                Text(s.artist, maxLines: 1, style: ts(small ? 14 : 17, c: const Color(0xA6FFFFFF))),
              ]),
            ),
            HeartBtn(app.cur, size: 24, offColor: const Color(0xB3FFFFFF)),
            Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0x26FFFFFF), shape: BoxShape.circle), child: IBtn('more', size: 32, iconSize: 18, color: Colors.white, onTap: () => openSongMore(context, app.cur, '', dark: true))),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 28 + 58 + 14,
          bottom: bottomH,
          child: IgnorePointer(
            ignoring: !small,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 360),
              opacity: small ? 1 : 0,
              child: view == 'queue' ? _inlineQueue(context) : (small ? LyricView(wave: app.amWave == 'wave', anchor: .3) : const SizedBox()),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottomH,
          child: Column(children: [
            const ProgressBar(track: 7, trackDrag: 12),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IBtn('prev', color: Colors.white, size: 64, iconSize: 44, onTap: app.prev),
              const PlayButton(size: 84, bg: Colors.transparent, fg: Colors.white),
              IBtn('next', color: Colors.white, size: 64, iconSize: 44, onTap: app.next),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(children: [
                const Icon(Icons.volume_mute_rounded, color: Color(0x99FFFFFF), size: 18),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: LSlider(value: app.vol, min: 0, max: 1, color: Colors.white, onChanged: (v) => app.update(() => app.vol = v)))),
                const Icon(Icons.volume_up_rounded, color: Color(0x99FFFFFF), size: 18),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _tog('lyric', view == 'lyrics', () => setState(() => view = view == 'lyrics' ? 'cover' : 'lyrics')),
                IBtn('cast', color: app.castDev != null ? context.pal.acc : const Color(0xB3FFFFFF), onTap: () => openCast(context, dark: true)),
                _tog('queue', view == 'queue', () => setState(() => view = view == 'queue' ? 'cover' : 'queue')),
              ]),
            ),
          ]),
        ),
      ]);
    });
  }

  Widget _tog(String icon, bool on, VoidCallback f) => Press(
        onTap: f,
        scale: .88,
        child: AnimatedContainer(
          duration: Tk.base,
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: on ? const Color(0x33FFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Icon(ic(icon), color: on ? Colors.white : const Color(0xB3FFFFFF), size: 22),
        ),
      );

  Widget _inlineQueue(BuildContext context) {
    final app = context.app;
    final i = app.queue.indexOf(app.cur);
    final next = [...app.queue.skip(i + 1), ...app.queue.take(i)];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 16, 6),
        child: Row(children: [
          Expanded(child: Text('接下来播放', style: ts(15, w: FontWeight.w700, c: Colors.white))),
          _chip(app.mode == 'shuffle', 'shuffle', () => app.update(() => app.mode = app.mode == 'shuffle' ? 'loop' : 'shuffle')),
          const SizedBox(width: 8),
          _chip(app.mode == 'one', 'repeat1', () => app.update(() => app.mode = app.mode == 'one' ? 'loop' : 'one')),
        ]),
      ),
      Expanded(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, .85, 1]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final (k, id) in next.indexed)
              Rise(
                k,
                Press(
                  onTap: () => app.play(id),
                  child: SizedBox(
                    height: 56,
                    child: Row(children: [
                      const SizedBox(width: 24),
                      Cover.song(songs[id], size: 42, radius: 8),
                      const SizedBox(width: 12),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[id].title, style: ts(14.5, w: FontWeight.w600, c: Colors.white)), Text(songs[id].artist, style: ts(12, c: const Color(0x8CFFFFFF)))])),
                      const Icon(Icons.drag_handle_rounded, color: Color(0x66FFFFFF)),
                      const SizedBox(width: 20),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _chip(bool on, String icon, VoidCallback f) => Press(
        onTap: f,
        child: AnimatedContainer(duration: Tk.base, width: 40, height: 30, decoration: BoxDecoration(color: on ? Colors.white : const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(9)), child: Icon(ic(icon), size: 18, color: on ? Colors.black : Colors.white)),
      );
}

// ============================ 通用骨架布局 ============================
Widget skeleton({required Widget middle, Widget? info, bool aux = true, Widget? lyric, double gap = 14}) => Column(children: [
      const PlayerTopBar(),
      Expanded(child: Center(child: middle)),
      if (lyric != null) ...[lyric, SizedBox(height: gap)],
      info ?? const SongInfo(),
      const SizedBox(height: 14),
      const ProgressBar(),
      const SizedBox(height: 6),
      const MainControls(),
      if (aux) ...[const SizedBox(height: 10), const AuxRow()],
      const SizedBox(height: 10),
    ]);

// ============================ 唱片 ============================
class VinylSkin extends StatelessWidget {
  const VinylSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final spin = app.playing && app.set.vinylSpin && !app.set.reduceMotion;
    return skeleton(
      middle: SizedBox(
        width: 330,
        height: 320,
        child: Stack(children: [
          Positioned(
            left: 10,
            top: 14,
            child: Spin(
              on: spin,
              child: SizedBox(
                width: 300,
                height: 300,
                child: CustomPaint(painter: _DiscPainter(), child: Center(child: ClipOval(child: Cover.song(app.song, size: 124, radius: 62)))),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedRotation(
              turns: (app.playing ? -6 : -30) / 360,
              duration: const Duration(milliseconds: 700),
              curve: Tk.out,
              alignment: const Alignment(.55, -.75),
              child: const SizedBox(width: 120, height: 210, child: CustomPaint(painter: _ArmPainter())),
            ),
          ),
        ]),
      ),
      lyric: const Lyric3(size: 16),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D0E12));
    final g = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = const Color(0x1AFFFFFF);
    for (var k = 66.0; k < r - 4; k += 3.2) {
      canvas.drawCircle(c, k, g);
    }
    canvas.drawCircle(c, r, Paint()..shader = SweepGradient(colors: const [Colors.transparent, Color(0x22FFFFFF), Colors.transparent, Colors.transparent, Color(0x1AFFFFFF), Colors.transparent], stops: const [0, .1, .2, .5, .6, .7]).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r - 1, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF26282F));
  }

  @override
  bool shouldRepaint(_DiscPainter o) => false;
}

class _ArmPainter extends CustomPainter {
  const _ArmPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final pivot = Offset(s.width * .78, s.height * .12);
    canvas.drawCircle(pivot, 16, Paint()..color = const Color(0xFF9CA0AD));
    canvas.drawCircle(pivot, 8, Paint()..color = const Color(0xFF4A4D57));
    final arm = Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFC9CCD6);
    final mid = Offset(s.width * .74, s.height * .72);
    canvas.drawLine(pivot, mid, arm);
    canvas.drawLine(mid, Offset(s.width * .46, s.height * .92), arm);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width * .42, s.height * .94), width: 26, height: 16), const Radius.circular(4)), Paint()..color = const Color(0xFF2B2D34));
  }

  @override
  bool shouldRepaint(_ArmPainter o) => false;
}

// ============================ 声波 ============================
class PulseSkin extends StatelessWidget {
  const PulseSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return skeleton(
      middle: SizedBox(
        width: 340,
        height: 340,
        child: Stack(alignment: Alignment.center, children: [
          Ticker2(builder: (c, t) => Beat(builder: (c, b, p) => CustomPaint(size: const Size(340, 340), painter: _PulsePainter(app.playing ? t : 0, b, pal.acc)))),
          Spin(period: const Duration(seconds: 24), on: app.playing, child: ClipOval(child: Cover.song(app.song, size: 210, radius: 105))),
        ]),
      ),
      lyric: const Lyric3(size: 16),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double t, beat;
  final Color c;
  _PulsePainter(this.t, this.beat, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final o = s.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final k = ((t + i * .85) % 2.6) / 2.6;
      canvas.drawCircle(o, 105 + k * 60, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = c.withValues(alpha: (1 - k) * .55));
    }
    final bar = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final a = i / 24 * math.pi * 2 - math.pi / 2;
      final env = 1 - (((i % 12) - 6).abs() / 6) * .6;
      final h = 8 + 26 * env * (.35 + .65 * beat) * (.6 + .4 * math.sin(t * 6 + i));
      final p0 = o + Offset(math.cos(a), math.sin(a)) * 118;
      bar.color = Color.lerp(c, Colors.white, i / 24)!.withValues(alpha: .85);
      canvas.drawLine(p0, p0 + Offset(math.cos(a), math.sin(a)) * h, bar);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter o) => true;
}

// ============================ 粒子 ============================
class ParticlesSkin extends StatelessWidget {
  const ParticlesSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return Stack(children: [
      Positioned.fill(child: ParticleView(preset: app.particle)),
      Column(children: [
        const PlayerTopBar(),
        const Spacer(),
        const IgnorePointer(child: Lyric3(size: 20)),
        const SizedBox(height: 18),
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), children: [
            for (final (k, n) in const [('galaxy', '星系'), ('disk', '事件视界'), ('globe', '全息地球'), ('gyro', '陀螺核心')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Press(
                  onTap: () => app.update(() => app.particle = k),
                  child: AnimatedContainer(
                    duration: Tk.base,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: app.particle == k ? pal.acc : const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(17)),
                    child: Text(n, style: ts(13, w: FontWeight.w600, c: app.particle == k ? pal.ink : Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        const SongInfo(),
        const SizedBox(height: 14),
        const ProgressBar(),
        const SizedBox(height: 6),
        const MainControls(),
        const SizedBox(height: 10),
        const AuxRow(),
        const SizedBox(height: 10),
      ]),
    ]);
  }
}

// ============================ 舞台 ============================
class StageSkin extends StatefulWidget {
  const StageSkin({super.key});
  @override
  State<StageSkin> createState() => _StageSkinState();
}

class _StageSkinState extends State<StageSkin> {
  bool show = false;
  Timer? t;
  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => show = !show);
        t?.cancel();
        if (show) {
          t = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() => show = false);
          });
        }
      },
      child: Stack(children: [
        Positioned.fill(child: Container(color: const Color(0xB8000000))),
        Column(children: [
          const PlayerTopBar(),
          Expanded(
            child: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: app.pos,
                builder: (_, __, ___) {
                  final k = app.lyricIndex;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: pal.acc.withValues(alpha: .6)), borderRadius: BorderRadius.circular(12)),
                      child: Text('${lyrics[k].section} · ${(k + 1).toString().padLeft(2, '0')}/${lyrics.length}', style: ts(12, w: FontWeight.w700, c: pal.acc, ls: 1, num: true)),
                    ),
                    const SizedBox(height: 26),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Lyric3(size: 38, fill: pal.acc, stage: true)),
                  ]);
                },
              ),
            ),
          ),
          AnimatedOpacity(
            duration: Tk.slow,
            opacity: show ? 1 : 0,
            child: IgnorePointer(
              ignoring: !show,
              child: const Column(children: [SongInfo(center: true), SizedBox(height: 14), ProgressBar(), SizedBox(height: 6), MainControls(), SizedBox(height: 10)]),
            ),
          ),
          AnimatedOpacity(duration: Tk.base, opacity: show ? 0 : .5, child: Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('轻点屏幕显示控制', style: ts(12, c: Colors.white)))),
        ]),
      ]),
    );
  }
}

// ============================ 写真 ============================
class PosterSkin extends StatelessWidget {
  const PosterSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    return Stack(children: [
      Positioned.fill(child: SwipeCover(child: Cover.song(s, size: 0, radius: 0))),
      Positioned.fill(
        child: IgnorePointer(
          child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40000000), Color(0x73000000), Color(0xDB000000)], stops: [0, .45, .8]))),
        ),
      ),
      Column(children: [
        const PlayerTopBar(),
        const Spacer(),
        ValueListenableBuilder<double>(
          valueListenable: app.pos,
          builder: (_, __, ___) {
            final k = app.lyricIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(a), child: c)),
                  child: Column(key: ValueKey(k), crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(lyrics[k].text, style: ts(34, w: FontWeight.w900, c: Colors.white, h: 1.25).copyWith(shadows: const [Shadow(color: Color(0xAAFFFFFF), blurRadius: 18)])),
                    if (app.set.trans) Padding(padding: const EdgeInsets.only(top: 8), child: Text(lyrics[k].trans, style: ts(15, c: const Color(0xB3FFFFFF)))),
                    const SizedBox(height: 14),
                    Text(k + 1 < lyrics.length ? lyrics[k + 1].text : '', style: ts(18, w: FontWeight.w700, c: const Color(0x66FFFFFF))),
                  ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 26),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 26), child: Row(children: [Expanded(child: Text('${s.title} — ${s.artist}', style: ts(14, w: FontWeight.w600, c: const Color(0xCCFFFFFF)))), HeartBtn(app.cur, offColor: Colors.white70)])),
        const SizedBox(height: 8),
        const ProgressBar(),
        const SizedBox(height: 6),
        const MainControls(),
        const SizedBox(height: 14),
      ]),
    ]);
  }
}

// ============================ 极简 ============================
class MinimalSkin extends StatelessWidget {
  const MinimalSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.song;
    return Container(
      color: const Color(0xFF0E0F14),
      child: Column(children: [
        const PlayerTopBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 10),
          child: Row(children: [
            Cover.song(s, size: 64, radius: 12),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(19, w: FontWeight.w700, c: Colors.white)), const SizedBox(height: 3), Text('${s.artist} · ${s.album}', style: ts(13.5, c: const Color(0x99FFFFFF)))])),
            HeartBtn(app.cur, offColor: Colors.white60),
          ]),
        ),
        Expanded(child: LyricView(fontSize: 17, fillColor: pal.acc, anchor: .4)),
        const SizedBox(height: 8),
        const ProgressBar(),
        const SizedBox(height: 6),
        const MainControls(circle: false, playSize: 64),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ============================ 待机 · 横屏全屏 ============================
// 全屏沉浸（隐藏状态栏和导航条）。背景是封面色的渐变，左右两侧各有一组同心波光随节拍向外荡开；
// 中间是衬线大字歌词，身后叠一个放大、模糊的当前字作为「影子」；底部一行细的歌曲信息与控制。
// 轻点屏幕显示时间与关闭按钮，4 秒后自动隐藏。
class StandbySkin extends StatefulWidget {
  const StandbySkin({super.key});
  @override
  State<StandbySkin> createState() => _StandbySkinState();
}

class _StandbySkinState extends State<StandbySkin> {
  bool chrome = false;
  Timer? _hide;
  double _phase = 0, _lastT = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hide?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggle() {
    _hide?.cancel();
    setState(() => chrome = !chrome);
    if (chrome) {
      _hide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => chrome = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    final size = MediaQuery.of(context).size;
    final short = math.min(size.width, size.height);
    final now = DateTime.now();
    const wk = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final white = Colors.white.withValues(alpha: .88);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Ticker2(builder: (c, t) {
              if (app.playing && !app.set.reduceMotion) _phase += (t - _lastT).clamp(0.0, .1);
              _lastT = t;
              return CustomPaint(painter: WaveGlowPainter(s.hue, _phase, app.playing ? app.beat() : 0));
            }),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(size.width * .1, 0, size.width * .1, short * .22),
            child: Center(child: _StandbyLyric(size: short * .1, hue: s.hue)),
          ),
        ),
        // 底部一行：封面 · 歌名 · 控制 · 收藏
        Positioned(
          left: size.width * .08,
          right: size.width * .08,
          bottom: short * .07,
          child: Row(children: [
            Cover.song(s, size: 46, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w: FontWeight.w600, c: white)),
                const SizedBox(height: 2),
                Text(s.artist, maxLines: 1, style: ts(11.5, c: Colors.white.withValues(alpha: .5))),
              ]),
            ),
            IBtn('prev', color: white, iconSize: 26, onTap: app.prev),
            const SizedBox(width: 6),
            Press(
              onTap: app.toggle,
              scale: .86,
              child: SizedBox(width: 56, height: 56, child: Icon(ic(app.playing ? 'pause' : 'play'), size: 42, color: white)),
            ),
            const SizedBox(width: 6),
            IBtn('next', color: white, iconSize: 26, onTap: app.next),
            const SizedBox(width: 10),
            HeartBtn(app.cur, size: 24, offColor: Colors.white.withValues(alpha: .7)),
          ]),
        ),
        // 轻点出现：时间 + 关闭
        Positioned(
          left: size.width * .08,
          right: 16,
          top: 14,
          child: IgnorePointer(
            ignoring: !chrome,
            child: AnimatedOpacity(
              duration: Tk.base,
              opacity: chrome ? 1 : 0,
              child: Row(children: [
                Text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}', style: ts(20, w: FontWeight.w300, c: white, num: true)),
                const SizedBox(width: 10),
                Text('${now.month} 月 ${now.day} 日 ${wk[now.weekday - 1]}', style: ts(13, c: Colors.white.withValues(alpha: .6))),
                const Spacer(),
                IBtn('close', color: white, onTap: () => Navigator.of(context).pop()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 当前句：衬线大字，已唱部分更亮；身后叠一个放大模糊的「当前字」影子。
class _StandbyLyric extends StatelessWidget {
  final double size, hue;
  const _StandbyLyric({required this.size, required this.hue});
  static const _serif = ['Songti SC', 'STSong', 'Noto Serif SC', 'Noto Serif CJK SC', 'Source Han Serif SC', 'serif'];
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ValueListenableBuilder<double>(
      valueListenable: app.pos,
      builder: (_, __, ___) {
        final k = app.lyricIndex;
        final line = lyrics[k].text;
        final chars = line.characters.toList();
        final p = app.lineProgress;
        final ci = (p * chars.length).floor().clamp(0, chars.length - 1);
        var ghost = chars[ci];
        if (ghost.trim().isEmpty && ci > 0) ghost = chars[ci - 1];
        final style = TextStyle(fontFamily: 'serif', fontFamilyFallback: _serif, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: size * .06, height: 1.25);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 520),
          switchInCurve: Tk.out,
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: c)),
          child: Stack(key: ValueKey(k), alignment: Alignment.center, clipBehavior: Clip.none, children: [
            RepaintBoundary(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                child: ImageFiltered(
                  key: ValueKey('$k-$ci'),
                  imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3, tileMode: TileMode.decal),
                  child: Text(ghost, style: style.copyWith(fontSize: size * 2.6, color: hsl(hue, .55, .1, .45), letterSpacing: 0)),
                ),
              ),
            ),
            // 阴影单独一层：放进 ShaderMask 会被染成浅色，变成一块发亮的矩形
            Text(line, textAlign: TextAlign.center, maxLines: 2, style: style.copyWith(color: Colors.transparent, shadows: [Shadow(color: hsl(hue, .6, .12, .55), blurRadius: 16)])),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(colors: const [Color(0xFFF2F7FF), Color(0xFFF2F7FF), Color(0xB3C9DBF5), Color(0xB3C9DBF5)], stops: [0, p, p, 1]).createShader(r),
              child: Text(line, textAlign: TextAlign.center, maxLines: 2, style: style.copyWith(color: Colors.white)),
            ),
          ]),
        );
      },
    );
  }
}

/// 待机背景：封面色水平渐变 + 左右两组同心波光（柔光带用径向渐变画，不用模糊滤镜，保证 60fps）。
class WaveGlowPainter extends CustomPainter {
  final double hue, t, beat;
  WaveGlowPainter(this.hue, this.t, this.beat);
  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(s.width, 0), [hsl(hue, .55, .14), hsl(hue, .55, .3), hsl(hue + 8, .7, .5)], [0, .5, 1]));
    final h = s.height;
    for (final (c, side) in [(Offset(-s.width * .04, h * .5), -1.0), (Offset(s.width * 1.04, h * .5), 1.0)]) {
      const n = 6;
      for (var k = 0; k < n; k++) {
        final ph = ((k + t * .22) % n) / n; // 0 → 1 向外
        final r = h * (.12 + ph * 1.05);
        final band = h * (.05 + .03 * beat);
        final fade = math.sin(ph * math.pi); // 生成和消失都柔和
        final a = (side > 0 ? .1 : .07) * fade * (1 + beat * .8);
        canvas.drawCircle(
            c,
            r + band,
            Paint()
              ..shader = ui.Gradient.radial(c, r + band, [Colors.transparent, Colors.white.withValues(alpha: a), Colors.black.withValues(alpha: a * .9), Colors.transparent], [
                ((r - band) / (r + band)).clamp(0.0, 1.0),
                (r / (r + band)).clamp(0.0, 1.0),
                ((r + band * .5) / (r + band)).clamp(0.0, 1.0),
                1,
              ]));
        if (k % 2 == 0) {
          canvas.drawCircle(c, r, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: .18 * fade));
        }
      }
    }
    // 上下压暗，让歌词和底部控制更清楚
    canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [const Color(0x33000000), Colors.transparent, Colors.transparent, const Color(0x66000000)], [0, .25, .6, 1]));
  }

  @override
  bool shouldRepaint(WaveGlowPainter o) => o.t != t || o.beat != beat || o.hue != hue;
}

// ============================ 磁带 ============================
class CassetteSkin extends StatelessWidget {
  const CassetteSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A2420), Color(0xFF120F0D)])),
      child: Column(children: [
        const PlayerTopBar(),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: AspectRatio(
            aspectRatio: 1.58,
            child: Ticker2(builder: (c, t) => ValueListenableBuilder<double>(valueListenable: app.pos, builder: (_, p, __) => CustomPaint(painter: _TapePainter(p / s.dur, app.playing ? t : -1, app.song.hue), child: _TapeLabel(s)))),
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(children: [
            Expanded(child: Beat(builder: (c, b, p) => _Vu(app.playing ? b * .9 + .1 * math.sin(p * 7).abs() : 0, 'L'))),
            const SizedBox(width: 16),
            Expanded(child: Beat(builder: (c, b, p) => _Vu(app.playing ? b * .8 + .15 * math.cos(p * 5).abs() : 0, 'R'))),
          ]),
        ),
        const Spacer(),
        const ProgressBar(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [
            _Key('◀◀', false, app.prev),
            _Key('▶', app.playing, () {
              if (!app.playing) app.toggle();
            }),
            _Key('❚❚', !app.playing, () {
              if (app.playing) app.toggle();
            }),
            _Key('▶▶', false, app.next),
            _Key('♡', app.liked.contains(app.cur), () => app.toggleLike(app.cur)),
          ]),
        ),
        const SizedBox(height: 18),
      ]),
    );
  }
}

class _TapeLabel extends StatelessWidget {
  final Song s;
  const _TapeLabel(this.s);
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (c, cs) {
      final w = cs.maxWidth, h = cs.maxHeight;
      return Stack(children: [
        Positioned(
          left: w * .09,
          right: w * .09,
          top: h * .1,
          height: h * .2,
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, maxLines: 1, style: TextStyle(fontFamily: 'serif', fontFamilyFallback: const ['Kaiti SC', 'STKaiti', 'KaiTi'], fontStyle: FontStyle.italic, fontSize: h * .085, fontWeight: FontWeight.w700, color: const Color(0xFF2B2014))), Text(s.artist, style: TextStyle(fontSize: h * .05, color: const Color(0xFF6A5A44)))])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('SIDE A', style: TextStyle(fontSize: h * .055, fontWeight: FontWeight.w900, color: const Color(0xFFC0392B))), Text('C-60 · ${fmtTime(s.dur.toDouble())}', style: TextStyle(fontSize: h * .045, color: const Color(0xFF6A5A44)))]),
          ]),
        ),
      ]);
    });
  }
}

class _TapePainter extends CustomPainter {
  final double p, t, hue;
  _TapePainter(this.p, this.t, this.hue);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * .04));
    canvas.drawRRect(body.shift(const Offset(0, 8)), Paint()..color = const Color(0x66000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawRRect(body, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [const Color(0xFF3A3840), const Color(0xFF232228)]));
    for (final o in [Offset(w * .04, h * .06), Offset(w * .96, h * .06), Offset(w * .04, h * .94), Offset(w * .96, h * .94)]) {
      canvas.drawCircle(o, w * .012, Paint()..color = const Color(0xFF6E6C74));
    }
    // 标签纸
    final label = RRect.fromRectAndRadius(Rect.fromLTWH(w * .07, h * .07, w * .86, h * .62), Radius.circular(w * .02));
    canvas.drawRRect(label, Paint()..color = const Color(0xFFF1E6CF));
    canvas.drawRect(Rect.fromLTWH(w * .07, h * .33, w * .86, h * .03), Paint()..color = hsl(hue, .6, .55));
    // 窗口
    final win = RRect.fromRectAndRadius(Rect.fromLTWH(w * .22, h * .38, w * .56, h * .26), Radius.circular(h * .13));
    canvas.drawRRect(win, Paint()..color = const Color(0xFF1A1A1E));
    final lc = Offset(w * .33, h * .51), rc = Offset(w * .67, h * .51);
    final r0 = h * .055, dr = h * .065;
    final lr = r0 + (1 - p) * dr, rr = r0 + p * dr;
    canvas.save();
    canvas.clipRRect(win);
    final tape = Paint()..color = const Color(0xFF4A2E1E);
    canvas.drawCircle(lc, lr, tape);
    canvas.drawCircle(rc, rr, tape);
    canvas.drawLine(Offset(lc.dx, lc.dy + lr), Offset(rc.dx, rc.dy + rr), Paint()
      ..color = const Color(0xFF4A2E1E)
      ..strokeWidth = 2);
    canvas.restore();
    for (final (c, r) in [(lc, lr), (rc, rr)]) {
      final ang = t < 0 ? 0.0 : t * 4 / (r / r0);
      canvas.drawCircle(c, r0 * .75, Paint()..color = const Color(0xFFEDEDED));
      for (var k = 0; k < 6; k++) {
        final a = ang + k * math.pi / 3;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0 * .25, c + Offset(math.cos(a), math.sin(a)) * r0 * .7, Paint()
          ..color = const Color(0xFF555555)
          ..strokeWidth = 2.2);
      }
      canvas.drawCircle(c, r0 * .22, Paint()..color = const Color(0xFF333333));
    }
    // 底部梯形
    final trap = Path()
      ..moveTo(w * .2, h)
      ..lineTo(w * .26, h * .78)
      ..lineTo(w * .74, h * .78)
      ..lineTo(w * .8, h)
      ..close();
    canvas.drawPath(trap, Paint()..color = const Color(0xFF2C2B31));
    for (final x in [.34, .5, .66]) {
      canvas.drawCircle(Offset(w * x, h * .89), h * .025, Paint()..color = const Color(0xFF15151A));
    }
  }

  @override
  bool shouldRepaint(_TapePainter o) => true;
}

class _Vu extends StatelessWidget {
  final double v;
  final String ch;
  const _Vu(this.v, this.ch);
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.8,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFFF3E7C6), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF6B5B3E), width: 2)),
          child: CustomPaint(painter: _VuPainter(v, ch)),
        ),
      );
}

class _VuPainter extends CustomPainter {
  final double v;
  final String ch;
  _VuPainter(this.v, this.ch);
  @override
  void paint(Canvas canvas, Size s) {
    final o = Offset(s.width / 2, s.height * 1.05);
    final r = s.height * .85;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(Rect.fromCircle(center: o, radius: r), -math.pi * .8, math.pi * .45, false, arc..color = const Color(0xFF3C3226));
    canvas.drawArc(Rect.fromCircle(center: o, radius: r), -math.pi * .35, math.pi * .15, false, arc..color = const Color(0xFFC0392B));
    for (var i = 0; i <= 10; i++) {
      final a = -math.pi * .8 + i / 10 * math.pi * .6;
      canvas.drawLine(o + Offset(math.cos(a), math.sin(a)) * (r - 6), o + Offset(math.cos(a), math.sin(a)) * r, Paint()
        ..color = i > 7 ? const Color(0xFFC0392B) : const Color(0xFF3C3226)
        ..strokeWidth = 1.4);
    }
    final a = -math.pi * .78 + v.clamp(0, 1) * math.pi * .56;
    canvas.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * (r + 4), Paint()
      ..color = const Color(0xFF1B1B1B)
      ..strokeWidth = 1.6);
    final tp = TextPainter(text: TextSpan(text: 'VU  $ch', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF3C3226))), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(8, s.height - 14));
  }

  @override
  bool shouldRepaint(_VuPainter o) => o.v != v;
}

class _Key extends StatelessWidget {
  final String label;
  final bool down;
  final VoidCallback onTap;
  const _Key(this.label, this.down, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: EdgeInsets.only(left: 3, right: 3, top: down ? 6 : 0),
            height: 58 - (down ? 6 : 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: down ? const [Color(0xFF8E8A82), Color(0xFFB9B4AA)] : const [Color(0xFFE2DDD2), Color(0xFFA7A296)]),
              borderRadius: BorderRadius.circular(8),
              boxShadow: down ? null : const [BoxShadow(color: Color(0xFF55524B), offset: Offset(0, 6)), BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 8))],
            ),
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF2B2A26))),
          ),
        ),
      );
}

// ============================ 胶片 ============================
class FilmSkin extends StatelessWidget {
  const FilmSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final qi = app.queue.indexOf(app.cur);
    const frameH = 170.0, gap = 18.0;
    return Container(
      color: const Color(0xFF0C0B0A),
      child: Column(children: [
        const PlayerTopBar(),
        Expanded(
          child: LayoutBuilder(builder: (c, cs) {
            final h = cs.maxHeight;
            return Stack(alignment: Alignment.center, children: [
              Positioned(
                top: 0,
                bottom: 0,
                width: 268,
                child: Container(
                  color: const Color(0xFF1B1916),
                  child: ClipRect(
                    child: Stack(children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 700),
                        curve: Tk.out,
                        left: 0,
                        right: 0,
                        top: h / 2 - frameH / 2 - qi * (frameH + gap),
                        child: Column(children: [
                          for (final (i, id) in app.queue.indexed)
                            Container(
                              height: frameH,
                              margin: const EdgeInsets.only(bottom: gap),
                              padding: const EdgeInsets.symmetric(horizontal: 34),
                              child: AnimatedContainer(
                                duration: Tk.slow,
                                decoration: BoxDecoration(border: Border.all(color: i == qi ? pal.acc : Colors.transparent, width: 3), borderRadius: BorderRadius.circular(4)),
                                child: ColorFiltered(colorFilter: ColorFilter.mode(i == qi ? Colors.transparent : const Color(0x66000000), BlendMode.darken), child: Cover.song(songs[id], size: 0, radius: 2)),
                              ),
                            ),
                        ]),
                      ),
                      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Sprockets()))),
                    ]),
                  ),
                ),
              ),
              Positioned.fill(child: IgnorePointer(child: Ticker2(builder: (c, t) => CustomPaint(painter: _GrainLeak(app.playing ? t : 0))))),
              Positioned(
                right: 12,
                top: 12,
                child: ValueListenableBuilder<double>(
                  valueListenable: app.pos,
                  builder: (_, p, __) => Text('24 FPS\nISO 400\nFRAME ${(p * 24).floor().toString().padLeft(5, '0')}', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.5, color: pal.acc.withValues(alpha: .8))),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 14),
        const SongInfo(),
        const SizedBox(height: 14),
        const ProgressBar(),
        const SizedBox(height: 6),
        const MainControls(),
        const SizedBox(height: 14),
      ]),
    );
  }
}

class _Sprockets extends CustomPainter {
  const _Sprockets();
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xFF0C0B0A);
    for (var y = 6.0; y < s.height; y += 22) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(9, y, 14, 10), const Radius.circular(2)), p);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 23, y, 14, 10), const Radius.circular(2)), p);
    }
  }

  @override
  bool shouldRepaint(_Sprockets o) => false;
}

class _GrainLeak extends CustomPainter {
  final double t;
  _GrainLeak(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random((t * 24).floor());
    final p = Paint()..color = const Color(0x22FFFFFF);
    canvas.drawPoints(ui.PointMode.points, [for (var i = 0; i < 500; i++) Offset(r.nextDouble() * s.width, r.nextDouble() * s.height)], p..strokeWidth = 1.2);
    final leak = .35 + .25 * math.sin(t * .7);
    canvas.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.radial(Offset(s.width * 1.05, s.height * (.3 + .1 * math.sin(t * .4))), s.width * .9, [const Color(0xFFFF5A1F).withValues(alpha: leak * .5), Colors.transparent])..blendMode = BlendMode.screen);
  }

  @override
  bool shouldRepaint(_GrainLeak o) => true;
}

// ============================ 像素 ============================
class PixelSkin extends StatelessWidget {
  const PixelSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier New', 'Menlo'], color: Colors.white, fontWeight: FontWeight.w700);
    return Container(
      color: const Color(0xFF1B1532),
      child: Stack(children: [
        Column(children: [
          const PlayerTopBar(),
          const Spacer(),
          ColorFiltered(
            colorFilter: app.playing ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : const ColorFilter.matrix([.33, .59, .11, 0, 0, .33, .59, .11, 0, 0, .33, .59, .11, 0, 0, 0, 0, 0, 1, 0]),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black, boxShadow: [BoxShadow(color: Colors.black, offset: Offset(8, 8))]),
              padding: const EdgeInsets.all(4),
              child: Container(padding: const EdgeInsets.all(4), color: Colors.white, child: SizedBox(width: 208, height: 208, child: CustomPaint(painter: _PixelArt(s.id, s.hue)))),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(height: 70, child: Beat(builder: (c, b, p) => CustomPaint(size: const Size(300, 70), painter: _BlockSpec(b, p, app.playing)))),
          const SizedBox(height: 18),
          Text(s.title.toUpperCase(), style: mono.copyWith(fontSize: 20)),
          Text(s.artist, style: mono.copyWith(fontSize: 13, color: const Color(0xFFB8A8FF))),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: app.pos,
            builder: (_, __, ___) {
              final l = lyrics[app.lyricIndex].text;
              final n = (l.characters.length * app.lineProgress * 1.6).ceil().clamp(0, l.characters.length);
              final cursor = (DateTime.now().millisecond ~/ 500).isEven;
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('${l.characters.take(n)}${cursor ? '█' : ' '}', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 16, color: const Color(0xFFF4D28A))));
            },
          ),
          const Spacer(),
          const ProgressBar(color: Color(0xFFB8A8FF), fg: Color(0xFFF4D28A), track: 6, trackDrag: 10),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _PixBtn('◀◀', app.prev),
            _PixBtn(app.playing ? '❚❚' : '▶', app.toggle, wide: true),
            _PixBtn('▶▶', app.next),
          ]),
          const SizedBox(height: 20),
        ]),
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Scanlines()))),
      ]),
    );
  }
}

class _PixelArt extends CustomPainter {
  final int seed;
  final double hue;
  _PixelArt(this.seed, this.hue);
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(seed * 7919 + 13);
    const n = 16;
    final cell = s.width / n;
    final cols = [hsl(hue, .7, .62), hsl(hue + 40, .6, .45), hsl(hue + 300, .6, .3), const Color(0xFFFFF4DE)];
    canvas.drawRect(Offset.zero & s, Paint()..color = hsl(hue + 180, .35, .14));
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n / 2; x++) {
        final d = math.sqrt(math.pow(x - 7.5, 2) + math.pow(y - 7.5, 2));
        if (r.nextDouble() < .62 - d * .03) {
          final c = cols[r.nextInt(cols.length)];
          final p = Paint()..color = c;
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .5, cell + .5), p);
          canvas.drawRect(Rect.fromLTWH((n - 1 - x) * cell, y * cell, cell + .5, cell + .5), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelArt o) => o.seed != seed;
}

class _BlockSpec extends CustomPainter {
  final double b, p;
  final bool on;
  _BlockSpec(this.b, this.p, this.on);
  @override
  void paint(Canvas canvas, Size s) {
    const cols = 16, rows = 8;
    final cw = s.width / cols, rh = s.height / rows;
    for (var i = 0; i < cols; i++) {
      final v = on ? ((.3 + .7 * b) * (.5 + .5 * math.sin(p * 9 + i * 1.7)).abs() * (1 - (i - 7.5).abs() / 12)) : .1;
      final hgt = (v * rows).ceil();
      for (var j = 0; j < hgt; j++) {
        final top = j == hgt - 1 && hgt > 3;
        canvas.drawRect(Rect.fromLTWH(i * cw + 2, s.height - (j + 1) * rh + 2, cw - 4, rh - 4), Paint()..color = top ? const Color(0xFFFF4D6D) : Color.lerp(const Color(0xFF6EE7C8), const Color(0xFFF4D28A), j / rows)!);
      }
    }
  }

  @override
  bool shouldRepaint(_BlockSpec o) => true;
}

class _Scanlines extends CustomPainter {
  const _Scanlines();
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0x22000000);
    for (var y = 0.0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1.2), p);
    }
    canvas.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.radial(s.center(Offset.zero), s.longestSide * .7, [Colors.transparent, const Color(0x66000000)]));
  }

  @override
  bool shouldRepaint(_Scanlines o) => false;
}

class _PixBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool wide;
  const _PixBtn(this.label, this.onTap, {this.wide = false});
  @override
  State<_PixBtn> createState() => _PixBtnState();
}

class _PixBtnState extends State<_PixBtn> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => down = true),
        onTapUp: (_) => setState(() => down = false),
        onTapCancel: () => setState(() => down = false),
        onTap: widget.onTap,
        child: Transform.translate(
          offset: down ? const Offset(4, 4) : Offset.zero,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: widget.wide ? 96 : 70,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFF4D28A), border: Border.all(color: Colors.black, width: 3), boxShadow: down ? null : const [BoxShadow(color: Colors.black, offset: Offset(4, 4))]),
            child: Text(widget.label, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
          ),
        ),
      );
}

// ============================ 霓虹 ============================
class NeonSkin extends StatelessWidget {
  const NeonSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    const pink = Color(0xFFFF5FD2), cyan = Color(0xFF7DF9FF);
    return Stack(children: [
      const Positioned.fill(child: CustomPaint(painter: _Bricks())),
      Column(children: [
        const PlayerTopBar(),
        const SizedBox(height: 10),
        Beat(builder: (c, b, p) {
          final glow = app.playing ? .6 + b * .4 : .25;
          return Text('NOW PLAYING', style: TextStyle(fontSize: 14, letterSpacing: 6, fontWeight: FontWeight.w800, color: pink.withValues(alpha: .4 + glow * .6), shadows: [Shadow(color: pink.withValues(alpha: glow), blurRadius: 18)]));
        }),
        const Spacer(),
        Beat(builder: (c, b, p) {
          final glow = app.playing ? .55 + b * .45 : .2;
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cyan.withValues(alpha: .5 + glow * .5), width: 4),
              boxShadow: [BoxShadow(color: cyan.withValues(alpha: glow * .9), blurRadius: 30, spreadRadius: 2), BoxShadow(color: cyan.withValues(alpha: glow * .5), blurRadius: 10, spreadRadius: -2)],
            ),
            child: Opacity(opacity: app.playing ? 1 : .6, child: Cover.song(s, size: 250, radius: 14)),
          );
        }),
        const SizedBox(height: 34),
        _NeonTitle(s.title, key: ValueKey(s.id)),
        const SizedBox(height: 6),
        Text(s.artist, style: TextStyle(fontSize: 15, color: cyan.withValues(alpha: .8), shadows: const [Shadow(color: cyan, blurRadius: 10)])),
        const SizedBox(height: 14),
        const IgnorePointer(child: Lyric3(size: 15, fill: pink)),
        const Spacer(),
        const ProgressBar(fg: pink),
        const SizedBox(height: 6),
        const MainControls(),
        const SizedBox(height: 14),
      ]),
    ]);
  }
}

class _NeonTitle extends StatelessWidget {
  final String text;
  const _NeonTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    const pink = Color(0xFFFF5FD2);
    final chars = text.characters.toList();
    return Ticker2(builder: (c, t) {
      final flicker = (t * 3).floor() % 7 == 3 ? ((t * 13).floor() % chars.length) : -1;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < chars.length; i++)
          Builder(builder: (_) {
            final lit = t > i * .09 && i != flicker && app.playing;
            return Text(chars[i], style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: lit ? const Color(0xFFFFE6F7) : pink.withValues(alpha: .25), shadows: lit ? const [Shadow(color: pink, blurRadius: 16), Shadow(color: pink, blurRadius: 4)] : null));
          }),
      ]);
    });
  }
}

class _Bricks extends CustomPainter {
  const _Bricks();
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1A0E10));
    final r = math.Random(5);
    const bw = 58.0, bh = 26.0;
    for (var y = 0.0, row = 0; y < s.height; y += bh, row++) {
      for (var x = row.isOdd ? -bw / 2 : 0.0; x < s.width; x += bw) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, y + 2, bw - 4, bh - 4), const Radius.circular(2)), Paint()..color = Color.lerp(const Color(0xFF2E1517), const Color(0xFF3D1C1E), r.nextDouble())!);
      }
    }
    canvas.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.radial(Offset(s.width / 2, s.height * .4), s.height * .7, [Colors.transparent, const Color(0xCC000000)]));
  }

  @override
  bool shouldRepaint(_Bricks o) => false;
}

// ============================ 终端 ============================
class TerminalSkin extends StatelessWidget {
  const TerminalSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    const g = Color(0xFF39FF88), dim = Color(0xFF1F8F4E), amber = Color(0xFFF4D28A);
    const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Sarasa Mono SC', 'Menlo', 'Courier New'], fontSize: 13.5, height: 1.55, color: g);
    final sc = app.curScript;
    Widget btn(String l, VoidCallback f) => Press(onTap: f, child: Padding(padding: const EdgeInsets.all(6), child: Text('[ $l ]', style: mono.copyWith(fontSize: 15, fontWeight: FontWeight.w700))));
    return Container(
      color: const Color(0xFF050806),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PlayerTopBar(color: g),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: ValueListenableBuilder<double>(
              valueListenable: app.pos,
              builder: (_, p, __) {
                final k = app.lyricIndex;
                final b = app.playing ? app.beat() : 0.0;
                const blocks = '▁▂▃▄▅▆▇█';
                final spec = List.generate(20, (i) => blocks[((b * .7 + .3 * math.sin(p * 8 + i)).abs() * (1 - (i - 9.5).abs() / 13) * 7.99).floor().clamp(0, 7)]).join();
                final pr = p / s.dur;
                final bar = '${'#' * (pr * 24).round()}${'-' * (24 - (pr * 24).round())}';
                final l = lyrics[k].text;
                final typed = l.characters.take((l.characters.length * app.lineProgress * 1.5).ceil()).toString();
                final cursor = (DateTime.now().millisecond ~/ 500).isEven ? '█' : ' ';
                return ListView(padding: EdgeInsets.zero, children: [
                  Text('\$ lyra play --id ${s.id} --quality ${app.quality}', style: mono.copyWith(color: amber)),
                  Text('[resolve] ${app.platform.name} · ${sc.name} · ${sc.ms}ms', style: mono.copyWith(color: dim)),
                  Text('[stream ] FLAC 16bit/44.1kHz · 27.8MB · cache hit', style: mono.copyWith(color: dim)),
                  Text('[  ok   ] ${s.title} — ${s.artist}', style: mono.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(spec, maxLines: 1, overflow: TextOverflow.clip, style: mono.copyWith(fontSize: 22, height: 1.1)),
                  const SizedBox(height: 6),
                  Text('[$bar] ${fmtTime(p)} / ${fmtTime(s.dur.toDouble())}', style: mono),
                  Text('mode=${app.mode} speed=${app.speed.toStringAsFixed(2)}x vol=${(app.vol * 100).round()}%', style: mono.copyWith(color: dim)),
                  const SizedBox(height: 10),
                  for (var i = math.max(0, k - 5); i < k; i++) Text('> ${lyrics[i].text}', style: mono.copyWith(color: dim)),
                  Text('\$ echo "$typed$cursor"', style: mono.copyWith(color: g, fontWeight: FontWeight.w700, fontSize: 15)),
                ]);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            btn('prev', app.prev),
            btn(app.playing ? 'pause' : 'play', app.toggle),
            btn('next', app.next),
            btn(app.liked.contains(app.cur) ? '♥' : '♡', () => app.toggleLike(app.cur)),
          ]),
        ),
      ]),
    );
  }
}

// ============================ 杂志 ============================
class MagazineSkin extends StatelessWidget {
  const MagazineSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    const ink = Color(0xFF1C1A16), red = Color(0xFFC0392B);
    const serif = TextStyle(fontFamily: 'serif', fontFamilyFallback: ['Songti SC', 'Noto Serif SC', 'Noto Serif CJK SC', 'Georgia'], color: ink);
    final now = DateTime.now();
    const mon = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle(false),
      child: Container(
        color: const Color(0xFFEFE8DA),
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _Paper())),
          ListView(padding: EdgeInsets.zero, physics: const ClampingScrollPhysics(), children: [
            const PlayerTopBar(color: ink),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 2, color: ink),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Text('LYRA · NO.01', style: serif.copyWith(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)), const Spacer(), Text('${mon[now.month - 1]} ${now.year}', style: serif.copyWith(fontSize: 12, letterSpacing: 2))])),
                Container(height: .8, color: ink),
                const SizedBox(height: 14),
                Text(s.title, style: serif.copyWith(fontSize: 58, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1)),
                const SizedBox(height: 8),
                Text('by ${s.artist}', style: serif.copyWith(fontSize: 17, fontStyle: FontStyle.italic, color: const Color(0xFF5A5246))),
                const SizedBox(height: 16),
                SwipeCover(
                  child: ColorFiltered(
                    colorFilter: app.playing ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : const ColorFilter.matrix([.33, .59, .11, 0, 0, .33, .59, .11, 0, 0, .33, .59, .11, 0, 0, 0, 0, 0, 1, 0]),
                    child: AspectRatio(aspectRatio: 1.35, child: Cover.song(s, size: 0, radius: 0)),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Fig. 1 — 《${s.album}》，${now.year}', style: serif.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic, color: const Color(0xFF6E6658))),
                const SizedBox(height: 18),
                ValueListenableBuilder<double>(
                  valueListenable: app.pos,
                  builder: (_, __, ___) {
                    final k = app.lyricIndex;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: Row(key: ValueKey(k), crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('“', style: serif.copyWith(fontSize: 64, height: .9, color: red, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(lyrics[k].text, style: serif.copyWith(fontSize: 24, height: 1.35, fontWeight: FontWeight.w700))),
                      ]),
                    );
                  },
                ),
                const SizedBox(height: 18),
              ]),
            ),
            const ProgressBar(color: ink, fg: red, showTimes: true),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final (l, f) in [('PREV', app.prev), (app.playing ? 'PAUSE' : 'PLAY', app.toggle), ('NEXT', app.next)])
                Press(onTap: f, child: Padding(padding: const EdgeInsets.all(10), child: Text(l, style: serif.copyWith(fontSize: 16, letterSpacing: 4, fontWeight: FontWeight.w700)))),
            ]),
            const SizedBox(height: 20),
          ]),
        ]),
      ),
    );
  }
}

class _Paper extends CustomPainter {
  const _Paper();
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(11);
    final p = Paint()
      ..color = const Color(0x0F5A4A30)
      ..strokeWidth = 1;
    canvas.drawPoints(ui.PointMode.points, [for (var i = 0; i < 4000; i++) Offset(r.nextDouble() * s.width, r.nextDouble() * s.height)], p);
  }

  @override
  bool shouldRepaint(_Paper o) => false;
}

// ============================ 表盘 ============================
class DialSkin extends StatelessWidget {
  const DialSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.song;
    return Container(
      color: Colors.black,
      child: Column(children: [
        const PlayerTopBar(),
        const Spacer(),
        SizedBox(
          width: 320,
          height: 320,
          child: ValueListenableBuilder<double>(
            valueListenable: app.pos,
            builder: (_, p, __) => GestureDetector(
              onPanUpdate: (d) {
                const c = Offset(160, 160);
                final v = d.localPosition - c;
                final a = (math.atan2(v.dy, v.dx) + math.pi / 2) % (math.pi * 2);
                app.seek(a / (math.pi * 2) * s.dur);
              },
              child: CustomPaint(
                painter: _DialPainter(p / s.dur, pal.acc),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Spin(period: const Duration(seconds: 20), on: app.playing, child: ClipOval(child: Cover.song(s, size: 170, radius: 85))),
                    const SizedBox(height: 10),
                    Text(fmtTime(p), style: ts(22, w: FontWeight.w300, c: Colors.white, num: true)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        const SongInfo(center: true),
        const SizedBox(height: 18),
        const MainControls(),
        const SizedBox(height: 10),
        const AuxRow(),
        const SizedBox(height: 10),
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double p;
  final Color acc;
  _DialPainter(this.p, this.acc);
  @override
  void paint(Canvas canvas, Size s) {
    final o = s.center(Offset.zero);
    final r = s.width / 2 - 6;
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2 - math.pi / 2;
      final long = i % 5 == 0;
      final lit = i / 60 <= p;
      canvas.drawLine(o + Offset(math.cos(a), math.sin(a)) * (r - (long ? 16 : 9)), o + Offset(math.cos(a), math.sin(a)) * r, Paint()
        ..strokeWidth = long ? 3 : 1.6
        ..strokeCap = StrokeCap.round
        ..color = lit ? (long ? Colors.white : acc) : const Color(0x33FFFFFF));
    }
    final a = p * math.pi * 2 - math.pi / 2;
    final dot = o + Offset(math.cos(a), math.sin(a)) * (r + 0);
    canvas.drawCircle(dot, 7, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 12, Paint()..color = acc.withValues(alpha: .35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.p != p;
}

// ============================ 皮肤缩略图 ============================
class SkinThumb extends StatelessWidget {
  final String id;
  const SkinThumb(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.song;
    switch (id) {
      case 'particles':
        return const ParticleView(preset: 'galaxy', interactive: false, animate: false);
      case 'magazine':
        return Container(color: const Color(0xFFEFE8DA), padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 1.5, color: Colors.black), const SizedBox(height: 4), Text(s.title, maxLines: 1, style: const TextStyle(fontFamily: 'serif', fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black)), const SizedBox(height: 4), Expanded(child: Cover.song(s, size: 0, radius: 0)), const SizedBox(height: 4), const Text('“ ……', style: TextStyle(color: Color(0xFFC0392B), fontWeight: FontWeight.w900))]));
      case 'terminal':
        return Container(color: const Color(0xFF050806), padding: const EdgeInsets.all(8), child: const Text('\$ lyra play\n[ ok ] 夜航星图\n▂▄▆█▆▄▂▁▃▅\n[#####----]\n> 城市在身后…', style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: Color(0xFF39FF88), height: 1.4)));
      case 'pixel':
        return Container(color: const Color(0xFF1B1532), alignment: Alignment.center, child: Container(color: Colors.white, padding: const EdgeInsets.all(3), child: SizedBox(width: 64, height: 64, child: CustomPaint(painter: _PixelArt(s.id, s.hue)))));
      case 'neon':
        return Stack(alignment: Alignment.center, children: [const Positioned.fill(child: CustomPaint(painter: _Bricks())), Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(border: Border.all(color: const Color(0xFF7DF9FF), width: 2), borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0xFF7DF9FF), blurRadius: 12)]), child: Cover.song(s, size: 60, radius: 4))]);
      case 'cassette':
        return Container(color: const Color(0xFF2A2420), padding: const EdgeInsets.all(10), child: Center(child: AspectRatio(aspectRatio: 1.58, child: CustomPaint(painter: _TapePainter(.35, -1, s.hue)))));
      case 'film':
        return Container(color: const Color(0xFF1B1916), padding: const EdgeInsets.symmetric(horizontal: 18), child: Stack(children: [Column(children: [for (var i = 0; i < 3; i++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Cover.song(songs[(s.id + i) % songs.length], size: 0, radius: 1)))]), const Positioned.fill(child: CustomPaint(painter: _Sprockets()))]));
      case 'dial':
        return Container(color: Colors.black, child: CustomPaint(painter: _DialPainter(.35, pal.acc), child: Center(child: ClipOval(child: Cover.song(s, size: 44, radius: 22)))));
      case 'vinyl':
        return Container(color: const Color(0xFF15161C), alignment: Alignment.center, child: SizedBox(width: 90, height: 90, child: CustomPaint(painter: _DiscPainter(), child: Center(child: ClipOval(child: Cover.song(s, size: 34, radius: 17))))));
      case 'pulse':
        return Container(color: const Color(0xFF0B0C12), child: CustomPaint(painter: _PulsePainter(.6, .7, pal.acc), child: Center(child: ClipOval(child: Cover.song(s, size: 46, radius: 23)))));
      case 'standby':
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: WaveGlowPainter(s.hue, 1.3, 0))),
          Center(child: Text(lyrics[6].text.split(' ').first, style: const TextStyle(fontFamily: 'serif', fontFamilyFallback: ['Songti SC', 'Noto Serif CJK SC'], fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFF2F7FF)))),
          Positioned(left: 8, right: 8, bottom: 8, child: Row(children: [Cover.song(s, size: 16, radius: 3), const Spacer(), const Icon(Icons.pause_rounded, size: 16, color: Colors.white70)])),
        ]);
      case 'minimal':
        return Container(color: const Color(0xFF0E0F14), padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Cover.song(s, size: 24, radius: 5), const SizedBox(width: 6), Container(width: 40, height: 5, color: Colors.white54)]), const SizedBox(height: 10), for (var i = 0; i < 4; i++) Container(margin: const EdgeInsets.only(bottom: 6), width: 60.0 + (i * 13 % 30), height: 5, color: i == 1 ? pal.acc : Colors.white24)]));
      case 'stage':
        return Stack(children: [Positioned.fill(child: Cover.song(s, size: 0, radius: 0)), Container(color: const Color(0xC0000000)), Center(child: Text('副歌\n每一颗都写着', textAlign: TextAlign.center, style: ts(13, w: FontWeight.w900, c: pal.acc)))]);
      case 'poster':
        return Stack(children: [Positioned.fill(child: Cover.song(s, size: 0, radius: 0)), Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))), Positioned(left: 8, bottom: 8, right: 8, child: Text(lyrics[6].text, style: ts(12, w: FontWeight.w900, c: Colors.white)))]);
      default: // spring
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _FlowThumb(coverColors(s.hue)))),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Cover.song(s, size: 62, radius: 8, shadow: true), const SizedBox(height: 6), Container(width: 60, height: 4, decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(2)))])),
        ]);
    }
  }
}

class _FlowThumb extends CustomPainter {
  final List<Color> c;
  _FlowThumb(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0B0C12));
    for (var i = 0; i < 4; i++) {
      final o = Offset(s.width * [.2, .8, .3, .75][i], s.height * [.2, .3, .8, .85][i]);
      canvas.drawCircle(o, s.width * .6, Paint()..shader = ui.Gradient.radial(o, s.width * .6, [c[i].withValues(alpha: .8), Colors.transparent]));
    }
  }

  @override
  bool shouldRepaint(_FlowThumb o) => false;
}

// 供设置页使用
void openSkinSheet(BuildContext context) => openSkins(context);
