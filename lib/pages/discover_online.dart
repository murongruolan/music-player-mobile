// 发现页 · 联网模式：沿用原型的结构（登录卡 + Banner · 快捷入口 · 精选 / 榜单 / 歌单 · 平台推荐区），
// 内容换成各平台未登录可用的公开数据。平台没有对应数据的区块直接不显示，不放假数据。
part of 'discover.dart';

typedef _Feed = ({DiscoverFeed feed, List<int> hot});

/// 平台推荐区要用的全部榜单和歌单分类（失败时为空，对应区块不显示）。
typedef _RecData = ({List<CatalogItem> boards, List<PlaylistCategory> cats});

class _OnlineDiscover extends StatefulWidget {
  const _OnlineDiscover();
  @override
  State<_OnlineDiscover> createState() => _OnlineDiscoverState();
}

class _OnlineDiscoverState extends State<_OnlineDiscover> {
  String? plat;
  late Future<_Feed> f;
  late Future<_RecData> rec;

  Future<_Feed> _fetch(AppState app) => app.content.discover(app.plat).then((d) => (feed: d, hot: [for (final t in d.hot) registerTrack(app, t)]));

  Future<_RecData> _fetchRec(AppState app) async {
    final c = app.content;
    final b = c.leaderboards(app.plat).catchError((Object _) => <CatalogItem>[]);
    final k = c.playlistCategories(app.plat).catchError((Object _) => <PlaylistCategory>[]);
    return (boards: await b, cats: await k);
  }

  AppState? _app;

  void _load(AppState app) {
    _app = app;
    f = _fetch(app);
    rec = _fetchRec(app);
    // 当前平台出内容后，空闲时把其他平台的发现页预载进缓存（切平台秒开）
    final mine = f;
    f.then((_) {
      if (mounted && identical(mine, f)) app.prefetch.start(app.plat);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _app?.prefetch.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    final app = context.appRead;
    app.content.invalidate(app.plat);
    clearBoardPreviews(app);
    setState(() => _load(app));
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (plat != app.plat) {
      plat = app.plat;
      _load(app);
    }
    final code = PlatformHub.codeOf(app.plat);
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
        const Padding(padding: EdgeInsets.fromLTRB(Tk.pad, 2, Tk.pad, 12), child: SourceBar()),
        FutureBuilder<_Feed>(
          key: ValueKey('feed$plat'),
          future: f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonPage();
            if (s.hasError) {
              return Column(children: [
                const _LoginStrip(),
                EmptyState('wifi', '${app.platform.name}的内容没有加载出来', desc: '${platformError(s.error!)}\n可以下拉刷新，或在上方换一个平台。', action: Btn.sec('重试', icon: 'refresh', small: true, onTap: _refresh)),
              ]);
            }
            final d = s.data!;
            final mods = <Widget>[];
            for (final m in app.homeMods) {
              if (!m.value) continue;
              switch (m.key) {
                case 'mypl':
                  if (app.myPlaylists.isNotEmpty) mods.add(const _LibPlaylists());
                case 'quick':
                  mods.add(QuickGrid([
                    // 「每日混音」指向的每日页已在底栏 tab 上，改为进入歌单广场；排行榜同理进完整榜单页
                    ('sun', '歌单广场', () => push(context, PlaylistSquarePage(platform: code))),
                    ('wave', '私人电台', () {
                      final ids = [...d.hot]..shuffle();
                      if (ids.isNotEmpty) app.play(ids.first, name: '私人电台', ids: ids);
                    }),
                    ('mic', '听歌识曲', () => pushFull(context, const ScanPage(match: true))),
                    ('chart', '排行榜', () => push(context, LeaderboardsPage(platform: code))),
                  ]));
                case 'tabs':
                  mods.add(_OnlineTabs(d.feed, d.hot, code));
                case 'platrec':
                  mods.add(_OnlinePlatRec(rec, d.feed, d.hot, code));
                // custom（为你定制）需要登录平台账号，未登录时原型里也不显示
              }
            }
            return Column(key: ValueKey('c$plat'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Rise(0, _LoginStrip()),
              const SizedBox(height: 16),
              Rise(1, _OnlineBanner(d.feed, key: ValueKey('bn$plat'))),
              for (var i = 0; i < mods.length; i++) Rise(i + 2, mods[i]),
              if (d.feed.errors.isNotEmpty) Hint('部分内容没有加载出来：${d.feed.errors.join('；')}', padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0)),
            ]);
          },
        ),
      ],
    );
  }
}

double _hueOf(CatalogItem x) => catalogHue(x);

