// 临时诊断：AmLyricView 下拉是否触发 onScrollUp(true)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/data/mock.dart';
import 'package:lyra/data/models.dart';
import 'package:lyra/player/am_lyrics.dart';

void main() {
  testWidgets('下拉 300 逻辑像素会唤起控制台', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    final app = AppState()..authed = true..autoPopups = false;
    lyrics
      ..clear()
      ..addAll([
        for (var i = 0; i < 20; i++)
          LyricLine(i * 3.0, 3, '第 $i 行歌词内容 $i', '', ''),
      ]);
    app.lyricsVersion++;
    app.pos.value = 10;

    final calls = <bool>[];
    await tester.pumpWidget(PalScope(
      pal: app.pal(Brightness.dark),
      child: AppScope(
        state: app,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 800,
              child: AmLyricView(
                anchor: .3,
                onScrollUp: calls.add,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // 往下拖 300 逻辑像素（看更早的词）
    await tester.drag(find.byType(AmLyricView), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.contains(true), isTrue, reason: '下拉应唤起控制台');

    // 往回拖 200 逻辑像素应收起
    await tester.drag(find.byType(AmLyricView), const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.contains(false), isTrue, reason: '反向拖动应收起控制台');

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
