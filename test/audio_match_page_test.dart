// 听歌识曲界面：识别中 / 结果两种状态能渲染、无溢出（预览模式，不开麦克风）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/main.dart';
import 'package:lyra/pages/audio_match_page.dart';
import 'package:lyra/shell/shell.dart';
import 'package:lyra/widgets/sheets.dart';

void main() {
  for (final mode in ['listen', 'hit']) {
    testWidgets('audio match $mode', (tester) async {
      registerSheets();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      final app = AppState()..authed = true..autoPopups = false;
      await tester.pumpWidget(LyraApp(state: app));
      await tester.pump(const Duration(seconds: 1));
      pushFull(tester.element(find.byType(Shell)), Scaffold(body: AudioMatchView(preview: mode)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text(mode == 'hit' ? '其他识别结果' : '点击停止识别', skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      app.dispose();
      tester.view.resetPhysicalSize();
    });
  }
}
