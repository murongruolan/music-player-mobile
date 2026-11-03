import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/main.dart';
import 'package:lyra/widgets/sheets.dart';

Future<void> _boot(WidgetTester tester, AppState app) async {
  registerSheets();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(LyraApp(state: app));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _done(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  app.dispose();
  tester.view.resetPhysicalSize();
}

void main() {
  testWidgets('auth flow renders', (tester) async {
    final app = AppState();
    await _boot(tester, app);
    expect(find.text('使用须知'), findsOneWidget);
    await _done(tester, app);
  });

  testWidgets('every tab renders', (tester) async {
    final app = AppState()..authed = true..autoPopups = false;
    await _boot(tester, app);
    for (var t = 0; t < 5; t++) {
      app.update(() => app.tab = t);
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    }
    await _done(tester, app);
  });

  testWidgets('every bar style renders', (tester) async {
    final app = AppState()..authed = true..autoPopups = false;
    await _boot(tester, app);
    for (final b in ['liquid', 'island', 'capsule', 'frosted', 'classic', 'cutout', 'dock', 'bubble', 'text']) {
      app.update(() => app.bar = b);
      await tester.pump(const Duration(milliseconds: 600));
    }
    await _done(tester, app);
  });
}
