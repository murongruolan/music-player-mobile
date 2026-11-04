// 本机音乐库（联网模式）：歌曲目录、我喜欢、自建 / 收藏的歌单、搜索历史。
//
// - 歌曲目录：全局 `songs` 列表在联网模式下清空，只放真实歌曲（来自云同步的音乐库、以后的平台搜索 / 本地扫描）。
//   页面里用 `songs[id]` 的地方因此不用改；真实歌曲带 key（`<平台代码>:<歌曲 id>`）和封面地址。
// - 持久化：整个音乐库以 library 同步文档的格式存在本机（prefs），启动时恢复。
// - 同步：实现 [LibraryBinding]，赞助用户开启云同步后与桌面端等其它设备互通（见 sync/）。
import 'dart:async';
import 'dart:convert';
import '../data/mock.dart';
import '../data/models.dart';
import '../net/storage.dart';
import '../sync/cloud_models.dart';
import '../sync/docs.dart';
import 'state.dart';

class LibraryStore implements LibraryBinding {
  final AppState _app;
  final KvStore? _prefs;
  final _byKey = <String, int>{};
  final _tracks = <int, CloudTrack>{};
  final _plRaw = <int, CloudPlaylist>{};
  Timer? _saveT;

  /// 本机修改（收藏、建歌单、改歌单）后通知同步引擎。
  void Function()? onLocalChange;

  static const _kLib = 'library.v1', _kHistory = 'search.history.v1';
  static const likedPlaylistId = 100;

  LibraryStore(this._app, this._prefs);

  // ---------------------------------------------------------------- 歌曲目录

  /// 把一首真实歌曲放进目录，返回它在 `songs` 里的 id（同 key 只放一次）。
  int register(CloudTrack t) {
    final k = t.id;
    final hit = _byKey[k];
    if (hit != null) {
      _tracks[hit] = t;
      return hit;
    }
    final id = songs.length;
    songs.add(Song(id, t.title.isEmpty ? '未知歌曲' : t.title, t.artist, t.album, t.durationSec, _quality(t), _hue(k), k.hashCode.abs() % 6, key: k, cover: t.cover));
    _byKey[k] = id;
    _tracks[id] = t;
    return id;
  }

  CloudTrack? trackOf(int id) => _tracks[id];

  /// 按歌曲 key（`<平台>:<平台歌曲 id>`）反查它在目录里的 id；没注册过返回 null。
  int? idOfKey(String key) => _byKey[key];

  static double _hue(String k) => (k.hashCode.abs() % 360).toDouble();

  static String _quality(CloudTrack t) {
    final q = t.raw['qualities'];
    if (q is List && q.isNotEmpty) {
      final s = q.map((e) => '$e').join(' ').toLowerCase();
      if (s.contains('flac24') || s.contains('hires') || s.contains('hi-res')) return 'Hi-Res';
      if (s.contains('flac') || s.contains('sq')) return 'SQ';
    }
    return 'HQ';
  }

  // ---------------------------------------------------------------- LibraryBinding

  @override
  CloudLibrary read() => CloudLibrary(
        favorites: [for (final id in _app.liked) if (_tracks[id] != null) _tracks[id]!],
        playlists: [for (final p in _app.myPlaylists) if (p.isReal) _toCloud(p)],
      );

  @override
  void write(CloudLibrary lib) {
    _apply(lib);
    _scheduleSave();
    _app.notify();
  }

  void _apply(CloudLibrary lib) {
    _app.liked
      ..clear()
      ..addAll([for (final t in lib.favorites) if (!t.isLocal) register(t)]);
    _plRaw.clear();
    _app.myPlaylists
      ..clear()
      ..addAll([for (final (i, p) in lib.playlists.indexed) _fromCloud(p, 200 + i)]);
  }

  Playlist _fromCloud(CloudPlaylist p, int id) {
    final ids = [for (final t in p.tracks) if (!t.isLocal) register(t)];
    _plRaw[id] = p;
    return Playlist(
      id,
      p.name.isEmpty ? '未命名歌单' : p.name,
      count: p.total ?? ids.length,
      hue: _hue(p.id),
      variant: p.id.hashCode.abs() % 6,
      mine: true,
      tag: p.kind == 'collected' ? '收藏' : null,
      ids: ids,
      key: p.id,
      platform: p.platform,
      externalId: p.externalId,
      kind: p.kind,
      updatedAt: p.updatedAt,
      createdAt: p.createdAt,
      cover: _displayCover(p.cover, ids),
    );
  }

