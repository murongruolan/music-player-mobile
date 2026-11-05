// 音源调度：脚本运行实例的启动 / 复用、能力缓存、播放地址解析（音质回退、换源、链接缓存）、换平台找同名歌。
// 对齐桌面端 SourceManager（source-manager.ts）与 MusicService.resolve / resolveTrack（music-service.ts）。
import 'dart:async';
import 'package:http/http.dart' as http;
import '../net/json.dart';
import '../platform/models.dart';
import '../platform/registry.dart';
import '../sync/cloud_models.dart';
import 'failure.dart';
import 'lx_runtime.dart';
import 'lx_track.dart';

typedef RuntimeStarter = Future<LxRuntime> Function(CloudSource source);

class ResolveException implements Exception {
  final String message;
  const ResolveException(this.message);
  @override
  String toString() => message;
}

/// 播放地址探测发现的问题。
enum UrlIssue { trial, forbidden, notFound }

/// 一次成功的解析。
class ResolvedUrl {
  final String url, quality, sourceId, sourceName, platform;
  final bool fromCache;

  /// 原平台解析失败、换到其它平台同名歌时：实际播放的平台曲目。
  final PTrack? alternative;
  const ResolvedUrl(this.url, this.quality, this.sourceId, this.sourceName, this.platform, {this.fromCache = false, this.alternative});
}

class SourceManager {
  final http.Client _client;
  late final RuntimeStarter _starter;
  final _runtimes = <String, Future<LxRuntime>>{};
  final _scriptOf = <String, String>{};

  /// 每个脚本的能力（平台 → 动作 / 音质），初始化成功后才有。
  final capabilities = <String, Map<String, LxCapability>>{};

  /// 初始化失败的原因。
  final initErrors = <String, String>{};

  /// 播放地址缓存：`音源:曲目:音质` → (地址, 时间)。各平台直链的有效期普遍在 15 分钟以上，按 15 分钟算。
  final _urlCache = <String, (String, DateTime)>{};
  static const urlTtl = Duration(minutes: 15);

  /// 试听判定：文件大小低于「时长 × 128kbps」的这个比例，就认为是试听片段（酷我常见 11 秒试听）。
  static const trialRatio = .75;

  /// 能力 / 初始化状态变化（界面刷新用）。
  void Function()? onChanged;

  SourceManager({http.Client? client, RuntimeStarter? starter}) : _client = client ?? http.Client() {
    _starter = starter ?? (s) => LxRuntime.start(s.rawScript, info: LxScriptInfo(name: s.name, description: s.description, version: s.version, author: s.author, homepage: s.homepage), client: _client);
  }

  /// 拿到（必要时启动）脚本的运行实例。脚本内容变了会重启。
  Future<LxRuntime> runtime(CloudSource s) {
    if (_scriptOf[s.id] != s.rawScript) stop(s.id);
    final hit = _runtimes[s.id];
    if (hit != null) return hit;
    _scriptOf[s.id] = s.rawScript;
    final f = _starter(s).then((rt) {
      capabilities[s.id] = rt.capabilities;
      initErrors.remove(s.id);
      onChanged?.call();
      return rt;
    }, onError: (Object e) {
      _runtimes.remove(s.id);
      _scriptOf.remove(s.id);
      initErrors[s.id] = '$e';
      onChanged?.call();
      throw e is LxException ? e : LxException('$e');
    });
    _runtimes[s.id] = f;
    return f;
  }

  /// 校验一个还没导入的脚本：启动、读能力、关掉。
  Future<Map<String, LxCapability>> probe(CloudSource s) async {
    final rt = await _starter(s);
    try {
      return rt.capabilities;
    } finally {
      rt.dispose();
    }
  }

  void stop(String id) {
    final f = _runtimes.remove(id);
    _scriptOf.remove(id);
    _urlCache.removeWhere((k, _) => k.startsWith('$id:'));
    f?.then((rt) => rt.dispose(), onError: (_) {});
  }

  void dispose() {
    for (final id in [..._runtimes.keys]) {
      stop(id);
    }
  }

