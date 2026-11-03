// 播放链路与音源的汇合点：实现 lib/audio 的 TrackResolver。
// 歌曲 → 本机曲目信息 → 依次尝试音源脚本（音质回退）→ 原平台都失败时按设置换到其它平台的同名歌。
// 对齐桌面端 MusicService.resolve（music-service.ts）。
import '../audio/track_resolver.dart';
import '../core/state.dart';
import '../data/models.dart';
import 'lx_track.dart';
import 'source_manager.dart';

class MusicResolver implements TrackResolver {
  /// main.dart 先建引擎再建 AppState，所以这里晚绑定。
  AppState? app;
  MusicResolver([this.app]);

  /// 最近一次解析的结果（界面显示实际音质 / 音源）。
  ResolvedUrl? last;

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ'}) async {
    final a = app;
    if (a == null) return null;
    final t = a.library.trackOf(song.id);
    if (t == null) throw const ResolveException('这首歌缺少平台信息，无法解析播放地址');
    if (t.isLocal) throw const ResolveException('本地歌曲暂不支持播放');
    final track = lxTrackOf(t);
    final preferred = lxQualityOf(a.set.onlineQ);
    final sources = a.sources.forPlayback();
    if (sources.isEmpty) throw const ResolveException('还没有导入音源脚本');
    final manager = a.sources.manager;
    try {
      return _done(a, await manager.resolveUrl(track, preferred, sources));
    } on ResolveException catch (first) {
      // 智能换源：原平台拿不到地址时，找其它平台的同一首歌
      if (!a.set.crossPlat) rethrow;
      final alts = await SourceManager.findAlternatives(a.content, track);
      for (final alt in alts.take(6)) {
        try {
          final r = await manager.resolveUrl(lxTrackOf(alt.toCloud()), preferred, sources);
          a.notice?.call('${_name(t.platform)}解析失败，已换到${_name(alt.platform)}播放', 'refresh');
          return _done(a, ResolvedUrl(r.url, r.quality, r.sourceId, r.sourceName, r.platform, alternative: alt));
        } on ResolveException {
          continue;
        }
      }
      throw ResolveException('${first.message}${alts.isEmpty ? '' : '（其它平台的同名歌也没有解析出来）'}');
    }
  }

  Uri _done(AppState a, ResolvedUrl r) {
    last = r;
    final q = appQualityOf(r.quality);
    if (a.quality != q) a.update(() => a.quality = q);
    return Uri.parse(r.url);
  }

  static String _name(String code) => const {'wy': '网易云', 'tx': 'QQ音乐', 'kg': '酷狗', 'kw': '酷我', 'mg': '咪咕'}[code] ?? code;
}
