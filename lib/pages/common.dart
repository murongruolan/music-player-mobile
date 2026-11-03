// 页面骨架：Tab 页（大标题折叠 + 回到顶部 + 下拉刷新）与二级页（52 顶栏 + 返回）。
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

const bottomSpace = 200.0;

class TabPage extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final ScrollController? controller;
  final Future<void> Function()? onRefresh;
  final Widget? overlay;
  final double bottom;
  const TabPage({super.key, required this.title, this.actions = const [], required this.children, this.controller, this.onRefresh, this.overlay, this.bottom = bottomSpace});
  @override
  State<TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<TabPage> {
  late final ScrollController sc = widget.controller ?? ScrollController();
  final y = ValueNotifier<double>(0);

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
    Widget list = ListView(
      controller: sc,
      padding: EdgeInsets.only(top: top, bottom: widget.bottom),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
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
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      height: top + 44,
                      padding: EdgeInsets.only(top: top),
                      color: pal.bg.withValues(alpha: .78),
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
  const SubPage({super.key, required this.title, this.actions = const [], required this.children, this.hero, this.fadeTitle = false, this.bottom = bottomSpace, this.dark = false, this.floating});
  @override
  State<SubPage> createState() => _SubPageState();
}

class _SubPageState extends State<SubPage> {
  final sc = ScrollController();
  final y = ValueNotifier<double>(0);
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
          child: ListView(
            controller: sc,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.only(top: top + 52, bottom: widget.bottom),
            children: widget.children,
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

/// 头像文字：Lyra 账号昵称首字；演示模式用「栗」。
String avatarText(AppState app) {
  final n = app.account?.nickname ?? '';
  if (n.isNotEmpty) return n.characters.first;
  return app.online ? 'L' : '栗';
}