/// Banner：飙升榜 / 新歌榜（带榜首歌曲）+ 推荐歌单第 7~10 个。
/// 精选区用的是推荐歌单前 6 个、此刻热门用的是第一个榜单，这里都避开，保证 Banner 和下面的区块不重复。
List<CatalogItem> bannerBoards(DiscoverFeed f) {
  final rest = [for (final b in f.boards) if (b.id != f.hotBoard?.id) b];
  final out = <CatalogItem>[];
  for (final keys in const [['飙升'], ['新歌', '新曲']]) {
    final b = rest.where((b) => !out.contains(b) && keys.any(b.title.contains)).firstOrNull;
    if (b != null) out.add(b);
  }
  for (final b in rest) {
    if (out.length >= 2) break;
    if (!out.contains(b)) out.add(b);
  }
  return out;
}

class _OnlineBanner extends StatefulWidget {
  final DiscoverFeed feed;
  const _OnlineBanner(this.feed, {super.key});
  @override
  State<_OnlineBanner> createState() => _OnlineBannerState();
}

class _OnlineBannerState extends State<_OnlineBanner> {
  late final boards = bannerBoards(widget.feed);
  late final Future<List<List<int>>> tops = Future.wait([for (final b in boards) _boardTracks(context.appRead, b).catchError((Object _) => <int>[])]);

  List<BannerItem> _items(List<List<int>>? top) {
    final app = context.appRead;
    return [
      for (final (i, b) in boards.indexed)
        BannerItem(
          '排行榜',
          b.title,
          switch (top?[i]) {
            [final id, ...] => '榜首 · ${songs[id].title} - ${songs[id].artist}',
            _ => b.subtitle.isNotEmpty ? b.subtitle : app.platform.name,
          },
          _hueOf(b),
          (c) => openCatalog(c, b),
          cover: b.cover,
        ),
      for (final x in widget.feed.playlists.skip(6).take(4))
        BannerItem('推荐歌单', x.title, [if (x.creator?.isNotEmpty == true) x.creator!, if (x.playCountText.isNotEmpty) '${x.playCountText}次播放'].join(' · '), _hueOf(x), (c) => openCatalog(c, x), cover: x.cover),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (boards.isEmpty && widget.feed.playlists.length <= 6) return const SizedBox.shrink();
    return FutureBuilder<List<List<int>>>(future: tops, builder: (_, s) => BannerCarousel(items: _items(s.data)));
  }
}
Future<List<int>> _boardTracks(AppState app, CatalogItem b) => boardTracks(app, b);

// ============ 我的歌单（Lyra 音乐库：自建 / 收藏） ============
class _LibPlaylists extends StatelessWidget {
  const _LibPlaylists();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final created = app.myPlaylists.where((p) => p.kind != 'collected').toList();
    final collected = app.myPlaylists.where((p) => p.kind == 'collected').toList();
    final seg = app.myPlSeg == 1 && collected.isNotEmpty ? 1 : (created.isEmpty ? 1 : 0);
    final pls = seg == 1 ? collected : created;
    final labels = ['我创建的 ${created.length}', '我收藏的 ${collected.length}'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Sec('我的歌单', more: '全部', onMore: () => app.update(() {
            app.tab = 3;
            app.libSeg = '歌单';
          })),
      Seg(labels, labels[seg], (v) => app.update(() => app.myPlSeg = v == labels[1] ? 1 : 0)),
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
                      Cover.pl(pls[i], size: 50, radius: 10),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pls[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)),
                          Text('${pls[i].kind == 'collected' ? pls[i].count : pls[i].ids.length} 首', style: ts(11.5, c: pal.t3)),
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
class _OnlineTabs extends StatelessWidget {
  final DiscoverFeed d;
  final List<int> hot;
  final String code;
  const _OnlineTabs(this.d, this.hot, this.code);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform;
    Widget body;
    if (app.homeTab == '精选') {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (d.playlists.isNotEmpty) ...[
          Sec('${p.short} · 热门歌单', more: '更多', onMore: () => app.update(() => app.homeTab = '歌单')),
          HScroll(height: 196, children: [for (final x in d.playlists.take(6)) PlCard(cardOf(x), onTap: () => openCatalog(context, x))]),
        ],
        if (hot.isNotEmpty) ...[
          Sec('热门榜单', more: '全部', onMore: () => app.update(() => app.homeTab = '榜单')),
          CardBox(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (final (i, id) in hot.take(5).indexed) SongRow(songs[id], num: i, list: 'all', listName: d.hotBoard?.title ?? '热门榜单', swipe: false, tail: HeartBtn(id), queue: hot),
            ]),
          ),
        ],
      ]);
    } else if (app.homeTab == '榜单') {
      body = Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          for (final b in d.boards.take(4)) Padding(padding: const EdgeInsets.only(bottom: 12), child: BoardBigCard(b)),
          if (d.boards.isNotEmpty) Press(onTap: () => push(context, LeaderboardsPage(platform: code)), child: Padding(padding: const EdgeInsets.all(8), child: Text('查看全部榜单', style: ts(13, w: FontWeight.w600, c: pal.accText)))),
          if (d.boards.isEmpty) EmptyState('chart', '${p.name}没有返回排行榜'),
        ]),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0),
        child: Column(children: [
          LayoutBuilder(builder: (c, cs) {
            final w = (cs.maxWidth - 14) / 2;
            return Wrap(spacing: 14, runSpacing: 16, children: [for (final x in d.playlists) PlCard(cardOf(x), w: w, onTap: () => openCatalog(context, x))]);
          }),
          Press(onTap: () => push(context, PlaylistSquarePage(platform: code)), child: Padding(padding: const EdgeInsets.all(14), child: Text('去歌单广场看更多', style: ts(13, w: FontWeight.w600, c: pal.accText)))),
        ]),
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

