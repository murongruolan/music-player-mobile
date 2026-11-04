// 二级页：歌单详情（模糊背景视差 + 多选）、歌手、听歌统计。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../platform/models.dart' show CatalogType;
import '../platform/registry.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';
import 'backup.dart' show SponsorGate, toastApiError;
import 'common.dart';
import 'discover.dart';
import 'remote.dart';

class PlaylistPage extends StatefulWidget {
  final int id;
  final String? chartName;
  const PlaylistPage({super.key, required this.id, this.chartName});
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool multi = false, faved = false;
  String sort = '默认';
  final sel = <int>{};

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final online = app.online;
    final Playlist? found = online
        ? (widget.id == 100 ? Playlist(100, '我喜欢的音乐', count: app.liked.length, hue: 42, variant: 0, mine: true) : app.myPlaylists.where((x) => x.id == widget.id).firstOrNull)
        : widget.id >= 100
            ? (app.myPlaylists.where((x) => x.id == widget.id).firstOrNull ?? app.myPlaylists.firstOrNull)
            : playlists[widget.id % playlists.length];
    if (found == null) {
      return SubPage(title: '歌单', children: [const EmptyState('queue', '歌单不存在', desc: '它可能已被删除，或在其它设备上被移除。')]);
    }
    final Playlist base = found;
    // 收藏的平台歌单只同步了平台 + 歌单 id：直接打开平台详情拉歌曲
    if (online && base.kind == 'collected' && base.externalId != null && base.platform != null && app.content.supports(base.platform!)) {
      return RemoteCollectionPage(platform: PlatformHub.codeOf(base.platform!), type: CatalogType.playlist, id: base.externalId!, title: base.title, cover: base.cover);
    }
    final pl = widget.chartName == null || online ? base : Playlist(base.id, widget.chartName!, by: '${app.platform.name} 官方', count: 30, playCount: base.playCount, hue: base.hue, variant: 2);
    var ids = widget.id == 100
        ? app.liked.where((i) => i < songs.length).toList()
        : online
            ? base.ids.where((i) => i < songs.length).toList()
            : [for (var i = 0; i < songs.length; i++) if ((i * 7 + pl.hue.toInt()) % 3 != 0) i].take(14).toList();
    final collected = online && base.kind == 'collected' && ids.isEmpty;
    if (sort == '歌名') ids = [...ids]..sort((a, b) => songs[a].title.compareTo(songs[b].title));
    if (sort == '时长') ids = [...ids]..sort((a, b) => songs[a].dur.compareTo(songs[b].dur));
    final listName = pl.title;
    return SubPage(
      title: pl.title,
      fadeTitle: true,
      actions: [IBtn('share', onTap: () => openShareCode(context, playlistTitle: pl.title))],
      hero: (y) => Positioned(
        left: 0,
        right: 0,
        top: -y * .5,
        height: 420,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.transparent]).createShader(r),
          blendMode: BlendMode.dstIn,
          // 极小图放大代替 sigma 40 的实时高斯模糊（滚动时每帧重算，老机型掉帧）
          child: ClipRect(child: Opacity(opacity: pal.dark ? .65 : .45, child: Transform.scale(scale: 1.3 + math.max(0, -y) / 400, child: BlurCover(hue: pl.hue, variant: pl.variant, url: pl.cover)))),
        ),
      ),
      floating: multi ? _multiBar(context, ids) : null,
      children: [
        Column(children: [
          const SizedBox(height: 8),
          Hero(tag: 'pl-${pl.id}', child: Cover.pl(pl, size: 196, radius: 24, child: widget.id == 100 ? const Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: 64)) : null)),
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: Text(pl.title, textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800, c: pal.t1))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Avatar((pl.by.isEmpty ? '我' : pl.by)[0], size: 22),
            const SizedBox(width: 6),
            Text('${pl.by.isEmpty ? '我' : pl.by} · ${pl.count} 首${pl.playCount.isNotEmpty ? ' · ${pl.playCount} 次播放' : ''}', style: ts(13, c: pal.t2)),
          ]),
          const SizedBox(height: 8),
          if (!online) SizedBox(width: 300, child: Text('适合在夜里一个人走路时听。霓虹、雨声、合成器和一点点想念。', textAlign: TextAlign.center, style: ts(12.5, c: pal.t3, h: 1.55))),
          if (online && base.platform != null) Text('来自 ${_platName(base.platform!)}${base.externalId != null ? ' · ID ${base.externalId}' : ''}', style: ts(12, c: pal.t3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 18, Tk.pad, 0),
            child: Row(children: [
              Expanded(child: Btn('播放全部', icon: 'play', onTap: () {
                if (!online) return app.playAll(widget.id == 100 ? 'like' : 'all', name: listName);
                if (ids.isNotEmpty) app.play(ids.first, name: listName, ids: ids);
              })),
              const SizedBox(width: 10),
              IBtn('shuffle', size: 48, bg: pal.s2, onTap: () {
                if (!online) return app.playAll(widget.id == 100 ? 'like' : 'all', shuffle: true, name: listName);
                if (ids.isEmpty) return;
                final q = [...ids]..shuffle();
                app.play(q.first, name: listName, ids: q);
              }),
              const SizedBox(width: 10),
              IBtn('download', size: 48, bg: pal.s2, onTap: () => online ? toast('下载功能还在开发中', 'info') : toast('已加入下载队列 · ${pl.count} 首', 'download')),
              const SizedBox(width: 10),
              if (online && widget.id != 100)
                IBtn('trash', size: 48, bg: pal.s2, onTap: () => showLDialog(context, icon: 'trash', iconColor: pal.danger, title: '删除歌单「${pl.title}」？', body: '歌单里的歌不会从「我喜欢」中移除。', actions: [
                      ('取消', BtnKind.sec, null),
                      ('删除', BtnKind.danger, () {
                        app.library.deletePlaylist(base.id);
                        Navigator.of(context).maybePop();
                        toast('已删除歌单', 'trash');
                      }),
                    ]))
              else if (!online)
                IBtn(faved ? 'heartf' : 'heart', size: 48, bg: pal.s2, color: faved ? pal.accText : null, onTap: () {
                  setState(() => faved = !faved);
                  toast(faved ? '已收藏歌单' : '已取消收藏', faved ? 'heartf' : 'heart');
                }),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 20, Tk.pad, 6),
          child: Row(children: [
            Expanded(child: Text('${ids.length} 首歌曲', style: ts(15, w: FontWeight.w700, c: pal.t1))),
            LChip(sort, icon: 'sort', h: 30, onTap: () => setState(() => sort = const {'默认': '歌名', '歌名': '时长', '时长': '默认'}[sort]!)),
            const SizedBox(width: 8),
            LChip(multi ? '完成' : '多选', icon: 'check', h: 30, on: multi, onTap: () => setState(() {
              multi = !multi;
              sel.clear();
            })),
          ]),
        ),
        if (ids.isEmpty && online)
          EmptyState(collected ? 'link' : 'music', collected ? '这是收藏的平台歌单' : '歌单还是空的', desc: collected ? '它只同步了平台和歌单 ID（${pl.count} 首），歌曲列表要等平台接口接入后再拉取。' : (widget.id == 100 ? '收藏的歌会出现在这里。' : '在歌曲的「···」里选「加入歌单」。')),
        for (final id in ids)
          multi
              ? Press(
                  onTap: () => setState(() => sel.contains(id) ? sel.remove(id) : sel.add(id)),
                  child: SizedBox(
                    height: 64,
                    child: Row(children: [
                      const SizedBox(width: Tk.pad),
                      AnimatedContainer(duration: Tk.fast, width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: sel.contains(id) ? pal.acc : Colors.transparent, border: Border.all(color: sel.contains(id) ? pal.acc : pal.t3, width: 1.6)), child: sel.contains(id) ? Icon(ic('check'), size: 14, color: pal.ink) : null),
                      const SizedBox(width: 12),
                      Cover.song(songs[id], size: 48),
                      const SizedBox(width: 12),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[id].title, style: ts(15, w: FontWeight.w600, c: pal.t1)), Text('${songs[id].artist} · ${songs[id].album}', style: ts(12.5, c: pal.t2))])),
                    ]),
                  ),
                )
              : SongRow(songs[id], key: ValueKey(id), list: widget.id == 100 ? 'like' : 'all', listName: listName, heart: widget.id == 100, queue: online ? ids : null),
      ],
    );
  }

  Widget _multiBar(BuildContext context, List<int> ids) {
    final pal = context.pal;
    final app = context.app;
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 112,
      child: Glass(
        radius: 22,
        color: pal.glassStrong,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(children: [
            const SizedBox(width: 10),
            Text('已选 ${sel.length}', style: ts(13.5, w: FontWeight.w700, c: pal.t1)),
            const Spacer(),
            for (final (i, l, f) in [
              ('next', '下一首', () {
                for (final id in sel) {
                  app.playNext(id);
                }
                toast('已添加 ${sel.length} 首到下一首播放', 'next');
              }),
              ('plus', '加歌单', () => openAddToPlaylist(context, sel.isEmpty ? ids.first : sel.first)),
              ('download', '下载', () => toast('已加入下载 · ${sel.length} 首', 'download')),
              ('trash', '移除', () => showLDialog(context, icon: 'trash', title: '从歌单移除 ${sel.length} 首？', actions: [
                    ('取消', BtnKind.sec, null),
                    ('移除', BtnKind.danger, () {
                      if (app.online) {
                        if (widget.id == 100) {
                          for (final id in sel) {
                            if (app.liked.contains(id)) app.toggleLike(id);
                          }
                        } else {
                          app.library.removeFromPlaylist(widget.id, {...sel});
                        }
                        setState(() => sel.clear());
                      }
                      toast('已移除', 'trash');
                    }),
                  ])),
            ])
              Opacity(opacity: sel.isEmpty ? .4 : 1, child: Press(onTap: sel.isEmpty ? null : f, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Column(children: [Icon(ic(i), size: 20, color: pal.t1), Text(l, style: ts(10.5, c: pal.t2))])))),
          ]),
        ),
      ),
    );
  }
}

