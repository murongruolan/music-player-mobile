// 公告弹窗。
//
// 规则：
// - 普通公告（popup = false）只出现在公告页，不弹窗。
// - 弹窗公告（popup = true）在进入主界面时弹出，多条时可以「上一条 / 下一条 / 全部已读」。
// - 可关闭公告（closable = true）：看到即视为已读；右上角 ✕ 或「全部已读」都能关闭。
// - 不可关闭公告（closable = false）：没有 ✕，返回键无效，「全部已读」也带不走它，
//   必须翻到这一条、停留 3 秒后点「我已知晓」单独确认。只要还有没确认的，弹窗就不会关闭。
//
// 数据与上报见 core/announcements.dart：弹窗里看过可关闭的上报 dismiss，公告页点开上报 read，「我已知晓」上报 confirm。
import 'dart:async';
import 'package:flutter/material.dart';
import '../api/announcement_api.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/markdown.dart';

bool _showing = false;

/// 弹出所有未读的弹窗公告；没有就什么都不做。
Future<void> showAnnouncementPopups(BuildContext context) async {
  final app = context.appRead;
  final items = app.anns.popups;
  if (items.isEmpty || _showing) return;
  _showing = true;
  final pal = context.pal;
  await showGeneralDialog<void>(
    context: rootNav.currentContext ?? context,
    barrierDismissible: false,
    barrierLabel: 'announcement',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (c, a, _, ch) {
      final t = Tk.softSpring.transform(a.value);
      return Opacity(opacity: a.value, child: Transform.scale(scale: .92 + .08 * t, child: ch));
    },
    pageBuilder: (ctx, _, __) => AppScope(state: app, child: PalScope(pal: pal, child: _AnnPopup(items: items))),
  );
  _showing = false;
}

/// 公告页里点开单条。
Future<void> showAnnouncementDetail(BuildContext context, Announcement a) {
  final app = context.appRead;
  final pal = context.pal;
  return showGeneralDialog<void>(
    context: rootNav.currentContext ?? context,
    barrierDismissible: a.closable || app.isRead(a),
    barrierLabel: 'announcement',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (c, an, _, ch) => Opacity(opacity: an.value, child: Transform.scale(scale: .94 + .06 * Tk.softSpring.transform(an.value), child: ch)),
    pageBuilder: (ctx, _, __) => AppScope(state: app, child: PalScope(pal: pal, child: _AnnPopup(items: [a], single: true))),
  );
}

class _AnnPopup extends StatefulWidget {
  final List<Announcement> items;
  final bool single;
  const _AnnPopup({required this.items, this.single = false});
  @override
  State<_AnnPopup> createState() => _AnnPopupState();
}

class _AnnPopupState extends State<_AnnPopup> {
  int i = 0, dir = 1, cd = 0;
  Timer? _t;

  List<Announcement> get items => widget.items;
  Announcement get cur => items[i];
  AppState get app => context.appRead;
  List<Announcement> get _locked => items.where((a) => !a.closable && !app.isRead(a)).toList();
  bool get _canClose => _locked.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  /// 可关闭的公告看过即已读：弹窗里上报 dismiss，公告页点开上报 read。
  AnnouncementAction get _seen => widget.single ? AnnouncementAction.read : AnnouncementAction.dismiss;