/// 分类匹配：名称包含任一关键词（排除「推荐 / 全部 / 最新 / 最热」这类入口）。
PlaylistCategory? _matchCat(List<PlaylistCategory> cats, List<String> keys) {
  for (final k in keys) {
    for (final c in cats) {
      if (_isEntry(c)) continue;
      if (c.name.contains(k)) return c;
    }
  }
  return null;
}

bool _isEntry(PlaylistCategory c) => const {'推荐', '全部', '全部歌单', '最新', '最热', '热门'}.contains(c.name) || c.id == 'recommend' || c.id.endsWith('::');

/// 新歌榜：名称带「新歌」的榜单，可按地区再筛。
CatalogItem? _newBoard(List<CatalogItem> boards, [List<String> region = const []]) {
  final l = boards.where((b) => b.title.contains('新歌') || b.title.contains('新曲')).toList();
  if (region.isEmpty) return l.firstOrNull;
  return l.where((b) => region.any(b.title.contains)).firstOrNull ?? boards.where((b) => region.any(b.title.contains) && !b.title.contains('飙升')).firstOrNull;
}

class _OnlinePlatRec extends StatelessWidget {
  final Future<_RecData> rec;
  final DiscoverFeed d;
  final List<int> hot;
  final String code;
  const _OnlinePlatRec(this.rec, this.d, this.hot, this.code);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform;
    return FutureBuilder<_RecData>(
      future: rec,
      builder: (c, s) {
        final r = s.data ?? (boards: d.boards, cats: const <PlaylistCategory>[]);
        final boards = r.boards.isEmpty ? d.boards : r.boards;
        final secs = <Widget>[
          for (final k in platRec[p.id]!)
            if (_sec(context, k, boards, r.cats) case final w?) w,
        ];
        if (secs.isEmpty) return const SizedBox.shrink();
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
          ...secs,
        ]);
      },
    );
  }

  Widget? _sec(BuildContext context, String k, List<CatalogItem> boards, List<PlaylistCategory> cats) {
    final app = context.app;
    final pal = context.pal;
    switch (k) {
      case 'newsongs':
        return _NewSongs(boards);
      case 'official':
        final l = boards.take(4).toList();
        if (l.isEmpty) return null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('官方榜', more: '更多', onMore: () => push(context, LeaderboardsPage(platform: code))),
          HScroll(height: 232, gap: 12, children: [for (final b in l) _OfficialCard(b)]),
        ]);
      case 'plcats':
        final l = cats.where((c) => !_isEntry(c)).take(15).toList();
        if (l.isEmpty) return null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('歌单分类', more: '全部', onMore: () => push(context, PlaylistSquarePage(platform: code))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, c) in l.indexed) Rise(i, LChip(c.name, onTap: () => push(context, PlaylistSquarePage(platform: code, category: c)))),
            ]),
          ),
        ]);
      case 'genres':
        final l = cats.where((c) => !_isEntry(c) && c.group.contains('风格')).take(6).toList();
        if (l.length < 3) return null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sec('曲风分类', more: '全部', onMore: () => push(context, PlaylistSquarePage(platform: code))),
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
                for (final (i, c) in l.indexed)
                  Press(
                    onTap: () => push(context, PlaylistSquarePage(platform: code, category: c)),
                    child: Cover(
                      hue: (c.name.hashCode.abs() % 360).toDouble(),
                      variant: i,
                      size: 0,
                      radius: 16,
                      child: Padding(padding: const EdgeInsets.all(10), child: Align(alignment: Alignment.bottomLeft, child: Text(c.name, style: ts(14, w: FontWeight.w700, c: Colors.white)))),
                    ),
                  ),
              ],
            ),
          ),
        ]);
      case 'nowlisten':
        return _NowListen(cats, hot, code);
      case 'mood':
        const moods = [
          ('开心', 40.0, '☼', ['快乐', '开心', '欢快', '愉快']),
          ('放松', 170.0, '～', ['放松', '轻松', '安静']),
          ('伤感', 220.0, '﹏', ['伤感', '悲伤', '难过']),
          ('热血', 0.0, '⚡', ['兴奋', '热血', '激情', '励志', '宣泄']),
          ('治愈', 140.0, '♡', ['治愈', '温暖']),
          ('思念', 280.0, '☾', ['思念', '想念', '孤独', '寂寞']),
        ];
        final hits = [for (final m in moods) if (_matchCat(cats, m.$4) case final c?) (m, c)];
        if (hits.length < 3) return null;
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
                for (final (i, ((n, h, g, _), c)) in hits.indexed)
                  Rise(
                    i,
                    Press(
                      onTap: () => push(context, PlaylistSquarePage(platform: code, category: c)),
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
        final b = _newBoard(boards);
        if (b == null) return null;
        return FutureBuilder<List<int>>(
          future: _boardTracks(app, b),
          builder: (c, s) {
            final ids = s.data ?? const <int>[];
            if (ids.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Sec('新鲜上架', more: '全部', onMore: () => openCatalog(context, b)),
              for (final id in ids.take(4)) SongRow(songs[id], list: 'all', listName: b.title, swipe: false, tail: HeartBtn(id), queue: ids),
            ]);
          },
        );
      // albums（新碟上架）、mvrank（MV 排行）、videos（推荐视频）：桌面端没有对应的公开接口，暂不显示
    }
    return null;
  }
}

