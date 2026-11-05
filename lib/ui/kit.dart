// 通用组件：按钮、胶囊、分段、开关、滑杆、设置行、歌曲行、Toast、Sheet、对话框、骨架屏、跑马灯……
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import '../platform/registry.dart' show PlatformHub;
import 'cover.dart';
import 'icons.dart';

final rootNav = GlobalKey<NavigatorState>();

// ============ 按压反馈（不用系统水波纹：只做弹性缩放，列表行可加柔和高亮） ============
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final double scale;
  final BorderRadius? radius;
  final bool hl;
  const Press({super.key, required this.child, this.onTap, this.onLongPress, this.scale = .96, this.radius, this.hl = false});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    if (!enabled) return widget.child;
    Widget c = widget.child;
    if (widget.hl) {
      final pal = context.pal;
      c = AnimatedContainer(
        duration: Duration(milliseconds: _down ? 60 : 220),
        foregroundDecoration: BoxDecoration(color: _down ? (pal.dark ? const Color(0x12FFFFFF) : const Color(0x0C000000)) : Colors.transparent, borderRadius: widget.radius),
        child: c,
      );
    }
    c = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: c,
    );
    if (widget.scale >= 1) return c;
    return AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Duration(milliseconds: _down ? 90 : 260),
      curve: _down ? Curves.easeOut : Tk.spring,
      child: c,
    );
  }
}

void haptic(BuildContext c) {
  // selectionClick 在很多安卓机上对应 CLOCK_TICK，几乎感觉不到或被系统忽略；lightImpact 对应 VIRTUAL_KEY，和按键反馈一致
  if (c.appRead.set.haptics) HapticFeedback.lightImpact();
}

// ============ 按钮 ============
class IBtn extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final double size, iconSize;
  final Color? color, bg;
  final bool dot;
  const IBtn(this.icon, {super.key, this.onTap, this.size = 44, this.iconSize = 22, this.color, this.bg, this.dot = false});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Press(
      onTap: onTap,
      radius: BorderRadius.circular(size / 2),
      scale: .88,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Stack(alignment: Alignment.center, children: [
          Icon(ic(icon), size: iconSize, color: color ?? pal.t1),
          if (dot) Positioned(right: size * .22, top: size * .22, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: pal.danger, shape: BoxShape.circle, border: Border.all(color: pal.bg, width: 1.5)))),
        ]),
      ),
    );
  }
}

enum BtnKind { pri, sec, ghost, danger, glass }

class Btn extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool small, block, busy;
  final Color? bg, fg;
  const Btn(this.label, {super.key, this.icon, this.onTap, this.kind = BtnKind.pri, this.small = false, this.block = false, this.busy = false, this.bg, this.fg});
  const Btn.sec(this.label, {super.key, this.icon, this.onTap, this.small = false, this.block = false, this.bg, this.fg})
      : kind = BtnKind.sec,
        busy = false;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final h = small ? 36.0 : 48.0;
    final (Color b, Color f, Border? br) = switch (kind) {
      BtnKind.pri => (pal.acc, pal.ink, null),
      BtnKind.sec => (pal.s2, pal.t1, null),
      BtnKind.ghost => (Colors.transparent, pal.t1, Border.all(color: pal.lineStrong)),
      BtnKind.danger => (pal.danger.withValues(alpha: .12), pal.danger, null),
      BtnKind.glass => (const Color(0x2EFFFFFF), Colors.white, null),
    };
    final content = AnimatedSwitcher(
      duration: Tk.base,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a), child: c)),
      child: busy
          ? SizedBox(key: const ValueKey('b'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg ?? f))
          : Row(key: const ValueKey('l'), mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(ic(icon!), size: small ? 17 : 19, color: fg ?? f), const SizedBox(width: 6)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(small ? 13.5 : 15, w: FontWeight.w600, c: fg ?? f))),
            ]),
    );
    return Opacity(
      opacity: onTap == null && !busy ? .45 : 1,
      child: Press(
        onTap: busy ? null : onTap,
        scale: .97,
        radius: BorderRadius.circular(h / 2),
        child: Container(
          height: h,
          width: block ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg ?? b,
            borderRadius: BorderRadius.circular(h / 2),
            border: br,
            boxShadow: kind == BtnKind.pri ? [BoxShadow(color: pal.accGlow, blurRadius: 22, offset: const Offset(0, 8))] : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

// ============ 胶囊 / 徽章 ============
class LChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final String? icon;
  final Widget? trailing;
  final double h;
  const LChip(this.label, {super.key, this.on = false, this.onTap, this.icon, this.trailing, this.h = 34});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Press(
      onTap: onTap,
      radius: BorderRadius.circular(h / 2),
      child: AnimatedContainer(
        duration: Tk.base,
        height: h,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? pal.accSoft : pal.s2,
          borderRadius: BorderRadius.circular(h / 2),
          border: Border.all(color: on ? pal.acc.withValues(alpha: .35) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(ic(icon!), size: 15, color: on ? pal.accText : pal.t2), const SizedBox(width: 5)],
          Text(label, style: ts(13, w: FontWeight.w500, c: on ? pal.accText : pal.t1)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ]),
      ),
    );
  }
}

