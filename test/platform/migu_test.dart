// 咪咕平台离线测试：MRC 样本由 Node 端按桌面端 decodeMiguMrc 的逆运算（XXTEA 64 位加密）生成，并用桌面端原函数验证能解回原文；
// 规范化用接近真实响应的 JSON 走公开方法，期望值与桌面端 PlatformService 在同样输入下的输出对齐（偏差处有注释）。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/migu.dart';
import 'package:lyra/platform/models.dart';

MiguPlatform fake(Map<String, Object> routes, [List<http.Request>? calls]) => MiguPlatform(PlatformHttp(
      sleep: (_) async {},
      log: (_) {},
      client: MockClient((r) async {
        calls?.add(r);
        for (final e in routes.entries) {
          if (r.url.toString().contains(e.key)) {
            final v = e.value;
            return http.Response.bytes(v is String ? utf8.encode(v) : v as List<int>, 200);
          }
        }
        return http.Response('not found', 404);
      }),
    ));

const mrcText = '[ti:知我]\n[0,3000]知(0,500)我(500,500)\n[3000,2000]Hello(3000,1000) World(4000,1000)';

void main() {
  group('crypto vectors (node)', () {
    test('miguSearchSign', () {
      expect(miguSearchSign('知我', '963B7AA0D21511ED807EE5846EC87D20', '1700000000000'), '09006217107df139a47638704eaed643');
    });

    test('decodeMiguMrc', () {
      expect(decodeMiguMrc(mgMrcHex), mrcText);
      expect(decodeMiguMrc(mgMrcHex.toLowerCase()), mrcText);
      expect(decodeMiguMrc('short'), 'short');
    });

    test('parseMiguMrc → LRC + words', () {
      final p = parseMiguMrc(mrcText);
      expect(p.lrc, '[ti:知我]\n[00:00.000]知我\n[00:03.000]Hello World');
      final w = p.words!;
      expect(w.map((e) => (e.start, e.duration, e.text)), [(0, 3000, '知我'), (3000, 2000, 'Hello World')]);
      expect(w[0].words, [(start: 0, duration: 500, text: '知'), (start: 500, duration: 500, text: '我')]);
      expect(w[1].words, [(start: 3000, duration: 1000, text: 'Hello'), (start: 4000, duration: 1000, text: ' World')]);
      // LRC 时间戳行头也支持
      final q = parseMiguMrc('[00:01.50]a(1500,100)b(1600,200)');
      expect(q.lrc, '[00:01.50]ab');
      expect((q.words!.single.start, q.words!.single.duration), (1500, 300));
    });
  });

  group('normalize', () {
    test('miguImage', () {
      expect(miguImage('/prod/x.jpg'), 'https://d.musicapp.migu.cn/prod/x.jpg');
      expect(miguImage('http://d.musicapp.migu.cn/a.jpg'), 'https://d.musicapp.migu.cn/a.jpg');
      expect(miguImage('//d.musicapp.migu.cn/b.jpg'), 'https://d.musicapp.migu.cn/b.jpg');
      expect(
          miguImage([
            {'imgSizeType': '01'},
            {'webpImg': 'c.webp'},
          ]),
          'https://d.musicapp.migu.cn/c.webp');
      expect(miguImage(null), isNull);
      expect(miguImage(''), isNull);
    });

    test('qualities', () {
      expect(miguQualities({'copyrightId': '1'}), ['128k']);
      expect(miguQualities({}), isEmpty);
      expect(miguQualityDetails({
        'newRateFormats': [
          {'formatType': 'SQ', 'androidSize': '30'},
          {'formatType': 'HQ'},
          {'formatType': 'XX', 'size': '1'},
        ]
      }), {
        'flac': {'size': 30},
        '320k': <String, dynamic>{},
      });
    });

    test('normalizeMigu: hh:mm:ss length', () {
      // 桌面端 parseDuration 只取前两段，"00:03:58" 会算成 3 秒；这里按时分秒算
      expect(normalizeMigu({'copyrightId': 'c', 'length': '00:03:58'})!.duration, 238);
      expect(normalizeMigu({'name': 'x'}), isNull);
    });
  });

  group('MiguPlatform', () {
    test('search song: signed headers, nested resultList', () async {
      final calls = <http.Request>[];
      final r = await fake({'searchAll': mgSong}, calls).search('知我', SearchType.song);
      final req = calls.single;
      expect(req.headers['deviceId'], miguDeviceId);
      expect(req.headers['sign'], miguSearchSign('知我', miguDeviceId, req.headers['timestamp']!));
      expect(req.headers['channel'], '0146921');
      expect(req.headers['uiVersion'], 'A_music_3.6.1');
      expect(jsonDecode(req.url.queryParameters['searchSwitch']!), {'song': 1, 'album': 0, 'singer': 0, 'tagSong': 1, 'mvSong': 0, 'bestShow': 1, 'songlist': 0, 'lyricSong': 0});
      expect((req.url.queryParameters['text'], req.url.queryParameters['pageNo'], req.url.queryParameters['pageSize']), ('知我', '1', '30'));
      expect((r.total, r.hasMore, r.songs.length), (88, true, 2));
      final a = r.songs[0];
      expect(a.id, 'mg:69910406417');
      expect((a.title, a.artist, a.album, a.duration), ('知我', '国风堂 / 哦漏', '知我', 283));
      expect(a.cover, 'https://d.musicapp.migu.cn/prod/file-service/file-down/x.jpg');
      expect(a.qualities, ['128k', '320k', 'flac', 'hires']);
      expect(a.qualityDetails, {
        '128k': {'size': 4530000},
        '320k': {'size': 11320000},
        'flac': {'size': 31310000},
        'hires': {'size': 61310000},
      });
      expect(a.identity, {'songId': '1135447830', 'albumId': '1139904', 'contentId': '600929000006296036', 'copyrightId': '69910406417'});
      final b = r.songs[1];
      expect((b.nativeId, b.title, b.artist, b.cover), ('c2', 'n2', 'S', 'https://d.musicapp.migu.cn/prod/y.jpg'));
      expect(b.qualities, ['128k']);
      expect(b.identity, {'songId': 'c2', 'albumId': '', 'contentId': 'c2', 'copyrightId': 'c2'});
    });

    test('search playlist', () async {
      final calls = <http.Request>[];
      final r = await fake({'searchAll': mgPlaylistSearch}, calls).search('知我', SearchType.playlist);
      expect(jsonDecode(calls.single.url.queryParameters['searchSwitch']!)['songlist'], 1);
      expect((r.total, r.hasMore), (12, false));
      final a = r.items.single;
      expect((a.id, a.type, a.title, a.subtitle, a.cover, a.playCount), ('191', CatalogType.playlist, '知我古风', '咪咕', 'https://d.musicapp.migu.cn/x.jpg', 98765));
    });

    test('search error code throws', () async {
      expect(() => fake({'searchAll': '{"code":"100001","info":"签名错误"}'}).search('x', SearchType.song), throwsA(isA<PlatformException>().having((e) => e.message, 'message', '签名错误')));
    });

    test('suggest is empty, hotSearch filters song words', () async {
      final calls = <http.Request>[];
      final p = fake({'search/hotword': mgHot}, calls);
      expect(await p.suggest('知我'), isEmpty);
      expect(await p.hotSearch(), ['知我', '晴天']);
      expect(calls.single.url.port, 7090);
    });

    test('playlistCategories', () async {
      final cats = await fake({'musiclistplaza-taglist': mgTags}).playlistCategories();
      expect(cats.map((c) => (c.id, c.name, c.group)), [('recommend', '推荐', ''), ('全部', '全部', '默认'), ('1000587673', '流行', '热门'), ('1000093951', '古风', '热门')]);
    });

    test('playlists: recursive collectMiguPlaylists', () async {
      final calls = <http.Request>[];
      final p = fake({'playlist-square-recommend': mgSquare, 'musiclistplaza-listbytag': mgSquare}, calls);
      final r = await p.playlists();
      expect(r.items.map((e) => (e.id, e.title, e.cover, e.playCount)), [
        ('228114498', '古风歌单', 'https://d.musicapp.migu.cn/prod/x.jpg', '12.3万'),
        ('555', 't2', 'https://d.musicapp.migu.cn/z.jpg', 321),
      ]);
      expect((r.total, r.hasMore), (2, false));
      await p.playlists(category: '1000587673', page: 2);
      expect((calls.last.url.queryParameters['tagId'], calls.last.url.queryParameters['pageNumber']), ('1000587673', '2'));
      expect((await p.playlists(limit: 1)).items.length, 1);
      await p.playlists(category: 'recommend');
      expect(calls.last.url.path, contains('playlist-square-recommend'));
    });

    test('leaderboards: recursive collectMiguBoards with dedupe', () async {
      final boards = await fake({'rank-index': mgRank}).leaderboards();
      expect(boards.map((b) => (b.id, b.title, b.subtitle, b.type, b.cover)), [
        ('27553319', '尖叫新歌榜', '咪咕音乐实时榜单', CatalogType.leaderboard, 'https://d.musicapp.migu.cn/x.png'),
        ('27186466', '热歌榜', '咪咕音乐实时榜单', CatalogType.leaderboard, 'https://d.musicapp.migu.cn/h.png'),
      ]);
    });

    test('collection playlist: info + songs', () async {
      final calls = <http.Request>[];
      final c = await fake({'playlist/song/v2.0': mgPlSongs, 'playlist/v2.0': mgPlInfo}, calls).collection(CatalogType.playlist, '228114498', limit: 20);
      expect(calls.length, 2);
      expect(calls.firstWhere((r) => r.url.path.contains('/song/')).url.queryParameters['pageSize'], '20');
      expect((c.title, c.description, c.cover, c.creator), ('古风', '简介', 'https://d.musicapp.migu.cn/y.jpg', '咪咕'));
      expect((c.total, c.limit, c.hasMore), (60, 20, true));
      final t = c.tracks.single;
      expect((t.nativeId, t.title, t.artist, t.album, t.duration, t.cover), ('69910406417', '知我', '国风堂', '知我', 283, 'https://d.musicapp.migu.cn/a.jpg'));
      expect(t.qualityDetails, {
        '128k': {'size': 100},
      });
    });

    test('collection leaderboard: local paging', () async {
      final p = fake({'querycontentbyId': mgBoard});
      final c = await p.collection(CatalogType.leaderboard, '27553319', limit: 2);
      expect((c.title, c.total, c.hasMore), ('咪咕榜单 27553319', 3, true));
      expect(c.tracks.map((t) => (t.nativeId, t.title, t.artist, t.duration)), [('c1', 's1', 'A', 241), ('c2', 's2', 'B', 0)]);
      expect(c.tracks[0].cover, 'https://d.musicapp.migu.cn/b.jpg');
      final c2 = await p.collection(CatalogType.leaderboard, '27553319', page: 2, limit: 2);
      expect(c2.tracks.map((t) => t.nativeId), ['3']);
      expect(c2.hasMore, isFalse);
      expect(() => fake({'querycontentbyId': '{"code":"999"}'}).collection(CatalogType.leaderboard, '1'), throwsA(isA<PlatformException>()));
      expect(() => p.collection(CatalogType.artist, '1'), throwsA(isA<PlatformException>()));
    });

    test('lyric: resourceinfo → MRC decode + translation', () async {
      final calls = <http.Request>[];
      const track = PTrack(platform: 'mg', nativeId: '69910406417', title: '知我', artist: '国风堂', identity: {'copyrightId': '69910406417', 'contentId': '600929000006296036'});
      final l = await fake({'resourceinfo.do': mgResource, 'x.mrc': mgMrcHex, 'x.trc': mgTrc}, calls).lyric(track);
      final info = calls.first;
      expect(info.method, 'POST');
      expect(info.body, 'resourceId=69910406417');
      expect(calls.where((r) => r.url.path.endsWith('.mrc')).single.headers['channel'], '0146921');
      // 桌面端 lyric 是 "[ti:知我]\n[0,3000]知我\n[3000,2000]Hello World"（毫秒行头），这里转成标准 LRC
      expect(l.lrc, '[ti:知我]\n[00:00.000]知我\n[00:03.000]Hello World');
      expect(l.translation, mgTrc);
      expect(l.words!.length, 2);
    });

    test('lyric: LRC fallback when no mrcUrl', () async {
      const track = PTrack(platform: 'mg', nativeId: '1', title: 't', artist: 'a', identity: {'copyrightId': '1'});
      final l = await fake({'resourceinfo.do': '{"resource":[{"lrcUrl":"https://d.musicapp.migu.cn/y.lrc"}]}', 'y.lrc': '[00:01.00]hi'}).lyric(track);
      expect((l.lrc, l.translation, l.words), ('[00:01.00]hi', null, null));
      expect(() => fake({'resourceinfo.do': '{"resource":[]}'}).lyric(track), throwsA(isA<PlatformException>()));
    });
  });
}

