// 页面骨架：Tab 页（大标题折叠 + 回到顶部 + 下拉刷新）与二级页（52 顶栏 + 返回）。
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
import '../core/state.dart';
import '../core/tokens.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

const bottomSpace = 200.0;

/// 页面里的长列表（歌曲行）：固定行高、按需构建（只建看得到的和上下各一点），
/// 放在 [TabPage] / [SubPage] 的 children（头部）和 footer 之间。
/// [current] 返回正在播放的那首在列表里的下标（不在列表里返回 -1），用于「定位到正在播放」按钮。
class ListRows {
  final int count;
  final double extent;
  final Widget Function(BuildContext context, int index) builder;
  final int Function()? current;
  const ListRows({required this.count, required this.builder, this.extent = Tk.rowH, this.current});
}

/// 头部（[children]）+ 固定行高的长列表（[rows]）+ 尾部（[footer]）。rows 为空时退化成普通列表。
List<Widget> _slivers(List<Widget> children, ListRows? rows, List<Widget> footer, GlobalKey rowsKey) => [
      SliverList(delegate: SliverChildListDelegate(children)),
      if (rows != null && rows.count > 0)
        SliverFixedExtentList(key: rowsKey, itemExtent: rows.extent, delegate: SliverChildBuilderDelegate((c, i) => rows.builder(c, i), childCount: rows.count)),
      if (footer.isNotEmpty) SliverList(delegate: SliverChildListDelegate(footer)),
    ];

/// 「定位到正在播放」：正在播放的歌在列表里、但不在屏幕上时出现，点一下滚到它（居中）。
class LocateButton extends StatelessWidget {
  final ScrollController sc;
  final GlobalKey rowsKey;
  final ListRows? rows;
  final ValueListenable<double> y;
  final double topInset, bottomInset;
  const LocateButton({super.key, required this.sc, required this.rowsKey, required this.rows, required this.y, this.topInset = 0, this.bottomInset = 0});

  /// 目标行的滚动偏移（行顶）；拿不到返回 null。
  double? _rowTop(int i) {
    final ro = rowsKey.currentContext?.findRenderObject();
    // 还没布局过（第一帧 / 刚换了列表）时读 constraints 会抛异常
    if (ro is! RenderSliver || !ro.attached || ro.geometry == null) return null;
    return ro.constraints.precedingScrollExtent + i * rows!.extent;
  }

  @override
  Widget build(BuildContext context) {
    final r = rows;
    if (r == null || r.current == null || r.count == 0) return const SizedBox();
    final pal = context.pal;
    return ValueListenableBuilder<double>(
      valueListenable: y,
      builder: (context, v, _) {
        final i = r.current!();
        var show = false;
        if (i >= 0 && i < r.count && sc.hasClients && sc.positions.length == 1) {
          final top = _rowTop(i);
          final p = sc.position;
          if (top != null) show = top + r.extent < p.pixels + topInset || top > p.pixels + p.viewportDimension - bottomInset;
        }
        return AnimatedScale(
          duration: Tk.base,
          scale: show ? 1 : 0,
          curve: Tk.spring,
          child: Glass(
            radius: 21,
            color: pal.glassStrong,
            child: IBtn('locate', size: 42, color: pal.accText, onTap: () {
              final top = _rowTop(i);
              if (top == null || !sc.hasClients) return;
              final p = sc.position;
              final to = (top - (p.viewportDimension - r.extent) / 2).clamp(p.minScrollExtent, p.maxScrollExtent);
              sc.animateTo(to, duration: const Duration(milliseconds: 520), curve: Tk.out);
            }),
          ),
        );
      },
    );
  }
}

