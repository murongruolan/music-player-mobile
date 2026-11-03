import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/core/listening_stats.dart';
import 'package:lyra/net/net.dart';
import 'package:lyra/net/storage.dart';
import 'package:lyra/sync/cloud_models.dart';
import 'package:lyra/sync/sync_doc.dart';
import 'package:lyra/sync/sync_engine.dart';
import 'package:lyra/sync/sync_socket.dart';

http.Response ok(Object? data) => http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'r', 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
http.Response err(int status, int code, String msg) => http.Response(jsonEncode({'code': code, 'message': msg, 'requestId': 'r', 'data': null}), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// 按后端 sync.ts / sync-hub.ts 的规则实现的假服务端。
class FakeServer {
  final docs = <String, (int, Object?)>{};
  final pushes = <Map<String, dynamic>>[];
  bool sponsor = true;
  int pulls = 0;

  Future<http.Response> handle(http.Request r) async {
    if (!sponsor) return err(403, 40301, '云同步是赞助用户专属功能');
    if (r.url.path.endsWith('/sync/pull')) {
      pulls++;
      final t = r.url.queryParameters['docType']!;
      final since = int.parse(r.url.queryParameters['sinceRevision'] ?? '0');
      final (rev, p) = docs[t] ?? (0, null);
      return ok({'changed': rev > since, 'revision': rev, 'updatedAt': rev > 0 ? '2026-11-02T00:00:00Z' : '', 'payload': rev > since ? p : null});
    }
    if (r.url.path.endsWith('/sync/push')) {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      pushes.add(b);
      final t = b['docType'] as String;
      final base = b['baseRevision'] as int;
      final (cur, p) = docs[t] ?? (0, null);
      if (b['force'] != true && base < cur) return ok({'conflict': true, 'revision': cur, 'updatedAt': 'x', 'payload': p});
      final nr = base > cur ? base + 1 : cur + 1;
      docs[t] = (nr, b['payload']);
      return ok({'conflict': false, 'revision': nr, 'updatedAt': 'x', 'payload': null});
    }
    return err(404, 40401, 'nf');
  }
}

/// 一个集合型的假文档：字符串集合，合并取并集。
class SetDoc extends SyncDoc {
  @override
  final String type;
  final Set<String> items;
  SetDoc(this.type, [Set<String>? init]) : items = init ?? {};
  @override
  String get label => type;
  @override
  bool get isEmpty => items.isEmpty;
  @override
  Object export() => {'items': items.toList()..sort()};
  @override
  bool apply(Object? remote, {bool replace = false}) {
    final r = ((remote as Map)['items'] as List).cast<String>().toSet();
    final extra = !replace && items.difference(r).isNotEmpty;
    if (replace) items.clear();
    items.addAll(r);
    return extra;
  }

  void add(String s) {
    items.add(s);
    onLocalChange?.call();
  }
}

class FakeSocket implements SyncSocket {
  final _c = StreamController<String>();
  final sent = <String>[];
  @override
  Stream<String> get messages => _c.stream;
  @override
  void send(String text) => sent.add(text);
  @override
  Future<void> close() async => _c.close();
  void emit(Object m) => _c.add(jsonEncode(m));
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  late FakeServer server;
  late MemoryKvStore prefs;
  late Net net;
  FakeSocket? sock;

  setUp(() async {
    server = FakeServer();
    prefs = MemoryKvStore();
    sock = null;
    net = await Net.build(MemoryKvStore(), prefs: prefs, baseUrl: 'https://api.test/api/v1', sleep: (_) async {}, httpClient: MockClient((r) => server.handle(r)));
    await net.session.save(AuthTokens(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(hours: 1))));
  });

  SyncEngine engine(List<SyncDoc> docs, {bool ws = false}) => SyncEngine(
        client: net.client,
        prefs: prefs,
        docs: docs,
        live: {for (final d in docs) d.type},
        debounce: const Duration(milliseconds: 10),
        connect: (_) async => ws ? (sock = FakeSocket()) : null,
      );

  test('首次同步：云端为空、本机有数据 → 推送', () async {
    final d = SetDoc('library', {'a'});
    final e = engine([d]);
    await e.start();
    expect(server.docs['library']!.$1, 1);
    expect(e.stateOf('library').revision, 1);
    expect(e.status.value.phase, SyncPhase.idle);
    await e.stop();
  });

  test('首次同步：云端有数据 → 合并，本机多出来的再推上去', () async {
    server.docs['library'] = (5, {'items': ['b']});
    final d = SetDoc('library', {'a'});
    final e = engine([d]);
    await e.start();
    expect(d.items, {'a', 'b'});
    expect(server.docs['library']!.$1, 6);
    expect((server.docs['library']!.$2 as Map)['items'], ['a', 'b']);
    await e.stop();
  });

  test('云端有数据、本机为空 → 只拉不推', () async {
    server.docs['library'] = (3, {'items': ['b']});
    final d = SetDoc('library');
    final e = engine([d]);
    await e.start();
    expect(d.items, {'b'});
    expect(server.pushes, isEmpty);
    await e.stop();
  });

  test('本机修改防抖后推送；改了又改回去不推', () async {
    final d = SetDoc('library', {'a'});
    final e = engine([d]);
    await e.start();
    server.pushes.clear();
    d.add('b');
    d.add('c');
    await settle();
    expect(server.pushes.length, 1);
    expect(server.pushes.single['baseRevision'], 1);
    expect(server.pushes.single['force'], false);

    d.items.remove('c');
    d.items.add('c'); // 内容没变
    d.onLocalChange!();
    await settle();
    expect(server.pushes.length, 1);
    await e.stop();
  });

  test('冲突：合并远端快照后用新 revision 再推一次', () async {
    final d = SetDoc('library', {'a'});
    final e = engine([d]);
    await e.start(); // r1
    server.docs['library'] = (4, {'items': ['a', 'z']}); // 别的设备推了
    server.pushes.clear();
    d.add('b');
    await settle();
    expect(server.pushes.map((p) => p['baseRevision']), [1, 4]);
    expect(d.items, {'a', 'b', 'z'});
    expect(server.docs['library']!.$1, 5);
    expect(e.stateOf('library').revision, 5);
    await e.stop();
  });

  test('同步进度持久化：重启后从记录的 revision 增量拉取', () async {
    final d = SetDoc('library', {'a'});
    final e = engine([d]);
    await e.start();
    await e.stop();
    server.pulls = 0;
    final e2 = engine([SetDoc('library', {'a'})]);
    await e2.start();
    expect(e2.stateOf('library').revision, 1);
    expect(server.pushes.length, 1); // 没有重复推
    await e2.stop();
  });

  test('WebSocket 收到其它设备的变更 → 拉取；自己推的不重复拉', () async {
    final d = SetDoc('library', {'a'});
    final e = engine([d], ws: true);
    await e.start();
    await settle();
    expect(e.status.value.realtime, isTrue);

    server.pulls = 0;
    sock!.emit({'type': 'changed', 'docType': 'library', 'revision': 1}); // 自己推的
    await settle();
    expect(server.pulls, 0);

    server.docs['library'] = (2, {'items': ['a', 'q']});
    sock!.emit({'type': 'changed', 'docType': 'library', 'revision': 2});
    await settle();
    expect(d.items, {'a', 'q'});
    expect(server.pulls, 1);
    await e.stop();
  });

  test('非赞助用户（40301）→ 停止并进入 needSponsor', () async {
    server.sponsor = false;
    final e = engine([SetDoc('library', {'a'})]);
    await e.start();
    expect(e.status.value.phase, SyncPhase.needSponsor);
    expect(e.running, isFalse);
  });

  test('手动上传用 force，手动恢复覆盖本机', () async {
    server.docs['listening_stats'] = (7, {'items': ['x']});
    final d = SetDoc('listening_stats', {'a'});
    final e = engine([d]);
    final r = await e.download('listening_stats');
    expect(r.changed, isTrue);
    expect(d.items, {'x'});
    d.items.add('y');
    await e.upload('listening_stats');
    expect(server.pushes.last['force'], true);
    expect(server.docs['listening_stats']!.$1, 8);
  });

  test('未接入的文档不读写', () async {
    final e = SyncEngine(client: net.client, prefs: prefs, docs: [_Unavailable()], live: {'library'}, connect: (_) async => null);
    await e.start();
    expect(server.pulls, 0);
    await expectLater(e.upload('library'), throwsA(isA<ApiException>()));
    await e.stop();
  });

  group('指纹', () {
    test('键顺序和 exportedAt 不影响', () {
      expect(fingerprint({'a': 1, 'b': [1, 2], 'exportedAt': 'x'}), fingerprint({'b': [1, 2], 'a': 1, 'exportedAt': 'y'}));
      expect(fingerprint({'a': 1}), isNot(fingerprint({'a': 2})));
    });
  });

  group('听歌统计', () {
    test('听满 30 秒记一次播放；mock 歌曲不上传', () {
      var now = DateTime(2026, 11, 2, 21);
      final s = ListeningStats(null, () {}, now: () => now);
      s.begin(key: 'wy:1', source: 'wy', songId: '1', name: '夜航星', artist: '不才', durationSec: 240);
      for (var i = 0; i < 29; i++) {
        s.tick(1);
      }
      expect(s.songs['wy:1']!.plays, 0);
      s.tick(1);
      s.tick(1);
      expect(s.songs['wy:1']!.plays, 1);
      expect(s.songs['wy:1']!.hourly[21], 1);
      s.begin(key: 'mock:3', source: 'mock', songId: '3', name: 'm', artist: 'm', durationSec: 20);
      for (var i = 0; i < 12; i++) {
        s.tick(1);
      }
      expect(s.songs['mock:3']!.plays, 1); // 短歌听满一半
      final p = s.toPayload();
      expect((p['items'] as List).length, 1);
      expect((p['stats'] as Map)['songs'], contains('wy:1'));
      expect(s.summary(7).plays, 2);
      expect(s.summary(7).artists, 2);
    });

    test('合并取最大值，幂等；认桌面端和 V2 两种格式', () {
      final s = ListeningStats(null, () {}, now: () => DateTime(2026, 11, 2));
      final desktop = {
        'items': [
          {'track': {'id': 'tx:9', 'platform': 'tx', 'title': 'A', 'artist': 'X', 'duration': 200}, 'playCount': 5, 'totalSeconds': 900, 'dailyPlays': {'2026-11-01': 5}, 'hourlyPlays': List.filled(24, 0)},
        ],
      };
      expect(s.apply(desktop), isFalse);
      expect(s.apply(desktop), isFalse);
      expect(s.songs['tx:9']!.plays, 5);
      expect(s.songs['tx:9']!.ms, 900000);
      final v2 = {
        'stats': {'songs': {'tx:9': {'name': 'A', 'artist': 'X', 'source': 'tx', 'songId': '9', 'plays': 3, 'ms': 1000, 'dailyPlays': {'2026-11-02': 3}}}},
      };
      expect(s.apply(v2), isTrue); // 本机 plays 5 > 3，需要回推
      expect(s.songs['tx:9']!.plays, 5);
      expect(s.songs['tx:9']!.daily, {'2026-11-01': 5, '2026-11-02': 3});
    });
  });

  group('音乐库编解码', () {
    test('桌面端格式与 V2 格式互认，导出两种都带', () {
      final lib = CloudLibrary(
        favorites: [const CloudTrack(id: 'wy:1', platform: 'wy', songId: '1', title: '雾港', artist: 'Ari', durationSec: 205), const CloudTrack(id: 'local:x', platform: 'local', songId: 'x', title: 'l', artist: 'l')],
        playlists: [CloudPlaylist(id: 'p1', name: '夜跑', updatedAt: DateTime.utc(2026, 11, 1), createdAt: DateTime.utc(2026, 10, 1))],
      );
      final p = lib.toPayload();
      expect(((p['items'] as Map)['tracks'] as List).length, 1); // 本地歌曲不上传
      expect(((p['favorites'] as List).first as Map)['song']['duration'], '3:25');
      final viaDesktop = CloudLibrary.parse(jsonDecode(jsonEncode(p)));
      expect(viaDesktop.favorites.single.id, 'wy:1');
      expect(viaDesktop.favorites.single.durationSec, 205);
      final v2Only = Map<String, dynamic>.from(jsonDecode(jsonEncode(p)) as Map)..remove('items');
      final viaV2 = CloudLibrary.parse(v2Only);
      expect(viaV2.favorites.single.title, '雾港');
      expect(viaV2.playlists.single.name, '夜跑');
    });

    test('合并：收藏并集，歌单新的一方胜出', () {
      final old = DateTime.utc(2026, 1, 1), now = DateTime.utc(2026, 11, 1);
      CloudPlaylist pl(String id, String name, DateTime at) => CloudPlaylist(id: id, name: name, updatedAt: at, createdAt: old);
      CloudTrack t(String id) => CloudTrack(id: 'wy:$id', platform: 'wy', songId: id, title: id, artist: '');
      final local = CloudLibrary(favorites: [t('1'), t('2')], playlists: [pl('a', '本机新', now), pl('b', '本机旧', old)]);
      final remote = CloudLibrary(favorites: [t('2'), t('3')], playlists: [pl('a', '云端旧', old), pl('b', '云端新', now), pl('c', '云端', now)]);
      final (m, extra) = CloudLibrary.merge(local, remote);
      expect(m.favorites.map((e) => e.songId), ['1', '2', '3']);
      expect(m.playlists.map((e) => e.name), ['本机新', '云端新', '云端']);
      expect(extra, isTrue);
    });
  });
}

class _Unavailable extends SyncDoc {
  @override
  String get type => 'library';
  @override
  String get label => '音乐库';
  @override
  bool get available => false;
  @override
  bool get isEmpty => true;
  @override
  Object export() => throw UnimplementedError();
  @override
  bool apply(Object? remote, {bool replace = false}) => throw UnimplementedError();
}
