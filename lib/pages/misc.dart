// 其它二级页：公告 · 平台账号 · 下载管理 · 账号中心 · 登录设备 · 音乐云盘（WebDAV）· 关于与更新。备份与同步在 backup.dart。
import 'package:flutter/material.dart';
import '../api/announcement_api.dart';
import '../api/account_api.dart';
import '../api/devices_api.dart';
import '../auth/auth.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../net/api_config.dart';
import '../net/net.dart';
import '../shell/shell.dart';
import '../ui/brand.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/markdown.dart';
import '../widgets/announce.dart';
import '../widgets/sheets.dart';
import 'common.dart';
import 'scan.dart';
import 'settings.dart';

export 'backup.dart' show BackupPage;

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});
  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  @override
  void initState() {
    super.initState();
    // 进页面拉一次（启动时已经拉过，这里拿最新的）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.appRead.anns.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final list = app.anns.items;
    final locked = list.where((a) => !a.closable && !app.isRead(a)).length;
    return SubPage(
      title: '公告',
      actions: [
        if (app.anns.loading)
          const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          IBtn('refresh', onTap: () async {
            if (!app.online) {
              // 演示：把弹窗公告重置为未读，再弹一次
              app.update(() => app.anns.read.removeWhere((id) => list.any((a) => a.id == id && a.popup)));
              showAnnouncementPopups(context);
              return;
            }
            await app.anns.load();
            if (context.mounted) showAnnouncementPopups(context);
          }),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 12),
          child: Row(children: [
            Expanded(child: Text(app.unread > 0 ? '${app.unread} 条未读' : '全部已读', style: ts(13, c: pal.t2))),
            if (app.unread > 0)
              Btn.sec('全部标为已读', small: true, onTap: () {
                for (final a in list) {
                  if (a.closable) app.anns.mark(a, AnnouncementAction.read);
                }
                if (locked > 0) toast('有 $locked 条公告需要点开单独确认', 'lock');
              }),
          ]),
        ),
        if (list.isEmpty && !app.anns.loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(children: [Icon(ic('bell'), size: 40, color: pal.t4), const SizedBox(height: 10), Text('暂无公告', style: ts(14, c: pal.t3))]),
          ),
        for (final (i, a) in list.indexed)
          Rise(
            i,
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CardBox(
                onTap: () => showAnnouncementDetail(context, a),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Badge2(a.type, acc: !a.important, color: a.important ? pal.danger : null),
                    if (a.popup) ...[const SizedBox(width: 6), const Badge2('弹窗', icon: 'bell')],
                    if (!a.closable) ...[const SizedBox(width: 6), Badge2(app.isRead(a) ? '已确认' : '需确认', icon: app.isRead(a) ? 'check' : 'lock', color: app.isRead(a) ? pal.ok : pal.warn)],
                    const SizedBox(width: 8),
                    Text(a.date, style: ts(12, c: pal.t3, num: true)),
                    const Spacer(),
                    AnimatedOpacity(duration: Tk.base, opacity: app.isRead(a) ? 0 : 1, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: pal.danger, shape: BoxShape.circle))),
                  ]),
                  const SizedBox(height: 8),
                  Text(a.title, style: ts(16, w: FontWeight.w700, c: app.isRead(a) ? pal.t2 : pal.t1)),
                  const SizedBox(height: 4),
                  Text(markdownPlain(a.body), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t3, h: 1.6)),
                ]),
              ),
            ),
          ),
        Hint(app.online
            ? '重要和置顶公告会在进入 App 时弹出，带「需确认」的必须单独点「我已知晓」。'
            : '普通公告只在这里显示；带「弹窗」的会在进入 App 时弹出，带「需确认」的必须单独点「我已知晓」。右上角可重新演示弹窗。'),
      ],
    );
  }
}

