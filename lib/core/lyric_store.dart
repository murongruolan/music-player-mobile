// 当前歌曲的歌词（联网模式）：从歌曲所在平台拉 LRC + 翻译，换成播放器用的 LyricLine，写进全局 `lyrics`。
// 拿不到歌词时放一行「歌名 - 歌手」，播放器的各种歌词视图都至少有一行可显示。
import 'dart:async';
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

/// 平台歌词 → 播放器歌词行：时间（秒）、时长、正文、翻译。
List<LyricLine> toLyricLines(Lyric l, int durationSec) {
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
  return out;
}
