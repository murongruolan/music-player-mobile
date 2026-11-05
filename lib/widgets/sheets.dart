// 所有 Bottom Sheet 与表单弹窗：歌曲更多、加入歌单、新建 / 导入歌单、平台登录、分享口令、
// 睡眠定时、均衡器、音质、倍速、投放、皮肤与背景、歌词快调、歌词分享卡、播放链路、播放队列、底栏样式、App 图标、字体。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../cast/dlna.dart';
import '../source/music_resolver.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../pages/detail.dart';
import '../pages/radio.dart' show isRadioQueue;
import '../pages/settings.dart';
import '../shell/shell.dart';
import '../ui/brand.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/custom_font.dart';
import 'plat_login.dart';

void registerSheets() {
  onSongMore = openSongMore;
}

// ============ 歌曲更多 ============
void openSongMore(BuildContext context, int id, String ctx, {bool dark = false}) {
  final s = context.appRead.songById(id);
  showLSheet(context, title: '歌曲', dark: dark, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    void close() => Navigator.of(c).pop();
    final dlTrack = app.online ? app.library.trackOf(id) : null;
    final downloaded = dlTrack != null && app.downloads.isDownloaded(dlTrack.id);
    // 联网模式：取流 / 下载 / 歌词 / 投放都依赖音源解析，先只保留真正能用的操作
    final onlineGrid = [
      ('plus', '加入歌单', () {
        close();
        openAddToPlaylist(context, id);
      }),
      ('copy', '复制歌名', () {
        close();
        Clipboard.setData(ClipboardData(text: '${s.title} - ${s.artist}'));
        toast('已复制「${s.title} - ${s.artist}」', 'copy');
      }),
      ('download', '下载', () {
        close();
        unawaited(app.downloads.enqueue(s));
        toast('已加入下载队列', 'download');
      }),
    ];
    final grid = app.online ? onlineGrid : [
      ('next', '下一首播放', () {
        app.playNext(id);
        close();
        toast('下一首播放：${s.title}', 'next');
      }),
      ('plus', '加入歌单', () {
        close();
        openAddToPlaylist(context, id);
      }),
      ('download', '下载', () {
        close();
        toast('已加入下载 · ${app.set.dlQ}', 'download');
      }),
      ('share', '分享口令', () {
        close();
        openShareCode(context, songId: id);
      }),
      ('quote', '歌词分享', () {
        close();
        openLyricCard(context);
      }),
      ('hd', '音质', () {
        close();
        openQuality(context);
      }),
      ('speed', '倍速', () {
        close();
        openSpeed(context);
      }),
      ('cast', '投放', () {
        close();
        openCast(context);
      }),
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 4, 10, 10),
        child: Row(children: [
          Cover.song(s, size: 52, radius: 12),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(16, w: FontWeight.w700, c: pal.t1)), const SizedBox(height: 3), Row(children: [QBadge(s.quality), const SizedBox(width: 6), Text('${s.artist} · ${s.album}', style: ts(12.5, c: pal.t2))])])),
          HeartBtn(id),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.05,
          children: [
            for (final (i, l, f) in grid)
              Press(
                onTap: f,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(16)), child: Icon(ic(i), color: pal.t1)),
                  const SizedBox(height: 6),
                  Text(l, style: ts(12, c: pal.t2)),
                ]),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (app.online)
        Group(children: [
          Item(icon: 'user', color: 'blue', label: '查看歌手', val: s.artist, onTap: () {
            close();
            push(context, ArtistPage(id: id));
          }),
          // 电台里的歌：不感兴趣 = 从队列拿掉，以后的电台也不再放（记在本机）
          if (isRadioQueue(app) && app.queue.contains(id))
            Item(icon: 'nodislike', color: 'gray', label: '不感兴趣', sub: '从电台移除，以后的电台不再放这首', onTap: () {
              close();
              app.dislike(id);
              toast('已从电台移除', 'nodislike');
            }),
          if (s.key != null) Item(icon: 'info', color: 'gray', label: '来源', val: s.key, chev: false),
        ])
      else
      Group(children: [
        Item(icon: 'album', color: 'violet', label: '查看专辑', val: s.album, onTap: () {
          close();
          push(context, PlaylistPage(id: id % 8, chartName: s.album));
        }),
        Item(icon: 'user', color: 'blue', label: '查看歌手', val: s.artist, onTap: () {
          close();
          push(context, ArtistPage(id: id));
        }),
        Item(icon: 'layers', color: 'teal', label: '播放链路', sub: '查看每次取流尝试', onTap: () {
          close();
          openTrace(context);
        }),
        if (ctx == 'daily')
          Item(icon: 'nodislike', color: 'gray', label: '不感兴趣', sub: '减少推荐相似歌曲', onTap: () {
            close();
            app.dislike(id);
            toast('已移除，以后的推荐和电台不再放这首', 'nodislike');
          }),
        // 联网模式：已下载的歌可以删掉本地文件（真删除，下载记录一起去掉）
        if (downloaded)
          Item(icon: 'trash', color: 'red', label: '删除已下载的文件', danger: true, onTap: () {
            close();
            final it = app.downloads.items.firstWhere((x) => x.key == dlTrack.id);
            showLDialog(context, icon: 'trash', iconColor: pal.danger, title: '删除下载的文件？', body: '「${s.title}」的本地文件会被删除，之后在线播放不受影响。', actions: [
              ('取消', BtnKind.sec, null),
              ('删除', BtnKind.danger, () async {
                await app.downloads.remove(it);
                toast('已删除下载的文件', 'trash');
              }),
            ]);
          }),
        if (ctx == 'local' && !app.online)
          Item(icon: 'trash', color: 'red', label: '从设备删除', danger: true, onTap: () {
            close();
            showLDialog(context, icon: 'trash', iconColor: pal.danger, title: '从设备删除？', body: '「${s.title}」的音频文件会被永久删除，此操作不可撤销。', actions: [('取消', BtnKind.sec, null), ('删除', BtnKind.danger, () => toast('已删除', 'trash'))]);
          }),
      ]),
    ]);
  });
}

