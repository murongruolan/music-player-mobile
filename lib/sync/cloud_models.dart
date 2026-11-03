// 云端文档的通用模型与编解码：音乐库（收藏 + 歌单）、音源脚本。
//
// 同一个账号会被桌面端（music-player 的 desktop 分支，src/main/services/cloud-backup.ts）
// 和原版移动端格式（Sollin V2）读写，所以：
// - 解析时两种格式都认；
// - 导出时两种都写：桌面端读 `items`，V2 读 `favorites` / `playlists` / `sources`；
// - 解析时保留原始对象（raw），重新导出时原样带回，不丢其它端的字段。
// 平台代码：wy 网易云 · tx QQ · kg 酷狗 · kw 酷我 · mg 咪咕 · local 本地（本地歌曲不上传）。
import '../net/json.dart';

/// App 内平台 id ↔ 云端平台代码。
const platformCodes = {'netease': 'wy', 'qq': 'tx', 'kugou': 'kg', 'kuwo': 'kw', 'migu': 'mg'};

class CloudTrack {
  /// `<平台代码>:<平台歌曲 id>`
  final String id;
  final String platform, songId, title, artist, album;
  final int durationSec;
  final String? cover;
  final Json raw;
  const CloudTrack({required this.id, required this.platform, required this.songId, required this.title, required this.artist, this.album = '', this.durationSec = 0, this.cover, this.raw = const {}});

  bool get isLocal => platform == 'local' || platform.isEmpty;

  /// 桌面端 Track：{id, platform, title, artist, album, duration(秒), cover, qualities, identity}
  factory CloudTrack.fromDesktop(Json j) {
    final id = j.str('id');
    final platform = j.str('platform', id.contains(':') ? id.split(':').first : '');
    final songId = j.obj('identity').str('id', id.contains(':') ? id.substring(id.indexOf(':') + 1) : id);
    return CloudTrack(id: id.isEmpty ? '$platform:$songId' : id, platform: platform, songId: songId, title: j.str('title'), artist: j.str('artist'), album: j.str('album'), durationSec: j.integer('duration'), cover: j.strOrNull('cover'), raw: j);
  }

  /// V2 song：{name, artist, album, duration:"m:ss", songId, source, coverUrl, …}
  factory CloudTrack.fromV2(Json j) {
    final source = j.str('source');
    final songId = j.str('songId');
    return CloudTrack(id: '$source:$songId', platform: source, songId: songId, title: j.str('name'), artist: j.str('artist'), album: j.str('album'), durationSec: _parseDur(j['duration']), cover: j.strOrNull('coverUrl'), raw: j);
  }

  Json toDesktop() => {
        // 来自桌面端的保留全部原字段（qualityDetails 等）；来自 V2 的不带，避免混入 V2 字段名
        ...(raw.containsKey('identity') ? raw : const <String, dynamic>{}),
        'id': id,
        'platform': platform,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': durationSec,
        if (cover != null) 'cover': cover,
        'qualities': raw['qualities'] ?? const [],
        'identity': {...asJson(raw['identity']), 'id': songId},
      };

  Json toV2() => {
        'rank': 0,
        'name': title,
        'artist': artist,
        'album': album,
        'duration': '${durationSec ~/ 60}:${(durationSec % 60).toString().padLeft(2, '0')}',
        'songId': songId,
        'source': platform,
        'coverUrl': cover ?? '',
        for (final k in const ['songHash', 'albumId', 'albumAudioId', 'mediaMid', 'contentId', 'copyrightId', 'availableQualities'])
          if (raw.containsKey(k)) k: raw[k],
      };

  static int _parseDur(Object? v) {
    if (v is num) return v > 10000 ? v ~/ 1000 : v.toInt();
    if (v is String && v.contains(':')) {
      final p = v.split(':').map((e) => int.tryParse(e) ?? 0).toList();
      return p.fold(0, (a, b) => a * 60 + b);
    }
    return int.tryParse('$v') ?? 0;
  }
}

class CloudPlaylist {
  final String id, name, description;
  final String? cover;

  /// created = 自建；collected = 收藏的平台歌单（只同步平台 + id，歌曲各端自己拉）
  final String kind;
  final String? platform, externalId;
  final List<CloudTrack> tracks;
  final int? total;
  final DateTime updatedAt, createdAt;
  final Json raw;
  const CloudPlaylist({required this.id, required this.name, this.description = '', this.cover, this.kind = 'created', this.platform, this.externalId, this.tracks = const [], this.total, required this.updatedAt, required this.createdAt, this.raw = const {}});

