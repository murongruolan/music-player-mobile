// 平台内容页（联网模式）：歌单 / 榜单 / 专辑 / 歌手详情、歌单广场、排行榜。
// 数据来自 AppState.content（lib/platform/），歌曲登记进本机歌曲目录后复用 SongRow（收藏、加歌单、同步都能用）。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../platform/models.dart';
import '../platform/registry.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'common.dart';

// ---------------------------------------------------------------- 转换

/// 平台代码（wy / tx / …）→ App 里的平台（名称、配色）。
Platform appPlatform(String code) => platformBy(Plat.toAppId[code] ?? code);

/// 把平台歌曲登记进本机歌曲目录，返回 `songs` 里的 id。
int registerTrack(AppState app, PTrack t) => app.library.register(t.toCloud());

double _hue(String k) => (k.hashCode.abs() % 360).toDouble();

/// 平台歌单 / 榜单卡片 → PlCard 用的 Playlist（id 无意义，只用于展示）。
Playlist cardOf(CatalogItem c) => Playlist(-1, c.title, by: c.creator ?? '', count: c.trackCount ?? 0, playCount: c.playCountText, hue: _hue('${c.platform}${c.id}'), variant: c.id.hashCode.abs() % 4, cover: c.cover);

void openCatalog(BuildContext context, CatalogItem c) => push(context, RemoteCollectionPage(platform: c.platform, type: c.type, id: c.id, title: c.title, cover: c.cover));

const catalogNames = {CatalogType.playlist: '歌单', CatalogType.leaderboard: '榜单', CatalogType.album: '专辑', CatalogType.artist: '歌手'};

/// 列表滚到底时触发加载下一页：ListView 懒构建，这个占位第一次被构建就说明快到底了。
class AutoLoad extends StatefulWidget {
  final VoidCallback onLoad;
  final bool busy;
  final String? error;
  const AutoLoad({super.key, required this.onLoad, this.busy = false, this.error});
  @override
  State<AutoLoad> createState() => _AutoLoadState();
}

class _AutoLoadState extends State<AutoLoad> {
  @override
  void initState() {
    super.initState();
    if (widget.error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.busy) widget.onLoad();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: widget.error != null
            ? Press(onTap: widget.onLoad, child: Text('${widget.error}，点此重试', style: ts(13, c: pal.accText)))
            : SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: pal.t3)),
      ),
    );
  }
}

/// 加载中的列表骨架。
class ListSkeleton extends StatelessWidget {
  final int rows;
  const ListSkeleton({super.key, this.rows = 6});
  @override
  Widget build(BuildContext context) => Shimmer(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(Tk.pad, 8, Tk.pad, 8),
              child: Row(children: [Bone(w: 48, h: 48, r: 10), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Bone(w: 160, h: 14), SizedBox(height: 8), Bone(w: 100, h: 11)]))]),
            ),
        ]),
      );
}

// ---------------------------------------------------------------- 详情

class RemoteCollectionPage extends StatefulWidget {
  final String platform, id;
  final CatalogType type;
  final String? title, cover;
  const RemoteCollectionPage({super.key, required this.platform, required this.type, required this.id, this.title, this.cover});
  @override
  State<RemoteCollectionPage> createState() => _RemoteCollectionPageState();
}