// ============ 加入歌单 / 新建歌单 ============
/// 加入歌单。[ids] 给了就批量加（多选），否则只加 [id]。
void openAddToPlaylist(BuildContext context, int id, {List<int>? ids}) {
  final all = ids ?? [id];
  showLSheet(context, title: all.length > 1 ? '加入歌单 · ${all.length} 首' : '加入歌单', builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Column(children: [
      Item(lead: Container(width: 48, height: 48, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(10)), child: Icon(ic('plus'), color: pal.accText)), label: '新建歌单', onTap: () {
        Navigator.of(c).pop();
        openNewPlaylist(context);
      }),
      for (final p in app.myPlaylists.where((p) => !app.online || p.kind == 'created'))
        Item(lead: Cover.pl(p, size: 48, radius: 10), label: p.title, sub: '${app.online ? p.ids.length : p.count} 首', onTap: () {
          Navigator.of(c).pop();
          if (app.online) {
            final n = app.library.addToPlaylist(p.id, all);
            if (all.length == 1) {
              toast(n > 0 ? '已加入「${p.title}」' : '「${p.title}」里已经有这首歌了', n > 0 ? 'check' : 'info');
            } else {
              toast(n == 0 ? '选中的歌「${p.title}」里都有了' : '已加入 $n 首到「${p.title}」${n < all.length ? '（${all.length - n} 首已在歌单里）' : ''}', n > 0 ? 'check' : 'info');
            }
            return;
          }
          toast('已加入「${p.title}」', 'check');
        }),
    ]);
  });
}

void openNewPlaylist(BuildContext context) {
  final tc = TextEditingController();
  var private = false;
  var hue = 200.0;
  showLSheet(context, title: '新建歌单', builder: (c) => StatefulBuilder(builder: (c, set) {
        final app = c.app;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            Row(children: [
              Press(onTap: () => set(() => hue = (hue + 67) % 360), child: Cover(hue: hue, variant: 2, size: 88, radius: 18, child: const Center(child: Icon(Icons.photo_camera_outlined, color: Colors.white)))),
              const SizedBox(width: 14),
              Expanded(child: LField(controller: tc, label: '歌单名称', icon: 'edit', autofocus: true)),
            ]),
            const SizedBox(height: 10),
            if (!app.online) Item(icon: 'lock', color: 'gray', label: '设为私密', sub: '仅自己可见', sw: private, onSw: (v) => set(() => private = v)),
            const SizedBox(height: 10),
            Btn('创建', block: true, onTap: () {
              final name = tc.text.trim().isEmpty ? '新建歌单' : tc.text.trim();
              if (app.online) {
                app.library.createPlaylist(name, hue);
              } else {
                app.update(() => app.myPlaylists.add(Playlist(200 + app.myPlaylists.length, name, count: 0, hue: hue, variant: 2, mine: true)));
              }
              Navigator.of(c).pop();
              toast('已创建「$name」', 'check');
            }),
          ]),
        );
      }));
}

// ============ 导入歌单：识别平台 → 解析 → 确认 ============
void openImportPlaylist(BuildContext context) {
  if (context.appRead.online) return openPendingFeature(context, '导入平台歌单', '解析网易云 / QQ / 酷狗等平台的歌单链接需要接入平台接口，正在开发。');
  final tc = TextEditingController();
  var pid = 'netease';
  var stage = 0; // 0 输入 1 解析中 2 确认
  var recognized = false;
  var sync = true;
  showLSheet(context, title: '导入歌单', sub: '平台链接 · ID', builder: (c) => StatefulBuilder(builder: (c, set) {
        final pal = c.pal;
        final app = c.app;
        void detect(String v) {
          final m = {'163': 'netease', 'music.qq': 'qq', 'kugou': 'kugou', 'kuwo': 'kuwo', 'migu': 'migu'};
          for (final e in m.entries) {
            if (v.contains(e.key)) {
              set(() {
                pid = e.value;
                recognized = true;
              });
              return;
            }
          }
          set(() => recognized = false);
        }

        if (stage == 1) {
          return SizedBox(height: 220, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: pal.acc), const SizedBox(height: 16), Text('正在解析 ${platformBy(pid).name} 歌单…', style: ts(14, c: pal.t2))]));
        }
        if (stage == 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Column(children: [
              Row(children: [
                Cover.pl(playlists[0], size: 88, radius: 16),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(playlists[0].title, style: ts(16, w: FontWeight.w700, c: pal.t1)),
                    const SizedBox(height: 4),
                    Row(children: [PlatBadge(platformBy(pid), size: 16), const SizedBox(width: 5), Text(platformBy(pid).name, style: ts(12.5, c: pal.t2))]),
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [TextSpan(text: '42 首中 '), TextSpan(text: '40 首可播', style: TextStyle(color: pal.ok, fontWeight: FontWeight.w700)), const TextSpan(text: '，2 首暂无音源')]), style: ts(12.5, c: pal.t2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Item(icon: 'refresh', color: 'teal', label: '保持与原歌单同步', sub: '原歌单更新时自动同步新增歌曲', sw: sync, onSw: (v) => set(() => sync = v)),
              const SizedBox(height: 10),
              Btn('导入到音乐库', block: true, onTap: () {
                app.update(() => app.myPlaylists.add(Playlist(300 + app.myPlaylists.length, playlists[0].title, count: 40, hue: playlists[0].hue, variant: playlists[0].variant, mine: true, tag: '导入')));
                Navigator.of(c).pop();
                toast('已导入 40 首到「歌单」', 'download');
              }),
            ]),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final p in platforms)
                Press(
                  onTap: () => set(() => pid = p.id),
                  child: Column(children: [
                    AnimatedContainer(
                      duration: Tk.base,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pid == p.id ? pal.acc : Colors.transparent, width: 2)),
                      child: AnimatedScale(scale: pid == p.id ? 1.08 : 1, duration: Tk.base, curve: Tk.spring, child: PlatBadge(p, size: 44, dim: pid != p.id)),
                    ),
                    const SizedBox(height: 4),
                    Text(p.short, style: ts(11.5, c: pid == p.id ? pal.t1 : pal.t3)),
                  ]),
                ),
            ]),
            const SizedBox(height: 16),
            LField(controller: tc, label: '歌单链接或 ID', icon: 'link', onChanged: detect, ok: recognized),
            AnimatedSize(
              duration: Tk.base,
              child: recognized ? Padding(padding: const EdgeInsets.only(top: 8, left: 4), child: Text('已识别为 ${platformBy(pid).name} 歌单链接', style: ts(12, c: pal.ok))) : const SizedBox(),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Btn.sec('取消', onTap: () => Navigator.of(c).pop())),
              const SizedBox(width: 10),
              Expanded(child: Btn.sec('粘贴', icon: 'paste', onTap: () async {
                final d = await Clipboard.getData('text/plain');
                tc.text = (d?.text?.isNotEmpty ?? false) ? d!.text! : 'https://music.163.com/playlist?id=7741029';
                detect(tc.text);
              })),
              const SizedBox(width: 10),
              Expanded(child: Btn('确认导入', onTap: () async {
                if (tc.text.trim().isEmpty) {
                  toast('请先粘贴歌单链接或输入 ID', 'info');
                  return;
                }
                set(() => stage = 1);
                await Future.delayed(const Duration(milliseconds: 1200));
                set(() => stage = 2);
              })),
            ]),
          ]),
        );
      }));
}