class Badge2 extends StatelessWidget {
  final String text;
  final bool acc;
  final String? icon;
  final Color? color;
  const Badge2(this.text, {super.key, this.acc = false, this.icon, this.color});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = color ?? (acc ? pal.accText : pal.t2);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: color?.withValues(alpha: .14) ?? (acc ? pal.accSoft : pal.s2), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(ic(icon!), size: 12, color: c), const SizedBox(width: 3)],
        Text(text, style: ts(11, w: FontWeight.w600, c: c)),
      ]),
    );
  }
}

class QBadge extends StatelessWidget {
  final String q;
  final Color? color;
  const QBadge(this.q, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final plain = q == 'HQ' || q == '128k';
    final c = color ?? (plain ? pal.t3 : pal.accText);
    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: c.withValues(alpha: .7))),
      child: Text(q, style: ts(9.5, w: FontWeight.w700, c: c, h: 1.1, num: true)),
    );
  }
}

class PlatBadge extends StatelessWidget {
  final Platform p;
  final double size;
  final bool dim;
  const PlatBadge(this.p, {super.key, this.size = 22, this.dim = false});
  @override
  Widget build(BuildContext context) {
    // 各平台真 logo（矢量，取自原版资源包 assets/platform_logos/）；带品牌色圆底，不再用文字占位
    Widget w = SvgPicture.asset(
      'assets/platform_logos/${PlatformHub.codeOf(p.id)}.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
    );
    if (dim) w = ColorFiltered(colorFilter: const ColorFilter.matrix([.6, .3, .1, 0, 0, .2, .7, .1, 0, 0, .2, .3, .5, 0, 0, 0, 0, 0, .8, 0]), child: w);
    return w;
  }
}

class SignalBars extends StatelessWidget {
  final int ms;
  const SignalBars(this.ms, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final n = ms < 400 ? 4 : ms < 700 ? 3 : ms < 1000 ? 2 : 1;
    final col = n >= 3 ? pal.ok : n == 2 ? pal.warn : pal.danger;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 4; i++)
        Container(margin: const EdgeInsets.only(right: 1.5), width: 3, height: 3.0 + i * 2.2, decoration: BoxDecoration(color: i <= n ? col : pal.t4, borderRadius: BorderRadius.circular(1))),
    ]);
  }
}

/// 当前播放行的 3 根均衡条（暂停时停住）。
class EqBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double h;
  const EqBars({super.key, required this.playing, required this.color, this.h = 12});
  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    if (widget.playing) c.repeat();
  }

  @override
  void didUpdateWidget(EqBars o) {
    super.didUpdateWidget(o);
    widget.playing ? (c.isAnimating ? null : c.repeat()) : c.stop();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(right: 1.5),
              width: 2.5,
              height: widget.h * (.3 + .7 * (.5 + .5 * math.sin((c.value + i * .33) * math.pi * 2)).abs()),
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1)),
            ),
        ]),
      );
}

// ============ 分段 ============
class Seg extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;
  final EdgeInsets margin;
  const Seg(this.options, this.value, this.onChanged, {super.key, this.compact = false, this.margin = const EdgeInsets.symmetric(horizontal: Tk.pad)});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final i = math.max(0, options.indexOf(value));
    final h = compact ? 30.0 : 34.0;
    return Padding(
      padding: margin,
      child: Container(
        height: h + 6,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(13)),
        child: LayoutBuilder(builder: (context, cs) {
          final w = cs.maxWidth / options.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: Tk.softSpring,
              left: w * i,
              top: 0,
              width: w,
              height: h,
              child: Container(
                decoration: BoxDecoration(
                  color: pal.dark ? pal.s3 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
            Row(children: [
              for (final o in options)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (o != value) {
                        haptic(context);
                        onChanged(o);
                      }
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: Tk.fast,
                        style: ts(compact ? 12.5 : 13.5, w: o == value ? FontWeight.w700 : FontWeight.w500, c: o == value ? pal.t1 : pal.t2),
                        child: Text(o, maxLines: 1),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

// ============ 开关 ============
class LSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const LSwitch(this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return GestureDetector(
      onTap: onChanged == null ? null : () {
        haptic(context);
        onChanged!(!value);
      },
      child: AnimatedContainer(
        duration: Tk.base,
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: value ? pal.acc : pal.s3, borderRadius: BorderRadius.circular(15)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Tk.softSpring,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))])),
        ),
      ),
    );
  }
}

