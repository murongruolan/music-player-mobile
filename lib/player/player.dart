// 全屏播放器：从底部升起（460ms），下拉关闭（>150px 或速度 >0.8），圆角随距离增大。
// 背景层（模糊封面 / 静态流光 / 动态流光 + 噪点 + 压暗）、通用骨架（顶栏 / 信息 / 进度 / 主控 / 辅助行）。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../pages/settings.dart';
import '../ui/cover.dart';
import '../ui/cover_tint.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';
import 'skins.dart';

bool _playerOpen = false;

/// 播放器路由：opaque，升起完成后下层外壳（毛玻璃底栏、迷你条）不再参与绘制。
/// 下拉关闭直接驱动路由自身的动画，下层会在拖动时自动重新露出来。
class PlayerRoute extends PageRouteBuilder<void> {
  PlayerRoute({required super.pageBuilder})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: _transition,
        );

  AnimationController get ctl => controller!;

  static Widget _transition(BuildContext context, Animation<double> a, Animation<double> _, Widget child) {
    final gesture = ModalRoute.of(context)?.navigator?.userGestureInProgress ?? false;
    final v = a.value;
    final t = gesture ? v : (a.status == AnimationStatus.reverse ? Tk.standard.transform(v) : Tk.out.transform(v));
    if (t >= 1) return child;
    return FractionalTranslation(
      translation: Offset(0, 1 - t),
      child: ClipRRect(borderRadius: BorderRadius.circular(36 * (1 - t).clamp(0.0, 1.0)), child: child),
    );
  }
}

Future<void> openPlayer(BuildContext context) async {
  if (_playerOpen || !context.appRead.hasSong) return;
  _playerOpen = true;
  final st = context.appRead;
  final pal = context.pal.forceDark;
  if (st.set.keepAwake) unawaited(WakelockPlus.enable()); // 播放页屏幕常亮

  await rootNav.currentState!.push(PlayerRoute(pageBuilder: (_, a, __) => AppScope(state: st, child: PalScope(pal: pal, child: const PlayerScreen()))));
  _playerOpen = false;
  unawaited(WakelockPlus.disable()); // 离开播放页恢复系统息屏策略
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _dragging = false;

  PlayerRoute? get _route {
    final r = ModalRoute.of(context);
    return r is PlayerRoute ? r : null;
  }

  void _start(DragStartDetails _) {
    final r = _route;
    if (r == null || r.navigator == null) return;
    _dragging = true;
    r.navigator!.didStartUserGesture();
  }

  void _update(DragUpdateDetails d) {
    final r = _route;
    if (!_dragging || r == null) return;
    final h = MediaQuery.of(context).size.height;
    r.ctl.value = (r.ctl.value - (d.primaryDelta ?? 0) / h).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final r = _route;
    if (!_dragging || r == null) return;
    _dragging = false;
    final nav = r.navigator!;
    final v = d.primaryVelocity ?? 0;
    final close = r.ctl.value < .82 || v > 800;
    if (close) {
      nav.pop();
    } else {
      r.ctl.animateTo(1, duration: const Duration(milliseconds: 260), curve: Tk.out);
    }
    if (r.ctl.isAnimating) {
      late AnimationStatusListener l;
      l = (s) {
        if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
          r.ctl.removeStatusListener(l);
          nav.didStopUserGesture();
        }
      };
      r.ctl.addStatusListener(l);
    } else {
      nav.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final sk = skinBy(app.skin);
    final mq = MediaQuery.of(context);
    final full = app.skin == 'standby';
    return GestureDetector(
      onVerticalDragStart: _start,
      onVerticalDragUpdate: _update,
      onVerticalDragEnd: _end,
      onVerticalDragCancel: () => _end(DragEndDetails()),
      child: Material(
        color: Colors.black,
        child: Stack(children: [
          if (sk.usesBg) Positioned.fill(child: RepaintBoundary(child: PlayerBackground(song: app.song, mode: app.bg, tone: app.tone, dim: app.dim, beat: true))),
          Positioned.fill(child: Padding(padding: EdgeInsets.only(top: full ? 0 : mq.padding.top, bottom: full ? 0 : mq.padding.bottom), child: RepaintBoundary(child: SkinHost(skin: app.skin)))),
        ]),
      ),
    );
  }
}