// ============ 平台登录：扫码 / 手机号 / Cookie ============
void openPlatLogin(BuildContext context, String pid, {String mode = '扫码'}) {
  final p = platformBy(pid);
  if (context.appRead.online) return openRealPlatLogin(context, pid, mode: mode); // 真实登录：plat_login.dart
  var m = mode;
  var st = 0; // 0 等待 1 已扫码 2 成功
  Timer? t1, t2;
  showLSheet(context, title: '登录${p.name}', builder: (c) => StatefulBuilder(builder: (c, set) {
        final pal = c.pal;
        final app = c.app;
        if (m == '扫码' && st == 0 && t1 == null) {
          t1 = Timer(const Duration(milliseconds: 2400), () {
            if (!c.mounted) return;
            set(() => st = 1);
            t2 = Timer(const Duration(milliseconds: 1600), () {
              if (!c.mounted) return;
              set(() => st = 2);
              Timer(const Duration(milliseconds: 900), () {
                app.login(pid, pid == 'netease' ? '小栗子' : '阿栗');
                if (c.mounted) Navigator.of(c).pop();
                toast('${p.name} 登录成功，正在同步', 'check');
                app.reload();
              });
            });
          });
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            Seg(const ['扫码', '手机号', 'Cookie'], m, (v) => set(() {
                  m = v;
                  t1?.cancel();
                  t2?.cancel();
                }), margin: EdgeInsets.zero),
            const SizedBox(height: 18),
            if (m == '扫码') ...[
              _QrBox(p: p, state: st),
              const SizedBox(height: 14),
              Text(st == 0 ? '打开${p.name} App，扫一扫登录' : st == 1 ? '已扫码，请在手机上确认' : '登录成功，正在同步', style: ts(14, w: FontWeight.w600, c: st == 2 ? pal.ok : pal.t1)),
              const SizedBox(height: 4),
              Text('登录信息只保存在本机', style: ts(12, c: pal.t3)),
            ] else if (m == '手机号') ...[
              const LField(label: '手机号', icon: 'phone', keyboard: TextInputType.phone),
              const SizedBox(height: 10),
              const LField(label: '短信验证码', icon: 'key', suffix: '获取'),
              const SizedBox(height: 16),
              Btn('登录', block: true, bg: Color(p.c1), fg: Colors.white, onTap: () {
                app.login(pid, '阿栗');
                Navigator.of(c).pop();
                toast('${p.name} 登录成功', 'check');
                app.reload();
              }),
            ] else ...[
              const LField(label: '粘贴 Cookie（MUSIC_U=…）', icon: 'code', lines: 4),
              const SizedBox(height: 8),
              Hint('Cookie 只保存在本机钥匙串，用于以你的身份请求该平台接口。', padding: EdgeInsets.zero),
              const SizedBox(height: 14),
              Btn('验证并登录', block: true, onTap: () {
                app.login(pid, '阿栗');
                Navigator.of(c).pop();
                toast('Cookie 有效，已登录', 'check');
                app.reload();
              }),
            ],
          ]),
        );
      })).whenComplete(() {
    t1?.cancel();
    t2?.cancel();
  });
}

class _QrBox extends StatefulWidget {
  final Platform p;
  final int state;
  const _QrBox({required this.p, required this.state});
  @override
  State<_QrBox> createState() => _QrBoxState();
}

class _QrBoxState extends State<_QrBox> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: 210,
      height: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Stack(alignment: Alignment.center, children: [
        AnimatedOpacity(duration: Tk.base, opacity: widget.state == 0 ? 1 : .25, child: const CustomPaint(size: Size(182, 182), painter: QrPainter(41))),
        if (widget.state == 0)
          AnimatedBuilder(
            animation: c,
            builder: (_, __) => Positioned(top: 182 * c.value, left: 0, right: 0, child: Container(height: 2, decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(widget.p.c1), blurRadius: 10)], color: Color(widget.p.c1)))),
          ),
        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: PlatBadge(widget.p, size: 38)),
        if (widget.state > 0) Icon(widget.state == 1 ? Icons.phonelink_ring_rounded : Icons.check_circle_rounded, size: 56, color: widget.state == 2 ? pal.ok : const Color(0xFF333333)),
      ]),
    );
  }
}

/// 伪二维码（按种子生成，三个定位角）。
class QrPainter extends CustomPainter {
  final int seed;
  final Color color;
  const QrPainter(this.seed, {this.color = const Color(0xFF111111)});
  @override
  void paint(Canvas canvas, Size s) {
    const n = 25;
    final cell = s.width / n;
    final r = math.Random(seed);
    final p = Paint()..color = color;
    bool finder(int x, int y) => (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) continue;
        if (r.nextDouble() < .48) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .3, cell + .3), p);
      }
    }
    for (final o in [Offset.zero, Offset((n - 7) * cell, 0), Offset(0, (n - 7) * cell)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(o & Size(cell * 7, cell * 7), Radius.circular(cell * 1.6)), p);
      canvas.drawRRect(RRect.fromRectAndRadius((o + Offset(cell, cell)) & Size(cell * 5, cell * 5), Radius.circular(cell)), Paint()..color = Colors.white);
      canvas.drawRRect(RRect.fromRectAndRadius((o + Offset(cell * 2, cell * 2)) & Size(cell * 3, cell * 3), Radius.circular(cell * .8)), p);
    }
  }

  @override
  bool shouldRepaint(QrPainter o) => false;
}

