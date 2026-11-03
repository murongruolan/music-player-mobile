import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/api/announcement_api.dart';
import 'package:lyra/core/announcements.dart';
import 'package:lyra/net/net.dart';
import 'package:lyra/net/storage.dart';

http.Response ok(Object? data) => http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'r', 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> ann(String id, String level, {bool dismissible = true, String at = '2026-11-01T08:00:00Z'}) =>
    {'id': id, 'title': 't$id', 'content': 'c$id', 'level': level, 'dismissible': dismissible, 'createdAt': at};

void main() {
  late List<http.Request> calls;
  late List<Map<String, dynamic>> served;
  late bool offline;
  late MemoryKvStore prefs;

  Future<(Net, Announcements)> make() async {
    final net = await Net.build(
      MemoryKvStore(),
      prefs: prefs,
      baseUrl: 'https://api.test/api/v1',
      sleep: (_) async {}, // 重试不真的等
      httpClient: MockClient((r) async {
        calls.add(r);
        if (offline) throw http.ClientException('offline');
        if (r.method == 'GET') return ok({'items': served});
        return ok(null);
      }),
    );
    await net.session.save(AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(hours: 1))));
    return (net, Announcements(net, () {}));
  }

  setUp(() {
    calls = [];
    offline = false;
    prefs = MemoryKvStore();
    served = [ann('1', 'info'), ann('2', 'warning', at: '2026-11-02T08:00:00Z'), ann('3', 'sticky'), ann('4', 'info', dismissible: false)];
  });

  test('后端字段映射到界面模型', () async {
    final (_, a) = await make();
    await a.load();
    expect(a.items.first.id, '2'); // 按时间倒序
    final m = {for (final x in a.items) x.id: x};
    expect(m['1']!.popup, isFalse);
    expect(m['2']!.important, isTrue);
    expect(m['2']!.type, '重要');
    expect(m['3']!.type, '置顶');
    expect(m['4']!.closable, isFalse);
    expect(m['4']!.popup, isTrue); // 必须确认的也要弹
    expect(a.popups.map((x) => x.id).toSet(), {'2', '3', '4'});
    expect(a.unread, 4);
  });

  test('标记已读后上报对应动作', () async {
    final (_, a) = await make();
    await a.load();
    final m = {for (final x in a.items) x.id: x};
    a.mark(m['2']!, AnnouncementAction.dismiss);
    a.mark(m['4']!, AnnouncementAction.confirm);
    a.mark(m['4']!, AnnouncementAction.confirm); // 重复点不重复上报
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final posts = calls.where((r) => r.method == 'POST').map((r) => r.url.path).toList();
    expect(posts, ['/api/v1/announcements/2/dismiss', '/api/v1/announcements/4/confirm']);
    expect(jsonDecode(calls.last.body)['deviceId'], startsWith('m-'));
    expect(a.unread, 2);
  });

  test('断网时上报留在队列，重启后补发', () async {
    final (_, a) = await make();
    await a.load();
    offline = true;
    a.mark(a.items.first, AnnouncementAction.read);
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    // 模拟重启：新的控制器从本地恢复
    offline = false;
    calls.clear();
    final (_, b) = await make();
    await b.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls.where((r) => r.method == 'POST').map((r) => r.url.path), ['/api/v1/announcements/2/read']);
    expect(b.isRead(b.items.first), isTrue);
  });

  test('服务端不再下发的公告保留在历史里并算已读', () async {
    final (_, a) = await make();
    await a.load();
    served = [ann('2', 'warning')];
    await a.load();
    expect(a.items.length, 4);
    expect(a.unread, 1);
  });

  test('退出登录清掉本机公告数据', () async {
    final (_, a) = await make();
    await a.load();
    await a.reset();
    expect(a.items, isEmpty);
    expect(await prefs.read('ann.history.v1'), isNull);
  });
}
