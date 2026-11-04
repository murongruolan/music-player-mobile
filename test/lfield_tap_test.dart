// 输入框：点浮动标签 / 图标也能聚焦（标签在输入区上方，手指常点到标签上）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/core/tokens.dart';
import 'package:lyra/widgets/sheets.dart';

void main() {
  testWidgets('点标签和图标都让输入框获得焦点', (tester) async {
    final app = AppState();
    await tester.pumpWidget(AppScope(
      state: app,
      child: PalScope(
        pal: Pal.of(true, accents[0]),
        child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(20), child: LField(label: '服务器地址', icon: 'globe')))),
      ),
    ));
    EditableTextState edit() => tester.state<EditableTextState>(find.byType(EditableText));
    expect(edit().widget.focusNode.hasFocus, isFalse);

    await tester.tap(find.text('服务器地址'));
    await tester.pump();
    expect(edit().widget.focusNode.hasFocus, isTrue);

    edit().widget.focusNode.unfocus();
    await tester.pump();
    expect(edit().widget.focusNode.hasFocus, isFalse);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    expect(edit().widget.focusNode.hasFocus, isTrue);
    app.dispose();
  });
}
