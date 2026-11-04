// 迷你播放条：点击打开播放器；左右滑切歌；上滑打开播放器；底部 2px 进度。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../player/player.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'nav.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with SingleTickerProviderStateMixin {
  double dx = 0, dy = 0;
  int dir = 0;
  late final inC = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..value = 1;

  @override
  void dispose() {
    inC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.song;
    final g = NavGeom.of(app.bar);
    final mq = MediaQuery.of(context);
    final adj = mq.padding.bottom - 34;
    final collapse = app.navMin && (app.bar == 'liquid' || app.bar == 'island');
    final sink = app.navMin && (app.bar == 'classic' || app.bar == 'frosted' || app.bar == 'text');
    final navH = g.attached ? math.max(56.0, g.height + adj) : g.height;
    final navB = g.attached ? 0.0 : math.max(10.0, g.bottom + adj);
    final bottom = collapse ? navB : (g.attached ? navH : navB + navH + 10) - (sink ? 30 : 0) + (app.bar == 'cutout' ? 24 : 0);
    final left = collapse ? 14.0 + 58 + 10 : g.miniL;
    final right = collapse ? 14.0 : g.miniR;
    final h = collapse ? 58.0 : 60.0;
    final radius = collapse ? 29.0 : g.miniR2;
    final attachedTop = app.bar == 'frosted' && !collapse;

    final body = Row(children: [
      const SizedBox(width: 8),
      Hero(tag: 'cover', child: Cover.song(s, size: 44, radius: 12)),
      const SizedBox(width: 10),
      Expanded(
        child: AnimatedBuilder(
          animation: inC,
          builder: (_, ch) => Opacity(
            opacity: (1 - dx.abs() / 120).clamp(0, 1) * inC.value,
            child: Transform.translate(offset: Offset(dx + (1 - Tk.softSpring.transform(inC.value)) * 60 * dir, 0), child: ch),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Marquee(s.title, style: ts(14.5, w: FontWeight.w600, c: pal.t1)),
            const SizedBox(height: 2),
            // 播放失败：副标题换成红色的失败原因，点播放键重试
            if (app.playError != null)
              Row(children: [
                Icon(Icons.error_outline_rounded, size: 13, color: pal.danger),
                const SizedBox(width: 3),
                Expanded(child: Text('播放失败 · ${app.playError}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.danger))),
              ])
            else
              Text(app.castDev != null ? '投放到 ${app.castDev} · ${s.artist}' : s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t2)),
          ]),
        ),
      ),
      Press(
        onTap: app.toggle,
        scale: .86,
        radius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: pal.t1, shape: BoxShape.circle),
          child: AnimatedSwitcher(duration: Tk.fast, child: Icon(ic(app.playing ? 'pause' : 'play'), key: ValueKey(app.playing), size: 22, color: pal.bg)),
        ),
      ),
      if (!collapse) IBtn('next', onTap: () => _swap(1)),
      if (collapse) const SizedBox(width: 9),
    ]);

    final card = Container(
      height: h,
      decoration: BoxDecoration(
        borderRadius: attachedTop ? const BorderRadius.vertical(top: Radius.circular(22)) : BorderRadius.circular(radius),
        boxShadow: attachedTop || app.bar == 'text' ? null : const [BoxShadow(color: Color(0x47000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: attachedTop ? const BorderRadius.vertical(top: Radius.circular(22)) : BorderRadius.circular(radius),
        child: app.bar == 'text' || app.bar == 'classic'
            ? Container(decoration: BoxDecoration(color: app.bar == 'text' ? pal.s1 : pal.glassStrong, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(radius)), child: Stack(children: [body, _progress(app, pal)]))
            : Glass(radius: attachedTop ? 0 : radius, color: pal.glassStrong, child: Stack(children: [body, _progress(app, pal)])),
      ),
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 420),
      curve: Tk.out,
      left: left,
      right: right,
      bottom: bottom,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openPlayer(context),
        onHorizontalDragUpdate: (d) => setState(() => dx += d.delta.dx),
        onHorizontalDragEnd: (d) {
          if (dx.abs() > 60 || (d.primaryVelocity ?? 0).abs() > 600) {
            _swap(dx < 0 || (d.primaryVelocity ?? 0) < 0 ? 1 : -1);
          }
          setState(() => dx = 0);
        },
        onVerticalDragUpdate: (d) => dy += d.delta.dy,
        onVerticalDragEnd: (d) {
          if (dy < -40 || (d.primaryVelocity ?? 0) < -500) openPlayer(context);
          dy = 0;
        },
        child: card,
      ),
    );
  }

  void _swap(int d) {
    final app = context.appRead;
    d > 0 ? app.next() : app.prev();
    dir = d;
    inC.forward(from: 0);
  }

  Widget _progress(AppState app, Pal pal) => Positioned(
        left: 18,
        right: 18,
        bottom: 0,
        height: 2,
        child: ValueListenableBuilder<double>(
          valueListenable: app.pos,
          builder: (_, p, __) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (app.song.dur > 0 ? p / app.song.dur : 0.0).clamp(0, 1),
            child: Container(decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(1))),
          ),
        ),
      );
}