  /// 按优先顺序尝试音源，解析 [track]（桌面端 Track 结构）的播放地址。
  /// [sources] 已按优先级排好（当前选中的在前）。全部失败抛 [ResolveException]（带最后一个错误）。
  ///
  /// [probe]：拿到地址后先发一个 `Range: bytes=0-1` 请求看文件多大、能不能访问：
  /// 试听片段 / 404 换下一个音源，403 重新取一次地址仍不行再换。探测本身失败（超时、不支持 Range）不拦截。
  /// [avoid]：这次跳过的音源 id（上一个地址被判定为试听片段时）。
  /// [allowLower]：音质可以往下降；[firstOnly]：只用第一个音源（关掉「换用同平台其他脚本」）。
  Future<ResolvedUrl> resolveUrl(Json track, String preferred, List<CloudSource> sources, {bool forceRefresh = false, bool probe = false, Set<String> avoid = const {}, bool allowLower = true, bool firstOnly = false}) async {
    final platform = '${track['platform']}';
    if (platform == 'local' || platform.isEmpty) throw const ResolveException('本地歌曲不需要在线解析');
    if (sources.isEmpty) throw const ResolveException('还没有导入音源脚本');
    final errors = <String>[];
    final trackQualities = [for (final q in (track['qualities'] as List? ?? const [])) '$q'];
    final duration = track['duration'] is num ? (track['duration'] as num).toInt() : 0;
    for (final s in firstOnly ? sources.take(1) : sources) {
      if (avoid.contains(s.id)) {
        errors.add('${s.name}：只拿到试听片段');
        continue;
      }
      LxRuntime rt;
      try {
        rt = await runtime(s);
      } catch (e) {
        errors.add('${s.name} 初始化失败：$e');
        continue;
      }
      final cap = rt.capabilities[platform];
      if (cap == null || !cap.actions.contains('musicUrl')) {
        errors.add('${s.name} 不支持${Plat.names[platform] ?? platform}');
        continue;
      }
      final q = pickQuality(preferred, trackQualities, cap.qualities, allowLower: allowLower);
      if (q == null) {
        errors.add('${s.name} 不支持这首歌可用的音质');
        continue;
      }
      final key = '${s.id}:${track['id']}:$q';
      final hit = _urlCache[key];
      if (!forceRefresh && hit != null && DateTime.now().difference(hit.$2) < urlTtl) return ResolvedUrl(hit.$1, q, s.id, s.name, platform, fromCache: true);
      try {
        Future<String> fetch() async => await rt.request('musicUrl', platform, toLegacyTrack(track, q), quality: q) as String;
        var url = await fetch();
        if (probe) {
          var issue = await checkUrl(url, duration);
          if (issue == UrlIssue.forbidden) {
            // 403：多半是签名 / 时效问题，重新取一次
            url = await fetch();
            issue = await checkUrl(url, duration);
          }
          if (issue != null) {
            errors.add('${s.name}：${const {UrlIssue.trial: '只拿到试听片段', UrlIssue.forbidden: '播放地址被拒绝（403）', UrlIssue.notFound: '播放地址不存在（404）'}[issue]}');
            continue;
          }
        }
        _urlCache[key] = (url, DateTime.now());
        return ResolvedUrl(url, q, s.id, s.name, platform);
      } catch (e) {
        errors.add('${s.name}：$e');
      }
    }
    throw ResolveException(errors.isEmpty ? '当前音源不支持这首歌曲或所选平台' : summarizeFailures(errors));
  }

