// 平台内容页（联网模式）：歌单 / 榜单 / 专辑 / 歌手详情、歌单广场、排行榜。
// 数据来自 AppState.content（lib/platform/），歌曲登记进本机歌曲目录后复用 SongRow（收藏、加歌单、同步都能用）。
import 'dart:math' as math;
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
import '../widgets/sheets.dart' show openAddToPlaylist;
import 'common.dart';

// ---------------------------------------------------------------- 转换

/// 平台代码（wy / tx / …）→ App 里的平台（名称、配色）。
Platform appPlatform(String code) => platformBy(Plat.toAppId[code] ?? code);

/// 把平台歌曲登记进本机歌曲目录，返回 `songs` 里的 id。
int registerTrack(AppState app, PTrack t) => app.library.register(t.toCloud());

double _hue(String k) => (k.hashCode.abs() % 360).toDouble();

/// 平台歌单 / 榜单卡片 → PlCard 用的 Playlist（id 无意义，只用于展示）。
Playlist cardOf(CatalogItem c) => Playlist(-1, c.title, by: c.creator ?? '', count: c.trackCount ?? 0, playCount: c.playCountText, hue: _hue('${c.platform}${c.id}'), variant: c.id.hashCode.abs() % 6, cover: c.cover);

double catalogHue(CatalogItem x) => _hue('${x.platform}${x.id}');

/// 榜单前几首（发现页、排行榜页共用缓存：都按 limit 10 请求）。
/// 同一个 Future 会复用一段时间：FutureBuilder 每次重建拿到同一个 Future，不会闪回加载态。
Future<List<int>> boardTracks(AppState app, CatalogItem b) {
  final memo = _boardMemo[app] ??= {};
  final k = '${b.platform}|${b.id}';
  final hit = memo[k];
  if (hit != null && DateTime.now().difference(hit.$2) < const Duration(minutes: 10)) return hit.$1;
  final f = app.content.collection(b.platform, CatalogType.leaderboard, b.id, limit: 10).then((c) => [for (final t in c.tracks.take(10)) registerTrack(app, t)]);
  memo[k] = (f, DateTime.now());
  f.then((_) {}, onError: (Object _) {
    memo.remove(k);
  });
  return f;
}

final _boardMemo = Expando<Map<String, (Future<List<int>>, DateTime)>>();

/// 下拉刷新时清掉榜单预览缓存。
void clearBoardPreviews(AppState app) => _boardMemo[app]?.clear();

void openCatalog(BuildContext context, CatalogItem c) => push(context, RemoteCollectionPage(platform: c.platform, type: c.type, id: c.id, title: c.title, cover: c.cover, playCount: c.playCountText, creator: c.creator));

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
  final String? title, cover, creator;

  /// 卡片上带过来的播放量文案（详情接口不一定返回）。
  final String playCount;
  const RemoteCollectionPage({super.key, required this.platform, required this.type, required this.id, this.title, this.cover, this.creator, this.playCount = ''});
  @override
  State<RemoteCollectionPage> createState() => _RemoteCollectionPageState();
}

