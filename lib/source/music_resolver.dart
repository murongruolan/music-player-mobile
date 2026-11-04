// 播放链路与音源的汇合点：实现 lib/audio 的 TrackResolver。
// 歌曲 → 本机曲目信息 → 依次尝试音源脚本（音质回退）→ 原平台都失败时按设置换到其它平台的同名歌。
// 对齐桌面端 MusicService.resolve（music-service.ts）。
import '../audio/track_resolver.dart';
import '../core/network.dart';
import '../core/state.dart';
import '../data/models.dart';
import 'failure.dart';
import 'lx_track.dart';
import 'source_manager.dart';

class MusicResolver implements TrackResolver {
  /// main.dart 先建引擎再建 AppState，所以这里晚绑定。
  AppState? app;
  MusicResolver([this.app, Future<NetKind> Function()? network]) : _network = network ?? currentNetwork;

  final Future<NetKind> Function() _network;

  /// 最近一次解析的结果（界面显示实际音质 / 音源）。
  ResolvedUrl? last;

  /// 每首歌（曲目 key）被判定只给试听片段的音源 id，这次会话内不再用它们解析这首歌。
  final _trialSources = <String, Set<String>>{};

  /// 每首歌被判定只有试听片段的平台曲目（换平台时也跳过）。
  final _trialAlts = <String, Set<String>>{};

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ', ResolveReason reason = ResolveReason.play}) async {
    final a = app;
    if (a == null) return null;
    final t = a.library.trackOf(song.id);
    if (t == null) throw const ResolveException('这首歌缺少平台信息，无法解析播放地址');
    if (t.isLocal) throw const ResolveException('本地歌曲暂不支持播放');
    final track = lxTrackOf(t);
    var preferred = lxQualityOf(a.set.onlineQ);
    // 移动网络使用较低音质：高于 HQ 的档位在蜂窝网络下降到 HQ（判断不了网络类型时不降）
    if (a.set.mobileLow && qualityFallback.indexOf(preferred) < qualityFallback.indexOf('320k') && await _network() == NetKind.mobile) preferred = '320k';
    final sources = a.sources.forPlayback();
    if (sources.isEmpty) throw const ResolveException('还没有导入音源脚本');
    final manager = a.sources.manager;
    final key = t.id;
    final prev = last;
    if (reason == ResolveReason.trial && prev != null) {
      // 上一个地址只有试听：记下这个音源（换过平台的话记下那个平台曲目），下面解析时跳过
      final alt = prev.alternative;
      if (alt == null) {
        (_trialSources[key] ??= {}).add(prev.sourceId);
      } else {
        (_trialAlts[key] ??= {}).add('${alt.platform}:${alt.nativeId}');
      }
    }
    final fresh = reason != ResolveReason.play;
    if (fresh) manager.forget('${track['id']}');
    final avoid = _trialSources[key] ?? const <String>{};
    try {
      if (_trialAlts[key]?.isNotEmpty ?? false) throw const ResolveException('只拿到试听片段');
      final r = await manager.resolveUrl(track, preferred, sources, forceRefresh: fresh, probe: true, avoid: avoid);
      if (reason == ResolveReason.trial) a.notice?.call('上一个音源只有试听片段，已换到「${r.sourceName}」', 'refresh');
      return _done(a, r);
    } on ResolveException catch (first) {
      // 智能换源：原平台拿不到地址时，找其它平台的同一首歌
      if (!a.set.crossPlat) rethrow;
      final skip = _trialAlts[key] ?? const <String>{};
      final alts = [for (final x in await SourceManager.findAlternatives(a.content, track)) if (!skip.contains('${x.platform}:${x.nativeId}')) x];
      for (final alt in alts.take(6)) {
        try {
          final r = await manager.resolveUrl(lxTrackOf(alt.toCloud()), preferred, sources, forceRefresh: fresh, probe: true);
          final why = classifyFailure(first.message) == FailKind.trial ? '只有试听片段' : '解析失败';
          a.notice?.call('${_name(t.platform)}$why，已换到${_name(alt.platform)}播放', 'refresh');
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
