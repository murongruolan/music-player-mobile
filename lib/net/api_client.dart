// 统一请求入口：所有接口都从这里走。
//
//   final settings = await client.get('/auth/registration-settings', auth: false, decode: RegSettings.fromData);
//   await client.post('/codes/activate', body: {'code': code});
//
// 它负责：
// - 拼地址、带公共头、带 Bearer 令牌；解析后端信封 {code, message, requestId, data}，code ≠ 0 抛 [ApiException]。
// - 令牌：快过期（60 秒内）先刷新；收到 40101 刷新一次再重试。刷新是「单飞」的——同一时刻只有一个刷新请求，
//   其他请求等它的结果（后端刷新令牌会轮换，并发刷新会被当成重放，吊销全部会话）。
//   刷新令牌失效（40102）→ 清掉会话并通过 [Session.onEnd] 通知上层回到登录页。
//   只看业务码 40101，不看 HTTP 401：密码错误也是 HTTP 401，但业务码是 40001。
// - 限流：请求先过 [RateLimiter]；收到 42901 / 429 进入冷却。
// - GET：相同请求在途时合并成一个；可选内存缓存（cacheTtl）和断网时回退旧数据（staleOnError）；
//   网络错误 / 超时 / 5xx / 限流时自动重试（最多 2 次，指数退避 + 抖动）。
//   POST / PUT / DELETE 默认不重试（可能不幂等），需要的话显式传 retry: true。
// - 取消：传 [CancelToken]，取消后调用方立刻收到 cancelled 错误（底层请求不会中断，结果丢弃）。
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_error.dart';
import 'device.dart';
import 'json.dart';
import 'rate_limiter.dart';
import 'session.dart';

/// 把信封里的 data 转成模型。抛出的任何异常都会变成 parse 错误。
typedef Decoder<T> = T Function(Object? data);

class CancelToken {
  final _c = Completer<void>();
  bool get isCancelled => _c.isCompleted;
  Future<void> get whenCancelled => _c.future;
  void cancel() {
    if (!_c.isCompleted) _c.complete();
  }
}

class _CacheEntry {
  final Object? data;
  final DateTime at;
  const _CacheEntry(this.data, this.at);
}

class ApiClient {
  final ApiConfig config;
  final Session session;
  final DeviceInfo device;
  final RateLimiter limiter;
  final http.Client _http;
  final Clock _now;
  final Sleeper _sleep;
  final Random _rand;

  /// 调试日志；默认只在 debug 构建里打印。
  final void Function(String line)? log;

  /// GET 自动重试的最大次数（不含首次）。
  final int maxRetries;

  /// 令牌离过期不到这么久就提前刷新。
  final Duration refreshMargin;

  final _inflight = <String, Future<Object?>>{};
  final _cache = LinkedHashMap<String, _CacheEntry>();
  static const _cacheMax = 128;
  Future<void>? _refreshing;
  StreamSubscription<AuthTokens?>? _sessionSub;

  ApiClient({
    required this.config,
    required this.session,
    required this.device,
    http.Client? httpClient,
    RateLimiter? limiter,
    Clock? now,
    Sleeper? sleep,
    Random? random,
    void Function(String line)? log,
    this.maxRetries = 2,
    this.refreshMargin = const Duration(seconds: 60),
  })  : _http = httpClient ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _rand = random ?? Random(),
        limiter = limiter ?? RateLimiter.standard(now: now, sleep: sleep, random: random),
        log = log ?? (kDebugMode ? debugPrint : null) {
    // 退出 / 会话失效时丢掉缓存，避免下一个账号看到上一个账号的数据。
    _sessionSub = session.onChanged.listen((t) {
      if (t == null) clearCache();
    });
  }

