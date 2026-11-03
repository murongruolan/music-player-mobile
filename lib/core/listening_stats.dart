// 听歌统计：本机记录 + 云端 listening_stats 文档的读写与合并。
//
// 记录规则：一首歌本次播放累计听满 min(30 秒, 时长一半) 记一次播放；聆听时长按实际播放时间累计。
// 云端格式（与桌面端 / V2 一致）：
//   {format:1,
//    items:[{track:{id, platform, title, artist, album, duration}, playCount, totalSeconds, firstPlayedAt, lastPlayedAt, dailyPlays, hourlyPlays}],
//    stats:{songs:{"<平台>:<id>":{name, artist, album, source, songId, plays, ms, first, last, dailyPlays, hourlyPlays}}, days:{"YYYY-MM-DD":次数}, totalMs},
//    exportedAt}
// 合并（与桌面端 mergeStats 一致，幂等）：同一首歌各项取最大值，首次播放取最早、最近播放取最晚，按天 / 按小时计数取最大值。
// mock 歌曲（source = mock）只记在本机，不会上传。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../net/json.dart';
import '../net/storage.dart';

class SongStat {
  final String key, source, songId;
  String name, artist, album;
  int plays, ms, durationSec;
  DateTime? first, last;
  final Map<String, int> daily;
  final List<int> hourly;

  SongStat({required this.key, required this.source, required this.songId, this.name = '', this.artist = '', this.album = '', this.plays = 0, this.ms = 0, this.durationSec = 0, this.first, this.last, Map<String, int>? daily, List<int>? hourly})
      : daily = daily ?? {},
        hourly = hourly ?? List.filled(24, 0);

  bool get isMock => source == 'mock';

  /// 平均每次播放的时长；没有播放次数时按总时长算。
  double get msPerPlay => plays > 0 ? ms / plays : ms.toDouble();

  Json toV2() => {
        'name': name, 'artist': artist, 'album': album, 'source': source, 'songId': songId, 'durationMs': durationSec * 1000,
        'plays': plays, 'ms': ms, 'first': first?.millisecondsSinceEpoch, 'last': last?.millisecondsSinceEpoch,
        'dailyPlays': daily, 'hourlyPlays': hourly,
      };

  Json toItem() => {
        'track': {'id': key, 'platform': source, 'title': name, 'artist': artist, 'album': album, 'duration': durationSec, 'identity': {'id': songId}},
        'playCount': plays,
        'totalSeconds': ms ~/ 1000,
        'firstPlayedAt': first?.toUtc().toIso8601String(),
        'lastPlayedAt': last?.toUtc().toIso8601String(),
        'dailyPlays': daily,
        'hourlyPlays': hourly,
      };

  static SongStat fromItem(Json j) {
    final t = j.obj('track');
    final id = t.str('id');
    final source = t.str('platform', id.contains(':') ? id.split(':').first : '');
    return SongStat(
      key: id,
      source: source,
      songId: t.obj('identity').str('id', id.contains(':') ? id.substring(id.indexOf(':') + 1) : id),
      name: t.str('title'),
      artist: t.str('artist'),
      album: t.str('album'),
      durationSec: t.integer('duration'),
      plays: j.integer('playCount'),
      ms: j.integer('totalSeconds') * 1000,
      first: j.time('firstPlayedAt'),
      last: j.time('lastPlayedAt'),
      daily: _counts(j['dailyPlays']),
      hourly: _hours(j['hourlyPlays']),
    );
  }

  static SongStat fromV2(String key, Json j) {
    final source = j.str('source', key.contains(':') ? key.split(':').first : '');
    return SongStat(
      key: key,
      source: source,
      songId: j.str('songId', key.contains(':') ? key.substring(key.indexOf(':') + 1) : key),
      name: j.str('name'),
      artist: j.str('artist'),
      album: j.str('album'),
      durationSec: j.integer('durationMs') ~/ 1000,
      plays: j.integer('plays'),
      ms: j.integer('ms'),
      first: j.time('first'),
      last: j.time('last'),
      daily: _counts(j['dailyPlays']),
      hourly: _hours(j['hourlyPlays']),
    );
  }

  /// 合并另一份（取最大值）；返回本机是否有对方没有的数据。
  bool mergeFrom(SongStat o) {
    var extra = plays > o.plays || ms > o.ms;
    plays = math.max(plays, o.plays);
    ms = math.max(ms, o.ms);
    if (name.isEmpty) name = o.name;
    if (artist.isEmpty) artist = o.artist;
    if (album.isEmpty) album = o.album;
    if (durationSec == 0) durationSec = o.durationSec;
    if (o.first != null && (first == null || o.first!.isBefore(first!))) first = o.first;
    if (first != null && (o.first == null || first!.isBefore(o.first!))) extra = true;
    if (o.last != null && (last == null || o.last!.isAfter(last!))) last = o.last;
    for (final e in o.daily.entries) {
      final v = daily[e.key] ?? 0;
      if (e.value > v) daily[e.key] = e.value;
    }
    extra = extra || daily.entries.any((e) => e.value > (o.daily[e.key] ?? 0));
    for (var h = 0; h < 24; h++) {
      if (hourly[h] > o.hourly[h]) extra = true;
      hourly[h] = math.max(hourly[h], o.hourly[h]);
    }
    return extra;
  }

