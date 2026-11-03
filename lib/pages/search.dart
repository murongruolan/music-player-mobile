// 搜索：输入框在底部（拇指区）+ 旋转唱片圆钮；默认态 / 联想 / 结果（类型 Tab + 平台筛选 + 相关搜索）。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../player/player.dart';
import '../shell/nav.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'common.dart';
import 'detail.dart';
import 'discover.dart';
import 'scan.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final tc = TextEditingController();
  final fn = FocusNode();
  bool done = false;
  String type = '综合', rplat = 'all';

  @override
  void initState() {
    super.initState();
    fn.addListener(() {
      final app = context.appRead;
      if (app.searchFocus != fn.hasFocus) app.update(() => app.searchFocus = fn.hasFocus);
    });
    tc.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    tc.dispose();
    fn.dispose();
    super.dispose();
  }

  void go(String q) {
    final app = context.appRead;
    q = q.trim();
    if (q.isEmpty) return;
    tc.text = q;
    app.history
      ..remove(q)
      ..insert(0, q);
    if (app.history.length > 20) app.history.removeRange(20, app.history.length);
    if (app.online) app.library.saveHistory();
    fn.unfocus();
    setState(() {
      done = true;
      type = '综合';
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = tc.text.trim();
    final Widget body;
    if (q.isNotEmpty && done) {
      body = _Results(q: q, type: type, rplat: rplat, onType: (v) => setState(() => type = v), onPlat: (v) => setState(() => rplat = v), onQuery: go, onClear: () {
        tc.clear();
        setState(() => done = false);
      });
    } else if (q.isNotEmpty) {
      body = _suggest(context, q);
    } else {
      body = _idle(context);
    }
    return Stack(children: [
      Positioned.fill(child: body),
      _dock(context),
    ]);
  }

  // ---------- 默认态 ----------
  Widget _idle(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return TabPage(title: '搜索', controller: tabScroll[1], bottom: 260, children: [
      if (app.history.isNotEmpty) ...[
        Sec('搜索历史', size: 16, trailing: IBtn('trash', size: 36, iconSize: 18, color: pal.t3, onTap: () => showLDialog(context, icon: 'trash', title: '清空搜索历史？', actions: [
                  ('取消', BtnKind.sec, null),
                  ('清空', BtnKind.danger, () {
                    app.update(app.history.clear);
                    if (app.online) app.library.saveHistory();
                  }),
                ]))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Tk.pad), child: Wrap(spacing: 8, runSpacing: 8, children: [for (final h in app.history) LChip(h, onTap: () => go(h))])),
      ],
      if (app.online)
        const EmptyState('search', '目前只能搜索本机音乐库', desc: '平台搜索、热搜榜需要接入各音乐平台的接口，正在开发。\n输入歌名、歌手或专辑，可以找到你收藏和歌单里的歌。'),
      if (!app.online) const Sec('热搜榜', size: 16, more: '每小时更新'),
      if (!app.online) CardBox(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final (i, h) in hotSearch.indexed)
            Press(
              onTap: () => go(h),
              child: SizedBox(
                height: 48,
                child: Row(children: [
                  const SizedBox(width: 16),
                  SizedBox(width: 26, child: Text('${i + 1}', style: ts(15, w: FontWeight.w700, c: i < 3 ? pal.accText : pal.t3, num: true))),
                  Expanded(child: Text(h, style: ts(14.5, w: FontWeight.w500, c: pal.t1))),
                  if (i == 0) const Badge2('热', acc: true),
                  if (i == 3 || i == 7) const Badge2('新'),
                  const SizedBox(width: 16),
                ]),
              ),
            ),
        ]),
      ),
      if (!app.online) const Sec('按风格探索', size: 16),
      if (!app.online) Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (final (i, t) in styleTiles.indexed)
              Press(onTap: () => go(t[0] as String), child: Cover(hue: t[1] as double, variant: i, size: 0, radius: 16, child: Align(alignment: Alignment.bottomLeft, child: Padding(padding: const EdgeInsets.all(12), child: Text(t[0] as String, style: ts(15, w: FontWeight.w700, c: Colors.white)))))),
          ],
        ),
      ),
    ]);
  }

  // ---------- 联想 ----------
  Widget _suggest(BuildContext context, String q) {
    final pal = context.pal;
    final ql = q.toLowerCase();
    final out = <(String, String, String)>[];
    for (final s in songs) {
      if (s.title.toLowerCase().contains(ql)) out.add(('music', s.title, '歌曲 · ${s.artist}'));
    }
    for (final a in songs.map((s) => s.artist).toSet()) {
      if (a.toLowerCase().contains(ql)) out.add(('user', a, '歌手'));
    }
    for (final a in songs.map((s) => s.album).toSet()) {
      if (a.toLowerCase().contains(ql)) out.add(('album', a, '专辑'));
    }
    if (!context.appRead.online) {
      for (final x in const ['现场版', '伴奏', '翻唱', '歌词', 'DJ 版']) {
        out.add(('search', '$q $x', ''));
      }
    }
    final hl = highlighter(q, pal.accText);
    final top = MediaQuery.of(context).padding.top;
    return ListView(padding: EdgeInsets.only(top: top + 10, bottom: 420), children: [
      Padding(padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 10), child: Text('搜索', style: ts(30, w: FontWeight.w800, c: pal.t1))),
      Press(
        onTap: () => go(q),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad, vertical: 12),
          child: Row(children: [
            Icon(ic('search'), color: pal.accText, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('搜索「$q」', style: ts(15, w: FontWeight.w700, c: pal.accText))),
            Text(rplat == 'all' ? '全部平台' : platformBy(rplat).name, style: ts(12, c: pal.t3)),
          ]),
        ),
      ),
      for (final (k, (i, t, d)) in out.take(9).indexed)
        Rise(
          k,
          Press(
            onTap: () => go(t),
            child: Padding(
              padding: const EdgeInsets.only(left: Tk.pad, right: 6),
              child: SizedBox(
                height: 50,
                child: Row(children: [
                  Icon(ic(i), color: pal.t3, size: 19),
                  const SizedBox(width: 12),
                  Expanded(child: Text.rich(hl(t, ts(15, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (d.isNotEmpty) Text(d, style: ts(12, c: pal.t3)),
                  IBtn('arrowUL', size: 40, iconSize: 18, color: pal.t3, onTap: () {
                    tc.text = '$t ';
                    tc.selection = TextSelection.collapsed(offset: tc.text.length);
                    fn.requestFocus();
                  }),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ---------- 底部输入栏 + 唱片圆钮 ----------
  Widget _dock(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final mq = MediaQuery.of(context);
    final focus = fn.hasFocus;
    final g = NavGeom.of(app.bar);
    final adj = mq.padding.bottom - 34;
    final navH = g.attached ? math.max(56.0, g.height + adj) : g.height;
    final navB = g.attached ? 0.0 : math.max(10.0, g.bottom + adj);
    final bottom = focus ? mq.viewInsets.bottom + 10 : navB + navH + 10 + (app.bar == 'cutout' ? 24 : 0);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 420),
      curve: Tk.softSpring,
      left: 12,
      right: 12,
      bottom: bottom,
      height: 54,
      child: Row(children: [
        Expanded(
          child: Glass(
            radius: 27,
            color: pal.glassStrong,
            shadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
            child: Row(children: [
              const SizedBox(width: 16),
              Icon(ic('search'), color: pal.t2, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: tc,
                  focusNode: fn,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() => done = false),
                  onSubmitted: go,
                  style: ts(15, c: pal.t1),
                  cursorColor: pal.acc,
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '在 ${rplat == 'all' ? '全部平台' : platformBy(rplat).name} 中搜索', hintStyle: ts(15, c: pal.t3)),
                ),
              ),
              if (tc.text.isNotEmpty)
                IBtn('close', size: 40, iconSize: 18, color: pal.t3, onTap: () {
                  tc.clear();
                  setState(() => done = false);
                  fn.requestFocus();
                })
              else
                IBtn('mic', size: 40, iconSize: 20, color: pal.t2, onTap: () => pushFull(context, const ScanPage(match: true))),
              const SizedBox(width: 4),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: Tk.base,
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: focus
              ? Press(key: const ValueKey('c'), onTap: () => fn.unfocus(), child: SizedBox(height: 54, child: Center(child: Text('取消', style: ts(15, w: FontWeight.w600, c: pal.accText)))))
              : app.hasSong
                  ? const _Disc(key: ValueKey('d'))
                  : const SizedBox(key: ValueKey('n'), width: 0),
        ),
      ]),
    );
  }
}

/// 唱片圆钮：封面旋转，外圈主题色进度环；暂停时显示播放图标。
class _Disc extends StatefulWidget {
  const _Disc({super.key});
  @override
  State<_Disc> createState() => _DiscState();
}

class _DiscState extends State<_Disc> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    app.playing ? (c.isAnimating ? null : c.repeat()) : c.stop();
    return Press(
      onTap: () => openPlayer(context),
      scale: .9,
      child: SizedBox(
        width: 54,
        height: 54,
        child: ValueListenableBuilder<double>(
          valueListenable: app.pos,
          builder: (_, p, ch) => CustomPaint(painter: _Ring(app.song.dur > 0 ? p / app.song.dur : 0, pal.acc, pal.s3), child: ch),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Stack(alignment: Alignment.center, children: [
              RotationTransition(turns: c, child: ClipOval(child: Cover.song(app.song, size: 46, radius: 23))),
              Container(width: 22, height: 22, decoration: const BoxDecoration(color: Color(0x8C000000), shape: BoxShape.circle), child: Icon(ic(app.playing ? 'pause' : 'play'), size: 14, color: Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  final double p;
  final Color a, b;
  _Ring(this.p, this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(1.5, 1.5, s.width - 3, s.height - 3);
    canvas.drawOval(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = b);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * p.clamp(0, 1), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = a);
  }

  @override
  bool shouldRepaint(_Ring o) => o.p != p || o.a != a;
}

// ---------- 结果页 ----------
class _Results extends StatelessWidget {
  final String q, type, rplat;
  final ValueChanged<String> onType, onPlat, onQuery;
  final VoidCallback onClear;
  const _Results({required this.q, required this.type, required this.rplat, required this.onType, required this.onPlat, required this.onQuery, required this.onClear});

  /// 联网模式：只在本机音乐库（收藏、歌单里的歌）里找。
  Widget _localResults(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final ql = q.toLowerCase();
    final res = songs.where((s) => '${s.title} ${s.artist} ${s.album}'.toLowerCase().contains(ql)).toList();
    final pls = app.myPlaylists.where((p) => p.title.toLowerCase().contains(ql)).toList();
    final hl = highlighter(q, pal.accText);
    final top = MediaQuery.of(context).padding.top;
    return ListView(padding: EdgeInsets.only(top: top, bottom: 170), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 10, 8, 4),
        child: Row(children: [Expanded(child: Text('「$q」', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(24, w: FontWeight.w800, c: pal.t1))), IBtn('close', onTap: onClear)]),
      ),
      Hint('本机音乐库 · ${res.length} 首歌${pls.isEmpty ? '' : ' · ${pls.length} 个歌单'}（平台搜索接入中）', padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 8)),
      if (pls.isNotEmpty) ...[
        const Sec('歌单', size: 16),
        for (final p in pls) _plRow(context, p, hl),
      ],
      if (res.isNotEmpty) ...[
        const Sec('歌曲', size: 16),
        for (final s in res.take(100)) SongRow(s, list: 'all', listName: '搜索「$q」', hl: hl),
      ],
      if (res.isEmpty && pls.isEmpty) EmptyState('search', '本机音乐库里没有找到「$q」', desc: '平台搜索接入后可以搜索全部平台的曲库。'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.online) return _localResults(context);
    final pal = context.pal;
    final ql = q.toLowerCase();
    var res = songs.where((s) => '${s.title}${s.artist}${s.album}'.toLowerCase().contains(ql)).toList();
    final exact = res.isNotEmpty;
    if (!exact) res = songs.take(8).toList();
    if (rplat != 'all') res = {...res, ...songs.sublist(4, 9)}.take(8).toList();
    final artist = songs.firstWhere((s) => s.artist.toLowerCase().contains(ql), orElse: () => songs.first);
    final counts = [for (var i = 0; i < platforms.length; i++) 12 + ((q.length * 7 + i * 13) % 40)];
    final hl = highlighter(q, pal.accText);
    final top = MediaQuery.of(context).padding.top;
    const types = ['综合', '歌曲', '歌单', '专辑', '艺术家', 'MV'];
    final artists = songs.map((s) => s.artist).toSet().toList();
    final albums = [artist.album, '现场 · 2025', '单曲合集', '远光 (Deluxe)', '夜航', '星图 EP'];

    Widget songRowR(int k) {
      final s = res[k];
      return SongRow(s, list: 'all', listName: '搜索「$q」', hl: hl);
    }

    final body = <Widget>[];
    switch (type) {
      case '综合':
        body.addAll([
          CardBox(
            margin: const EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 0),
            onTap: () => push(context, ArtistPage(id: artist.id)),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Cover(hue: artist.hue, variant: 1, size: 64, radius: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('最佳匹配 · 艺术家', style: ts(11, w: FontWeight.w600, c: pal.t3, ls: .6)),
                  const SizedBox(height: 2),
                  Text.rich(hl(artist.artist, ts(18, w: FontWeight.w700, c: pal.t1))),
                  Text('${songs.where((s) => s.artist == artist.artist).length} 首单曲 · 3 张专辑 · 12 万关注', style: ts(12.5, c: pal.t2)),
                ]),
              ),
              IBtn('play', bg: pal.acc, color: pal.ink, onTap: () => app.playAll('all', name: artist.artist)),
            ]),
          ),
          if (!exact) Hint('没有找到「$q」的精确结果，为你展示相关内容', padding: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 0)),
          Sec('单曲', more: '全部', onMore: () => onType('歌曲')),
          for (var k = 0; k < math.min(4, res.length); k++) songRowR(k),
          Sec('专辑', more: '全部', onMore: () => onType('专辑')),
          HScroll(height: 186, gap: 26, children: [for (final (i, a) in albums.take(4).indexed) _AlbumR(a, artist.hue + i * 30, i, artist.artist, 2026 - i, hl)]),
          Sec('歌单', more: '全部', onMore: () => onType('歌单')),
          for (final p in playlists.take(3)) _plRow(context, p, hl),
          Sec('MV', more: '全部', onMore: () => onType('MV')),
          HScroll(height: 180, gap: 12, children: [for (var i = 0; i < 4; i++) MvCard(i, w: 220)]),
          const Sec('艺术家'),
          HScroll(height: 150, gap: 16, children: [
            for (final (i, a) in artists.take(6).indexed)
              Press(
                onTap: () => push(context, ArtistPage(id: songs.firstWhere((s) => s.artist == a).id)),
                child: SizedBox(width: 96, child: Column(children: [Cover(hue: i * 60.0 + 20, variant: 1, size: 88, radius: 44), const SizedBox(height: 8), Text.rich(hl(a, ts(13, w: FontWeight.w600, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${12 - i} 万关注', style: ts(11, c: pal.t3))])),
              ),
          ]),
        ]);
        break;
      case '歌曲':
        body.addAll([
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 6),
            child: Row(children: [
              Btn('播放全部', icon: 'play', small: true, onTap: () => app.playAll('all', name: '搜索「$q」')),
              const SizedBox(width: 8),
              LChip('综合排序', icon: 'sort', onTap: () => toast('已按综合排序', 'sort')),
              const SizedBox(width: 8),
              LChip('只看无损', icon: 'hd', onTap: () => toast('只显示 SQ 及以上', 'hd')),
            ]),
          ),
          for (var k = 0; k < math.min(10, res.length); k++) songRowR(k),
        ]);
        break;
      case '歌单':
        body.addAll([for (final p in playlists.take(5)) _plRow(context, p, hl)]);
        break;
      case '专辑':
        body.add(Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
          child: Wrap(spacing: 10, runSpacing: 16, children: [for (final (i, a) in albums.indexed) _AlbumR(a, artist.hue + i * 30, i, artist.artist, 2026 - i, hl, size: 140)]),
        ));
        break;
      case '艺术家':
        body.addAll([
          for (final (i, a) in artists.take(8).indexed)
            Item(
              lead: Cover(hue: i * 60.0 + 20, variant: 1, size: 48, radius: 24),
              label: a,
              sub: '${12 - i} 万关注 · ${songs.where((s) => s.artist == a).length} 首',
              onTap: () => push(context, ArtistPage(id: songs.firstWhere((s) => s.artist == a).id)),
              trailing: Btn.sec('关注', small: true, onTap: () => toast('已关注 $a', 'heartf')),
            ),
        ]);
        break;
      default:
        body.add(Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
          child: LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 14, children: [for (var i = 0; i < 6; i++) MvCard(i, w: w)]);
          }),
        ));
    }

    return ListView(padding: EdgeInsets.only(top: top, bottom: 170), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 10, 8, 4),
        child: Row(children: [Expanded(child: Text('「$q」', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(24, w: FontWeight.w800, c: pal.t1))), IBtn('close', onTap: onClear)]),
      ),
      // 类型 Tab
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final t in types)
            Press(
              onTap: () => onType(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedDefaultTextStyle(duration: Tk.fast, style: ts(15, w: t == type ? FontWeight.w800 : FontWeight.w500, c: t == type ? pal.t1 : pal.t2), child: Text(t)),
                  const SizedBox(height: 4),
                  AnimatedContainer(duration: Tk.base, width: t == type ? 18 : 0, height: 3, decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ),
        ]),
      ),
      // 平台筛选
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tk.pad, 6, Tk.pad, 6), children: [
          LChip('全部平台', on: rplat == 'all', onTap: () => onPlat('all'), trailing: Text('${counts.reduce((a, b) => a + b)}', style: ts(11, c: pal.t3, num: true))),
          for (final (i, p) in platforms.indexed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Press(
                onTap: () => onPlat(p.id),
                child: AnimatedContainer(
                  duration: Tk.base,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: rplat == p.id ? pal.accSoft : pal.s2, borderRadius: BorderRadius.circular(17), border: Border.all(color: rplat == p.id ? pal.acc.withValues(alpha: .35) : Colors.transparent)),
                  child: Row(children: [PlatBadge(p, size: 18), const SizedBox(width: 5), Text(p.short, style: ts(13, c: rplat == p.id ? pal.accText : pal.t1)), const SizedBox(width: 4), Text('${counts[i]}', style: ts(11, c: pal.t3, num: true))]),
                ),
              ),
            ),
        ]),
      ),
      // 相关搜索
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [
          Row(children: [Icon(ic('trend'), size: 15, color: pal.t3), const SizedBox(width: 4), Text('相关搜索', style: ts(12, c: pal.t3))]),
          for (final x in ['$q 现场', artist.artist, '$q 歌词', artist.album, '$q 翻唱'])
            Padding(padding: const EdgeInsets.only(left: 8), child: Center(child: Press(onTap: () => onQuery(x), child: Text(x, style: ts(12.5, c: pal.accText))))),
        ]),
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Column(key: ValueKey('$type$rplat'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, w) in body.indexed) Rise(i, w)]),
      ),
    ]);
  }

  Widget _plRow(BuildContext context, Playlist p, TextSpan Function(String, TextStyle) hl) {
    final pal = context.pal;
    return Press(
      onTap: () => push(context, PlaylistPage(id: p.id)),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          const SizedBox(width: Tk.pad),
          Cover.pl(p, size: 48, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(hl(p.title, ts(15, w: FontWeight.w600, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${p.count} 首 · ${p.by} · ${p.playCount}次播放', maxLines: 1, style: ts(12.5, c: pal.t2)),
            ]),
          ),
          Icon(ic('right'), color: pal.t3),
          const SizedBox(width: 12),
        ]),
      ),
    );
  }
}

class _AlbumR extends StatelessWidget {
  final String name, artist;
  final double hue;
  final int v, year;
  final double size;
  final TextSpan Function(String, TextStyle) hl;
  const _AlbumR(this.name, this.hue, this.v, this.artist, this.year, this.hl, {this.size = 130});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Press(
      onTap: () => push(context, PlaylistPage(id: v % 8, chartName: name)),
      child: SizedBox(
        width: size + 14,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: size,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 14, top: 4, child: Container(width: size - 8, height: size - 8, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0D0E12), border: Border.all(color: const Color(0xFF26282F), width: 6)))),
              Cover(hue: hue, variant: v, size: size, radius: 12, shadow: true),
            ]),
          ),
          const SizedBox(height: 8),
          Text.rich(hl(name, ts(13, w: FontWeight.w600, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$artist · $year', maxLines: 1, style: ts(12, c: pal.t3)),
        ]),
      ),
    );
  }
}
