// 账号备份与同步（赞助专属）：实时同步开关 / 状态、立即同步、云备份与恢复、分项手动同步。
// 非赞助用户：不发请求，显示引导激活的卡片（后端 /sync/* 对非赞助返回 403 / 40301）。
import 'package:flutter/material.dart';
import '../api/sync_api.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../net/net.dart';
import '../shell/shell.dart';
import '../sync/sync_doc.dart';
import '../sync/sync_engine.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'common.dart';
import 'misc.dart';
import 'settings.dart';

/// 非赞助用户看到的引导卡：说明功能、去账号中心输入激活码。
class SponsorGate extends StatelessWidget {
  final String feature;
  final String desc;
  const SponsorGate(this.feature, {super.key, this.desc = '激活赞助后可以使用多端实时同步、云备份和云端听歌统计。'});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return CardBox(
      margin: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(14)), child: Icon(ic('crown'), color: pal.accText)),
          const SizedBox(width: 12),
          Expanded(child: Text('「$feature」是赞助用户专属功能', style: ts(15, w: FontWeight.w700, c: pal.t1))),
        ]),
        const SizedBox(height: 10),
        Text(desc, style: ts(13, c: pal.t2, h: 1.6)),
        const SizedBox(height: 14),
        Btn('输入激活码', icon: 'key', block: true, onTap: () => push(context, const AccountPage())),
      ]),
    );
  }
}

/// 操作时遇到 40301 等情况的统一提示。
void toastApiError(Object e) {
  if (e is ApiException) {
    if (e.isCancelled) return;
    toast(e.code == ApiCode.forbidden ? '云同步是赞助用户专属功能，请先激活' : e.userMessage, e.isNetwork ? 'wifi' : 'info');
  } else {
    toast('操作失败，请稍后重试', 'info');
  }
}

