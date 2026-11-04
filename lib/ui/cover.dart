// 封面：按色相 + 变体取预渲染的占位图（由原型 coverStyle 生成）。有封面地址时在占位图上叠网络图片，
// 占位图同时是加载中 / 加载失败的兜底。CoverPainter 保留给需要实时绘制的少数场景。
//
// 网络层必须走 [UaImage]（不要用 Image.network / NetworkImage + headers）：
// 网易 / QQ 图床按 UA 拦截，Dart 默认 UA 一律 403；且 Image.network 的 headers 参数
// 在本工程实测不透传（带上 UA 请求仍以 Dart UA 出网，宿主 curl 双向验证过 2026-11-04）。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/tokens.dart';
import '../data/models.dart';

class Cover extends StatelessWidget {
  /// 封面图请求统一 UA：网易 / QQ 等图床按 UA 拦截 Dart 默认 UA（403）。
  static const ua = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';
  final double hue;
  final int variant;
  final double size;
  final double? width, height;
  final double radius;
  final Widget? child;
  final bool shadow;

  /// 封面图片地址（http / https）。
  final String? url;
  const Cover({super.key, required this.hue, this.variant = 0, this.size = 48, this.width, this.height, this.radius = 10, this.child, this.shadow = false, this.url});
  factory Cover.song(Song s, {double size = 48, double radius = 10, bool shadow = false, Widget? child}) =>
      Cover(hue: s.hue, variant: s.variant, size: size, radius: radius, shadow: shadow, url: s.cover, child: child);
  factory Cover.pl(Playlist p, {double size = 140, double radius = 16, Widget? child}) =>
      Cover(hue: p.hue, variant: p.variant, size: size, radius: radius, url: p.cover, child: child);

  /// 按显示尺寸解码，避免大图占内存。
  int? _cacheW(BuildContext context) {
    final w = width ?? size;
    if (w <= 0 || !w.isFinite) return null;
    return (w * MediaQuery.devicePixelRatioOf(context)).round();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? (size > 0 ? size : double.infinity),
      height: height ?? (size > 0 ? size : double.infinity),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? [const BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 18))] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          // 预渲染图片作为底图：老机型上实时绘制多层渐变每帧都要重画，图片只解码一次、全局共享缓存。
          decoration: BoxDecoration(
            color: hsl(hue + 40, .62, .34),
            image: DecorationImage(image: AssetImage(placeholderAsset(hue, variant)), fit: BoxFit.cover),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: _image(context),
          ),
        ),
      ),
    );
  }

  Widget? _image(BuildContext context) {
    final u = coverUrl(url);
    if (u == null) return child;
    print('[coverimg] enter url=$u');
    // UA 拦截见文件头说明；cacheWidth 拿不到（撑满容器的 Cover）时不缩放解码。
    final cacheW = _cacheW(context);
    final img = Image(
      image: cacheW == null ? UaImage(u) : ResizeImage(UaImage(u), width: cacheW, height: cacheW, policy: ResizeImagePolicy.exact),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      frameBuilder: (_, ch, frame, sync) => sync ? ch : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), child: ch),
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
    if (child == null) return img;
    return Stack(fit: StackFit.expand, children: [img, child!]);
  }
}

/// 模糊背景封面：把封面解码成极小的图（[px] 像素宽）再放大铺满，双三次插值放大本身就是柔和的模糊。
/// 相比 ImageFiltered（sigma 30~40 的高斯模糊每帧都要在 GPU 上重算，滚动时老机型掉帧明显），
/// 这里只在解码时付一次成本，之后和普通图片一样合成。
class BlurCover extends StatelessWidget {
  final double hue;
  final int variant;
  final String? url;
  final int px;
  const BlurCover({super.key, required this.hue, this.variant = 0, this.url, this.px = 20});
  factory BlurCover.song(Song s, {int px = 20}) => BlurCover(hue: s.hue, variant: s.variant, url: s.cover, px: px);

  @override
  Widget build(BuildContext context) {
    final u = coverUrl(url);
    Widget img(ImageProvider p, {bool fade = false}) => Image(
          image: ResizeImage(p, width: px),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          frameBuilder: fade ? (_, ch, frame, sync) => sync ? ch : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), child: ch) : null,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        );
    return RepaintBoundary(
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: hsl(hue + 40, .62, .34)),
        img(AssetImage(placeholderAsset(hue, variant))),
        if (u != null) img(UaImage(u), fade: true),
      ]),
    );
  }
}

/// 占位封面图片：色相按 30° 分桶（12 档），样式 6 种。
String placeholderAsset(double hue, int variant) {
  final h = ((hue % 360 + 360) % 360 / 30).round() % 12;
  return 'assets/covers/cover_${h}_${variant.abs() % 6}.jpg';
}

/// 带浏览器 UA 的网络图：网易 / QQ 等图床按 UA 拦截，Dart 默认 UA（Dart/3.x）一律 403，
/// 而 Image.network / NetworkImage 的 headers 参数在本工程实测不透传（2026-11-04，
/// 曾导致全量封面静默落回占位图）——所以自己取字节解码。
/// 失败抛给 errorBuilder（占位图兜底）；ImageCache 按 key 缓存，不会重复请求。
class UaImage extends ImageProvider<UaImage> {
  final String url;
  const UaImage(this.url);