// ============ 分享口令 ============
void openShareCode(BuildContext context, {int? songId, String? playlistTitle, bool dark = false}) {
  if (context.appRead.online) return openPendingFeature(context, '分享口令', '分享口令需要服务端生成可被其它设备识别的歌曲 / 歌单链接，目前后端还没有对应接口。');
  final s = songs[songId ?? context.appRead.cur];
  final code = playlistTitle != null ? '【Lyra歌单·7741029】「$playlistTitle」复制这段话，打开 Lyra 即可收听' : '【Lyra歌曲·${s.id + 1}·${s.title}】${s.artist} · 复制这段话，打开 Lyra 即可收听';
  showLSheet(context, title: '分享口令', dark: dark, builder: (c) {
    final pal = c.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.acc.withValues(alpha: .35))),
          child: SelectableText(code, style: ts(14, w: FontWeight.w600, c: pal.accText, h: 1.6)),
        ),
        const Hint('好友复制后打开 Lyra，会在刘海处弹出横幅直接播放', padding: EdgeInsets.symmetric(vertical: 12)),
        Row(children: [
          Expanded(child: Btn('复制口令', icon: 'copy', onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            Navigator.of(c).pop();
            toast('口令已复制', 'copy');
          })),
          if (playlistTitle == null) ...[
            const SizedBox(width: 10),
            Expanded(child: Btn.sec('生成歌词卡', icon: 'image', onTap: () {
              Navigator.of(c).pop();
              openLyricCard(context);
            })),
          ],
        ]),
      ]),
    );
  });
}

// ============ 睡眠定时 ============
void openTimer(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '睡眠定时', dark: dark, builder: (c) {
    final app = c.app;
    final left = app.sleepLeft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        if (left > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('正在倒计时 · 剩 ${(left / 60).ceil()} 分钟（${(left / 60).floor()}:${(left % 60).toString().padLeft(2, '0')}）后停止播放',
                style: ts(13, w: FontWeight.w600, c: c.pal.accText)),
          ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final m in const [0, 15, 30, 45, 60, 90])
              Press(
                onTap: () {
                  app.setSleepTimer(m);
                  Navigator.of(c).pop();
                  toast(m == 0 ? '已关闭睡眠定时' : '$m 分钟后停止播放', 'moon');
                },
                child: AnimatedContainer(
                  duration: Tk.base,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: app.timer == m ? c.pal.accSoft : c.pal.s2, borderRadius: BorderRadius.circular(14), border: Border.all(color: app.timer == m ? c.pal.acc : Colors.transparent)),
                  child: Text(m == 0 ? '关闭' : '$m 分钟', style: ts(14, w: FontWeight.w600, c: app.timer == m ? c.pal.accText : c.pal.t1)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Group(children: [
          Item(label: '播完当前歌曲再停', sw: app.set.finishSong, onSw: (v) => app.update(() => app.set.finishSong = v)),
          Item(label: '停止前 30 秒淡出', sw: app.set.fadeStop, onSw: (v) => app.update(() => app.set.fadeStop = v)),
        ]),
      ]),
    );
  });
}

// ============ 均衡器 ============
void openEq(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '均衡器', dark: dark, action: Builder(builder: (c) {
    final app = c.app;
    return Padding(padding: const EdgeInsets.only(right: 8), child: LSwitch(app.eqOn, (v) => app.update(() {
        app.eqOn = v;
        app.applyEqToEngine();
      })));
  }), builder: (c) {
    final app = c.app;
    final pal = c.pal;
    final presets = [...eqPresets.keys, if (app.eqPreset == '自定义') '自定义'];
    return Opacity(
      opacity: app.eqOn ? 1 : .4,
      child: Column(children: [
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LChip(p, on: app.eqPreset == p, onTap: () {
                  if (p == '自定义') return;
                  app.update(() {
                    app.eqPreset = p;
                    app.eq = [...eqPresets[p]!];
                    app.applyEqToEngine();
                  });
                }),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 230,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Stack(children: [
              Positioned.fill(bottom: 24, child: CustomPaint(painter: _EqCurve(app.eq, pal.acc))),
              Row(children: [
                for (var i = 0; i < 10; i++)
                  Expanded(
                    child: Column(children: [
                      Expanded(
                        child: LayoutBuilder(builder: (c2, cs) {
                          final h = cs.maxHeight;
                          final v = app.eq[i];
                          void set(double dy) => app.update(() {
                                app.eq[i] = ((1 - dy / h) * 24 - 12).clamp(-12, 12).roundToDouble();
                                app.eqPreset = '自定义';
                                app.applyEqToEngine();
                              });
                          return GestureDetector(
                            onVerticalDragUpdate: (d) => set(d.localPosition.dy),
                            onTapDown: (d) => set(d.localPosition.dy),
                            child: Container(
                              color: Colors.transparent,
                              child: Stack(alignment: Alignment.topCenter, children: [
                                Container(width: 4, decoration: BoxDecoration(color: pal.s3, borderRadius: BorderRadius.circular(2))),
                                Positioned(top: (1 - (v + 12) / 24) * (h - 20), child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: pal.acc, width: 3)))),
                              ]),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(eqBands[i], style: ts(10, c: pal.t3, num: true)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
        const Hint('±12 dB · 拖动竖向滑杆调整，调整后自动切到「自定义」', align: TextAlign.center),
      ]),
    );
  });
}

class _EqCurve extends CustomPainter {
  final List<double> v;
  final Color c;
  _EqCurve(this.v, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final pts = [for (var i = 0; i < v.length; i++) Offset(s.width * (i + .5) / v.length, 10 + (1 - (v[i] + 12) / 24) * (s.height - 20))];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      path.cubicTo((a.dx + b.dx) / 2, a.dy, (a.dx + b.dx) / 2, b.dy, b.dx, b.dy);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = c.withValues(alpha: .6));
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, s.height)
      ..lineTo(pts.first.dx, s.height)
      ..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .22), c.withValues(alpha: 0)]).createShader(Offset.zero & s));
  }

  @override
  bool shouldRepaint(_EqCurve o) => true;
}

// ============ 音质 / 倍速 / 投放 ============
void openQuality(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '音质', sub: context.appRead.song.title, dark: dark, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    const order = ['128k', 'HQ', 'SQ', 'Hi-Res', 'Dolby', 'Atmos'];
    final max = order.indexOf(app.song.quality == 'Atmos' ? 'Atmos' : app.song.quality);
    return Column(children: [
      for (final (i, q) in qualities.indexed)
        Opacity(
          opacity: i <= math.max(max, 2) || q.key == app.song.quality ? 1 : .35,
          child: Press(
            onTap: i <= math.max(max, 2) || q.key == app.song.quality
                ? () {
                    app.update(() {
                      app.quality = q.key;
                      app.set.onlineQ = q.key; // 真实生效：下一次取流按此档位（music_resolver 消费）
                    });
                    Navigator.of(c).pop();
                    toast('已切换到 ${q.name} ${q.key}，下一首起生效', 'hd');
                  }
                : () => toast('当前歌曲不支持 ${q.name}', 'info'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tk.pad, vertical: 12),
              child: Row(children: [
                SizedBox(width: 56, child: QBadge(q.key)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q.name, style: ts(15, w: FontWeight.w600, c: pal.t1)), Text(q.desc, style: ts(12, c: pal.t3))])),
                if (app.quality == q.key) Icon(ic('check'), color: pal.accText),
              ]),
            ),
          ),
        ),
      Group(children: [const Item(label: '不可用时自动降级', sub: '当前版本取流失败时会自动尝试更低档位，此行为始终开启')]),
    ]);
  });
}

