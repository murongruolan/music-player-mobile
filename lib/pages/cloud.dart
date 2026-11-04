// 音乐云盘（联网模式）：WebDAV 服务器列表 → 添加 / 测试连接 → 浏览文件夹 → 直接播放。
// 演示模式的原型界面在 misc.dart 的 CloudPage 里。
import 'dart:async';
import 'package:flutter/material.dart';
import '../cloud/dav_store.dart';
import '../cloud/webdav.dart';
import '../core/app_log.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart' show songs;
import '../shell/shell.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';
import 'common.dart';
import 'settings.dart' show noteBox;

// ---------------------------------------------------------------- 首页：服务器列表

class DavHome extends StatelessWidget {
  const DavHome({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final list = app.dav.servers;
    return SubPage(title: '音乐云盘', actions: [IBtn('plus', onTap: () => push(context, const DavAddPage()))], children: [
      if (list.isEmpty) ...[
        EmptyState('cloud', '还没有连接云盘',
            desc: '连接坚果云、Alist、Nextcloud、群晖或威联通的 WebDAV，直接播放上面的音乐，不用先下载。',
            action: Btn('添加服务器', icon: 'plus', small: true, onTap: () => push(context, const DavAddPage()))),
      ] else ...[
        Group(title: '服务器', children: [
          for (final s in list)
            Item(
              icon: 'cloud',
              color: 'blue',
              label: s.name,
              sub: '${s.host} · ${s.user} · 音乐目录 ${s.root}',
              onTap: () => push(context, DavBrowsePage(serverId: s.id, path: s.root)),
              trailing: IBtn('more', color: pal.t3, onTap: () => _serverMenu(context, s)),
            ),
        ]),
        const Hint('点服务器浏览文件夹，点歌就能播放；云盘里的歌也可以收藏、加进歌单和下载。地址和密码只保存在本机钥匙串。'),
      ],
    ]);
  }

  void _serverMenu(BuildContext context, DavServer s) {
    final app = context.appRead;
    final pal = context.pal;
    showLSheet(context, title: s.name, builder: (c) => Group(children: [
          Item(icon: 'folder', color: 'orange', label: '浏览音乐目录', val: s.root, onTap: () {
            Navigator.of(c).pop();
            push(context, DavBrowsePage(serverId: s.id, path: s.root));
          }),
          Item(icon: 'folder', color: 'gray', label: '浏览根目录', onTap: () {
            Navigator.of(c).pop();
            push(context, DavBrowsePage(serverId: s.id, path: '/'));
          }),
          Item(icon: 'trash', color: 'red', label: '删除这台服务器', danger: true, chev: false, onTap: () {
            Navigator.of(c).pop();
            showLDialog(context, icon: 'trash', iconColor: pal.danger, title: '删除「${s.name}」？', body: '只删除本机保存的地址和密码，服务器上的文件不受影响。已收藏的云盘歌曲会无法播放。', actions: [
              ('取消', BtnKind.sec, null),
              ('删除', BtnKind.danger, () {
                unawaited(app.dav.remove(s.id));
                toast('已删除 ${s.name}', 'trash');
              }),
            ]);
          }),
        ]));
  }
}

// ---------------------------------------------------------------- 添加服务器

class DavAddPage extends StatefulWidget {
  const DavAddPage({super.key});
  @override
  State<DavAddPage> createState() => _DavAddPageState();
}

class _DavAddPageState extends State<DavAddPage> {
  int pv = 0;
  final name = TextEditingController(text: davProviders[0].$1);
  final url = TextEditingController(text: davProviders[0].$2);
  final user = TextEditingController();
  final pass = TextEditingController();
  final root = TextEditingController(text: '/');
  bool busy = false;

  /// 测试结果：null 没测；true 成功；false 失败（[msg] 是原因）。
  bool? ok;
  String msg = '';