// ============ 滑杆 ============
class LSlider extends StatefulWidget {
  final double value, min, max;
  final double? step;
  final ValueChanged<double> onChanged;
  final String? label;
  final String Function(double)? fmt;
  final Color? color;
  const LSlider({super.key, required this.value, required this.min, required this.max, required this.onChanged, this.step, this.label, this.fmt, this.color});
  @override
  State<LSlider> createState() => _LSliderState();
}

class _LSliderState extends State<LSlider> {
  bool drag = false;
  void _set(double dx, double w) {
    var v = widget.min + (dx / w).clamp(0, 1) * (widget.max - widget.min);
    if (widget.step != null) v = (v / widget.step!).round() * widget.step!;
    v = v.clamp(widget.min, widget.max);
    if (v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final track = LayoutBuilder(builder: (c, cs) {
      final w = cs.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 按下就跟手（不等滑动距离超过阈值），触控区 44 高
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (d) {
          setState(() => drag = true);
          _set(d.localPosition.dx, w);
        },
        onHorizontalDragUpdate: (d) => _set(d.localPosition.dx, w),
        onHorizontalDragEnd: (_) => setState(() => drag = false),
        onHorizontalDragCancel: () => setState(() => drag = false),
        onTapDown: (d) => _set(d.localPosition.dx, w),
        child: SizedBox(
          height: 44,
          child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
            Container(height: 4, decoration: BoxDecoration(color: pal.s3, borderRadius: BorderRadius.circular(2))),
            Container(width: w * p, height: 4, decoration: BoxDecoration(color: widget.color ?? pal.acc, borderRadius: BorderRadius.circular(2))),
            Positioned(
              left: w * p - 11,
              child: AnimatedScale(
                scale: drag ? 1.25 : 1,
                duration: Tk.base,
                curve: Tk.spring,
                child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))])),
              ),
            ),
          ]),
        ),
      );
    });
    if (widget.label == null && widget.fmt == null) return track;
    return Row(children: [
      if (widget.label != null) SizedBox(width: 74, child: Text(widget.label!, style: ts(14, c: pal.t2))),
      Expanded(child: track),
      const SizedBox(width: 12),
      SizedBox(width: 50, child: Text(widget.fmt?.call(widget.value) ?? widget.value.toStringAsFixed(0), textAlign: TextAlign.right, style: ts(13, w: FontWeight.w600, c: pal.t1, num: true))),
    ]);
  }
}

// ============ 卡片 / 设置组 ============
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = const EdgeInsets.symmetric(horizontal: Tk.pad), this.onTap, this.radius = 20, this.color, this.gradient});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(color: gradient == null ? (color ?? pal.s1) : null, gradient: gradient, borderRadius: BorderRadius.circular(radius), border: Border.all(color: pal.line)),
      child: child,
    );
    return Padding(padding: margin, child: onTap == null ? box : Press(onTap: onTap, scale: .98, radius: BorderRadius.circular(radius), child: box));
  }
}

class Group extends StatelessWidget {
  final String? title, foot;
  final List<Widget> children;
  const Group({super.key, this.title, required this.children, this.foot});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) items.add(Padding(padding: const EdgeInsets.only(left: 56), child: Container(height: .6, color: pal.line)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tk.pad - 4, 0, Tk.pad - 4, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(10, 4, 0, 8), child: Text(title!, style: ts(12.5, w: FontWeight.w600, c: pal.t3))),
        Container(
          decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: items),
        ),
        if (foot != null) Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 0), child: Text(foot!, style: ts(12, c: pal.t3, h: 1.5))),
      ]),
    );
  }
}