String _ago(DateTime? t) {
  if (t == null) return '从未';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  return '${t.month}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _time(DateTime? t) => t == null ? '' : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(2)} MB' : '${(b / 1024).toStringAsFixed(b < 10240 ? 1 : 0)} KB';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool backing = false, syncing = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.online) return const _DemoBackupPage();
    final pal = context.pal;
    final status = app.cloud.status!;
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: status,
      builder: (context, st, _) {
        final (icon, color, title) = switch (st.phase) {
          _ when !app.isSponsor => ('crown', pal.warn, '需要赞助才能使用云同步'),
          SyncPhase.syncing => ('refresh', pal.acc, '正在同步…'),
          SyncPhase.idle => ('cloud', pal.ok, '云同步正常'),
          SyncPhase.offline => ('wifi', pal.warn, '网络不可用，恢复后自动同步'),
          SyncPhase.error => ('info', pal.danger, '同步出错'),
          SyncPhase.needSponsor => ('crown', pal.warn, '需要赞助才能使用云同步'),
          SyncPhase.off => ('cloud', pal.t3, app.set.cloudSync ? '实时同步未启动' : '实时同步已关闭'),
        };
        final sub = switch (st.phase) {
          SyncPhase.error => st.error ?? '请稍后重试',
          _ when !app.isSponsor => '激活后设置与音乐库会自动同步到你的其它设备',
          // 原型状态卡：收藏 / 歌单计数 + 最后同步时间
          _ => '收藏 ${app.liked.length} · 歌单 ${app.myPlaylists.length} · 最后同步 ${_ago(st.lastSyncAt)}${app.cloud.engine!.running ? (st.realtime ? ' · 实时通知已连接' : ' · 每 5 分钟检查') : ''}',
        };
        return SubPage(title: '备份与同步', children: [
          CardBox(
            margin: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 14),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)), child: Icon(ic(icon), color: color)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: ts(15, w: FontWeight.w700, c: pal.t1)), const SizedBox(height: 2), Text(sub, style: ts(12.5, c: pal.t2))])),
            ]),
          ),
          if (!app.isSponsor)
            const SponsorGate('账号备份与同步')
          else ...[
            Group(title: '账号云同步', children: [
              Item(icon: 'refresh', color: 'green', label: '多端实时同步', sub: '设置与音乐库自动同步到其它设备', sw: app.set.cloudSync, onSw: (v) => app.update(() => app.set.cloudSync = v)),
              Item(
                icon: 'cloud',
                color: 'teal',
                label: '立即同步',
                trailing: syncing ? const _Spin() : null,
                onTap: syncing ? null : _syncNow,
              ),
              Item(icon: 'cloud', color: 'blue', label: '立即备份到账号', sub: '云端保留最近 ${BackupApi.keep} 份', trailing: backing ? const _Spin() : null, onTap: backing ? null : _backupNow),
              Item(icon: 'history', color: 'gray', label: '历史备份', onTap: () => _history(context)),
            ]),
            Group(
              title: '分项同步',
              foot: '手动上传或从云端恢复某一类数据。音乐库、收藏、歌单、音源脚本会在本地音乐库接入后开放。',
              children: [
                for (final d in app.cloud.docs) _docItem(context, d),
              ],
            ),
          ],
          Press(onTap: () => push(context, const CloudPage()), child: noteBox(context, 'cloud', 'WebDAV 已移到「我的 → 音乐云盘」，可以直接浏览和播放 NAS 上的音乐。')),
        ]);
      },
    );
  }

  Widget _docItem(BuildContext context, SyncDoc d) {
    final app = context.appRead;
    final e = app.cloud.engine!;
    final st = e.stateOf(d.type);
    final live = e.live.contains(d.type);
    final sub = !d.available ? '暂未接入' : (st.revision > 0 ? '云端版本 ${st.revision}${live ? ' · 自动同步' : ''}' : (live ? '自动同步' : '手动同步'));
    final icon = switch (d.type) { DocType.settings => 'gear', DocType.listeningStats => 'chart', DocType.lxSources => 'code', DocType.favorites => 'heart', DocType.playlists => 'queue', _ => 'library' };
    return Item(
      icon: icon,
      color: d.available ? 'violet' : 'gray',
      label: d.label,
      sub: sub,
      onTap: d.available ? () => _docSheet(context, d) : () => toast('「${d.label}」会在本地音乐库接入后开放', 'info'),
    );
  }

  void _docSheet(BuildContext context, SyncDoc d) {
    final app = context.appRead;
    final e = app.cloud.engine!;
    showLSheet(context, title: d.label, sub: '云端同步', builder: (c) => Column(children: [
          Item(icon: 'up', color: 'blue', label: '上传本机到云端', sub: '用本机数据覆盖云端', onTap: () async {
            Navigator.of(c).pop();
            try {
              final r = await e.upload(d.type);
              toast('已上传 · 云端版本 ${r.revision}', 'cloud');
            } catch (err) {
              toastApiError(err);
            }
            if (mounted) setState(() {});
          }),
          Item(icon: 'refresh', color: 'teal', label: '与云端合并', sub: '两边的数据都保留', onTap: () async {
            Navigator.of(c).pop();
            try {
              final r = await e.download(d.type, replace: false);
              toast(r.changed ? '已合并云端数据' : '云端还没有这项数据', r.changed ? 'check' : 'info');
            } catch (err) {
              toastApiError(err);
            }
            if (mounted) setState(() {});
          }),
          Item(icon: 'down', color: 'orange', label: '从云端恢复', sub: '用云端数据覆盖本机', onTap: () {
            Navigator.of(c).pop();
            showLDialog(context, icon: 'down', title: '用云端覆盖本机的${d.label}？', body: '本机现有的${d.label}会被替换，此操作不可撤销。', actions: [
              ('取消', BtnKind.sec, null),
              ('覆盖', BtnKind.danger, () async {
                try {
                  final r = await e.download(d.type);
                  toast(r.changed ? '已从云端恢复' : '云端还没有这项数据', r.changed ? 'check' : 'info');
                } catch (err) {
                  toastApiError(err);
                }
                if (mounted) setState(() {});
              }),
            ]);
          }),
        ]));
  }

  Future<void> _syncNow() async {
    final app = context.appRead;
    final e = app.cloud.engine!;
    setState(() => syncing = true);
    try {
      if (!e.running) {
        // 开关关着也允许手动同步一次实时文档
        await e.start();
        if (!app.set.cloudSync) await e.stop();
      } else {
        await e.syncLive();
      }
      final st = e.status.value;
      if (st.phase == SyncPhase.idle || st.phase == SyncPhase.off) {
        toast('同步完成', 'check');
      } else {
        toast(st.error ?? '同步失败，请稍后重试', 'info');
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> _backupNow() async {
    final app = context.appRead;
    setState(() => backing = true);
    try {
      await app.cloud.backupNow();
      toast('备份完成', 'cloud');
    } catch (e) {
      toastApiError(e);
    } finally {
      if (mounted) setState(() => backing = false);
    }
  }

  void _history(BuildContext context) {
    final app = context.appRead;
    showLSheet(context, title: '历史备份', sub: '云端保留最近 ${BackupApi.keep} 份', builder: (c) => FutureBuilder<List<BackupMeta>>(
          future: app.cloud.backups(),
          builder: (c, snap) {
            final pal = c.pal;
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(30), child: Center(child: _Spin(size: 24)));
            }
            if (snap.hasError) {
              final e = snap.error;
              return Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(e is ApiException ? e.userMessage : '加载失败', style: ts(13.5, c: pal.t2))));
            }
            final l = snap.data!;
            if (l.isEmpty) return Padding(padding: const EdgeInsets.all(30), child: Center(child: Text('还没有备份，点「立即备份到账号」创建一份', style: ts(13.5, c: pal.t2))));
            return Column(children: [
              for (final b in l)
                Item(
                  icon: 'history',
                  color: 'gray',
                  label: _time(b.createdAt),
                  sub: '${b.deviceName.isEmpty ? '未知设备' : b.deviceName} · ${_size(b.size)}${b.appVersion.isEmpty ? '' : ' · v${b.appVersion}'}',
                  onTap: () {
                    Navigator.of(c).pop();
                    showLDialog(context, icon: 'history', title: '恢复这份备份？', body: '会用这份备份覆盖本机的设置与听歌统计，此操作不可撤销。', actions: [
                      ('取消', BtnKind.sec, null),
                      ('恢复', BtnKind.pri, () async {
                        try {
                          final done = await app.cloud.restore(b.id);
                          toast(done.isEmpty ? '这份备份里没有本机可恢复的内容' : '已恢复：${done.join('、')}', done.isEmpty ? 'info' : 'check');
                        } catch (e) {
                          toastApiError(e);
                        }
                      }),
                    ]);
                  },
                ),
            ]);
          },
        ));
  }
}