  @override
  void dispose() {
    for (final c in [name, url, user, pass, root]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pick(int i) => setState(() {
        pv = i;
        name.text = davProviders[i].$1;
        url.text = davProviders[i].$2;
        ok = null;
      });

  String get _root {
    var r = root.text.trim();
    if (r.isEmpty) r = '/';
    if (!r.startsWith('/')) r = '/$r';
    if (!r.endsWith('/')) r = '$r/';
    return r;
  }

  Future<void> _test() async {
    if (url.text.trim().length < 10) {
      return setState(() {
        ok = false;
        msg = '请填写服务器地址';
      });
    }
    setState(() {
      busy = true;
      ok = null;
    });
    final c = WebDavClient(url.text, user.text.trim(), pass.text);
    try {
      final ms = await c.test(_root);
      final n = (await c.list(_root)).where((e) => e.isAudio || e.isDir).length;
      if (!mounted) return;
      setState(() {
        ok = true;
        msg = '连接成功 · ${ms}ms · 音乐目录里有 $n 个文件夹 / 音频';
      });
    } catch (e) {
      AppLog.instance.add('音乐云盘', '测试连接失败（${c.base.host}）：$e');
      if (mounted) {
        setState(() {
          ok = false;
          msg = '$e';
        });
      }
    } finally {
      c.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    final app = context.appRead;
    final s = DavServer(id: DavStore.newId(), name: name.text.trim().isEmpty ? davProviders[pv].$1 : name.text.trim(), url: WebDavClient.normalizeBase(url.text).toString(), user: user.text.trim(), root: _root);
    await app.dav.save(s, password: pass.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    toast('已添加 ${s.name}', 'check');
    push(context, DavBrowsePage(serverId: s.id, path: s.root));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SubPage(title: '添加服务器', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 4, Tk.pad, 10),
        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final (i, p) in davProviders.indexed) LChip(p.$1, on: i == pv, onTap: () => _pick(i))]),
      ),
      noteBox(context, 'info', davProviders[pv].$3),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 12, Tk.pad, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LField(controller: name, label: '名称', icon: 'edit'),
          const SizedBox(height: 10),
          LField(controller: url, label: '服务器地址', icon: 'globe', keyboard: TextInputType.url, onChanged: (_) => setState(() => ok = null)),
          const SizedBox(height: 10),
          LField(controller: user, label: '用户名', icon: 'user', onChanged: (_) => setState(() => ok = null)),
          const SizedBox(height: 10),
          LField(controller: pass, label: pv == 0 ? '应用密码' : '密码', icon: 'lock', password: true, onChanged: (_) => setState(() => ok = null)),
          const SizedBox(height: 10),
          LField(controller: root, label: '音乐目录（如 /Music）', icon: 'folder', onChanged: (_) => setState(() => ok = null)),
          if (ok != null) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(ok! ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: ok! ? pal.ok : pal.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: ts(13, c: ok! ? pal.ok : pal.danger, h: 1.5))),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Btn.sec('测试连接', icon: 'wifi', onTap: busy ? null : _test)),
            const SizedBox(width: 10),
            Expanded(child: Btn('保存', busy: busy, onTap: ok == true && !busy ? _save : null)),
          ]),
          const SizedBox(height: 8),
          Text('先测试连接，成功后才能保存。地址和密码只保存在本机钥匙串，不会上传。', style: ts(12, c: pal.t3, h: 1.6)),
          const SizedBox(height: 24),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- 浏览文件夹

class DavBrowsePage extends StatefulWidget {
  final String serverId, path;
  const DavBrowsePage({super.key, required this.serverId, required this.path});
  @override
  State<DavBrowsePage> createState() => _DavBrowsePageState();
}

class _DavBrowsePageState extends State<DavBrowsePage> {
  late Future<List<DavEntry>> f;
  String? _logged;

  @override
  void initState() {
    super.initState();
    f = _load();
  }

  Future<List<DavEntry>> _load() async {
    final c = context.appRead.dav.clientOf(widget.serverId);
    if (c == null) throw const DavException(DavErrorKind.other, '这台服务器已删除');
    try {
      return await c.list(widget.path);
    } catch (e) {
      AppLog.instance.add('音乐云盘', '列目录失败（${widget.path}）：$e');
      rethrow;
    } finally {
      c.close();
    }
  }

  String get _title {
    final p = widget.path.split('/').where((x) => x.isNotEmpty).toList();
    return p.isEmpty ? (context.appRead.dav.byId(widget.serverId)?.name ?? '音乐云盘') : p.last;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final server = app.dav.byId(widget.serverId);
    return SubPage(title: _title, children: [
      FutureBuilder<List<DavEntry>>(
        future: f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
          if (s.hasError) {
            return EmptyState('wifi', '没有读到这个文件夹', desc: '${s.error}', action: Btn.sec('重试', icon: 'refresh', small: true, onTap: () => setState(() {
                  _logged = null;
                  f = _load();
                })));
          }
          final all = s.data!;
          final dirs = all.where((e) => e.isDir).toList();
          final audio = all.where((e) => e.isAudio).toList();
          final other = all.length - dirs.length - audio.length;
          if (_logged != widget.path) {
            _logged = widget.path;
            final others = [for (final e in all) if (!e.isDir && !e.isAudio) e.name];
            AppLog.instance.add('音乐云盘', '列目录 ${widget.path}：${dirs.length} 个文件夹、${audio.length} 首${others.isEmpty ? '' : '，未列出 ${others.length} 个：${others.take(8).join('、')}'}');
          }
          if (server == null) return const EmptyState('cloud', '这台服务器已删除');
          // 登记进歌曲目录：之后可以收藏、加歌单、下载
          final ids = [for (final e in audio) app.library.register(DavStore.trackOf(server, e))];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 8),
              child: Text('${server.name} · ${widget.path}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t3)),
            ),
            if (ids.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 8),
                child: Row(children: [
                  Btn('播放全部', icon: 'play', small: true, onTap: () => app.play(ids.first, name: _title, ids: ids)),
                  const SizedBox(width: 8),
                  Btn.sec('随机', icon: 'shuffle', small: true, onTap: () {
                    final q = [...ids]..shuffle();
                    app.play(q.first, name: _title, ids: q);
                  }),
                ]),
              ),
            if (dirs.isNotEmpty)
              Group(children: [
                for (final d in dirs)
                  Item(icon: 'folder', color: 'orange', label: d.name, onTap: () => push(context, DavBrowsePage(serverId: widget.serverId, path: d.path))),
              ]),
            for (final (i, id) in ids.indexed)
              SongRow(songs[id], key: ValueKey('dav$id'), num: i, list: 'all', listName: _title, queue: ids, tail: Padding(padding: const EdgeInsets.only(right: 6), child: Text(audio[i].ext.toUpperCase(), style: ts(11, c: pal.t3)))),
            if (dirs.isEmpty && ids.isEmpty) const EmptyState('folder', '这个文件夹里没有可播放的音乐', desc: '支持 MP3、FLAC、M4A、AAC、WAV、OGG、Opus。'),
            if (other > 0) Hint('另有 $other 个其它文件（歌词、封面、不支持的格式）没有列出'),
          ]);
        },
      ),
    ]);
  }
}