class Item extends StatelessWidget {
  final String? icon, color, sub, val;
  final String label;
  final bool? sw;
  final ValueChanged<bool>? onSw;
  final VoidCallback? onTap;
  final bool danger, chev;
  final Widget? trailing, lead;
  const Item({super.key, this.icon, this.color, required this.label, this.sub, this.val, this.sw, this.onSw, this.onTap, this.danger = false, this.chev = true, this.trailing, this.lead});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final tap = sw != null ? () => onSw?.call(!sw!) : onTap;
    return Press(
      onTap: tap,
      scale: 1,
      hl: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          if (lead != null) ...[lead!, const SizedBox(width: 12)],
          if (icon != null && lead == null) ...[
            Container(width: 30, height: 30, decoration: BoxDecoration(color: settingTiles[color] ?? settingTiles['gray'], borderRadius: BorderRadius.circular(9)), child: Icon(ic(icon!), size: 18, color: Colors.white)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: ts(15, w: FontWeight.w500, c: danger ? pal.danger : pal.t1)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: ts(12, c: pal.t3, h: 1.35))),
            ]),
          ),
          if (trailing != null) trailing!,
          if (sw != null) LSwitch(sw!, onSw),
          if (sw == null && trailing == null) ...[
            if (val != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(val!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, c: pal.t3))),
            if (chev && (onTap != null)) Icon(ic('right'), size: 20, color: pal.t3),
          ],
        ]),
      ),
    );
  }
}

class Sec extends StatelessWidget {
  final String title;
  final String? more;
  final VoidCallback? onMore;
  final double size;
  final Widget? trailing;
  const Sec(this.title, {super.key, this.more, this.onMore, this.size = 19, this.trailing});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tk.pad, 22, Tk.pad - 6, 12),
      child: Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(size, w: FontWeight.w700, c: pal.t1))),
        if (trailing != null) trailing!,
        if (more != null)
          Press(
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(children: [Text(more!, style: ts(13, c: pal.t3)), if (onMore != null) Icon(ic('right'), size: 16, color: pal.t3)]),
            ),
          ),
      ]),
    );
  }
}

class Hint extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  final TextAlign align;
  const Hint(this.text, {super.key, this.padding = const EdgeInsets.symmetric(horizontal: Tk.pad, vertical: 8), this.align = TextAlign.start});
  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: Text(text, textAlign: align, style: ts(12, c: context.pal.t3, h: 1.55)));
}

class Avatar extends StatelessWidget {
  final String text;
  final double size;
  final VoidCallback? onTap;

  /// 头像图片地址；加载中 / 失败时显示首字占位。
  final String? url;
  const Avatar(this.text, {super.key, this.size = 36, this.onTap, this.url});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Press(
      onTap: onTap,
      radius: BorderRadius.circular(size),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.acc, Color.lerp(pal.acc, Colors.black, .45)!])),
        child: url == null
            ? Text(text, style: ts(size * .42, w: FontWeight.w700, c: pal.ink))
            : Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
                Center(child: Text(text, style: ts(size * .42, w: FontWeight.w700, c: pal.ink))),
                ClipOval(
                  child: Image.network(
                    url!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                    gaplessPlayback: true,
                    frameBuilder: (_, ch, frame, sync) => sync ? ch : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: ch),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ]),
      ),
    );
  }
}

// ============ 玻璃 ============
/// 背景模糊开关：「减少模糊效果」开启时不做 BackdropFilter（每帧对背后内容做高斯模糊，是老机型掉帧大户），
/// 调用方需在 [child] 里用 [opaque] 换成不透明底色。
bool reduceBlur(BuildContext context) => context.appRead.set.reduceBlur;
Widget backdrop(BuildContext context, ui.ImageFilter filter, Widget child) => reduceBlur(context) ? child : BackdropFilter(filter: filter, child: child);

