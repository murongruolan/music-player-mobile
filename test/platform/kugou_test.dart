// 酷狗适配器离线测试。签名与 KRC 向量由 Node 直接运行桌面端原函数得到：
// KRC 样本 = 'krc1' + zlib.deflateSync(文本) 再从第 4 字节起按 16 字节表异或、base64；期望值是桌面端 decodeKrc 的输出。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/kugou.dart';
import 'package:lyra/platform/models.dart';

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
http.Response _text(String body) => http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/html; charset=utf-8'});

KugouPlatform _platform(Future<http.Response> Function(http.Request) handler) => KugouPlatform(PlatformHttp(client: MockClient(handler), sleep: (_) async {}, log: (_) {}));

const _krc =
    'a3JjMTjbLOeffLYHQbDeCXJXKWcbC+pBy7ExI8o04Au6iYzIq5EXvOgEYB+rMvf1ZRRN8ziE2ka/X8SvCq6ct/ZVp5aNu54WOH79/VZI2o+QyRU69TtMvYUJdXT7oJq2YTUpaIwM485Jyt7YSidf5w5nC2njU5rOzwvC20GNqpXYhpRT5+OmD/sfOjbe068QJi6hsfl+OA9DpJa6mOrxJL3qK79ShNjoE7XiVVxfKcTP5VVOaSNzzuykWV9+dS0+B2Nn6pFyVgJdypy/HlEPH5zVYn94fgZPZ5E3cZIGp35mEWKvIc8S9Mbv+P32pfFoXnD/HchrLz5i+FvcPbcYeTTacuAjYmE3/RsK5dCwPW3NZtny1WG1eCOOGPObYgT9EGxTha7MGxryerZny76Hhyu807f+UPv33ViEvgXiWvLmue/m';
const _krcExtended = '[ar:歌手]\n[ti:标题]\n[1000,2000]<0,500,0>你<500,500,0>好<1000,1000,0>世界\n[61500,1500]<0,700,0>第二<700,800,0>行\n';

const _infoParams = {
  'appid': '1058',
  'specialid': '0',
  'global_specialid': 'collection_3_1234_5_0',
  'format': 'jsonp',
  'srcappid': '2919',
  'clientver': '20000',
  'clienttime': '1586163242519',
  'mid': '1586163242519',
  'uuid': '1586163242519',
  'dfid': '-',
};

/// song_search_v2 的一行。
Map<String, dynamic> _searchRow({String hash = 'HASH128'}) => {
      'FileHash': hash,
      'SongName': '<em>知我</em>',
      'SingerName': '国风堂、哦漏',
      'AlbumName': '知我',
      'AlbumID': '123',
      'ID': '9988',
      'Duration': 245,
      'Image': 'http://imge.kugou.com/stdmusic/{size}/20200101/x.jpg',
      'FileSize': 3900000,
      'HQFileHash': 'HASH320',
      'HQFileSize': 9800000,
      'SQFileHash': 'HASHFLAC',
      'SQFileSize': 28000000,
      'ResFileHash': '',
      'ResFileSize': 0,
      'Singers': [
        {'id': 1, 'name': '国风堂'},
        {'id': 0, 'name': ''},
      ],
    };

