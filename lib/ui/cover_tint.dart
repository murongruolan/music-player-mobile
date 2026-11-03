// 封面取色：从真实封面图里取主色，给播放器的流光背景、声波 / 粒子等按色相着色的效果用。
// 没有封面（mock 歌曲）或还没取到时，退回按歌曲色相生成的颜色（coverColors）。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import 'cover.dart';

class CoverTint {
  CoverTint._();
  static final _colors = <String, List<Color>>{};
  static final _hues = <String, double>{};
  static final _pending = <String>{}, _failed = <String>{};

  /// 取到新的颜色后通知（main.dart 接到 AppState.notify，播放器随之重绘）。
  static void Function()? onReady;

  static List<Color>? colorsOf(String? url) => url == null ? null : _colors[url];
  static double? hueOf(String? url) => url == null ? null : _hues[url];

  /// 后台取色（每个地址只取一次）。
  static void ensure(String? url) {
    final u = coverUrl(url);
    if (url == null || u == null || _colors.containsKey(url) || _failed.contains(url) || !_pending.add(url)) return;
    final stream = ResizeImage(NetworkImage(u), width: 24, height: 24).resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) async {
      stream.removeListener(l);
      try {
        final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null) {
          final (colors, hue) = paletteOf(data.buffer.asUint8List());
          _colors[url] = colors;
          _hues[url] = hue;
          onReady?.call();
        }
      } catch (_) {
      } finally {
        _pending.remove(url);
      }
    }, onError: (_, __) {
      stream.removeListener(l);
      _pending.remove(url);
      _failed.add(url);
    });
    stream.addListener(l);
  }
}

/// 从 RGBA 像素里取 4 个颜色（主色、次色、暗色、补色）和主色相。
/// 按色相分 24 个桶，权重 = 饱和度 × 亮度（灰白像素几乎不计），取权重最高的两个桶。
(List<Color>, double) paletteOf(List<int> rgba) {
  final w = List<double>.filled(24, 0), sumS = List<double>.filled(24, 0), sumV = List<double>.filled(24, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final r = rgba[i] / 255, g = rgba[i + 1] / 255, b = rgba[i + 2] / 255;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final d = mx - mn;
    if (mx < .08) continue;
    final s = mx == 0 ? 0.0 : d / mx;
    double h;
    if (d == 0) {
      h = 0;
    } else if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
    if (h < 0) h += 360;
    final k = (h / 15).floor() % 24;
    final wt = s * s * mx + .002;
    w[k] += wt;
    sumS[k] += s * wt;
    sumV[k] += mx * wt;
  }
  final order = List.generate(24, (i) => i)..sort((a, b) => w[b].compareTo(w[a]));
  final a = order.first;
  // 次色：和主色至少隔 3 个桶（45°），否则用主色偏移
  final b = order.skip(1).firstWhere((x) => ((x - a).abs() % 24) >= 3 && ((x - a).abs() % 24) <= 21 && w[x] > w[a] * .15, orElse: () => (a + 3) % 24);
  double hueOf(int k) => k * 15 + 7.5;
  double sat(int k) => w[k] == 0 ? .5 : (sumS[k] / w[k]).clamp(.25, .85);
  final ha = hueOf(a), hb = hueOf(b);
  final sa = sat(a), sb = sat(b);
  // 灰白封面：饱和度太低时整体按低饱和处理，避免硬加颜色
  final grey = w[a] < .02 * rgba.length / 4;
  final colors = [
    hsl(ha, grey ? .12 : sa, .52),
    hsl(hb, grey ? .1 : sb * .9, .38),
    hsl(ha + 10, grey ? .08 : sa * .8, .24),
    hsl(hb + 180, grey ? .08 : .45, .38),
  ];
  return (colors, ha);
}

/// 播放器背景用的 4 个颜色。
List<Color> songColors(Song s) {
  CoverTint.ensure(s.cover);
  return CoverTint.colorsOf(s.cover) ?? coverColors(s.hue);
}

/// 按色相着色的效果用的色相。
double songHue(Song s) {
  CoverTint.ensure(s.cover);
  return CoverTint.hueOf(s.cover) ?? s.hue;
}