void openSpeed(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '倍速', dark: dark, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        Text('${app.speed.toStringAsFixed(2)}×', style: ts(44, w: FontWeight.w800, c: pal.t1, num: true)),
        LSlider(value: app.speed, min: .5, max: 2, step: .05, onChanged: (v) => app.update(() {
              app.speed = v;
              app.applySpeedToEngine(); // 正在播放的这一首立即变速，不等下一首加载
            })),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [for (final v in const [.75, 1.0, 1.25, 1.5, 2.0]) LChip('$v×', on: (app.speed - v).abs() < .01, onTap: () => app.update(() {
              app.speed = v;
              app.applySpeedToEngine();
            }))]),
        const SizedBox(height: 14),
        Group(children: [Item(label: '保持音调', sub: '变速时不改变音高', sw: app.set.pitch, onSw: (v) => app.update(() {
              app.set.pitch = v;
              app.applySpeedToEngine(); // 音调跟随倍速 / 恢复 1.0，同样立即生效
            }))]),
      ]),
    );
  });
}

void openCast(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '投放', sub: '同一 Wi-Fi 下的 DLNA 设备', dark: dark, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    // 真实 DLNA 发现：SSDP 组播 → 设备描述解析。连接后经 resolver 取流，声音由渲染端播放。
    return StatefulBuilder(builder: (c, set) {
      List<DlnaDevice> devices = [];
      var scanning = true;
      var connecting = '';
      String? error;

      Future<void> rescan() async {
        set(() {
          scanning = true;
          error = null;
          devices = [];
        });
        try {
          final r = await app.cast?.discover() ?? const <DlnaDevice>[];
          if (c.mounted) set(() {
            devices = r;
            scanning = false;
          });
        } catch (e) {
          if (c.mounted) set(() {
            scanning = false;
            error = '$e';
          });
        }
      }

      unawaited(rescan());

      Future<void> pick(DlnaDevice d) async {
        if (app.cast == null) return toast('当前环境不支持投放', 'info');
        set(() => connecting = d.name);
        try {
          await app.connectCast(d); // 有歌在播：立即把当前曲目投过去
          if (c.mounted) Navigator.of(c).pop();
          toast(app.hasSong ? '已投放到 ${d.name}' : '已连接 ${d.name}，播放时自动投放', 'cast');
        } catch (e) {
          app.update(() => app.castDev = null);
          toast('投放失败：$e', 'info');
        }
        if (c.mounted) set(() => connecting = '');
      }

      return Column(children: [
        if (scanning) const Padding(padding: EdgeInsets.symmetric(horizontal: Tk.pad), child: _ScanStrip()),
        if (!scanning && error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 6, Tk.pad, 6),
            child: Text('扫描失败：$error', style: ts(12.5, c: pal.danger)),
          ),
        if (!scanning && devices.isEmpty && error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 14, Tk.pad, 8),
            child: Text('未发现可投放的设备\n确认电视 / 音箱已开启 DLNA 并与手机在同一 Wi-Fi', textAlign: TextAlign.center, style: ts(13, c: pal.t3, h: 1.6)),
          ),
        // 已连接且设备支持 RenderingControl：这里调电视 / 音箱的音量（手机音量键同样生效）
        if (app.castDev != null && app.cast?.canVolume == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.pad, 4, Tk.pad, 10),
            child: Row(children: [
              Icon(Icons.volume_mute_rounded, color: pal.t3, size: 18),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: LSlider(value: app.outputVolume, min: 0, max: 1, onChanged: app.setVolume))),
              Icon(Icons.volume_up_rounded, color: pal.t3, size: 18),
              const SizedBox(width: 8),
              SizedBox(width: 34, child: Text('${(app.outputVolume * 100).round()}', textAlign: TextAlign.right, style: ts(12.5, c: pal.t2, num: true))),
            ]),
          ),
        for (final d in devices)
          Item(
            lead: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: app.castDev == d.name ? pal.accSoft : pal.s2, borderRadius: BorderRadius.circular(12)),
                child: connecting == d.name
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: pal.acc))
                    : Icon(ic((d.modelName ?? '').toLowerCase().contains('tv') ? 'tv' : 'speaker'), color: app.castDev == d.name ? pal.accText : pal.t2)),
            label: d.name,
            sub: connecting == d.name ? '连接中…' : (d.modelName ?? 'DLNA 渲染设备'),
            trailing: app.castDev == d.name ? Icon(ic('check'), color: pal.accText) : null,
            onTap: connecting.isEmpty ? () => unawaited(pick(d)) : null,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 0),
          child: Row(children: [
            Expanded(child: Btn.sec('重新扫描', icon: 'refresh', onTap: scanning ? null : () => unawaited(rescan()))),
            if (app.castDev != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Btn('断开 ${app.castDev}', kind: BtnKind.danger, onTap: () async {
                  await app.disconnectCast();
                  if (c.mounted) Navigator.of(c).pop();
                  toast('已断开投放，按播放键回到本地播放', 'cast');
                }),
              ),
            ],
          ]),
        ),
      ]);
    });
  });
}

class _ScanStrip extends StatefulWidget {
  const _ScanStrip();
  @override
  State<_ScanStrip> createState() => _ScanStripState();
}

class _ScanStripState extends State<_ScanStrip> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: AnimatedBuilder(animation: c, builder: (_, __) => FractionalTranslation(translation: Offset(c.value * 2 - 1, 0), child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, pal.acc, Colors.transparent]))))),
      ),
    );
  }
}

