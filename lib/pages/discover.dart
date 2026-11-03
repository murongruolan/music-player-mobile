// 发现：音源选择器 · 未登录一行登录卡 + Banner · 为你定制 · 我的歌单 · 快捷入口 · 精选/榜单/歌单 · 平台推荐区。
// 模块可在「外观 → 首页内容与顺序」开关与排序。
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../platform/registry.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/picker.dart';
import '../widgets/sheets.dart';
import 'common.dart';
import 'detail.dart';
import 'misc.dart';
import 'remote.dart';
import 'scan.dart';

class PlatFeat {
  final int lv, like, mine, fav;
  final String vip;
  final List<(String, String, String)> hero;
  final List<String> mySeg;
  final String? extra;
  const PlatFeat(this.lv, this.vip, this.like, this.mine, this.fav, this.hero, this.mySeg, this.extra);
}

const platFeat = <String, PlatFeat>{
  'netease': PlatFeat(8, '黑胶VIP', 128, 12, 8, [('daily', '每日推荐', '每天 06:00 按你的口味更新'), ('heart', '心动模式', '从你喜欢的歌出发，越听越懂你')], ['我创建的', '我收藏的'], null),
  'qq': PlatFeat(6, '绿钻', 342, 9, 15, [('daily', '每日 30 首', '每天为你挑 30 首'), ('radar', '雷达推荐', '扫描你的口味，雷达捕捉新歌')], ['我喜欢', '个人歌单'], '新歌推荐'),
  'kugou': PlatFeat(5, '概念VIP', 96, 4, 6, [('daily', '每日推荐', '今日为你精选'), ('heart', '猜你喜欢', '私人电台，一直播下去')], ['我喜欢', '自建歌单'], '新歌首发'),
  'kuwo': PlatFeat(4, '豪华VIP', 51, 3, 2, [('daily', '每日推荐', '今日为你精选'), ('radar', '私人 FM', '按口味连续播放')], ['我喜欢', '自建歌单'], null),
  'migu': PlatFeat(3, '白金会员', 20, 2, 1, [('daily', '每日推荐', '今日为你精选'), ('radar', '新歌雷达', '首发新歌第一时间推给你')], ['我喜欢', '自建歌单'], '新歌首发'),
};

const platRec = <String, List<String>>{
  'netease': ['albums', 'newsongs', 'official', 'plcats', 'genres', 'mvrank', 'videos'],
  'qq': ['nowlisten', 'mood', 'fresh', 'official', 'mvrank'],
  'kugou': ['nowlisten', 'mood', 'fresh', 'official', 'videos'],
  'kuwo': ['newsongs', 'official', 'plcats', 'mvrank'],
  'migu': ['fresh', 'albums', 'official', 'videos'],
};

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.online) return const _OnlineDiscover();
    final logged = app.isIn(app.plat);
    final mods = <Widget>[];
    for (final m in app.homeMods) {
      if (!m.value) continue;
      switch (m.key) {
        case 'custom':
          if (logged) mods.addAll([const _PlatAccount(), const _Custom()]);
          break;
        case 'mypl':
          if (logged) mods.add(const _MyPlaylists());
          break;
        case 'quick':
          mods.add(QuickGrid([
            ('sun', '每日混音', () => context.appRead.update(() => context.appRead.tab = 2)),
            ('wave', '私人电台', () {
              app.playAll('hot', shuffle: true, name: '私人电台');
              toast('私人电台：按你的口味连续播放', 'wave');
            }),
            ('mic', '听歌识曲', () => pushFull(context, const ScanPage(match: true))),
            ('chart', '排行榜', () => app.update(() => app.homeTab = '榜单')),
          ]));
          break;
        case 'tabs':
          mods.add(const _HomeTabs());
          break;
        case 'platrec':
          mods.add(const _PlatRec());
      }
    }
    return TabPage(
      title: '发现',
      controller: tabScroll[0],
      onRefresh: app.reload,
      actions: [
        IBtn('scan', onTap: () => pushFull(context, const ScanPage())),
        IBtn('bell', dot: app.unread > 0, onTap: () => push(context, const AnnouncementsPage())),
        const SizedBox(width: 4),
        Avatar('栗', onTap: () => app.update(() => app.tab = 4)),
      ],
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(Tk.pad, 2, Tk.pad, 12), child: SourceBar()),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          child: app.loading
              ? const SkeletonPage(key: ValueKey('sk'))
              : Column(key: ValueKey('c${app.plat}$logged'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!logged) ...[const Rise(0, _LoginStrip()), const SizedBox(height: 16), const Rise(1, BannerCarousel())],
                  for (var i = 0; i < mods.length; i++) Rise(i + 2, mods[i]),
                ]),
        ),
      ],
    );
  }
}