class _RemoteCollectionPageState extends State<RemoteCollectionPage> {
  static const _limit = 100;
  Collection? head;
  final ids = <int>[];
  int page = 0;
  bool busy = false, hasMore = true, expand = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (busy || !hasMore) return;
    final app = context.appRead;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = await app.content.collection(widget.platform, widget.type, widget.id, page: page + 1, limit: _limit);
      if (!mounted) return;
      final before = ids.length;
      for (final t in c.tracks) {
        final id = registerTrack(app, t);
        if (!ids.contains(id)) ids.add(id);
      }
      setState(() {
        head ??= c;
        page++;
        // 没有新歌也视为到底，防止平台忽略分页时无限加载
        hasMore = c.hasMore && ids.length > before;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = platformError(e);
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final h = head;
    final title = h?.title.isNotEmpty == true ? h!.title : (widget.title ?? catalogNames[widget.type]!);
    final cover = h?.cover ?? widget.cover;
    final hue = _hue('${widget.platform}${widget.id}');
    final plat = appPlatform(widget.platform);
    final total = h == null ? 0 : math.max(h.total, ids.length);
    final collected = widget.type == CatalogType.playlist ? app.library.collectedOf(widget.platform, widget.id) : null;
    final artist = widget.type == CatalogType.artist;
    final listName = title;
    final meta = [
      if (h?.creator?.isNotEmpty == true) h!.creator!,
      if (total > 0) '$total 首',
      plat.name,
    ].join(' · ');
    return SubPage(
      title: title,
      fadeTitle: true,
      hero: (y) => Positioned(
        left: 0,
        right: 0,
        top: -y * .5,
        height: 420,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.transparent]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
              child: Opacity(opacity: pal.dark ? .65 : .45, child: Transform.scale(scale: 1.3 + math.max(0, -y) / 400, child: Cover(hue: hue, variant: 2, size: 0, radius: 0, url: cover))),
            ),
          ),
        ),
      ),
      children: [
        Column(children: [
          const SizedBox(height: 8),
          Cover(hue: hue, variant: 2, size: 196, radius: artist ? 98 : 24, url: cover),
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: Text(title, textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800, c: pal.t1))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            PlatBadge(plat, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t2))),
          ]),
          if (h != null && h.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
              child: Press(
                onTap: () => setState(() => expand = !expand),
                child: Text(h.description.trim(), textAlign: TextAlign.center, maxLines: expand ? 40 : 2, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t3, h: 1.55)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 18, Tk.pad, 0),
            child: Row(children: [
              Expanded(child: Btn('播放全部', icon: 'play', onTap: ids.isEmpty ? null : () => app.play(ids.first, list: 'all', name: listName))),
              const SizedBox(width: 10),
              IBtn('shuffle', size: 48, bg: pal.s2, onTap: ids.isEmpty ? null : () => app.play(ids[math.Random().nextInt(ids.length)], list: 'all', name: listName)),
              if (widget.type == CatalogType.playlist) ...[
                const SizedBox(width: 10),
                IBtn(collected != null ? 'heartf' : 'heart', size: 48, bg: pal.s2, color: collected != null ? pal.accText : null, onTap: () {
                  if (collected != null) {
                    app.library.deletePlaylist(collected.id);
                    toast('已取消收藏歌单', 'heart');
                  } else {
                    app.library.collect(platform: widget.platform, externalId: widget.id, name: title, cover: cover, description: h?.description ?? '', total: total > 0 ? total : null);
                    toast('已收藏到「音乐库 → 歌单」', 'heartf');
                  }
                }),
              ],
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 20, Tk.pad, 6),
          child: Text(h == null ? '歌曲' : '${ids.length}${hasMore ? '+' : ''} 首歌曲', style: ts(15, w: FontWeight.w700, c: pal.t1)),
        ),
        if (h == null && error == null) const ListSkeleton(),
        if (h == null && error != null)
          EmptyState('info', '没有加载出来', desc: error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _load)),
        if (h != null && ids.isEmpty && !hasMore) EmptyState('music', '这里还没有歌', desc: '${plat.name}没有返回歌曲，可能需要登录平台账号或该内容已下架。'),
        for (final (i, id) in ids.indexed) SongRow(songs[id], key: ValueKey(id), num: widget.type == CatalogType.leaderboard ? i : null, list: 'all', listName: listName),
        if (h != null && hasMore) AutoLoad(key: ValueKey('more$page$error'), onLoad: _load, busy: busy, error: error),
      ],
    );
  }
}

// ---------------------------------------------------------------- 歌单广场

class PlaylistSquarePage extends StatefulWidget {
  final String platform;
  const PlaylistSquarePage({super.key, required this.platform});
  @override
  State<PlaylistSquarePage> createState() => _PlaylistSquarePageState();
}

class _PlaylistSquarePageState extends State<PlaylistSquarePage> {
  static const _limit = 30;
  List<PlaylistCategory> cats = const [];
  String? cat;
  final items = <CatalogItem>[];
  int page = 0, gen = 0;
  bool busy = false, hasMore = true;
  String? error;

  @override
  void initState() {
    super.initState();
    context.appRead.content.playlistCategories(widget.platform).then((c) {
      if (mounted) setState(() => cats = c);
    }, onError: (_) {});
    _load();
  }

  void _pick(String? c) {
    if (c == cat) return;
    setState(() {
      cat = c;
      items.clear();
      page = 0;
      hasMore = true;
      busy = false;
      error = null;
      gen++;
    });
    _load();
  }