  /// 翻到某一条：可关闭的看到即已读；不可关闭的开始 3 秒阅读倒计时。
  void _enter() {
    if (!mounted) return;
    _t?.cancel();
    if (cur.closable) {
      app.anns.mark(cur, _seen);
      setState(() => cd = 0);
    } else if (!app.isRead(cur)) {
      setState(() => cd = 3);
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => cd--);
        if (cd <= 0) t.cancel();
      });
    }
  }

  void _go(int j) {
    if (j < 0 || j >= items.length || j == i) return;
    haptic(context);
    setState(() {
      dir = (j - i).sign;
      i = j;
    });
    _enter();
  }

  void _close() => Navigator.of(context).pop();

  void _ack() {
    app.anns.mark(cur, AnnouncementAction.confirm);
    final next = items.indexWhere((a) => !app.isRead(a));
    if (next < 0) return _close();
    _go(next);
  }

  void _readAll() {
    for (final a in items) {
      if (a.closable) app.anns.mark(a, _seen);
    }
    final locked = _locked;
    if (locked.isEmpty) return _close();
    toast('还有 ${locked.length} 条公告需要单独确认', 'lock');
    final j = items.indexOf(locked.first);
    if (j == i) {
      setState(() {});
    } else {
      _go(j);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.app; // 已读状态变化时重建
    final pal = context.pal;
    final n = items.length;
    final lockedHere = !cur.closable && !app.isRead(cur);
    final h = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: _canClose,
      onPopInvokedWithResult: (did, _) {
        if (!did) toast('请先确认需要确认的公告', 'lock');
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: pal.bgElev,
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // 顶部：类型 · 需确认 · 页码 · 关闭
                Row(children: [
                  Badge2(cur.type, acc: !cur.important, color: cur.important ? pal.danger : null),
                  if (!cur.closable) ...[const SizedBox(width: 6), Badge2(app.isRead(cur) ? '已确认' : '需确认', icon: app.isRead(cur) ? 'check' : 'lock', color: app.isRead(cur) ? pal.ok : pal.warn)],
                  const SizedBox(width: 8),
                  Text(cur.date, style: ts(12, c: pal.t3, num: true)),
                  const Spacer(),
                  if (n > 1) Text('${i + 1} / $n', style: ts(12.5, w: FontWeight.w600, c: pal.t2, num: true)),
                  SizedBox(
                    width: 40,
                    height: 36,
                    child: AnimatedOpacity(
                      duration: Tk.fast,
                      opacity: _canClose ? 1 : 0,
                      child: IgnorePointer(ignoring: !_canClose, child: IBtn('close', size: 36, iconSize: 18, color: pal.t2, onTap: _close)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                // 内容：左右滑动切换
                GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -300) _go(i + 1);
                    if (v > 300) _go(i - 1);
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Tk.out,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: Offset(.08 * dir, 0), end: Offset.zero).animate(a), child: c),
                    ),
                    layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, if (cur != null) cur]),
                    child: Column(
                      key: ValueKey(cur.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.only(right: 8), child: Text(cur.title, style: ts(19, w: FontWeight.w800, c: pal.t1, h: 1.35))),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: h * .46),
                          child: SingleChildScrollView(padding: const EdgeInsets.only(right: 8), child: MarkdownView(cur.body, style: ts(14, c: pal.t2, h: 1.7))),
                        ),
                      ],
                    ),
                  ),
                ),
                if (n > 1) ...[
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var k = 0; k < n; k++)
                      AnimatedContainer(
                        duration: Tk.base,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: k == i ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: k == i ? pal.acc : (app.isRead(items[k]) ? pal.t4 : (items[k].closable ? pal.t3 : pal.warn)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ]),
                ],
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    if (n > 1)
                      Row(children: [
                        Expanded(child: Btn.sec('上一条', small: true, onTap: i > 0 ? () => _go(i - 1) : null)),
                        const SizedBox(width: 8),
                        Expanded(child: Btn.sec('下一条', small: true, onTap: i < n - 1 ? () => _go(i + 1) : null)),
                        const SizedBox(width: 8),
                        Expanded(child: Btn('全部已读', small: true, kind: lockedHere ? BtnKind.sec : BtnKind.pri, onTap: _readAll)),
                      ]),
                    if (lockedHere) ...[
                      if (n > 1) const SizedBox(height: 10),
                      Btn(cd > 0 ? '我已知晓（$cd）' : '我已知晓', block: true, onTap: cd > 0 ? null : _ack),
                    ] else if (n == 1)
                      Btn(widget.single ? '关闭' : '我知道了', block: true, onTap: _close),
                  ]),
                ),
                if (lockedHere)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(ic('lock'), size: 13, color: pal.t3),
                      const SizedBox(width: 4),
                      Text('这条公告需要阅读并确认后才能关闭', style: ts(11.5, c: pal.t3)),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
