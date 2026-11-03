// 扫一扫（设备登录 / 歌单码 / 分享码）+ 听歌识曲，全屏暗色，底部分段切换。
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'detail.dart';
import '../shell/shell.dart';

class ScanPage extends StatefulWidget {
  final bool match;
  const ScanPage({super.key, this.match = false});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with TickerProviderStateMixin {
  late bool match = widget.match;
  String? result; // device | playlist | song
  int deviceStep = 0;
  String matchState = 'listen';
  Timer? mt;
  late final scanC = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  late final ringC = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void initState() {
    super.initState();
    if (match) _listen();
  }

  void _listen() {
    mt?.cancel();
    setState(() => matchState = 'listen');
    mt = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => matchState = 'done');
    });
  }

  @override
  void dispose() {
    mt?.cancel();
    scanC.dispose();
    ringC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal.forceDark;
    final mq = MediaQuery.of(context);
    return PalScope(
      pal: pal,
      child: Scaffold(
        backgroundColor: const Color(0xFF050608),
        body: Stack(children: [
          Positioned.fill(child: AnimatedSwitcher(duration: const Duration(milliseconds: 360), child: match ? _matchView(pal) : (result == null ? _scanView(pal) : _resultView(pal)))),
          Positioned(top: mq.padding.top + 4, left: 8, child: IBtn('close', color: Colors.white, onTap: () => Navigator.of(context).pop())),
          Positioned(
            left: 60,
            right: 60,
            bottom: mq.padding.bottom + 20,
            child: Seg(const ['扫一扫', '听歌识曲'], match ? '听歌识曲' : '扫一扫', (v) {
              setState(() {
                match = v == '听歌识曲';
                result = null;
              });
              if (match) _listen();
            }, margin: EdgeInsets.zero),
          ),
        ]),
      ),
    );
  }

  Widget _scanView(Pal pal) {
    return Column(key: const ValueKey('scan'), children: [
      const Spacer(flex: 2),
      SizedBox(
        width: 250,
        height: 250,
        child: AnimatedBuilder(
          animation: scanC,
          builder: (_, __) => CustomPaint(
            painter: _Finder(pal.acc, 1 + math.sin(scanC.value * math.pi) * .04),
            child: Stack(children: [
              Positioned(
                left: 14,
                right: 14,
                top: 10 + 222 * scanC.value,
                child: Container(height: 2, decoration: BoxDecoration(color: pal.acc, boxShadow: [BoxShadow(color: pal.acc, blurRadius: 14, spreadRadius: 2)])),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text('对准二维码，自动识别', style: ts(14, c: const Color(0xB3FFFFFF))),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        child: Row(children: [
          for (final (k, i, t, d) in const [('device', 'tv', '设备登录', '电视 / 车机 / 桌面端'), ('playlist', 'qr', '歌单码', '打开歌单'), ('song', 'share', '分享码', '好友分享的歌')])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Press(
                  onTap: () => setState(() {
                    result = k;
                    deviceStep = 0;
                  }),
                  child: Glass(
                    radius: 18,
                    color: const Color(0x991A1C26),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(ic(i), color: pal.acc, size: 22),
                        const SizedBox(height: 8),
                        Text(t, style: ts(13.5, w: FontWeight.w700, c: Colors.white)),
                        Text(d, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(10.5, c: const Color(0x8CFFFFFF))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _resultView(Pal pal) {
    final app = context.app;
    Widget card;
    if (result == 'device') {
      card = deviceStep == 1
          ? Column(children: [
              TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 600), curve: Tk.spring, builder: (_, v, __) => Transform.scale(scale: v, child: Icon(Icons.check_circle_rounded, color: pal.ok, size: 72))),
              const SizedBox(height: 14),
              Text('客厅电视 已登录', style: ts(18, w: FontWeight.w700, c: Colors.white)),
              const SizedBox(height: 18),
              Btn('完成', block: true, onTap: () => Navigator.of(context).pop()),
            ])
          : Column(children: [
              Icon(ic('tv'), size: 56, color: pal.acc),
              const SizedBox(height: 12),
              Text('登录到这台设备？', style: ts(18, w: FontWeight.w700, c: Colors.white)),
              const SizedBox(height: 14),
              for (final (k, v) in const [('设备', '客厅电视'), ('系统', 'Android TV 13'), ('IP', '192.168.1.24 · 与你在同一网络')])
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [SizedBox(width: 44, child: Text(k, style: ts(13, c: const Color(0x8CFFFFFF)))), Expanded(child: Text(v, style: ts(13, w: FontWeight.w600, c: Colors.white)))])),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Btn.sec('取消', onTap: () => setState(() => result = null))),
                const SizedBox(width: 10),
                Expanded(child: Btn('确认登录', onTap: () => setState(() => deviceStep = 1))),
              ]),
            ]);
    } else if (result == 'playlist') {
      final p = playlists[3];
      card = Column(children: [
        Cover.pl(p, size: 160, radius: 22),
        const SizedBox(height: 14),
        Text(p.title, style: ts(18, w: FontWeight.w700, c: Colors.white)),
        Text('${p.by} · ${p.count} 首', style: ts(13, c: const Color(0x99FFFFFF))),
        const SizedBox(height: 18),
        Btn('打开歌单', block: true, onTap: () {
          Navigator.of(context).pop();
          push(context, PlaylistPage(id: p.id));
        }),
      ]);
    } else {
      final s = songs[7];
      card = Column(children: [
        Cover.song(s, size: 160, radius: 22, shadow: true),
        const SizedBox(height: 14),
        Text(s.title, style: ts(18, w: FontWeight.w700, c: Colors.white)),
        Text(s.artist, style: ts(13, c: const Color(0x99FFFFFF))),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(14)), child: Text('「Mo：这首睡前听特别好」', style: ts(13, c: const Color(0xD9FFFFFF)))),
        const SizedBox(height: 18),
        Btn('立即播放', icon: 'play', block: true, onTap: () {
          app.play(s.id, list: 'all');
          Navigator.of(context).pop();
        }),
      ]);
    }
    return Center(
      key: ValueKey('r$result$deviceStep'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Glass(radius: 26, color: const Color(0xCC14151E), child: Padding(padding: const EdgeInsets.all(22), child: card)),
      ),
    );
  }

  Widget _matchView(Pal pal) {
    final app = context.app;
    if (matchState == 'done') {
      final s = songs[4];
      return Column(key: const ValueKey('done'), children: [
        const Spacer(),
        TweenAnimationBuilder<double>(tween: Tween(begin: .4, end: 1), duration: const Duration(milliseconds: 620), curve: Tk.spring, builder: (_, v, ch) => Transform.scale(scale: v, child: ch), child: Cover.song(s, size: 200, radius: 26, shadow: true)),
        const SizedBox(height: 18),
        const Badge2('匹配度 98%', acc: true),
        const SizedBox(height: 10),
        Text(s.title, style: ts(24, w: FontWeight.w800, c: Colors.white)),
        Text('${s.artist} · ${s.album}', style: ts(14, c: const Color(0x99FFFFFF))),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(children: [
            Expanded(child: Btn('播放', icon: 'play', onTap: () {
              app.play(s.id, list: 'all');
              Navigator.of(context).pop();
            })),
            const SizedBox(width: 10),
            Expanded(child: Btn.sec('收藏', icon: 'heart', onTap: () {
              if (!app.liked.contains(s.id)) app.toggleLike(s.id);
              toast('已收藏到「我喜欢」', 'heartf');
            })),
          ]),
        ),
        const SizedBox(height: 10),
        Press(onTap: _listen, child: Padding(padding: const EdgeInsets.all(12), child: Text('再识别一首', style: ts(14, w: FontWeight.w600, c: pal.acc)))),
        const Spacer(),
        const SizedBox(height: 90),
      ]);
    }
    return Column(key: const ValueKey('listen'), children: [
      const Spacer(flex: 2),
      SizedBox(
        width: 280,
        height: 280,
        child: AnimatedBuilder(
          animation: ringC,
          builder: (_, __) => CustomPaint(
            painter: _Rings(ringC.value, pal.acc),
            child: Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [pal.acc, Color.lerp(pal.acc, Colors.black, .35)!]), boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 40, spreadRadius: 6)]),
                child: Icon(ic('mic'), size: 46, color: pal.ink),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 40,
        child: AnimatedBuilder(
          animation: ringC,
          builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 32; i++)
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: 6 + 30 * (.5 + .5 * math.sin(ringC.value * math.pi * 8 + i * .7)).abs() * (1 - (i - 15.5).abs() / 20),
                decoration: BoxDecoration(color: pal.acc.withValues(alpha: .8), borderRadius: BorderRadius.circular(2)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Text('正在聆听…', style: ts(18, w: FontWeight.w700, c: Colors.white)),
      const SizedBox(height: 4),
      Text('请把手机靠近声源', style: ts(13, c: const Color(0x8CFFFFFF))),
      const Spacer(flex: 3),
    ]);
  }
}

class _Finder extends CustomPainter {
  final Color c;
  final double s;
  _Finder(this.c, this.s);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-size.width / 2, -size.height / 2);
    final p = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    final w = size.width, h = size.height;
    for (final (o, dx, dy) in [(Offset.zero, 1.0, 1.0), (Offset(w, 0), -1.0, 1.0), (Offset(0, h), 1.0, -1.0), (Offset(w, h), -1.0, -1.0)]) {
      canvas.drawPath(Path()
        ..moveTo(o.dx, o.dy + l * dy)
        ..lineTo(o.dx, o.dy + 8 * dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + 8 * dx, o.dy)
        ..lineTo(o.dx + l * dx, o.dy), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Finder o) => o.s != s;
}

/// 3 道扩散环（2.6s，错相 0.85s）——识曲与声波皮肤共用。
class _Rings extends CustomPainter {
  final double t;
  final Color c;
  _Rings(this.t, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      canvas.drawCircle(s.center(Offset.zero), 60 + k * 80, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = c.withValues(alpha: (1 - k) * .6));
    }
  }

  @override
  bool shouldRepaint(_Rings o) => o.t != t;
}