  static Map<String, int> _counts(Object? v) {
    if (v is! Map) return {};
    return {for (final e in v.entries) '${e.key}': (e.value is num ? (e.value as num).toInt() : int.tryParse('${e.value}') ?? 0)};
  }

  static List<int> _hours(Object? v) {
    final l = List.filled(24, 0);
    if (v is List) {
      for (var i = 0; i < math.min(24, v.length); i++) {
        final x = v[i];
        l[i] = x is num ? x.toInt() : 0;
      }
    }
    return l;
  }
}

/// 一段时间的汇总。
class StatsSummary {
  final int ms, plays, songs, artists;
  const StatsSummary(this.ms, this.plays, this.songs, this.artists);
}

class ListeningStats {
  final KvStore? _prefs;
  final DateTime Function() _now;
  final void Function() _changed;
  final songs = <String, SongStat>{};
  final days = <String, int>{};

  static const _key = 'stats.listening.v1';
  static const _maxSongs = 3000;

  // 当前这次播放
  SongStat? _cur;
  double _sessionSec = 0;
  bool _counted = false;
  Timer? _saveT;

  /// 本机数据变化（播放计数、清除、合并云端），同步引擎订阅它。
  void Function()? onLocalChange;

  ListeningStats(this._prefs, this._changed, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get isEmpty => songs.isEmpty;

  /// 云端文档意义上的「空」：只有 mock 歌曲。
  bool get cloudEmpty => !songs.values.any((s) => !s.isMock);

  int get totalMs => songs.values.fold(0, (a, s) => a + s.ms);

  // ---------------------------------------------------------------- 记录

  /// 开始播放一首歌（切歌 / 重新播放）。
  void begin({required String key, required String source, required String songId, required String name, required String artist, String album = '', int durationSec = 0}) {
    _cur = songs.putIfAbsent(key, () => SongStat(key: key, source: source, songId: songId));
    _cur!
      ..name = name
      ..artist = artist
      ..album = album
      ..durationSec = durationSec;
    _sessionSec = 0;
    _counted = false;
  }

  /// 播放中每次进度推进调用；[sec] 是这次推进的真实播放时间。
  void tick(double sec) {
    final s = _cur;
    if (s == null || sec <= 0 || sec > 5) return; // 大跳变（拖动进度、后台恢复）不算
    _sessionSec += sec;
    s.ms += (sec * 1000).round();
    final need = s.durationSec > 0 ? math.min(30, s.durationSec / 2) : 30;
    if (!_counted && _sessionSec >= need) {
      _counted = true;
      final now = _now();
      final d = dayKey(now);
      s.plays++;
      s.first ??= now;
      s.last = now;
      s.daily[d] = (s.daily[d] ?? 0) + 1;
      s.hourly[now.hour]++;
      days[d] = (days[d] ?? 0) + 1;
      _changed();
      onLocalChange?.call();
    }
    _scheduleSave();
  }

  // ---------------------------------------------------------------- 查询

  List<String> _lastDays(int n) {
    final today = _now();
    return [for (var i = n - 1; i >= 0; i--) dayKey(DateTime(today.year, today.month, today.day - i))];
  }

  /// 每首歌在某一天的估算时长 = 当天播放次数 × 平均每次时长（云端只有按天的次数）。
  StatsSummary summary(int nDays) {
    final ds = _lastDays(nDays).toSet();
    var ms = 0.0;
    var plays = 0;
    final sIds = <String>{}, artists = <String>{};
    for (final s in songs.values) {
      var p = 0;
      for (final d in ds) {
        p += s.daily[d] ?? 0;
      }
      if (p == 0) continue;
      plays += p;
      ms += p * s.msPerPlay;
      sIds.add(s.key);
      if (s.artist.isNotEmpty) artists.add(s.artist);
    }
    return StatsSummary(ms.round(), plays, sIds.length, artists.length);
  }

  /// 最近 n 天每天的聆听分钟数（旧 → 新）。
  List<int> dailyMinutes(int nDays) {
    final ds = _lastDays(nDays);
    return [
      for (final d in ds) (songs.values.fold<double>(0, (a, s) => a + (s.daily[d] ?? 0) * s.msPerPlay) / 60000).round(),
    ];
  }

  /// 最近 n 天每天的播放次数（旧 → 新），用于足迹热力图。
  List<int> dailyPlays(int nDays) {
    final ds = _lastDays(nDays);
    return [for (final d in ds) songs.values.fold<int>(0, (a, s) => a + (s.daily[d] ?? 0))];
  }

  /// 最近 n 天播放最多的歌手。
  List<(String, int)> topArtists(int nDays, {int limit = 6}) {
    final ds = _lastDays(nDays).toSet();
    final m = <String, int>{};
    for (final s in songs.values) {
      final p = ds.fold<int>(0, (a, d) => a + (s.daily[d] ?? 0));
      if (p > 0 && s.artist.isNotEmpty) m[s.artist] = (m[s.artist] ?? 0) + p;
    }
    final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in l.take(limit)) (e.key, e.value)];
  }

  // ---------------------------------------------------------------- 云端

  Json toPayload() {
    final l = songs.values.where((s) => !s.isMock).toList();
    final ds = <String, int>{};
    for (final s in l) {
      for (final e in s.daily.entries) {
        ds[e.key] = (ds[e.key] ?? 0) + e.value;
      }
    }
    return {
      'format': 1,
      'items': [for (final s in l) s.toItem()],
      'stats': {'songs': {for (final s in l) s.key: s.toV2()}, 'days': ds, 'totalMs': l.fold<int>(0, (a, s) => a + s.ms)},
      'exportedAt': _now().toUtc().toIso8601String(),
    };
  }

  /// 解析云端文档：items（桌面端）优先，否则 stats.songs（V2）。
  static List<SongStat> parse(Object? v) {
    final j = asJson(v);
    if (j['items'] is List && (j['items'] as List).isNotEmpty) return j.list('items', SongStat.fromItem);
    final m = j.obj('stats').obj('songs');
    return [for (final e in m.entries) if (e.value is Map) SongStat.fromV2(e.key, asJson(e.value))];
  }

  /// 应用云端数据。[replace] = 用云端覆盖本机（保留本机的 mock 记录）。返回本机是否有云端没有的数据。
  bool apply(Object? remote, {bool replace = false}) {
    final l = parse(remote);
    var extra = false;
    if (replace) songs.removeWhere((_, s) => !s.isMock);
    final remoteKeys = <String>{};
    for (final r in l) {
      remoteKeys.add(r.key);
      final s = songs[r.key];
      if (s == null) {
        songs[r.key] = r;
      } else {
        extra = s.mergeFrom(r) || extra;
      }
    }
    if (!replace) extra = extra || songs.values.any((s) => !s.isMock && !remoteKeys.contains(s.key));
    _rebuildDays();
    _trim();
    _changed();
    _scheduleSave(immediate: true);
    return extra;
  }

  /// 清除全部记录（本机）。云端由调用方推一份空文档。
  Future<void> clear() async {
    songs.clear();
    days.clear();
    _cur = null;
    _changed();
    await _save();
  }

  // ---------------------------------------------------------------- 持久化

  Future<void> load() async {
    final raw = await _prefs?.read(_key);
    if (raw == null) return;
    try {
      final j = asJson(jsonDecode(raw));
      for (final e in j.obj('songs').entries) {
        if (e.value is Map) songs[e.key] = SongStat.fromV2(e.key, asJson(e.value));
      }
      _rebuildDays();
      _changed();
    } catch (_) {}
  }

  void _rebuildDays() {
    days.clear();
    for (final s in songs.values) {
      for (final e in s.daily.entries) {
        days[e.key] = (days[e.key] ?? 0) + e.value;
      }
    }
  }

  /// 歌太多时丢掉最久没听的，控制本地存储大小。
  void _trim() {
    if (songs.length <= _maxSongs) return;
    final l = songs.values.toList()..sort((a, b) => (a.last ?? DateTime(0)).compareTo(b.last ?? DateTime(0)));
    for (final s in l.take(songs.length - _maxSongs)) {
      songs.remove(s.key);
    }
  }

  void _scheduleSave({bool immediate = false}) {
    if (_prefs == null) return;
    if (immediate) {
      _saveT?.cancel();
      _saveT = null;
      unawaited(_save());
      return;
    }
    _saveT ??= Timer(const Duration(seconds: 15), () {
      _saveT = null;
      unawaited(_save());
    });
  }

  /// App 进后台时调用，立刻落盘。
  Future<void> flush() async {
    _saveT?.cancel();
    _saveT = null;
    await _save();
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.write(_key, jsonEncode({'v': 1, 'songs': {for (final s in songs.values) s.key: s.toV2()}}));
  }

  void dispose() => _saveT?.cancel();
}
