// 横屏皮肤（待机 · 唱片 · 时钟）。参照 QQ 音乐横屏播放页（HorizontalScreenPlayerActivity）的做法：
// - 页面分「普通态」（封面 + 信息 + 进度 + 控制 + 歌词 + 右侧功能坞）和「全屏态」（沉浸大字）两套，
//   两套内容一直挂着，切换只做 500ms 交叉淡化，曲线 Cubic(0.32, 0.94, 0.6, 1)（快出缓收、不回弹）；
// - 状态先行、动画跟随，动画进行中不接受再次切换（防连点抖动）；
// - 普通态一段时间没操作、且在播放时，自动进全屏态（待机 / 床头）；全屏态点一下回普通态；
// - 不用系统转场，横竖屏切换由播放器页自己处理（进入时锁横屏、离开时恢复竖屏）。
part of 'skins.dart';

const _landCurve = Cubic(.32, .94, .6, 1);
const _landSwitch = Duration(milliseconds: 500);
const _landIdle = Duration(seconds: 12);

class LandscapeShell extends StatefulWidget {
  final Widget Function(BuildContext context, Size size) background;
  final Widget Function(BuildContext context, Size size) normal;
  final Widget Function(BuildContext context, Size size) full;

  /// 普通态的底色压暗（文字可读）；全屏态淡掉。
  final Color scrim;
  const LandscapeShell({super.key, required this.background, required this.normal, required this.full, this.scrim = const Color(0x59000000)});
  @override
  State<LandscapeShell> createState() => _LandscapeShellState();
}

class _LandscapeShellState extends State<LandscapeShell> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: _landSwitch);
  late final fade = CurvedAnimation(parent: c, curve: _landCurve, reverseCurve: _landCurve.flipped);
  bool fullMode = false;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _arm();
  }

  @override
  void dispose() {
    _idle?.cancel();
    c.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 普通态无操作计时：到点且在播放就进全屏态。
  void _arm() {
    _idle?.cancel();
    if (fullMode) return;
    _idle = Timer(_landIdle, () {
      if (!mounted || fullMode) return;
      if (context.appRead.playing) {
        _setMode(true);
      } else {
        _arm();
      }
    });
  }

  void _setMode(bool full) {
    if (c.isAnimating || full == fullMode) return; // 动画中不重入
    setState(() => fullMode = full); // 状态先行
    full ? c.forward() : c.reverse();
    _arm();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cs) {
      final size = cs.biggest;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _arm(), // 有操作就重新计时
        child: Stack(children: [
          Positioned.fill(child: RepaintBoundary(child: widget.background(context, size))),
          // 普通态压暗层：随全屏淡出
          Positioned.fill(child: IgnorePointer(child: FadeTransition(opacity: ReverseAnimation(fade), child: ColoredBox(color: widget.scrim)))),
          // 两套内容常驻，只做互补淡化（合成器友好，不重新布局）
          Positioned.fill(
            child: IgnorePointer(
              ignoring: fullMode,
              child: FadeTransition(opacity: ReverseAnimation(fade), child: RepaintBoundary(child: _Normal(shell: this, size: size))),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !fullMode,
              child: FadeTransition(
                opacity: fade,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setMode(false), child: RepaintBoundary(child: widget.full(context, size))),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// 普通态：皮肤内容 + 右侧功能坞（QQ 横屏页右侧那条窄坞：圆形功能钮竖排）。
class _Normal extends StatelessWidget {
  final _LandscapeShellState shell;
  final Size size;
  const _Normal({required this.shell, required this.size});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pad = MediaQuery.of(context).padding;
    final dockW = math.max(60.0, size.height * 90 / 844 * 1.4);
    Widget btn(String icon, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Press(
            onTap: onTap,
            scale: .88,
            child: Container(width: 42, height: 42, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1FFFFFFF)), child: Icon(ic(icon), size: 20, color: color ?? Colors.white.withValues(alpha: .9))),
          ),
        );
    final liked = app.liked.contains(app.cur);
    return Row(children: [
      // 上下留白：原来封面顶到屏幕上沿、播放键贴着下沿
      Expanded(child: Padding(padding: EdgeInsets.fromLTRB(math.max(pad.left, 28), 22, 0, 14), child: shell.widget.normal(context, Size(size.width - dockW - math.max(pad.left, 28), size.height - 36)))),
      SizedBox(
        width: dockW + pad.right,
        child: Padding(
          padding: EdgeInsets.only(right: pad.right),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            btn('close', () => Navigator.of(context).maybePop()),
            const SizedBox(height: 6),
            btn(liked ? 'heartf' : 'heart', () => app.update(() => app.toggleLike(app.cur)), color: liked ? const Color(0xFFFF4D6D) : null),
            btn(const {'loop': 'repeat', 'one': 'repeat1', 'shuffle': 'shuffle', 'order': 'order'}[app.mode]!, () {
              app.cycleMode();
              toast(app.modeName, 'repeat');
            }),
            btn('queue', () => openQueue(context)),
            btn('expand', () => shell._setMode(true)),
          ]),
        ),
      ),
    ]);
  }
}

/// 普通态左栏通用：封面 / 唱片位 + 歌名歌手 + 进度 + 控制。
class _LandInfo extends StatelessWidget {
  final Widget art;
  const _LandInfo({required this.art});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    final white = Colors.white.withValues(alpha: .92);
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: Center(child: art)),
      const SizedBox(height: 14),
      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: ts(17, w: FontWeight.w700, c: white)),
      const SizedBox(height: 2),
      Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: ts(12.5, c: Colors.white.withValues(alpha: .6))),
      const SizedBox(height: 4),
      const ProgressBar(padding: EdgeInsets.symmetric(horizontal: 12), track: 3, trackDrag: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IBtn('prev', color: white, iconSize: 28, size: 48, onTap: app.prev),
        const SizedBox(width: 14),
        PlayButton(size: 52, bg: white, fg: Colors.black),
        const SizedBox(width: 14),
        IBtn('next', color: white, iconSize: 28, size: 48, onTap: app.next),
      ]),
    ]);
  }
}

