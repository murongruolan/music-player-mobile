// 联网模式的「导入歌单」：粘贴链接 / 分享文案 / 歌单 ID → 解析预览 → 保持同步或复制一份。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/playlist_import.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../pages/detail.dart';
import '../pages/remote.dart' show appPlatform;
import '../platform/models.dart';
import '../platform/playlist_link.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/kit.dart';
import 'sheets.dart' show LField;

/// 输入框旁的即时提示：不联网就能认出来的给平台名，短链只说「分享链接」。
String? importHint(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final pre = parsePrefixedId(t);
  if (pre != null) return '已识别为 ${Plat.names[pre.platform]} 歌单 ID';
  final url = firstUrlIn(t);
  if (url == null) return null;
  final hit = parsePlaylistUrl(url);
  if (hit != null) return '已识别为 ${Plat.names[hit.platform]} 歌单链接';
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  for (final e in const {'163': Plat.wy, 'qq.com': Plat.tx, 'kugou': Plat.kg, 'kuwo': Plat.kw, 'migu': Plat.mg}.entries) {
    if (host.contains(e.key)) return '${Plat.names[e.value]} 分享链接，导入时自动展开';
  }
  return null;
}

void openImportOnline(BuildContext context, {String? initial}) {
  final tc = TextEditingController(text: initial ?? '');
  final importer = PlaylistImporter(context.appRead);
  var pid = 'netease';
  var stage = 0; // 0 输入 1 解析中 2 确认 3 导入中
  var sync = true;
  var closed = false;
  String? error;
  PlaylistRef? ref;
  Collection? head;
  var got = 0, total = 0;

  showLSheet(context, title: '导入歌单', sub: '平台链接 · 分享文案 · 歌单 ID', builder: (c) => StatefulBuilder(builder: (c, set) {
        final pal = c.pal;
        final app = c.app;
        final hint = importHint(tc.text);

        Future<void> parse() async {
          if (tc.text.trim().isEmpty) return set(() => error = '请先粘贴歌单链接或输入歌单 ID');
          set(() {
            stage = 1;
            error = null;
          });
          try {
            final r = await importer.resolve(tc.text, fallbackPlatform: Plat.fromAppId[pid] ?? Plat.wy);
            final h = await importer.preview(r);
            if (closed) return;
            set(() {
              ref = r;
              head = h;
              stage = 2;
            });
          } on PlaylistLinkException catch (e) {
            if (!closed) set(() {
              stage = 0;
              error = e.message;
            });
          }
        }

        void openResult(int playlistId) {
          Navigator.of(c).pop();
          push(context, PlaylistPage(id: playlistId));
        }

        Future<void> doImport() async {
          final r = ref!, h = head!;
          final old = importer.existing(r);
          if (sync) {
            if (old != null) {
              toast('这个歌单已经在音乐库里了', 'info');
              return openResult(old.id);
            }
            final p = importer.link(r, h);
            app.telemetry.track('playlist_import', {'platform': r.platform, 'mode': 'link', 'total': h.total});
            toast('已导入「${p.title}」，会跟原歌单保持同步', 'download');
            return openResult(p.id);
          }
          set(() {
            stage = 3;
            got = h.tracks.length;
            total = h.total;
          });
          try {
            final (p, n) = await importer.copy(r, h, cancelled: () => closed, onProgress: (g, t) {
              if (!closed) set(() {
                got = g;
                total = t;
              });
            });
            app.telemetry.track('playlist_import', {'platform': r.platform, 'mode': 'copy', 'total': h.total, 'added': n});
            if (closed) return toast('已导入 $n 首到「${p.title}」', 'download');
            toast('已导入 $n 首到「${p.title}」', 'download');
            openResult(p.id);
          } catch (e) {
            if (!closed) set(() {
              stage = 2;
              error = '导入中断：$e';
            });
          }
        }

        if (stage == 1) {
          return SizedBox(height: 200, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: pal.acc), const SizedBox(height: 16), Text('正在解析歌单…', style: ts(14, c: pal.t2))]));
        }
        if (stage == 3) {
          final p = total > 0 ? (got / total).clamp(0.0, 1.0) : null;
          return SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tk.pad * 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: p, minHeight: 6, color: pal.acc, backgroundColor: pal.s2)),
                const SizedBox(height: 14),
                Text(total > 0 ? '正在拉取歌曲 $got / $total' : '正在拉取歌曲 $got', style: ts(13.5, c: pal.t2, num: true)),
              ]),
            ),
          );
        }
        final h = head;
        if (stage == 2 && h != null) {
          final plat = appPlatform(ref!.platform);
          final old = importer.existing(ref!);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Column(children: [
              Row(children: [
                Cover(hue: (h.title.hashCode.abs() % 360).toDouble(), variant: 2, size: 88, radius: 16, url: h.cover),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.title.isEmpty ? '未命名歌单' : h.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w700, c: pal.t1)),
                    const SizedBox(height: 4),
                    Row(children: [PlatBadge(plat, size: 16), const SizedBox(width: 5), Flexible(child: Text([plat.name, if ((h.creator ?? '').isNotEmpty) h.creator!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t2)))]),
                    const SizedBox(height: 6),
                    Text('${h.total > 0 ? h.total : h.tracks.length} 首${old != null ? ' · 已在音乐库' : ''}', style: ts(12.5, c: old != null ? pal.ok : pal.t2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Item(
                icon: 'refresh',
                color: 'teal',
                label: '保持与原歌单同步',
                sub: sync ? '每次打开都从${plat.name}拉最新歌曲，桌面端同步可见' : '复制一份到自建歌单，之后可以自己增删',
                sw: sync,
                onSw: (v) => set(() => sync = v),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: ts(12.5, c: pal.danger))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Btn.sec('换一个', onTap: () => set(() {
                      stage = 0;
                      error = null;
                    }))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: Btn(sync && old != null ? '打开歌单' : '导入到音乐库', onTap: () => unawaited(doImport()))),
              ]),
            ]),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LField(controller: tc, label: '歌单链接、分享文案或 ID', icon: 'link', onChanged: (_) => set(() => error = null), ok: hint != null),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(error ?? hint ?? '支持网易云、QQ、酷狗、酷我、咪咕的歌单分享链接', style: ts(12, c: error != null ? pal.danger : (hint != null ? pal.ok : pal.t3))),
            ),
            const SizedBox(height: 14),
            Text('只有歌单 ID 时选平台', style: ts(12, c: pal.t3)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final p in platforms)
                Press(
                  onTap: () => set(() => pid = p.id),
                  child: Column(children: [
                    AnimatedContainer(
                      duration: Tk.base,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: pid == p.id ? pal.acc : Colors.transparent, width: 2)),
                      child: PlatBadge(p, size: 36, dim: pid != p.id),
                    ),
                    const SizedBox(height: 4),
                    Text(p.short, style: ts(11, c: pid == p.id ? pal.t1 : pal.t3)),
                  ]),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Btn.sec('粘贴', icon: 'paste', onTap: () async {
                final d = await Clipboard.getData('text/plain');
                final t = d?.text?.trim() ?? '';
                if (t.isEmpty) return toast('剪贴板是空的', 'info');
                tc.text = t;
                set(() => error = null);
              })),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Btn('解析歌单', onTap: () => unawaited(parse()))),
            ]),
          ]),
        );
      })).whenComplete(() => closed = true);
}