  bool get compact => kind == 'collected' && platform != null && externalId != null;

  /// 桌面端 Playlist：{id, title, description, cover, platform, source, externalId, tracks, total, updatedAt}
  factory CloudPlaylist.fromDesktop(Json j) {
    final ext = j.strOrNull('externalId');
    final up = j.time('updatedAt') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return CloudPlaylist(
      id: j.str('id'),
      name: j.str('title', j.str('name')),
      description: j.str('description'),
      cover: j.strOrNull('cover'),
      kind: j.str('source') == 'local' || ext == null ? 'created' : 'collected',
      platform: j.strOrNull('platform'),
      externalId: ext,
      tracks: j.list('tracks', CloudTrack.fromDesktop),
      total: j.intOrNull('total'),
      updatedAt: up,
      createdAt: j.time('createdAt') ?? up,
      raw: j,
    );
  }

  /// V2 playlist：{id, name, description, coverUrl, kind, remoteSource, remotePlaylistId, songs:[{song, addedAtMs}], createdAtMs, updatedAtMs}
  factory CloudPlaylist.fromV2(Json j) => CloudPlaylist(
        id: j.str('id'),
        name: j.str('name'),
        description: j.str('description'),
        cover: j.strOrNull('coverUrl'),
        kind: j.str('kind', 'created'),
        platform: j.strOrNull('remoteSource'),
        externalId: j.strOrNull('remotePlaylistId'),
        tracks: [for (final s in j.list('songs', (e) => e)) CloudTrack.fromV2(s.objOrNull('song') ?? s)],
        total: j.intOrNull('songCountHint'),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j.integer('updatedAtMs')),
        createdAt: DateTime.fromMillisecondsSinceEpoch(j.integer('createdAtMs')),
        raw: j,
      );

  Json toDesktop() => {
        'id': id,
        'title': name,
        'description': description,
        if (cover != null) 'cover': cover,
        if (platform != null) 'platform': platform,
        'source': kind == 'created' ? 'local' : 'platform',
        if (externalId != null) 'externalId': externalId,
        'tracks': [for (final t in tracks) if (!t.isLocal) t.toDesktop()],
        'total': total ?? tracks.length,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  Json toV2() => {
        'id': id,
        'name': name,
        'description': description,
        'coverUrl': cover ?? '',
        'kind': kind,
        'remoteSource': platform,
        'remotePlaylistId': externalId,
        'songs': compact ? const [] : [for (final t in tracks) if (!t.isLocal) {'song': t.toV2(), 'addedAtMs': 0}],
        if (compact) ...{'songCountHint': total ?? tracks.length, 'compact': true},
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
      };
}

/// 音乐库 = 收藏 + 歌单。library 文档装两者；favorites / playlists 文档各装一半。
class CloudLibrary {
  final List<CloudTrack> favorites;
  final List<CloudPlaylist> playlists;
  const CloudLibrary({this.favorites = const [], this.playlists = const []});

  bool get isEmpty => favorites.isEmpty && playlists.isEmpty;

  // ---- library 文档 ----
  /// 桌面端格式 {format:2, items:{tracks, playlists}}；V2 格式 {format:2, favorites, playlists}（没有 items）。
  factory CloudLibrary.parse(Object? v) {
    final j = asJson(v);
    final items = j.objOrNull('items');
    if (items != null) {
      return CloudLibrary(favorites: items.list('tracks', CloudTrack.fromDesktop), playlists: items.list('playlists', CloudPlaylist.fromDesktop));
    }
    return CloudLibrary(
      favorites: [for (final e in j.list('favorites', (e) => e)) CloudTrack.fromV2(e.objOrNull('song') ?? e)],
      playlists: j.list('playlists', CloudPlaylist.fromV2),
    );
  }

