// 播放链路与音源的汇合点：实现 lib/audio 的 TrackResolver。
// 歌曲 → 本机曲目信息 → 依次尝试音源脚本（音质回退）→ 原平台都失败时按设置换到其它平台的同名歌。
// 对齐桌面端 MusicService.resolve（music-service.ts）。
import '../audio/track_resolver.dart';
import '../core/state.dart';
import '../data/models.dart';
import 'lx_track.dart';
import 'source_manager.dart';

/// 一条取流记录（播放链路页展示）。[ok] = 是否拿到可播地址。
class ResolveTrace {
  final DateTime time;
  final String title, platform, source, quality, note;
  final bool ok;
  const ResolveTrace({
    required this.time,
    required this.title,
    required this.platform,
    required this.source,
    required this.quality,
    required this.ok,
    this.note = '',
  });
}

class MusicResolver implements TrackResolver {
  /// main.dart 先建引擎再建 AppState，所以这里晚绑定。
  AppState? app;
  MusicResolver([this.app]);

  /// 最近一次解析的结果（界面显示实际音质 / 音源）。
  ResolvedUrl? last;

  /// 取流记录（播放链路页）：最新在前，最多 8 条，成功与失败都记。
  final List<ResolveTrace> history = [];

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ'}) async {
    final a = app;
    if (a == null) return null;
    final t = a.library.trackOf(song.id);
    if (t == null) return _fail(a, song, '缺少平台信息，无法解析播放地址', '未知');
    if (t.isLocal) return _fail(a, song, '本地歌曲暂不支持在线解析', '本地');
    // 已下载的歌离线优先：本地文件存在就直接播，不走音源（断网可用）
    final downloaded = a.downloads.pathOf(t.id);
    if (downloaded != null) {
      last = ResolvedUrl(downloaded, 'local', 'download', '本地文件', 'local', fromCache: true);
      _history(song, '本地', '已下载', '原档位', true, '离线优先：直接播放本地文件');
      return Uri.file(downloaded);
    }
    final track = lxTrackOf(t);
    final preferred = lxQualityOf(a.set.onlineQ);
    final sources = a.sources.forPlayback();
    if (sources.isEmpty) return _fail(a, song, '还没有导入音源脚本', _name(t.platform), source: '未导入');
    final manager = a.sources.manager;
    final firstSource = sources.first.name;
    try {
      return _done(a, song, t.platform, await manager.resolveUrl(track, preferred, sources));
    } on ResolveException catch (first) {
      // 智能换源：原平台拿不到地址时，找其它平台的同一首歌
      if (!a.set.crossPlat) return _fail(a, song, first.message, _name(t.platform), source: firstSource);
      final alts = await SourceManager.findAlternatives(a.content, track);
      for (final alt in alts.take(6)) {
        try {
          final r = await manager.resolveUrl(lxTrackOf(alt.toCloud()), preferred, sources);
          a.notice?.call('${_name(t.platform)}解析失败，已换到${_name(alt.platform)}播放', 'refresh');
          return _done(a, song, alt.platform, ResolvedUrl(r.url, r.quality, r.sourceId, r.sourceName, r.platform, alternative: alt),
              note: '原平台失败，已换平台');
        } on ResolveException {
          continue;
        }
      }
      return _fail(a, song, '${first.message}${alts.isEmpty ? '' : '（其它平台的同名歌也没有解析出来）'}', _name(t.platform),
          source: firstSource);
    }
  }

  Uri _done(AppState a, Song song, String platform, ResolvedUrl r, {String note = ''}) {
    last = r;
    _history(song, _name(r.platform), r.sourceName, appQualityOf(r.quality), true,
        note.isEmpty && r.fromCache ? '取流地址缓存命中' : note);
    final q = appQualityOf(r.quality);
    if (a.quality != q) a.update(() => a.quality = q);
    return Uri.parse(r.url);
  }

  Uri? _fail(AppState a, Song song, String message, String platform, {String source = '音源解析'}) {
    _history(song, platform, source, a.set.onlineQ, false, message);
    throw ResolveException(message);
  }

  void _history(Song song, String platform, String source, String quality, bool ok, String note) {
    history.insert(
        0,
        ResolveTrace(
          time: DateTime.now(),
          title: song.title,
          platform: platform,
          source: source,
          quality: quality,
          ok: ok,
          note: note,
        ));
    if (history.length > 8) history.removeRange(8, history.length);
  }

  static String _name(String code) => const {'wy': '网易云', 'tx': 'QQ音乐', 'kg': '酷狗', 'kw': '酷我', 'mg': '咪咕'}[code] ?? code;
}
