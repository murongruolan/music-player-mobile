// 设计令牌：与原型 css/tokens.css、tokens.json 一一对应。
import 'dart:math' as math;
import 'package:flutter/material.dart';

class Accent {
  final String name;
  final Color fill, textOnLight, ink;
  const Accent(this.name, this.fill, this.textOnLight, this.ink);
}

const accents = <Accent>[
  Accent('鎏金', Color(0xFFF4D28A), Color(0xFF93650F), Color(0xFF1B1508)),
  Accent('星蓝', Color(0xFF8AB4FF), Color(0xFF2F5FD0), Color(0xFF08142B)),
  Accent('极光', Color(0xFF6EE7C8), Color(0xFF0E8A6C), Color(0xFF04201A)),
  Accent('霓紫', Color(0xFFB79CFF), Color(0xFF6B45D6), Color(0xFF160A33)),
  Accent('樱粉', Color(0xFFFF9CC2), Color(0xFFC23A72), Color(0xFF2B0816)),
  Accent('赤焰', Color(0xFFFF7A66), Color(0xFFC93C28), Color(0xFF2B0A05)),
];

/// 一套完整的配色（深 / 浅 × 主题色）。通过 [Lc.of] 取用。
class Pal {
  final bool dark;
  final Accent accent;
  final Color bg, bgElev, s1, s2, s3, line, lineStrong, t1, t2, t3, t4, glass, glassStrong;
  const Pal._(this.dark, this.accent, this.bg, this.bgElev, this.s1, this.s2, this.s3, this.line, this.lineStrong, this.t1,
      this.t2, this.t3, this.t4, this.glass, this.glassStrong);

  factory Pal.of(bool dark, Accent a) => dark
      ? Pal._(true, a, const Color(0xFF0A0B11), const Color(0xFF101119), const Color(0xFF14151D), const Color(0xFF1A1C26),
          const Color(0xFF242735), const Color(0x12FFFFFF), const Color(0x24FFFFFF), const Color(0xFFF3F4F8),
          const Color(0xFFA6ABBB), const Color(0xFF6C7186), const Color(0xFF454A5C), const Color(0x9414151E),
          const Color(0xD1181922))
      : Pal._(false, a, const Color(0xFFF5F5F8), Colors.white, Colors.white, const Color(0xFFEEF0F4),
          const Color(0xFFE3E6EC), const Color(0x12000000), const Color(0x24000000), const Color(0xFF12131A),
          const Color(0xFF5A5F6F), const Color(0xFF8C91A1), const Color(0xFFC2C6D0), const Color(0xA8FFFFFF),
          const Color(0xE6FFFFFF));

  /// 播放器、深色 Sheet 永远使用深色令牌。
  Pal get forceDark => dark ? this : Pal.of(true, accent);

  Color get acc => accent.fill;
  Color get accText => dark ? accent.fill : accent.textOnLight;
  Color get ink => accent.ink;
  Color get accSoft => accent.fill.withValues(alpha: dark ? .14 : .16);
  Color get accGlow => accent.fill.withValues(alpha: .38);
  Color get ok => const Color(0xFF4CD39B);
  Color get warn => const Color(0xFFFFC266);
  Color get danger => const Color(0xFFFF6B6B);
}

class Tk {
  static const pad = 20.0;
  static const rowH = 64.0;
  static const out = Cubic(.22, 1, .36, 1);
  static const standard = Cubic(.4, 0, .2, 1);
  static const spring = Cubic(.34, 1.56, .64, 1);
  static const softSpring = Cubic(.3, 1.25, .5, 1);
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
  static const playerOpen = Duration(milliseconds: 460);
  static const lyric = Duration(milliseconds: 720);
  static const numFont = 'monospace';
}

const settingTiles = <String, Color>{
  'violet': Color(0xFF7C6CF2), 'blue': Color(0xFF3D8BF4), 'orange': Color(0xFFF2994A), 'green': Color(0xFF2FB47C),
  'red': Color(0xFFEB5757), 'pink': Color(0xFFE0559B), 'gold': Color(0xFFC9A04A), 'cyan': Color(0xFF2CB5D6),
  'gray': Color(0xFF6E7385), 'teal': Color(0xFF1FA38E),
};

Color hsl(double h, double s, double l, [double a = 1]) =>
    HSLColor.fromAHSL(a, h % 360, s.clamp(0, 1), l.clamp(0, 1)).toColor();

/// 数字使用等宽 tabular 字形（对应原型 --font-num）。
const numFeatures = [FontFeature.tabularFigures()];

TextStyle ts(double size, {FontWeight w = FontWeight.w500, Color? c, double? h, double? ls, bool num = false}) => TextStyle(
    fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls, fontFeatures: num ? numFeatures : null);

double ease(double t) => 1 - math.pow(1 - t.clamp(0, 1), 3).toDouble();
