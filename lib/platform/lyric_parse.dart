// 各平台通用的歌词文本解析（纯函数，不依赖任何平台）。
// 对齐桌面端 lyric-parser.ts（parseTimed / alignTimeline）与 platform-crypto.ts（parseTencentQrcLines 等）。
//
// 逐字格式速查（时间均为毫秒）：
//   网易 YRC：  [行开始,行时长](字开始,字时长,0)字(字开始,字时长,0)字      —— 字时间是绝对时间，标记在字前
//   QQ QRC：    [行开始,行时长]字(字开始,字时长)字(字开始,字时长)          —— 绝对时间，标记在字后
//   酷狗 KRC：  [行开始,行时长]<偏移,字时长,0>字<偏移,字时长,0>字          —— 相对行开始，标记在字前
//   转换后扩展：[mm:ss.xxx]<偏移,字时长>字                                 —— parseQrcText 产出的 extended
import 'models.dart';

final _lrcTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _wordMarker = RegExp(r'\((\d+),(\d+)(?:,-?\d+)?\)|<(-?\d+),(-?\d+)(?:,-?\d+)?>');
final _msLine = RegExp(r'^\[(\d+),(\d+)(?:,\d+)?\](.*)$');
final _lrcLine = RegExp(r'^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\](.*)$');

int _ms(String min, String sec, String? frac) => (int.parse(min) * 60 + int.parse(sec)) * 1000 + int.parse((frac ?? '0').padRight(3, '0').substring(0, 3));

/// LRC 时间标签 → 毫秒。接受 `[01:02.34]`、`01:02.345`、`01:02:34`、`01:02`；不是时间标签返回 null。
/// 小数部分按位补齐（`.3` = 300ms，`.34` = 340ms），与桌面端一致。
int? lrcTimeMs(String tag) {
  final m = RegExp(r'^\[?\s*(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\s*\]?$').firstMatch(tag.trim());
  return m == null ? null : _ms(m[1]!, m[2]!, m[3]);
}

/// 毫秒 → `[mm:ss.xxx]`（桌面端 qrcTimestamp）。
String lrcTimestamp(int milliseconds) {
  final ms = milliseconds < 0 ? 0 : milliseconds;
  final rest = ms % 60000;
  return '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${(rest ~/ 1000).toString().padLeft(2, '0')}.${(rest % 1000).toString().padLeft(3, '0')}]';
}

/// 去掉逐字时间标记：`<a,b>` `<a,b,c>` `(a,b)` `(a,b,c)`，得到可直接显示的文本。
String stripWordTags(String text) => text.replaceAll(_wordMarker, '');

