// Markdown 渲染（公告用）：dart-lang/markdown 解析成 AST，这里转成 Flutter 组件。
//
// 支持：标题、段落、粗体 / 斜体 / 删除线、行内代码、代码块、链接、图片、有序 / 无序 / 任务列表、引用、分隔线、表格。
// 纯文字公告：段落里的单个换行保留成换行（不像标准 Markdown 那样合并成空格），所以按行写的通知原样显示。
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import 'icons.dart';

List<md.Node> parseMarkdown(String text) {
  final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
  return doc.parse(text.replaceAll('\r\n', '\n'));
}

/// 去掉 Markdown 标记的纯文字（列表预览用）。图片显示为「[图片]」。
String markdownPlain(String text) {
  final out = StringBuffer();
  void walk(md.Node n) {
    if (n is md.Text) {
      out.write(_entities(n.text));
    } else if (n is md.Element) {
      if (n.tag == 'img') {
        out.write('[图片]');
        return;
      }
      if (n.tag == 'br') {
        out.write(' ');
        return;
      }
      for (final c in n.children ?? const <md.Node>[]) {
        walk(c);
      }
      if (_blockTags.contains(n.tag) || n.tag == 'li' || n.tag == 'tr' || n.tag == 'td' || n.tag == 'th') out.write(' ');
    }
  }

  try {
    for (final n in parseMarkdown(text)) {
      walk(n);
    }
  } catch (_) {
    return text;
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _blockTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'blockquote', 'ul', 'ol', 'pre', 'hr', 'table', 'section', 'div'};

String _entities(String s) => s.contains('&')
    ? s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp);'), (m) {
        final e = m[1]!;
        switch (e) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return "'";
          case 'nbsp':
            return '\u00a0';
        }
        final code = e.startsWith('#x') || e.startsWith('#X') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code == null ? m[0]! : String.fromCharCode(code);
      })
    : s;