// ============ 未登录：一行登录卡（背景漂移光晕） ============
class _LoginStrip extends StatefulWidget {
  const _LoginStrip();
  @override
  State<_LoginStrip> createState() => _LoginStripState();
}

class _LoginStripState extends State<_LoginStrip> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.platform;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 66,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(p.c1).withValues(alpha: .28), Color(p.c2).withValues(alpha: .18)]), border: Border.all(color: Color(p.c1).withValues(alpha: .3)), borderRadius: BorderRadius.circular(20)),
          child: Stack(children: [
            AnimatedBuilder(
              animation: c,
              builder: (_, __) => Positioned(
                left: 40 + math.sin(c.value * math.pi * 2) * 90,
                top: -40,
                child: Container(width: 160, height: 140, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(p.c1).withValues(alpha: .45), Colors.transparent]))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                PlatBadge(p, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('登录${p.name}', style: ts(15, w: FontWeight.w700, c: context.pal.t1)),
                    const SizedBox(height: 2),
                    Text('每日推荐 · 心动 / 雷达 · 你的歌单 · 收藏同步', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, c: context.pal.t2)),
                  ]),
                ),
                Btn('登录', icon: 'scan', small: true, bg: Color(p.c1), fg: Colors.white, onTap: () => openPlatLogin(context, p.id)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============ Banner（86% 宽，4.5s 轮播，触摸暂停） ============
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});
  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final pc = PageController(viewportFraction: .88, initialPage: 1000);
  int i = 0;
  Timer? t;
  bool touching = false;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (!touching && pc.hasClients) pc.nextPage(duration: const Duration(milliseconds: 600), curve: Tk.out);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(children: [
      SizedBox(
        height: 168,
        child: Listener(
          onPointerDown: (_) => touching = true,
          onPointerUp: (_) => touching = false,
          child: PageView.builder(
            controller: pc,
            onPageChanged: (v) => setState(() => i = v % banners.length),
            itemBuilder: (_, k) {
              final b = banners[k % banners.length];
              return AnimatedBuilder(
                animation: pc,
                builder: (_, ch) {
                  final page = pc.position.haveDimensions ? (pc.page ?? k.toDouble()) : 1000.0;
                  final d = (page - k).abs().clamp(0.0, 1.0);
                  return Transform.scale(scale: 1 - d * .06, child: ch);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Press(
                    scale: .98,
                    onTap: () => push(context, PlaylistPage(id: k % banners.length)),
                    child: Cover(
                      hue: b.hue,
                      variant: k % banners.length,
                      width: double.infinity,
                      height: 168,
                      radius: 22,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xA6000000)], stops: [.35, 1])),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(8)), child: Text(b.kicker, style: ts(11, w: FontWeight.w700, c: Colors.white))),
                          const SizedBox(height: 6),
                          Text(b.title, style: ts(22, w: FontWeight.w800, c: Colors.white)),
                          Text(b.desc, style: ts(12.5, c: const Color(0xCCFFFFFF))),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var k = 0; k < banners.length; k++)
          AnimatedContainer(duration: Tk.base, margin: const EdgeInsets.symmetric(horizontal: 3), width: k == i ? 16 : 6, height: 6, decoration: BoxDecoration(color: k == i ? pal.acc : pal.t4, borderRadius: BorderRadius.circular(3))),
      ]),
    ]);
  }
}

// ============ 已登录：平台账号条 + 为你定制 ============
class _PlatAccount extends StatelessWidget {
  const _PlatAccount();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform, f = platFeat[p.id]!;
    // 退出登录时，正在淡出的旧内容还会再构建一次，这里不能假设一定已登录
    final nick = app.platLogin[p.id];
    if (nick == null || nick.isEmpty) return const SizedBox.shrink();
    return CardBox(
      onTap: () => push(context, const PlatAccountsPage()),
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(colors: [Color(p.c1).withValues(alpha: .22), pal.s1], stops: const [0, .7]),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(p.c1), Color(p.c2)])), child: Text(nick[0], style: ts(20, w: FontWeight.w700, c: Colors.white))),
          Positioned(right: -3, bottom: -3, child: PlatBadge(p, size: 18)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nick, style: ts(16, w: FontWeight.w700, c: pal.t1)),
            const SizedBox(height: 4),
            Row(children: [Badge2('Lv.${f.lv}'), const SizedBox(width: 6), Badge2(f.vip, acc: true)]),
          ]),
        ),
        _num(context, f.like.toDouble(), '喜欢'),
        const SizedBox(width: 16),
        _num(context, (f.mine + f.fav).toDouble(), '歌单'),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _num(BuildContext c, double v, String l) => Column(children: [
        CountUp(v, style: ts(18, w: FontWeight.w800, c: c.pal.t1, num: true)),
        Text(l, style: ts(11, c: c.pal.t3)),
      ]);
}