/// 解析标准 LRC：返回按时间排序的 (毫秒, 文本)。一行多个时间标签会展开成多行；空文本行丢弃。
/// 同时兼容 `[行开始,行时长]` 毫秒行头（YRC / QRC / KRC）。文本里的逐字标记会被去掉。
List<({int time, String text})> parseLrc(String? text) {
  if (text == null || text.isEmpty) return const [];
  final out = <({int time, String text})>[];
  for (final raw in _lines(text)) {
    final ms = _msLine.firstMatch(raw);
    if (ms != null) {
      final value = stripWordTags(ms[3]!).trim();
      if (value.isNotEmpty) out.add((time: int.parse(ms[1]!), text: value));
      continue;
    }
    final tags = _lrcTag.allMatches(raw).toList();
    if (tags.isEmpty || tags.first.start != 0) continue;
    // 只认行首连续的时间标签，后面的都是正文
    var end = 0;
    final times = <int>[];
    for (final t in tags) {
      if (t.start != end) break;
      times.add(_ms(t[1]!, t[2]!, t[3]));
      end = t.end;
    }
    final value = stripWordTags(raw.substring(end)).trim();
    if (value.isEmpty) continue;
    for (final t in times) {
      out.add((time: t, text: value));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

Iterable<String> _lines(String text) => text.replaceFirst('\uFEFF', '').replaceAll('\r', '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

/// 把翻译 / 音译按时间对齐到主歌词（桌面端 alignTimeline）：结果与 [baseTimes] 等长，对不上的位置为 null。
/// 规则：顺序扫描，取时间最近的主歌词行，差值 < 100ms 才算同一行。
List<String?> alignTimeline(List<int> baseTimes, String? auxiliary) {
  final aligned = List<String?>.filled(baseTimes.length, null);
  if (baseTimes.isEmpty) return aligned;
  var i = 0;
  for (final line in parseLrc(auxiliary)) {
    while (i + 1 < baseTimes.length && (baseTimes[i + 1] - line.time).abs() <= (baseTimes[i] - line.time).abs()) {
      i++;
    }
    if (i >= baseTimes.length) break;
    if ((baseTimes[i] - line.time).abs() < 100) {
      aligned[i] = line.text;
      i++;
      if (i >= baseTimes.length) break;
    }
  }
  return aligned;
}

/// 合并翻译：主歌词每行后面紧跟同时间的翻译行（导出 / 不支持双行显示的场景用）。
String mergeTranslation(String lrc, String? translation) {
  final base = parseLrc(lrc);
  if (base.isEmpty || translation == null || translation.trim().isEmpty) return lrc;
  final aligned = alignTimeline([for (final l in base) l.time], translation);
  final out = <String>[];
  for (var i = 0; i < base.length; i++) {
    final stamp = lrcTimestamp(base[i].time);
    out.add('$stamp${base[i].text}');
    final t = aligned[i];
    if (t != null && t.isNotEmpty) out.add('$stamp$t');
  }
  return out.join('\n');
}

/// 通用逐字歌词解析。行头支持 `[开始,时长]`（毫秒）和 `[mm:ss.xxx]`；
/// 字标记 `(开始,时长[,x])` 是绝对时间，`<偏移,时长[,x]>` 相对行开始。
/// 标记在行首时文本跟在标记后面（YRC / KRC），否则文本在标记前面（QRC 原文）。
/// 无法识别的行（元数据、JSON 署名行等）跳过；结果按行开始时间排序。
List<LyricLineWords> parseWordLines(String? text) {
  if (text == null || text.isEmpty) return const [];
  final out = <LyricLineWords>[];
  for (final raw in _lines(text)) {
    int start;
    int? lineDuration;
    String body;
    final ms = _msLine.firstMatch(raw);
    if (ms != null) {
      start = int.parse(ms[1]!);
      lineDuration = int.parse(ms[2]!);
      body = ms[3]!;
    } else {
      final l = _lrcLine.firstMatch(raw);
      if (l == null) continue;
      start = _ms(l[1]!, l[2]!, l[3]);
      body = l[4]!;
    }
    final line = _parseWordBody(start, lineDuration, body);
    if (line != null) out.add(line);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

LyricLineWords? _parseWordBody(int lineStart, int? lineDuration, String body) {
  final marks = _wordMarker.allMatches(body).toList();
  final words = <({int start, int duration, String text})>[];
  int wordStart(RegExpMatch m) => m[1] != null ? int.parse(m[1]!) : lineStart + int.parse(m[3]!);
  int wordDuration(RegExpMatch m) {
    final d = int.parse(m[2] ?? m[4]!);
    return d < 0 ? 0 : d;
  }

  if (marks.isNotEmpty && marks.first.start == 0) {
    // 标记在前：文本 = 本标记结束到下一个标记开始
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final t = body.substring(m.end, i + 1 < marks.length ? marks[i + 1].start : body.length);
      if (t.isNotEmpty) words.add((start: wordStart(m), duration: wordDuration(m), text: t));
    }
  } else if (marks.isNotEmpty) {
    // 标记在后（QRC）：文本 = 上一个标记结束到本标记开始；末尾多出来的文本按上一字结束时间补一个字
    var cursor = 0;
    for (final m in marks) {
      final t = body.substring(cursor, m.start);
      if (t.isNotEmpty) {
        final s = wordStart(m);
        words.add((start: s < lineStart ? lineStart : s, duration: wordDuration(m), text: t));
      }
      cursor = m.end;
    }
    final tail = body.substring(cursor);
    if (tail.isNotEmpty) {
      final prev = words.isEmpty ? null : words.last;
      final s = prev == null ? lineStart : (prev.start + prev.duration < lineStart ? lineStart : prev.start + prev.duration);
      final end = lineDuration == null ? s : lineStart + lineDuration;
      words.add((start: s, duration: end > s ? end - s : 0, text: tail));
    }
  }
  final text = (marks.isEmpty ? body : words.map((w) => w.text).join()).trim();
  if (text.isEmpty) return null;
  var duration = lineDuration ?? 0;
  if (lineDuration == null && words.isNotEmpty) {
    final end = words.last.start + words.last.duration;
    duration = end > lineStart ? end - lineStart : 0;
  }
  return LyricLineWords(lineStart, duration, text, words);
}

/// 网易云 YRC 逐字歌词。开头的 `{"t":0,"c":[...]}` JSON 署名行会被跳过。
List<LyricLineWords> parseYrc(String text) => parseWordLines(text.split('\n').where((l) => !l.trimLeft().startsWith('{')).join('\n'));

/// XML 实体解码（QRC 外层 XML 用）。`&amp;` 最后处理，避免二次解码。
String decodeXmlEntities(String value) => value
    .replaceAll(RegExp('&quot;', caseSensitive: false), '"')
    .replaceAll(RegExp('&apos;', caseSensitive: false), "'")
    .replaceAll(RegExp('&lt;', caseSensitive: false), '<')
    .replaceAll(RegExp('&gt;', caseSensitive: false), '>')
    .replaceAll(RegExp('&amp;', caseSensitive: false), '&');

/// 从 QRC 的 XML 外壳里取出 `LyricContent="..."`；没有外壳原样返回。
String extractQrcContent(String value) {
  final m = RegExp(r'''LyricContent\s*=\s*(["'])([\s\S]*?)\1''', caseSensitive: false).firstMatch(value);
  return m == null ? value : decodeXmlEntities(m[2]!);
}

/// 解密后的 QRC 文本 → 标准 LRC（[lyric]）+ 逐字扩展格式（[extended]，`[mm:ss.xxx]<偏移,时长>字`，可交给 [parseWordLines]）。
/// 输入可以带 XML 外壳。没有任何逐字时间行时 lyric 原样返回、extended 为空串（桌面端 decodeTencentLyric 的兜底）。
({String lyric, String extended}) parseQrcText(String text) {
  final source = text.replaceFirst('\uFEFF', '').replaceAll('\r', '');
  if (source.trim().isEmpty) return (lyric: '', extended: '');
  final content = RegExp(r'^\s*<').hasMatch(source) ? extractQrcContent(source) : source;
  final lyricLines = <String>[];
  final extendedLines = <String>[];
  var timed = false;
  for (final line in content.replaceAll('\r', '').split('\n').map((l) => l.trim())) {
    if (line.isEmpty) continue;
    final m = RegExp(r'^\[\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*\d+)?\s*\](.*)$').firstMatch(line);
    if (m == null) {
      // 保留 [ti:] [ar:] 之类的元数据行
      if (RegExp(r'^\[[a-z]+\s*:', caseSensitive: false).hasMatch(line)) lyricLines.add(line);
      continue;
    }
    timed = true;
    final lineStart = int.parse(m[1]!);
    final parsed = _parseQrcWords(lineStart, int.parse(m[2]!), m[3] ?? '');
    final visible = parsed.map((w) => w.text).join().trim();
    if (visible.isEmpty) continue;
    final stamp = lrcTimestamp(lineStart);
    lyricLines.add('$stamp$visible');
    if (parsed.isNotEmpty) {
      extendedLines.add('$stamp${parsed.map((w) => '<${w.start - lineStart < 0 ? 0 : w.start - lineStart},${w.duration}>${w.text}').join()}');
    }
  }
  if (!timed || lyricLines.isEmpty) return (lyric: source, extended: '');
  return (lyric: lyricLines.join('\n'), extended: extendedLines.join('\n'));
}

/// QRC 行内：`字(开始,时长)`，标记在字后；行尾无标记的文本按上一字结束时间补齐到行尾。
List<({int start, int duration, String text})> _parseQrcWords(int lineStart, int lineDuration, String rest) {
  final lineEnd = lineStart + (lineDuration < 0 ? 0 : lineDuration);
  final words = <({int start, int duration, String text})>[];
  var cursor = 0;
  for (final m in RegExp(r'\(\s*(\d+)\s*,\s*(\d+)\s*\)').allMatches(rest)) {
    final t = rest.substring(cursor, m.start);
    if (t.isNotEmpty) {
      final s = int.parse(m[1]!);
      words.add((start: s < lineStart ? lineStart : s, duration: int.parse(m[2]!), text: t));
    }
    cursor = m.end;
  }
  final tail = rest.substring(cursor);
  if (tail.isNotEmpty) {
    final prev = words.isEmpty ? null : words.last;
    final s = prev == null ? lineStart : (prev.start + prev.duration < lineStart ? lineStart : prev.start + prev.duration);
    words.add((start: s, duration: lineEnd - s < 0 ? 0 : lineEnd - s, text: tail));
  }
  return words;
}
