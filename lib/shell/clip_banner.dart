// 好友口令横幅：打开 App 时剪贴板里有【Lyra歌曲·N·…】口令，就从刘海处展开（124×36 → 366×76，620ms 弹簧）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../ui/cover.dart';
import '../ui/kit.dart';

Future<void> detectClipboard(AppState app) async {
  // 分享口令目前是 mock 歌曲编号，联网模式下不识别
  if (app.online || !app.set.clipDetect || app.clipSong != null) return;
  try {
    final d = await Clipboard.getData('text/plain');
    final m = RegExp(r'【Lyra歌曲·(\d+)·').firstMatch(d?.text ?? '');
    if (m == null) return;
    final id = (int.tryParse(m[1]!) ?? 1) - 1;
    if (id >= 0 && id < songs.length) app.update(() => app.clipSong = id);
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
    app.update(() => app.clipSong = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final id = app.clipSong;
    if (id == null) return const SizedBox();
    final s = songs[id];
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
                      Cover.song(s, size: 50, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('好友分享给你一首歌', style: ts(11.5, c: const Color(0x99FFFFFF))),
                          Text('${s.title} · ${s.artist}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, c: Colors.white)),
                        ]),
                      ),
                      Press(
                        onTap: () {
                          app.play(s.id, list: 'all');
                          _close();
                        },
                        scale: .9,
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: pal.acc, borderRadius: BorderRadius.circular(16)), child: Text('播放', style: ts(13.5, w: FontWeight.w700, c: pal.ink))),
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
