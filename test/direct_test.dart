// 平台直链层测试：MockClient 模拟各平台响应，覆盖
// 没凭证 / 非会员 / 会员三种情况、咪咕 200002、缓存与试听黑名单、凭证失效 markExpired。
//
// 一律不绕过会员限制：VIP 歌在非会员/匿名下必须返回 null（交给音源脚本）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/net/storage.dart';
import 'package:lyra/net/json.dart';
import 'package:lyra/platform/credentials.dart';
import 'package:lyra/audio/track_resolver.dart' show ResolveReason;
import 'package:lyra/data/models.dart';
import 'package:lyra/source/music_resolver.dart';
import 'package:lyra/source/source_manager.dart' show UrlIssue;
import 'package:lyra/platform/http.dart';
import 'package:lyra/source/direct/direct.dart';
import 'package:lyra/source/direct/direct_url.dart';
import 'package:lyra/source/direct/direct_sources.dart';

/// 组一个网易云 track（lx 结构）。
Json wyTrack({List<String> qualities = const ['128k', '320k', 'flac']}) => {
      'platform': 'wy',
      'id': 'wy:123',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200,
      'identity': {'id': '123'},
      'qualities': qualities,
    };

Json txTrack() => {
      'platform': 'tx',
      'id': 'tx:456',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200,
      'identity': {'id': '456', 'songId': '456', 'strMediaMid': '002abcd'},
      'qualities': ['128k', '320k', 'flac'],
    };

Json kgTrack({String hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}) => {
      'platform': 'kg',
      'id': 'kg:$hash',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200,
      'identity': {'id': hash, 'hash': hash, 'qualityHashes': {'128k': hash}},
      'qualities': ['128k'],
    };

Json kwTrack() => {
      'platform': 'kw',
      'id': 'kw:789',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200,
      'identity': {'id': '789'},
      'qualities': ['128k'],
    };

Json mgTrack() => {
      'platform': 'mg',
      'id': 'mg:abc',
      'title': '歌名',
      'artist': '歌手',
      'duration': 200,
      'identity': {'id': 'abc', 'copyrightId': 'COP123'},
      'qualities': ['128k'],
    };

PlatformHttp mockHttp(Future<http.Response> Function(http.Request) handler) =>
    PlatformHttp(client: MockClient(handler));

