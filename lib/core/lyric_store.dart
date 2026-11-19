// 当前歌曲的歌词（联网模式）：从歌曲所在平台拉 LRC + 翻译，换成播放器用的 LyricLine，写进全局 `lyrics`。
// 拿不到歌词时放一行「歌名 - 歌手」，播放器的各种歌词视图都至少有一行可显示。
import 'dart:async';
import 'dart:math' as math;
import '../data/mock.dart';
import '../data/models.dart';
import '../platform/lyric_parse.dart';
import '../platform/models.dart';
import 'state.dart';

class LyricStore {
  final AppState _app;
  int _for = -1;
  int _seq = 0;
  final _cache = <String, List<LyricLine>>{};

  LyricStore(this._app);

  /// 清掉缓存的歌词（设置 → 关于 → 清除缓存）。当前这首不受影响。
  void clear() => _cache.clear();

  /// 歌曲 [id] 开始播放时调用。
  void load(int id) {
    if (id == _for || id < 0 || id >= songs.length) return;
    _for = id;
    final s = songs[id];
    final seq = ++_seq;
    final key = s.key;
    final hit = key == null ? null : _cache[key];
    if (hit != null) return _set(hit);
    _set([LyricLine(0, 1e6, s.title, s.artist, '')]);
    final t = _app.library.trackOf(id);
    if (t == null || t.isLocal || !_app.content.supports(t.platform)) return;
    final identity = t.raw['identity'] is Map ? Map<String, dynamic>.from(t.raw['identity'] as Map) : <String, dynamic>{};
    final track = PTrack(platform: t.platform, nativeId: t.songId, title: t.title, artist: t.artist, album: t.album, duration: t.durationSec, cover: t.cover, identity: identity);
    unawaited(_app.content.lyric(track).then((l) {
      final lines = toLyricLines(l, t.durationSec);
      if (lines.isEmpty) return;
      if (key != null) _cache[key] = lines;
      if (seq == _seq) _set(lines);
    }, onError: (_) {}));
  }

  void _set(List<LyricLine> l) {
    lyrics
      ..clear()
      ..addAll(l);
    _app.lyricsVersion++; // 歌词视图的布局缓存失效（换歌后行数变了，旧 tops/hs 不能再按旧长度用）
    _app.notify();
  }

  /// 重置（退出登录 / 清空队列）。
  void reset() {
    _for = -1;
    _seq++;
  }
}

/// 平台歌词 → 播放器歌词行：时间（秒）、时长、正文、翻译；有逐字时间时带上逐字（填充跟着演唱走）。
List<LyricLine> toLyricLines(Lyric l, int durationSec) {
  final words = l.words;
  if (words != null && words.isNotEmpty) {
    final lines = _fromWords(words, l.translation);
    final clean = _dropLeadingCredits(lines);
    if (clean.isNotEmpty) return clean;
  }
  final base = parseLrc(l.lrc).where((x) => x.text.trim().isNotEmpty).toList();
  if (base.isEmpty) return const [];
  final trans = alignTimeline([for (final x in base) x.time], l.translation);
  final out = <LyricLine>[];
  for (var i = 0; i < base.length; i++) {
    final t = base[i].time / 1000;
    final next = i + 1 < base.length ? base[i + 1].time / 1000 : (durationSec > t ? durationSec.toDouble() : t + 5);
    final d = (next - t).clamp(.3, 30.0).toDouble();
    out.add(LyricLine(t, d, base[i].text.trim(), (trans[i] ?? '').trim(), ''));
  }
  return _dropLeadingCredits(out);
}

/// 平台歌词常在开头塞「歌名 - 歌手」「词：xxx」「曲：xxx」「编曲：xxx」等
/// 制作信息。Apple Music 的歌词页不展示这些，它们还会把真正要唱的第一句
/// 推到屏幕下半部分。只清掉开头连续的制作信息，后面正文里出现同样字样不动。
final _creditPrefix = RegExp(
  r'^\s*(作词|作曲|编曲|制作人|监制|混音|母带|录音|和声|出品|发行|版权|OP|SP|策划|统筹|吉他|贝斯|鼓手|键盘|弦乐|封面|视觉|文案|演唱|原唱|翻唱|词|曲)\s*[：:]',
  caseSensitive: false,
);
final _titleArtist = RegExp(r'^\s*[^，。！？]{1,40}\s*[-–—]\s*[^，。！？]{1,40}\s*$');

bool _isCredit(String text) {
  final t = text.trim();
  return _creditPrefix.hasMatch(t) || _titleArtist.hasMatch(t);
}

List<LyricLine> _dropLeadingCredits(List<LyricLine> lines) {
  var i = 0;
  while (i < lines.length && i < 10 && _isCredit(lines[i].text)) {
    i++;
  }
  return i == 0 ? lines : lines.sublist(i);
}

List<LyricLine> _fromWords(List<LyricLineWords> src, String? translation) {
  final rows = [...src.where((x) => x.words.isNotEmpty && x.words.any((w) => w.text.trim().isNotEmpty))]..sort((a, b) => a.start.compareTo(b.start));
  if (rows.isEmpty) return const [];
  final trans = alignTimeline([for (final r in rows) r.start], translation);
  final out = <LyricLine>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final buf = StringBuffer();
    final ws = <LyricWord>[];
    for (final w in r.words) {
      final from = buf.length;
      buf.write(w.text);
      if (w.text.isEmpty) continue;
      ws.add(LyricWord(w.start / 1000, w.duration / 1000, from, buf.length));
    }
    // 去掉行首行尾空白，词的下标跟着平移
    final raw = buf.toString();
    final lead = raw.length - raw.trimLeft().length;
    final text = raw.trim();
    final shifted = [
      for (final w in ws)
        if (w.to - lead > 0 && w.from - lead < text.length) LyricWord(w.start, w.dur, (w.from - lead).clamp(0, text.length), (w.to - lead).clamp(0, text.length)),
    ];
    final t = r.start / 1000;
    final lineEnd = r.duration > 0 ? (r.start + r.duration) / 1000 : (shifted.isEmpty ? t + 3 : shifted.last.start + shifted.last.dur);
    final next = i + 1 < rows.length ? rows[i + 1].start / 1000 : lineEnd + 2;
    out.add(LyricLine(t, (math.max(lineEnd, next) - t).clamp(.3, 60.0).toDouble(), text, (trans[i] ?? '').trim(), '', words: shifted));
  }
  return out;
}
