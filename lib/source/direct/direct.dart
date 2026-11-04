// 直链编排：按平台分发取地址，统一管理 15 分钟缓存、试听黑名单与凭证失效。
//
// 使用方（music_resolver）约定：
// - reason == play：可以用缓存；
// - reason == reload：不用缓存重新取；
// - reason == trial：这首歌本次会话不再用直链（上一条直链被判为试听片段）；
// - 返回 null = 直链拿不到，回退音源脚本；
// - 凭证失效在内部 markExpired（登录层会提示重新登录），随后回退音源脚本。

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../audio/track_resolver.dart' show ResolveReason;
import '../../net/json.dart';
import '../../platform/credentials.dart';
import '../../platform/http.dart';
import '../../platform/models.dart';
import 'direct_sources.dart';
import 'direct_url.dart';
import '../source_manager.dart' show SourceManager;

class DirectLinkResolver {
  DirectLinkResolver(this.creds, {http.Client? client, PlatformHttp? http})
      : _http = http ?? PlatformHttp(client: client, maxConcurrent: 4) {
    _sub = creds.changes.listen(clearPlatform);
  }

  final CredentialStore creds;
  final PlatformHttp _http;
  StreamSubscription<String>? _sub;

  /// 直链地址缓存：`平台:歌曲id:音质` → (结果, 取得时间)。TTL 与音源脚本一致（15 分钟）。
  final _cache = <String, (DirectUrl, DateTime)>{};

  /// 被判定只有试听片段的歌曲（本会话不再用直链）。
  final _noDirect = <String>{};

  /// 与音源脚本一致的地址有效期。
  Duration get ttl => SourceManager.urlTtl;

  void init() {} // 占位：构造时已订阅 creds.changes

  /// 清掉某平台（平台代码）的全部直链缓存——凭证变化时调用。
  void clearPlatform(String code) {
    _cache.removeWhere((k, _) => k.startsWith('$code:'));
  }

  void clearAll() => _cache.clear();

  /// 试听黑名单（本会话不再对该曲目用直链）。
  void blacklist(Json track) => _noDirect.add(directTrackKey(track));

  /// 取直链。返回 null = 直链不可用（调用方回退音源脚本）。
  Future<DirectUrl?> resolve(Json track, String quality, {ResolveReason reason = ResolveReason.play}) async {
    final platform = '${track['platform']}';
    if (platform == 'local' || platform.isEmpty) return null;
    final songKey = directTrackKey(track);
    if (_noDirect.contains(songKey)) return null; // 上次直链只有试听：本次不再试
    if (reason == ResolveReason.trial) {
      _noDirect.add(songKey); // 试听场景：本曲本次不再用直链（本次解析直接跳过）
      return null;
    }
    final cacheKey = directCacheKey(track, quality);
    final fresh = reason != ResolveReason.play;
    if (!fresh) {
      final hit = _cache[cacheKey];
      if (hit != null && DateTime.now().difference(hit.$2) < ttl) return hit.$1;
    } else {
      _cache.remove(cacheKey);
    }

    final cred = creds.of(platform);
    DirectUrl? d;
    try {
      d = switch (platform) {
        'wy' => await wyDirect(_http, track, quality, cred: cred, anonCookie: creds.anonymousCookie(platform)),
        'tx' => await txDirect(_http, track, quality, cred: cred),
        'kg' => await kgDirect(_http, track, quality, cred: cred),
        'kw' => await kwDirect(_http, track, quality),
        'mg' => await mgDirect(_http, track, quality),
        _ => null,
      };
    } on DirectAuthException catch (e) {
      // 登录失效：标记（登录层提示重新登录），清该平台缓存，回退音源脚本
      if (cred != null) unawaited(creds.markExpired(platform, e.message));
      clearPlatform(platform);
      return null;
    } on Exception {
      return null; // 网络 / 解析问题：回退音源脚本
    }
    if (d != null) _cache[cacheKey] = (d, DateTime.now());
    return d;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _cache.clear();
  }
}
