// 搜索 · 联网模式：沿用原型的结果页（类型 Tab · 平台筛选 · 相关搜索 · 综合 / 歌曲 / 歌单 / 专辑 / 艺术家 / MV），
// 数据来自各平台的搜索接口。「全部平台」同时搜五个平台并交替合并。
part of 'search.dart';

// ---------------------------------------------------------------- 默认态：热搜

class _HotSearch extends StatefulWidget {
  final String plat;
  final ValueChanged<String> onPick;
  const _HotSearch({required this.plat, required this.onPick});
  @override
  State<_HotSearch> createState() => _HotSearchState();
}

class _HotSearchState extends State<_HotSearch> {
  late Future<List<String>> f = context.appRead.content.hotSearch(widget.plat);

  @override
  void didUpdateWidget(_HotSearch o) {
    super.didUpdateWidget(o);
    if (o.plat != widget.plat) f = context.appRead.content.hotSearch(widget.plat);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = platformBy(widget.plat);
    return FutureBuilder<List<String>>(
      future: f,
      builder: (c, s) {
        final l = s.data ?? const <String>[];
        if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.only(top: 18), child: ListSkeleton(rows: 4));
        if (s.hasError || l.isEmpty) return Hint(s.hasError ? '${p.name}热搜没有加载出来：${platformError(s.error!)}' : '${p.name}暂时没有热搜', padding: const EdgeInsets.fromLTRB(Tk.pad, 18, Tk.pad, 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('热搜榜', size: 16, more: p.name),
          CardBox(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (i, h) in l.take(10).indexed)
                Press(
                  onTap: () => widget.onPick(h),
                  child: SizedBox(
                    height: 48,
                    child: Row(children: [
                      const SizedBox(width: 16),
                      SizedBox(width: 26, child: Text('${i + 1}', style: ts(15, w: FontWeight.w700, c: i < 3 ? pal.accText : pal.t3, num: true))),
                      Expanded(child: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14.5, w: FontWeight.w500, c: pal.t1))),
                      if (i == 0) const Badge2('热', acc: true),
                      const SizedBox(width: 16),
                    ]),
                  ),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- 输入联想

/// 平台联想（停顿 300ms 再请求），行样式与原型的联想行一致。
class _RemoteSuggest extends StatefulWidget {
  final String q, plat;
  final ValueChanged<String> onPick;
  final TextSpan Function(String, TextStyle) hl;
  const _RemoteSuggest({super.key, required this.q, required this.plat, required this.onPick, required this.hl});
  @override
  State<_RemoteSuggest> createState() => _RemoteSuggestState();
}

class _RemoteSuggestState extends State<_RemoteSuggest> {
  Timer? _t;
  List<String> items = const [];
  String asked = '';

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_RemoteSuggest o) {
    super.didUpdateWidget(o);
    if (o.q != widget.q) _schedule();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 300), () async {
      final q = widget.q;
      asked = q;
      try {
        final r = await context.appRead.content.suggest(widget.plat, q);
        if (mounted && asked == q) setState(() => items = r.where((x) => x.trim().isNotEmpty && x != q).take(6).toList());
      } catch (_) {
        if (mounted && asked == q) setState(() => items = const []);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(children: [
      for (final (k, t) in items.indexed)
        Rise(
          k,
          Press(
            onTap: () => widget.onPick(t),
            child: Padding(
              padding: const EdgeInsets.only(left: Tk.pad, right: 6),
              child: SizedBox(
                height: 50,
                child: Row(children: [
                  Icon(ic('search'), color: pal.t3, size: 19),
                  const SizedBox(width: 12),
                  Expanded(child: Text.rich(widget.hl(t, ts(15, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(platformBy(widget.plat).short, style: ts(12, c: pal.t3)),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- 结果页

const _typeOf = {'歌曲': SearchType.song, '歌单': SearchType.playlist, '专辑': SearchType.album, '艺术家': SearchType.artist, 'MV': SearchType.mv};

class _Bucket {
  final songs = <int>[];
  final mvs = <PTrack>[];
  final items = <CatalogItem>[];
  int page = 0, total = 0;
  bool busy = false, hasMore = true;
  String? error, note;
  bool get empty => songs.isEmpty && mvs.isEmpty && items.isEmpty;
  bool get done => page > 0 || error != null;
}

class _OnlineResults extends StatefulWidget {
  final String q, plat, type;
  final ValueChanged<String> onType, onPlat, onQuery;
  final VoidCallback onClear;
  const _OnlineResults({super.key, required this.q, required this.plat, required this.type, required this.onType, required this.onPlat, required this.onQuery, required this.onClear});
  @override
  State<_OnlineResults> createState() => _OnlineResultsState();
}

class _OnlineResultsState extends State<_OnlineResults> {
  final _b = <String, _Bucket>{};

  /// 各平台歌曲结果总数（平台筛选上的数字）。
  final totals = <String, int>{};
  bool lossless = false;
  late final Future<List<String>> related = context.appRead.content.suggest(context.appRead.plat, widget.q).catchError((Object _) => <String>[]);

  _Bucket _bucket(String plat, SearchType t) => _b.putIfAbsent('$plat|${t.name}', _Bucket.new);

  /// 当前平台筛选支持的搜索类型（全部平台 = 五个平台的并集）。
  Set<SearchType> _types(String plat) {
    final hub = context.appRead.content;
    if (plat != 'all') return hub.of(plat)?.searchTypes ?? const {SearchType.song};
    return {for (final c in Plat.all) ...?hub.of(c)?.searchTypes};
  }

  /// 需要时安排加载第一页（构建期间不能直接 setState）。
  void _ensure(SearchType t) {
    final b = _bucket(widget.plat, t);
    if (b.page == 0 && !b.busy && b.error == null && _types(widget.plat).contains(t)) {
      b.busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        b.busy = false;
        _load(t);
      });
    }
  }

  Future<void> _load(SearchType t) async {
    if (!mounted) return;
    final plat = widget.plat;
    final b = _bucket(plat, t);
    if (b.busy || !b.hasMore) return;
    final app = context.appRead;
    final hub = app.content;
    setState(() {
      b.busy = true;
      b.error = null;
    });
    try {
      final page = b.page + 1;
      final results = <(String, SearchResult)>[];
      final failed = <String>[];
      String? note;
      if (plat == 'all') {
        final codes = [for (final c in Plat.all) if (hub.of(c)?.searchTypes.contains(t) ?? false) c];
        final rs = await Future.wait([
          for (final c in codes) hub.search(c, widget.q, t, page: page, limit: 10, fallback: false).then<SearchOutcome?>((o) => o, onError: (Object _) => null),
        ]);
        for (final (i, o) in rs.indexed) {
          if (o == null) {
            failed.add(Plat.names[codes[i]]!);
          } else {
            results.add((codes[i], o.result));
          }
        }
        if (results.isEmpty) throw PlatformException('all', '各平台都没有返回结果');
        if (failed.isNotEmpty) note = '${failed.join('、')}搜索失败，下面是其它平台的结果';
      } else {
        final o = await hub.search(plat, widget.q, t, page: page, limit: 30);
        results.add((o.platform, o.result));
        if (o.fallbackFrom != null) note = '${appPlatform(o.fallbackFrom!).name}搜索失败（${o.error}），下面是${appPlatform(o.platform).name}的结果';
      }
      if (!mounted) return;
      var added = 0;
      // 多个平台的结果交替合并：A1 B1 C1 A2 B2 …
      final n = results.fold<int>(0, (m, r) => math.max(m, math.max(r.$2.songs.length, r.$2.items.length)));
      final seenSongs = {...b.songs}, seenMv = {for (final x in b.mvs) x.id}, seenItems = {for (final x in b.items) '${x.platform}${x.id}'};
      for (var i = 0; i < n; i++) {
        for (final (_, r) in results) {
          if (t == SearchType.mv) {
            if (i < r.songs.length && seenMv.add(r.songs[i].id)) {
              b.mvs.add(r.songs[i]);
              added++;
            }
          } else if (t == SearchType.song) {
            if (i < r.songs.length) {
              final id = registerTrack(app, r.songs[i]);
              if (seenSongs.add(id)) {
                b.songs.add(id);
                added++;
              }
            }
          } else if (i < r.items.length && seenItems.add('${r.items[i].platform}${r.items[i].id}')) {
            b.items.add(r.items[i]);
            added++;
          }
        }
      }
      setState(() {
        b.page = page;
        b.total = results.fold<int>(0, (s, r) => s + r.$2.total);
        b.hasMore = results.any((r) => r.$2.hasMore) && added > 0;
        b.busy = false;
        b.note = note ?? b.note;
        if (t == SearchType.song && page == 1) {
          for (final (c, r) in results) {
            totals[c] = r.total > 0 ? r.total : r.songs.length;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        b.error = platformError(e);
        b.busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final q = widget.q;
    final hl = highlighter(q, pal.accText);
    final top = MediaQuery.of(context).padding.top;
    final supported = _types(widget.plat);
    final types = ['综合', for (final e in _typeOf.entries) if (supported.contains(e.value)) e.key];
    final type = types.contains(widget.type) ? widget.type : '综合';
    // 平台筛选上的数字来自歌曲搜索的总数
    _ensure(SearchType.song);

    final body = type == '综合' ? _overview(context, hl, supported) : _typed(context, _typeOf[type]!, hl);
    final allCount = totals.values.fold<int>(0, (a, b) => a + b);

    return ListView(padding: EdgeInsets.only(top: top, bottom: 170), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 10, 8, 4),
        child: Row(children: [Expanded(child: Text('「$q」', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(24, w: FontWeight.w800, c: pal.t1))), IBtn('close', onTap: widget.onClear)]),
      ),
      // 类型 Tab
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final t in types)
            Press(
              onTap: () => widget.onType(t),
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
          LChip('全部平台', on: widget.plat == 'all', onTap: () => widget.onPlat('all'), trailing: widget.plat == 'all' && allCount > 0 ? Text(_count(allCount), style: ts(11, c: pal.t3, num: true)) : null),
          for (final p in platforms)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Press(
                onTap: () => widget.onPlat(p.id),
                child: AnimatedContainer(
                  duration: Tk.base,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: widget.plat == p.id ? pal.accSoft : pal.s2, borderRadius: BorderRadius.circular(17), border: Border.all(color: widget.plat == p.id ? pal.acc.withValues(alpha: .35) : Colors.transparent)),
                  child: Row(children: [
                    PlatBadge(p, size: 18),
                    const SizedBox(width: 5),
                    Text(p.short, style: ts(13, c: widget.plat == p.id ? pal.accText : pal.t1)),
                    if (totals[PlatformHub.codeOf(p.id)] case final n? when n > 0) ...[const SizedBox(width: 4), Text(_count(n), style: ts(11, c: pal.t3, num: true))],
                  ]),
                ),
              ),
            ),
        ]),
      ),
      // 相关搜索（平台联想）
      FutureBuilder<List<String>>(
        future: related,
        builder: (c, s) {
          final l = (s.data ?? const <String>[]).where((x) => x != q).take(5).toList();
          if (l.isEmpty) return const SizedBox(height: 4);
          return SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [
              Row(children: [Icon(ic('trend'), size: 15, color: pal.t3), const SizedBox(width: 4), Text('相关搜索', style: ts(12, c: pal.t3))]),
              for (final x in l) Padding(padding: const EdgeInsets.only(left: 8), child: Center(child: Press(onTap: () => widget.onQuery(x), child: Text(x, style: ts(12.5, c: pal.accText))))),
            ]),
          );
        },
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Column(key: ValueKey('$type${widget.plat}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, w) in body.indexed) Rise(math.min(i, 8), w)]),
      ),
    ]);
  }

  static String _count(int n) => n >= 10000 ? '${(n / 10000).toStringAsFixed(n >= 100000 ? 0 : 1)}万' : '$n';

  Widget _status(_Bucket b, SearchType t, String what) {
    if (!b.done) return const ListSkeleton(rows: 4);
    if (b.error != null) return EmptyState('info', '搜索失败', desc: b.error, action: Btn.sec('重试', icon: 'refresh', small: true, onTap: () => _load(t)));
    return EmptyState('search', '没有找到「${widget.q}」相关的$what', desc: '换个关键词，或切到其它平台试试。');
  }

  // ---------- 综合 ----------
  List<Widget> _overview(BuildContext context, TextSpan Function(String, TextStyle) hl, Set<SearchType> supported) {
    final pal = context.pal;
    for (final t in SearchType.values) {
      if (supported.contains(t)) _ensure(t);
    }
    final songsB = _bucket(widget.plat, SearchType.song);
    final albums = _bucket(widget.plat, SearchType.album);
    final pls = _bucket(widget.plat, SearchType.playlist);
    final mvs = _bucket(widget.plat, SearchType.mv);
    final artists = _bucket(widget.plat, SearchType.artist);
    final best = artists.items.firstOrNull;
    final all = [songsB, if (supported.contains(SearchType.album)) albums, pls, if (supported.contains(SearchType.mv)) mvs, if (supported.contains(SearchType.artist)) artists];
    if (all.every((b) => b.done && b.empty)) {
      return [all.every((b) => b.error != null) ? _status(songsB, SearchType.song, '内容') : EmptyState('search', '没有找到「${widget.q}」相关的内容', desc: '换个关键词，或切到其它平台试试。')];
    }
    return [
      if (songsB.note != null) Hint(songsB.note!, padding: const EdgeInsets.fromLTRB(Tk.pad, 4, Tk.pad, 0)),
      if (best != null)
        CardBox(
          margin: const EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 0),
          onTap: () => openCatalog(context, best),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Cover(hue: catalogHue(best), variant: 1, size: 64, radius: 32, url: best.cover),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('最佳匹配 · 艺术家', style: ts(11, w: FontWeight.w600, c: pal.t3, ls: .6)),
                const SizedBox(height: 2),
                Text.rich(hl(best.title, ts(18, w: FontWeight.w700, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text([if (best.subtitle.isNotEmpty) best.subtitle, if (best.trackCount != null && best.trackCount! > 0) '${best.trackCount} 首单曲', appPlatform(best.platform).name].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t2)),
              ]),
            ),
            IBtn('play', bg: pal.acc, color: pal.ink, onTap: () => openCatalog(context, best)),
          ]),
        ),
      Sec('单曲', more: '全部', onMore: () => widget.onType('歌曲')),
      if (songsB.songs.isEmpty) _status(songsB, SearchType.song, '单曲'),
      for (final id in songsB.songs.take(4)) SongRow(songs[id], list: 'all', listName: '搜索「${widget.q}」', hl: hl, queue: songsB.songs),
      if (albums.items.isNotEmpty) ...[
        Sec('专辑', more: '全部', onMore: () => widget.onType('专辑')),
        HScroll(height: 186, gap: 26, children: [for (final a in albums.items.take(6)) _AlbumCard(a, hl)]),
      ],
      if (pls.items.isNotEmpty) ...[
        Sec('歌单', more: '全部', onMore: () => widget.onType('歌单')),
        for (final p in pls.items.take(3)) CatalogRow(p, hl: hl),
      ],
      if (mvs.mvs.isNotEmpty) ...[
        Sec('MV', more: '全部', onMore: () => widget.onType('MV')),
        HScroll(height: 180, gap: 12, children: [for (final m in mvs.mvs.take(6)) _MvCard(m, w: 220)]),
      ],
      if (artists.items.length > 1) ...[
        const Sec('艺术家'),
        HScroll(height: 150, gap: 16, children: [
          for (final a in artists.items.take(8))
            Press(
              onTap: () => openCatalog(context, a),
              child: SizedBox(
                width: 96,
                child: Column(children: [
                  Cover(hue: catalogHue(a), variant: 1, size: 88, radius: 44, url: a.cover),
                  const SizedBox(height: 8),
                  Text.rich(hl(a.title, ts(13, w: FontWeight.w600, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(appPlatform(a.platform).short, style: ts(11, c: pal.t3)),
                ]),
              ),
            ),
        ]),
      ],
    ];
  }

  // ---------- 单一类型（分页） ----------
  List<Widget> _typed(BuildContext context, SearchType t, TextSpan Function(String, TextStyle) hl) {
    final app = context.app;
    _ensure(t);
    final b = _bucket(widget.plat, t);
    final q = widget.q;
    final more = b.page > 0 && b.hasMore ? AutoLoad(key: ValueKey('more${widget.plat}${t.name}${b.page}${b.error}'), onLoad: () => _load(t), busy: b.busy, error: b.error) : null;
    final out = <Widget>[if (b.note != null) Hint(b.note!, padding: const EdgeInsets.fromLTRB(Tk.pad, 4, Tk.pad, 0))];
    switch (t) {
      case SearchType.song:
        final ids = lossless ? b.songs.where((id) => !songs[id].plainQ).toList() : b.songs;
        // 音乐库里（收藏、歌单）匹配的歌，平台结果里没有的才列出
        final ql = q.toLowerCase();
        final lib = <int>{...app.liked, for (final p in app.myPlaylists) ...p.ids};
        final local = [for (final id in lib) if (id < songs.length && !b.songs.contains(id) && '${songs[id].title} ${songs[id].artist} ${songs[id].album}'.toLowerCase().contains(ql)) songs[id]].take(3).toList();
        out.addAll([
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 6),
            child: Row(children: [
              Btn('播放全部', icon: 'play', small: true, onTap: ids.isEmpty ? null : () => app.play(ids.first, name: '搜索「$q」', ids: ids)),
              const SizedBox(width: 8),
              LChip('综合排序', icon: 'sort', onTap: () => toast('按平台的默认相关度排序', 'sort')),
              const SizedBox(width: 8),
              LChip('只看无损', icon: 'hd', on: lossless, onTap: () => setState(() => lossless = !lossless)),
            ]),
          ),
          if (local.isNotEmpty) ...[
            const Sec('音乐库里', size: 16),
            for (final s in local) SongRow(s, list: 'all', listName: '搜索「$q」', hl: hl),
            const Sec('平台结果', size: 16),
          ],
          if (b.songs.isEmpty) _status(b, t, '歌曲'),
          if (b.songs.isNotEmpty && ids.isEmpty) Hint('已加载的结果里没有无损音质的歌', padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0)),
          for (final id in ids) SongRow(songs[id], key: ValueKey('s$id'), list: 'all', listName: '搜索「$q」', hl: hl, queue: ids),
        ]);
      case SearchType.playlist:
        out.addAll([if (b.items.isEmpty) _status(b, t, '歌单'), for (final c in b.items) CatalogRow(c, key: ValueKey('c${c.platform}${c.id}'), hl: hl)]);
      case SearchType.album:
        out.add(b.items.isEmpty
            ? _status(b, t, '专辑')
            : Padding(
                padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
                child: Wrap(spacing: 10, runSpacing: 16, children: [for (final a in b.items) _AlbumCard(a, hl, size: 140)]),
              ));
      case SearchType.artist:
        out.addAll([
          if (b.items.isEmpty) _status(b, t, '艺术家'),
          for (final a in b.items)
            Item(
              key: ValueKey('a${a.platform}${a.id}'),
              lead: Cover(hue: catalogHue(a), variant: 1, size: 48, radius: 24, url: a.cover),
              label: a.title,
              sub: [if (a.subtitle.isNotEmpty) a.subtitle, appPlatform(a.platform).name].join(' · '),
              onTap: () => openCatalog(context, a),
              trailing: Btn.sec('主页', small: true, onTap: () => openCatalog(context, a)),
            ),
        ]);
      case SearchType.mv:
        out.add(b.mvs.isEmpty
            ? _status(b, t, 'MV')
            : Padding(
                padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
                child: LayoutBuilder(builder: (c, cs) {
                  final w = (cs.maxWidth - 12) / 2;
                  return Wrap(spacing: 12, runSpacing: 14, children: [for (final m in b.mvs) _MvCard(m, w: w)]);
                }),
              ));
    }
    if (more != null) out.add(more);
    return out;
  }
}

/// 专辑卡（原型 _AlbumR：封面后露出唱片）。
class _AlbumCard extends StatelessWidget {
  final CatalogItem a;
  final TextSpan Function(String, TextStyle) hl;
  final double size;
  const _AlbumCard(this.a, this.hl, {this.size = 130});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final sub = [if (a.creator?.isNotEmpty == true) a.creator!, if (a.date?.isNotEmpty == true) a.date!.length > 4 ? a.date!.substring(0, 4) : a.date!].join(' · ');
    return Press(
      onTap: () => openCatalog(context, a),
      child: SizedBox(
        width: size + 14,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: size,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 14, top: 4, child: Container(width: size - 8, height: size - 8, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0D0E12), border: Border.all(color: const Color(0xFF26282F), width: 6)))),
              Cover(hue: catalogHue(a), variant: a.id.hashCode.abs() % 6, size: size, radius: 12, shadow: true, url: a.cover),
            ]),
          ),
          const SizedBox(height: 8),
          Text.rich(hl(a.title, ts(13, w: FontWeight.w600, c: pal.t1)), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(sub.isEmpty ? appPlatform(a.platform).short : sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t3)),
        ]),
      ),
    );
  }
}

/// MV 卡（原型 MvCard 的真实数据版）。MV 播放还没接入，点开只提示。
class _MvCard extends StatelessWidget {
  final PTrack m;
  final double w;
  const _MvCard(this.m, {this.w = 236});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Press(
      onTap: () => toast('MV 播放还没有接入', 'video'),
      child: SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover(
            hue: (m.id.hashCode.abs() % 360).toDouble(),
            variant: 1,
            width: w,
            height: w * 9 / 16,
            radius: 14,
            url: m.cover,
            child: Stack(children: [
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Color(0xE6FFFFFF), size: 36)),
              if (m.duration > 0) Positioned(right: 6, bottom: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(6)), child: Text(fmtTime(m.duration.toDouble()), style: ts(10.5, c: Colors.white, num: true)))),
            ]),
          ),
          const SizedBox(height: 6),
          Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
          Text(m.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t3)),
        ]),
      ),
    );
  }
}