class Glass extends StatelessWidget {
  final Widget child;
  final double radius, blur;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? shadow;
  const Glass({super.key, required this.child, this.radius = 20, this.blur = 13, this.color, this.border, this.shadow});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: backdrop(
          context,
          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          Container(
            decoration: BoxDecoration(color: reduceBlur(context) ? pal.bgElev : color ?? pal.glass, borderRadius: BorderRadius.circular(radius), border: border ?? Border.all(color: pal.line)),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ============ 跑马灯 ============
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const Marquee(this.text, {super.key, required this.style});
  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  // 开头静止 2s（这段时间不占用帧），再用 9s 滚完一轮。
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  bool _overflow = false;
  @override
  void initState() {
    super.initState();
    _loop();
  }

  Future<void> _loop() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      if (!_overflow) continue;
      try {
        await c.forward(from: 0).orCancel;
      } catch (_) {
        return;
      }
      if (mounted) c.value = 0;
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cs) {
      final tp = TextPainter(text: TextSpan(text: widget.text, style: widget.style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
      _overflow = tp.width > cs.maxWidth;
      if (!_overflow) return Text(widget.text, maxLines: 1, style: widget.style);
      final gap = 40.0, span = tp.width + gap;
      return ShaderMask(
        // 必须 dstIn（只取渐变的透明度）：默认的 modulate 会把文字颜色乘成黑色——长歌名滚动时变黑就是这个
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, .06, .92, 1]).createShader(r),
        child: ClipRect(
          child: SizedBox(
            height: tp.height,
            child: AnimatedBuilder(
              animation: c,
              builder: (_, __) {
                final t = c.value;
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(-span * t, 0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Text(widget.text, style: widget.style), SizedBox(width: gap), Text(widget.text, style: widget.style)]),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

// ============ 依次浮现 / 数字滚动 / 骨架屏 ============
class Rise extends StatefulWidget {
  final Widget child;
  final int index;
  final double dy;
  final int step, ms;
  const Rise(this.index, this.child, {super.key, this.dy = 14, this.step = 32, this.ms = 520});
  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: math.min(widget.index, 16) * widget.step), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.appRead.set.reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (_, ch) {
        final t = Tk.out.transform(c.value);
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, widget.dy * (1 - t)), child: ch));
      },
    );
  }
}

class CountUp extends StatelessWidget {
  final double value;
  final int decimals;
  final TextStyle style;
  const CountUp(this.value, {super.key, this.decimals = 0, required this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(v.toStringAsFixed(decimals), style: style),
      );
}

class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (_, ch) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          colors: [pal.s2, pal.s3, pal.s2],
          stops: const [.35, .5, .65],
          transform: _Slide(c.value * 2 - 1),
        ).createShader(r),
        child: ch,
      ),
    );
  }
}

class _Slide extends GradientTransform {
  final double t;
  const _Slide(this.t);
  @override
  Matrix4 transform(Rect b, {TextDirection? textDirection}) => Matrix4.translationValues(b.width * t, 0, 0);
}

class Bone extends StatelessWidget {
  final double? w;
  final double h, r;
  const Bone({super.key, this.w, required this.h, this.r = 8});
  @override
  Widget build(BuildContext context) => Container(width: w, height: h, decoration: BoxDecoration(color: context.pal.s2, borderRadius: BorderRadius.circular(r)));
}

class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});
  @override
  Widget build(BuildContext context) => Shimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Bone(h: 168, r: 22),
            const SizedBox(height: 22),
            Row(children: [for (var i = 0; i < 4; i++) ...[const Expanded(child: Bone(h: 54, r: 18)), if (i < 3) const SizedBox(width: 12)]]),
            const SizedBox(height: 26),
            const Bone(w: 140, h: 22),
            const SizedBox(height: 12),
            Row(children: [for (var i = 0; i < 3; i++) ...[const Bone(w: 100, h: 100, r: 16), const SizedBox(width: 14)]]),
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Row(children: [Bone(w: 48, h: 48, r: 10), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Bone(w: 160, h: 14), SizedBox(height: 8), Bone(w: 100, h: 11)]))]),
              ),
          ]),
        ),
      );
}

// ============ Toast（顶部，深色玻璃） ============
class Toast {
  static OverlayEntry? _e;
  static Timer? _t;
  static void show(String msg, {String icon = 'check'}) {
    final ov = rootNav.currentState?.overlay;
    if (ov == null) return;
    _t?.cancel();
    _e?.remove();
    final key = GlobalKey<_ToastViewState>();
    final e = OverlayEntry(builder: (_) => _ToastView(key: key, msg: msg, icon: icon));
    _e = e;
    ov.insert(e);
    _t = Timer(const Duration(milliseconds: 1900), () {
      key.currentState?.hide();
      Timer(const Duration(milliseconds: 300), () {
        if (_e == e) {
          e.remove();
          _e = null;
        }
      });
    });
  }
}