class _Custom extends StatelessWidget {
  const _Custom();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.platform, f = platFeat[p.id]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Sec('为你定制', trailing: Row(children: [PlatBadge(p, size: 16), const SizedBox(width: 5), Text(p.name, style: ts(12.5, c: context.pal.t3)), const SizedBox(width: 6)])),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
        child: Row(children: [
          for (var i = 0; i < f.hero.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: _HeroCard(f.hero[i]))],
        ]),
      ),
      if (f.extra != null) ...[
        Sec(f.extra!, more: '播放', onMore: () => app.playAll('all', name: f.extra)),
        HScroll(height: 64, gap: 12, children: [
          for (final id in const [19, 8, 13, 22, 10, 3])
            Press(
              onTap: () => app.play(id, list: 'all'),
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: context.pal.s1, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.pal.line)),
                child: Row(children: [
                  Cover.song(songs[id], size: 56, radius: 12),
                  const SizedBox(width: 10),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[id].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w600, c: context.pal.t1)), Text(songs[id].artist, style: ts(12, c: context.pal.t3))])),
                ]),
              ),
            ),
        ]),
      ],
    ]);
  }
}

class _HeroCard extends StatefulWidget {
  final (String, String, String) h;
  const _HeroCard(this.h);
  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final (k, t, d) = widget.h;
    final daily = k == 'daily';
    final pal = context.pal;
    Widget vis;
    if (daily) {
      vis = Stack(children: [
        Positioned(left: 14, top: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('02', style: ts(32, w: FontWeight.w800, c: Colors.white, num: true, h: 1)), Text('NOV', style: ts(10.5, w: FontWeight.w700, c: const Color(0xCCFFFFFF), ls: 1.5))])),
        for (var i = 2; i >= 0; i--)
          Positioned(
            right: 10.0 + i * 13,
            top: 14.0 + i * 4,
            child: Transform.rotate(angle: (1 - i) * .18, child: Cover.song(songs[[4, 11, 17][i]], size: 40, radius: 8, shadow: true)),
          ),
      ]);
    } else if (k == 'heart') {
      vis = AnimatedBuilder(
        animation: c,
        builder: (_, __) => CustomPaint(painter: _EkgPainter(c.value, pal.acc), child: Align(alignment: const Alignment(.7, -.5), child: Transform.scale(scale: 1 + app.beat(c.value * 2.2) * .18, child: Icon(Icons.favorite_rounded, color: pal.acc, size: 30)))),
      );
    } else {
      vis = AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _RadarPainter(c.value, pal.acc)));
    }
    return Press(
      scale: .97,
      onTap: () => daily ? push(context, const PlaylistPage(id: 1)) : app.playAll('hot', shuffle: true, name: t),
      child: Container(
        height: 168,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.line), color: daily ? null : pal.s1),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (daily) const Positioned.fill(child: Cover(hue: 300, variant: 2, size: 0, radius: 20)),
          if (daily) Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0x99000000)])))),
          Positioned.fill(child: vis),
          Positioned(
            left: 14,
            right: 50,
            bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: ts(16, w: FontWeight.w700, c: daily ? Colors.white : pal.t1)),
              const SizedBox(height: 2),
              Text(d, maxLines: 2, style: ts(11, c: daily ? const Color(0xCCFFFFFF) : pal.t3, h: 1.35)),
            ]),
          ),
          Positioned(
            right: 10,
            bottom: 12,
            child: Press(
              onTap: () => app.playAll(daily ? 'daily' : 'hot', name: t),
              scale: .88,
              child: Container(width: 36, height: 36, decoration: BoxDecoration(color: daily ? Colors.white : pal.acc, shape: BoxShape.circle), child: Icon(Icons.play_arrow_rounded, color: daily ? Colors.black : pal.ink)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EkgPainter extends CustomPainter {
  final double t;
  final Color c;
  _EkgPainter(this.t, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height * .38;
    final pts = [const Offset(0, 24), const Offset(38, 24), const Offset(44, 14), const Offset(51, 36), const Offset(59, 6), const Offset(66, 36), const Offset(72, 24), const Offset(160, 24)];
    final sx = s.width / 160;
    final path = Path()..moveTo(0, y - 24 + 24);
    for (final p in pts) {
      path.lineTo(p.dx * sx, y - 24 + p.dy);
    }
    final m = path.computeMetrics().first;
    final len = m.length;
    final head = len * t;
    final seg = m.extractPath(math.max(0, head - len * .45), head);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = c.withValues(alpha: .18));
    canvas.drawPath(seg, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = c
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2));
  }

  @override
  bool shouldRepaint(_EkgPainter o) => o.t != t;
}

class _RadarPainter extends CustomPainter {
  final double t;
  final Color c;
  _RadarPainter(this.t, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final o = Offset(s.width * .62, s.height * .36);
    final r = s.height * .3;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = c.withValues(alpha: .22);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(o, r * i / 3, ring);
    }
    final a = t * math.pi * 2;
    canvas.drawArc(Rect.fromCircle(center: o, radius: r), a - .9, .9, true, Paint()..shader = SweepGradient(startAngle: a - .9, endAngle: a, colors: [c.withValues(alpha: 0), c.withValues(alpha: .45)]).createShader(Rect.fromCircle(center: o, radius: r)));
    const dots = [(.3, .4), (.64, .22), (.52, .7), (.78, .58)];
    for (var k = 0; k < dots.length; k++) {
      final ph = (t * 1.5 + k * .25) % 1;
      final d = Offset(o.dx + (dots[k].$1 - .5) * r * 1.6, o.dy + (dots[k].$2 - .5) * r * 1.6);
      canvas.drawCircle(d, 3 * (1 - ph) + 1, Paint()..color = c.withValues(alpha: 1 - ph));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter o) => o.t != t;
}

// ============ 我的歌单（分段胶囊滑动） ============
class _MyPlaylists extends StatelessWidget {
  const _MyPlaylists();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final f = platFeat[app.plat]!;
    final seg = app.myPlSeg;
    final pls = seg == 1 ? playlists.sublist(2, 6) : app.myPlaylists;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Sec('我的歌单', more: '全部', onMore: () => app.update(() => app.tab = 3)),
      Seg([for (var i = 0; i < 2; i++) '${f.mySeg[i]} ${i == 1 ? f.fav : (f.mySeg[i] == '我喜欢' ? f.like : f.mine)}'], '${f.mySeg[seg]} ${seg == 1 ? f.fav : (f.mySeg[seg] == '我喜欢' ? f.like : f.mine)}', (v) => app.update(() => app.myPlSeg = v.startsWith(f.mySeg[1]) ? 1 : 0)),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
        child: GridView.count(
          key: ValueKey(seg),
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: [
            for (var i = 0; i < math.min(4, pls.length); i++)
              Rise(
                i,
                Press(
                  onTap: () => push(context, PlaylistPage(id: pls[i].id)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.line)),
                    child: Row(children: [
                      Cover.pl(pls[i], size: 50, radius: 10, child: i == 0 && seg == 0 ? const Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: 20)) : null),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i == 0 && seg == 0 ? '我喜欢的音乐' : pls[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
                          Text('${i == 0 && seg == 0 ? f.like : pls[i].count} 首', style: ts(11.5, c: pal.t3)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

// ============ 精选 / 榜单 / 歌单 ============
class _HomeTabs extends StatelessWidget {
  const _HomeTabs();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform;
    final logged = app.isIn(p.id);
    Widget body;
    if (app.homeTab == '精选') {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Sec(logged ? '推荐歌单' : '${p.short} · 热门歌单', more: '更多', onMore: () => app.update(() => app.homeTab = '歌单')),
        HScroll(height: 196, children: [for (final x in playlists.take(6)) PlCard(x, onTap: () => push(context, PlaylistPage(id: x.id)))]),
        Sec('热门榜单', more: '全部', onMore: () => app.update(() => app.homeTab = '榜单')),
        CardBox(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final (i, id) in app.listOf('hot').take(5).indexed) SongRow(songs[id], num: i, list: 'hot', listName: '热门榜单', swipe: false, tail: HeartBtn(id)),
          ]),
        ),
      ]);
    } else if (app.homeTab == '榜单') {
      body = Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          for (final (n, h, ids) in const [('飙升榜', 300.0, [11, 17, 5]), ('新歌榜', 40.0, [8, 13, 19]), ('热歌榜', 200.0, [0, 2, 4]), ('Hi-Res 榜', 160.0, [7, 21, 12])])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CardBox(
                onTap: () => push(context, PlaylistPage(id: h.toInt() % 8, chartName: n)),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Cover(hue: h, variant: 2, size: 88, radius: 14, child: Align(alignment: Alignment.bottomLeft, child: Padding(padding: const EdgeInsets.all(8), child: Text(n, style: ts(15, w: FontWeight.w700, c: Colors.white))))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: '${i + 1}  ', style: ts(13, w: FontWeight.w700, c: i == 0 ? pal.accText : pal.t1)),
                            TextSpan(text: '${songs[ids[i]].title} - ${songs[ids[i]].artist}'),
                          ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t2)),
                        ),
                      Text('${p.name} · 每日 10:00 更新', style: ts(11, c: pal.t3)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0),
        child: LayoutBuilder(builder: (c, cs) {
          final w = (cs.maxWidth - 14) / 2;
          return Wrap(spacing: 14, runSpacing: 16, children: [for (final x in playlists) PlCard(x, w: w, onTap: () => push(context, PlaylistPage(id: x.id)))]);
        }),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 22),
      Seg(const ['精选', '榜单', '歌单'], app.homeTab, (v) => app.update(() => app.homeTab = v)),
      AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: KeyedSubtree(key: ValueKey(app.homeTab), child: body)),
    ]);
  }
}