// ======================= 背景层 =======================
class PlayerBackground extends StatefulWidget {
  final Song song;
  final String mode, tone;
  final double dim;
  final bool preview, beat;
  const PlayerBackground({super.key, required this.song, required this.mode, required this.tone, required this.dim, this.preview = false, this.beat = false});
  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = widget.song;
    final still = app.set.reduceMotion || widget.mode != 'flow';
    Widget base;
    if (widget.mode == 'blur') {
      // 极小图放大代替实时高斯模糊：播放页常驻，ImageFiltered 每帧重算是老机型卡顿的主因之一
      base = ColorFiltered(colorFilter: const ColorFilter.matrix(_sat15), child: Transform.scale(scale: 1.2, child: BlurCover.song(s, px: widget.preview ? 32 : 16)));
    } else {
      base = RepaintBoundary(child: AnimatedBuilder(
        animation: c,
        builder: (_, __) => ValueListenableBuilder<double>(
          valueListenable: app.pos,
          builder: (_, p, __) => CustomPaint(painter: _FlowPainter(songColors(s), still ? 0 : c.value, widget.beat && app.playing ? app.beat() : 0)),
        ),
      ));
    }
    final light = widget.tone == 'light';
    return Stack(fit: StackFit.expand, children: [
      Container(color: const Color(0xFF0B0C12)),
      base,
      const RepaintBoundary(child: CustomPaint(painter: _Noise())),
      Container(color: light ? Colors.white.withValues(alpha: widget.dim / 100 * .6) : Colors.black.withValues(alpha: widget.dim / 100)),
    ]);
  }
}

const _sat15 = <double>[1.35, -.25, -.1, 0, 0, -.15, 1.3, -.15, 0, 0, -.1, -.25, 1.35, 0, 0, 0, 0, 0, 1, 0];

class _FlowPainter extends CustomPainter {
  final List<Color> cols;
  final double t, beat;
  _FlowPainter(this.cols, this.t, this.beat);
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.max(s.width, s.height);
    final pts = [const Offset(.2, .2), const Offset(.85, .3), const Offset(.3, .75), const Offset(.8, .85)];
    for (var i = 0; i < 4; i++) {
      final a = t * math.pi * 2 * (i.isEven ? 1 : -1) + i * 1.7;
      final o = Offset(s.width * (pts[i].dx + math.sin(a) * .12), s.height * (pts[i].dy + math.cos(a * .9) * .1));
      final rad = r * (.55 + .08 * math.sin(a * 1.3)) * (1 + beat * .05);
      canvas.drawCircle(o, rad, Paint()
        ..shader = ui.Gradient.radial(o, rad, [cols[i].withValues(alpha: .85), cols[i].withValues(alpha: 0)])
        ..blendMode = BlendMode.screen);
    }
  }

  @override
  bool shouldRepaint(_FlowPainter o) => o.t != t || o.beat != beat || o.cols.first != cols.first;
}

class _Noise extends CustomPainter {
  const _Noise();
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(3);
    final p = Paint()..color = const Color(0x0FFFFFFF);
    final pts = <Offset>[for (var i = 0; i < (s.width * s.height / 60).clamp(0, 9000).toInt(); i++) Offset(r.nextDouble() * s.width, r.nextDouble() * s.height)];
    canvas.drawPoints(ui.PointMode.points, pts, p..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_Noise o) => false;
}

// ======================= 通用骨架组件 =======================
class PlayerTopBar extends StatelessWidget {
  final Color color;
  final Widget? center;
  const PlayerTopBar({super.key, this.color = Colors.white, this.center});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SizedBox(
      height: 52,
      child: Row(children: [
        const SizedBox(width: 6),
        IBtn('down', color: color, iconSize: 28, onTap: () => Navigator.of(context).pop()),
        Expanded(
          child: center ??
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('正在播放', style: ts(11, w: FontWeight.w600, c: color.withValues(alpha: .6), ls: 1)),
                Text(app.queueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w600, c: color)),
              ]),
        ),
        IBtn('more', color: color, onTap: () => openSongMore(context, app.cur, '', dark: true)),
        const SizedBox(width: 6),
      ]),
    );
  }
}