  /// 歌单显示用的封面：歌单自己的封面，没有就用第一首有封面的歌。
  String? _displayCover(String? own, List<int> ids) {
    if (own != null && own.isNotEmpty) return own;
    for (final id in ids) {
      final c = _tracks[id]?.cover;
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  CloudPlaylist _toCloud(Playlist p) {
    final raw = _plRaw[p.id];
    return CloudPlaylist(
      id: p.key!,
      name: p.title,
      description: raw?.description ?? '',
      // 只同步歌单自己的封面，不把「第一首歌的封面」写回云端
      cover: raw?.cover,
      kind: p.kind,
      platform: p.platform,
      externalId: p.externalId,
      tracks: [for (final id in p.ids) if (_tracks[id] != null) _tracks[id]!],
      total: p.kind == 'collected' ? p.count : p.ids.length,
      updatedAt: p.updatedAt ?? DateTime.now().toUtc(),
      createdAt: p.createdAt ?? p.updatedAt ?? DateTime.now().toUtc(),
      raw: raw?.raw ?? const {},
    );
  }

  // ---------------------------------------------------------------- 本机修改

  /// 收藏变化后调用。
  void favoritesChanged() => _changed();

  Playlist createPlaylist(String name, double hue) {
    final now = DateTime.now().toUtc();
    final id = _app.myPlaylists.fold<int>(199, (m, p) => p.id > m ? p.id : m) + 1;
    final p = Playlist(id, name, count: 0, hue: hue, variant: 2, mine: true, key: 'm${now.microsecondsSinceEpoch}', kind: 'created', updatedAt: now, createdAt: now);
    _app.myPlaylists.add(p);
    _changed();
    return p;
  }

  /// 已收藏的平台歌单（按平台代码 + 平台歌单 id 找）。
  Playlist? collectedOf(String platform, String externalId) =>
      _app.myPlaylists.where((p) => p.kind == 'collected' && p.platform == platform && p.externalId == externalId).firstOrNull;

  /// 收藏平台歌单：只记平台 + 歌单 id（与桌面端一致，歌曲各端打开时自己拉）。已收藏的直接返回。
  Playlist collect({required String platform, required String externalId, required String name, String? cover, String description = '', int? total}) {
    final hit = collectedOf(platform, externalId);
    if (hit != null) return hit;
    final now = DateTime.now().toUtc();
    final id = _app.myPlaylists.fold<int>(199, (m, p) => p.id > m ? p.id : m) + 1;
    final key = '$platform-$externalId';
    _plRaw[id] = CloudPlaylist(id: key, name: name, description: description, cover: cover, kind: 'collected', platform: platform, externalId: externalId, total: total, updatedAt: now, createdAt: now);
    final p = Playlist(id, name.isEmpty ? '未命名歌单' : name, count: total ?? 0, hue: _hue(key), variant: key.hashCode.abs() % 6, mine: true, tag: '收藏', key: key, platform: platform, externalId: externalId, kind: 'collected', updatedAt: now, createdAt: now, cover: cover);
    _app.myPlaylists.add(p);
    _changed();
    return p;
  }

  /// 把歌加进歌单（已在里面的跳过）。返回实际新增数量。
  int addToPlaylist(int playlistId, Iterable<int> songIds) {
    final i = _app.myPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) return 0;
    final p = _app.myPlaylists[i];
    final add = [for (final s in songIds) if (!p.ids.contains(s) && _tracks.containsKey(s)) s];
    if (add.isEmpty) return 0;
    _replace(i, p, [...p.ids, ...add]);
    return add.length;
  }

  void removeFromPlaylist(int playlistId, Set<int> songIds) {
    final i = _app.myPlaylists.indexWhere((p) => p.id == playlistId);
    if (i < 0) return;
    final p = _app.myPlaylists[i];
    _replace(i, p, [for (final s in p.ids) if (!songIds.contains(s)) s]);
  }

  void deletePlaylist(int playlistId) {
    _app.myPlaylists.removeWhere((p) => p.id == playlistId);
    _plRaw.remove(playlistId);
    _changed();
  }

  void _replace(int i, Playlist p, List<int> ids) {
    _app.myPlaylists[i] = Playlist(p.id, p.title, count: ids.length, hue: p.hue, variant: p.variant, mine: true, tag: p.tag, ids: ids, key: p.key, platform: p.platform, externalId: p.externalId, kind: p.kind, updatedAt: DateTime.now().toUtc(), createdAt: p.createdAt, cover: _displayCover(_plRaw[p.id]?.cover, ids));
    _changed();
  }

  void _changed() {
    _scheduleSave();
    _app.notify();
    onLocalChange?.call();
  }

  // ---------------------------------------------------------------- 持久化

  Future<void> load() async {
    final p = _prefs;
    if (p == null) return;
    try {
      final raw = await p.read(_kLib);
      if (raw != null) _apply(CloudLibrary.parse(jsonDecode(raw)));
      final h = await p.read(_kHistory);
      if (h != null) {
        _app.history
          ..clear()
          ..addAll((jsonDecode(h) as List).map((e) => '$e').take(20));
      }
    } catch (_) {
      // 本地数据损坏：当作空库
    }
  }

  void saveHistory() {
    final p = _prefs;
    if (p == null) return;
    unawaited(p.write(_kHistory, jsonEncode(_app.history.take(20).toList())));
  }

  void _scheduleSave() {
    if (_prefs == null) return;
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 500), () => unawaited(flush()));
  }

  Future<void> flush() async {
    _saveT?.cancel();
    _saveT = null;
    await _prefs?.write(_kLib, jsonEncode(read().toPayload(keepDav: true))); // 云盘歌曲只存本机
  }

  /// 退出登录：清空本机音乐库（下一个账号从云端重新同步）。
  Future<void> reset() async {
    _saveT?.cancel();
    _app.liked.clear();
    _app.myPlaylists.clear();
    _app.history.clear();
    _plRaw.clear();
    await _prefs?.delete(_kLib);
    await _prefs?.delete(_kHistory);
    _app.notify();
  }

  void dispose() => _saveT?.cancel();
}