// ============ 平台推荐区 ============
class _PlatRec extends StatefulWidget {
  const _PlatRec();
  @override
  State<_PlatRec> createState() => _PlatRecState();
}

class _PlatRecState extends State<_PlatRec> {
  String region = '华语';
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform;
    final secs = platRec[p.id]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 30, Tk.pad, 0),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: pal.line)),
          const SizedBox(width: 10),
          PlatBadge(p, size: 18),
          const SizedBox(width: 6),
          Text('来自${p.name}', style: ts(12.5, w: FontWeight.w600, c: pal.t2)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: pal.line)),
        ]),
      ),
      for (final k in secs) _sec(context, k),
    ]);
  }

  Widget _sec(BuildContext context, String k) {
    final app = context.app;
    final pal = context.pal;
    switch (k) {
      case 'albums':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('新碟上架', more: '更多'),
          HScroll(height: 186, gap: 26, children: [for (final (i, id) in const [2, 7, 12, 16, 21, 1].indexed) AlbumCard(songs[id], onTap: () => push(context, PlaylistPage(id: i)))]),
        ]);
      case 'newsongs':
        final off = region == '欧美' ? 16 : region == '日韩' ? 8 : 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('新歌速递', more: '播放', onMore: () => app.playAll('all', name: '新歌速递')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Row(children: [for (final r in const ['华语', '欧美', '日韩']) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(r, on: r == region, h: 30, onTap: () => setState(() => region = r)))]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 3 * 60,
            child: PageView.builder(
              key: ValueKey(region),
              controller: PageController(viewportFraction: .88),
              padEnds: false,
              itemCount: 3,
              itemBuilder: (_, c) => Padding(
                padding: const EdgeInsets.only(left: Tk.pad - 4),
                child: Column(children: [
                  for (var r = 0; r < 3; r++)
                    Builder(builder: (_) {
                      final s = songs[(c * 3 + r + off) % songs.length];
                      return Press(
                        onTap: () => app.play(s.id, list: 'all'),
                        child: SizedBox(
                          height: 60,
                          child: Row(children: [
                            Cover.song(s, size: 48),
                            const SizedBox(width: 10),
                            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(14, w: FontWeight.w600, c: pal.t1)), Text(s.artist, style: ts(12, c: pal.t3))])),
                            Icon(Icons.play_circle_outline_rounded, color: pal.t3),
                            const SizedBox(width: 10),
                          ]),
                        ),
                      );
                    }),
                ]),
              ),
            ),
          ),
        ]);
      case 'official':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('官方榜', more: '更多'),
          HScroll(height: 232, gap: 12, children: [
            for (final (n, h, ids) in const [('飙升榜', 340.0, [11, 17, 5]), ('新歌榜', 30.0, [8, 13, 19]), ('热歌榜', 210.0, [0, 2, 4]), ('原创榜', 150.0, [7, 21, 12])])
              Press(
                onTap: () => push(context, PlaylistPage(id: h.toInt() % 8, chartName: n)),
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hsl(h, .5, pal.dark ? .22 : .9), pal.s1])),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Text(n, style: ts(17, w: FontWeight.w800, c: pal.t1)), const Spacer(), Text('每日更新', style: ts(11, c: pal.t3))]),
                    const SizedBox(height: 8),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          Cover.song(songs[ids[i]], size: 40, radius: 8),
                          const SizedBox(width: 8),
                          SizedBox(width: 16, child: Text('${i + 1}', style: ts(14, w: FontWeight.w800, c: i == 0 ? pal.accText : pal.t2, num: true))),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[ids[i]].title, maxLines: 1, style: ts(13, w: FontWeight.w600, c: pal.t1)), Text(songs[ids[i]].artist, style: ts(11, c: pal.t3))])),
                          Text(i == 0 ? '▲3' : '—', style: ts(11, w: FontWeight.w700, c: i == 0 ? pal.danger : pal.t3)),
                        ]),
                      ),
                  ]),
                ),
              ),
          ]),
        ]);
      case 'plcats':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('歌单分类', more: '全部'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, c) in const ['华语', '流行', '摇滚', '民谣', '电子', '说唱', '轻音乐', '爵士', '古典', 'ACG', '影视原声', '运动', '学习', '深夜', '治愈'].indexed)
                Rise(i, LChip(c, onTap: () => push(context, PlaylistPage(id: i % 8, chartName: '$c 歌单')))),
            ]),
          ),
        ]);
      case 'genres':
        final logged = app.isIn(app.plat);
        final g = logged
            ? const [('城市流行', 34, 300.0), ('电子', 22, 200.0), ('后摇', 16, 225.0), ('华语独立', 14, 30.0), ('Lo-fi', 9, 280.0), ('R&B', 5, 340.0)]
            : const [('流行', 0, 300.0), ('摇滚', 0, 0.0), ('电子', 0, 200.0), ('民谣', 0, 30.0), ('说唱', 0, 340.0), ('古典', 0, 225.0)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec(logged ? '曲风偏好' : '曲风分类', more: logged ? '调整' : '全部'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final (i, (n, p, h)) in g.indexed)
                  Cover(
                    hue: h,
                    variant: i,
                    size: 0,
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(n, style: ts(14, w: FontWeight.w700, c: Colors.white)),
                        if (logged) ...[
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: p / 38, minHeight: 3, color: Colors.white, backgroundColor: const Color(0x40FFFFFF))),
                          const SizedBox(height: 4),
                          Text('你的偏好 $p%', style: ts(10, c: const Color(0xCCFFFFFF))),
                        ],
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ]);
      case 'mvrank':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('MV 排行', more: '更多'),
          for (var i = 0; i < 3; i++)
            Builder(builder: (_) {
              final s = songs[(i * 5 + 3) % songs.length];
              return Press(
                onTap: () => toast('播放 MV：${s.title}', 'video'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Tk.pad, 6, Tk.pad, 6),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: ts(16, w: FontWeight.w800, c: i == 0 ? pal.accText : pal.t3, num: true))),
                    Cover(hue: s.hue + 20, variant: s.variant, width: 128, height: 72, radius: 12, child: Align(alignment: Alignment.bottomRight, child: Container(margin: const EdgeInsets.all(5), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(5)), child: Text(fmtTime(180.0 + i * 31), style: ts(10, c: Colors.white, num: true))))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(14, w: FontWeight.w600, c: pal.t1)), const SizedBox(height: 3), Text('${s.artist} · ${98 - i * 17}万次播放', style: ts(12, c: pal.t3))])),
                  ]),
                ),
              );
            }),
        ]);
      case 'videos':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('推荐视频', more: '更多'),
          HScroll(height: 186, gap: 12, children: [for (var i = 1; i <= 4; i++) MvCard(i)]),
        ]);
      case 'nowlisten':
        final hr = DateTime.now().hour;
        final slot = hr < 6 ? ('深夜', '安静的夜') : hr < 11 ? ('早晨', '清醒一下') : hr < 14 ? ('午间', '午休小憩') : hr < 18 ? ('下午', '适合专注') : hr < 22 ? ('傍晚', '下班路上') : ('夜晚', '睡前放松');
        final now = DateTime.now();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('适合现在听', more: '换一批'),
          CardBox(
            padding: EdgeInsets.zero,
            onTap: () => app.playAll('daily', name: '适合现在听'),
            child: Cover(
              hue: hr * 15.0,
              variant: 2,
              width: double.infinity,
              height: 150,
              radius: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xB3000000), Colors.transparent])),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} · ${slot.$1}', style: ts(12, w: FontWeight.w600, c: const Color(0xCCFFFFFF), num: true)),
                      const SizedBox(height: 4),
                      Text(slot.$2, style: ts(24, w: FontWeight.w800, c: Colors.white)),
                      Text('根据时间和你最近常听的歌', style: ts(12, c: const Color(0xB3FFFFFF))),
                    ]),
                  ),
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(children: [for (var i = 0; i < 4; i++) Positioned(left: (i % 2) * 40.0 + (i ~/ 2) * 8, top: (i ~/ 2) * 40.0, child: Transform.rotate(angle: (i - 1.5) * .1, child: Cover.song(songs[[3, 9, 15, 22][i]], size: 48, radius: 9, shadow: true)))]),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [for (final n in const ['通勤', '学习', '运动', '开车', '睡前', '做饭']) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(n, onTap: () => toast('场景：$n', 'sparkle')))])),
        ]);
      case 'mood':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Sec('换个心情听'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                for (final (i, (n, h, g)) in const [('开心', 40.0, '☼'), ('放松', 170.0, '～'), ('伤感', 220.0, '﹏'), ('热血', 0.0, '⚡'), ('治愈', 140.0, '♡'), ('思念', 280.0, '☾')].indexed)
                  Rise(
                    i,
                    Press(
                      onTap: () => app.playAll('hot', shuffle: true, name: '心情 · $n'),
                      child: Container(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hsl(h, .6, pal.dark ? .32 : .78), hsl(h + 30, .5, pal.dark ? .18 : .9)])),
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(g, style: ts(18, c: pal.t1)), Text(n, style: ts(14, w: FontWeight.w700, c: pal.t1))]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]);
      case 'fresh':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('新鲜上架', more: '播放', onMore: () => app.playAll('all', name: '新鲜上架')),
          for (final (i, id) in const [19, 8, 13, 22].indexed)
            SongRow(songs[id], list: 'all', swipe: false, tail: Padding(padding: const EdgeInsets.only(right: 14), child: Badge2(const ['今天', '今天', '昨天', '3 天前'][i], acc: i < 2))),
        ]);
    }
    return const SizedBox();
  }
}

