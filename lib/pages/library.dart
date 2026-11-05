// 音乐库：我喜欢 · 最近 · 歌单 · 本地（A–Z 索引条 + 气泡）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/listening_stats.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../shell/shell.dart';
import '../sync/cloud_models.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';
import 'common.dart';
import 'detail.dart';
import 'misc.dart' show DownloadPage;

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String filter = '全部', dim = '歌曲';
  String? letter;
  double letterY = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final seg = app.libSeg;
    final body = <Widget>[];
    final online = app.online;
    final syncSt = online ? app.cloud.status?.value : null;
    final synced = !online || (app.isSponsor && app.set.cloudSync);
    if (seg == '我喜欢') {
      body.addAll([
        CardBox(
          margin: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 0),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.acc.withValues(alpha: .28), pal.s1]),
          child: Row(children: [
            Container(width: 60, height: 60, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [pal.acc, Color.lerp(pal.acc, Colors.black, .4)!])), child: Icon(ic('heartf'), color: pal.ink, size: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('我喜欢的音乐', style: ts(17, w: FontWeight.w700, c: pal.t1)),
                const SizedBox(height: 3),
                Row(children: [
                  CountUp(app.liked.length.toDouble(), style: ts(12.5, c: pal.t2, num: true)),
                  Text(' 首 · ', style: ts(12.5, c: pal.t2)),
                  Icon(ic(synced ? 'cloud' : 'device'), size: 13, color: synced ? pal.ok : pal.t3),
                  Text(synced ? ' 云同步' : ' 仅本机', style: ts(12.5, c: synced ? pal.ok : pal.t3)),
                  if (!online) Text(' · 刚刚', style: ts(12.5, c: pal.t2)) else if (synced && syncSt?.lastSyncAt != null) Text(' · ${_ago(syncSt!.lastSyncAt!)}', style: ts(12.5, c: pal.t2)),
                ]),
              ]),
            ),
            Press(onTap: () => app.playAll('like', name: '我喜欢的音乐'), scale: .9, child: Container(width: 48, height: 48, decoration: BoxDecoration(color: pal.acc, shape: BoxShape.circle), child: Icon(ic('play'), color: pal.ink))),
          ]),
        ),
        if (!online)
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 4), children: [
              for (final f in const ['全部', '已下载', 'Hi-Res']) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(f, on: filter == f, onTap: () => setState(() => filter = f))),
              LChip('最近添加', icon: 'sort', onTap: () => toast('排序：最近添加', 'sort')),
            ]),
          )
        else
          const SizedBox(height: 10),
        for (final id in app.liked.where((id) => id < songs.length).where((id) => filter != 'Hi-Res' || songs[id].quality == 'Hi-Res').where((id) => online || filter != '已下载' || id % 2 == 0))
          SongRow(songs[id], key: ValueKey('l$id'), list: 'like', listName: '我喜欢的音乐', heart: true),
        if (app.liked.isEmpty)
          online
              ? EmptyState('heart', '还没有收藏的歌曲', desc: app.isSponsor ? '开启「备份与同步 → 多端实时同步」后，桌面端的收藏会同步到这里。' : '赞助用户可以把桌面端的收藏同步到这里。平台搜索接入后也能直接在手机上收藏。')
              : const Hint('还没有收藏的歌曲，点歌曲旁的 ♡ 收藏', align: TextAlign.center, padding: EdgeInsets.all(30)),
      ]);
    } else if (seg == '最近' && online) {
      // 真实播放记录：本机听歌统计（last = 最近一次完整听完的时间）按时间倒序，分今天 / 昨天 / 更早。
      // 云端同步来的统计里可能有本目录没有的歌（其它设备播的）——用统计里的元数据注册进目录，
      // 之后可以直接点播（走音源解析）；目录里已有的（本机播过的）保持原样不覆盖封面。
      final entries = [for (final s in app.cloud.stats.songs.values) if (!s.isMock && s.last != null) s]
        ..sort((a, b) => b.last!.compareTo(a.last!));
      if (entries.isEmpty) {
        body.add(const EmptyState('history', '还没有播放记录', desc: '完整听过一首歌后，它会按时间出现在这里。'));
      } else {
        final today = ListeningStats.dayKey(DateTime.now());
        final yesterday = ListeningStats.dayKey(DateTime.now().subtract(const Duration(days: 1)));
        final groups = <String, List<SongStat>>{'今天': [], '昨天': [], '更早': []};
        for (final s in entries) {
          final k = ListeningStats.dayKey(s.last!);
          groups[k == today ? '今天' : k == yesterday ? '昨天' : '更早']!.add(s);
        }
        for (final g in groups.entries) {
          final title = g.key;
          final list = g.value;
          if (list.isEmpty) continue;
          body.add(Padding(padding: const EdgeInsets.fromLTRB(Tk.pad, 18, 0, 4), child: Text(title, style: ts(12.5, w: FontWeight.w600, c: pal.t3))));
          for (final st in list) {
            final id = app.library.idOfKey(st.key) ?? app.library.register(CloudTrack(
                  id: st.key,
                  platform: st.source,
                  songId: st.songId,
                  title: st.name.isEmpty ? '未知歌曲' : st.name,
                  artist: st.artist,
                  album: st.album,
                  durationSec: st.durationSec,
                ));
            if (id >= songs.length) continue; // 注册失败等异常情况，跳过不渲染
            body.add(SongRow(songs[id], list: 'all', listName: '最近播放'));
          }
        }
      }
    } else if (seg == '最近') {
      for (final (g, ids) in [('今天', [app.cur, 5, 11, 2]), ('昨天', [7, 16, 18, 20, 9]), ('更早', [3, 14, 22])]) {
        body.add(Padding(padding: const EdgeInsets.fromLTRB(Tk.pad, 18, 0, 4), child: Text(g, style: ts(12.5, w: FontWeight.w600, c: pal.t3))));
        for (final id in ids.toSet()) {
          body.add(SongRow(songs[id], list: 'all'));
        }
      }
    } else if (seg == '歌单') {
      if (online) {
        body.add(Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 0),
          child: Row(children: [
            Expanded(child: Btn.sec('新建歌单', icon: 'plus', onTap: () => openNewPlaylist(context))),
            const SizedBox(width: 10),
            Expanded(child: Btn.sec('导入平台歌单', icon: 'link', onTap: () => openImportPlaylist(context))),
          ]),
        ));
      }
      body.add(Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 16, Tk.pad, 0),
        child: LayoutBuilder(builder: (c, cs) {
          final w = (cs.maxWidth - 12) / 2;
          return Wrap(spacing: 12, runSpacing: 16, children: [
            for (final pl in app.myPlaylists) PlCard(pl, w: w, sub: '${pl.isReal && pl.kind == 'created' ? pl.ids.length : pl.count} 首${pl.tag != null ? ' · ${pl.tag}' : ''}', onTap: () => push(context, PlaylistPage(id: pl.id))),
          ]);
        }),
      ));
      if (online && app.myPlaylists.isEmpty) body.add(EmptyState('queue', '还没有歌单', desc: '新建歌单，或粘贴网易云 / QQ / 酷狗 / 酷我 / 咪咕的歌单链接导入；赞助用户开启云同步后，桌面端的歌单也会出现在这里。'));
    } else if (online) {
      body.add(const EmptyState('folder', '本地音乐扫描接入中', desc: '读取手机里的音乐文件需要接入媒体库扫描和本地播放，正在开发。'));
    } else {
      final ids = app.listOf('local');
      body.addAll([
        CardBox(
          margin: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(12)), child: Icon(ic('folder'), color: pal.accText)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('本地 ${ids.length} 首 · 3.2 GB', style: ts(14.5, w: FontWeight.w600, c: pal.t1)),
                Text('/Music · /Download · 上次扫描 2 小时前', style: ts(12, c: pal.t3)),
              ]),
            ),
            Btn.sec('扫描', small: true, onTap: () => toast('扫描完成，新增 3 首，修复 2 个乱码标签', 'refresh')),
          ]),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 4), children: [
            for (final f in const ['歌曲', '歌手', '专辑', '文件夹']) Padding(padding: const EdgeInsets.only(right: 8), child: LChip(f, on: dim == f, onTap: () => setState(() => dim = f))),
          ]),
        ),
        if (dim == '歌曲')
          for (final id in ids) Padding(padding: const EdgeInsets.only(right: 18), child: SongRow(songs[id], list: 'local', listName: '本地音乐', ctx: 'local'))
        else
          for (final (i, n) in (dim == '歌手' ? songs.map((s) => s.artist).toSet().toList() : dim == '专辑' ? songs.map((s) => s.album).toSet().toList() : const ['/Music', '/Download', '/Music/Live', '/Recordings']).indexed)
            Item(
              lead: Container(width: 44, height: 44, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(dim == '歌手' ? 22 : 10)), child: Icon(ic(dim == '歌手' ? 'user' : dim == '专辑' ? 'album' : 'folder'), color: pal.t2)),
              label: n,
              sub: '${3 + i % 4} 首',
              onTap: () => toast('打开 $n', 'folder'),
            ),
      ]);
    }
    return Stack(children: [
      TabPage(
        title: '音乐库',
        controller: tabScroll[3],
        actions: [
          IBtn('chart', onTap: () => push(context, const StatsPage())),
          IBtn('download', onTap: () => online ? push(context, const DownloadPage()) : openImportPlaylist(context)), // 联网：下载管理
          IBtn('plus', onTap: () => openNewPlaylist(context)),
        ],
        children: [
          Seg(const ['我喜欢', '歌单', '最近', '本地'], seg, (v) => app.update(() => app.libSeg = v)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Column(key: ValueKey(seg), crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, w) in body.indexed) i < 14 ? Rise(i, w) : w]),
          ),
        ],
      ),
      if (seg == '本地' && dim == '歌曲' && !app.online) _azBar(context),
    ]);
  }

  Widget _azBar(BuildContext context) {
    final pal = context.pal;
    const letters = '★ABCDEFGHJKLMNPQSTWXYZ#';
    final top = MediaQuery.of(context).padding.top + 190;
    const h = 23 * 15.0;
    void pick(double dy) {
      final i = (dy / h * letters.length).floor().clamp(0, letters.length - 1);
      final l = letters[i];
      if (l != letter) {
        HapticFeedback.selectionClick();
        setState(() {
          letter = l;
          letterY = dy;
        });
        final c = tabScroll[3];
        if (c.positions.length == 1) c.jumpTo((280 + i * 64.0 * songs.length / letters.length).clamp(0, c.position.maxScrollExtent));
      }
    }

    return Positioned(
      right: 0,
      top: top,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedOpacity(
          duration: Tk.fast,
          opacity: letter == null ? 0 : 1,
          child: Padding(
            padding: EdgeInsets.only(top: (letterY - 32).clamp(0, h - 64)),
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: pal.acc, borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), bottomLeft: Radius.circular(32), topRight: Radius.circular(32), bottomRight: Radius.circular(4))),
              child: Text(letter ?? '', style: ts(28, w: FontWeight.w800, c: pal.ink)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onVerticalDragStart: (d) => pick(d.localPosition.dy),
          onVerticalDragUpdate: (d) => pick(d.localPosition.dy),
          onVerticalDragEnd: (_) => Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => letter = null);
          }),
          onTapDown: (d) => pick(d.localPosition.dy),
          onTapUp: (_) => Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => letter = null);
          }),
          child: SizedBox(
            width: 18,
            height: h,
            child: Column(children: [
              for (final l in letters.split(''))
                Container(
                  height: 15,
                  width: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: l == letter ? pal.acc : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                  child: Text(l, style: ts(10, w: FontWeight.w700, c: l == letter ? pal.ink : pal.accText)),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 2),
      ]),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}
