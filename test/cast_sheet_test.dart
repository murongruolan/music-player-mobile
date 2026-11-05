// 投放面板：扫描结束后要停下来显示结果（回归：状态写在 StatefulBuilder 里，每次重建都重置成「扫描中」）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/main.dart';
import 'package:lyra/shell/shell.dart';
import 'package:lyra/widgets/sheets.dart';

void main() {
  testWidgets('cast sheet leaves the scanning state', (tester) async {
    registerSheets();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    final app = AppState()..authed = true..autoPopups = false;
    await tester.pumpWidget(LyraApp(state: app));
    await tester.pump(const Duration(seconds: 1));
    openCast(tester.element(find.byType(Shell)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    // 测试环境没有投放控制器：扫描立刻结束，应显示空态而不是一直转
    expect(find.textContaining('未发现可投放的设备', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    app.dispose();
    tester.view.resetPhysicalSize();
  });
}