  /// 探测播放地址：只取前 2 个字节，从 Content-Range / Content-Length 读出文件大小。
  /// 返回 null 表示没发现问题（包括探测失败、服务器不给大小的情况）。
  Future<UrlIssue?> checkUrl(String url, int durationSec) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    http.StreamedResponse res;
    try {
      final req = http.Request('GET', uri)
        ..followRedirects = true
        ..headers['Range'] = 'bytes=0-1'
        ..headers['User-Agent'] = _probeUa;
      res = await _client.send(req).timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
    // 不读正文：服务器忽略 Range 返回整个文件时，取消订阅即断开
    unawaited(res.stream.listen(null, onError: (_) {}, cancelOnError: true).cancel());
    if (res.statusCode == 401 || res.statusCode == 403) return UrlIssue.forbidden;
    if (res.statusCode == 404 || res.statusCode == 410) return UrlIssue.notFound;
    if (res.statusCode >= 300) return null;
    int? total;
    final range = res.headers['content-range'];
    if (range != null) total = int.tryParse(range.split('/').last.trim());
    if (total == null && res.statusCode == 200) total = int.tryParse(res.headers['content-length'] ?? '');
    if (total == null || total <= 0 || durationSec < 30) return null;
    // 按 32kbps 估：试听片段只有全长的百分之几，低码率（64 / 96kbps）的完整歌不会被误判
    return total < durationSec * 4000 * trialRatio ? UrlIssue.trial : null;
  }

  static const _probeUa = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

  /// 去掉某首歌的缓存链接（播放器报错、链接过期时）。
  void forget(String trackId) => _urlCache.removeWhere((k, _) => k.contains(':$trackId:'));

  /// 其它平台的同名歌（桌面端 findAlternatives + rankAlternativeTracks）。
  static Future<List<PTrack>> findAlternatives(PlatformHub hub, Json track) async {
    final platform = '${track['platform']}';
    final title = '${track['title'] ?? ''}'.trim(), artist = '${track['artist'] ?? ''}'.trim();
    if (title.isEmpty) return const [];
    final codes = [for (final c in const ['kw', 'kg', 'tx', 'wy', 'mg']) if (c != platform && hub.supports(c)) c];
    final results = await Future.wait([
      for (final c in codes) hub.search(c, '$title $artist'.trim(), SearchType.song, limit: 25, fallback: false).then<List<PTrack>>((o) => o.result.songs, onError: (_) => const <PTrack>[]),
    ]);
    final target = (title: title, artist: artist, album: '${track['album'] ?? ''}', duration: track['duration'] is num ? (track['duration'] as num).toInt() : 0);
    final same = [for (final l in results) ...l.where((t) => isSameTrack(target, (title: t.title, artist: t.artist, album: t.album, duration: t.duration)))];
    int score(PTrack t) {
      final dur = target.duration > 0 && t.duration > 0 && (target.duration - t.duration).abs() < 1 ? 8 : 0;
      return (normalizeName(t.title) == normalizeName(target.title) ? 32 : 0) +
          (normalizeSinger(t.artist) == normalizeSinger(target.artist) ? 16 : 0) +
          (normalizeName(target.album).isNotEmpty && normalizeName(t.album) == normalizeName(target.album) ? 4 : 0) +
          dur;
    }

    same.sort((a, b) => score(b) - score(a));
    return same;
  }
}

typedef TrackLike = ({String title, String artist, String album, int duration});

String normalizeName(String v) => v.toLowerCase().replaceAll(RegExp(r'''[\s·・()（）\[\]【】'"“”‘’,，&、\-<>|/\\!！]'''), '');

String normalizeSinger(String v) {
  final l = v.split(RegExp(r'、|&|;|；|/|,|，|\|')).map(normalizeName).where((x) => x.isNotEmpty).toList()..sort();
  return l.join('、');
}

/// 桌面端 isSameTrack。
bool isSameTrack(TrackLike a, TrackLike b) {
  final tn = normalizeName(a.title), cn = normalizeName(b.title);
  final ts = normalizeSinger(a.artist), cs = normalizeSinger(b.artist);
  final ta = normalizeName(a.album), ca = normalizeName(b.album);
  if (a.duration > 0 && b.duration > 0 && (a.duration - b.duration).abs() >= 5) return false;
  final includesName = tn.contains(cn) || cn.contains(tn);
  final includesSinger = ts.isEmpty || ts.contains(cs) || cs.contains(ts);
  return (tn == cn && includesSinger) || (ts == cs && includesName) || (ta.isNotEmpty && ta == ca && includesSinger && includesName);
}
