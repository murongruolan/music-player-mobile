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
  MusicResolver([this.app, Future<NetKind> Function()? network]) : _network = network ?? currentNetwork;

  final Future<NetKind> Function() _network;

  /// 最近一次解析的结果（界面显示实际音质 / 音源）。
  ResolvedUrl? last;

  /// 取流记录（播放链路页）：最新在前，最多 8 条，成功与失败都记。
  final List<ResolveTrace> history = [];

  /// 每首歌（曲目 key）被判定只给试听片段的音源 id，这次会话内不再用它们解析这首歌。
  final _trialSources = <String, Set<String>>{};

  /// 每首歌被判定只有试听片段的平台曲目（换平台时也跳过）。
  final _trialAlts = <String, Set<String>>{};

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ', ResolveReason reason = ResolveReason.play}) async {
    final a = app;
    if (a == null) return null;
    final t = a.library.trackOf(song.id);
    if (t == null) return _fail(a, song, '缺少平台信息，无法解析播放地址', '未知');
    if (t.isLocal) return _fail(a, song, '本地歌曲暂不支持在线解析', '本地');
    // 已下载的歌离线优先：本地文件存在就直接播，不走音源（断网可用）
    final downloaded = a.downloads.pathOf(t.id);
    if (downloaded != null && reason != ResolveReason.trial) { // 本地文件被判为试听片段时改走在线
      last = ResolvedUrl(downloaded, 'local', 'download', '本地文件', 'local', fromCache: true);
      _history(song, '本地', '已下载', '原档位', true, '离线优先：直接播放本地文件');
      return Uri.file(downloaded);
    }
    final track = lxTrackOf(t);
    var preferred = lxQualityOf(a.set.onlineQ);
    // 移动网络使用较低音质：高于 HQ 的档位在蜂窝网络下降到 HQ（判断不了网络类型时不降）
    if (a.set.mobileLow && qualityFallback.indexOf(preferred) < qualityFallback.indexOf('320k') && await _network() == NetKind.mobile) preferred = '320k';
    final sources = a.sources.forPlayback();
    if (sources.isEmpty) return _fail(a, song, '还没有导入音源脚本', _name(t.platform), source: '未导入');
    final manager = a.sources.manager;
    final firstSource = sources.first.name;
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
    final why = switch (reason) { ResolveReason.reload => '链接失效，重新取链', ResolveReason.trial => '上一个地址是试听片段，换音源', _ => '' };
    try {
      if (_trialAlts[key]?.isNotEmpty ?? false) throw const ResolveException('只拿到试听片段');
      final r = await manager.resolveUrl(track, preferred, sources, forceRefresh: fresh, probe: true, avoid: avoid);
      if (reason == ResolveReason.trial) a.notice?.call('上一个音源只有试听片段，已换到「${r.sourceName}」', 'refresh');
      return _done(a, song, t.platform, r, note: why);
    } on ResolveException catch (first) {
      // 智能换源：原平台拿不到地址时，找其它平台的同一首歌
      if (!a.set.crossPlat) return _fail(a, song, first.message, _name(t.platform), source: firstSource);
      final skip = _trialAlts[key] ?? const <String>{};
      final alts = [for (final x in await SourceManager.findAlternatives(a.content, track)) if (!skip.contains('${x.platform}:${x.nativeId}')) x];
      for (final alt in alts.take(6)) {
        try {
          final r = await manager.resolveUrl(lxTrackOf(alt.toCloud()), preferred, sources, forceRefresh: fresh, probe: true);
          final trial = classifyFailure(first.message) == FailKind.trial;
          a.notice?.call('${_name(t.platform)}${trial ? '只有试听片段' : '解析失败'}，已换到${_name(alt.platform)}播放', 'refresh');
          return _done(a, song, alt.platform, ResolvedUrl(r.url, r.quality, r.sourceId, r.sourceName, r.platform, alternative: alt),
              note: trial ? '原平台只有试听片段，已换平台' : '原平台失败，已换平台');
        } on ResolveException {
          continue;
        }
      }
      return _fail(a, song, '${first.message}${alts.isEmpty ? '' : '（其它平台的同名歌也没有解析出来）'}', _name(t.platform), source: firstSource);
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