  Json toPayload() {
    final favs = favorites.where((t) => !t.isLocal).toList();
    return {
      'format': 2,
      'items': {'tracks': [for (final t in favs) t.toDesktop()], 'playlists': [for (final p in playlists) p.toDesktop()]},
      'favorites': [for (final t in favs) {'song': t.toV2(), 'addedAtMs': 0}],
      'playlists': [for (final p in playlists) p.toV2()],
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // ---- favorites / playlists 文档（桌面端格式 {items: [...]}）----
  static List<CloudTrack> parseFavorites(Object? v) => asJson(v).list('items', CloudTrack.fromDesktop);
  static Json favoritesPayload(List<CloudTrack> l) => {'items': [for (final t in l) if (!t.isLocal) t.toDesktop()]};
  static List<CloudPlaylist> parsePlaylists(Object? v) => asJson(v).list('items', CloudPlaylist.fromDesktop);
  static Json playlistsPayload(List<CloudPlaylist> l) => {'items': [for (final p in l) p.toDesktop()]};

  /// 合并：收藏按 id 取并集（本机顺序在前）；歌单按 id，updatedAt 新的一方胜出。
  /// 没有删除标记：一端删了、另一端还有的会被合并回来（与桌面端一致）。
  static (CloudLibrary, bool) merge(CloudLibrary local, CloudLibrary remote) {
    final (favs, extraF) = mergeFavorites(local.favorites, remote.favorites);
    final (pls, extraP) = mergePlaylists(local.playlists, remote.playlists);
    return (CloudLibrary(favorites: favs, playlists: pls), extraF || extraP);
  }

  static (List<CloudTrack>, bool) mergeFavorites(List<CloudTrack> local, List<CloudTrack> remote) {
    final remoteIds = remote.map((t) => t.id).toSet();
    final localIds = local.map((t) => t.id).toSet();
    final extra = local.any((t) => !t.isLocal && !remoteIds.contains(t.id));
    return ([...local, for (final t in remote) if (!localIds.contains(t.id)) t], extra);
  }

  static (List<CloudPlaylist>, bool) mergePlaylists(List<CloudPlaylist> local, List<CloudPlaylist> remote) {
    final r = {for (final p in remote) p.id: p};
    var extra = false;
    final out = <CloudPlaylist>[];
    for (final p in local) {
      final o = r.remove(p.id);
      if (o == null) {
        extra = true;
        out.add(p);
      } else if (p.updatedAt.isAfter(o.updatedAt)) {
        extra = true;
        out.add(p);
      } else {
        out.add(o);
      }
    }
    out.addAll(r.values);
    return (out, extra);
  }
}

/// 洛雪（lx）音源脚本。
class CloudSource {
  final String id, name, rawScript, description, version, author, homepage;
  final String? sourceUrl;
  final bool isActive;
  final DateTime? addedAt;
  final Json raw;
  const CloudSource({required this.id, required this.name, required this.rawScript, this.description = '', this.version = '', this.author = '', this.homepage = '', this.sourceUrl, this.isActive = false, this.addedAt, this.raw = const {}});

  factory CloudSource.fromJson(Json j) {
    final info = j.objOrNull('info') ?? j;
    return CloudSource(
      id: j.str('id'),
      name: info.str('name'),
      rawScript: info.str('rawScript', j.str('rawScript')),
      description: info.str('description'),
      version: info.str('version'),
      author: info.str('author'),
      homepage: info.str('homepage'),
      sourceUrl: j.strOrNull('sourceUrl'),
      isActive: j.boolean('isActive'),
      addedAt: j.time('addedAt'),
      raw: j,
    );
  }

  Json toJson() => {
        ...raw,
        'id': id,
        'info': {'name': name, 'rawScript': rawScript, 'description': description, 'version': version, 'author': author, 'homepage': homepage},
        'addedAt': (addedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc().toIso8601String(),
        'isActive': isActive,
        'allowShowUpdateAlert': raw['allowShowUpdateAlert'] ?? true,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  /// {format:1, items, sources, activeSourceId}：两种格式都认（items 优先）。
  static (List<CloudSource>, String?) parse(Object? v) {
    final j = asJson(v);
    final l = j['items'] is List ? j.list('items', CloudSource.fromJson) : j.list('sources', CloudSource.fromJson);
    return (l, j.strOrNull('activeSourceId'));
  }

  static Json payload(List<CloudSource> l, String? activeId) {
    final items = [for (final s in l) s.toJson()];
    return {'format': 1, 'items': items, 'sources': items, 'activeSourceId': activeId, 'exportedAt': DateTime.now().toUtc().toIso8601String()};
  }

  /// 合并：按 id 取并集，同 id 以云端为准（脚本内容以最后上传的为准）。
  static (List<CloudSource>, bool) merge(List<CloudSource> local, List<CloudSource> remote) {
    final r = {for (final s in remote) s.id: s};
    final extra = local.any((s) => !r.containsKey(s.id));
    return ([for (final s in local) r.remove(s.id) ?? s, ...r.values], extra);
  }
}