class SongInfo extends StatelessWidget {
  final double size;
  final Color color;
  final bool center;
  const SongInfo({super.key, this.size = 22, this.color = Colors.white, this.center = false});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    final col = Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
      center ? Text(s.title, style: ts(size, w: FontWeight.w800, c: color)) : Marquee(s.title, style: ts(size, w: FontWeight.w800, c: color)),
      const SizedBox(height: 4),
      Row(mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max, children: [
        Flexible(child: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, c: color.withValues(alpha: .7)))),
        const SizedBox(width: 8),
        GestureDetector(onTap: () => openQuality(context, dark: true), child: QBadge(app.quality, color: context.pal.acc)),
      ]),
    ]);
    if (center) return Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: col);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 14, 0),
      child: Row(children: [Expanded(child: col), HeartBtn(app.cur, size: 26, offColor: color.withValues(alpha: .7))]),
    );
  }
}

/// 进度条：触控区 20 高，轨道 4；拖动时轨道变 8、拇指 ×1.5；右侧显示剩余时间。
class ProgressBar extends StatefulWidget {
  final double track, trackDrag;
  final Color color, fg;
  final bool showTimes;
  final EdgeInsets padding;
  const ProgressBar({super.key, this.track = 4, this.trackDrag = 8, this.color = Colors.white, this.fg = Colors.white, this.showTimes = true, this.padding = const EdgeInsets.symmetric(horizontal: 28)});
  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  double? dragP;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final dur = app.song.dur.toDouble();
    return Padding(
      padding: widget.padding,
      child: ValueListenableBuilder<double>(
        valueListenable: app.pos,
        builder: (_, pos, __) {
          final p = dragP ?? (pos / dur).clamp(0.0, 1.0);
          return Column(children: [
            LayoutBuilder(builder: (c, cs) {
              final w = cs.maxWidth;
              final th = dragP != null ? widget.trackDrag : widget.track;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragCancel: () => setState(() => dragP = null),
                onHorizontalDragStart: (d) => setState(() => dragP = (d.localPosition.dx / w).clamp(0, 1)),
                onHorizontalDragUpdate: (d) => setState(() => dragP = (d.localPosition.dx / w).clamp(0, 1)),
                onHorizontalDragEnd: (_) {
                  app.seek(dragP! * dur);
                  setState(() => dragP = null);
                },
                onTapUp: (d) => app.seek((d.localPosition.dx / w).clamp(0, 1) * dur),
                child: SizedBox(
                  height: 40, // 触控区：轨道只有几像素，原来 20 高很难按住
                  child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
                    AnimatedContainer(duration: Tk.base, curve: Tk.spring, height: th, decoration: BoxDecoration(color: widget.color.withValues(alpha: .18), borderRadius: BorderRadius.circular(th))),
                    AnimatedContainer(duration: Tk.base, curve: Tk.spring, height: th, width: w * math.min(1, p + .22), decoration: BoxDecoration(color: widget.color.withValues(alpha: .22), borderRadius: BorderRadius.circular(th))),
                    AnimatedContainer(duration: Tk.base, curve: Tk.spring, height: th, width: w * p, decoration: BoxDecoration(color: widget.fg, borderRadius: BorderRadius.circular(th))),
                    Positioned(
                      left: w * p - 6,
                      child: AnimatedScale(scale: dragP != null ? 1.5 : 1, duration: Tk.base, curve: Tk.spring, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: widget.fg, shape: BoxShape.circle))),
                    ),
                  ]),
                ),
              );
            }),
            if (widget.showTimes)
              Row(children: [
                Text(fmtTime(p * dur), style: ts(11.5, c: widget.color.withValues(alpha: .6), num: true)),
                const Spacer(),
                Text('-${fmtTime(dur - p * dur)}', style: ts(11.5, c: widget.color.withValues(alpha: .6), num: true)),
              ]),
          ]);
        },
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  final double size;
  final Color bg, fg;
  const PlayButton({super.key, this.size = 76, this.bg = Colors.white, this.fg = Colors.black});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Press(
      onTap: app.toggle,
      scale: .9,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: bg == Colors.transparent ? null : const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))]),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(ic(app.playing ? 'pause' : 'play'), key: ValueKey(app.playing), size: size * .46, color: fg),
        ),
      ),
    );
  }
}

