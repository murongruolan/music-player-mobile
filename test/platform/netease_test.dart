// 网易云适配离线测试：加密向量（期望值由 Node 跑桌面端 platform-crypto.ts 原算法得到）、规范化、歌词解析。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/lyric_parse.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/netease.dart';
import 'package:lyra/platform/netease_crypto.dart';

http.Response jsonRes(Object? body, {int status = 200}) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// 解出 eapi 请求里加密的接口路径和 payload。
({String url, Map<String, dynamic> payload}) eapiOf(http.Request req) {
  final d = eapiDecode(Uri.splitQueryString(req.body)['params']!)!;
  return (url: d.url, payload: jsonDecode(d.text) as Map<String, dynamic>);
}

typedef Handler = Future<http.Response> Function(http.Request req);

NeteasePlatform platformWith(Handler handler, {bool quality = false, List<http.Request>? calls}) => NeteasePlatform(
      PlatformHttp(client: MockClient((req) { calls?.add(req); return handler(req); }), sleep: (_) async {}, log: (_) {}),
      fetchQualityDetails: quality,
    );

void main() {
  group('加密向量（与桌面端 JS 逐字节一致）', () {
    test('weapi 空 payload', () {
      expect(
        weapi(const {}, secret: 'abcdefghijklmnop'),
        'params=qFnMWVHk2FofqgdXwao9gVJSweI5iRQHowAHHOvBiiA%3D&encSecKey=d15a1683c992095d0c234c19966605c5c5964911268bbeda8cb8d08d834913e59d53b32358903a121b5fca784c1f5ae44951fd02524df58ecc98e52cc7cf8689b42c2e93ddf05b0592512d87f5960467e2f086c018849d76014d323500e30f13ef4cafbb0cf5a66731a3f1776c75ca35d0062dac70a3e33245afabcf47938487',
      );
    });

    test('weapi 中文 + 数字 + 布尔', () {
      expect(
        weapi({'cat': '华语', 'order': 'hot', 'limit': 30, 'offset': 0, 'total': true}, secret: 'Zx9Qw2Er4Ty6Ui8O'),
        'params=ehXDNokCjZswhARbcNTyJUpNt2Z%2BGItoOyszsUBHzZcseEgq9TOiLb%2BwYbmDKhZUZ8qm6fM2Ae4iD5qLzStz3pOhLdFLyzaNwSotc9AE5RK4MZgfOOw6FXsf3e6rWHXCS%2BgFlTWbPilqZ%2FYhpESZ4A%3D%3D&encSecKey=d50d847993c0ce57d565ae14a87867fd6b525ff65c6334c2f53102d195bf691c14c8a8f53c0812e84ebf38e3ddecceab8730bed2db5fb8823ce35b191c0b13ec3a18849513951b45124dc97d6e47fa4b73d00c3d8566fb338e34cdb2831480f54c752dc598ee90a70e996c919d0adf91f9008ad48beee5d11cd0462fa4afd292',
      );
    });

    test('weapi 嵌套 JSON 字符串（song/detail）', () {
      expect(
        weapi({'c': jsonEncode([{'id': 1}, {'id': 2}]), 'ids': jsonEncode([1, 2])}, secret: 'abcdefghijklmnop'),
        'params=stcT8hbEcBipoi7sPoOj8Sip2lohdj0lDEffbQISWoo2EVoYKOzfhsSHDH4xLev4wQ2VjCfBWpQ%2BJfCjmbXpUvVe3Xmq8YXlh8kw5Ff7E3o%3D&encSecKey=d15a1683c992095d0c234c19966605c5c5964911268bbeda8cb8d08d834913e59d53b32358903a121b5fca784c1f5ae44951fd02524df58ecc98e52cc7cf8689b42c2e93ddf05b0592512d87f5960467e2f086c018849d76014d323500e30f13ef4cafbb0cf5a66731a3f1776c75ca35d0062dac70a3e33245afabcf47938487',
      );
    });

    test('weapi 随机密钥是 16 位 base62', () {
      final s = neteaseRandomSecret();
      expect(s, matches(RegExp(r'^[a-zA-Z0-9]{16}$')));
      expect(weapi(const {}), startsWith('params='));
    });

    test('eapi 单曲搜索', () {
      expect(
        eapi('/api/search/song/list/page', {'keyword': '知我', 'needCorrect': '1', 'channel': 'typing', 'offset': 0, 'scene': 'normal', 'total': true, 'limit': 30}),
        'params=74A595527B7A1647174ADDB4F261E92F180F42F921F98E9D338C60DB20AF499CEA90E95FB2FDA117A0B5D8175C2F21E5E71D86B87C6E74FD9203B4A6FEE082755ECCD6FB95592FA5280348236698BCBBAB8645D8F534488F2E7F9D639BF8146E070B45B5889004E0CC502E9F96CD56ED8E8FB700977800E5C616368B3C31571F7130F5BA92FF81EF767FE901A4783B3A87BCACA418296D0FF073E900D40B535A86B35041CAE02FCF0B7397C6AD4D3771C950F58559E20562CF480D9EB75EE44E168FE2DB2E68501F70D8D5A275E47498',
      );
    });

    test('eapi 歌词', () {
      expect(
        eapi('/api/song/lyric/v1', {'id': '186016', 'cp': false, 'tv': 0, 'lv': 0, 'rv': 0, 'kv': 0, 'yv': 0, 'ytv': 0, 'yrv': 0, 'yromalrc': true}),
        'params=04AE33D34A93FE3EC22DA8FA305D290AB337D0FE5F36D211DE0D338CC6AA89D0DD03BB327E4E8792B5D592510173A15FD461DFF90077763EC1AEFEEA70B344C419ABCE961F17B6B8EC72B6A226725280E97469E44EE0EE9B82E7B6CB0ADD23237407F15E74F871A9201446F7EDF66C80FE6AE21CEAE689CD033C87F311A4A902A7AAC8E3803176E33BDB61F28F886DD23DB329B51A88F047614A81F28AFD9DDCA2EAF5D70BEE990AF940E506C6AE027A',
      );
      final d = eapiDecode(eapiParams('/api/x', {'a': 1}))!;
      expect(d.url, '/api/x');
      expect(d.text, '{"a":1}');
    });

    test('linuxapi 歌单详情', () {
      expect(
        linuxapi({
          'method': 'POST',
          'url': 'https://music.163.com/api/v3/playlist/detail',
          'params': {'id': '3778678', 'n': 100000, 's': 8},
        }),
        'eparams=A0D9583F4C5FF68DE851D2893A49DE98FAFB24399F27B4F7E74C64B6FC49A965CFA972FA5EA3D6247CD6247C8198CB87193DFC37756896DF3666AE409ED93B3934F099F173733DD2A2271FA1255205590F0C81A96ED498E731DBF7B8C9D4A817131922803C7411E66615626146979EF7FC5965DED0B85514DD5B3281C0C36ECB',
      );
    });
  });

  group('搜索', () {
    final songRaw = {
      'id': 186016,
      'name': '晴天',
      'ar': [{'name': '周杰伦'}, {'name': '客串'}],
      'al': {'name': '叶惠美', 'picUrl': 'http://p1.music.126.net/abc/109951.jpg'},
      'dt': 269000,
      'mv': 5302271,
      'l': {'size': 4313356, 'br': 128000},
      'h': {'size': 10783324, 'br': 320000},
      'sq': {'size': 30219344, 'br': 900000},
      'privilege': {'maxbr': 999000, 'maxBrLevel': 'hires'},
    };

    test('单曲：eapi resources → PTrack（秒、歌手连接、封面、音质、mvId）+ 音质补全', () async {
      final calls = <http.Request>[];
      final p = platformWith((req) async {
        if (req.url.path == '/eapi/batch') {
          final e = eapiOf(req);
          expect(e.url, '/api/search/song/list/page');
          expect(e.payload['keyword'], '知我');
          expect(e.payload['offset'], 30);
          expect(e.payload['total'], false);
          expect(req.headers['Origin'], 'https://music.163.com');
          return jsonRes({
            'code': 200,
            'data': {
              'totalCount': 300,
              'resources': [
                {'resourceId': '186016', 'baseInfo': {'simpleSongData': songRaw}},
                {'baseInfo': {}}, // 无 simpleSongData → 跳过
              ],
            },
          });
        }
        if (req.url.path == '/api/song/music/detail/get') {
          expect(req.url.queryParameters['songId'], '186016');
          return jsonRes({'code': 200, 'data': {'jm': {'size': 99000000, 'br': 4000000}}});
        }
        return jsonRes({'code': 404}, status: 404);
      }, quality: true, calls: calls);

      final r = await p.search('  知我  ', SearchType.song, page: 2, limit: 30);
      expect(r.songs, hasLength(1));
      expect(r.total, 300);
      expect(r.hasMore, isTrue);
      final t = r.songs.single;
      expect(t.id, 'wy:186016');
      expect(t.nativeId, '186016');
      expect(t.title, '晴天');
      expect(t.artist, '周杰伦 / 客串');
      expect(t.album, '叶惠美');
      expect(t.duration, 269);
      expect(t.cover, 'https://p1.music.126.net/abc/109951.jpg');
      expect(t.identity, {'id': '186016'});
      expect(t.mvId, '5302271');
      expect(t.qualities, ['128k', '320k', 'flac', 'hires', 'master']);
      expect(t.qualityDetails['flac'], {'size': 30219344, 'bitrate': 900000});
      expect(t.qualityDetails['master'], {'size': 99000000, 'bitrate': 4000000});
      expect(calls.where((c) => c.url.path == '/api/song/music/detail/get'), hasLength(1));
    });

    test('单曲：eapi 失败时退到明文 search/get/web', () async {
      final p = platformWith((req) async {
        if (req.url.path == '/eapi/batch') return jsonRes({'code': 500}, status: 500);
        expect(req.url.toString(), 'https://music.163.com/api/search/get/web');
        final form = Uri.splitQueryString(req.body);
        expect(form, {'s': '知我', 'type': '1', 'limit': '30', 'offset': '0'});
        return jsonRes({
          'code': 200,
          'result': {
            'songCount': 1,
            'songs': [
              {'id': 1, 'name': '知我', 'artists': [{'name': '国风堂'}, {'name': ''}], 'album': {'name': '专辑'}, 'duration': 200400, 'mvid': 0},
            ],
          },
        });
      });
      final r = await p.search('知我', SearchType.song);
      final t = r.songs.single;
      expect(t.duration, 200);
      expect(t.artist, '国风堂');
      expect(t.mvId, isNull);
      expect(t.cover, isNull);
      expect(t.qualities, ['128k']);
      expect(r.total, 1);
      expect(r.hasMore, isFalse);
    });

    test('空关键词不发请求', () async {
      final p = platformWith((req) async => fail('不应请求'));
      expect((await p.search('   ', SearchType.song)).songs, isEmpty);
      expect(await p.suggest(' '), isEmpty);
    });

    test('歌单：明文 search/get/web type=1000', () async {
      final p = platformWith((req) async {
        expect(req.url.path, '/api/search/get/web');
        expect(Uri.splitQueryString(req.body)['type'], '1000');
        return jsonRes({
          'code': 200,
          'result': {
            'playlistCount': 2,
            'playlists': [
              {'id': 111, 'name': '古风歌单', 'coverImgUrl': 'https://p2.music.126.net/x.jpg', 'creator': {'nickname': '小明'}, 'playCount': 123456, 'trackCount': 50},
            ],
          },
        });
      });
      final r = await p.search('古风', SearchType.playlist);
      final it = r.items.single;
      expect(it.type, CatalogType.playlist);
      expect(it.id, '111');
      expect(it.title, '古风歌单');
      expect(it.creator, '小明');
      expect(it.cover, 'https://p2.music.126.net/x.jpg?param=300y300');
      expect(it.playCount, 123456);
      expect(it.trackCount, 50);
      expect(r.total, 2);
    });

    test('歌手 / 专辑：eapi cloudsearch', () async {
      final p = platformWith((req) async {
        final e = eapiOf(req);
        expect(e.url, '/api/cloudsearch/pc');
        if (e.payload['type'] == 100) {
          return jsonRes({
            'code': 200,
            'result': {'artistCount': 1, 'artists': [{'id': 6452, 'name': '周杰伦', 'picUrl': 'https://p1.music.126.net/a.jpg', 'albumSize': 40, 'musicSize': 500}]},
          });
        }
        expect(e.payload['type'], 10);
        return jsonRes({
          'code': 200,
          'result': {
            'albumCount': 1,
            'albums': [
              {'id': 18905, 'name': '叶惠美', 'blurPicUrl': 'https://p1.music.126.net/b.jpg', 'artists': [{'name': '周杰伦'}], 'artist': {'name': '周杰伦'}, 'size': 11, 'publishTime': 1059580800000},
            ],
          },
        });
      });
      final a = (await p.search('周杰伦', SearchType.artist)).items.single;
      expect(a.type, CatalogType.artist);
      expect(a.subtitle, '40 张专辑');
      expect(a.cover, 'https://p1.music.126.net/a.jpg?param=300y300');
      final al = (await p.search('叶惠美', SearchType.album)).items.single;
      expect(al.type, CatalogType.album);
      expect(al.subtitle, '周杰伦');
      expect(al.trackCount, 11);
      expect(al.date, matches(RegExp(r'^2003-07-3[01]$')));
    });

    test('MV：/api/search/get type=1004 → PTrack(mvId)', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/api/search/get');
        return jsonRes({
          'code': 200,
          'result': {'mvCount': 1, 'mvs': [{'id': 5302271, 'name': '晴天', 'artistName': '周杰伦', 'cover': 'http://p1.music.126.net/mv.jpg', 'duration': 271000}]},
        });
      });
      final mv = (await p.search('晴天', SearchType.mv)).songs.single;
      expect(mv.mvId, '5302271');
      expect(mv.artist, '周杰伦');
      expect(mv.duration, 271);
      expect(mv.identity['type'], 'mv');
    });

    test('联想词与热搜', () async {
      final p = platformWith((req) async {
        if (req.url.path == '/api/search/suggest/web') {
          expect(req.url.queryParameters['s'], '晴 天');
          return jsonRes({
            'code': 200,
            'result': {
              'songs': [
                {'name': '晴天', 'artists': [{'name': '周杰伦'}]},
                {'name': '晴天', 'artists': [{'name': '周杰伦'}]},
                {'name': '晴天娃娃', 'artists': []},
              ],
            },
          });
        }
        final e = eapiOf(req);
        expect(e.url, '/api/search/chart/detail');
        expect(e.payload, {'id': 'HOT_SEARCH_SONG#@#'});
        return jsonRes({'code': 200, 'data': {'itemList': [{'searchWord': '知我'}, {'searchWord': ' '}, {'searchWord': '晴天'}]}});
      });
      expect(await p.suggest('晴 天'), ['晴天 - 周杰伦', '晴天娃娃']);
      expect(await p.hotSearch(), ['知我', '晴天']);
    });

    test('热搜失败返回空列表', () async {
      final p = platformWith((req) async => jsonRes({}, status: 503));
      expect(await p.hotSearch(), isEmpty);
    });
  });

  group('歌单广场 / 榜单 / 详情', () {
    test('歌单分类', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/weapi/playlist/catalogue');
        final form = Uri.splitQueryString(req.body);
        expect(form.keys, ['params', 'encSecKey']);
        return jsonRes({
          'code': 200,
          'all': {'name': '全部歌单', 'category': 4},
          'categories': {'0': '语种', '1': '风格'},
          'sub': [{'name': '华语', 'category': 0, 'hot': true}, {'name': '流行', 'category': 1}, {'name': '', 'category': 1}],
        });
      });
      final c = await p.playlistCategories();
      expect(c.map((e) => '${e.id}|${e.name}|${e.group}'), ['recommend|推荐|', '全部|全部歌单|默认', '华语|华语|语种', '流行|流行|风格']);
    });

    test('歌单广场', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/weapi/playlist/list');
        return jsonRes({
          'code': 200,
          'total': 100,
          'more': true,
          'playlists': [
            {'id': 1, 'name': 'A', 'coverImgUrl': 'https://p1.music.126.net/1.jpg', 'creator': {'nickname': '甲'}, 'playCount': 5000, 'trackCount': 20, 'createTime': 1700000000000},
            {'id': 2, 'name': 'B', 'coverImgUrl': 'https://p1.music.126.net/2.jpg?x=1'},
          ],
        });
      });
      final r = await p.playlists(category: '华语', page: 1, limit: 2);
      expect(r.items, hasLength(2));
      expect(r.total, 100);
      expect(r.hasMore, isTrue);
      expect(r.items[0].subtitle, '甲');
      expect(r.items[0].creator, '甲');
      expect(r.items[0].trackCount, 20);
      expect(r.items[0].date, matches(RegExp(r'^2023-11-1[45]$')));
      expect(r.items[1].subtitle, '未知创建者');
      expect(r.items[1].cover, 'https://p1.music.126.net/2.jpg?x=1');
    });

    test('榜单', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/weapi/toplist');
        return jsonRes({
          'code': 200,
          'list': [
            {'id': 19723756, 'name': '飙升榜', 'updateFrequency': '每天更新', 'coverImgUrl': 'https://p1.music.126.net/u.jpg', 'trackCount': 100},
            {'id': 3778678, 'name': '热歌榜', 'coverImgUrl': 'https://p1.music.126.net/h.jpg', 'trackCount': 200},
            {'name': '无 id'},
          ],
        });
      });
      final b = await p.leaderboards();
      expect(b, hasLength(2));
      expect(b[0].type, CatalogType.leaderboard);
      expect(b[0].id, '19723756');
      expect(b[0].subtitle, '每天更新');
      expect(b[0].cover, 'https://p1.music.126.net/u.jpg?param=300y300');
      expect(b[1].subtitle, '网易云音乐实时榜单');
      expect(b[1].trackCount, 200);
    });

    test('歌单详情：linuxapi trackIds → v3/song/detail 分页', () async {
      final p = platformWith((req) async {
        if (req.url.path == '/api/linux/forward') {
          expect(req.headers['Cookie'], 'MUSIC_U=');
          expect(Uri.splitQueryString(req.body).keys, ['eparams']);
          return jsonRes({
            'code': 200,
            'playlist': {
              'name': '热歌榜',
              'description': '描述',
              'coverImgUrl': 'https://p1.music.126.net/c.jpg',
              'creator': {'nickname': '网易云音乐'},
              'trackIds': [{'id': 1}, {'id': 2}, {'id': 3}],
              'tracks': [],
            },
          });
        }
        expect(req.url.toString(), 'https://music.163.com/weapi/v3/song/detail');
        return jsonRes({
          'code': 200,
          'songs': [
            {'id': 3, 'name': '三', 'ar': [{'name': '歌手'}], 'al': {'name': '辑', 'picUrl': 'https://p1.music.126.net/3.jpg'}, 'dt': 180000, 'h': {'size': 7200000}},
          ],
        });
      });
      final c = await p.collection(CatalogType.leaderboard, '3778678', page: 2, limit: 2);
      expect(c.title, '热歌榜');
      expect(c.description, '描述');
      expect(c.cover, 'https://p1.music.126.net/c.jpg');
      expect(c.creator, '网易云音乐');
      expect(c.total, 3);
      expect(c.page, 2);
      expect(c.hasMore, isFalse);
      final t = c.tracks.single;
      expect(t.nativeId, '3');
      expect(t.duration, 180);
      expect(t.qualities, ['320k']);
    });

    test('歌单不存在：业务码 != 200 抛 PlatformException', () async {
      final p = platformWith((req) async => jsonRes({'code': 404, 'msg': 'not found'}));
      await expectLater(p.collection(CatalogType.playlist, '1'), throwsA(isA<PlatformException>().having((e) => e.platform, 'platform', 'wy')));
    });

    test('专辑详情（本地分页）', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/weapi/v1/album/18905');
        return jsonRes({
          'code': 200,
          'album': {'name': '叶惠美', 'description': 'd', 'picUrl': 'https://p1.music.126.net/al.jpg', 'artists': [{'name': '周杰伦'}]},
          'songs': [for (var i = 1; i <= 3; i++) {'id': i, 'name': 's$i', 'ar': [{'name': '周杰伦'}], 'al': {'name': '叶惠美'}, 'dt': 200000}],
        });
      });
      final c = await p.collection(CatalogType.album, 'wy__18905', limit: 2);
      expect(c.title, '叶惠美');
      expect(c.creator, '周杰伦');
      expect(c.tracks.map((t) => t.nativeId), ['1', '2']);
      expect(c.total, 3);
      expect(c.hasMore, isTrue);
    });

    test('歌手详情', () async {
      final p = platformWith((req) async {
        if (req.url.path == '/weapi/artist/head/info/get') {
          return jsonRes({
            'code': 200,
            'data': {'artist': {'name': '周杰伦', 'briefDesc': '简介', 'picUrl': 'https://p1.music.126.net/ar.jpg', 'alias': ['Jay', 'Jay Chou']}, 'user': {}},
          });
        }
        expect(req.url.path, '/weapi/v1/artist/songs');
        return jsonRes({'code': 200, 'total': 500, 'more': true, 'songs': [{'id': 9, 'name': '晴天', 'ar': [{'name': '周杰伦'}], 'al': {'name': '叶惠美'}, 'dt': 269000}]});
      });
      final c = await p.collection(CatalogType.artist, '6452', limit: 1);
      expect(c.title, '周杰伦');
      expect(c.description, '简介');
      expect(c.cover, 'https://p1.music.126.net/ar.jpg');
      expect(c.creator, 'Jay / Jay Chou');
      expect(c.total, 500);
      expect(c.hasMore, isTrue);
      expect(c.tracks.single.title, '晴天');
    });
  });

  group('歌词 / MV', () {
    test('歌词：lrc / tlyric / romalrc / yrc', () async {
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://interface3.music.163.com/eapi/song/lyric/v1');
        final e = eapiOf(req);
        expect(e.url, '/api/song/lyric/v1');
        expect(e.payload['id'], '186016');
        expect(e.payload['yromalrc'], true);
        return jsonRes({
          'code': 200,
          'lrc': {'lyric': '[00:01.00]晴天\n'},
          'tlyric': {'lyric': '[00:01.00]Sunny'},
          'romalrc': {'lyric': ''},
          'yrc': {'lyric': '{"t":0,"c":[{"tx":"作词: "},{"tx":"周杰伦"}]}\n[1000,2000](1000,500,0)晴(1500,1500,0)天\n'},
        });
      });
      final track = const PTrack(platform: 'wy', nativeId: '186016', title: '晴天', artist: '周杰伦', identity: {'id': '186016'});
      final l = await p.lyric(track);
      expect(l.lrc, '[00:01.00]晴天\n');
      expect(l.translation, '[00:01.00]Sunny');
      expect(l.romanization, isNull);
      final w = l.words!.single;
      expect(w.start, 1000);
      expect(w.duration, 2000);
      expect(w.text, '晴天');
      expect(w.words.map((x) => (x.start, x.duration, x.text)), [(1000, 500, '晴'), (1500, 1500, '天')]);
    });

    test('没有歌词抛 PlatformException', () async {
      final p = platformWith((req) async => jsonRes({'code': 200, 'lrc': {'lyric': ''}}));
      await expectLater(p.lyric(const PTrack(platform: 'wy', nativeId: '1', title: '', artist: '')), throwsA(isA<PlatformException>()));
    });

    test('mvUrl', () async {
      var n = 0;
      final p = platformWith((req) async {
        expect(req.url.toString(), 'https://music.163.com/weapi/song/enhance/play/mv/url');
        return n++ == 0 ? jsonRes({'code': 200, 'data': {'url': 'https://vodkgeyttp8.vod.126.net/x.mp4', 'r': 1080}}) : jsonRes({'code': 200, 'data': {'url': '', 'msg': '无版权'}});
      });
      expect(await p.mvUrl('5302271'), 'https://vodkgeyttp8.vod.126.net/x.mp4');
      expect(await p.mvUrl('5302271'), isNull);
      await expectLater(p.mvUrl(' '), throwsA(isA<PlatformException>()));
    });
  });

  group('歌词解析', () {
    test('parseYrc：跳过 JSON 署名行、按开始时间排序', () {
      final lines = parseYrc('{"t":0,"c":[{"tx":"作曲"}]}\n[5000,1000](5000,400,0)B(5400,600,0) b\n[1000,2000](1000,500,0)晴(1500,1500,0)天\n[9000,0]');
      expect(lines.map((l) => l.start), [1000, 5000]);
      expect(lines[1].text, 'B b');
      expect(lines[1].words.last, (start: 5400, duration: 600, text: ' b'));
    });

    test('parseWordLines：KRC 相对偏移 / QRC 字在前', () {
      final krc = parseWordLines('[1000,800]<0,300,0>你<300,500,0>好');
      expect(krc.single.words.map((w) => w.start), [1000, 1300]);
      final qrc = parseWordLines('[2000,1000]你(2000,400)好(2400,300)啊');
      expect(qrc.single.text, '你好啊');
      expect(qrc.single.words.last, (start: 2700, duration: 300, text: '啊'));
    });

    test('parseQrcText：XML 外壳 + 逐字 → LRC + 扩展', () {
      final r = parseQrcText('<?xml version="1.0"?><QrcInfos><Lyric_1 LyricType="1" LyricContent="[ti:晴天]\n[1000,2000]晴(1000,500)天(1500,1500)\n[61500,500]&amp;(61500,500)"/></QrcInfos>');
      expect(r.lyric, '[ti:晴天]\n[00:01.000]晴天\n[01:01.500]&');
      expect(r.extended, '[00:01.000]<0,500>晴<500,1500>天\n[01:01.500]<0,500>&');
      final ext = parseWordLines(r.extended);
      expect(ext.first.words.map((w) => w.start), [1000, 1500]);
      expect(parseQrcText('[00:01.00]普通歌词'), (lyric: '[00:01.00]普通歌词', extended: ''));
    });

    test('lrcTimeMs / lrcTimestamp / stripWordTags', () {
      expect(lrcTimeMs('[01:02.34]'), 62340);
      expect(lrcTimeMs('01:02.3'), 62300);
      expect(lrcTimeMs('00:05'), 5000);
      expect(lrcTimeMs('[ti:x]'), isNull);
      expect(lrcTimestamp(62345), '[01:02.345]');
      expect(stripWordTags('<0,300,0>你<300,500>好(1,2)啊'), '你好啊');
    });

    test('parseLrc / alignTimeline / mergeTranslation', () {
      final base = parseLrc('[ti:x]\n[00:01.00][00:03.00]A\n[00:02.00]B\n[00:04.00]');
      expect(base.map((l) => (l.time, l.text)), [(1000, 'A'), (2000, 'B'), (3000, 'A')]);
      expect(alignTimeline([1000, 2000, 3000], '[00:01.05]甲\n[00:03.00]丙'), ['甲', null, '丙']);
      expect(mergeTranslation('[00:01.00]A\n[00:02.00]B', '[00:02.00]乙'), '[00:01.000]A\n[00:02.000]B\n[00:02.000]乙');
    });
  });
}
