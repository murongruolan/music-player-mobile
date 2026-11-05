import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/playlist_link.dart';

PlatformHttp _http(Future<http.Response> Function(http.Request) h) => PlatformHttp(client: MockClient(h), sleep: (_) async {}, log: (_) {});

void main() {
  group('parsePlaylistUrl', () {
    final cases = {
      'https://music.163.com/#/playlist?id=7741029': const PlaylistRef('wy', '7741029'),
      'https://music.163.com/playlist?id=7741029&userid=1': const PlaylistRef('wy', '7741029'),
      'https://y.music.163.com/m/playlist?id=2829883282&creatorId=1': const PlaylistRef('wy', '2829883282'),
      'https://y.qq.com/n/ryqq/playlist/8052190267': const PlaylistRef('tx', '8052190267'),
      'https://i.y.qq.com/n2/m/share/details/taoge.html?platform=11&appshare=android_qq&id=8052190267': const PlaylistRef('tx', '8052190267'),
      'https://www.kuwo.cn/playlist_detail/3570386443': const PlaylistRef('kw', '3570386443'),
      'https://m.kuwo.cn/newh5app/playlist_detail/3570386443?from=ar': const PlaylistRef('kw', '3570386443'),
      'https://www.kugou.com/yy/special/single/546903.html': const PlaylistRef('kg', '546903'),
      'https://m.kugou.com/share/zlist.html?listid=2&type=0&global_collection_id=collection_3_1133_9_0&uid=1': const PlaylistRef('kg', 'collection_3_1133_9_0'),
      'https://m.kugou.com/songlist/gcid_3z9vyb3z1z1/': const PlaylistRef('kg', 'gcid_3z9vyb3z1z1'),
      'https://music.migu.cn/v3/music/playlist/228114498': const PlaylistRef('mg', '228114498'),
      'https://h5.nf.migu.cn/app/v4/p/share/playlist/index.html?id=228114498&channel=0146921': const PlaylistRef('mg', '228114498'),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(parsePlaylistUrl(e.key), e.value));
    }
    test('不是歌单的链接', () {
      expect(parsePlaylistUrl('https://music.163.com/song?id=186016'), isNull);
      expect(parsePlaylistUrl('https://example.com/playlist/1'), isNull);
      expect(parsePlaylistUrl('163cn.tv/abc'), isNull);
    });
  });

  test('分享文案里取链接', () {
    expect(firstUrlIn('分享小栗子创建的歌单「夜跑」: https://163cn.tv/zA1b2C (来自@网易云音乐)'), 'https://163cn.tv/zA1b2C');
    expect(firstUrlIn('看看这个 music.163.com/playlist?id=1'), 'https://music.163.com/playlist?id=1');
    expect(firstUrlIn('7741029'), isNull);
  });

  test('前缀 id', () {
    expect(parsePrefixedId('wy:7741029'), const PlaylistRef('wy', '7741029'));
    expect(parsePrefixedId('KG：collection_3_1_9_0'), const PlaylistRef('kg', 'collection_3_1_9_0'));
    expect(parsePrefixedId('7741029'), isNull);
  });

  group('resolvePlaylistInput', () {
    test('纯 id 用所选平台，不发请求', () async {
      var calls = 0;
      final h = _http((_) async {
        calls++;
        return http.Response('', 500);
      });
      expect(await resolvePlaylistInput(' 7741029 ', http: h, fallbackPlatform: 'tx'), const PlaylistRef('tx', '7741029'));
      expect(calls, 0);
    });

    test('短链：跟一次跳转后识别', () async {
      final h = _http((req) async {
        expect(req.followRedirects, isFalse);
        expect(req.url.host, '163cn.tv');
        return http.Response('', 302, headers: {'location': 'https://y.music.163.com/m/playlist?id=2829883282&app_version=9'});
      });
      expect(await resolvePlaylistInput('分享歌单 https://163cn.tv/zA1b2C (来自@网易云音乐)', http: h, fallbackPlatform: 'wy'), const PlaylistRef('wy', '2829883282'));
    });

    test('页面内 JS 跳转', () async {
      final h = _http((req) async => http.Response('<script>location.href="https://y.qq.com/n/ryqq/playlist/8052190267"</script>', 200));
      expect(await resolvePlaylistInput('https://c6.y.qq.com/base/fcgi-bin/u?__=AbCd', http: h, fallbackPlatform: 'wy'), const PlaylistRef('tx', '8052190267'));
    });

    test('酷狗 gcid 解码成 collection id', () async {
      final h = _http((req) async {
        expect(req.url.host, 't.kugou.com');
        expect(req.url.queryParameters['signature'], hasLength(32));
        final body = jsonDecode(req.body) as Map;
        expect((body['data'] as List).first['id'], 'gcid_3z9vyb3z1z1');
        return http.Response(jsonEncode({
          'status': 1,
          'data': {
            'list': [
              {'global_collection_id': 'collection_3_1133_9_0'}
            ]
          }
        }), 200);
      });
      expect(await resolvePlaylistInput('https://m.kugou.com/songlist/gcid_3z9vyb3z1z1/', http: h, fallbackPlatform: 'wy'), const PlaylistRef('kg', 'collection_3_1133_9_0'));
    });

    test('认不出的链接给出明确提示', () async {
      final h = _http((_) async => http.Response('<html></html>', 200));
      expect(() => resolvePlaylistInput('https://example.com/x', http: h, fallbackPlatform: 'wy'), throwsA(isA<PlaylistLinkException>()));
    });
  });
}