class ArtistPage extends StatefulWidget {
  final int id;
  const ArtistPage({super.key, required this.id});
  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  bool follow = false;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.songById(widget.id);
    final mine = app.online ? songs.where((x) => x.artist == s.artist).toList() : {...songs.where((x) => x.artist == s.artist), ...songs.take(3)}.take(6).toList();
    return SubPage(
      title: s.artist,
      fadeTitle: true,
      actions: [IBtn(follow ? 'heartf' : 'heart', color: follow ? pal.accText : null, onTap: () {
        setState(() => follow = !follow);
        toast(follow ? '已关注 ${s.artist}' : '已取消关注', 'heartf');
      })],
      hero: (y) => Positioned(
        left: 0,
        right: 0,
        top: -y * .45,
        height: 380,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, .55, 1]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: Transform.scale(scale: 1 + math.max(0, -y) / 380, child: Cover(hue: s.hue, variant: 1, size: 0, radius: 0, url: app.online ? mine.where((x) => x.cover != null).firstOrNull?.cover ?? s.cover : null)),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 150, Tk.pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.artist, style: ts(34, w: FontWeight.w800, c: Colors.white).copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 20)])),
            const SizedBox(height: 6),
            Text(app.online ? '音乐库里 ${mine.length} 首' : '12.4 万关注 · 本月 38 万次聆听', style: ts(13, c: pal.t2)),
            const SizedBox(height: 16),
            Row(children: [
              Btn('播放热门', icon: 'play', onTap: () {
                if (!app.online) return app.playAll('all', name: '${s.artist} · 热门');
                if (mine.isNotEmpty) app.play(mine.first.id, name: s.artist, ids: [for (final x in mine) x.id]);
              }),
              const SizedBox(width: 10),
              Btn.sec('歌手电台', icon: 'wave', onTap: () {
                app.playAll('hot', shuffle: true, name: '${s.artist} 电台');
                toast('${s.artist} 电台：相似歌手连续播放', 'wave');
              }),
            ]),
          ]),
        ),
        Sec(app.online ? '音乐库里的歌' : '热门歌曲'),
        for (final (i, x) in mine.indexed) SongRow(x, num: i, list: 'all', listName: '${s.artist} · 热门', queue: app.online ? [for (final y in mine) y.id] : null),
        if (!app.online) const Sec('专辑'),
        if (!app.online) HScroll(height: 186, gap: 26, children: [for (final (i, id) in [s.id, (s.id + 8) % 24, (s.id + 16) % 24].indexed) AlbumCard(songs[id], onTap: () => push(context, PlaylistPage(id: i, chartName: songs[id].album)))]),
      ],
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String range = '近 7 天';
  bool busy = false;

  int get _days => range == '近 7 天' ? 7 : range == '近 30 天' ? 30 : 90;

  @override
  Widget build(BuildContext context) => context.app.online ? _real(context) : _demo(context);

  /// 本机记录 + 与云端合并后的真实统计。
  Widget _real(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final st = app.cloud.stats;
    final sum = st.summary(_days);
    final cards = [('聆听时长', sum.ms / 3600000, 1, '小时'), ('播放次数', sum.plays.toDouble(), 0, '次'), ('不同歌曲', sum.songs.toDouble(), 0, '首'), ('不同歌手', sum.artists.toDouble(), 0, '位')];
    final mins = st.dailyMinutes(7);
    final maxMin = mins.fold<int>(1, math.max);
    final today = DateTime.now();
    final foot = st.dailyPlays(90);
    final maxFoot = foot.fold<int>(1, math.max);
    final top = st.topArtists(_days);
    return SubPage(title: '听歌统计', children: [
      Seg(const ['近 7 天', '近 30 天', '近 90 天'], range, (v) => setState(() => range = v)),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final (l, v, d, u) in cards)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l, style: ts(12, c: pal.t2)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [CountUp(v, key: ValueKey('$range$l$v'), decimals: d, style: ts(28, w: FontWeight.w800, c: pal.t1, num: true)), const SizedBox(width: 3), Text(u, style: ts(13, c: pal.t3))]),
                ]),
              ),
          ],
        ),
      ),
      if (sum.plays == 0) const Hint('还没有听歌记录。一首歌听满 30 秒（短歌听满一半）会记一次播放。', padding: EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0)),
      const Sec('近 7 天每日时长', size: 16, more: '分钟'),
      CardBox(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
        child: SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${mins[i]}', style: ts(10, c: pal.t3, num: true)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    key: ValueKey('bar$i${mins[i]}'),
                    tween: Tween(begin: 0, end: mins[i] / maxMin),
                    duration: Duration(milliseconds: 600 + i * 60),
                    curve: Tk.softSpring,
                    builder: (_, v, __) => Container(height: math.max(2.0, 110 * v), margin: const EdgeInsets.symmetric(horizontal: 7), decoration: BoxDecoration(color: pal.acc.withValues(alpha: i == 6 ? 1 : .55), borderRadius: BorderRadius.circular(6))),
                  ),
                  const SizedBox(height: 6),
                  Text('一二三四五六日'[DateTime(today.year, today.month, today.day - 6 + i).weekday - 1], style: ts(11, c: pal.t3)),
                ]),
              ),
          ]),
        ),
      ),
      const Sec('90 天足迹', size: 16),
      CardBox(
        child: GridView.count(
          crossAxisCount: 15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [for (final n in foot) Container(decoration: BoxDecoration(color: pal.acc.withValues(alpha: n == 0 ? .06 : .2 + .8 * n / maxFoot), borderRadius: BorderRadius.circular(3)))],
        ),
      ),
      if (top.isNotEmpty) ...[
        const Sec('最常听的歌手', size: 16),
        HScroll(height: 120, gap: 16, children: [
          for (final (i, (a, n)) in top.indexed)
            SizedBox(width: 76, child: Column(children: [Cover(hue: i * 60.0 + 20, variant: 1, size: 76, radius: 38), const SizedBox(height: 6), Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, c: pal.t1)), Text('$n 次', style: ts(11, c: pal.t3))])),
        ]),
      ],
      const SizedBox(height: 18),
      if (app.isSponsor)
        Group(title: '云端统计', foot: '与桌面端等其它设备上的听歌统计合并显示。合并取各设备的最大值，不会重复累加。', children: [
          Item(icon: 'refresh', color: 'teal', label: '从云端合并', trailing: busy ? const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null, onTap: busy ? null : () => _cloud(() async {
                final r = await app.cloud.engine!.download('listening_stats', replace: false);
                toast(r.changed ? '已合并云端统计' : '云端还没有统计数据', r.changed ? 'check' : 'info');
              })),
          Item(icon: 'up', color: 'blue', label: '上传本机记录', onTap: busy ? null : () => _cloud(() async {
                await app.cloud.engine!.upload('listening_stats');
                toast('已上传到云端', 'cloud');
              })),
        ])
      else
        const SponsorGate('云端听歌统计', desc: '激活赞助后，听歌统计可以上传到账号，并与桌面端等其它设备合并显示。'),
      Group(children: [
        Item(icon: 'trash', color: 'red', label: '清除听歌记录', danger: true, chev: false, onTap: () => showLDialog(context, icon: 'trash', iconColor: pal.danger, title: '清除全部听歌记录？', body: app.isSponsor ? '本机记录和云端统计都会被清空。其它设备上的记录需要在那台设备上单独清除，否则下次同步会合并回来。' : '本机的听歌记录会被清空，此操作不可撤销。', actions: [
              ('取消', BtnKind.sec, null),
              ('清除', BtnKind.danger, () => _cloud(() async {
                    await app.cloud.clearStats();
                    toast('已清除听歌记录', 'trash');
                  })),
            ])),
      ]),
    ]);
  }

  Future<void> _cloud(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      toastApiError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 演示模式（截图 / 测试）：原来的 mock 统计。
  Widget _demo(BuildContext context) {
    final pal = context.pal;
    final k = range == '近 7 天' ? 1.0 : range == '近 30 天' ? 4.1 : 11.6;
    final cards = [('聆听时长', 6.2 * k, 1, '小时', '+18%'), ('播放次数', 214 * k, 0, '次', '+9%'), ('不同歌曲', 63 * math.sqrt(k), 0, '首', ''), ('不同歌手', 21 * math.sqrt(k), 0, '位', '')];
    const bars = [42, 65, 38, 80, 54, 96, 71];
    final rnd = math.Random(7);
    return SubPage(title: '听歌统计', children: [
      Seg(const ['近 7 天', '近 30 天', '近 90 天'], range, (v) => setState(() => range = v)),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final (l, v, d, u, delta) in cards)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l, style: ts(12, c: pal.t2)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [CountUp(v, key: ValueKey('$range$l'), decimals: d, style: ts(28, w: FontWeight.w800, c: pal.t1, num: true)), const SizedBox(width: 3), Text(u, style: ts(13, c: pal.t3))]),
                  if (delta.isNotEmpty) Text('较上期 $delta', style: ts(11.5, c: pal.ok)),
                ]),
              ),
          ],
        ),
      ),
      const Sec('每日时长', size: 16, more: '分钟'),
      CardBox(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
        child: SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${(bars[i] * 1.2).round()}', style: ts(10, c: pal.t3, num: true)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    key: ValueKey('$range$i'),
                    tween: Tween(begin: 0, end: bars[(i + range.length) % 7] / 100),
                    duration: Duration(milliseconds: 600 + i * 60),
                    curve: Tk.softSpring,
                    builder: (_, v, __) => Container(height: 110 * v, margin: const EdgeInsets.symmetric(horizontal: 7), decoration: BoxDecoration(color: pal.acc.withValues(alpha: i == 5 ? 1 : .55), borderRadius: BorderRadius.circular(6))),
                  ),
                  const SizedBox(height: 6),
                  Text('一二三四五六日'[i], style: ts(11, c: pal.t3)),
                ]),
              ),
          ]),
        ),
      ),
      const Sec('风格分布', size: 16),
      CardBox(
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(height: 12, child: Row(children: [for (final (i, t) in tasteChips.indexed) Expanded(flex: t[1] as int, child: Container(color: hsl(40.0 + i * 52, .7, .62)))])),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 8, children: [
            for (final (i, t) in tasteChips.indexed) Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: hsl(40.0 + i * 52, .7, .62), shape: BoxShape.circle)), const SizedBox(width: 5), Text('${t[0]} ${t[1]}%', style: ts(12, c: pal.t2))]),
          ]),
        ]),
      ),
      const Sec('90 天足迹', size: 16),
      CardBox(
        child: GridView.count(
          crossAxisCount: 15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [for (var i = 0; i < 90; i++) Container(decoration: BoxDecoration(color: pal.acc.withValues(alpha: .08 + rnd.nextDouble() * .9 * (i % 7 == 3 ? .3 : 1)), borderRadius: BorderRadius.circular(3)))],
        ),
      ),
      const Sec('最常听的歌手', size: 16),
      HScroll(height: 120, gap: 16, children: [
        for (final (i, a) in songs.map((s) => s.artist).toSet().take(6).indexed)
          SizedBox(width: 76, child: Column(children: [Cover(hue: i * 60.0 + 20, variant: 1, size: 76, radius: 38), const SizedBox(height: 6), Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, c: pal.t1)), Text('${48 - i * 7} 次', style: ts(11, c: pal.t3))])),
      ]),
    ]);
  }
}

String _platName(String code) {
  const m = {'wy': '网易云音乐', 'tx': 'QQ音乐', 'kg': '酷狗音乐', 'kw': '酷我音乐', 'mg': '咪咕音乐', 'local': '本地'};
  return m[code] ?? code;
}