class TabPage extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final ScrollController? controller;
  final Future<void> Function()? onRefresh;
  final Widget? overlay;
  final double bottom;
  final ListRows? rows;
  final List<Widget> footer;
  const TabPage({super.key, required this.title, this.actions = const [], required this.children, this.controller, this.onRefresh, this.overlay, this.bottom = bottomSpace, this.rows, this.footer = const []});
  @override
  State<TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<TabPage> {
  late final ScrollController sc = widget.controller ?? ScrollController();
  final y = ValueNotifier<double>(0);
  final rowsKey = GlobalKey();

  void _l() {
    if (sc.positions.isNotEmpty) y.value = sc.positions.last.pixels;
  }

  @override
  void initState() {
    super.initState();
    sc.addListener(_l);
  }

  @override
  void dispose() {
    sc.removeListener(_l);
    if (widget.controller == null) sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final top = MediaQuery.of(context).padding.top;
    Widget list = CustomScrollView(
      controller: sc,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top)),
        ..._slivers([
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.pad, 10, 12, 8),
          child: ValueListenableBuilder<double>(
            valueListenable: y,
            builder: (_, v, ch) {
              final k = ((v - 10) / 50).clamp(0.0, 1.0);
              return Opacity(opacity: 1 - k, child: Transform.scale(scale: 1 - k * .08, alignment: Alignment.centerLeft, child: ch));
            },
            child: Row(children: [
              Expanded(child: Text(widget.title, style: ts(30, w: FontWeight.w800, c: pal.t1, ls: -.4))),
              ...widget.actions,
            ]),
          ),
        ),
        ...widget.children,
      ], widget.rows, widget.footer, rowsKey),
        SliverToBoxAdapter(child: SizedBox(height: widget.bottom)),
      ],
    );
    if (widget.onRefresh != null) {
      list = RefreshIndicator(onRefresh: widget.onRefresh!, color: pal.acc, backgroundColor: pal.s1, edgeOffset: top + 40, child: list);
    }
    return Stack(children: [
      Positioned.fill(child: list),
      // 紧凑标题栏（滚动后淡入）
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: ValueListenableBuilder<double>(
          valueListenable: y,
          builder: (_, v, __) {
            final k = ((v - 10) / 50).clamp(0.0, 1.0);
            if (k == 0) return const SizedBox();
            return IgnorePointer(
              ignoring: k < .5,
              child: Opacity(
                opacity: k,
                child: ClipRect(
                  child: backdrop(
                    context,
                    ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    Container(
                      height: top + 44,
                      padding: EdgeInsets.only(top: top),
                      color: reduceBlur(context) ? pal.bg : pal.bg.withValues(alpha: .78),
                      alignment: Alignment.center,
                      child: Text(widget.title, style: ts(16, w: FontWeight.w700, c: pal.t1)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // 定位到正在播放（在「回到顶部」上方）
      Positioned(
        right: 16,
        bottom: 176 + MediaQuery.of(context).padding.bottom - 34 + 52,
        child: LocateButton(sc: sc, rowsKey: rowsKey, rows: widget.rows, y: y, topInset: top + 44, bottomInset: 150),
      ),
      // 回到顶部
      Positioned(
        right: 16,
        bottom: 176 + MediaQuery.of(context).padding.bottom - 34,
        child: ValueListenableBuilder<double>(
          valueListenable: y,
          builder: (_, v, __) => AnimatedScale(
            duration: Tk.base,
            scale: v > 700 ? 1 : 0,
            curve: Tk.spring,
            child: Glass(
              radius: 21,
              color: pal.glassStrong,
              child: IBtn('up', size: 42, onTap: () {
                if (sc.positions.length == 1) sc.animateTo(0, duration: const Duration(milliseconds: 600), curve: Tk.out);
              }),
            ),
          ),
        ),
      ),
      if (widget.overlay != null) widget.overlay!,
    ]);
  }
}

/// 二级页：sticky 顶栏 + 内容。[hero] 为可选的顶部视差背景（歌单 / 歌手）。
class SubPage extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget Function(double y)? hero;
  final bool fadeTitle, dark;
  final double bottom;
  final Widget? floating;
  final ListRows? rows;
  final List<Widget> footer;
  const SubPage({super.key, required this.title, this.actions = const [], required this.children, this.hero, this.fadeTitle = false, this.bottom = bottomSpace, this.dark = false, this.floating, this.rows, this.footer = const []});
  @override
  State<SubPage> createState() => _SubPageState();
}

class _SubPageState extends State<SubPage> {
  final sc = ScrollController();
  final y = ValueNotifier<double>(0);
  final rowsKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    sc.addListener(() => y.value = sc.offset);
  }

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Stack(children: [
        if (widget.hero != null) ValueListenableBuilder<double>(valueListenable: y, builder: (_, v, __) => widget.hero!(v)),
        Positioned.fill(
          child: CustomScrollView(
            controller: sc,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: top + 52)),
              ..._slivers(widget.children, widget.rows, widget.footer, rowsKey),
              SliverToBoxAdapter(child: SizedBox(height: widget.bottom)),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: y,
            builder: (_, v, __) {
              final solid = widget.hero == null ? (v / 30).clamp(0.0, 1.0) : ((v - 200) / 60).clamp(0.0, 1.0);
              final tt = widget.fadeTitle ? ((v - 200) / 60).clamp(0.0, 1.0) : 1.0;
              return Container(
                height: top + 52,
                padding: EdgeInsets.only(top: top),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pal.bg.withValues(alpha: .96 * solid + (widget.hero == null ? .9 : 0)), pal.bg.withValues(alpha: solid * .9)]),
                ),
                child: Row(children: [
                  const SizedBox(width: 4),
                  IBtn('left', iconSize: 20, onTap: () => Navigator.of(context).maybePop()),
                  Expanded(child: Opacity(opacity: tt, child: Text(widget.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(17, w: FontWeight.w600, c: pal.t1)))),
                  if (widget.actions.isEmpty) const SizedBox(width: 44) else ...widget.actions,
                  const SizedBox(width: 4),
                ]),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 176 + MediaQuery.of(context).padding.bottom - 34,
          child: LocateButton(sc: sc, rowsKey: rowsKey, rows: widget.rows, y: y, topInset: top + 52, bottomInset: 150),
        ),
        if (widget.floating != null) widget.floating!,
      ]),
    );
  }
}