class _ToastView extends StatefulWidget {
  final String msg, icon;
  const _ToastView({super.key, required this.msg, required this.icon});
  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), reverseDuration: const Duration(milliseconds: 260))..forward();
  void hide() => c.reverse();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, ch) {
            final t = c.status == AnimationStatus.reverse ? Curves.easeIn.transform(c.value) : Tk.softSpring.transform(c.value);
            return Opacity(opacity: c.value.clamp(0, 1), child: Transform.translate(offset: Offset(0, -70 * (1 - t)), child: ch));
          },
          child: Material(
            type: MaterialType.transparency,
            child: Center(
            child: Glass(
              radius: 24,
              color: const Color(0xE6141520),
              border: Border.all(color: const Color(0x1AFFFFFF)),
              shadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 24, height: 24, decoration: BoxDecoration(color: pal.acc, shape: BoxShape.circle), child: Icon(ic(widget.icon), size: 14, color: pal.ink)),
                  const SizedBox(width: 10),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 290), child: Text(widget.msg, style: ts(13.5, w: FontWeight.w500, c: Colors.white, h: 1.35))),
                ]),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

void toast(String msg, [String icon = 'check']) => Toast.show(msg, icon: icon);

// ============ Bottom Sheet ============
Future<T?> showLSheet<T>(BuildContext context, {required String title, String? sub, bool dark = false, Widget? action, required Widget Function(BuildContext) builder, bool scroll = true}) {
  final st = context.appRead;
  final basePal = context.pal;
  return showModalBottomSheet<T>(
    context: rootNav.currentContext ?? context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x80000000),
    useSafeArea: true,
    builder: (ctx) {
      final pal = dark ? basePal.forceDark : basePal;
      return AppScope(
        state: st,
        child: PalScope(
          pal: pal,
          child: Builder(builder: (ctx) {
            final mq = MediaQuery.of(ctx);
            return Padding(
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: mq.size.height * .86),
                child: Container(
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xF2141520) : pal.bgElev,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: pal.line)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 8),
                    Container(width: 38, height: 5, decoration: BoxDecoration(color: pal.t4, borderRadius: BorderRadius.circular(3))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Tk.pad, 12, 10, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(18, w: FontWeight.w700, c: pal.t1))),
                          if (action != null) action,
                          IBtn('close', size: 36, iconSize: 18, bg: pal.s2, color: pal.t2, onTap: () => Navigator.of(ctx).pop()),
                        ]),
                        if (sub != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, c: pal.t3)),
                          ),
                      ]),
                    ),
                    Flexible(
                      child: scroll
                          ? SingleChildScrollView(padding: EdgeInsets.only(bottom: mq.padding.bottom + 20), child: builder(ctx))
                          : Padding(padding: EdgeInsets.only(bottom: mq.padding.bottom + 12), child: builder(ctx)),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      );
    },
  );
}

// ============ 对话框 ============
Future<T?> showLDialog<T>(BuildContext context, {String icon = 'info', required String title, String? body, Widget? content, required List<(String, BtnKind, VoidCallback?)> actions, bool dismissible = false, Color? iconColor}) {
  final st = context.appRead;
  final pal = context.pal;
  return showGeneralDialog<T>(
    context: rootNav.currentContext ?? context,
    barrierDismissible: dismissible,
    barrierLabel: 'dialog',
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 380),
    transitionBuilder: (c, a, _, ch) {
      final t = Tk.softSpring.transform(a.value);
      return Opacity(opacity: a.value, child: Transform.scale(scale: .9 + .1 * t, child: ch));
    },
    pageBuilder: (ctx, _, __) => AppScope(
      state: st,
      child: PalScope(
        pal: pal,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: pal.bgElev,
              borderRadius: BorderRadius.circular(26),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: (iconColor ?? pal.acc).withValues(alpha: .15), shape: BoxShape.circle), child: Icon(ic(icon), color: iconColor ?? pal.accText, size: 26)),
                  const SizedBox(height: 14),
                  Text(title, textAlign: TextAlign.center, style: ts(18, w: FontWeight.w700, c: pal.t1)),
                  if (body != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(body, textAlign: TextAlign.center, style: ts(14, c: pal.t2, h: 1.6))),
                  if (content != null) Padding(padding: const EdgeInsets.only(top: 12), child: content),
                  const SizedBox(height: 20),
                  Row(children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Btn(actions[i].$1, kind: actions[i].$2, onTap: () {
                          Navigator.of(ctx).pop();
                          actions[i].$3?.call();
                        }),
                      ),
                    ],
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ============ 歌曲行（左滑操作 + 当前播放态） ============
typedef MoreHandler = void Function(BuildContext context, int id, String ctx);
MoreHandler? onSongMore; // 由 sheets.dart 注入，避免循环依赖

class SongRow extends StatefulWidget {
  final Song song;
  final int? num;
  final String list;
  final String? listName;
  final bool heart, swipe, showCover;
  final String ctx;
  final Widget? tail;
  final double h;
  final TextSpan Function(String text, TextStyle style)? hl;

