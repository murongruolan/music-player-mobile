import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/core/telemetry.dart';
import 'package:lyra/net/net.dart';
import 'package:lyra/net/storage.dart';

http.Response ok() => http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'r', 'data': null}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // Telemetry 监听前后台
  late List<http.Request> calls;
  late bool offline;
  late MemoryKvStore prefs;
  late DateTime now;

  Future<(Net, Telemetry)> make({bool login = true}) async {
    final net = await Net.build(MemoryKvStore(), prefs: prefs, baseUrl: 'https://api.test/api/v1', sleep: (_) async {}, httpClient: MockClient((r) async {
      calls.add(r);
      if (offline) throw http.ClientException('offline');
      return ok();
    }));
    if (login) await net.session.save(AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(hours: 1))));
    final t = Telemetry(net, now: () => now, batchDelay: const Duration(milliseconds: 30), soonDelay: const Duration(milliseconds: 5));
    await t.init();
    return (net, t);
  }

  setUp(() {
    calls = [];
    offline = false;
    prefs = MemoryKvStore();
    now = DateTime(2026, 11, 2, 12);
  });

  Future<void> wait([int ms = 80]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('一条用 /stats/track，带设备信息', () async {
    final (_, t) = await make();
    t.track('app_launch', {'source': 'normal'});
    await wait();
    expect(calls.single.url.path, '/api/v1/stats/track');
    final b = jsonDecode(calls.single.body) as Map;
    expect(b['eventName'], 'app_launch');
    expect(b['properties'], {'source': 'normal'});
    expect(b['deviceId'], startsWith('m-'));
    expect(b['buildNumber'], isNotNull);
    expect(t.pending, 0);
  });

  test('攒批：多条合并成一次 track-batch', () async {
    final (_, t) = await make();
    for (var i = 0; i < 5; i++) {
      t.track('e$i');
    }
    await wait();
    expect(calls.length, 1);
    expect(calls.single.url.path, '/api/v1/stats/track-batch');
    expect((jsonDecode(calls.single.body)['events'] as List).length, 5);
  });

  test('断网退避：留在队列，退避期内不重发', () async {
    final (_, t) = await make();
    offline = true;
    t.track('a');
    t.track('b');
    await wait();
    final n = calls.length;
    expect(t.pending, 2);
    await t.flush(); // 退避期内
    expect(calls.length, n);
    offline = false;
    now = now.add(const Duration(minutes: 1));
    await t.flush();
    expect(t.pending, 0);
  });

  test('未登录时只入队；队列持久化，重启后补发', () async {
    final (_, t) = await make(login: false);
    t.track('a');
    await wait();
    expect(calls, isEmpty);
    expect(t.pending, 1);
    t.dispose();
    final (_, t2) = await make();
    await wait();
    expect(calls.single.url.path, '/api/v1/stats/track');
    expect(t2.pending, 0);
  });

  test('队列上限 200 条，丢最旧的', () async {
    final (_, t) = await make(login: false);
    for (var i = 0; i < 230; i++) {
      t.track('e$i');
    }
    expect(t.pending, Telemetry.maxQueue);
  });
}
