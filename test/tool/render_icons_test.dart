// 生成启动器图标（Android / iOS / Web）：用 App 内同一个图标画法（lib/ui/brand.dart，默认「鎏金」款）。
// 平时跳过；需要重新生成时：RENDER_ICONS=1 flutter test test/tool/render_icons_test.dart，
// 结果在 build/icons/ 下，目录结构与工程一致（android/…、ios/…、web/…），直接覆盖即可。
// CI 里手动触发 .github/workflows/icons.yml 会跑这一步并上传产物。
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/ui/brand.dart';

const _id = 'gold';

Future<void> _png(String path, int px, {double radius = 0, IconLayer layer = IconLayer.full, double artScale = 1}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  paintAppIcon(c, Size(px.toDouble(), px.toDouble()), _id, radius: radius, layer: layer, artScale: artScale);
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File('build/icons/$path');
  await f.parent.create(recursive: true);
  await f.writeAsBytes(data!.buffer.asUint8List());
}

void main() {
  final on = Platform.environment['RENDER_ICONS'] == '1';
  testWidgets('render launcher icons', (tester) async {
    await tester.runAsync(() async {
      // Android 旧版图标（圆角方块）
      const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
      for (final e in dens.entries) {
        final d = 'android/app/src/main/res/mipmap-${e.key}';
        await _png('$d/ic_launcher.png', (48 * e.value).round(), radius: 23);
        // 自适应图标（Android 8+）：108dp 画布，前景缩进 66dp 安全区，底单独一层
        await _png('$d/ic_launcher_foreground.png', (108 * e.value).round(), layer: IconLayer.foreground, artScale: .6);
        await _png('$d/ic_launcher_background.png', (108 * e.value).round(), layer: IconLayer.background);
      }
      // iOS：方形、不透明（系统自己切圆角）
      const ios = {'20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60, '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87, '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120, '60x60@2x': 120, '60x60@3x': 180, '76x76@1x': 76, '76x76@2x': 152, '83.5x83.5@2x': 167, '1024x1024@1x': 1024};
      for (final e in ios.entries) {
        await _png('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-${e.key}.png', e.value);
      }
      // Web
      await _png('web/icons/Icon-192.png', 192, radius: 23);
      await _png('web/icons/Icon-512.png', 512, radius: 23);
      await _png('web/icons/Icon-maskable-192.png', 192, artScale: .8);
      await _png('web/icons/Icon-maskable-512.png', 512, artScale: .8);
      await _png('web/favicon.png', 64, radius: 23);
    });
  }, skip: !on);
}