  /// 点歌时的播放队列（平台歌单、榜单、搜索结果等）；不给时按 [list] 取。
  final List<int>? queue;
  const SongRow(this.song, {super.key, this.num, this.list = 'all', this.listName, this.heart = false, this.swipe = true, this.ctx = '', this.tail, this.showCover = true, this.h = Tk.rowH, this.hl, this.queue});
  @override
  State<SongRow> createState() => _SongRowState();
}

class _SongRowState extends State<SongRow> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380), lowerBound: -1, upperBound: 0)..value = 0;
  static const open = 216.0;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _settle(double v) {
    final target = (c.value * open < -90 || v < -500) ? -1.0 : 0.0;
    c.animateTo(target, curve: Tk.softSpring);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = widget.song;
    final isCur = app.cur == s.id;
    final liked = app.liked.contains(s.id);
    final titleStyle = ts(15, w: FontWeight.w600, c: isCur ? pal.accText : pal.t1);
    final subStyle = ts(12.5, c: pal.t2);
    final row = Press(
      scale: .99,
      hl: true,
      onTap: () {
        if (c.value < -.05) {
          c.animateTo(0, curve: Tk.out);
          return;
        }
        app.play(s.id, list: widget.list, name: widget.listName, ids: widget.queue);
      },
      child: Container(
        height: widget.h,
        color: pal.bg.withValues(alpha: 0),
        padding: const EdgeInsets.only(left: Tk.pad, right: 6),
        child: Row(children: [
          if (widget.num != null)
            SizedBox(width: 26, child: Text('${widget.num! + 1}', style: ts(15, w: FontWeight.w700, c: widget.num! < 3 ? pal.accText : pal.t3, num: true))),
          if (widget.showCover) ...[Cover.song(s, size: 48), const SizedBox(width: 12)],
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              widget.hl != null ? Text.rich(widget.hl!(s.title, titleStyle), maxLines: 1, overflow: TextOverflow.ellipsis) : Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
              const SizedBox(height: 3),
              Row(children: [
                if (isCur) ...[EqBars(playing: app.playing, color: pal.accText, h: 11), const SizedBox(width: 5)],
                QBadge(s.quality),
                const SizedBox(width: 6),
                Expanded(
                  child: widget.hl != null
                      ? Text.rich(widget.hl!('${s.artist} · ${s.album}', subStyle), maxLines: 1, overflow: TextOverflow.ellipsis)
                      : Text('${s.artist} · ${s.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                ),
              ]),
            ]),
          ),
          if (widget.tail != null) widget.tail!,
          if (widget.tail == null && widget.heart) HeartBtn(s.id),
          if (widget.tail == null) IBtn('more', color: pal.t3, onTap: () => onSongMore?.call(context, s.id, widget.ctx)),
        ]),
      ),
    );
    if (!widget.swipe) return row;
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        var v = c.value + d.delta.dx / open;
        if (v < -1) v = -1 + (v + 1) * .3;
        c.value = v.clamp(-1.15, 0);
      },
      onHorizontalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
      child: ClipRect(
        child: Stack(children: [
          Positioned.fill(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _act('next', '下一首', const Color(0xFF3D8BF4), Colors.white, () {
                app.playNext(s.id);
                toast('下一首播放：${s.title}', 'next');
                c.animateTo(0);
              }),
              _act(liked ? 'heartf' : 'heart', liked ? '已收藏' : '收藏', pal.acc, pal.ink, () {
                final on = app.toggleLike(s.id);
                toast(on ? '已收藏' : '已取消收藏', on ? 'heartf' : 'heart');
                c.animateTo(0);
              }),
              _act('more', '更多', const Color(0xFF6E7385), Colors.white, () {
                c.animateTo(0);
                onSongMore?.call(context, s.id, widget.ctx);
              }),
            ]),
          ),
          AnimatedBuilder(animation: c, builder: (_, ch) => Transform.translate(offset: Offset(c.value * open, 0), child: ch), child: Container(color: pal.bg, child: row)),
        ]),
      ),
    );
  }

  Widget _act(String icon, String label, Color bg, Color fg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          color: bg,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(ic(icon), color: fg, size: 22), const SizedBox(height: 3), Text(label, style: ts(11, w: FontWeight.w600, c: fg))]),
        ),
      );
}