/// 专辑卡：封面后面露出唱片，按下时唱片滑出并旋转。
class AlbumCard extends StatefulWidget {
  final Song s;
  final VoidCallback? onTap;
  final double size;
  const AlbumCard(this.s, {super.key, this.onTap, this.size = 130});
  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final sz = widget.size;
    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapUp: (_) => setState(() => down = false),
      onTapCancel: () => setState(() => down = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: sz + 18,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: sz,
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Tk.softSpring,
                left: down ? 30 : 16,
                top: 4,
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 900),
                  turns: down ? .5 : 0,
                  child: Container(
                    width: sz - 8,
                    height: sz - 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0D0E12), border: Border.all(color: const Color(0xFF26282F), width: 6)),
                    child: Center(child: Cover.song(widget.s, size: (sz - 8) * .38, radius: sz)),
                  ),
                ),
              ),
              Cover.song(widget.s, size: sz, radius: 12, shadow: true),
            ]),
          ),
          const SizedBox(height: 8),
          Text(widget.s.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
          Text(widget.s.artist, maxLines: 1, style: ts(12, c: pal.t3)),
        ]),
      ),
    );
  }
}

class MvCard extends StatelessWidget {
  final int i;
  final double w;
  const MvCard(this.i, {super.key, this.w = 236});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = songs[(i * 4 + 1) % songs.length];
    return Press(
      onTap: () => toast('播放视频：${s.title}', 'video'),
      child: SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover(
            hue: s.hue + 30,
            variant: i,
            width: w,
            height: w * 9 / 16,
            radius: 14,
            child: Stack(children: [
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Color(0xE6FFFFFF), size: 36)),
              Positioned(right: 6, bottom: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(6)), child: Text(fmtTime(150.0 + i * 37), style: ts(10.5, c: Colors.white, num: true)))),
            ]),
          ),
          const SizedBox(height: 6),
          Text('${s.title}（官方 MV）', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
          Text(s.artist, style: ts(12, c: pal.t3)),
        ]),
      ),
    );
  }
}