// ============ 歌词分享卡 / 播放链路 ============
void openLyricCard(BuildContext context) {
  final cardKey = GlobalKey();
  showLSheet(context, title: '歌词分享卡', dark: true, builder: (c) {
    final app = c.app;
    final s = app.song;
    final k = app.lyricIndex;
    final text = [lyrics[k].text, lyrics[(k + 1) % lyrics.length].text].where((x) => x.trim().isNotEmpty).join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        RepaintBoundary(key: cardKey, child: SizedBox(
          height: 360,
          child: Cover.song(
          s,
          size: 0,
          radius: 24,
          child: SizedBox(
            height: 360,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0xCC000000)])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('“', style: ts(64, w: FontWeight.w800, c: c.pal.acc, h: 1)),
                Text(lyrics[k].text, style: ts(24, w: FontWeight.w800, c: Colors.white, h: 1.4)),
                const SizedBox(height: 8),
                Text(lyrics[(k + 1) % lyrics.length].text, style: ts(24, w: FontWeight.w800, c: Colors.white, h: 1.4)),
                const Spacer(),
                Row(children: [
                  Cover.song(s, size: 40, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(14, w: FontWeight.w700, c: Colors.white)), Text(s.artist, style: ts(12, c: const Color(0xB3FFFFFF)))])),
                  AppIcon(app.appIcon, size: 28),
                ]),
              ]),
            ),
          ),
        ),
        )),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Btn.sec('复制歌词', icon: 'copy', onTap: () {
            Clipboard.setData(ClipboardData(text: '$text\n—— ${s.title} · ${s.artist}'));
            Navigator.of(c).pop();
            toast('已复制歌词', 'copy');
          })),
          const SizedBox(width: 10),
          // 分享图片：把卡片渲染成 PNG 交给系统分享面板（面板里可以「保存到相册」或发给好友）
          Expanded(child: Btn('分享图片', icon: 'share', onTap: () async {
            try {
              final b = cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              if (b == null) return;
              final img = await b.toImage(pixelRatio: 3);
              final png = await img.toByteData(format: ui.ImageByteFormat.png);
              if (png == null) return;
              final file = XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'lyra-lyric.png');
              if (c.mounted) Navigator.of(c).pop();
              await SharePlus.instance.share(ShareParams(files: [file], text: '${s.title} · ${s.artist}'));
            } catch (e) {
              toast('分享失败：$e', 'info');
            }
          })),
        ]),
      ]),
    );
  });
}

void openTrace(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '播放链路', sub: context.appRead.song.title, dark: dark, builder: (c) {
    final pal = c.pal;
    final history = c.appRead.resolver?.history ?? const <ResolveTrace>[];
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 8, Tk.pad, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('还没有取流记录', style: ts(14, w: FontWeight.w600, c: pal.t1)),
          const SizedBox(height: 6),
          Text('播放一首歌后，这里会显示每次尝试用的是「直链」还是「音源脚本」，以及实际音质、缓存命中与换平台过程。', style: ts(12.5, c: pal.t3, h: 1.6)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(children: [
        for (final (i, t) in history.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Column(children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(shape: BoxShape.circle, color: t.ok ? pal.ok : pal.danger)),
                if (i < history.length - 1) Expanded(child: Container(width: 1.5, color: pal.line)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_hhmmss(t.time)} · ${t.title}', style: ts(11, c: pal.t3, num: true), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${t.ok ? '取流成功' : '取流失败'} · ${t.platform} · ${t.quality}', style: ts(14, w: FontWeight.w600, c: pal.t1)),
                    Text((t.source == '直链' || t.source == 'WebDAV' || t.source == '已下载' ? t.source : '音源脚本 · ${t.source}') + (t.note.isEmpty ? '' : ' · ${t.note}'), style: ts(12.5, c: t.ok ? pal.t2 : pal.danger)),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  });
}

String _hhmmss(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

// ============ 播放队列 ============
void openQueue(BuildContext context, {bool dark = true}) {
  showLSheet(context, title: '播放队列', sub: '${context.appRead.queue.length} 首', dark: dark, scroll: false, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad, vertical: 5), children: [
          LChip(app.modeName, icon: const {'loop': 'repeat', 'one': 'repeat1', 'shuffle': 'shuffle', 'order': 'order'}[app.mode], on: true, onTap: app.cycleMode),
          const SizedBox(width: 8),
          if (!app.online) LChip('存为歌单', icon: 'plus', onTap: () {
            app.update(() => app.myPlaylists.add(Playlist(400 + app.myPlaylists.length, app.queueName, count: app.queue.length, hue: app.song.hue, variant: 2, mine: true)));
            toast('已存为歌单「${app.queueName}」', 'check');
          }),
          const SizedBox(width: 8),
          LChip('清空', icon: 'trash', onTap: () => showLDialog(c, icon: 'trash', title: '清空播放队列？', body: '当前歌曲会保留', actions: [
                ('取消', BtnKind.sec, null),
                ('清空', BtnKind.danger, () {
                  app.update(() => app.queue = [app.cur]);
                  toast('已清空队列', 'trash');
                }),
              ])),
        ]),
      ),
      Flexible(
        child: ReorderableListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 10),
          itemCount: app.queue.length,
          onReorder: app.reorderQueue,
          proxyDecorator: (ch, _, __) => Material(color: Colors.transparent, elevation: 8, child: ch),
          itemBuilder: (_, i) {
            final s = songs[app.queue[i]];
            final cur = s.id == app.cur;
            return Container(
              key: ValueKey('q${s.id}'),
              color: cur ? pal.accSoft : Colors.transparent,
              child: Press(
                onTap: () => app.play(s.id),
                child: SizedBox(
                  height: 60,
                  child: Row(children: [
                    const SizedBox(width: Tk.pad),
                    Cover.song(s, size: 42),
                    const SizedBox(width: 12),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: ts(14.5, w: FontWeight.w600, c: cur ? pal.accText : pal.t1)), Text(s.artist, style: ts(12, c: pal.t3))])),
                    if (cur) EqBars(playing: app.playing, color: pal.accText),
                    ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(14), child: Icon(ic('drag'), color: pal.t3))),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  });
}

// ============ 外观相关 Sheet：底栏样式 / App 图标 / 字体 ============
void openBarStyles(BuildContext context) {
  showLSheet(context, title: '底部导航样式', sub: '${barStyles.length} 种', builder: (c) {
    final app = c.app;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: .66,
        children: [
          for (final e in barStyles.entries)
            BarPreviewTile(e.key, on: app.bar == e.key, desc: barDesc[e.key], onTap: () {
              app.update(() {
                app.bar = e.key;
                app.navMin = false;
              });
              toast('底栏：${e.value}', 'grid');
            }),
        ],
      ),
    );
  });
}