/// 页面内的 4 宫格快捷入口。
class QuickGrid extends StatelessWidget {
  final List<(String icon, String label, VoidCallback onTap)> items;
  const QuickGrid(this.items, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tk.pad, 18, Tk.pad, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final (i, l, f) in items)
          Press(
            onTap: f,
            scale: .92,
            child: SizedBox(
              width: 74,
              child: Column(children: [
                Container(width: 54, height: 54, decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line)), child: Icon(ic(i), color: pal.accText, size: 24)),
                const SizedBox(height: 7),
                Text(l, style: ts(12.5, w: FontWeight.w500, c: pal.t2)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 空状态：没有数据 / 功能还没接入时用，说清楚原因和下一步。
class EmptyState extends StatelessWidget {
  final String icon, title;
  final String? desc;
  final Widget? action;
  final EdgeInsets padding;
  const EmptyState(this.icon, this.title, {super.key, this.desc, this.action, this.padding = const EdgeInsets.fromLTRB(Tk.pad, 36, Tk.pad, 24)});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: padding,
      child: Column(children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(20)), child: Icon(ic(icon), size: 30, color: pal.t3)),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: ts(15.5, w: FontWeight.w700, c: pal.t1)),
        if (desc != null) ...[const SizedBox(height: 6), Text(desc!, textAlign: TextAlign.center, style: ts(13, c: pal.t3, h: 1.55))],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// QQ 号格式（与桌面端一致）：5~12 位数字，不以 0 开头。
final qqPattern = RegExp(r'^[1-9]\d{4,11}$');

/// QQ 头像地址（qlogo 公开接口，按 QQ 号取，不需要授权）。[s] 取 40 / 100 / 140 / 640。
String qqAvatarUrl(String qq, {int s = 640}) => 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=$s';

/// Lyra 账号头像：自定义头像 > 已绑定 QQ 的头像 > null（显示首字占位）。演示模式没有账号，返回 null。
/// 号码不合法时 qlogo 也会返回一张默认图，所以这里先按格式过滤。
String? avatarUrl(AppState app, {double size = 36}) {
  final acc = app.account;
  if (acc == null) return null;
  final custom = acc.avatarUrl?.trim();
  if (custom != null && (custom.startsWith('https://') || custom.startsWith('http://'))) return custom;
  final qq = acc.qq?.trim();
  if (qq == null || !qqPattern.hasMatch(qq)) return null;
  return qqAvatarUrl(qq, s: size > 40 ? 640 : 140);
}

/// 头像文字：Lyra 账号昵称首字；演示模式用「栗」。
String avatarText(AppState app) {
  final n = app.account?.nickname ?? '';
  if (n.isNotEmpty) return n.characters.first;
  return app.online ? 'L' : '栗';
}