class PlatAccountsPage extends StatelessWidget {
  const PlatAccountsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return SubPage(title: '平台账号', children: [
      noteBox(context, 'link', '登录平台账号后可同步该平台的收藏、歌单与每日推荐。账号凭据只保存在本机。'),
      Group(title: '平台', children: [
        for (final p in platforms)
          Item(
            lead: PlatBadge(p, size: 30),
            label: p.name,
            sub: app.isIn(p.id) ? '已登录 · ${app.platLogin[p.id]}' : '未登录',
            trailing: app.isIn(p.id)
                ? Btn.sec('退出', small: true, onTap: () => showLDialog(context, icon: 'logout', iconColor: pal.danger, title: '退出${p.name}？', body: '退出后该平台的每日推荐、个人歌单将不可用', actions: [
                      ('取消', BtnKind.sec, null),
                      ('退出', BtnKind.danger, () {
                        app.logout(p.id);
                        toast('已退出 ${p.name}', 'logout');
                      }),
                    ]))
                : Btn('登录', small: true, onTap: () => openPlatLogin(context, p.id)),
          ),
      ]),
      Group(title: '登录方式', children: [
        Item(icon: 'scan', color: 'violet', label: '扫码登录', sub: '用对应平台 App 扫码', onTap: () => openPlatLogin(context, app.plat)),
        Item(icon: 'phone', color: 'orange', label: '手机号登录', onTap: () => openPlatLogin(context, app.plat, mode: '手机号')),
        Item(icon: 'code', color: 'gray', label: '导入 Cookie', sub: '高级：从浏览器复制', onTap: () => openPlatLogin(context, app.plat, mode: 'Cookie')),
      ]),
    ]);
  }
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final paused = <int>{};
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.set;
    return SubPage(title: '下载管理', children: [
      if (app.online) const EmptyState('download', '暂无下载任务', desc: '下载需要先接入音源解析，接入后可以在歌曲的「···」里下载。'),
      if (!app.online) Padding(padding: const EdgeInsets.fromLTRB(Tk.pad, 0, 0, 6), child: Text('正在下载 · 2', style: ts(12.5, w: FontWeight.w600, c: pal.t3))),
      if (!app.online)
      for (final (id, p, t) in const [(13, .62, '12.4 / 20.1 MB'), (20, .18, '6.0 / 33.6 MB')])
        SizedBox(
          height: 70,
          child: Row(children: [
            const SizedBox(width: Tk.pad),
            Cover.song(songs[id], size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(songs[id].title, style: ts(15, w: FontWeight.w600, c: pal.t1)),
                const SizedBox(height: 7),
                ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: p, minHeight: 4, color: paused.contains(id) ? pal.t3 : pal.acc, backgroundColor: pal.s3)),
                const SizedBox(height: 5),
                Text('${paused.contains(id) ? '已暂停 · ' : ''}$t · ${songs[id].quality}', style: ts(12, c: pal.t3)),
              ]),
            ),
            IBtn(paused.contains(id) ? 'play' : 'pause', color: pal.t3, onTap: () => setState(() => paused.contains(id) ? paused.remove(id) : paused.add(id))),
            const SizedBox(width: 6),
          ]),
        ),
      const SizedBox(height: 14),
      Group(title: '设置', children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: LSlider(label: '同时下载', value: s.dlConc, min: 1, max: 8, step: 1, fmt: (v) => '${v.round()} 首', onChanged: (v) => app.update(() => s.dlConc = v))),
        Item(icon: 'edit', color: 'violet', label: '文件命名', val: '歌名 - 歌手', onTap: () => toast('可选顺序与分隔符，非法字符自动替换', 'edit')),
        Item(icon: 'album', color: 'orange', label: '内嵌封面与标签', sub: 'FLAC / MP3 / M4A 自动写入元数据', sw: s.dlCover, onSw: (v) => app.update(() => s.dlCover = v)),
        Item(icon: 'quote', color: 'pink', label: '另存歌词与封面文件', sub: '同目录生成 .lrc 与 cover.jpg', sw: s.dlLyric, onSw: (v) => app.update(() => s.dlLyric = v)),
        Item(icon: 'folder', color: 'blue', label: '保存位置', val: '/Music/Lyra', onTap: () => toast('选择文件夹', 'folder')),
        Item(icon: 'wifi', color: 'cyan', label: '仅 Wi-Fi 下载', sw: s.wifiOnly, onSw: (v) => app.update(() => s.wifiOnly = v)),
      ]),
    ]);
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  int deviceCount = -1; // -1：还没拉到（演示 / 截图），展示 mock 数量
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 拉取用户资料与设备数。演示 / 截图（net == null）时保持 mock，不发请求。
  Future<void> _load() async {
    final net = context.appRead.net;
    if (net == null) return;
    final app = context.appRead;
    try {
      final acc = await AccountApi(net.client).profile();
      if (!mounted) return;
      app.update(() => app.account = acc);
    } on ApiException catch (e) {
      if (mounted && !e.isCancelled) toast(e.userMessage, 'info');
    }
    try {
      final dl = await DevicesApi(net.client).list();
      if (!mounted) return;
      setState(() => deviceCount = dl.devices.length);
    } on ApiException catch (_) {
      // 设备数拉不到不阻塞页面，进「登录设备」页会有完整报错
    }
  }

  /// 统一的「执行 + 错误提示」包装：busy 期间不重复提交，业务错误直接展示后端文案。
  Future<void> _guard(Future<void> Function() f, {String okMsg = ''}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
      if (okMsg.isNotEmpty && mounted) toast(okMsg, 'check');
    } on ApiException catch (e) {
      if (mounted && !e.isCancelled) toast(e.userMessage, 'info');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final acc = app.account;
    final name = acc?.nickname ?? (app.online ? 'Lyra 用户' : '阿栗');
    final activated = acc?.isActivated ?? !app.online;
    final memberName = (acc?.membershipName.isNotEmpty ?? false) ? acc!.membershipName : (acc == null ? '已激活 · 永久' : '已激活');
    return SubPage(title: '账号中心', children: [
      Column(children: [
        Avatar(name.isEmpty ? 'L' : name.characters.first, size: 84),
        const SizedBox(height: 12),
        Text(name, style: ts(20, w: FontWeight.w700, c: pal.t1)),
        Text(acc == null ? (app.online ? '' : 'UID 10086427 · ali@example.com') : 'UID ${acc.uid} · ${acc.email}', style: ts(12.5, c: pal.t2, num: true)),
        const SizedBox(height: 10),
        Badge2(memberName, acc: activated, icon: 'crown', color: activated ? null : pal.warn),
        const SizedBox(height: 18),
      ]),
      Group(title: '资料', children: [
        Item(icon: 'user', color: 'blue', label: '昵称与头像', val: name, onTap: () => _editNickname(context)),
        Item(icon: 'mail', color: 'orange', label: '邮箱', val: acc?.email ?? (app.online ? '' : 'ali@example.com')),
        Item(icon: 'lock', color: 'gray', label: '修改密码', sub: '重置密码接口暂未开放，可从登录页「忘记密码」入口查看进度', onTap: () => toast('重置密码接口暂未开放', 'info')),
        Item(icon: 'link', color: 'cyan', label: 'QQ 绑定', val: (acc?.qq?.isNotEmpty ?? false) ? '已绑定 ${acc!.qq}' : '未绑定', onTap: () => _editQQ(context)),
      ]),
      Group(title: '会员', children: [
        Item(icon: 'key', color: 'gold', label: '激活码', sub: activated ? '输入升级码提升会员等级' : '输入激活码解锁全部功能', onTap: () => _activate(context)),
        Item(icon: 'crown', color: 'pink', label: '会员权益', val: '6 项', onTap: () => toast('Hi-Res 下载 · 粒子皮肤 · 云同步 …', 'crown')),
      ]),
      Group(title: '安全', children: [
        Item(icon: 'phone', color: 'violet', label: '登录设备', val: deviceCount < 0 ? (app.online ? null : '${loginDevices.length} 台') : '$deviceCount 台', onTap: () => push(context, const DevicesPage())),
        Item(icon: 'scan', color: 'teal', label: '扫码登录电视 / 车机 / 桌面端', onTap: () => pushFull(context, const ScanPage())),
      ]),
      Group(children: [
        Item(icon: 'logout', color: 'red', label: '退出登录', danger: true, chev: false, onTap: () => showLDialog(context, icon: 'logout', iconColor: pal.danger, title: '退出登录？', body: '本机的收藏与歌单会保留，下次登录后自动同步', actions: [
              ('取消', BtnKind.sec, null),
              ('退出', BtnKind.danger, () async {
                popToRoot();
                app.signOut(); // 通知服务端作废令牌 + 清空会话（网络层统一处理）
              }),
            ])),
      ]),
    ]);
  }

  /// 修改昵称（≤64 字符，与后端一致）。
  Future<void> _editNickname(BuildContext context) async {
    final acc = context.appRead.account;
    final tc = TextEditingController(text: acc?.nickname ?? '');
    final r = await showLSheet(context, title: '修改昵称', builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            LField(controller: tc, label: '昵称', icon: 'user', autofocus: true),
            const SizedBox(height: 14),
            Btn('保存', block: true, onTap: () => Navigator.of(c).pop(tc.text)),
          ]),
        ));
    final nickname = (r as String?)?.trim() ?? '';
    if (nickname.isEmpty || nickname == acc?.nickname) return;
    if (nickname.characters.length > 64) return toast('昵称不能超过 64 个字符', 'info');
    await _guard(() async {
      final app = context.appRead;
      final nu = await AccountApi(app.api.client).updateProfile(nickname: nickname);
      app.update(() => app.account = nu);
    }, okMsg: '已保存');
  }

  /// 绑定 / 解绑 QQ（≤12 位数字，与后端一致）。
  Future<void> _editQQ(BuildContext context) async {
    final app = context.appRead;
    final cur = app.account?.qq;
    if (cur != null && cur.isNotEmpty) {
      showLDialog(context, icon: 'link', title: '解绑 QQ？', body: '解绑后可以绑定其他 QQ 号', actions: [
        ('取消', BtnKind.sec, null),
        ('解绑', BtnKind.danger, () => _guard(() async {
              final nu = await AccountApi(app.api.client).bindQQ(null);
              app.update(() => app.account = nu);
            }, okMsg: '已解绑')),
      ]);
      return;
    }
    final tc = TextEditingController();
    final r = await showLSheet(context, title: '绑定 QQ', builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            LField(controller: tc, label: 'QQ 号', icon: 'link', keyboard: TextInputType.number, autofocus: true),
            const SizedBox(height: 14),
            Btn('绑定', block: true, onTap: () => Navigator.of(c).pop(tc.text)),
          ]),
        ));
    final qq = (r as String?)?.trim() ?? '';
    if (qq.isEmpty) return;
    if (qq.length > 12 || !RegExp(r'^\d+$').hasMatch(qq)) return toast('QQ 号格式不正确', 'info');
    await _guard(() async {
      final nu = await AccountApi(app.api.client).bindQQ(qq);
      app.update(() => app.account = nu);
    }, okMsg: '已绑定');
  }

  /// 激活码 / 升级码兑换。激活 / 升级成功后返回带新会员态的用户。
  Future<void> _activate(BuildContext context) async {
    final app = context.appRead;
    if (app.net == null) return toast('演示模式，不发起请求', 'info');
    final tc = TextEditingController();
    final r = await showLSheet(context, title: '激活码', builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            LField(controller: tc, label: '输入激活码', icon: 'key', autofocus: true),
            const SizedBox(height: 14),
            Btn('激活', block: true, onTap: () => Navigator.of(c).pop(tc.text)),
          ]),
        ));
    final code = (r as String?)?.trim() ?? '';
    if (code.isEmpty) return;
    await _guard(() async {
      final nu = await AccountApi(app.api.client).redeemCode(code);
      app.update(() => app.account = nu);
      if (mounted) toast('激活成功 · ${nu.membershipName.isEmpty ? '会员' : nu.membershipName}', 'crown');
    });
  }
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<DeviceRecord> devices = const [];
  int maxDevices = 10;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 演示 / 截图（net == null）时用 mock 的 loginDevices；连着后端时只显示接口数据（加载中 / 失败为空，不显示假设备）。
  List<DeviceRecord> get _view => context.appRead.online ? devices : [for (final (i, d) in loginDevices.indexed) _mock(d, i)];

  DeviceRecord _mock(Device d, int i) => DeviceRecord(
        id: i,
        deviceName: d.name,
        platform: d.os.contains('TV') ? 'android_tv' : d.os.contains('Windows') ? 'windows' : 'ios',
        systemVersion: d.os,
        lastSeenAt: d.current ? '' : d.last,
        isCurrent: d.current,
      );

  Future<void> _load() async {
    final net = context.appRead.net;
    if (net == null) return;
    setState(() => loading = true);
    try {
      final dl = await DevicesApi(net.client).list();
      if (!mounted) return;
      setState(() {
        devices = dl.devices;
        maxDevices = dl.maxDevices;
      });
    } on ApiException catch (e) {
      if (mounted && !e.isCancelled) toast(e.userMessage, 'info');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _remove(DeviceRecord d) async {
    final app = context.appRead;
    if (app.net == null) return toast('演示模式，不发起请求', 'info');
    if (loading) return;
    setState(() => loading = true);
    try {
      await DevicesApi(app.api.client).remove(d.id);
      if (!mounted) return;
      toast('已移除 ${d.deviceName}', 'logout');
      await _load();
    } on ApiException catch (e) {
      if (mounted && !e.isCancelled) toast(e.userMessage, 'info');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 最近在线时间：相对时间（后端 lastSeenAt 是 RFC3339）。
  String _lastSeen(DeviceRecord d) {
    if (d.isCurrent) return '当前在线';
    final t = DateTime.tryParse(d.lastSeenAt)?.toLocal();
    if (t == null) return d.lastSeenAt.isEmpty ? '' : d.lastSeenAt;
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚在线';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} 在线';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final list = _view;
    return SubPage(title: '登录设备', children: [
      Hint('最多同时登录 $maxDevices 台设备。移除后该设备需要重新登录。', padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 12)),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text('没有拿到设备列表，返回后重试', style: ts(13.5, c: pal.t3))),
        )
      else
        Group(children: [
        for (final d in list)
          Item(
            lead: Container(width: 30, height: 30, decoration: BoxDecoration(color: d.isCurrent ? settingTiles['green'] : settingTiles['gray'], borderRadius: BorderRadius.circular(9)), child: Icon(ic(d.isTv ? 'tv' : d.isDesktop ? 'grid' : 'phone'), size: 18, color: Colors.white)),
            label: d.deviceName,
            sub: [d.systemVersion, _lastSeen(d)].where((s) => s.isNotEmpty).join(' · '),
            trailing: d.isCurrent
                ? const Badge2('本机', acc: true)
                : Btn('移除', small: true, kind: BtnKind.danger, onTap: loading ? null : () => showLDialog(context, icon: 'logout', iconColor: pal.danger, title: '移除「${d.deviceName}」？', body: '该设备需要重新登录', actions: [('取消', BtnKind.sec, null), ('移除', BtnKind.danger, () => _remove(d))])),
          ),
      ]),
    ]);
  }
}

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});
  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  String seg = '音乐';
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    if (app.online) {
      return SubPage(title: '音乐云盘', children: [
        const EmptyState('cloud', 'WebDAV 云盘接入中', desc: '连接坚果云 / Alist / Nextcloud / 群晖，直接播放 NAS 上的音乐、备份收藏和歌单。\n浏览和播放需要本地播放器接入后才能用，正在开发。'),
      ]);
    }
    return SubPage(title: '音乐云盘', actions: [IBtn('plus', onTap: () => _davAdd(context))], children: [
      CardBox(
        margin: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 12),
        child: Row(children: [
          Stack(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(14)), child: Icon(ic('cloud'), color: pal.accText)),
            Positioned(right: 2, bottom: 2, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: pal.ok, shape: BoxShape.circle, border: Border.all(color: pal.s1, width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('家里的 NAS', style: ts(15, w: FontWeight.w700, c: pal.t1)), Text('WebDAV · dav.example.com · 已连接 86ms', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: pal.t3))])),
          Btn.sec('测试', small: true, onTap: () => toast('连接正常 · 延迟 86ms', 'wifi')),
        ]),
      ),
      Seg(const ['音乐', '备份'], seg, (v) => setState(() => seg = v)),
      if (seg == '音乐') ...[
        const Hint('直接播放 WebDAV 上的音乐文件，歌词和封面读取同目录文件；不经过任何平台。', padding: EdgeInsets.fromLTRB(Tk.pad, 10, Tk.pad, 10)),
        Group(title: '/Music', children: [for (final f in davFolders) Item(icon: 'folder', color: 'blue', label: f[0], sub: f[1], onTap: () => toast('打开 /Music/${f[0]}', 'folder'))]),
        Padding(padding: const EdgeInsets.fromLTRB(Tk.pad, 0, 0, 4), child: Text('最近添加', style: ts(12.5, w: FontWeight.w600, c: pal.t3))),
        for (final (i, id) in const [3, 14, 18, 21, 6].indexed) SongRow(songs[id], list: 'all', tail: Padding(padding: const EdgeInsets.only(right: 14), child: Badge2(const ['FLAC', 'FLAC', 'MP3', 'FLAC', 'M4A'][i]))),
      ] else ...[
        const SizedBox(height: 14),
        Group(title: '收藏与歌单备份', foot: '备份内容为收藏与歌单 JSON，不包含音频文件', children: [
          Item(icon: 'refresh', color: 'teal', label: '每天自动备份', sub: '凌晨 3:00 · 只在 Wi-Fi 下', sw: app.set.autoBackup, onSw: (v) => app.update(() => app.set.autoBackup = v)),
          Item(icon: 'cloud', color: 'blue', label: '立即备份', onTap: () => toast('已上传 lyra-backup-20261102.json', 'cloud')),
          Item(icon: 'download', color: 'orange', label: '从备份恢复', val: '12 份', onTap: () => toast('恢复前会先备份当前数据', 'info')),
        ]),
        Group(title: '服务器', children: [
          Item(icon: 'globe', color: 'violet', label: '家里的 NAS', sub: 'dav.example.com · ali', val: '当前', onTap: () => _davAdd(context)),
          Item(icon: 'plus', color: 'gray', label: '添加服务器', sub: '坚果云 / Alist / Nextcloud / 群晖', onTap: () => _davAdd(context)),
        ]),
      ],
    ]);
  }

  void _davAdd(BuildContext context) {
    var pv = 0;
    const urls = ['https://dav.jianguoyun.com/dav/', 'https://alist.example.com/dav/', 'https://cloud.example.com/remote.php/dav/', 'https://nas.local:5006/', 'https://'];
    final url = TextEditingController(text: urls[0]);
    showLSheet(context, title: '添加 WebDAV 服务器', sub: '选择服务商自动填好地址', builder: (c) => StatefulBuilder(builder: (c, set) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: Column(children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (i, n) in const ['坚果云', 'Alist', 'Nextcloud', '群晖', '自定义'].indexed)
                  LChip(n, on: pv == i, onTap: () => set(() {
                        pv = i;
                        url.text = urls[i];
                      })),
              ]),
              const SizedBox(height: 12),
              LField(controller: url, label: '服务器地址', icon: 'globe'),
              const SizedBox(height: 10),
              const LField(label: '用户名', icon: 'user'),
              const SizedBox(height: 10),
              const LField(label: '密码 / 应用专用密码', icon: 'lock', password: true),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Btn.sec('取消', onTap: () => Navigator.of(c).pop())),
                const SizedBox(width: 8),
                Expanded(child: Btn.sec('测试', onTap: () => toast('连接成功 · 延迟 92ms', 'wifi'))),
                const SizedBox(width: 8),
                Expanded(child: Btn('保存', onTap: () {
                  Navigator.of(c).pop();
                  toast('已添加服务器', 'cloud');
                })),
              ]),
            ]),
          );
        }));
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _checkUpdate(BuildContext context) async {
    final app = context.appRead;
    toast('正在检查更新…', 'refresh');
    await app.checkUpdate();
    final r = app.updateInfo;
    if (!context.mounted) return;
    if (r == null) return toast('检查失败，请稍后重试', 'info');
    final l = r.latest;
    if (!r.hasUpdate || l == null) return toast('已是最新版本 v${ApiConfig.appVersion}', 'check');
    showLDialog(context, icon: 'download', title: '发现新版本 v${l.version}', body: l.notes.isEmpty ? '当前 v${ApiConfig.appVersion}' : l.notes, actions: [('稍后', BtnKind.sec, null), ('立即更新', BtnKind.pri, () => openUpdateUrl(l.url))]);
  }
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return SubPage(title: '关于与更新', children: [
      Column(children: [
        const SizedBox(height: 10),
        const AppLogo(size: 72),
        const SizedBox(height: 14),
        Text('Lyra', style: ts(20, w: FontWeight.w800, c: pal.t1)),
        Text(app.online ? 'v${ApiConfig.appVersion} (${ApiConfig.buildNumber})' : 'v2.4.0 (2401) · 稳定版', style: ts(12.5, c: pal.t2)),
        const SizedBox(height: 22),
      ]),
      Group(children: [
        if (app.online)
          Item(icon: 'refresh', color: 'green', label: '检查更新', val: app.updateInfo?.hasUpdate == true ? '有新版本 v${app.updateInfo!.latest?.version ?? ''}' : null, onTap: () => _checkUpdate(context))
        else
          Item(icon: 'refresh', color: 'green', label: '检查更新', val: '有新版本', onTap: () => showLDialog(context, icon: 'download', title: '发现新版本 v2.5.0', body: '· 新增 4 套皮肤\n· 底部搜索栏\n· 修复若干问题', actions: [('稍后', BtnKind.sec, null), ('立即更新', BtnKind.pri, () => toast('正在下载更新包…', 'download'))])),
        Item(icon: 'bell', color: 'orange', label: '公告历史', onTap: () => push(context, const AnnouncementsPage())),
        Item(icon: 'info', color: 'blue', label: '使用须知', onTap: () => pushFull(context, const DisclaimerPage(readOnly: true))),
        if (!app.online) Item(icon: 'info', color: 'red', label: '版本停用页（演示）', onTap: () => pushFull(context, const VersionDisabledPage())),
      ]),
      if (!app.online)
      Group(title: '诊断', children: [
        Item(icon: 'bug', color: 'red', label: '崩溃报告', val: '0 条', onTap: () => toast('没有崩溃记录', 'check')),
        Item(icon: 'bug', color: 'gray', label: '自动上报崩溃', sw: app.set.crash, onSw: (v) => app.update(() => app.set.crash = v)),
        Item(icon: 'code', color: 'gray', label: '应用日志', onTap: () => toast('日志已复制，可发给开发者', 'copy')),
        Item(icon: 'trash', color: 'gray', label: '清除缓存', val: '1.8 GB', onTap: () => showLDialog(context, icon: 'trash', title: '清除 1.8 GB 缓存？', body: '已下载的歌曲不受影响', actions: [('取消', BtnKind.sec, null), ('清除', BtnKind.danger, () => toast('已清除 1.8 GB', 'trash'))])),
      ]),
      const Hint('© 2026 Lyra · 开源许可', align: TextAlign.center),
    ]);
  }
}
