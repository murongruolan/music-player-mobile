// 音源选择器：源条（平台 → 解析脚本）+ 从源条位置向下展开的形变面板。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../pages/settings.dart';
import '../shell/shell.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

class SourceBar extends StatefulWidget {
  final bool compact;
  const SourceBar({super.key, this.compact = false});
  @override
  State<SourceBar> createState() => _SourceBarState();
}

class _SourceBarState extends State<SourceBar> with SingleTickerProviderStateMixin {
  late final sweep = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  final key = GlobalKey();
  bool open = false;
  @override
  void dispose() {
    sweep.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final box = key.currentContext!.findRenderObject() as RenderBox;
    final r = box.localToGlobal(Offset.zero) & box.size;
    setState(() => open = true);
    await showPicker(context, r);
    if (mounted) setState(() => open = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final p = app.platform, sc = app.curScript;
    final h = widget.compact ? 40.0 : 54.0;
    return Press(
      key: key,
      onTap: _open,
      scale: .98,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: widget.compact ? Colors.transparent : pal.s1,
          borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
          border: Border.all(color: widget.compact ? pal.lineStrong : pal.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (!widget.compact)
            AnimatedBuilder(
              animation: sweep,
              builder: (_, __) {
                final t = sweep.value;
                if (t > .25) return const SizedBox();
                return Positioned.fill(
                  child: FractionalTranslation(
                    translation: Offset(1.2 - t / .25 * 2.4, 0),
                    child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, pal.acc.withValues(alpha: .14), Colors.transparent]))),
                  ),
                );
              },
            ),
          Positioned.fill(
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              PlatBadge(p, size: widget.compact ? 20 : 26),
              const SizedBox(width: 8),
              Text(p.name, style: ts(widget.compact ? 13.5 : 15, w: FontWeight.w700, c: pal.t1)),
              Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: pal.lineStrong),
              SignalBars(sc.ms),
              const SizedBox(width: 6),
              Expanded(child: Text(sc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t2))),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: const Duration(milliseconds: 460),
                curve: Tk.softSpring,
                child: Container(width: 28, height: 28, decoration: BoxDecoration(color: pal.s2, shape: BoxShape.circle), child: Icon(ic('down'), size: 18, color: pal.t2)),
              ),
            ]),
          ),
          ),
        ]),
      ),
    );
  }
}

Future<void> showPicker(BuildContext context, Rect anchor) {
  final st = context.appRead;
  final pal = context.pal;
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, a, _) => AppScope(
      state: st,
      child: PalScope(pal: pal, child: Material(type: MaterialType.transparency, child: _PickerPanel(anchor: anchor, anim: a))),
    ),
  ));
}