// 便于其它页面引用的平台推荐类型
Widget platBadgeOf(Platform p, [double s = 22]) => PlatBadge(p, size: s);
IconData icOf(String n) => ic(n);

// ============ 联网模式：各平台公开内容（未登录可用） ============
// 对齐桌面端 publicPlatform：此刻热门（第一个榜单的前 10 首）· 推荐歌单 12 个 · 排行榜 9 个；
// 下面是真实的本机数据（我的歌单、听歌统计）。
class _OnlineDiscover extends StatefulWidget {
  const _OnlineDiscover();
  @override
  State<_OnlineDiscover> createState() => _OnlineDiscoverState();
}

typedef _Feed = ({DiscoverFeed feed, List<int> hot});

class _OnlineDiscoverState extends State<_OnlineDiscover> {
  String? plat;
  late Future<_Feed> f;

  Future<_Feed> _fetch(AppState app) => app.content.discover(app.plat).then((d) => (feed: d, hot: [for (final t in d.hot) registerTrack(app, t)]));

  Future<void> _refresh() async {
    final app = context.appRead;
    app.content.invalidate(app.plat);
    final nf = _fetch(app);
    setState(() => f = nf);
    try {
      await nf;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    if (plat != app.plat) {
      plat = app.plat;
      f = _fetch(app);
    }
    final code = PlatformHub.codeOf(app.plat);
    final pls = app.myPlaylists;
    final week = app.cloud.stats.summary(7);
    return TabPage(
      title: '发现',
      controller: tabScroll[0],
      onRefresh: _refresh,
      actions: [
        IBtn('scan', onTap: () => pushFull(context, const ScanPage())),
        IBtn('bell', dot: app.unread > 0, onTap: () => push(context, const AnnouncementsPage())),
        const SizedBox(width: 4),
        Avatar(avatarText(app), onTap: () => app.update(() => app.tab = 4)),
      ],
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(Tk.pad, 2, Tk.pad, 4), child: SourceBar()),
        Rise(
          0,
          QuickGrid([
            ('grid', '歌单广场', () => push(context, PlaylistSquarePage(platform: code))),
            ('chart', '排行榜', () => push(context, LeaderboardsPage(platform: code))),
            ('library', '音乐库', () => app.update(() => app.tab = 3)),
            ('clock', '听歌统计', () => push(context, const StatsPage())),
          ]),
        ),
        FutureBuilder<_Feed>(
          key: ValueKey('feed$plat'),
          future: f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.only(top: 22), child: ListSkeleton(rows: 5));
            if (s.hasError) {
              return EmptyState('wifi', '${app.platform.name}的内容没有加载出来', desc: '${platformError(s.error!)}\n可以下拉刷新，或在上方换一个平台。', action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _refresh));
            }
            final d = s.data!.feed, hot = s.data!.hot;
            final board = d.hotBoard;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (hot.isNotEmpty) ...[
                Sec('此刻热门', more: board == null ? null : '完整榜单', onMore: board == null ? null : () => openCatalog(context, board)),
                if (board != null) Hint('${board.title} · ${app.platform.name}', padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 6)),
                CardBox(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    for (final (i, id) in hot.indexed) SongRow(songs[id], num: i, list: 'all', listName: board?.title ?? '此刻热门', swipe: false, tail: HeartBtn(id)),
                  ]),
                ),
              ],
              if (d.playlists.isNotEmpty) ...[
                Sec('推荐歌单', more: '歌单广场', onMore: () => push(context, PlaylistSquarePage(platform: code))),
                HScroll(height: 196, children: [for (final x in d.playlists) PlCard(cardOf(x), onTap: () => openCatalog(context, x))]),
              ],
              if (d.boards.isNotEmpty) ...[
                Sec('排行榜', more: '全部', onMore: () => push(context, LeaderboardsPage(platform: code))),
                HScroll(height: 160, gap: 12, children: [for (final b in d.boards) BoardCard(b)]),
              ],
              if (d.errors.isNotEmpty) Hint('部分内容没有加载出来：${d.errors.join('；')}', padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0)),
            ]);
          },
        ),
        Sec('我的歌单', more: pls.isEmpty ? null : '全部', onMore: () => app.update(() {
              app.tab = 3;
              app.libSeg = '歌单';
            })),
        if (pls.isEmpty)
          const Hint('还没有歌单。可以在「音乐库 → 歌单」新建、收藏平台歌单，或开启云同步拉取桌面端的歌单。', padding: EdgeInsets.symmetric(horizontal: Tk.pad))
        else
          HScroll(height: 196, children: [for (final p in pls.take(10)) PlCard(p, sub: '${p.kind == 'collected' ? p.count : p.ids.length} 首', onTap: () => push(context, PlaylistPage(id: p.id)))]),
        Sec('本周', more: '统计', onMore: () => push(context, const StatsPage())),
        CardBox(
          onTap: () => push(context, const StatsPage()),
          child: Row(children: [
            Expanded(child: _kv(pal, '收藏', '${app.liked.length}', '首')),
            Expanded(child: _kv(pal, '聆听', (week.ms / 3600000).toStringAsFixed(1), '小时')),
            Expanded(child: _kv(pal, '播放', '${week.plays}', '次')),
          ]),
        ),
      ],
    );
  }

  Widget _kv(Pal pal, String k, String v, String u) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: ts(12, c: pal.t3)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(v, style: ts(22, w: FontWeight.w800, c: pal.t1, num: true)), const SizedBox(width: 2), Text(u, style: ts(12, c: pal.t3))]),
      ]);
}