void main() {
  group('签名（node 跑桌面端原函数得到的向量）', () {
    test('kugouWebSignature', () {
      expect(kugouWebSignature(_infoParams), '5fe8183cc621017b833af47ad04757fa');
    });

    test('kugouAndroidSignature', () {
      const params = {'dfid': '-', 'appid': '1005', 'mid': '0', 'clientver': '20109', 'clienttime': '640612895', 'uuid': '-'};
      expect(kugouAndroidSignature(params, '{"ret_info":1,"data":[{"id":"gcid_3z1abc","id_type":2}]}'), '7e8e9ad92ee30e8bd0e98e68bf7793cf');
      expect(kugouAndroidSignature(params), 'ca2c4873ed3443d72e1d91a9dca20111');
    });
  });

  group('KRC', () {
    test('decodeKrc 与桌面端输出一致', () {
      final k = decodeKrc(_krc);
      expect(k.extended, _krcExtended);
      expect(k.lyric, _krcExtended);
      expect(k.translation, '[00:01.000]你好世界\n[01:01.500]第二行');
      expect(k.romanization, '[00:01.000]ni hao\n[01:01.500]di er');
    });

    test('krcToLyric 转标准 LRC + 逐字', () {
      final l = krcToLyric(decodeKrc(_krc));
      expect(l.lrc, '[ar:歌手]\n[ti:标题]\n[00:01.000]你好世界\n[01:01.500]第二行');
      expect(l.translation, '[00:01.000]你好世界\n[01:01.500]第二行');
      expect(l.words, hasLength(2));
      final first = l.words!.first;
      expect((first.start, first.duration, first.text), (1000, 2000, '你好世界'));
      expect(first.words.map((w) => (w.start, w.duration, w.text)).toList(), [(1000, 500, '你'), (1500, 500, '好'), (2000, 1000, '世界')]);
      expect(l.words![1].words.map((w) => w.start).toList(), [61500, 62200]);
    });

    test('坏数据抛 PlatformException', () {
      expect(() => decodeKrc('a3Jj'), throwsA(isA<PlatformException>()));
      expect(() => decodeKrc('a3JjMQAAAAAA'), throwsA(isA<PlatformException>()));
    });
  });

  group('网页内嵌 JSON', () {
    test('括号配对跳过字符串里的括号', () {
      const html = r'''<script>var data = [{"hash":"HC","songname":"知我]\"[","n":[1,2]}]; var specialInfo = {"name":"网页 {歌单}","x":{"y":1}};</script>''';
      final arr = parseEmbeddedJsonArray(html, 'data');
      expect(arr, hasLength(1));
      expect((arr.first as Map)['songname'], '知我]"[');
      expect(parseEmbeddedJsonObject(html, 'specialInfo')!['name'], '网页 {歌单}');
      expect(parseEmbeddedJsonObject(html, 'missing'), isNull);
    });
  });

  group('规范化', () {
    test('normalizeKugou：identity / 音质 hash / 封面 / 标题去 em', () {
      final t = normalizeKugou(_searchRow())!;
      expect(t.id, 'kg:HASH128');
      expect(t.title, '知我');
      expect(t.artist, '国风堂、哦漏');
      expect(t.album, '知我');
      expect(t.duration, 245);
      expect(t.cover, 'http://imge.kugou.com/stdmusic/500/20200101/x.jpg');
      expect(t.qualities, ['128k', '320k', 'flac']);
      expect(t.qualityDetails['320k'], {'size': 9800000});
      expect(t.identity, {
        'hash': 'HASH128',
        'albumId': '123',
        'albumAudioId': '9988',
        'qualityHashes': {'128k': 'HASH128', '320k': 'HASH320', 'flac': 'HASHFLAC'},
      });
      expect(normalizeKugou({'SongName': 'x'}), isNull);
    });

    test('normalizeKugouDetailSong：filename 拆歌手 / 歌名，毫秒时长', () {
      final t = normalizeKugouDetailSong({'hash': 'HA', 'filename': '国风堂 - 知我', 'album_id': '1', 'duration': 245000, 'album_audio_id': 555, '320hash': 'HB', 'trans_param': {'union_cover': 'http://imge.kugou.com/stdmusic/{size}/c.jpg'}})!;
      expect(t.artist, '国风堂');
      expect(t.title, '知我');
      expect(t.duration, 245);
      expect(t.identity['albumAudioId'], '555');
      expect(t.identity['albumId'], '1');
      expect(t.qualities, ['128k', '320k']);
      expect(t.cover, 'http://imge.kugou.com/stdmusic/500/c.jpg');
    });
  });

  group('接口', () {
    test('歌曲搜索：song_search_v2 filter=2', () async {
      late Uri url;
      final p = _platform((req) async {
        url = req.url;
        return _json({
          'error_code': 0,
          'data': {
            'total': 100,
            'lists': [_searchRow(), _searchRow(hash: '')],
          },
        });
      });
      final r = await p.search('知我', SearchType.song, limit: 20);
      expect(url.host, 'songsearch.kugou.com');
      expect(url.queryParameters['filter'], '2');
      expect(url.queryParameters['pagesize'], '20');
      expect(r.songs.single.nativeId, 'HASH128');
      expect(r.total, 100);
      expect(r.hasMore, isTrue);
    });

    test('歌曲搜索 error_code≠0 抛错', () async {
      final p = _platform((req) async => _json({'error_code': 1, 'data': {}}));
      await expectLater(p.search('知我', SearchType.song), throwsA(isA<PlatformException>()));
    });

    test('专辑搜索 filter=4 去重、跳过 AlbumID=0', () async {
      final p = _platform((req) async {
        expect(req.url.queryParameters['filter'], '4');
        return _json({
          'error_code': 0,
          'data': {
            'total': 2,
            'lists': [
              {'AlbumID': '11', 'AlbumName': '知我', 'SingerName': '国风堂', 'Image': 'http://imge.kugou.com/stdmusic/{size}/a.jpg'},
              {'AlbumID': '11', 'AlbumName': '知我', 'SingerName': '国风堂'},
              {'AlbumID': '0', 'AlbumName': '单曲'},
            ],
          },
        });
      });
      final r = await p.search('知我', SearchType.album);
      expect(r.items.single.id, '11');
      expect(r.items.single.type, CatalogType.album);
      expect(r.items.single.cover, 'http://imge.kugou.com/stdmusic/500/a.jpg');
    });

    test('歌手搜索：从歌曲结果收集歌手 id 再查 singer/info', () async {
      final infoIds = <String>[];
      final p = _platform((req) async {
        if (req.url.host == 'songsearch.kugou.com') {
          expect(req.url.queryParameters['pagesize'], '30');
          return _json({
            'error_code': 0,
            'data': {
              'lists': [
                _searchRow(),
                {
                  ..._searchRow(),
                  'Singers': [
                    {'id': 2},
                    {'id': 1},
                  ],
                },
              ],
            },
          });
        }
        final id = req.url.queryParameters['singerid']!;
        infoIds.add(id);
        return _json({
          'data': {'singerid': int.parse(id), 'singername': '歌手$id', 'albumcount': id == '1' ? 3 : 0, 'songcount': 40, 'imgurl': 'http://singerimg.kugou.com/{size}/$id.jpg'},
        });
      });
      final r = await p.search('知我', SearchType.artist, limit: 5);
      expect(infoIds.toSet(), {'1', '2'});
      expect(r.items.map((i) => i.id), ['1', '2']);
      expect(r.items.first.subtitle, '3 张专辑');
      expect(r.items.last.subtitle, '40 首歌曲');
      expect(r.items.first.cover, 'http://singerimg.kugou.com/500/1.jpg');
    });

    test('歌单搜索：msearchretry special', () async {
      final p = _platform((req) async {
        expect(req.url.host, 'msearchretry.kugou.com');
        return _json({
          'data': {
            'total': 1,
            'info': [
              {'specialid': 546, 'specialname': '<em>知我</em>合集', 'nickname': '用户', 'imgurl': 'http://imge.kugou.com/soft/collection/{size}/x.jpg', 'playcount': 999, 'songcount': 12},
            ],
          },
        });
      });
      final item = (await p.search('知我', SearchType.playlist)).items.single;
      expect(item.id, '546');
      expect(item.title, '知我合集');
      expect(item.cover, 'http://imge.kugou.com/soft/collection/500/x.jpg');
      expect(item.playCount, 999);
      expect(item.trackCount, 12);
    });

    test('联想词 / 热搜', () async {
      final p = _platform((req) async {
        if (req.url.host == 'searchtip.kugou.com') {
          return _json({
            'data': [
              {
                'RecordDatas': [
                  {'HintInfo': '知我'},
                  {'HintInfo': '知我 国风堂'},
                ],
              },
            ],
          });
        }
        expect(req.url.queryParameters['signature'], 'ee44edb9d7155821412d220bcaf509dd');
        expect(req.headers['x-router'], 'msearch.kugou.com');
        return _json({
          'data': {
            'list': [
              {
                'keywords': [
                  {'keyword': '晴天'},
                  {'keyword': '知我'},
                ],
              },
              {
                'keywords': [
                  {'keyword': '晴天'},
                ],
              },
            ],
          },
        });
      });
      expect(await p.suggest('知我'), ['知我', '知我 国风堂']);
      expect(await p.hotSearch(), ['晴天', '知我']);
    });

    test('榜单列表只要 isvol=1', () async {
      final p = _platform((req) async => _json({
            'data': {
              'info': [
                {'rankid': 8888, 'rankname': '酷狗TOP500', 'img_9': 'http://imge.kugou.com/mcommon/{size}/x.png', 'isvol': 1},
                {'rankid': 1, 'rankname': '非期刊', 'isvol': 0},
              ],
            },
          }));
      final boards = await p.leaderboards();
      expect(boards.single.id, '8888');
      expect(boards.single.type, CatalogType.leaderboard);
      expect(boards.single.cover, 'http://imge.kugou.com/mcommon/500/x.png');
    });

    test('榜单详情 rank/song', () async {
      final p = _platform((req) async {
        expect(req.url.queryParameters['rankid'], '8888');
        return _json({
          'errcode': 0,
          'data': {
            'total': 500,
            'info': [
              {
                'hash': 'H1',
                'songname': '知我',
                'authors': [
                  {'author_name': '国风堂'},
                  {'author_name': '哦漏'},
                ],
                'remark': '专辑名',
                'duration': 245,
                'album_id': '5',
                'audio_id': 77,
                'filesize': 100,
                '320hash': 'H2',
                '320filesize': 200,
                'sqhash': '',
                'album_sizable_cover': 'http://imge.kugou.com/stdmusic/{size}/y.jpg',
              },
            ],
          },
        });
      });
      final c = await p.collection(CatalogType.leaderboard, '8888', limit: 20);
      final t = c.tracks.single;
      expect(t.artist, '国风堂 / 哦漏');
      expect(t.album, '专辑名');
      expect(t.identity['albumAudioId'], '77');
      expect(t.qualities, ['128k', '320k']);
      expect(t.cover, 'http://imge.kugou.com/stdmusic/500/y.jpg');
      expect(c.total, 500);
      expect(c.hasMore, isTrue);
    });

    test('collection_ 歌单：info_v2 + song_v2（Web 签名，JSONP）', () async {
      final paths = <String>[];
      final p = _platform((req) async {
        paths.add(req.url.path);
        if (req.url.path.endsWith('info_v2')) {
          expect(req.url.queryParameters['signature'], '5fe8183cc621017b833af47ad04757fa');
          expect(req.headers['mid'], '1586163242519');
          expect(req.headers['clienttime'], '1586163242519');
          return _text('jsonp({"status":1,"data":{"specialname":"歌单名","intro":"简介","imgurl":"http://imge.kugou.com/soft/collection/{size}/x.jpg","nickname":"用户","songcount":2}})');
        }
        final q = Map<String, String>.from(req.url.queryParameters)..remove('signature');
        expect(req.url.queryParameters['signature'], kugouWebSignature(q));
        expect(q['pagesize'], '50');
        return _json({
          'data': {
            'total': 2,
            'info': [
              {'hash': 'HA', 'filename': '国风堂 - 知我', 'album_id': '1', 'duration': 245, 'album_audio_id': 555},
              {'hash': 'HB', 'filename': '哦漏 - 知你', 'duration': 200},
            ],
          },
        });
      });
      final c = await p.collection(CatalogType.playlist, 'collection_3_1234_5_0', limit: 50);
      expect(paths.toSet(), {'/api/v5/special/info_v2', '/api/v5/special/song_v2'});
      expect(c.title, '歌单名');
      expect(c.description, '简介');
      expect(c.creator, '用户');
      expect(c.cover, 'http://imge.kugou.com/soft/collection/500/x.jpg');
      expect(c.tracks.map((t) => t.nativeId), ['HA', 'HB']);
      expect(c.tracks.first.artist, '国风堂');
      expect(c.total, 2);
    });

    test('collection_ 歌单：H5 接口无数据时抓网页 var data', () async {
      final p = _platform((req) async {
        if (req.url.host == 'mobiles.kugou.com') return _json({'data': []});
        expect(req.url.toString(), 'https://www.kugou.com/yy/special/single/collection_9.html');
        return _text(r'''<script>var data = [{"hash":"HC","songname":"知我","singername":"歌手","album_name":"A","duration":245000},{"hash":"HD","songname":"二","singername":"歌手"}];
var specialInfo = {"name":"网页歌单","intro":"介绍","image":"http://imge.kugou.com/soft/{size}/a.jpg","nickname":"nick"};</script>''');
      });
      final c = await p.collection(CatalogType.playlist, 'collection_9', limit: 1);
      expect(c.title, '网页歌单');
      expect(c.cover, 'http://imge.kugou.com/soft/500/a.jpg');
      expect(c.tracks.single.nativeId, 'HC');
      expect(c.tracks.single.duration, 245);
      expect(c.total, 2);
      expect(c.hasMore, isTrue);
    });

    test('数字 specialid 歌单：抓 www2 的 global.data', () async {
      final p = _platform((req) async {
        expect(req.url.toString(), 'http://www2.kugou.kugou.com/yueku/v9/special/single/546-5-9999.html');
        return _text('''<script>
global.data = [{"hash":"H9","songname":"知我","singername":"歌手","album_name":"专","duration":245,"album_id":"3","audio_id":"44","trans_param":{"union_cover":"http://imge.kugou.com/stdmusic/{size}/c.jpg"}}];
global = {
  name: "老歌单",
  pic: "http://imge.kugou.com/soft/{size}/p.jpg",
};
</script>''');
      });
      final c = await p.collection(CatalogType.playlist, '546');
      expect(c.title, '老歌单');
      expect(c.cover, 'http://imge.kugou.com/soft/500/p.jpg');
      final t = c.tracks.single;
      expect(t.identity, {
        'hash': 'H9',
        'albumId': '3',
        'albumAudioId': '44',
        'qualityHashes': {'128k': 'H9'},
      });
      expect(t.cover, 'http://imge.kugou.com/stdmusic/500/c.jpg');
    });

    test('专辑详情：album/song + container 专辑信息', () async {
      final p = _platform((req) async {
        if (req.url.host == 'kmrserviceretry.kugou.com') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['data'], [
            {'album_id': '77'},
          ]);
          return _json({
            'data': [
              {'album_name': '知我专辑', 'intro': '<p>介绍</p>', 'sizable_cover': 'http://imge.kugou.com/stdmusic/{size}/al.jpg', 'authors': [
                  {'author_name': '国风堂'},
                  {'author_name': '哦漏'},
                ]},
            ],
          });
        }
        return _json({
          'data': {
            'total': 1,
            'info': [
              {'hash': 'HA', 'filename': '国风堂 - 知我', 'duration': 245},
            ],
          },
        });
      });
      final c = await p.collection(CatalogType.album, '77');
      expect(c.title, '知我专辑');
      expect(c.description, '介绍');
      expect(c.creator, '国风堂 / 哦漏');
      expect(c.cover, 'http://imge.kugou.com/stdmusic/500/al.jpg');
      expect(c.tracks.single.title, '知我');
    });

    test('专辑详情：专辑信息接口失败时用第一首歌兜底', () async {
      final p = _platform((req) async {
        if (req.url.host == 'kmrserviceretry.kugou.com') return http.Response('x', 500);
        return _json({
          'data': {
            'info': [
              {'hash': 'HA', 'filename': '国风堂 - 知我', 'album_name': '兜底专辑', 'duration': 245},
            ],
          },
        });
      });
      final c = await p.collection(CatalogType.album, '77');
      expect(c.title, '兜底专辑');
      expect(c.creator, '国风堂');
      expect(c.total, 1);
    });

    test('歌手详情', () async {
      final p = _platform((req) async {
        if (req.url.path.endsWith('singer/info')) {
          return _json({
            'data': {'singername': '国风堂', 'intro': '<b>简介</b>', 'imgurl': 'http://singerimg.kugou.com/{size}/s.jpg', 'songcount': 80},
          });
        }
        return _json({
          'data': {
            'info': [
              {'hash': 'HA', 'filename': '国风堂 - 知我'},
            ],
          },
        });
      });
      final c = await p.collection(CatalogType.artist, '1');
      expect(c.title, '国风堂');
      expect(c.description, '简介');
      expect(c.cover, 'http://singerimg.kugou.com/500/s.jpg');
      expect(c.total, 80);
      expect(c.hasMore, isFalse);
    });

    test('歌单广场 / 分类', () async {
      final urls = <Uri>[];
      final p = _platform((req) async {
        urls.add(req.url);
        if (req.url.queryParameters['is_smarty'] == '1') {
          return _json({
            'data': {
              'hotTag': {
                'data': {
                  '0': {'special_id': '1001', 'special_name': '热门1'},
                },
              },
              'tagids': {
                '语种': {
                  'data': [
                    {'id': '11', 'name': '华语'},
                  ],
                },
              },
            },
          });
        }
        return _json({
          'special_db': [
            {'specialid': 1, 'specialname': '歌单1', 'nickname': 'a', 'img': 'http://imge.kugou.com/soft/{size}/1.jpg', 'total_play_count': '1.2万', 'song_count': 30, 'publish_time': '2024-05-06 10:00:00'},
            {'specialid': 2, 'specialname': '歌单2', 'nickname': 'b', 'img': '', 'total_play_count': 5, 'song_count': 0},
          ],
        });
      });
      final cats = await p.playlistCategories();
      expect(cats.map((c) => c.id), ['5::', '7::', '6::', '3::', '8::', '全部', '1001', '11']);
      expect(cats.last.group, '语种');
      final page = await p.playlists(category: '6::11', page: 2, limit: 1);
      expect(urls.last.queryParameters['t'], '6');
      expect(urls.last.queryParameters['c'], '11');
      expect(urls.last.queryParameters['p'], '2');
      expect(page.items.single.title, '歌单1');
      expect(page.items.single.playCount, '1.2万');
      expect(page.items.single.trackCount, 30);
      expect(page.items.single.date, '2024-05-06');
      expect(page.hasMore, isTrue);
      await p.playlists();
      expect(urls.last.queryParameters['t'], '5');
      expect(urls.last.queryParameters['c'], '');
    });

    test('歌词：KRC', () async {
      final calls = <Uri>[];
      final p = _platform((req) async {
        calls.add(req.url);
        expect(req.headers['User-Agent'], 'KuGou2012-9020-ExpandSearchManager');
        if (req.url.path == '/search') {
          return _json({
            'status': 200,
            'candidates': [
              {'id': '111', 'accesskey': 'AK', 'krctype': 1, 'contenttype': 0},
            ],
          });
        }
        return _json({'status': 200, 'content': _krc});
      });
      final track = normalizeKugou(_searchRow())!;
      final l = await p.lyric(track);
      expect(calls.first.queryParameters['hash'], 'HASH128');
      expect(calls.first.queryParameters['timelength'], '245000');
      expect(calls.first.queryParameters['keyword'], '知我 - 国风堂、哦漏');
      expect(calls.last.queryParameters['fmt'], 'krc');
      expect(calls.last.queryParameters['accesskey'], 'AK');
      expect(l.lrc, '[ar:歌手]\n[ti:标题]\n[00:01.000]你好世界\n[01:01.500]第二行');
      expect(l.romanization, '[00:01.000]ni hao\n[01:01.500]di er');
      expect(l.words, hasLength(2));
    });

    test('歌词：contenttype=1 时下 base64 LRC；无候选时报错', () async {
      final lrc = base64.encode(utf8.encode('[00:01.00]知我'));
      var empty = false;
      final p = _platform((req) async {
        if (req.url.path == '/search') {
          return _json({
            'candidates': empty
                ? []
                : [
                    {'id': 5, 'accesskey': 'K', 'krctype': 1, 'contenttype': 1},
                  ],
          });
        }
        expect(req.url.queryParameters['fmt'], 'lrc');
        return _json({'content': lrc});
      });
      final track = normalizeKugou(_searchRow())!;
      expect((await p.lyric(track)).lrc, '[00:01.00]知我');
      empty = true;
      await expectLater(p.lyric(track), throwsA(isA<PlatformException>()));
    });
  });
}
