// 平台内容的统一模型（对齐桌面端 platform-service.ts 的 makeTrack / makeCatalogItem / collection 返回）。
// 五个平台的原始 JSON 都在各自的 adapter 里转换成这些模型，页面只认这里。
import '../net/json.dart';
import '../sync/cloud_models.dart';

/// 平台代码：wy 网易云 · tx QQ · kg 酷狗 · kw 酷我 · mg 咪咕。
abstract final class Plat {
  static const wy = 'wy', tx = 'tx', kg = 'kg', kw = 'kw', mg = 'mg';
  static const all = [wy, tx, kg, kw, mg];

  /// App 内平台 id（netease / qq / …）→ 平台代码。
  static const fromAppId = {'netease': wy, 'qq': tx, 'kugou': kg, 'kuwo': kw, 'migu': mg};
  static const toAppId = {wy: 'netease', tx: 'qq', kg: 'kugou', kw: 'kuwo', mg: 'migu'};
  static const names = {wy: '网易云音乐', tx: 'QQ音乐', kg: '酷狗音乐', kw: '酷我音乐', mg: '咪咕音乐'};
}

/// 音质档位，从低到高。
const qualityOrder = ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'atmos_plus', 'master'];
const qualityDefaults = ['128k', '320k', 'flac', 'flac24bit'];

/// 一首歌。[identity] 是播放解析需要的各平台原生字段（见文档 1.3）。
class PTrack {
  final String platform, nativeId, title, artist, album;
  final int duration; // 秒
  final String? cover;
  final List<String> qualities;
  final Json identity;

  /// 每档音质的大小 / 码率（可选），如 {'flac': {'size': 30219344, 'bitrate': 900000}}
  final Json qualityDetails;
  final String? mvId;

  const PTrack({required this.platform, required this.nativeId, required this.title, required this.artist, this.album = '', this.duration = 0, this.cover, this.qualities = qualityDefaults, this.identity = const {}, this.qualityDetails = const {}, this.mvId});

  String get id => '$platform:$nativeId';

  /// 界面上显示的最高音质标签。
  String get qualityLabel {
    if (qualities.contains('master') || qualities.contains('hires') || qualities.contains('flac24bit')) return 'Hi-Res';
    if (qualities.contains('atmos') || qualities.contains('atmos_plus')) return 'Atmos';
    if (qualities.contains('flac')) return 'SQ';
    return 'HQ';
  }

  /// 转成云同步 / 本机音乐库用的格式（桌面端 Track）。
  CloudTrack toCloud() => CloudTrack(
        id: id,
        platform: platform,
        songId: nativeId,
        title: title,
        artist: artist,
        album: album,
        durationSec: duration,
        cover: cover,
        raw: {'id': id, 'platform': platform, 'title': title, 'artist': artist, 'album': album, 'duration': duration, if (cover != null) 'cover': cover, 'qualities': qualities, if (qualityDetails.isNotEmpty) 'qualityDetails': qualityDetails, 'identity': {'id': nativeId, ...identity}},
      );

  @override
  String toString() => 'PTrack($id, $title - $artist, ${duration}s)';
}

enum CatalogType { playlist, leaderboard, album, artist }

/// 歌单 / 榜单 / 专辑 / 歌手卡片。
class CatalogItem {
  final String platform, id, title, subtitle;
  final CatalogType type;
  final String? cover, creator, date;

  /// 播放量；有的平台给的是文案（「1.2万」），原样保留成字符串。
  final Object? playCount;
  final int? trackCount;
  const CatalogItem({required this.platform, required this.id, required this.title, this.subtitle = '', required this.type, this.cover, this.creator, this.date, this.playCount, this.trackCount});

  String get playCountText {
    final p = playCount;
    if (p == null) return '';
    if (p is num) return p >= 100000000 ? '${(p / 100000000).toStringAsFixed(1)}亿' : p >= 10000 ? '${(p / 10000).toStringAsFixed(1)}万' : '$p';
    return '$p';
  }

  @override
  String toString() => 'CatalogItem($platform/${type.name}/$id $title)';
}

/// 分页结果。
class Page<T> {
  final List<T> items;
  final int page, limit, total;
  final bool hasMore;
  const Page(this.items, {this.page = 1, this.limit = 30, this.total = 0, bool? hasMore}) : hasMore = hasMore ?? (page * limit < total);
  static Page<T> empty<T>() => Page<T>(const [], total: 0, hasMore: false);
}

/// 歌单 / 榜单 / 专辑 / 歌手详情。
class Collection {
  final String platform, id, title, description;
  final CatalogType type;
  final String? cover, creator;
  final List<PTrack> tracks;
  final int total, page, limit;
  final bool hasMore;
  const Collection({required this.platform, required this.id, required this.type, required this.title, this.description = '', this.cover, this.creator, this.tracks = const [], this.total = 0, this.page = 1, this.limit = 100, this.hasMore = false});
}

enum SearchType { song, playlist, artist, album, mv }

/// 搜索结果：按类型只填对应的列表。
class SearchResult {
  final List<PTrack> songs;
  final List<CatalogItem> items; // playlist / artist / album
  final int total;
  final bool hasMore;
  const SearchResult({this.songs = const [], this.items = const [], this.total = 0, this.hasMore = false});
}

/// 歌单分类（歌单广场筛选）。id 原样传回 [MusicPlatform.playlists]。
class PlaylistCategory {
  final String id, name, group;
  const PlaylistCategory(this.id, this.name, {this.group = ''});
}

/// 歌词。[lrc] 是标准 LRC；[translation] 翻译；[words] 逐字（可选）。
class Lyric {
  final String lrc;
  final String? translation, romanization;
  final List<LyricLineWords>? words;
  const Lyric(this.lrc, {this.translation, this.romanization, this.words});
  bool get isEmpty => lrc.trim().isEmpty;
}

class LyricLineWords {
  final int start, duration; // 毫秒
  final String text;
  final List<({int start, int duration, String text})> words;
  const LyricLineWords(this.start, this.duration, this.text, this.words);
}

/// 平台请求失败。[message] 可以直接展示。
class PlatformException implements Exception {
  final String platform, message;
  final Object? cause;
  const PlatformException(this.platform, this.message, [this.cause]);
  @override
  String toString() => 'PlatformException($platform): $message${cause == null ? '' : ' ($cause)'}';
}
