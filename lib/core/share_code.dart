// 分享口令：纯前端，不经过服务端。口令里直接带平台 + 平台 id，好友复制后打开 Lyra 就能识别。
//   歌曲：[Lyra]V1·wy·186016·晴天-周杰伦
//   歌单：[Lyra]V1·歌单·wy·7741029·夜跑歌单
// 歌名 / 歌手只用于展示和兜底搜索；真正定位歌曲靠平台 + id。
import '../platform/models.dart';
import '../platform/registry.dart';

sealed class ShareCode {
  const ShareCode(this.platform, this.id);
  final String platform, id;
}

class SongShareCode extends ShareCode {
  const SongShareCode(super.platform, super.id, this.title, this.artist);
  final String title, artist;
}

class PlaylistShareCode extends ShareCode {
  const PlaylistShareCode(super.platform, super.id, this.name);
  final String name;
}

const _ver = 'V1';
const _sep = '·';

/// 口令字段里不能出现分隔符和换行。
String _clean(String s) => s.replaceAll(_sep, '・').replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

String songShareCode({required String platform, required String id, required String title, required String artist}) =>
    '[Lyra]$_ver$_sep$platform$_sep${_clean(id)}$_sep${_clean(title)}${artist.trim().isEmpty ? '' : '-${_clean(artist)}'}';

String playlistShareCode({required String platform, required String id, required String name}) =>
    '[Lyra]$_ver$_sep歌单$_sep$platform$_sep${_clean(id)}$_sep${_clean(name)}';

final _re = RegExp(r'\[Lyra\]V(\d+)·(?:(歌单)·)?(wy|tx|kg|kw|mg)·([^·\s]+)·([^\r\n]*)');

/// 从任意文本里找口令（好友可能连着别的话一起发）。不认识的版本号返回 null。
ShareCode? parseShareCode(String text) {
  final m = _re.firstMatch(text);
  if (m == null || m[1] != '1') return null;
  final platform = m[3]!, id = m[4]!, rest = m[5]!.trim();
  if (m[2] != null) return PlaylistShareCode(platform, id, rest);
  // 歌名-歌手：歌名本身可能带「-」，按最后一个「-」分（只影响展示 / 兜底搜索）
  final i = rest.lastIndexOf('-');
  return i <= 0 ? SongShareCode(platform, id, rest, '') : SongShareCode(platform, id, rest.substring(0, i).trim(), rest.substring(i + 1).trim());
}

/// 口令的身份（同一首歌 / 歌单的口令文字可能不同，按平台 + id 认）。
String shareSig(ShareCode c) => '${c is PlaylistShareCode ? 'pl' : 'song'}|${c.platform}|${c.id}';

/// 口令 → 可播放的平台曲目。先按歌名歌手在该平台搜索，取 id 相同的那首（带齐音源需要的 identity：
/// 酷狗 albumAudioId、QQ songId、咪咕 contentId 等）；搜不到就用口令里的 id 组一首，交给解析器碰运气。
Future<PTrack> resolveSongCode(PlatformHub hub, SongShareCode c) async {
  final bare = PTrack(platform: c.platform, nativeId: c.id, title: c.title.isEmpty ? '好友分享的歌' : c.title, artist: c.artist, identity: {'id': c.id});
  if (!hub.supports(c.platform)) return bare;
  try {
    final r = await hub.search(c.platform, '${c.title} ${c.artist}'.trim(), SearchType.song, fallback: false);
    final same = r.result.songs.where((t) => t.nativeId.toLowerCase() == c.id.toLowerCase()).firstOrNull;
    return same ?? bare;
  } catch (_) {
    return bare;
  }
}