/// 爱心：收藏时 0.6 → 1.3 → 1 弹跳 + 粒子迸发。
class HeartBtn extends StatefulWidget {
  final int id;
  final double size;
  final Color? offColor;
  const HeartBtn(this.id, {super.key, this.size = 22, this.offColor});
  @override
  State<HeartBtn> createState() => _HeartBtnState();
}

class _HeartBtnState extends State<HeartBtn> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final on = app.liked.contains(widget.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        haptic(context);
        final v = app.toggleLike(widget.id);
        if (v) c.forward(from: 0);
        toast(v ? '已收藏到「我喜欢」' : '已取消收藏', v ? 'heartf' : 'heart');
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) {
            final t = c.value;
            final s = c.isAnimating ? (t < .3 ? .6 + t / .3 * .7 : 1.3 - (t - .3) / .7 * .3) : 1.0;
            return CustomPaint(
              painter: _Burst(t, pal.acc, c.isAnimating),
              child: Center(child: Transform.scale(scale: s, child: Icon(ic(on ? 'heartf' : 'heart'), size: widget.size, color: on ? pal.accText : (widget.offColor ?? pal.t3)))),
            );
          },
        ),
      ),
    );
  }
}

class _Burst extends CustomPainter {
  final double t;
  final Color c;
  final bool on;
  _Burst(this.t, this.c, this.on);
  @override
  void paint(Canvas canvas, Size s) {
    if (!on || t > .9) return;
    final p = Paint()..color = c.withValues(alpha: 1 - t);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final r = 8 + 16 * Curves.easeOut.transform(t);
      canvas.drawCircle(s.center(Offset(math.cos(a) * r, math.sin(a) * r)), 2.2 * (1 - t), p);
    }
  }

  @override
  bool shouldRepaint(_Burst o) => true;
}

/// 关键词高亮。
TextSpan Function(String, TextStyle) highlighter(String q, Color c) => (text, style) {
      if (q.isEmpty) return TextSpan(text: text, style: style);
      final lower = text.toLowerCase(), ql = q.toLowerCase();
      final spans = <TextSpan>[];
      var i = 0;
      while (true) {
        final j = lower.indexOf(ql, i);
        if (j < 0) {
          spans.add(TextSpan(text: text.substring(i)));
          break;
        }
        if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
        spans.add(TextSpan(text: text.substring(j, j + q.length), style: TextStyle(color: c, fontWeight: FontWeight.w700)));
        i = j + q.length;
      }
      return TextSpan(style: style, children: spans);
    };

String fmtTime(double s) {
  final v = math.max(0, s.floor());
  return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
}

/// 平台 / 歌单卡（横滑）。
class PlCard extends StatelessWidget {
  final Playlist p;
  final double w;
  final VoidCallback? onTap;
  final String? sub;
  const PlCard(this.p, {super.key, this.w = 140, this.onTap, this.sub});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SizedBox(
      width: w,
      child: Press(
        onTap: onTap,
        scale: .97,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover.pl(
            p,
            size: w,
            child: p.playCount.isEmpty && p.tag == null
                ? null
                : Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x73000000), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (p.tag == null) const Icon(Icons.play_arrow_rounded, size: 11, color: Colors.white),
                        Text(p.tag ?? p.playCount, style: ts(10.5, w: FontWeight.w600, c: Colors.white, num: true)),
                      ]),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500, c: pal.t1, h: 1.35)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, maxLines: 1, style: ts(12, c: pal.t3))),
        ]),
      ),
    );
  }
}

/// 横滑容器。
class HScroll extends StatelessWidget {
  final List<Widget> children;
  final double gap, height;
  const HScroll({super.key, required this.children, this.gap = 14, required this.height});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          itemCount: children.length,
          separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

/// 横向滚动行的边缘渐隐：右侧（和已经往右滑过时的左侧）淡出 [fade] 像素，提示后面还有内容。
/// 只包一个横向 [ScrollView]（ListView 等）。
class EdgeFade extends StatefulWidget {
  final Widget child;
  final double fade;
  const EdgeFade({super.key, required this.child, this.fade = 28});
  @override
  State<EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<EdgeFade> {
  bool left = false, right = true;

  bool _onScroll(ScrollMetrics m) {
    final l = m.pixels > 1, r = m.pixels < m.maxScrollExtent - 1;
    if (l != left || r != right) {
      setState(() {
        left = l;
        right = r;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onScroll(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onScroll(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) {
            final f = (widget.fade / r.width).clamp(0.0, .5);
            return LinearGradient(colors: [
              left ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              right ? Colors.transparent : Colors.black,
            ], stops: [0, f, 1 - f, 1]).createShader(r);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