class _RemoteCollectionPageState extends State<RemoteCollectionPage> {
  static const _limit = 100;
  Collection? head;
  final ids = <int>[];
  int page = 0;
  bool busy = false, hasMore = true, expand = false, multi = false;
  String? error;
  String sort = '默认';
  final sel = <int>{};

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
    final by = h?.creator?.isNotEmpty == true ? h!.creator! : (widget.creator?.isNotEmpty == true ? widget.creator! : plat.name);
    final meta = [
      by,
      if (total > 0) '$total 首',
      if (widget.playCount.isNotEmpty) '${widget.playCount} 次播放',
    ].join(' · ');
    var shown = ids;
    if (sort == '歌名') shown = [...ids]..sort((a, b) => songs[a].title.compareTo(songs[b].title));
    if (sort == '时长') shown = [...ids]..sort((a, b) => songs[a].dur.compareTo(songs[b].dur));
    return SubPage(
      title: title,
      fadeTitle: true,
      floating: multi ? _multiBar(context) : null,
      hero: (y) => Positioned(
        left: 0,
        right: 0,
        top: -y * .5,
        height: 420,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.transparent]).createShader(r),
          blendMode: BlendMode.dstIn,
          // 极小图放大代替 sigma 40 的实时高斯模糊（滚动时每帧重算，老机型掉帧）
          child: ClipRect(child: Opacity(opacity: pal.dark ? .65 : .45, child: Transform.scale(scale: 1.3 + math.max(0, -y) / 400, child: BlurCover(hue: hue, variant: 2, url: cover)))),
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
            Avatar(by.characters.first, size: 22),
            const SizedBox(width: 6),
            Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t2))),
          ]),
          if (h != null && h.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
              child: Press(
                onTap: () => setState(() => expand = !expand),
                child: SizedBox(width: 300, child: Text(h.description.trim(), textAlign: TextAlign.center, maxLines: expand ? 40 : 2, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t3, h: 1.55))),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [PlatBadge(plat, size: 14), const SizedBox(width: 5), Text('来自 ${plat.name} · ${catalogNames[widget.type]}', style: ts(12, c: pal.t3))]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 18, Tk.pad, 0),
            child: Row(children: [
              Expanded(child: Btn('播放全部', icon: 'play', onTap: ids.isEmpty ? null : () => app.play(ids.first, name: listName, ids: ids))),
              const SizedBox(width: 10),
              IBtn('shuffle', size: 48, bg: pal.s2, onTap: ids.isEmpty ? null : () {
                final q = [...ids]..shuffle();
                app.play(q.first, name: listName, ids: q);
              }),
              const SizedBox(width: 10),
              IBtn('download', size: 48, bg: pal.s2, onTap: () => toast('下载功能还在开发中', 'info')),
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
              if (widget.type == CatalogType.artist) ...[
                const SizedBox(width: 10),
                IBtn(app.taste.follows(title) ? 'heartf' : 'heart', size: 48, bg: pal.s2, color: app.taste.follows(title) ? pal.accText : null, onTap: () {
                  final on = app.taste.toggleFollow(title, widget.platform, catalogId: widget.id, cover: cover);
                  toast(on ? '已关注 $title，可在「我的 → 关注的歌手」找到' : '已取消关注 $title', on ? 'heartf' : 'heart');
                }),
              ],
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 20, Tk.pad, 6),
          child: Row(children: [
            Expanded(child: Text(h == null ? '歌曲' : '${ids.length}${hasMore ? '+' : ''} 首歌曲', style: ts(15, w: FontWeight.w700, c: pal.t1))),
            LChip(sort, icon: 'sort', h: 30, onTap: () => setState(() => sort = const {'默认': '歌名', '歌名': '时长', '时长': '默认'}[sort]!)),
            const SizedBox(width: 8),
            LChip(multi ? '完成' : '多选', icon: 'check', h: 30, on: multi, onTap: () => setState(() {
                  multi = !multi;
                  sel.clear();
                })),
          ]),
        ),
        if (h == null && error == null) const ListSkeleton(),
        if (h == null && error != null)
          EmptyState('info', '没有加载出来', desc: error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _load)),
        if (h != null && ids.isEmpty && !hasMore) EmptyState('music', '这里还没有歌', desc: '${plat.name}没有返回歌曲，可能需要登录平台账号或该内容已下架。'),
        for (final (i, id) in shown.indexed)
          multi ? _pickRow(context, id) : SongRow(songs[id], key: ValueKey(id), num: widget.type == CatalogType.leaderboard && sort == '默认' ? i : null, list: 'all', listName: listName, queue: shown),
        if (h != null && hasMore) AutoLoad(key: ValueKey('more$page$error'), onLoad: _load, busy: busy, error: error),
      ],
    );
  }

  Widget _pickRow(BuildContext context, int id) {
    final pal = context.pal;
    final on = sel.contains(id);
    return Press(
      key: ValueKey('m$id'),
      onTap: () => setState(() => on ? sel.remove(id) : sel.add(id)),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          const SizedBox(width: Tk.pad),
          AnimatedContainer(duration: Tk.fast, width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? pal.acc : Colors.transparent, border: Border.all(color: on ? pal.acc : pal.t3, width: 1.6)), child: on ? Icon(ic('check'), size: 14, color: pal.ink) : null),
          const SizedBox(width: 12),
          Cover.song(songs[id], size: 48),
          const SizedBox(width: 12),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[id].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w600, c: pal.t1)), Text('${songs[id].artist} · ${songs[id].album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t2))])),
        ]),
      ),
    );
  }

  Widget _multiBar(BuildContext context) {
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
              }),
              ('heart', '收藏', () {
                var n = 0;
                for (final id in sel) {
                  if (!app.liked.contains(id)) {
                    app.toggleLike(id);
                    n++;
                  }
                }
                toast(n > 0 ? '已收藏 $n 首到「我喜欢」' : '选中的歌都已收藏', 'heartf');
              }),
              ('plus', '加歌单', () => openAddToPlaylist(context, sel.first)),
              ('download', '下载', () => toast('下载功能还在开发中', 'info')),
            ])
              Opacity(opacity: sel.isEmpty ? .4 : 1, child: Press(onTap: sel.isEmpty ? null : f, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Column(children: [Icon(ic(i), size: 20, color: pal.t1), Text(l, style: ts(10.5, c: pal.t2))])))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 歌单广场