class _Spin extends StatelessWidget {
  final double size;
  const _Spin({this.size = 18});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(width: size, height: size, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.acc)),
      );
}

/// 演示模式（截图 / 测试）：原来的 mock 页面。
class _DemoBackupPage extends StatelessWidget {
  const _DemoBackupPage();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return SubPage(title: '备份与同步', children: [
      CardBox(
        margin: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 14),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: pal.ok.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)), child: Icon(ic('cloud'), color: pal.ok)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('云同步正常', style: ts(15, w: FontWeight.w700, c: pal.t1)), Text('收藏 ${app.liked.length} · 歌单 ${app.myPlaylists.length} · 最后同步 刚刚', style: ts(12.5, c: pal.t2))])),
        ]),
      ),
      Group(title: '账号云同步', children: [
        Item(icon: 'refresh', color: 'green', label: '多端实时同步', sub: '收藏、歌单、播放进度', sw: app.set.cloudSync, onSw: (v) => app.update(() => app.set.cloudSync = v)),
        Item(icon: 'cloud', color: 'blue', label: '立即备份到账号', onTap: () => toast('备份完成 · 1.2 MB', 'cloud')),
        Item(icon: 'history', color: 'gray', label: '历史备份', val: '3 份', onTap: () => _history(context)),
      ]),
      Press(onTap: () => push(context, const CloudPage()), child: noteBox(context, 'cloud', 'WebDAV 已移到「我的 → 音乐云盘」，可以直接浏览和播放 NAS 上的音乐。')),
    ]);
  }

  void _history(BuildContext context) {
    showLSheet(context, title: '历史备份', sub: '3 份', builder: (c) => Column(children: [
          for (var i = 0; i < 3; i++)
            Item(icon: 'history', color: 'gray', label: '2026-11-0${2 - i} ${['09:12', '03:00', '21:40'][i]}', sub: '${(1.2 - i * .02).toStringAsFixed(2)} MB · iPhone 15 Pro', onTap: () {
              Navigator.of(c).pop();
              showLDialog(context, icon: 'history', title: '恢复这份备份？', body: '会用这份备份覆盖本机的设置与听歌统计', actions: [('取消', BtnKind.sec, null), ('恢复', BtnKind.pri, () => toast('已恢复', 'check'))]);
            }),
        ]));
  }
}
