// 酷我平台离线测试：加密向量由 Node 跑桌面端原始 JS（platform-crypto.ts）得到；
// 规范化用接近真实响应的 JSON 走公开方法，期望值与桌面端 PlatformService 在同样输入下的输出对齐（偏差处有注释）。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/crypto_util.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/kuwo.dart';
import 'package:lyra/platform/models.dart';

/// 按 URL 子串路由的假平台；值是 String（UTF-8）或 List<int>。
KuwoPlatform fake(Map<String, Object> routes, [List<http.Request>? calls]) => KuwoPlatform(PlatformHttp(
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

String localDate(int seconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  group('crypto vectors (node)', () {
    test('kuwoBoardParams', () {
      expect(kuwoBoardParams('93', 1, 20, time: 1700000000000),
          'data=WkMIYYRh9KUzeRRawjXXaoMHen4RKh1V8Fy%2BlzIzNADTo666ORiMDeHjlF3tGF1DepboQy7YV9oPoe2hryX1o7hmVXa4ujFXpqu5jktJwVK3WTe8ueldViwbQG5VjKWlpXwLzByjOVdZyaNRJv4Q8gXL13wm9%2FT8WlIYYzxXlke6e%2Brvh3prkYagIdaBMToF&time=1700000000000&appId=y67sprxhhpws&sign=F911E138BD904E03FD4E72F2ABEC39A4');
      expect(kuwoBoardParams('17', 3, 100, time: 1700000000000),
          'data=WkMIYYRh9KUzeRRawjXXaoMHen4RKh1V8Fy%2BlzIzNADTo666ORiMDeHjlF3tGF1DepboQy7YV9oPoe2hryX1o7hmVXa4ujFXpqu5jktJwVK3WTe8ueldViwbQG5VjKWlpXwLzByjOVdZyaNRJv4Q8qGo2ns6cKak8UgE7QzjdipUKWavA4WIWz0nJvDyuZXc&time=1700000000000&appId=y67sprxhhpws&sign=C3F1286DCD72A761C57057EA2371D5F1');
    });

    test('buildKuwoLyricParams', () {
      expect(buildKuwoLyricParams('228908'), 'DBYAHlReXEpRUEAeCgxVEgAORRgLG0MXCRgaCwoRAB5UAwEaBAkEBhwaXxcAHVReSAsMAVEkOj0wJjpeW1dXSV1DABsMFkRU');
    });

    test('kuwoDecode decrypts bang_info body', () {
      final data = kuwoDecode(kwBangBody) as Map;
      expect(data['code'], 200);
      expect((data['data'] as Map)['total'], '300');
      // URL 编码过的 body 也能解
      expect((kuwoDecode(Uri.encodeComponent(kwBangBody)) as Map)['code'], 200);
      expect(() => kuwoDecode('not-base64!'), throwsA(isA<PlatformException>()));
    });

    test('parseKuwoObject (single-quote JSON)', () {
      expect(parseKuwoObject(kwPlaylistSearch), {
        'TOTAL': '35',
        'abslist': [
          {'playlistid': '2891238463', 'name': '知我 古风', 'nickname': 'kuwo用户', 'pic': 'http://img1.kwcdn.kuwo.cn/star/userpl2015/41/1/1/1.jpg', 'playcnt': '1205678', 'songnum': '30'},
          {'playlistid': '77', 'name': 'b', 'nickname': '', 'pic': '', 'playcnt': '0'},
        ],
      });
    });

    test('gb18030Decode', () {
      expect(gb18030Decode([0xC4, 0xE3, 0xBA, 0xC3, 0x41, 0x81, 0x30, 0x81, 0x30, 0x90, 0x30, 0x81, 0x30, 0x80, 0xFF]), '你好A\u0080\u{10000}€\uFFFD');
    });
  });

  group('normalize', () {
    test('kuwoImage', () {
      expect(kuwoImage('120/s4s73/27/2735573711.jpg'), 'https://img1.kuwo.cn/star/albumcover/500/s4s73/27/2735573711.jpg');
      expect(kuwoImage('http://img2.kuwo.cn/120/a.jpg'), 'http://img2.kuwo.cn/star/albumcover/500/a.jpg');
      expect(kuwoImage('//img1.kwcdn.kuwo.cn/star/albumcover/120/x.jpg'), 'https://img1.kwcdn.kuwo.cn/star/albumcover/500/x.jpg');
      expect(kuwoImage(''), isNull);
      expect(kuwoImage(12), isNull);
    });

    test('quality details from N_MINFO', () {
      final d = kuwoQualityDetails({'N_MINFO': 'level:ff,bitrate:2000,format:flac,size:31.31Mb;level:p,bitrate:320,format:mp3;level:x,bitrate:999,size:1Mb'});
      expect(d, {
        'flac': {'size': (31.31 * 1024 * 1024).round()},
        '320k': <String, dynamic>{},
      });
      expect(kuwoQualities({'n_minfo': 'bitrate:4000,size:1Mb;bitrate:128,size:2Mb'}), ['128k', 'hires']);
    });
  });

  group('KuwoPlatform', () {
    test('search song: uppercase fields, MUSIC_ prefix, html strip', () async {
      final calls = <http.Request>[];
      final r = await fake({'ft=music': kwSong}, calls).search(' 知我 ', SearchType.song);
      expect(calls.single.url.queryParameters['all'], '知我');
      expect(calls.single.url.queryParameters['pn'], '0');
      expect(calls.single.headers['Referer'], 'https://www.kuwo.cn/');
      expect(r.total, 120);
      expect(r.hasMore, isTrue);
      expect(r.songs.length, 2); // MUSICRID 为空的条目被丢弃
      final a = r.songs[0];
      expect(a.id, 'kw:228908');
      expect((a.title, a.artist, a.album), ('知我', '国风堂&哦漏', '知我'));
      expect(a.duration, 283); // 桌面端这里是 0（没读大写 DURATION），移动端补上
      expect(a.cover, 'https://img1.kuwo.cn/star/albumcover/500/s4s73/27/2735573711.jpg');
      expect(a.qualities, ['128k', '320k', 'flac']);
      expect(a.identity, {'id': '228908'});
      expect((a.qualityDetails['128k'] as Map)['size'], (4.32 * 1024 * 1024).round());
      final b = r.songs[1];
      expect((b.nativeId, b.title, b.cover, b.duration), ('1001', '知我(Live)', null, 0));
      expect(b.qualities, ['128k']);
    });

    test('search playlist: single-quote JSON', () async {
      final r = await fake({'ft=playlist': kwPlaylistSearch}).search('知我', SearchType.playlist);
      expect(r.total, 35);
      expect(r.hasMore, isTrue);
      expect(r.items.map((e) => e.id), ['2891238463', '77']);
      final a = r.items[0];
      expect((a.type, a.title, a.subtitle, a.cover, a.playCount), (CatalogType.playlist, '知我 古风', 'kuwo用户', 'http://img1.kwcdn.kuwo.cn/star/userpl2015/41/1/1/1.jpg', 1205678));
      expect(r.items[1].cover, isNull);
      expect(r.items[1].playCount, isNull);
    });

    test('search: empty keyword / unsupported type', () async {
      final calls = <http.Request>[];
      final p = fake({}, calls);
      expect((await p.search('  ', SearchType.song)).songs, isEmpty);
      expect((await p.search('x', SearchType.album)).items, isEmpty);
      expect(calls, isEmpty);
    });

    test('suggest & hotSearch', () async {
      final calls = <http.Request>[];
      final p = fake({'tips.kuwo.cn': kwSuggest, 'hotword.kuwo.cn': kwHot}, calls);
      expect(await p.suggest('知我'), ['知我', '知我 国风堂']);
      expect(await p.hotSearch(), ['知我', '晴天']);
      expect(calls.last.headers['User-Agent'], 'Dalvik/2.1.0 (Linux; U; Android 9;)');
      expect(await p.suggest(' '), isEmpty);
    });

    test('playlistCategories', () async {
      final cats = await fake({'getTagList': kwTags}).playlistCategories();
      expect(cats.map((c) => (c.id, c.name, c.group)), [('new::', '最新', '排序'), ('hot::', '最热', '排序'), ('全部', '全部', '默认'), ('146-10000', '伤感', '心情'), ('62-10000', '放松', '心情'), ('1848-43', '翻唱', '热门')]);
    });

    test('playlists: recommend / tag / grouped', () async {
      final calls = <http.Request>[];
      final p = fake({
        'getRcmPlayList': kwRcm,
        'getTagPlayList': kwRcm,
        'mobileinterfaces.kuwo.cn': r'''[{"list":[{"id":"1","name":"x","uname":"u","img":"","listencnt":"5","total":"3"}]},{"list":[]}]''',
      }, calls);
      final rcm = await p.playlists();
      expect(calls.last.url.queryParameters['order'], 'hot');
      expect(rcm.total, 1000);
      expect(rcm.hasMore, isTrue);
      expect(rcm.items.length, 1); // id 为空的被丢弃
      final a = rcm.items.single;
      expect((a.id, a.title, a.subtitle, a.creator, a.playCount, a.trackCount), ('3467195003', '古风', '酷我', '酷我', 12345678, 50));
      expect(a.cover, 'http://img1.kwcdn.kuwo.cn/star/userpl2015/1/1/1_150.jpg');
      expect(a.date, localDate(1700000000));

      await p.playlists(category: 'new');
      expect(calls.last.url.queryParameters['order'], 'new');
      await p.playlists(category: 'new::');
      expect(calls.last.url.queryParameters['order'], 'new');
      await p.playlists(category: '全部');
      expect(calls.last.url.queryParameters['order'], 'hot');

      await p.playlists(category: '146-10000', page: 2, limit: 10);
      expect(calls.last.url.path, contains('getTagPlayList'));
      expect((calls.last.url.queryParameters['id'], calls.last.url.queryParameters['pn'], calls.last.url.queryParameters['rn']), ('146', '2', '10'));

      final grouped = await p.playlists(category: '1848-43');
      expect(calls.last.url.queryParameters['id'], '1848');
      expect(grouped.items.map((e) => (e.id, e.playCount, e.trackCount, e.cover)), [('1', 5, 3, null)]);
      expect(grouped.hasMore, isFalse);
    });

    test('leaderboards: collectKuwoBoards', () async {
      final boards = await fake({'qukudata.kuwo.cn': kwTree}).leaderboards();
      expect(boards.map((b) => (b.id, b.title, b.subtitle, b.type)), [('93', '酷我飙升榜', '每日更新', CatalogType.leaderboard), ('17', '酷我新歌榜', '酷我音乐实时榜单', CatalogType.leaderboard)]);
      expect(boards[0].cover, 'https://img1.kwcdn.kuwo.cn/star/upload/2/2/1.png');
      expect(boards[1].cover, 'https://img1.kuwo.cn/star/albumcover/500/a/b.jpg');
    });

    test('collection playlist', () async {
      final calls = <http.Request>[];
      final c = await fake({'nplserver.kuwo.cn': kwPl}, calls).collection(CatalogType.playlist, '3467195003', limit: 20);
      expect((calls.single.url.queryParameters['pid'], calls.single.url.queryParameters['pn'], calls.single.url.queryParameters['rn']), ('3467195003', '0', '20'));
      expect((c.title, c.description, c.creator, c.cover), ('古风', '简介', '酷我', 'http://img1.kwcdn.kuwo.cn/star/userpl2015/x.jpg'));
      expect((c.total, c.hasMore, c.type), (42, true, CatalogType.playlist));
      expect(c.tracks.map((t) => (t.nativeId, t.title, t.artist, t.album, t.duration, t.qualities.join(','))), [
        ('228908', '知我', '国风堂', '知我', 283, '128k'),
        ('5', 'n2', '', 'al', 200, '128k'),
      ]);
    });

    test('collection leaderboard: signed params + encrypted body', () async {
      final calls = <http.Request>[];
      final c = await fake({'bang_info': kwBangBody}, calls).collection(CatalogType.leaderboard, '93', limit: 20);
      final q = calls.single.url.queryParameters;
      expect(q['appId'], 'y67sprxhhpws');
      expect(q['sign'], md5Hex('y67sprxhhpws${q['data']}${q['time']}').toUpperCase());
      final plain = jsonDecode(utf8.decode(aesEcbDecrypt(base64.decode(q['data']!), const [112, 87, 39, 61, 199, 250, 41, 191, 57, 68, 45, 114, 221, 94, 140, 228])));
      expect((plain['id'], plain['pn'], plain['rn']), ('93', 0, 20));
      expect((c.title, c.total, c.hasMore), ('酷我榜单 93', 300, true));
      final t = c.tracks.single;
      expect((t.nativeId, t.duration, t.cover), ('228908', 283, 'https://img1.kwcdn.kuwo.cn/star/albumcover/500/x.jpg'));
      expect(t.qualities, ['320k']);
    });

    test('collection: unsupported type / empty id', () async {
      final p = fake({});
      expect(() => p.collection(CatalogType.album, '1'), throwsA(isA<PlatformException>()));
      expect(() => p.collection(CatalogType.playlist, ' '), throwsA(isA<PlatformException>()));
    });

    test('lyric: inflate + base64 + yeelion XOR + GB18030, translation & word timing', () async {
      final calls = <http.Request>[];
      const track = PTrack(platform: 'kw', nativeId: '228908', title: '知我', artist: '国风堂', identity: {'id': '228908'});
      final l = await fake({'newlyric.kuwo.cn': base64.decode(kwLyricBodyB64)}, calls).lyric(track);
      expect(calls.single.url.toString(), 'http://newlyric.kuwo.cn/newlyric.lrc?DBYAHlReXEpRUEAeCgxVEgAORRgLG0MXCRgaCwoRAB5UAwEaBAkEBhwaXxcAHVReSAsMAVEkOj0wJjpeW1dXSV1DABsMFkRU');
      // 以下与桌面端 lyricKuwo 输出一致
      expect(l.lrc, '[ti:知我]\n[ar:国风堂]\n[kuwo:0410]\n[00:01.00]知我\n[00:03.50]心中\n[00:06.00]结束');
      expect(l.translation, '[ti:知我]\n[ar:国风堂]\n[kuwo:0410]\n[00:01.00]Know me\n[00:03.50]In heart');
      // 桌面端 extended："[00:01.00]<0,3>知<3,319>我\n[00:03.50]<1,1>心<2,37>中\n[00:06.00]<1,1>结束"（行内相对毫秒）
      final w = l.words!;
      expect(w.map((e) => (e.start, e.duration, e.text)), [(1000, 322, '知我'), (3500, 39, '心中'), (6000, 2, '结束')]);
      expect(w[0].words, [(start: 1000, duration: 3, text: '知'), (start: 1003, duration: 319, text: '我')]);
      expect(w[1].words, [(start: 3501, duration: 1, text: '心'), (start: 3502, duration: 37, text: '中')]);
      expect(w[2].words, [(start: 6001, duration: 1, text: '结束')]);
    });

    test('lyric: non-lyric body throws', () async {
      const track = PTrack(platform: 'kw', nativeId: '1', title: 't', artist: 'a');
      expect(() => fake({'newlyric.kuwo.cn': 'tp=none\r\n\r\n'}).lyric(track), throwsA(isA<PlatformException>()));
    });

    test('parseKuwoLyric: plain lrc without [kuwo:] has no words; garbage translation layout throws', () {
      final l = parseKuwoLyric('[ti:a]\n[00:01.00]一\n[00:02.00]二');
      expect(l.lrc, '[ti:a]\n[00:01.00]一\n[00:02.00]二');
      expect(l.translation, isNull);
      expect(l.words, isNull);
      // 每句都被识别成「翻译」且没有逐字标签 → 桌面端判定格式不可用
      final bad = [for (var i = 10; i < 30; i++) '[00:$i.00]a$i', for (var k = 0; k < 8; k++) '[00:${10 + k}.00]b$k'].join('\n');
      expect(() => parseKuwoLyric(bad), throwsA(isA<PlatformException>()));
    });
  });
}

// ───────── 固定样本（形状对齐真实响应） ─────────
const kwSong = r'''{"TOTAL":"120","abslist":[{"MUSICRID":"MUSIC_228908","SONGNAME":"知我","ARTIST":"国风堂&哦漏","ALBUM":"知我","DURATION":"283","N_MINFO":"level:ff,bitrate:2000,format:flac,size:31.31Mb;level:p,bitrate:320,format:mp3,size:10.81Mb;level:h,bitrate:128,format:mp3,size:4.32Mb","web_albumpic_short":"120/s4s73/27/2735573711.jpg","NAME":"知我"},{"MUSICRID":"MUSIC_1001","SONGNAME":"<em>知我</em>(Live)","ARTIST":"A","ALBUM":"","N_MINFO":"","web_albumpic_short":""},{"MUSICRID":"","SONGNAME":"bad"}]}''';
const kwSuggest = r'''{"WORDITEMS":[{"RELWORD":"知我"},{"RELWORD":"知我 国风堂"},{"RELWORD":" 知我 "},{"RELWORD":""}]}''';
const kwHot = r'''{"tagvalue":[{"key":"知我"},{"key":"晴天"},{"key":"知我"}]}''';
const kwTags = r'''{"code":200,"data":[{"name":"心情","id":"1","data":[{"id":"146","digest":"10000","name":"伤感"},{"id":"62","digest":"10000","name":"放松"}]},{"name":"热门","data":[{"id":"1848","digest":"43","name":"翻唱"},{"id":"9","digest":"10000","name":""}]}]}''';
const kwRcm = r'''{"code":200,"data":{"total":1000,"data":[{"id":"3467195003","name":"古风","uname":"酷我","img":"http://img1.kwcdn.kuwo.cn/star/userpl2015/1/1/1_150.jpg","listencnt":12345678,"total":50,"publish_time":"1700000000"},{"id":"","name":"skip"}]}}''';
const kwTree = r'''{"child":[{"name":"排行榜","source":"0","child":[{"name":"酷我飙升榜","source":"1","sourceid":"93","info":"每日更新","pic":"https://img1.kwcdn.kuwo.cn/star/upload/2/2/1.png"},{"name":"酷我新歌榜","source":"1","sourceid":"17","pic":"120/a/b.jpg"},{"name":"x","source":"2","sourceid":"5"},{"name":"y","source":"1","sourceid":""}]}]}''';
const kwPl = r'''{"result":"ok","id":3467195003,"title":"古风","info":"简介","pic":"http://img1.kwcdn.kuwo.cn/star/userpl2015/x.jpg","uname":"酷我","total":42,"musiclist":[{"id":"228908","name":"知我","artist":"国风堂","album":"知我","duration":"283","N_MINFO":"level:h,bitrate:128,format:mp3,size:4.32Mb"},{"id":"5","name":"n2","artist":"","album":"al","songTimeMinutes":"03:20"}]}''';
const kwPlaylistSearch = r"""{'TOTAL':'35','abslist':[{'playlistid':'2891238463','name':'知我 古风','nickname':'kuwo用户','pic':'http://img1.kwcdn.kuwo.cn/star/userpl2015/41/1/1/1.jpg','playcnt':'1205678','songnum':'30'},{'playlistid':'77','name':'b','nickname':'','pic':'','playcnt':'0'}]}""";
const kwBangBody = 'QsrPX+VuDR5X4TJ7Rh3hrodNzp4b745s5NtMQbm1tEQwj92bssTzMDWxEhtn3Jvlf/+vzvpKk0VCqKtYwNfhubXwcjav19PLCKMD6dcP/8JOHN3Y5Kq0T/aJvG9WCBoRbtEpz02HxEu0Hw4c430iQgHQs2f7muisM76NKv9FUGkuvJZSAMxKqoDTaOqXykL5QmKvBctjGNN1TbZKlFgH8SRu5Cd4mMvL5bc85r5B0af0noGXb+JQuJpkv+/awW674lLjg1e+lps8SDCLGmZvIDRnVYj/nuJr2suobu9rEteUsq9iW2/PiKIrcLpGU9Ii3/1AgSIuXTnF8tj6KIishA==';
const kwLyricBodyB64 = 'dHA9Y29udGVudA0KbHJjeD0xDQoNCnicHcxNcoIwAAbQIwmjaF10UYSkQImSkC+BHb9NJdVpC4KevjO+A7zIhCl+V+Sa/G0qWtwDswTreFWff45jTM2NzVFFedkDptAP5tQPr1FAJ8IROuC5dkZA+qG2SwxM29llvbC+zkLeacfP1TbZFd/ZFwClsLzlRG4ksYEemukwp10+p01FX9YKeylQfigMdzmY56ngvY8VyZS77yCN1MTyKbHX+tGW2uWxdMZG5dGFOJIdss+WXvjtZJcS8E7CRcMI64W0WpNenHfHtqLF6z8TBVCn';
