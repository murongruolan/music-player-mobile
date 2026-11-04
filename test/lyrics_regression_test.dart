// 歌词崩溃回归：换歌时歌词列表被整体替换（行数变化），旧的布局缓存 tops/hs
// 若不失效，按旧长度索引新列表会 RangeError（如 0..51: 52）。
// 对应用户实测：部分歌曲歌词区红屏报错、切歌时按钮区闪现报错。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/data/mock.dart';
import 'package:lyra/data/models.dart';
import 'package:lyra/player/lyrics.dart';

void main() {
  Future<void> boot(WidgetTester tester, AppState app, Widget body) async {
    await tester.pumpWidget(PalScope(
      pal: app.pal(Brightness.dark),
      child: AppScope(state: app, child: MaterialApp(home: Scaffold(body: body))),
    ));
  }

  Future<void> teardown(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(const SizedBox());
    app.dispose(); // 停掉 50ms 的模拟时钟，避免 pending timer
  }

  // 换歌序列：占位 1 行 → 真词 60 行（远多于 mock 的行数），每一步都不能抛异常
  testWidgets('换歌后歌词行数变多，布局缓存按版本失效，不再越界', (tester) async {
    tester.view.physicalSize = const Size(1170, 12000);
    tester.view.devicePixelRatio = 3;
    final app = AppState()..authed = true..autoPopups = false;
    await boot(tester, app, LyricView(align: TextAlign.left, fontSize: 6));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull, reason: '初始布局（mock 歌词 ${lyrics.length} 行）');

    // 换歌第 1 步：占位 1 行（LyricStore.load 的行为）
    lyrics
      ..clear()
      ..add(const LyricLine(0, 5, '测试歌曲 - 测试歌手', '', ''));
    app.lyricsVersion++;
    app.notify(); // LyricStore._set 的真实顺序：版本 + 通知，驱动歌词视图重建
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull, reason: '占位 1 行');

    // 换歌第 2 步：30 行真词（行数 > 首次布局的 16 行），并推进 pos 触发 _onPos 的 retarget 路径
    lyrics
      ..clear()
      ..addAll([for (var i = 0; i < 30; i++) LyricLine(i * 3.0, 3, '第 $i 行歌词内容', '', '')]);
    app.lyricsVersion++;
    app.notify(); // LyricStore._set 的真实顺序：版本 + 通知，驱动歌词视图重建
    app.pos.value = 30; // 落在第 10 行附近，触发 _retarget
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800)); // 切行动画走完
    expect(tester.takeException(), isNull, reason: '30 行真词 + retarget');
    // 重布局正确性：布局缓存必须覆盖新的 60 行（旧行为下还是旧歌的长度，
    // 新词按旧长度索引正是 RangeError 0..51:52 的来源）。几何无关、直接观测缓存。
    final st = tester.state(find.byType(LyricView)) as dynamic;
    expect(st.layoutLines, 30, reason: '布局缓存必须随换歌重测');
    expect((st.paintedLines as List<int>).contains(29), isTrue, reason: '第 29 行应已按新布局画出来');

    // 再反向收缩：60 行 → 3 行（tops 比 lyrics 长的场景也不能崩）
    lyrics
      ..clear()
      ..addAll([const LyricLine(0, 10, 'A', '', ''), const LyricLine(10, 10, 'B', '', ''), const LyricLine(20, 10, 'C', '', '')]);
    app.lyricsVersion++;
    app.notify(); // LyricStore._set 的真实顺序：版本 + 通知，驱动歌词视图重建
    app.pos.value = 15;
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: '行数收缩');

    tester.view.resetPhysicalSize();
    await teardown(tester, app);
  });

  // Lyric3（皮肤里的 3 行歌词）：空歌词窗口期不能崩
  testWidgets('Lyric3 空歌词窗口期显示空白而不是越界', (tester) async {
    final app = AppState()..authed = true..autoPopups = false;
    final saved = [...lyrics];
    lyrics.clear();
    await boot(tester, app, Lyric3());
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '空歌词');
    // 恢复全局歌词，避免影响同进程内的其他用例
    lyrics..clear()..addAll(saved);
    await tester.pump();
    await teardown(tester, app);
  });
}
