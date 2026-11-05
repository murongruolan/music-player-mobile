// 好友口令横幅：打开 App 时剪贴板里有分享口令（联网：[Lyra]V1·…；演示：【Lyra歌曲·N·…】），就从刘海处展开（124×36 → 366×76，620ms 弹簧）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/share_code.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../pages/remote.dart' show RemoteCollectionPage;
import '../platform/models.dart';
import '../ui/cover.dart';
import 'shell.dart' show push;
import '../ui/kit.dart';

Future<void> detectClipboard(AppState app) async {
  if (!app.set.clipDetect || app.clipSong != null || app.clipList != null) return;
  try {
    final d = await Clipboard.getData('text/plain');
    final text = d?.text ?? '';
    if (!app.online) {
      // 演示模式：mock 歌曲编号口令
      final m = RegExp(r'【Lyra歌曲·(\d+)·').firstMatch(text);
      if (m == null) return;
      final id = (int.tryParse(m[1]!) ?? 1) - 1;
      if (id >= 0 && id < songs.length) app.update(() => app.clipSong = id);
      return;
    }
    // 联网模式：[Lyra]V1·wy·186016·晴天-周杰伦 / [Lyra]V1·歌单·wy·7741029·名字
    final code = parseShareCode(text);
    if (code == null || await app.clipSeen(shareSig(code))) return;
    app.markClipHandled(text);
    switch (code) {
      case SongShareCode():
        final t = await resolveSongCode(app.content, code);
        final id = app.library.register(t.toCloud());
        app.update(() => app.clipSong = id);
      case PlaylistShareCode():
        app.update(() => app.clipList = code);
    }
  } catch (_) {}
}

class ClipBanner extends StatefulWidget {
  const ClipBanner({super.key});
  @override
  State<ClipBanner> createState() => _ClipBannerState();
}

class _ClipBannerState extends State<ClipBanner> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))..forward();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await c.reverse();
    if (!mounted) return;
    final app = context.appRead;
    app.update(() {
      app.clipSong = null;
      app.clipList = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final id = app.clipSong;
    final list = app.clipList;
    if (id == null && list == null) return const SizedBox();
    final s = id == null ? null : app.songById(id);
    final pal = context.pal.forceDark;
    final top = MediaQuery.of(context).padding.top;
    final w = MediaQuery.of(context).size.width;
    return Positioned(
      top: top > 30 ? 11 : top + 6,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) {
            final t = c.status == AnimationStatus.reverse ? Curves.easeIn.transform(c.value) : Tk.softSpring.transform(c.value);
            final bw = 124 + (w - 24 - 124) * t, bh = 36 + 40 * t;
            return Container(
              width: bw,
              height: bh,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18 + 6 * t), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .4 * t), blurRadius: 24, offset: const Offset(0, 10))]),
              clipBehavior: Clip.antiAlias,
              child: Opacity(
                opacity: ((c.value - .35) / .65).clamp(0, 1),
                child: OverflowBox(
                  maxWidth: w - 24,
                  maxHeight: 76,
                  child: SizedBox(
                    width: w - 24,
                    height: 76,
                    child: Row(children: [
                      const SizedBox(width: 12),
                      s != null ? Cover.song(s, size: 50, radius: 12) : Cover(hue: (list!.id.hashCode.abs() % 360).toDouble(), variant: 2, size: 50, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s != null ? '好友分享给你一首歌' : '好友分享给你一个${Plat.names[list!.platform] ?? ''}歌单', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, c: const Color(0x99FFFFFF))),
                          Text(s != null ? (s.artist.isEmpty ? s.title : '${s.title} · ${s.artist}') : (list!.name.isEmpty ? '歌单 ${list.id}' : list.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, c: Colors.white)),
                        ]),
                      ),
                      Press(
                        onTap: () {
                          if (s != null) {
                            app.online ? app.play(s.id, ids: [s.id], name: '好友分享') : app.play(s.id, list: 'all');
                          } else {
                            push(context, RemoteCollectionPage(platform: list!.platform, type: CatalogType.playlist, id: list.id, title: list.name));
                          }
                          _close();
                        },
                        scale: .9,
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(16)), child: Text(s != null ? '播放' : '打开', style: ts(13.5, w: FontWeight.w700, c: pal.ink))),
                      ),
                      IBtn('close', size: 40, iconSize: 18, color: Colors.white60, onTap: _close),
                      const SizedBox(width: 4),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