/// 全屏态底部小信息条（封面 · 歌名 · 进度细线）。
class _LandMini extends StatelessWidget {
  const _LandMini();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    return Row(children: [
      Cover.song(s, size: 36, radius: 6),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${s.title} · ${s.artist}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, c: Colors.white.withValues(alpha: .8))),
          const SizedBox(height: 6),
          ValueListenableBuilder<double>(
            valueListenable: app.pos,
            builder: (_, p, __) => ClipRRect(borderRadius: BorderRadius.circular(1), child: LinearProgressIndicator(value: s.dur > 0 ? (p / s.dur).clamp(0.0, 1.0) : 0, minHeight: 2, color: Colors.white.withValues(alpha: .75), backgroundColor: Colors.white.withValues(alpha: .15))),
          ),
        ]),
      ),
      const SizedBox(width: 12),
      Icon(ic(app.playing ? 'pause' : 'play'), size: 18, color: Colors.white.withValues(alpha: .6)),
    ]);
  }
}

/// 每秒刷新的时钟。
class _Clock extends StatefulWidget {
  final Widget Function(DateTime now) builder;
  const _Clock({required this.builder});
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}

const _wk = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
String _hm(DateTime n) => '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------- 待机

/// 待机：两侧随节拍荡开的波光。普通态左封面右歌词；全屏态衬线大字歌词 + 时钟。
class StandbySkin extends StatefulWidget {
  const StandbySkin({super.key});
  @override
  State<StandbySkin> createState() => _StandbySkinState();
}

class _StandbySkinState extends State<StandbySkin> {
  double _phase = 0, _lastT = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    return LandscapeShell(
      background: (c, size) => Ticker2(builder: (c, t) {
        if (app.playing && !app.set.reduceMotion) _phase += (t - _lastT).clamp(0.0, .1);
        _lastT = t;
        return CustomPaint(painter: WaveGlowPainter(songHue(s), _phase, app.playing ? app.beat() : 0));
      }),
      normal: (c, size) => Row(children: [
        SizedBox(width: size.width * .4, child: _LandInfo(art: AspectRatio(aspectRatio: 1, child: Cover.song(s, size: 0, radius: 14, shadow: true)))),
        const SizedBox(width: 22),
        Expanded(child: LyricView(anchor: .45, compact: true, fontSize: math.max(18, size.height * .05), padding: const EdgeInsets.symmetric(horizontal: 4))),
      ]),
      full: (c, size) {
        final short = math.min(size.width, size.height);
        final white = Colors.white.withValues(alpha: .88);
        return Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(size.width * .1, 0, size.width * .1, short * .2),
              child: Center(child: _StandbyLyric(size: short * .1, hue: songHue(s))),
            ),
          ),
          Positioned(
            left: size.width * .08,
            top: short * .08,
            child: _Clock(builder: (n) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_hm(n), style: ts(28, w: FontWeight.w300, c: white, num: true)),
                  const SizedBox(width: 10),
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${n.month} 月 ${n.day} 日 ${_wk[n.weekday - 1]}', style: ts(13, c: Colors.white.withValues(alpha: .6)))),
                ])),
          ),
          Positioned(left: size.width * .08, right: size.width * .08, bottom: short * .07, child: const _LandMini()),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- 唱片