/// 底栏样式缩略预览。
class BarPreviewTile extends StatelessWidget {
  final String k;
  final bool on;
  final String? desc;
  final VoidCallback onTap;
  const BarPreviewTile(this.k, {super.key, required this.on, this.desc, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget bar;
    final dots = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (var i = 0; i < (k == 'capsule' ? 4 : 5); i++) Container(width: k == 'text' ? 10 : 8, height: k == 'text' ? 3 : 8, decoration: BoxDecoration(color: i == 0 ? pal.acc : pal.t3, borderRadius: BorderRadius.circular(4)))]);
    switch (k) {
      case 'classic':
      case 'text':
      case 'frosted':
        bar = Positioned(left: 0, right: 0, bottom: 0, height: 18, child: Container(decoration: BoxDecoration(color: k == 'frosted' ? pal.glassStrong : pal.bgElev, border: Border(top: BorderSide(color: k == 'classic' ? pal.acc : pal.line))), child: dots));
        break;
      case 'dock':
        bar = Positioned(left: 22, right: 22, bottom: 6, height: 16, child: Container(decoration: BoxDecoration(color: pal.glassStrong, borderRadius: BorderRadius.circular(6)), child: dots));
        break;
      case 'bubble':
        bar = Positioned(left: 6, right: 6, bottom: 6, height: 14, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (var i = 0; i < 5; i++) Container(width: 12, height: 12, decoration: BoxDecoration(color: i == 0 ? pal.acc : pal.glassStrong, shape: BoxShape.circle, border: Border.all(color: pal.lineStrong)))]));
        break;
      case 'capsule':
        bar = Positioned(left: 6, right: 6, bottom: 6, height: 16, child: Row(children: [Expanded(child: Container(decoration: BoxDecoration(color: pal.glassStrong, borderRadius: BorderRadius.circular(8)), child: dots)), const SizedBox(width: 4), Container(width: 16, height: 16, decoration: BoxDecoration(color: pal.glassStrong, shape: BoxShape.circle))]));
        break;
      case 'cutout':
        bar = Positioned(left: 6, right: 6, bottom: 6, height: 16, child: Stack(clipBehavior: Clip.none, children: [Container(decoration: BoxDecoration(color: pal.glassStrong, borderRadius: BorderRadius.circular(6))), Positioned(left: 14, top: -9, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: pal.acc, shape: BoxShape.circle)))]));
        break;
      default:
        bar = Positioned(left: 6, right: 6, bottom: 6, height: 16, child: Container(decoration: BoxDecoration(color: pal.glass, borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.lineStrong)), child: dots));
    }
    return Press(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: Tk.base,
          height: 92,
          decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? pal.acc : Colors.transparent, width: 2)),
          child: Stack(children: [bar]),
        ),
        const SizedBox(height: 6),
        Text(barStyles[k]!, style: ts(13, w: on ? FontWeight.w700 : FontWeight.w500, c: on ? pal.accText : pal.t1)),
        if (desc != null) Text(desc!, maxLines: 2, textAlign: TextAlign.center, style: ts(10, c: pal.t3)),
      ]),
    );
  }
}

void openAppIcons(BuildContext context) {
  showLSheet(context, title: 'App 图标', builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Column(children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: Tk.pad),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: [hsl(240, .3, pal.dark ? .2 : .85), hsl(300, .3, pal.dark ? .14 : .9)])),
        child: GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 14, children: [
          for (var i = 0; i < 8; i++)
            i == 5
                ? Column(children: [const AppLogo(size: 54), const SizedBox(height: 4), Text('Lyra', style: ts(11, c: Colors.white))])
                : Center(child: Container(width: 54, height: 54, decoration: BoxDecoration(color: hsl(i * 47.0, .4, pal.dark ? .3 : .72), borderRadius: BorderRadius.circular(13)))),
        ]),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: .66,
          crossAxisSpacing: 8,
          children: [
            for (final a in appIcons)
              Press(
                onTap: () {
                  app.update(() => app.appIcon = a[0]);
                  toast('App 内图标已换成「${a[1]}」', 'grid');
                },
                child: Column(children: [
                  AnimatedContainer(duration: Tk.base, padding: const EdgeInsets.all(3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: app.appIcon == a[0] ? pal.acc : Colors.transparent, width: 2)), child: AppIcon(a[0], size: 60)),
                  const SizedBox(height: 6),
                  Text(a[1], style: ts(12.5, w: FontWeight.w600, c: pal.t1)),
                  Text(a[2], maxLines: 2, textAlign: TextAlign.center, style: ts(10, c: pal.t3)),
                ]),
              ),
          ],
        ),
      ),
      const Hint('图标为「Lyra」暂名设计：天琴座（Lyra）的竖琴 + 织女星。这里只更换 App 里显示的图标（迷你播放器、分享卡等），桌面上的应用图标暂时不能更换。'),
    ]);
  });
}

void openFonts(BuildContext context) {
  showLSheet(context, title: '界面字体', builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Column(children: [
      for (final f in fonts)
        Press(
          onTap: () => app.update(() => app.font = f[0]),
          child: Container(
            margin: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: app.font == f[0] ? pal.accSoft : pal.s1, borderRadius: BorderRadius.circular(16), border: Border.all(color: app.font == f[0] ? pal.acc : pal.line)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f[1], style: TextStyle(fontFamily: fontFamilyOf(f[0]), fontFamilyFallback: fontFallbackOf(f[0]), fontSize: 15, fontWeight: FontWeight.w700, color: pal.t1)),
                  Text('夜航的星图 Aa 0123', style: TextStyle(fontFamily: fontFamilyOf(f[0]), fontFamilyFallback: fontFallbackOf(f[0]), fontSize: 13, color: pal.t2)),
                ]),
              ),
              if (app.font == f[0]) Icon(ic('check'), color: pal.accText),
            ]),
          ),
        ),
      Group(children: [
        if (customFontReady)
          Item(icon: 'font', color: 'teal', label: '导入的字体', sw: app.font == 'custom', onSw: (v) => app.update(() => app.font = v ? 'custom' : 'system')),
        Item(icon: 'plus', color: 'blue', label: customFontReady ? '重新导入字体' : '导入字体', sub: '支持 .ttf / .otf，导入后只在本 App 内生效', onTap: () async {
          try {
            final name = await importCustomFont();
            if (name == null) return;
            app.update(() => app.font = 'custom');
            toast('已导入「$name」', 'font');
          } catch (e) {
            toast(e is FormatException ? e.message : '导入失败：$e', 'info');
          }
        }),
      ]),
    ]);
  });
}