/// 原型「官方榜」横滑卡：渐变底 + 前三首（带封面）。
class _OfficialCard extends StatelessWidget {
  final CatalogItem b;
  const _OfficialCard(this.b);
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final h = _hueOf(b);
    return Press(
      onTap: () => openCatalog(context, b),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hsl(h, .5, pal.dark ? .22 : .9), pal.s1])),
        child: FutureBuilder<List<int>>(
          future: _boardTracks(app, b),
          builder: (c, s) {
            final ids = s.data ?? const <int>[];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(17, w: FontWeight.w800, c: pal.t1))),
                if (b.subtitle.isNotEmpty) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 90), child: Text(b.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, c: pal.t3))),
              ]),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: i < ids.length
                      ? Row(children: [
                          Cover.song(songs[ids[i]], size: 40, radius: 8),
                          const SizedBox(width: 8),
                          SizedBox(width: 16, child: Text('${i + 1}', style: ts(14, w: FontWeight.w800, c: i == 0 ? pal.accText : pal.t2, num: true))),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(songs[ids[i]].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w600, c: pal.t1)), Text(songs[ids[i]].artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, c: pal.t3))])),
                        ])
                      : const Row(children: [Bone(w: 40, h: 40, r: 8), SizedBox(width: 8), Bone(w: 130, h: 13)]),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// 原型「新歌速递」：地区切换 + 3 列分页。地区按榜单名称匹配，没有对应榜单的地区不显示。
class _NewSongs extends StatefulWidget {
  final List<CatalogItem> boards;
  const _NewSongs(this.boards);
  @override
  State<_NewSongs> createState() => _NewSongsState();
}