/// 唱片：模糊封面背景。普通态左边旋转黑胶、右边歌词；全屏态大唱片压在左侧屏外、右侧大字三行歌词。
class LandVinylSkin extends StatelessWidget {
  const LandVinylSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    Widget disc(double d) => Spin(
          on: app.playing,
          period: const Duration(seconds: 12),
          child: SizedBox(width: d, height: d, child: CustomPaint(painter: const _DiscPainter(), child: Center(child: ClipOval(child: Cover.song(s, size: d * .62, radius: d * .31))))),
        );
    return LandscapeShell(
      scrim: const Color(0x33000000),
      background: (c, size) => Stack(fit: StackFit.expand, children: [BlurCover.song(s, px: 16), const ColoredBox(color: Color(0x99000000))]),
      normal: (c, size) => Row(children: [
        SizedBox(width: size.width * .42, child: _LandInfo(art: disc(math.min(size.width * .3, size.height * .52)))),
        const SizedBox(width: 22),
        Expanded(child: LyricView(anchor: .45, compact: true, fontSize: math.max(18, size.height * .05), padding: const EdgeInsets.symmetric(horizontal: 4))),
      ]),
      full: (c, size) {
        final d = size.height * 1.05;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(left: -d * .42, top: (size.height - d) / 2, child: disc(d)),
          Positioned(
            left: d * .64,
            right: size.width * .06,
            top: 0,
            bottom: 0,
            child: Center(child: Lyric3(size: math.max(22, size.height * .075))),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- 时钟

/// 时钟：床头 / 桌面待机。普通态左边大时钟、右边封面 + 歌词；全屏态只留超大时钟和当前一句。
class LandClockSkin extends StatelessWidget {
  const LandClockSkin({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.song;
    final hue = songHue(s);
    return LandscapeShell(
      scrim: const Color(0x00000000),
      background: (c, size) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hsl(hue, .35, .07), hsl(hue, .45, .14)]))),
      normal: (c, size) => Row(children: [
        Expanded(
          flex: 5,
          child: _Clock(builder: (n) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_hm(n), style: ts(size.height * .26, w: FontWeight.w200, c: Colors.white, num: true, h: 1)),
                const SizedBox(height: 6),
                Text('${n.month} 月 ${n.day} 日 · ${_wk[n.weekday - 1]}', style: ts(15, c: Colors.white.withValues(alpha: .6))),
              ])),
        ),
        Expanded(
          flex: 4,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Cover.song(s, size: 56, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15.5, w: FontWeight.w700, c: Colors.white)),
                  Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: Colors.white.withValues(alpha: .6))),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(height: size.height * .32, child: LyricView(anchor: .5, compact: true, fontSize: 16, padding: EdgeInsets.zero)),
            const SizedBox(height: 6),
            const ProgressBar(padding: EdgeInsets.zero, track: 3, trackDrag: 6, showTimes: false),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IBtn('prev', color: Colors.white, iconSize: 26, onTap: app.prev),
              const SizedBox(width: 10),
              PlayButton(size: 46, bg: Colors.white.withValues(alpha: .92), fg: Colors.black),
              const SizedBox(width: 10),
              IBtn('next', color: Colors.white, iconSize: 26, onTap: app.next),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
      ]),
      full: (c, size) => _Clock(builder: (n) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_hm(n), style: ts(size.height * .38, w: FontWeight.w100, c: Colors.white.withValues(alpha: .92), num: true, h: 1)),
            const SizedBox(height: 8),
            Text('${n.month} 月 ${n.day} 日 · ${_wk[n.weekday - 1]}', style: ts(15, c: Colors.white.withValues(alpha: .5))),
            const SizedBox(height: 18),
            Padding(padding: EdgeInsets.symmetric(horizontal: size.width * .12), child: Lyric3(size: math.max(16, size.height * .05))),
          ])),
    );
  }
}