class MainControls extends StatelessWidget {
  final Color color;
  final bool circle;
  final double playSize;
  const MainControls({super.key, this.color = Colors.white, this.circle = true, this.playSize = 76});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IBtn(const {'loop': 'repeat', 'one': 'repeat1', 'shuffle': 'shuffle', 'order': 'order'}[app.mode]!, color: app.mode == 'loop' ? color.withValues(alpha: .7) : context.pal.acc, onTap: () {
          app.cycleMode();
          toast(app.modeName, 'repeat');
        }),
        IBtn('prev', color: color, iconSize: 34, size: 56, onTap: app.prev),
        circle ? PlayButton(size: playSize, bg: color, fg: Colors.black) : PlayButton(size: playSize, bg: Colors.transparent, fg: color),
        IBtn('next', color: color, iconSize: 34, size: 56, onTap: app.next),
        IBtn('queue', color: color.withValues(alpha: .7), onTap: () => openQueue(context)),
      ]),
    );
  }
}

class AuxRow extends StatelessWidget {
  final Color color;
  final VoidCallback? onLyric;
  final bool lyricOn;
  const AuxRow({super.key, this.color = Colors.white, this.onLyric, this.lyricOn = false});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final acc = context.pal.acc;
    final c = color.withValues(alpha: .7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IBtn('lyric', color: lyricOn ? acc : c, iconSize: 20, onTap: onLyric ?? () => openLyricQuick(context)),
        IBtn('cast', color: app.castDev != null ? acc : c, iconSize: 20, onTap: () => openCast(context, dark: true)),
        IBtn('moon', color: app.timer > 0 ? acc : c, iconSize: 20, onTap: () => openTimer(context, dark: true)),
        IBtn('sliders', color: app.eqOn ? acc : c, iconSize: 20, onTap: () => openEq(context, dark: true)),
        IBtn('palette', color: c, iconSize: 20, onTap: () => openSkins(context, dark: true)),
      ]),
    );
  }
}

/// 歌词快调：字号、±0.5s、翻译、模糊 → 全部歌词设置。
void openLyricQuick(BuildContext context) {
  showLSheet(context, title: '歌词快调', dark: true, builder: (c) {
    final app = c.app;
    final s = app.set;
    final pal = c.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        LSlider(label: '字号', value: s.lfs, min: 16, max: 40, step: 1, fmt: (v) => '${v.round()}px', onChanged: (v) => app.update(() => s.lfs = v)),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 74, child: Text('偏移', style: ts(14, c: pal.t2))),
          Btn.sec('-0.5s', small: true, onTap: () => app.update(() => s.loff = (s.loff - .5).clamp(-3, 3))),
          Expanded(child: Text('${s.loff > 0 ? '+' : ''}${s.loff.toStringAsFixed(1)}s', textAlign: TextAlign.center, style: ts(16, w: FontWeight.w700, c: pal.t1, num: true))),
          Btn.sec('+0.5s', small: true, onTap: () => app.update(() => s.loff = (s.loff + .5).clamp(-3, 3))),
        ]),
        const SizedBox(height: 14),
        Group(children: [
          Item(label: '显示翻译', sw: s.trans, onSw: (v) => app.update(() => s.trans = v)),
          Item(label: '非当前行模糊', sw: s.blur, onSw: (v) => app.update(() => s.blur = v)),
          Item(label: '逐字辉光', sw: s.glow, onSw: (v) => app.update(() => s.glow = v)),
        ]),
        Btn.sec('全部歌词设置', block: true, onTap: () {
          Navigator.of(c).pop();
          Navigator.of(context).pop();
          rootNav.currentState!.push(MaterialPageRoute(builder: (_) => AppScope(state: app, child: PalScope(pal: context.pal, child: const LyricsSettingsPage()))));
        }),
      ]),
    );
  });
}