class _PickerPanel extends StatefulWidget {
  final Rect anchor;
  final Animation<double> anim;
  const _PickerPanel({required this.anchor, required this.anim});
  @override
  State<_PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<_PickerPanel> {
  String? justPicked;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final list = [...app.scriptsOf(app.plat)]..sort((a, b) => b.ok.compareTo(a.ok));
    final top = widget.anchor.bottom + 8;
    final panel = Container(
      decoration: BoxDecoration(
        color: pal.dark ? const Color(0xF2171821) : const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: pal.line),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _h(pal, '音乐平台', '决定搜索、榜单、歌单的数据来源'),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (c, cs) {
          final w = cs.maxWidth / platforms.length;
          final sel = platforms.indexWhere((p) => p.id == app.plat);
          return SizedBox(
            height: 92,
            child: Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 520),
                curve: Tk.softSpring,
                left: w * sel + (w - 58) / 2,
                top: 0,
                child: Container(width: 58, height: 58, decoration: BoxDecoration(borderRadius: BorderRadius.circular(19), border: Border.all(color: pal.acc, width: 2), boxShadow: [BoxShadow(color: pal.accGlow, blurRadius: 14)])),
              ),
              Row(children: [
                for (final p in platforms)
                  SizedBox(
                    width: w,
                    child: Press(
                      onTap: () {
                        haptic(context);
                        app.switchPlatform(p.id);
                      },
                      child: Column(children: [
                        const SizedBox(height: 4),
                        AnimatedScale(scale: p.id == app.plat ? 1.04 : .94, duration: Tk.base, child: PlatBadge(p, size: 50, dim: p.id != app.plat)),
                        const SizedBox(height: 8),
                        Text(p.short, style: ts(12, w: FontWeight.w600, c: p.id == app.plat ? pal.t1 : pal.t2)),
                        Text(app.isIn(p.id) ? '已登录' : '未登录', style: ts(10.5, c: app.isIn(p.id) ? pal.ok : pal.t3)),
                      ]),
                    ),
                  ),
              ]),
            ]),
          );
        }),
        const SizedBox(height: 8),
        _h(pal, '解析脚本', '${app.platform.name} 可用 ${list.length} 个 · 按成功率排序'),
        const SizedBox(height: 6),
        Column(key: ValueKey(app.plat), children: [
          Rise(0, step: 18, ms: 300, _row(context, 'auto', 'zap', Row(children: [Text('自动选择', style: ts(14.5, w: FontWeight.w600, c: pal.t1)), const SizedBox(width: 6), const Badge2('推荐', acc: true)]), Text('失败时按智能换源规则依次切换', style: ts(12, c: pal.t3)), null)),
          for (final (i, s) in list.indexed)
            Rise(
              i + 1,
              step: 18,
              ms: 300,
              _row(
                context,
                s.id,
                'code',
                Text.rich(TextSpan(children: [TextSpan(text: s.name, style: ts(14.5, w: FontWeight.w600, c: pal.t1)), TextSpan(text: '  v${s.ver}', style: ts(11.5, c: pal.t3))])),
                Row(children: [for (final q in s.qualities) Padding(padding: const EdgeInsets.only(right: 4), child: QBadge(q)), Text('· 成功率 ${s.ok}%', style: ts(12, c: pal.t3))]),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [SignalBars(s.ms), const SizedBox(height: 3), Text('${s.ms}ms', style: ts(10.5, c: pal.t3, num: true))]),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Container(height: 1, color: pal.line),
        Row(children: [
          Expanded(child: _foot(context, 'grid', '管理平台与脚本', () => const SourcesPage())),
          Expanded(child: _foot(context, 'zap', '智能换源', () => const SmartPage())),
        ]),
      ]),
    );
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: FadeTransition(opacity: widget.anim, child: const ColoredBox(color: Color(0x73000000))),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        top: top,
        child: AnimatedBuilder(
          animation: widget.anim,
          child: panel,
          builder: (_, ch) {
            final v = widget.anim.value;
            final rev = widget.anim.status == AnimationStatus.reverse;
            final t = rev ? Curves.easeIn.transform(v) : const Cubic(.2, 1.12, .4, 1).transform(v);
            final sx = .92 + .08 * t, sy = .6 + .4 * t;
            final body = Transform(alignment: Alignment.topCenter, transform: Matrix4.diagonal3Values(sx, sy, 1), child: ch);
            return Opacity(
              opacity: (v * 1.6).clamp(0.0, 1.0),
              child: v >= 1 ? body : ClipRect(clipper: _Reveal(math.min(1, v * 1.5)), child: body),
            );
          },
        ),
      ),
    ]);
  }

  Widget _h(Pal pal, String t, String s) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(t, style: ts(14, w: FontWeight.w700, c: pal.t1)),
        const SizedBox(width: 8),
        Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, c: pal.t3))),
      ]);

  Widget _row(BuildContext context, String id, String icon, Widget title, Widget sub, Widget? trail) {
    final app = context.app;
    final pal = context.pal;
    final on = app.script == id;
    return Press(
      onTap: () async {
        haptic(context);
        app.update(() => app.script = id);
        setState(() => justPicked = id);
        await Future.delayed(const Duration(milliseconds: 280));
        if (!context.mounted) return;
        Navigator.of(context).pop();
        toast('解析：${app.curScript.name} · ${app.platform.short}', 'zap');
      },
      child: AnimatedContainer(
        duration: Tk.base,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: on ? pal.accSoft : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(10)), child: Icon(ic(icon), size: 18, color: on ? pal.accText : pal.t2)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 3), sub])),
          if (trail != null) ...[trail, const SizedBox(width: 10)],
          AnimatedScale(scale: on ? 1 : 0, duration: const Duration(milliseconds: 360), curve: Tk.spring, child: Icon(ic('check'), color: pal.accText, size: 20)),
        ]),
      ),
    );
  }

  Widget _foot(BuildContext context, String icon, String label, Widget Function() page) {
    final pal = context.pal;
    return Press(
      onTap: () {
        Navigator.of(context).pop();
        push(context, page());
      },
      child: SizedBox(height: 46, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(ic(icon), size: 17, color: pal.t2), const SizedBox(width: 6), Text(label, style: ts(13, w: FontWeight.w500, c: pal.t2))])),
    );
  }
}

class _Reveal extends CustomClipper<Rect> {
  final double t;
  _Reveal(this.t);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(-20, -20, s.width + 40, (s.height + 40) * t);
  @override
  bool shouldReclip(_Reveal o) => o.t != t;
}