void main() {
  group('网易云（eapi 直链）', () {
    test('匿名游客 Cookie 取免费歌', () async {
      var sawCookie = '';
      final httpx = mockHttp((req) async {
        sawCookie = req.headers['Cookie'] ?? '';
        return http.Response(jsonEncode({
          'code': 200,
          'data': [
            {'url': 'https://m801.music.126.net/x.mp3', 'fee': 0, 'level': 'standard', 'freeTrialInfo': null},
          ],
        }), 200);
      });
      final creds = PlatformCredentials(MemoryKvStore());
      await creds.saveAnonymous('wy', 'MUSIC_A=guest-cookie');
      final d = await wyDirect(httpx, wyTrack(), '128k', anonCookie: creds.anonymousCookie('wy'));
      expect(d, isNotNull);
      expect(d!.url, 'https://m801.music.126.net/x.mp3');
      expect(d.quality, '128k');
      expect(sawCookie, 'MUSIC_A=guest-cookie');
    });

    test('VIP 专享歌（fee=1）非会员返回 null', () async {
      final httpx = mockHttp((req) async => http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {'url': 'https://cdn/vip.mp3', 'fee': 1, 'level': 'lossless', 'freeTrialInfo': null},
            ],
          }),
          200));
      final d = await wyDirect(httpx, wyTrack(qualities: ['flac']), 'flac'); // 无凭证 = 非会员
      expect(d, isNull);
    });

    test('会员（vipActive）可取 VIP 歌完整地址', () async {
      final httpx = mockHttp((req) async => http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {'url': 'https://cdn/vip-full.flac', 'fee': 1, 'level': 'lossless', 'freeTrialInfo': null},
            ],
          }),
          200));
      final creds = PlatformCredentials(MemoryKvStore());
      await creds.save(PlatformCredential(
        platform: 'wy',
        cookie: 'MUSIC_A=vip; __csrf=csrf1',
        isVip: true,
        extra: {CredKey.wyCsrf: 'csrf1'},
        savedAt: DateTime.now(),
      ));
      final d = await wyDirect(httpx, wyTrack(qualities: ['flac']), 'flac', cred: creds.of('wy'));
      expect(d, isNotNull);
      expect(d!.quality, 'SQ');
    });

    test('登录失效（code 301）抛 DirectAuthException → markExpired 被调用', () async {
      final httpx = mockHttp((req) async => http.Response(jsonEncode({'code': 301}), 200));
      final creds = PlatformCredentials(MemoryKvStore());
      await creds.save(PlatformCredential(platform: 'wy', cookie: 'MUSIC_A=old', isVip: true, savedAt: DateTime.now()));
      expect(creds.of('wy'), isNotNull);
      expect(
        () async => wyDirect(httpx, wyTrack(), '128k', cred: creds.of('wy')),
        throwsA(isA<DirectAuthException>()),
      );
      await creds.markExpired('wy', '网易云登录已过期');
      expect(creds.expiredReason('wy'), isNotNull);
      expect(creds.of('wy'), isNull); // 标记失效后 of 返回 null
    });
  });

  group('QQ音乐（musicu.fcg，必须有凭证）', () {
    test('匿名一律返回 null', () async {
      var requested = false;
      final httpx = mockHttp((req) async {
        requested = true;
        return http.Response('{}', 200);
      });
      final d = await txDirect(httpx, txTrack(), '320k', cred: null);
      expect(d, isNull);
      expect(requested, isFalse, reason: '匿名不应该发请求');
    });

    test('有凭证 + qm_keyst 拿到 vkey 拼地址', () async {
      final httpx = mockHttp((req) async {
        final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map;
        expect(body['req_1']['module'], 'vkey.GetEVkey');
        expect(body['comm']['uin'], '123');
        return http.Response(
            jsonEncode({
              'req_1': {
                'data': {
                  'midurlinfo': [
                    {'purl': 'RS02M500002abcd.mp3?x=1'},
                  ],
                },
              },
            }),
            200);
      });
      final creds = PlatformCredentials(MemoryKvStore());
      await creds.save(PlatformCredential(
        platform: 'tx',
        cookie: 'qm_keyst=KEY123',
        isVip: true,
        extra: {CredKey.txUin: '123', CredKey.txKeyst: 'KEY123'},
        savedAt: DateTime.now(),
      ));
      final d = await txDirect(httpx, txTrack(), '320k', cred: creds.of('tx'));
      expect(d, isNotNull);
      expect(d!.url, startsWith('http://ws.stream.qqmusic.qq.com/'));
      expect(d.url, contains('002abcd'));
    });

    test('有凭证但缺 qm_keyst 返回 null', () async {
      final httpx = mockHttp((req) async => http.Response('{}', 200));
      final creds = PlatformCredentials(MemoryKvStore());
      await creds.save(PlatformCredential(platform: 'tx', cookie: 'a=b', savedAt: DateTime.now()));
      final d = await txDirect(httpx, txTrack(), '320k', cred: creds.of('tx'));
      expect(d, isNull);
    });
  });

  group('酷狗（getSongInfo.php）', () {
    test('hash 命中返回直链', () async {
      final httpx = mockHttp((req) async {
        expect(req.url.host, 'm.kugou.com');
        expect(req.url.queryParameters['hash'], 'a' * 32);
        return http.Response(jsonEncode({'status': 1, 'url': 'https://kg-cdn/file.mp3'}), 200);
      });
      final d = await kgDirect(httpx, kgTrack(), '128k');
      expect(d!.url, 'https://kg-cdn/file.mp3');
    });

    test('status != 1 返回 null', () async {
      final httpx = mockHttp((req) async => http.Response(jsonEncode({'status': 0, 'url': ''}), 200));
      expect(await kgDirect(httpx, kgTrack(), '128k'), isNull);
    });
  });

  group('酷我（playUrl，带 Referer）', () {
    test('code 200 返回直链并带 Referer 头', () async {
      final httpx = mockHttp((req) async {
        expect(req.headers['Referer'], 'https://www.kuwo.cn/');
        return http.Response(jsonEncode({'code': 200, 'data': {'url': 'https://kw-cdn/file.mp3'}}), 200);
      });
      final d = await kwDirect(httpx, kwTrack(), '128k');
      expect(d!.url, 'https://kw-cdn/file.mp3');
      expect(d.headers['Referer'], 'https://www.kuwo.cn/');
    });

    test('code 非 200（VIP 歌）返回 null', () async {
      final httpx = mockHttp((req) async => http.Response(jsonEncode({'code': 431, 'msg': 'vip'}), 200));
      expect(await kwDirect(httpx, kwTrack(), '128k'), isNull);
    });
  });

  group('咪咕（resourceinfo，200002 = 无权限）', () {
    test('000000 解析出音频地址并带 Referer 头', () async {
      final httpx = mockHttp((req) async => http.Response(
          jsonEncode({
            'code': '000000',
            'data': {
              'resourceList': [
                {
                  'contentList': [
                    {'itemType': '2', 'item': {'url': 'https://migu-cdn/file.mp3'}},
                  ],
                },
              ],
            },
          }),
          200));
      final d = await mgDirect(httpx, mgTrack(), '128k');
      expect(d!.url, 'https://migu-cdn/file.mp3');
      expect(d.headers['Referer'], 'https://app.c.nf.migu.cn/');
    });

    test('code 200002（无权限）返回 null', () async {
      final httpx = mockHttp((req) async => http.Response(jsonEncode({'code': '200002'}), 200));
      expect(await mgDirect(httpx, mgTrack(), '128k'), isNull);
    });
  });

  group('DirectLinkResolver 编排', () {
    test('play 用缓存、reload 绕过缓存、trial 进黑名单', () async {
      var hits = 0;
      final httpx = mockHttp((req) async {
        hits++;
        return http.Response(jsonEncode({'code': 200, 'data': {'url': 'https://kw-cdn/file.mp3'}}), 200);
      });
      final creds = PlatformCredentials(MemoryKvStore());
      final direct = DirectLinkResolver(creds, http: httpx);
      final track = kwTrack();

      final a = await direct.resolve(track, '128k'); // play：发请求
      expect(a, isNotNull);
      final b = await direct.resolve(track, '128k'); // play：走缓存
      expect(hits, 1, reason: '第二次应命中缓存');
      expect(b!.url, a!.url);

      final c = await direct.resolve(track, '128k', reason: ResolveReason.reload); // reload：绕过缓存
      expect(hits, 2);
      expect(c, isNotNull);

      final t = await direct.resolve(track, '128k', reason: ResolveReason.trial); // trial：黑名单
      expect(t, isNull);
      expect(await direct.resolve(track, '128k'), isNull, reason: '黑名单后本会话不再用直链');
      expect(hits, 2);
    });

    test('凭证变化清对应平台缓存', () async {
      var hits = 0;
      final httpx = mockHttp((req) async {
        hits++;
        return http.Response(jsonEncode({'code': '000000', 'data': {'resourceList': []}}), 200);
      });
      final creds = PlatformCredentials(MemoryKvStore());
      final direct = DirectLinkResolver(creds, http: httpx);
      final track = mgTrack();
      await direct.resolve(track, '128k'); // 失败也会被缓存吗？不会：null 不入缓存
      expect(hits, 1);
      await direct.resolve(track, '128k');
      expect(hits, 2, reason: 'null 结果不入缓存，会重试');
      // 凭证变化：清缓存（此处仅验证订阅与清理不抛）
      final sub = creds.changes.listen((code) => direct.clearPlatform(code));
      await creds.saveAnonymous('mg', null);
      await sub.cancel();
    });

    test('直链 URL 检测不过（试听）回退音源脚本（resolveDirect 返回 null）', () async {
      final httpx = mockHttp((req) async => http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {'url': 'https://cdn/trial.mp3', 'fee': 0, 'level': 'standard', 'freeTrialInfo': {'end': 30}},
            ],
          }),
          200));
      final creds = PlatformCredentials(MemoryKvStore());
      final direct = DirectLinkResolver(creds, http: httpx);
      final resolver = MusicResolver()..direct = direct;
      final result = await resolver.resolveDirect(
        wyTrack(),
        const Song(0, '歌名', '歌手', '专辑', 200, 'HQ', 0.5, 0),
        '128k',
        ResolveReason.play,
        checkUrl: (url, duration) async => UrlIssue.trial, // 检测判为试听
      );
      expect(result, isNull, reason: '试听片段：回退音源脚本');
      // 再问一次：本曲已进黑名单，不再请求直链
      final again = await resolver.resolveDirect(
        wyTrack(),
        const Song(0, '歌名', '歌手', '专辑', 200, 'HQ', 0.5, 0),
        '128k',
        ResolveReason.play,
        checkUrl: (url, duration) async => null,
      );
      expect(again, isNull, reason: '黑名单生效');
    });
  });

  test('maskSecret 打码（凭证不落日志）', () {
    expect(maskSecret('MUSIC_A=verylongsecretvalue'), isNot(contains('verylongsecretvalue')));
    expect(maskSecret('short'), '*****');
  });
}