  @override
  Future<UaImage> obtainKey(covariant ImageConfiguration configuration) => SynchronousFuture<UaImage>(this);

  @override
  ImageStreamCompleter loadImage(UaImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1.0);
  }

  Future<ui.Codec> _load(UaImage key, ImageDecoderCallback decode) async {
    try {
      final r = await http.get(Uri.parse(key.url), headers: const {'User-Agent': Cover.ua}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        print('[cover] HTTP ${r.statusCode} len=${r.bodyBytes.length} ua=${Cover.ua.length}ch $key');
        throw StateError('封面 HTTP ${r.statusCode}');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(r.bodyBytes);
      return decode(buffer);
    } catch (e) {
      print('[cover] load failed: $e $key');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is UaImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'UaImage("$url")';
}

/// 规范封面地址：只接受 http(s)；支持 https 的图床（网易 / QQ）把 http 升级成 https，
/// 其余 http 图床（酷狗 / 酷我 / 咪咕）由 network_security_config 单独放行。
String? coverUrl(String? u) {
  if (u == null) return null;
  u = u.trim();
  if (u.startsWith('//')) u = 'https:$u';
  if (!(u.startsWith('http://') || u.startsWith('https://'))) return null;
  if (u.startsWith('http://')) {
    final host = Uri.tryParse(u)?.host ?? '';
    if (host.endsWith('126.net') || host.endsWith('gtimg.cn') || host.endsWith('qq.com') || host.endsWith('qpic.cn')) u = 'https://${u.substring(7)}';
  }
  return u;
}

Offset _dirPts(Size s, double deg, bool start) {
  // CSS 线性渐变角度：0deg 向上，顺时针。
  final r = (deg - 90) * math.pi / 180;
  final dx = math.cos(r), dy = math.sin(r);
  final half = (s.width * dx.abs() + s.height * dy.abs()) / 2;
  final c = s.center(Offset.zero);
  return start ? c - Offset(dx, dy) * half : c + Offset(dx, dy) * half;
}

ui.Shader cssLinear(Size s, double deg, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.linear(_dirPts(s, deg, true), _dirPts(s, deg, false), colors, stops);

class CoverPainter extends CustomPainter {
  final double h;
  final int v;
  CoverPainter(this.h, this.v);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final a = hsl(h, .72, .62), b = hsl(h + 40, .62, .34), c = hsl(h + 320, .70, .14);
    final p = Paint();
    switch (v % 4) {
      case 0:
        p.shader = cssLinear(s, 140, [b, c]);
        canvas.drawRect(rect, p);
        final far = math.sqrt(s.width * s.width + s.height * s.height);
        p.shader = ui.Gradient.radial(Offset(s.width * .7, s.height * .75), far * .62, [a, a, a.withValues(alpha: 0)], [0, .3 / .62, 1]);
        canvas.drawRect(rect, p);
        p.shader = null;
        p.color = hsl(h, .9, .82);
        canvas.drawCircle(Offset(s.width * .3, s.height * .28), far * .13 * .72, p);
        break;
      case 1:
        p.shader = cssLinear(s, 160, [a, c]);
        canvas.drawRect(rect, p);
        p
          ..shader = null
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = hsl(h, .8, .7, .45);
        final o = Offset(s.width * .72, s.height * .78);
        final maxR = math.sqrt(math.pow(math.max(o.dx, s.width - o.dx), 2) + math.pow(math.max(o.dy, s.height - o.dy), 2));
        for (double r = 2.5; r < maxR + 13; r += 13) {
          canvas.drawCircle(o, r, p);
        }
        break;
      case 2:
        final cc = Offset(s.width * .62, s.height * .40);
        final start = (210 - 90) * math.pi / 180;
        p.shader = ui.Gradient.sweep(cc, [a, b, c, hsl(h, .8, .72), a], [0, .25, .5, .75, 1], TileMode.clamp, start, start + math.pi * 2);
        canvas.drawRect(rect, p);
        break;
      default:
        p.shader = cssLinear(s, 20, [b, c]);
        canvas.drawRect(rect, p);
        final far = math.sqrt(s.width * s.width + s.height * s.height);
        final g = hsl(h + 60, .8, .6, .7);
        p.shader = ui.Gradient.radial(Offset(s.width * .8, s.height * .85), far * .5, [g, g.withValues(alpha: 0)]);
        canvas.drawRect(rect, p);
        final t = hsl(h, .74, .66);
        p.shader = cssLinear(s, 162, [t, t, t.withValues(alpha: 0), t.withValues(alpha: 0)], [0, .38, .385, 1]);
        canvas.drawRect(rect, p);
    }
  }

  @override
  bool shouldRepaint(CoverPainter o) => o.h != h || o.v != v;
}

/// 封面取色：返回 4 个用于流光背景的颜色（替代 palette_generator）。
List<Color> coverColors(double h) => [hsl(h, .72, .55), hsl(h + 40, .62, .38), hsl(h + 320, .7, .3), hsl(h + 180, .5, .4)];
