import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/state.dart';
import 'package:lyra/core/tokens.dart';
import 'package:lyra/ui/markdown.dart';

Widget _wrap(Widget child) => MaterialApp(home: PalScope(pal: Pal.of(true, accents[0]), child: Material(child: SingleChildScrollView(child: child))));

/// 页面上所有 RichText 的纯文本。
String _allText(WidgetTester tester) => tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');

void main() {
  test('纯文字预览：去掉标记，图片写成 [图片]', () {
    expect(markdownPlain('# 标题\n\n**加粗** 和 *斜体*，`code` [链接](https://a.b)\n\n![图](https://x/y.png)\n\n- 一\n- 二'), '标题 加粗 和 斜体，code 链接 [图片] 一 二');
    expect(markdownPlain('第一行\n第二行'), '第一行 第二行');
    expect(markdownPlain('A &amp; B'), 'A & B');
  });

  testWidgets('纯文字公告保留换行', (tester) async {
    await tester.pumpWidget(_wrap(const MarkdownView('第一行\n第二行\n\n第二段')));
    final t = _allText(tester);
    expect(t, contains('第一行\n第二行'));
    expect(t, contains('第二段'));
  });

  testWidgets('常用 Markdown：标题、强调、列表、引用、代码、表格、分隔线', (tester) async {
    const doc = '''
# 版本 2.0

**重要**：*请更新* ~~旧版~~，运行 `flutter run`。

1. 第一步
2. 第二步

- [x] 已完成
- [ ] 未完成

> 引用内容

```
code block
```

---

| 名称 | 值 |
| :-- | --: |
| a | 1 |
''';
    await tester.pumpWidget(_wrap(const MarkdownView(doc)));
    expect(tester.takeException(), isNull);
    final t = _allText(tester);
    for (final s in ['版本 2.0', '重要', '请更新', '旧版', 'flutter run', '第一步', '2.', '已完成', '引用内容', 'code block', '名称', '值']) {
      expect(t, contains(s), reason: s);
    }
    expect(find.byType(Table), findsOneWidget);
    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
  });

  testWidgets('图片单独成块，加载失败显示说明', (tester) async {
    await tester.pumpWidget(_wrap(const MarkdownView('看图：\n\n![活动海报](https://example.invalid/a.png)\n\n![坏图](javascript:alert)')));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('图片加载失败：坏图'), findsOneWidget);
  });

  testWidgets('点链接回调 href', (tester) async {
    String? got;
    await tester.pumpWidget(_wrap(MarkdownView('打开 [官网](https://lyra.app)', onLink: (h) => got = h)));
    final rich = tester.widgetList<RichText>(find.byType(RichText)).firstWhere((r) => r.text.toPlainText().contains('官网'));
    var tapped = false;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == '官网' && s.recognizer is TapGestureRecognizer) {
        (s.recognizer! as TapGestureRecognizer).onTap!();
        tapped = true;
        return false;
      }
      return true;
    });
    expect(tapped, isTrue);
    expect(got, 'https://lyra.app');
  });
}