class _NewSongsState extends State<_NewSongs> {
  String region = '华语';
  static const _regions = {
    '华语': ['华语', '内地', '国语'],
    '欧美': ['欧美', '美国', '英国', 'Billboard', 'UK'],
    '日韩': ['日本', '韩国', '日语', '韩语', '日韩', 'Oricon', 'Melon'],
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final general = _newBoard(widget.boards);
    final byRegion = <String, CatalogItem>{
      for (final e in _regions.entries)
        if ((_newBoard(widget.boards, e.value) ?? (e.key == '华语' ? general : null)) case final b?) e.key: b,
    };
    if (byRegion.isEmpty && general == null) return const SizedBox.shrink();
    if (byRegion.isEmpty) byRegion['华语'] = general!;
    if (!byRegion.containsKey(region)) region = byRegion.keys.first;
    final b = byRegion[region]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Sec('新歌速递', more: '全部', onMore: () => openCatalog(context, b)),
      if (byRegion.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 10),
          child: Row(children: [for (final r in byRegion.keys) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(r, on: r == region, h: 30, onTap: () => setState(() => region = r)))]),
        ),
      FutureBuilder<List<int>>(
        key: ValueKey(b.id),
        future: _boardTracks(app, b),
        builder: (c, s) {
          final ids = s.data ?? const <int>[];
          if (s.connectionState != ConnectionState.done) return const ListSkeleton(rows: 3);
          if (ids.isEmpty) return Hint('${b.title}暂时没有歌曲', padding: const EdgeInsets.symmetric(horizontal: Tk.pad));
          final pages = (math.min(9, ids.length) + 2) ~/ 3;
          return SizedBox(
            height: 3 * 60,
            child: PageView.builder(
              controller: PageController(viewportFraction: .88),
              padEnds: false,
              itemCount: pages,
              itemBuilder: (_, pg) => Padding(
                padding: const EdgeInsets.only(left: Tk.pad - 4),
                child: Column(children: [
                  for (var r = 0; r < 3 && pg * 3 + r < ids.length; r++)
                    Builder(builder: (_) {
                      final s = songs[ids[pg * 3 + r]];
                      return Press(
                        onTap: () => app.play(s.id, name: b.title, ids: ids),
                        child: SizedBox(
                          height: 60,
                          child: Row(children: [
                            Cover.song(s, size: 48),
                            const SizedBox(width: 10),
                            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w: FontWeight.w600, c: pal.t1)), Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t3))])),
                            Icon(Icons.play_circle_outline_rounded, color: pal.t3),
                            const SizedBox(width: 10),
                          ]),
                        ),
                      );
                    }),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}

/// 原型「适合现在听」：按时段推荐对应分类的歌单；场景标签按分类名称匹配。
class _NowListen extends StatelessWidget {
  final List<PlaylistCategory> cats;
  final List<int> hot;
  final String code;
  const _NowListen(this.cats, this.hot, this.code);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hr = now.hour;
    final slot = hr < 6
        ? ('深夜', '安静的夜', ['深夜', '夜晚', '睡前', '安静'])
        : hr < 11
            ? ('早晨', '清醒一下', ['清晨', '早晨', '早安', '清新'])
            : hr < 14
                ? ('午间', '午休小憩', ['午休', '午后', '咖啡', '轻音乐'])
                : hr < 18
                    ? ('下午', '适合专注', ['学习', '工作', '下午茶', '专注'])
                    : hr < 22
                        ? ('傍晚', '下班路上', ['驾车', '旅行', '散步', '运动'])
                        : ('夜晚', '睡前放松', ['夜晚', '睡前', '深夜', '安静']);
    final slotCat = _matchCat(cats, slot.$3);
    const scenes = [('通勤', ['通勤', '地铁', '路上']), ('学习', ['学习', '工作']), ('运动', ['运动', '健身', '跑步']), ('开车', ['驾车', '开车', '车载']), ('睡前', ['睡前', '助眠', '夜晚']), ('下午茶', ['下午茶', '咖啡'])];
    final chips = [for (final (n, keys) in scenes) if (_matchCat(cats, keys) case final c?) (n, c)];
    if (slotCat == null && chips.isEmpty) return const SizedBox.shrink();
    final covers = hot.take(4).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Sec('适合现在听', more: slotCat?.name, onMore: slotCat == null ? null : () => push(context, PlaylistSquarePage(platform: code, category: slotCat))),
      CardBox(
        padding: EdgeInsets.zero,
        onTap: () => push(context, PlaylistSquarePage(platform: code, category: slotCat)),
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
                  Text(slotCat == null ? '按时段挑的歌单' : '「${slotCat.name}」分类的歌单', style: ts(12, c: const Color(0xB3FFFFFF))),
                ]),
              ),
              if (covers.isNotEmpty)
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(children: [for (var i = 0; i < covers.length; i++) Positioned(left: (i % 2) * 40.0 + (i ~/ 2) * 8, top: (i ~/ 2) * 40.0, child: Transform.rotate(angle: (i - 1.5) * .1, child: Cover.song(songs[covers[i]], size: 48, radius: 9, shadow: true)))]),
                ),
            ]),
          ),
        ),
      ),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [for (final (n, c) in chips) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(n, onTap: () => push(context, PlaylistSquarePage(platform: code, category: c))))])),
      ],
    ]);
  }
}