class PlaylistSquarePage extends StatefulWidget {
  final String platform;

  /// 打开时选中的分类（首页分类 / 心情 / 场景入口）。
  final PlaylistCategory? category;
  const PlaylistSquarePage({super.key, required this.platform, this.category});
  @override
  State<PlaylistSquarePage> createState() => _PlaylistSquarePageState();
}

class _PlaylistSquarePageState extends State<PlaylistSquarePage> {
  static const _limit = 30;
  List<PlaylistCategory> cats = const [];
  late String? cat = widget.category?.id;
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
    // 分类太多时只放前 40 个（按平台返回的顺序），选中的分类始终在里面
    final seen = <String>{};
    final shown = cats.where((c) => seen.add(c.id)).take(40).toList();
    final pre = widget.category;
    if (pre != null && !shown.any((c) => c.id == pre.id)) shown.insert(0, pre);
    return SubPage(title: '${plat.short} · 歌单广场', children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tk.pad, 6, Tk.pad, 6), children: [
          LChip('推荐', on: cat == null, onTap: () => _pick(null)),
          for (final c in shown)
            if (c.name != '推荐' && c.id != 'recommend') Padding(padding: const EdgeInsets.only(left: 8), child: LChip(c.name, on: cat == c.id, onTap: () => _pick(c.id))),
        ]),
      ),
      if (items.isEmpty && busy) const Padding(padding: EdgeInsets.only(top: 12), child: _GridSkeleton(cols: 2)),
      if (items.isEmpty && !busy && error != null) EmptyState('info', '没有加载出来', desc: error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _load)),
      if (items.isEmpty && !busy && error == null && !hasMore) EmptyState('queue', '这个分类下没有歌单', desc: '换个分类看看。'),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
          child: LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 14) / 2;
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
  final int cols;
  const _GridSkeleton({this.cols = 3});
  @override
  Widget build(BuildContext context) => Shimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 14 * (cols - 1)) / cols;
            return Wrap(spacing: 14, runSpacing: 16, children: [
              for (var i = 0; i < cols * 3; i++) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Bone(w: w, h: w, r: 16), const SizedBox(height: 8), Bone(w: w * .8, h: 12)]),
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
  List<CatalogItem>? boards;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final l = await context.appRead.content.leaderboards(widget.platform);
      if (mounted) setState(() => boards = l);
    } catch (e) {
      if (mounted) setState(() => error = platformError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plat = appPlatform(widget.platform);
    final l = boards;
    // 每张卡是列表的直接子项：滚到才构建、才去拉前三首
    return SubPage(title: '${plat.short} · 排行榜', children: [
      const SizedBox(height: 12),
      if (l == null && error == null) const ListSkeleton(),
      if (error != null) EmptyState('info', '排行榜没有加载出来', desc: error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _load)),
      if (l != null && l.isEmpty) EmptyState('chart', '${plat.name}没有返回排行榜'),
      if (l != null)
        for (final x in l) Padding(padding: const EdgeInsets.only(bottom: 12), child: BoardBigCard(x, key: ValueKey(x.id))),
    ]);
  }
}

/// 原型「榜单」页签的大卡：封面 88 + 前三首。
class BoardBigCard extends StatelessWidget {
  final CatalogItem b;
  const BoardBigCard(this.b, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = appPlatform(b.platform);
    return CardBox(
      onTap: () => openCatalog(context, b),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Cover(
          hue: catalogHue(b),
          variant: 2,
          size: 88,
          radius: 14,
          url: b.cover,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)], stops: [.4, 1])),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(8),
            child: Text(b.title, maxLines: 2, style: ts(14, w: FontWeight.w700, c: Colors.white, h: 1.2)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FutureBuilder<List<int>>(
            future: boardTracks(app, b),
            builder: (c, s) {
              final ids = s.data ?? const <int>[];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: i < ids.length
                        ? Text.rich(TextSpan(children: [
                            TextSpan(text: '${i + 1}  ', style: ts(13, w: FontWeight.w700, c: i == 0 ? pal.accText : pal.t1)),
                            TextSpan(text: '${songs[ids[i]].title} - ${songs[ids[i]].artist}'),
                          ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t2))
                        : Bone(w: 120.0 + i * 20, h: 13),
                  ),
                Text(b.subtitle.isNotEmpty ? b.subtitle : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, c: pal.t3)),
              ]);
            },
          ),
        ),
      ]),
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
          Cover(hue: _hue('${c.platform}${c.id}'), variant: c.id.hashCode.abs() % 6, size: 48, radius: artist ? 24 : 10, url: c.cover),
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
