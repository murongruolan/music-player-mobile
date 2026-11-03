import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/net/net.dart';
import 'package:lyra/net/rate_limiter.dart';
import 'package:lyra/net/storage.dart';

/// 假时钟：sleep 不真的等，只把时间往前拨。
class FakeTime {
  DateTime t = DateTime(2026, 1, 1, 12);
  Duration slept = Duration.zero;
  DateTime now() => t;
  Future<void> sleep(Duration d) async {
    t = t.add(d);
    slept += d;
  }

  void advance(Duration d) => t = t.add(d);
}

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'rid', 'data': data}), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response err(int status, int code, String message) =>
    http.Response(jsonEncode({'code': code, 'message': message, 'requestId': 'rid-err', 'data': null}), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> tokens(String a, String r) => {'accessToken': a, 'refreshToken': r, 'expiresIn': 7200, 'user': {'uid': '1', 'email': 'a@b.c', 'nickname': 'n'}};

void main() {
  late FakeTime ft;
  late List<http.Request> calls;
  late Future<http.Response> Function(http.Request) handler;
  late Net net;

  setUp(() async {
    ft = FakeTime();
    calls = [];
    handler = (r) async => ok(null);
    net = await Net.memory(
      httpClient: MockClient((r) {
        calls.add(r);
        return handler(r);
      }),
      now: ft.now,
      sleep: ft.sleep,
      baseUrl: 'https://api.test/api/v1',
    );
  });

  tearDown(() => net.dispose());

  Future<void> login(String access, {Duration ttl = const Duration(hours: 2)}) =>
      net.session.save(AuthTokens(accessToken: access, refreshToken: 'r1', expiresAt: ft.now().add(ttl)));

  int hits(String path) => calls.where((r) => r.url.path == '/api/v1$path').length;

  test('解析信封并解码 data', () async {
    handler = (r) async => ok({'open': true, 'emailVerificationRequired': false, 'maxDevices': 5});
    final s = await net.client.get('/auth/registration-settings', auth: false, decode: (d) => asJson(d).integer('maxDevices'));
    expect(s, 5);
    expect(calls.single.url.toString(), 'https://api.test/api/v1/auth/registration-settings');
    expect(calls.single.headers['Authorization'], isNull);
  });

  test('业务错误抛 ApiException，userMessage 用后端文案', () async {
    handler = (r) async => err(409, 40901, '邮箱已被注册');
    await expectLater(
      net.client.post('/x', auth: false, body: {'a': 1}),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.business).having((e) => e.code, 'code', 40901).having((e) => e.userMessage, 'msg', '邮箱已被注册').having((e) => e.requestId, 'rid', 'rid-err')),
    );
    expect(jsonDecode(calls.single.body), {'a': 1});
  });

  test('需要登录的接口未登录时直接报 unauthorized，不发请求', () async {
    await expectLater(net.client.get('/auth/profile'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)));
    expect(calls, isEmpty);
  });

  test('40101：并发请求只刷新一次，刷新后各自重试成功', () async {
    await login('old');
    handler = (r) async {
      if (r.url.path.endsWith('/auth/refresh')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(jsonDecode(r.body)['refreshToken'], 'r1');
        return ok(tokens('new', 'r2'));
      }
      return r.headers['Authorization'] == 'Bearer new' ? ok(r.url.path) : err(401, 40101, '访问令牌已过期');
    };
    final results = await Future.wait([net.client.get<String>('/a'), net.client.get<String>('/b'), net.client.post<String>('/c')]);
    expect(results, ['/api/v1/a', '/api/v1/b', '/api/v1/c']);
    expect(hits('/auth/refresh'), 1);
    expect(net.session.tokens!.accessToken, 'new');
    expect(net.session.tokens!.refreshToken, 'r2');
    // 新令牌已落盘
    final again = Session(net.store);
    await again.restore();
    expect(again.tokens!.refreshToken, 'r2');
  });

  test('令牌快过期时先刷新再请求', () async {
    await login('old', ttl: const Duration(seconds: 30));
    handler = (r) async => r.url.path.endsWith('/auth/refresh') ? ok(tokens('new', 'r2')) : ok(r.headers['Authorization']);
    expect(await net.client.get<String>('/me'), 'Bearer new');
    expect(calls.map((r) => r.url.path), ['/api/v1/auth/refresh', '/api/v1/me']);
  });

  test('40102：刷新令牌失效 → 清会话并通知 expired', () async {
    await login('old');
    final ended = <SessionEnd>[];
    net.session.onEnd.listen(ended.add);
    handler = (r) async => r.url.path.endsWith('/auth/refresh') ? err(401, 40102, '刷新令牌无效') : err(401, 40101, '访问令牌已过期');
    await expectLater(net.client.get('/me'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)));
    await Future<void>.delayed(Duration.zero);
    expect(net.session.isLoggedIn, isFalse);
    expect(ended, [SessionEnd.expired]);
    expect(await net.store.read('auth.tokens.v1'), isNull);
  });

  test('刷新时断网：会话保留', () async {
    await login('old');
    handler = (r) async {
      if (r.url.path.endsWith('/auth/refresh')) throw http.ClientException('offline');
      return err(401, 40101, '访问令牌已过期');
    };
    await expectLater(net.client.post('/me'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network)));
    expect(net.session.tokens!.accessToken, 'old');
  });

  test('密码错误（HTTP 401 + 40001）不触发刷新', () async {
    await login('old');
    handler = (r) async => err(401, 40001, '账号或密码错误');
    await expectLater(net.auth.login('a@b.c', 'bad'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.business).having((e) => e.userMessage, 'msg', '账号或密码错误')));
    expect(hits('/auth/refresh'), 0);
    expect(net.session.tokens!.accessToken, 'old');
  });

  test('登录成功保存令牌并带上设备信息', () async {
    handler = (r) async => ok(tokens('a1', 'r1'));
    final u = await net.auth.login(' A@b.c ', 'pw');
    expect(u.email, 'a@b.c');
    expect(net.session.tokens!.accessToken, 'a1');
    final body = jsonDecode(calls.single.body) as Map;
    expect(body['account'], 'A@b.c');
    expect((body['device'] as Map)['deviceId'], startsWith('m-'));
  });

  test('退出：通知服务端并清本地，服务端失败也照样清', () async {
    await login('old');
    handler = (r) async => throw http.ClientException('offline');
    await net.auth.logout();
    expect(net.session.isLoggedIn, isFalse);
    expect(jsonDecode(calls.first.body), {'refreshToken': 'r1'});
  });

  test('相同 GET 在途时合并成一个请求', () async {
    final gate = Completer<void>();
    handler = (r) async {
      await gate.future;
      return ok(1);
    };
    final f = Future.wait([net.client.get<int>('/a', auth: false), net.client.get<int>('/a', auth: false), net.client.get<int>('/a', auth: false, query: {'p': 2})]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    expect(await f, [1, 1, 1]);
    expect(calls.length, 2);
  });

  test('GET 遇到 503 自动重试，POST 不重试', () async {
    var n = 0;
    handler = (r) async => ++n < 3 ? http.Response('bad gateway', 503) : ok('done');
    expect(await net.client.get<String>('/a', auth: false), 'done');
    expect(n, 3);
    expect(ft.slept, greaterThan(Duration.zero));

    calls.clear();
    handler = (r) async => http.Response('bad gateway', 503);
    await expectLater(net.client.post('/b', auth: false), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.server)));
    expect(calls.length, 1);
  });

  test('42901：进入冷却，冷却期内不再打服务端', () async {
    handler = (r) async => err(429, 42901, '请求过于频繁');
    await expectLater(net.client.post('/a', auth: false), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.rateLimited).having((e) => e.userMessage, 'msg', '请求过于频繁')));
    expect(calls.length, 1);

    await expectLater(net.client.post('/a', auth: false), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.rateLimited)));
    expect(calls.length, 1);

    ft.advance(const Duration(seconds: 10));
    handler = (r) async => ok(true);
    expect(await net.client.post<bool>('/a', auth: false), isTrue);
    expect(calls.length, 2);
  });

  test('缓存：TTL 内不重复请求；过期后重新拉取；断网时回退旧数据', () async {
    var n = 0;
    handler = (r) async => ok(++n);
    Future<int> fetch() => net.client.get<int>('/c', auth: false, cacheTtl: const Duration(minutes: 1), staleOnError: true);
    expect(await fetch(), 1);
    expect(await fetch(), 1);
    ft.advance(const Duration(minutes: 2));
    expect(await fetch(), 2);

    ft.advance(const Duration(minutes: 2));
    handler = (r) async => throw http.ClientException('offline');
    expect(await fetch(), 2);

    net.client.clearCache('/c');
    await expectLater(fetch(), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network)));
  });

  test('取消：调用方立刻收到 cancelled', () async {
    final gate = Completer<void>();
    handler = (r) async {
      await gate.future;
      return ok(1);
    };
    final c = CancelToken();
    final f = net.client.get('/slow', auth: false, cancel: c);
    c.cancel();
    await expectLater(f, throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.cancelled)));
    gate.complete();
  });

  test('响应不是 JSON 时报 parse / server', () async {
    handler = (r) async => http.Response('<html>', 200);
    await expectLater(net.client.get('/h', auth: false), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.parse)));
  });

  group('RateLimiter', () {
    test('冷却时间指数增长，成功后清零', () {
      final t = FakeTime();
      final l = RateLimiter(now: t.now, random: Random(1));
      final d1 = l.penalize('global');
      expect(() => l.check(['global']), throwsA(isA<RateLimitedLocally>()));
      expect(() => l.check(['auth']), returnsNormally);
      t.advance(const Duration(minutes: 5));
      final d2 = l.penalize('global');
      expect(d1.inMilliseconds, inInclusiveRange(2000, 2500));
      expect(d2.inMilliseconds, inInclusiveRange(4000, 5000));
      t.advance(const Duration(minutes: 5));
      l.reward('global');
      expect(l.penalize('global').inMilliseconds, inInclusiveRange(2000, 2500));
    });

    test('客户端不主动限速：连续请求不排队', () async {
      handler = (r) async => ok(1);
      for (var i = 0; i < 30; i++) {
        await net.client.post('/p', auth: false);
      }
      expect(calls.length, 30);
      expect(ft.slept, Duration.zero);
    });
  });

  test('启动恢复：刷新令牌并更新缓存的账号信息', () async {
    await login('old');
    handler = (r) async => ok({...tokens('new', 'r2'), 'user': {'uid': '7', 'email': 'x@y.z', 'nickname': '新', 'isActivated': true, 'membershipRank': 1}});
    final a = await net.auth.resume();
    expect(a!.nickname, '新');
    expect(a.isSponsor, isTrue);
    final again = Session(net.store);
    await again.restore();
    expect(again.user!['uid'], '7');
  });

  test('启动恢复：刷新令牌失效 → 返回 null 并清会话', () async {
    await login('old');
    handler = (r) async => err(401, 40102, '刷新令牌无效');
    expect(await net.auth.resume(), isNull);
    expect(net.session.isLoggedIn, isFalse);
  });

  test('启动恢复：断网时保留会话和缓存账号', () async {
    handler = (r) async => ok(tokens('a1', 'r1'));
    await net.auth.login('a@b.c', 'pw');
    handler = (r) async => throw http.ClientException('offline');
    final a = await net.auth.resume();
    expect(a!.email, 'a@b.c');
    expect(net.session.isLoggedIn, isTrue);
  });

  test('不保持登录：令牌不落盘', () async {
    handler = (r) async => ok(tokens('a1', 'r1'));
    await net.auth.login('a@b.c', 'pw', remember: false);
    expect(net.session.isLoggedIn, isTrue);
    expect(await net.store.read('auth.tokens.v1'), isNull);
  });

  test('Session 持久化与恢复', () async {
    final store = MemoryKvStore();
    final s = Session(store);
    await s.save(AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime(2030)));
    final s2 = Session(store);
    await s2.restore();
    expect(s2.tokens!.accessToken, 'a');
    expect(s2.tokens!.expiresAt, DateTime(2030));
    await s2.clear(SessionEnd.logout);
    final s3 = Session(store);
    await s3.restore();
    expect(s3.isLoggedIn, isFalse);
  });
}