String? fontFamilyOf(String id) => id == 'custom' ? (customFontReady ? customFontFamily : null) : const {'serif': 'serif', 'mono': 'monospace', 'kai': 'serif', 'round': 'sans-serif'}[id];
List<String>? fontFallbackOf(String id) => const {
      'round': ['SF Pro Rounded', 'HarmonyOS Sans SC', 'MiSans', 'PingFang SC'],
      'serif': ['Songti SC', 'Noto Serif SC', 'Noto Serif CJK SC', 'Source Han Serif SC'],
      'kai': ['Kaiti SC', 'STKaiti', 'KaiTi', 'LXGW WenKai'],
      'mono': ['SF Mono', 'Sarasa Mono SC', 'JetBrains Mono', 'Menlo'],
    }[id];

// ============ 输入框（浮动标签 + 聚焦描边 + 校验） ============
class LField extends StatefulWidget {
  final String label;
  final String? icon, error, suffix;
  final TextEditingController? controller;
  final bool password, autofocus, ok;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSuffix;
  final TextInputType? keyboard;
  final int lines;
  final int shake;
  const LField({super.key, required this.label, this.icon, this.controller, this.password = false, this.autofocus = false, this.onChanged, this.error, this.ok = false, this.suffix, this.onSuffix, this.keyboard, this.lines = 1, this.shake = 0});
  @override
  State<LField> createState() => _LFieldState();
}

class _LFieldState extends State<LField> with SingleTickerProviderStateMixin {
  late final tc = widget.controller ?? TextEditingController();
  final fn = FocusNode();
  bool hide = true;
  late final sh = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    fn.addListener(() => setState(() {}));
    tc.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(LField o) {
    super.didUpdateWidget(o);
    if (widget.shake != o.shake) sh.forward(from: 0);
  }

  @override
  void dispose() {
    fn.dispose();
    sh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final focus = fn.hasFocus;
    final up = focus || tc.text.isNotEmpty;
    final err = widget.error != null;
    final border = err ? pal.danger : focus ? pal.acc.withValues(alpha: .6) : Colors.transparent;
    final h = widget.lines > 1 ? 52.0 + (widget.lines - 1) * 20 : 52.0;
    final field = AnimatedContainer(
      duration: Tk.base,
      height: h,
      decoration: BoxDecoration(
        color: focus ? pal.s1 : pal.s2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.4),
        boxShadow: focus && !err ? [BoxShadow(color: pal.acc.withValues(alpha: .16), blurRadius: 12, spreadRadius: 1)] : null,
      ),
      child: Row(crossAxisAlignment: widget.lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        if (widget.icon != null) Padding(padding: EdgeInsets.only(left: 14, right: 10, top: widget.lines > 1 ? 16 : 0), child: Icon(ic(widget.icon!), size: 19, color: focus ? pal.accText : pal.t3)),
        if (widget.icon == null) const SizedBox(width: 14),
        Expanded(
          child: SizedBox(
          height: h - 3,
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Tk.out,
              top: up ? 6 : 14,
              left: 0,
              child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: ts(up ? 11 : 15, c: err ? pal.danger : (focus ? pal.accText : pal.t3)), child: Text(widget.label)),
            ),
            Padding(
              padding: EdgeInsets.only(top: widget.lines > 1 ? 24 : 22),
              child: TextField(
                controller: tc,
                focusNode: fn,
                autofocus: widget.autofocus,
                obscureText: widget.password && hide,
                keyboardType: widget.keyboard,
                maxLines: widget.lines,
                textAlignVertical: TextAlignVertical.top,
                onChanged: widget.onChanged,
                style: ts(15, c: pal.t1),
                cursorColor: pal.acc,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
              ),
            ),
          ]),
        ),
        ),
        if (widget.ok) Padding(padding: const EdgeInsets.only(right: 10), child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 420), curve: Tk.spring, builder: (_, v, __) => Transform.scale(scale: v, child: Icon(Icons.check_circle_rounded, color: pal.ok, size: 20)))),
        if (widget.password) IBtn(hide ? 'eye' : 'eyeoff', size: 40, iconSize: 19, color: pal.t3, onTap: () => setState(() => hide = !hide)),
        if (widget.suffix != null) Press(onTap: widget.onSuffix ?? () => toast('验证码已发送', 'mail'), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text(widget.suffix!, style: ts(14, w: FontWeight.w600, c: widget.onSuffix == null && widget.suffix!.endsWith('s') ? pal.t3 : pal.accText)))),
      ]),
    );
    // 点框内任意位置（浮动标签、图标、空白处）都让输入框获得焦点；输入区、眼睛、后缀按钮自己处理点击
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!fn.hasFocus) fn.requestFocus();
      },
      child: MouseRegion(cursor: SystemMouseCursors.text, child: field),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedBuilder(animation: sh, child: tappable, builder: (_, ch) => Transform.translate(offset: Offset(math.sin(sh.value * math.pi * 6) * 8 * (1 - sh.value), 0), child: ch)),
      AnimatedSize(duration: Tk.base, child: err ? Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(widget.error!, style: ts(12, c: pal.danger))) : const SizedBox(width: double.infinity)),
    ]);
  }
}

// ============ 设置页里用到的跳转 ============
void openSkinsLink(BuildContext context) => push(context, const AppearancePage());

/// 还没接入的功能：说明原因，不假装成功。
void openPendingFeature(BuildContext context, String title, String why) {
  showLSheet(context, title: title, builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 8),
        child: Column(children: [
          Icon(ic('clock'), size: 40, color: c.pal.t3),
          const SizedBox(height: 12),
          Text('这个功能正在接入', style: ts(16, w: FontWeight.w700, c: c.pal.t1)),
          const SizedBox(height: 6),
          Text(why, textAlign: TextAlign.center, style: ts(13, c: c.pal.t2, h: 1.6)),
          const SizedBox(height: 18),
          Btn('知道了', block: true, onTap: () => Navigator.of(c).pop()),
        ]),
      ));
}