  // ---------------------------------------------------------------- 公共方法

  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    Decoder<T>? decode,
    bool auth = true,
    bool retry = true,
    Duration? cacheTtl,
    bool staleOnError = false,
    bool dedupe = true,
    Duration? timeout,
    CancelToken? cancel,
  }) async {
    final uri = config.uri(path, query);
    final key = 'GET $uri';
    final now = _now();
    final hit = _cache[key];
    if (cacheTtl != null && hit != null && now.difference(hit.at) < cacheTtl) {
      return _decode(hit.data, decode);
    }
    Future<Object?> run() => _withRetry(() => _call('GET', path, uri, auth: auth, timeout: timeout), retry: retry);
    Future<Object?> shared;
    if (dedupe) {
      // 注意回调用块体：箭头函数会把 remove 返回的 Future 交给 whenComplete，它会等自己完成而死锁。
      shared = _inflight[key] ??= run().whenComplete(() {
        _inflight.remove(key);
      });
    } else {
      shared = run();
    }
    final Object? data;
    try {
      data = await _raceCancel(shared, cancel);
    } on ApiException catch (e) {
      if (staleOnError && hit != null && (e.isNetwork || e.kind == ApiErrorKind.server || e.isRateLimited)) {
        log?.call('[api] $key 失败（${e.kind.name}），使用缓存数据');
        return _decode(hit.data, decode);
      }
      rethrow;
    }
    if (cacheTtl != null || staleOnError) _put(key, data);
    return _decode(data, decode);
  }

  Future<T> post<T>(String path, {Object? body, Map<String, Object?>? query, Decoder<T>? decode, bool auth = true, bool retry = false, Duration? timeout, CancelToken? cancel}) =>
      _write('POST', path, body: body, query: query, decode: decode, auth: auth, retry: retry, timeout: timeout, cancel: cancel);

  Future<T> put<T>(String path, {Object? body, Map<String, Object?>? query, Decoder<T>? decode, bool auth = true, bool retry = false, Duration? timeout, CancelToken? cancel}) =>
      _write('PUT', path, body: body, query: query, decode: decode, auth: auth, retry: retry, timeout: timeout, cancel: cancel);

  Future<T> delete<T>(String path, {Object? body, Map<String, Object?>? query, Decoder<T>? decode, bool auth = true, bool retry = false, Duration? timeout, CancelToken? cancel}) =>
      _write('DELETE', path, body: body, query: query, decode: decode, auth: auth, retry: retry, timeout: timeout, cancel: cancel);

  /// 清缓存。传 [pathPrefix]（如 '/announcements'）只清这一类；写操作成功后用它让列表重新拉取。
  void clearCache([String? pathPrefix]) {
    if (pathPrefix == null) return _cache.clear();
    final p = 'GET ${config.uri(pathPrefix)}';
    _cache.removeWhere((k, _) => k.startsWith(p));
  }

  /// 刷新访问令牌（单飞）。一般不用手动调，[ApiClient] 会在需要时自动刷新。
  Future<void> refreshTokens() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  void close() {
    _sessionSub?.cancel();
    _http.close();
  }

  // ---------------------------------------------------------------- 内部流程

  Future<T> _write<T>(String method, String path, {Object? body, Map<String, Object?>? query, Decoder<T>? decode, required bool auth, required bool retry, Duration? timeout, CancelToken? cancel}) async {
    final uri = config.uri(path, query);
    final data = await _raceCancel(_withRetry(() => _call(method, path, uri, body: body, auth: auth, timeout: timeout), retry: retry), cancel);
    return _decode(data, decode);
  }

  /// 一次逻辑请求：处理令牌（提前刷新、40101 刷新后重试一次）。
  Future<Object?> _call(String method, String path, Uri uri, {Object? body, required bool auth, Duration? timeout}) async {
    if (!auth) return _send(method, path, uri, body: body, timeout: timeout);
    var t = session.tokens;
    if (t == null || !t.isValid) throw const ApiException(ApiErrorKind.unauthorized, '请先登录');
    if (t.expiresWithin(refreshMargin, _now())) {
      try {
        await refreshTokens();
      } on ApiException catch (e) {
        // 断网等情况刷新不了：先用旧令牌试试，真过期了服务端会返回 40101 再走一次刷新。
        if (e.isUnauthorized) rethrow;
      }
      t = session.tokens;
      if (t == null) throw const ApiException(ApiErrorKind.unauthorized, '登录已失效，请重新登录');
    }
    try {
      return await _send(method, path, uri, body: body, timeout: timeout, token: t.accessToken);
    } on ApiException catch (e) {
      if (e.code != ApiCode.unauthorized) rethrow;
      // 别的请求可能已经刷新过了：令牌变了就直接用新的重试，不再刷新。
      if (session.tokens?.accessToken == t.accessToken) await refreshTokens();
      final nt = session.tokens;
      if (nt == null) throw const ApiException(ApiErrorKind.unauthorized, '登录已失效，请重新登录');
      return _send(method, path, uri, body: body, timeout: timeout, token: nt.accessToken);
    }
  }

  Future<void> _doRefresh() async {
    final rt = session.tokens?.refreshToken;
    if (rt == null || rt.isEmpty) {
      await session.clear(SessionEnd.expired);
      throw const ApiException(ApiErrorKind.unauthorized, '登录已失效，请重新登录');
    }
    try {
      final data = await _send('POST', '/auth/refresh', config.uri('/auth/refresh'), body: {'refreshToken': rt, 'device': device.toJson()});
      final t = AuthTokens.fromLogin(asJson(data), now: _now());
      if (!t.isValid) throw const ApiException(ApiErrorKind.parse, '刷新令牌返回的数据不完整');
      await session.save(t); // 先落盘再用：旧刷新令牌此刻已经作废了
      log?.call('[api] 令牌已刷新');
    } on ApiException catch (e) {
      // 断网 / 超时 / 5xx / 限流：会话保留，下次再试。其余（40102、40101、参数错误、设备被移除 403 等）都视为会话失效。
      if (e.isNetwork || e.kind == ApiErrorKind.server || e.isRateLimited || e.isCancelled) rethrow;
      log?.call('[api] 刷新失败，会话失效：$e');
      await session.clear(SessionEnd.expired);
      throw ApiException(ApiErrorKind.unauthorized, '登录已失效，请重新登录', code: e.code, httpStatus: e.httpStatus, requestId: e.requestId, cause: e);
    }
  }

  Future<Object?> _withRetry(Future<Object?> Function() f, {required bool retry}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await f();
      } on ApiException catch (e) {
        if (!retry || attempt >= maxRetries) rethrow;
        final Duration wait;
        if (e.isNetwork || e.kind == ApiErrorKind.server) {
          final base = 400 * pow(2, attempt).toInt();
          wait = Duration(milliseconds: base + _rand.nextInt(base ~/ 2 + 1));
        } else if (e.isRateLimited && e.retryAfter != null && e.retryAfter! <= const Duration(seconds: 5)) {
          wait = e.retryAfter! + Duration(milliseconds: _rand.nextInt(300));
        } else {
          rethrow;
        }
        log?.call('[api] ${e.kind.name}，${wait.inMilliseconds}ms 后第 ${attempt + 1} 次重试');
        await _sleep(wait);
      }
    }
  }

  /// 真正发出一个 HTTP 请求并解析信封。成功返回 data。
  Future<Object?> _send(String method, String path, Uri uri, {Object? body, String? token, Duration? timeout}) async {
    final buckets = ['global', if (path.startsWith('/auth/')) 'auth'];
    try {
      await limiter.acquire(buckets);
    } on RateLimitedLocally catch (e) {
      throw ApiException(ApiErrorKind.rateLimited, '操作太频繁了，请稍后再试', retryAfter: e.retryAfter);
    }

    final req = http.Request(method, uri);
    req.headers.addAll({
      'Accept': 'application/json',
      'X-Client-Version': device.appVersion,
      'X-Platform': device.platform,
      if (token != null) 'Authorization': 'Bearer $token',
    });
    if (body != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.body = jsonEncode(body);
    }

    final started = _now();
    final http.Response res;
    try {
      res = await _http.send(req).then(http.Response.fromStream).timeout(timeout ?? config.timeout);
    } on TimeoutException catch (e) {
      log?.call('[api] $method $path 超时');
      throw ApiException(ApiErrorKind.timeout, '请求超时', cause: e);
    } catch (e) {
      log?.call('[api] $method $path 网络错误：$e');
      throw ApiException(ApiErrorKind.network, '网络连接失败', cause: e);
    }
    log?.call('[api] $method $path → ${res.statusCode} (${_now().difference(started).inMilliseconds}ms)');

    final status = res.statusCode;
    Object? decoded;
    try {
      decoded = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map && decoded['code'] is num) {
      final env = decoded.cast<String, dynamic>();
      final code = env.integer('code');
      final msg = env.str('message');
      final rid = env.strOrNull('requestId');
      if (code == ApiCode.ok) {
        limiter.reward(buckets.last);
        return env['data'];
      }
      if (code == ApiCode.rateLimited || status == 429) throw _rateLimited(buckets.last, res, msg, code, rid);
      final kind = switch (code) {
        ApiCode.unauthorized || ApiCode.refreshInvalid => ApiErrorKind.unauthorized,
        ApiCode.internal => ApiErrorKind.server,
        _ => status >= 500 ? ApiErrorKind.server : ApiErrorKind.business,
      };
      throw ApiException(kind, msg, code: code, httpStatus: status, requestId: rid);
    }

    // 没有合法信封：通常是网关 / Cloudflare 层面的错误页。
    if (status == 429) throw _rateLimited(buckets.last, res, '', null, null);
    if (status >= 500) throw ApiException(ApiErrorKind.server, '服务器错误（HTTP $status）', httpStatus: status);
    if (status >= 200 && status < 300) throw ApiException(ApiErrorKind.parse, '响应格式不正确', httpStatus: status);
    throw ApiException(ApiErrorKind.business, '请求失败（HTTP $status）', httpStatus: status);
  }

  ApiException _rateLimited(String bucket, http.Response res, String msg, int? code, String? rid) {
    final ra = int.tryParse(res.headers['retry-after'] ?? '');
    final d = limiter.penalize(bucket, retryAfter: ra == null ? null : Duration(seconds: ra));
    log?.call('[api] 被限流，$bucket 冷却 ${d.inMilliseconds}ms');
    return ApiException(ApiErrorKind.rateLimited, msg, code: code ?? ApiCode.rateLimited, httpStatus: res.statusCode, requestId: rid, retryAfter: d);
  }

  T _decode<T>(Object? data, Decoder<T>? decode) {
    try {
      return decode != null ? decode(data) : data as T;
    } catch (e) {
      log?.call('[api] 解析失败：$e');
      throw ApiException(ApiErrorKind.parse, '数据解析失败', cause: e);
    }
  }

  void _put(String key, Object? data) {
    _cache.remove(key);
    _cache[key] = _CacheEntry(data, _now());
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<R> _raceCancel<R>(Future<R> f, CancelToken? cancel) {
    if (cancel == null) return f;
    if (cancel.isCancelled) return Future.error(const ApiException(ApiErrorKind.cancelled, '已取消'));
    final c = Completer<R>();
    f.then((v) {
      if (!c.isCompleted) c.complete(v);
    }, onError: (Object e, StackTrace s) {
      if (!c.isCompleted) c.completeError(e, s);
    });
    cancel.whenCancelled.then((_) {
      if (!c.isCompleted) c.completeError(const ApiException(ApiErrorKind.cancelled, '已取消'));
    });
    return c.future;
  }
}