// ───────── 固定样本（形状对齐真实响应） ─────────
const mgSong = r'''{"code":"000000","info":"成功","songResultData":{"totalCount":"88","resultList":[[{"id":"1135447830","contentId":"600929000006296036","copyrightId":"69910406417","name":"知我","singerList":[{"id":"1","name":"国风堂"},{"id":"2","name":"哦漏"}],"albumName":"知我","albumId":"1139904","duration":283,"imgItems":[{"imgSizeType":"03","img":"http://d.musicapp.migu.cn/prod/file-service/file-down/x.jpg"}],"audioFormats":[{"formatType":"PQ","asize":"4530000"},{"formatType":"HQ","asize":"11320000"},{"formatType":"SQ","asize":"31310000"},{"formatType":"ZQ24","asize":"61310000"}]}],[{"copyrightId":"c2","name":"n2","singerName":"S","imgItems":[{"img":"/prod/y.jpg"}]}]]}}''';
const mgPlaylistSearch = r'''{"code":"000000","songListResultData":{"totalCount":"12","result":[{"id":"191","name":"知我古风","userName":"咪咕","musicListPicUrl":"http://d.musicapp.migu.cn/x.jpg","playNum":"98765"}]}}''';
const mgHot = r'''{"data":{"hotwords":[{"hotwordList":[{"word":"知我","resourceType":"song"},{"word":"x","resourceType":"singer"}]},{"hotwordList":[{"word":"晴天","resourceType":"song"}]}]}}''';
const mgTags = r'''{"data":[{"title":"热门","content":[{"texts":["流行","1000587673"]},{"texts":["古风","1000093951"]}]},{"name":"场景","content":[{"texts":["","x"]}]}]}''';
const mgSquare = r'''{"data":{"contents":[{"contents":[{"resType":"2021","resId":"228114498","txt":"古风歌单","img":"/prod/x.jpg","barList":[{"title":"12.3万"}]},{"resType":"2022","resId":"x"},{"logEvent":{"contentType":"2021","contentId":"555"},"title":"t2","imageUrl":"//d.musicapp.migu.cn/z.jpg","barList":[{"title":"321"}]}]}]}}''';
const mgRank = r'''{"data":{"contentItemList":[{"itemList":[{"rankId":"27553319","rankName":"尖叫新歌榜","imageUrl":"//d.musicapp.migu.cn/x.png"},{"rankId":"27553319","rankName":"dup"}]},{"contents":[{"rankId":"27186466","rankName":"热歌榜","imageUrl":"https://d.musicapp.migu.cn/h.png"}]}]}}''';
const mgPlInfo = r'''{"data":{"title":"古风","summary":"简介","imgItem":{"img":"https://d.musicapp.migu.cn/y.jpg"},"ownerName":"咪咕"}}''';
const mgPlSongs = r'''{"data":{"totalCount":60,"songList":[{"songId":"1135447830","contentId":"600929000006296036","copyrightId":"69910406417","songName":"知我","singerList":[{"name":"国风堂"}],"album":"知我","duration":"283","albumImgs":[{"img":"https://d.musicapp.migu.cn/a.jpg"}],"newRateFormats":[{"formatType":"PQ","size":"100"}]}]}}''';
const mgBoard = r'''{"code":"000000","columnInfo":{"contents":[{"objectInfo":{"songId":"1","copyrightId":"c1","contentId":"ct1","songName":"s1","singerName":"A","album":"al","length":"04:01","albumImgs":[{"img":"https://d.musicapp.migu.cn/b.jpg"}]}},{"objectInfo":{"songId":"2","copyrightId":"c2","songName":"s2","singerName":"B"}},{"objectInfo":{"songId":"3","songName":"s3"}}]}}''';
const mgResource = r'''{"resource":[{"mrcUrl":"https://d.musicapp.migu.cn/x.mrc","lrcUrl":"https://d.musicapp.migu.cn/x.lrc","trcUrl":"https://d.musicapp.migu.cn/x.trc"}]}''';
const mgMrcHex = 'E7229B431CDA2EC7A58E04C8082F3EE967B93A41A991BD59BB76F83068C7A85CB1983E8FACEFAB71EF84BE298B440FBD79078C378DC1A314189D48BDA1DA23897AF9AB77E226DFBE9C4B2596E00A67A619911678DC6C95B95837EF373753C8AC07F7CAA1FC52B338EA9713C9E10DAD6680196C38DA747AB8C9820D544657D5D36D3AADA167D3229ABF71E311BAB03D400263E2E3AEEA55F56E5CF60377D635A0';
const mgTrc = "[00:00.00]Know me\n[00:03.00]Hello World";