  Future<void> _load() async {
    if (busy || !hasMore) return;
    final g = gen;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await context.appRead.content.playlists(widget.platform, category: cat, page: page + 1, limit: _limit);
      if (!mounted || g != gen) return;
      final seen = {for (final x in items) x.id};
      final add = r.items.where((x) => seen.add(x.id)).toList();
      setState(() {
        items.addAll(add);
        page++;
        hasMore = r.hasMore && add.isNotEmpty;
        busy = false;
      });
    } catch (e) {
      if (!mounted || g != gen) return;
      setState(() {
        error = platformError(e);
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final plat = appPlatform(widget.platform);
    // 分类太多时只放前 40 个，按桌面端的分组顺序
    final shown = cats.take(40).toList();
    return SubPage(title: '${plat.short} · 歌单广场', children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tk.pad, 6, Tk.pad, 6), children: [
          LChip('推荐', on: cat == null, onTap: () => _pick(null)),
          for (final c in shown)
            if (c.name != '推荐' && c.id != 'recommend') Padding(padding: const EdgeInsets.only(left: 8), child: LChip(c.name, on: cat == c.id, onTap: () => _pick(c.id))),
        ]),
      ),
      if (items.isEmpty && busy) const Padding(padding: EdgeInsets.only(top: 12), child: _GridSkeleton()),
      if (items.isEmpty && !busy && error != null) EmptyState('info', '没有加载出来', desc: error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _load)),
      if (items.isEmpty && !busy && error == null && !hasMore) EmptyState('queue', '这个分类下没有歌单', desc: '换个分类看看。'),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
          child: LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 28) / 3;
            return Wrap(spacing: 14, runSpacing: 16, children: [
              for (final x in items) PlCard(cardOf(x), w: w, onTap: () => openCatalog(context, x)),
            ]);
          }),
        ),
      if (items.isNotEmpty && hasMore) AutoLoad(key: ValueKey('more$gen$page$error'), onLoad: _load, busy: busy, error: error),
      if (items.isNotEmpty && !hasMore) Padding(padding: const EdgeInsets.all(18), child: Center(child: Text('没有更多了', style: ts(12, c: pal.t3)))),
    ]);
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();
  @override
  Widget build(BuildContext context) => Shimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 28) / 3;
            return Wrap(spacing: 14, runSpacing: 16, children: [
              for (var i = 0; i < 9; i++) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Bone(w: w, h: w, r: 16), const SizedBox(height: 8), Bone(w: w * .8, h: 12)]),
            ]);
          }),
        ),
      );
}

// ---------------------------------------------------------------- 排行榜

class LeaderboardsPage extends StatefulWidget {
  final String platform;
  const LeaderboardsPage({super.key, required this.platform});
  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  late Future<List<CatalogItem>> f = context.appRead.content.leaderboards(widget.platform);

  @override
  Widget build(BuildContext context) {
    final plat = appPlatform(widget.platform);
    return SubPage(title: '${plat.short} · 排行榜', children: [
      FutureBuilder<List<CatalogItem>>(
        future: f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.only(top: 12), child: _GridSkeleton());
          if (s.hasError) {
            return EmptyState('info', '排行榜没有加载出来', desc: platformError(s.error!), action: Btn.sec('重试', icon: 'refresh', small: true, onTap: () => setState(() => f = context.appRead.content.leaderboards(widget.platform))));
          }
          final l = s.data!;
          if (l.isEmpty) return EmptyState('chart', '${plat.name}没有返回排行榜');
          return Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
            child: LayoutBuilder(builder: (c, cs) {
              final w = (cs.maxWidth - 28) / 3;
              return Wrap(spacing: 14, runSpacing: 16, children: [for (final x in l) BoardCard(x, w: w)]);
            }),
          );
        },
      ),
    ]);
  }
}

/// 榜单卡：封面 + 名称（叠在封面左下角） + 副标题。
class BoardCard extends StatelessWidget {
  final CatalogItem b;
  final double w;
  const BoardCard(this.b, {super.key, this.w = 110});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SizedBox(
      width: w,
      child: Press(
        onTap: () => openCatalog(context, b),
        scale: .97,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover(
            hue: _hue('${b.platform}${b.id}'),
            variant: 2,
            size: w,
            radius: 16,
            url: b.cover,
            child: b.cover != null
                ? null
                : Align(alignment: Alignment.bottomLeft, child: Padding(padding: const EdgeInsets.all(8), child: Text(b.title, maxLines: 2, style: ts(14, w: FontWeight.w800, c: Colors.white)))),
          ),
          const SizedBox(height: 7),
          Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
          if (b.subtitle.isNotEmpty) Text(b.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, c: pal.t3)),
        ]),
      ),
    );
  }
}

/// 搜索结果里的歌单 / 专辑 / 歌手行。
class CatalogRow extends StatelessWidget {
  final CatalogItem c;
  final TextSpan Function(String, TextStyle)? hl;
  const CatalogRow(this.c, {super.key, this.hl});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final artist = c.type == CatalogType.artist;
    final sub = [
      if (c.type == CatalogType.album && c.creator?.isNotEmpty == true) c.creator!,
      if (c.subtitle.isNotEmpty) c.subtitle,
      if (c.trackCount != null && c.trackCount! > 0) '${c.trackCount} 首',
      if (c.type == CatalogType.playlist && c.creator?.isNotEmpty == true) c.creator!,
      if (c.playCountText.isNotEmpty) '${c.playCountText}次播放',
      if (c.date?.isNotEmpty == true) c.date!,
    ].join(' · ');
    final ts1 = ts(15, w: FontWeight.w600, c: pal.t1);
    return Press(
      onTap: () => openCatalog(context, c),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          const SizedBox(width: Tk.pad),
          Cover(hue: _hue('${c.platform}${c.id}'), variant: c.id.hashCode.abs() % 4, size: 48, radius: artist ? 24 : 10, url: c.cover),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              hl != null ? Text.rich(hl!(c.title, ts1), maxLines: 1, overflow: TextOverflow.ellipsis) : Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts1),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t2)),
            ]),
          ),
          Icon(ic('right'), color: pal.t3),
          const SizedBox(width: 12),
        ]),
      ),
    );
  }
}