/// 打开链接：只放行 http / https / mailto。
Future<void> openMarkdownLink(String href) async {
  final u = Uri.tryParse(href.trim());
  if (u == null || !const {'http', 'https', 'mailto'}.contains(u.scheme)) return;
  try {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class MarkdownView extends StatefulWidget {
  final String data;

  /// 正文样式；默认 14 号 t2 色。
  final TextStyle? style;

  /// 点链接（测试可替换）；默认用系统浏览器打开。
  final void Function(String href)? onLink;
  const MarkdownView(this.data, {super.key, this.style, this.onLink});
  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _rec = <TapGestureRecognizer>[];
  List<md.Node>? _nodes;
  String? _parsed;

  @override
  void dispose() {
    _clearRec();
    super.dispose();
  }

  void _clearRec() {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
  }

  List<md.Node> get nodes {
    if (_parsed != widget.data) {
      _parsed = widget.data;
      try {
        _nodes = parseMarkdown(widget.data);
      } catch (_) {
        _nodes = [md.Element('p', [md.Text(widget.data)])];
      }
    }
    return _nodes!;
  }

  @override
  Widget build(BuildContext context) {
    _clearRec();
    final pal = context.pal;
    final base = widget.style ?? ts(14, c: pal.t2, h: 1.7);
    final b = _Builder(this, pal, base);
    final children = b.blocks(nodes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _Builder {
  final _MarkdownViewState s;
  final Pal pal;
  final TextStyle base;
  _Builder(this.s, this.pal, this.base);

  static const _gap = 10.0;
  TextStyle get mono => base.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'Courier New'], fontSize: (base.fontSize ?? 14) * .92);

  bool _isBlock(md.Node n) => n is md.Element && (_blockTags.contains(n.tag) || n.tag == 'li');

  /// 一组节点 → 块级组件。连续的行内节点合成一个段落。
  List<Widget> blocks(List<md.Node> nodes, {TextStyle? style}) {
    final st = style ?? base;
    final out = <Widget>[];
    var inline = <md.Node>[];
    void flush() {
      if (inline.isEmpty) return;
      out.addAll(_paragraph(inline, st));
      inline = [];
    }

    for (final n in nodes) {
      if (_isBlock(n)) {
        flush();
        final w = _block(n as md.Element, st);
        if (w != null) out.add(w);
      } else {
        inline.add(n);
      }
    }
    flush();
    // 块之间留间距
    return [
      for (var i = 0; i < out.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : _gap), child: out[i]),
    ];
  }

  /// 段落：图片单独成块，其余是富文本。
  List<Widget> _paragraph(List<md.Node> nodes, TextStyle st) {
    final out = <Widget>[];
    var run = <md.Node>[];
    void flush() {
      // 去掉图片两侧只剩空白 / 换行的文字
      if (run.every((n) => n is md.Text && n.text.trim().isEmpty)) {
        run = [];
        return;
      }
      out.add(Text.rich(TextSpan(style: st, children: _inlines(run, st))));
      run = [];
    }

    for (final n in nodes) {
      if (n is md.Element && n.tag == 'img') {
        flush();
        out.add(_MdImage(n.attributes['src'] ?? '', n.attributes['alt'] ?? '', pal));
      } else {
        run.add(n);
      }
    }
    flush();
    if (out.length <= 1) return out;
    return [Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < out.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: out[i])])];
  }

  Widget? _block(md.Element e, TextStyle st) {
    final kids = e.children ?? const <md.Node>[];
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = const {'h1': 21.0, 'h2': 19.0, 'h3': 17.0, 'h4': 15.5, 'h5': 14.5, 'h6': 14.0}[e.tag]!;
        final hs = base.copyWith(fontSize: size, fontWeight: FontWeight.w800, color: pal.t1, height: 1.4);
        return Padding(padding: EdgeInsets.only(top: e.tag == 'h1' || e.tag == 'h2' ? 4 : 0), child: Text.rich(TextSpan(style: hs, children: _inlines(kids, hs))));
      case 'p':
        final p = _paragraph(kids, st);
        return p.isEmpty ? null : p.single;
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(color: pal.s2.withValues(alpha: .6), border: Border(left: BorderSide(color: pal.acc.withValues(alpha: .7), width: 3)), borderRadius: const BorderRadius.horizontal(right: Radius.circular(8))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(kids, style: st.copyWith(color: pal.t3))),
        );
      case 'ul' || 'ol':
        final ordered = e.tag == 'ol';
        final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        final items = kids.whereType<md.Element>().where((x) => x.tag == 'li').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, li) in items.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 4), child: _li(li, st, ordered ? '${start + i}.' : '•')),
        ]);
      case 'li':
        return _li(e, st, '•');
      case 'pre':
        final code = _text(e).replaceAll(RegExp(r'\n$'), '');
        return Container(
          decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.line)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(code, style: mono.copyWith(color: pal.t1, height: 1.5)),
          ),
        );
      case 'hr':
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Container(height: 1, color: pal.line));
      case 'table':
        return _table(e, st);
      default:
        // section / div / 不认识的块：只渲染内容
        final b = blocks(kids, style: st);
        return b.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: b);
    }
  }

  Widget _li(md.Element li, TextStyle st, String mark) {
    var kids = li.children ?? const <md.Node>[];
    Widget lead = SizedBox(width: 22, child: Text(mark, style: st.copyWith(color: pal.t3, fontWeight: FontWeight.w700)));
    // 任务列表：- [x] 已完成
    final first = kids.isNotEmpty ? kids.first : null;
    md.Element? box;
    if (first is md.Element && first.tag == 'input') box = first;
    if (box == null && first is md.Element && first.tag == 'p' && (first.children?.isNotEmpty ?? false) && first.children!.first is md.Element && (first.children!.first as md.Element).tag == 'input') {
      box = first.children!.first as md.Element;
      kids = [md.Element(first.tag, first.children!.sublist(1)), ...kids.skip(1)];
    } else if (box != null) {
      kids = kids.sublist(1);
    }
    if (box != null) {
      final on = box.attributes.containsKey('checked');
      lead = SizedBox(width: 24, child: Padding(padding: const EdgeInsets.only(top: 3), child: Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 17, color: on ? pal.accText : pal.t3)));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      lead,
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(kids, style: st))),
    ]);
  }

  Widget _table(md.Element e, TextStyle st) {
    final rows = <(bool head, List<md.Element> cells)>[];
    void collect(md.Element x, bool head) {
      for (final c in (x.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (c.tag == 'thead') {
          collect(c, true);
        } else if (c.tag == 'tbody') {
          collect(c, false);
        } else if (c.tag == 'tr') {
          rows.add((head, (c.children ?? const <md.Node>[]).whereType<md.Element>().toList()));
        }
      }
    }

    collect(e, false);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.fold<int>(0, (m, r) => r.$2.length > m ? r.$2.length : m);
    final small = st.copyWith(fontSize: (st.fontSize ?? 14) * .93, height: 1.45);
    TextAlign align(md.Element c) => switch (c.attributes['align'] ?? c.attributes['style']?.replaceAll(RegExp(r'.*text-align:\s*'), '').replaceAll(';', '')) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: pal.line, borderRadius: BorderRadius.circular(8)),
        children: [
          for (final (head, cells) in rows)
            TableRow(
              decoration: head ? BoxDecoration(color: pal.s2) : null,
              children: [
                for (var i = 0; i < cols; i++)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: i < cells.length
                          ? Text.rich(TextSpan(style: head ? small.copyWith(fontWeight: FontWeight.w700, color: pal.t1) : small, children: _inlines(cells[i].children ?? const [], head ? small.copyWith(fontWeight: FontWeight.w700, color: pal.t1) : small)), textAlign: align(cells[i]))
                          : const SizedBox(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _text(md.Node n) => n is md.Text ? _entities(n.text) : (n is md.Element ? (n.children ?? const <md.Node>[]).map(_text).join() : '');

  /// 行内节点 → TextSpan。
  List<InlineSpan> _inlines(List<md.Node> nodes, TextStyle st) => [for (final n in nodes) _inline(n, st)];

  InlineSpan _inline(md.Node n, TextStyle st) {
    if (n is md.Text) return TextSpan(text: _entities(n.text));
    if (n is! md.Element) return const TextSpan();
    final kids = n.children ?? const <md.Node>[];
    switch (n.tag) {
      case 'strong':
        final bold = st.copyWith(fontWeight: FontWeight.w800, color: pal.t1);
        return TextSpan(style: bold, children: _inlines(kids, bold));
      case 'em':
        final italic = st.copyWith(fontStyle: FontStyle.italic);
        return TextSpan(style: italic, children: _inlines(kids, italic));
      case 'del':
        final strike = st.copyWith(decoration: TextDecoration.lineThrough, color: pal.t3);
        return TextSpan(style: strike, children: _inlines(kids, strike));
      case 'code':
        return TextSpan(text: _text(n), style: mono.copyWith(color: pal.accText, backgroundColor: pal.s2));
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = n.attributes['href'] ?? '';
        final link = st.copyWith(color: pal.accText, decoration: TextDecoration.underline, decorationColor: pal.accText.withValues(alpha: .5));
        final r = TapGestureRecognizer()
          ..onTap = () {
            final f = s.widget.onLink;
            f != null ? f(href) : openMarkdownLink(href);
          };
        s._rec.add(r);
        return TextSpan(style: link, recognizer: r, children: [for (final k in kids) _linkChild(k, link, r)]);
      case 'img':
        // 正常情况下图片已经在段落里拆成块；表格 / 标题里的图片退化成文字
        final alt = n.attributes['alt'] ?? '';
        return TextSpan(text: alt.isEmpty ? '[图片]' : '[$alt]', style: st.copyWith(color: pal.t3));
      case 'input':
        return TextSpan(text: n.attributes.containsKey('checked') ? '☑ ' : '☐ ');
      default:
        return TextSpan(children: _inlines(kids, st));
    }
  }

  /// 链接里的子节点也要能点（TextSpan 的 recognizer 不向下继承）。
  InlineSpan _linkChild(md.Node k, TextStyle x, TapGestureRecognizer r) {
    final span = _inline(k, x);
    if (span is TextSpan && span.recognizer == null) return TextSpan(text: span.text, style: span.style, children: span.children, recognizer: r);
    return span;
  }
}

class _MdImage extends StatelessWidget {
  final String src, alt;
  final Pal pal;
  const _MdImage(this.src, this.alt, this.pal);

  Widget _fail() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(ic('image'), size: 18, color: pal.t3),
          const SizedBox(width: 8),
          Expanded(child: Text(alt.isEmpty ? '图片加载失败' : '图片加载失败：$alt', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12.5, c: pal.t3))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final u = src.trim();
    Widget img;
    if (u.startsWith('data:image/')) {
      final i = u.indexOf('base64,');
      if (i < 0) return _fail();
      try {
        img = Image.memory(base64Decode(u.substring(i + 7)), fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fail());
      } catch (_) {
        return _fail();
      }
    } else if (u.startsWith('http://') || u.startsWith('https://')) {
      img = Image.network(
        u,
        fit: BoxFit.contain,
        loadingBuilder: (_, ch, p) => p == null ? ch : Container(height: 160, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: pal.t3))),
        errorBuilder: (_, __, ___) => _fail(),
      );
    } else {
      return _fail();
    }
    return Semantics(
      image: true,
      label: alt,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Align(alignment: Alignment.centerLeft, child: img)),
      ),
    );
  }
}
