// 曲目 → 洛雪脚本认识的 musicInfo（桌面端 source-worker.ts#toLegacyTrack 的移植），以及音质回退顺序。
import '../net/json.dart';
import '../sync/cloud_models.dart';

/// 音质从高到低（桌面端 music-service.ts FALLBACK）。
const qualityFallback = ['master', 'atmos_plus', 'atmos', 'hires', 'flac24bit', 'flac', '320k', '128k'];

/// App 的音质档位（设置里的 onlineQ）→ 洛雪音质。
String lxQualityOf(String appQuality) => switch (appQuality) {
      '128k' || '标准' => '128k',
      'HQ' => '320k',
      'SQ' => 'flac',
      'Hi-Res' => 'flac24bit',
      'Dolby' => 'atmos',
      'Atmos' => 'atmos_plus',
      'Master' => 'master',
      _ => 'flac',
    };

/// 洛雪音质 → 界面上的档位名（qualities 里的 key）。
String appQualityOf(String lx) => switch (lx) {
      '128k' => '128k',
      '320k' => 'HQ',
      'flac' => 'SQ',
      'flac24bit' || 'hires' || 'master' => 'Hi-Res',
      'atmos' => 'Dolby',
      'atmos_plus' => 'Atmos',
      _ => 'HQ',
    };

/// 从偏好音质往下找第一个「歌曲有、音源也支持」的档位（桌面端 qualityOrder）。
String? pickQuality(String preferred, List<String> track, List<String> source) {
  final tier = preferred == 'flac24bit' ? 'hires' : preferred;
  final start = qualityFallback.indexOf(tier).clamp(0, qualityFallback.length - 1);
  final have = track.toSet();
  for (final t in qualityFallback.skip(start)) {
    final aliases = t == 'hires' || t == 'flac24bit' ? const ['hires', 'flac24bit'] : [t];
    for (final q in aliases) {
      if (source.contains(q) && aliases.any(have.contains)) return q;
    }
  }
  return null;
}

/// 本机曲目（云同步 / 平台列表登记的）→ 桌面端 Track 结构：{id, platform, title, artist, album, duration, cover, qualities, qualityDetails, identity}。
Json lxTrackOf(CloudTrack t) {
  final d = t.toDesktop();
  final identity = <String, dynamic>{...asJson(d['identity'])};
  // V2 格式的字段名换成桌面端的
  final raw = t.raw;
  void alias(String from, String to) {
    if (identity[to] == null && raw[from] != null) identity[to] = raw[from];
  }

  alias('songHash', 'hash');
  alias('mediaMid', 'strMediaMid');
  alias('albumAudioId', 'albumAudioId');
  alias('albumId', 'albumId');
  alias('contentId', 'contentId');
  alias('copyrightId', 'copyrightId');
  if (t.platform == 'kg' && identity['hash'] == null && RegExp(r'^[a-fA-F\d]{32}$').hasMatch(t.songId)) identity['hash'] = t.songId;
  var qualities = [for (final q in (d['qualities'] is List ? d['qualities'] as List : const [])) '$q'];
  if (qualities.isEmpty && raw['availableQualities'] is List) qualities = [for (final q in raw['availableQualities'] as List) '$q'];
  if (qualities.isEmpty) qualities = const ['128k', '320k', 'flac'];
  return {
    ...d,
    'qualities': qualities,
    'qualityDetails': asJson(raw['qualityDetails']),
    'identity': identity,
  };
}

/// 桌面端 trackNativeId：去掉 `平台:` 前缀；酷我再去掉 MUSIC_。
String nativeIdOf(Json track) {
  final platform = '${track['platform']}';
  final id = '${track['id'] ?? ''}';
  var v = id.toLowerCase().startsWith('$platform:') ? id : '${asJson(track['identity'])['id'] ?? id}';
  while (v.toLowerCase().startsWith('$platform:')) {
    v = v.substring(platform.length + 1);
  }
  if (platform == 'kw') v = v.replaceFirst(RegExp(r'^MUSIC_', caseSensitive: false), '');
  return v.trim();
}

/// 桌面端 toLegacyTrack：洛雪脚本的 musicInfo。
Json toLegacyTrack(Json track, String? quality) {
  final platform = '${track['platform']}';
  final identity = asJson(track['identity']);
  final fallbackId = nativeIdOf(track);
  final id = '${switch (platform) {
    'tx' => identity['songId'] ?? identity['id'] ?? fallbackId,
    'kg' => identity['albumAudioId'] ?? fallbackId,
    'mg' => identity['contentId'] ?? identity['copyrightId'] ?? fallbackId,
    _ => fallbackId,
  }}';
  final qualities = [for (final q in (track['qualities'] is List ? track['qualities'] as List : const [])) '$q'];
  final details = asJson(track['qualityDetails']);
  final hashes = asJson(identity['qualityHashes']);
  Json typeOf(String q) => {'type': q, 'size': asJson(details[q])['size'], if (hashes[q] != null) 'hash': hashes[q]};
  final typed = {for (final q in qualities) q: {'size': asJson(details[q])['size'], if (hashes[q] != null) 'hash': hashes[q]}};
  final songId = identity['songId'] ?? identity['albumAudioId'] ?? id;
  final dur = track['duration'] is num ? (track['duration'] as num).toInt() : 0;
  final types = [for (final q in qualities) typeOf(q)];
  final meta = {
    'songId': id,
    'albumName': track['album'] ?? '',
    'picUrl': track['cover'],
    'qualitys': types,
    '_qualitys': typed,
    'albumId': identity['albumId'],
    'hash': identity['hash'],
    'id': identity['songId'],
    'albumMid': identity['albumMid'],
    'strMediaMid': identity['strMediaMid'],
    'contentId': identity['contentId'],
    'copyrightId': identity['copyrightId'],
    'lrcUrl': identity['lrcUrl'],
    'mrcUrl': identity['mrcUrl'],
    'trcUrl': identity['trcUrl'],
    if (platform == 'tx') ...{
      'qq': {'mid': identity['strMediaMid'] ?? id, 'songid': identity['songId'] ?? id},
      'mid': identity['strMediaMid'] ?? id,
      'songid': identity['songId'] ?? id,
    },
  };
  return {
    'id': id,
    'songmid': id,
    'songId': songId,
    'hash': identity['hash'],
    'albumId': identity['albumId'],
    'albumAudioId': identity['albumAudioId'],
    'albumMid': identity['albumMid'],
    'strMediaMid': identity['strMediaMid'],
    'contentId': identity['contentId'],
    'copyrightId': identity['copyrightId'],
    'lrcUrl': identity['lrcUrl'],
    'mrcUrl': identity['mrcUrl'],
    'trcUrl': identity['trcUrl'],
    'name': track['title'] ?? '',
    'title': track['title'] ?? '',
    'singer': track['artist'] ?? '',
    'artist': track['artist'] ?? '',
    'albumName': track['album'] ?? '',
    'album': track['album'] ?? '',
    'interval': '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}',
    'source': platform,
    'type': quality,
    'types': types,
    '_types': typed,
    'meta': meta,
  };
}
