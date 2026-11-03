// QQ 音乐适配器离线测试。加密向量由 Node 直接运行桌面端 platform-crypto.ts / platform-account-crypto.ts 的原函数得到。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/tencent.dart';

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
http.Response _text(String body) => http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/html; charset=utf-8'});

TencentPlatform _platform(Future<http.Response> Function(http.Request) handler) =>
    TencentPlatform(PlatformHttp(client: MockClient(handler), sleep: (_) async {}, log: (_) {}));

/// 形如 client_search_cp new_json=1 / songInfo 的歌曲。
Map<String, dynamic> _song({String mid = '003abcMid', int id = 1234567, String albumMid = 'albumMid9', int interval = 245}) => {
      'id': id,
      'mid': mid,
      'name': '知我',
      'title': '知我',
      'interval': interval,
      'singer': [
        {'id': 1, 'mid': 'singerMid1', 'name': '国风堂'},
        {'id': 2, 'mid': 'singerMid2', 'name': '哦漏'},
      ],
      'album': {'id': 9, 'mid': albumMid, 'name': '知我专辑'},
      'file': {
        'media_mid': 'mediaMid1',
        'size_128mp3': 3920000,
        'size_320mp3': 9800000,
        'size_flac': 28000000,
        'size_hires': 0,
        'size_new': [0, 5000000, 0],
      },
      'mv': {'id': 0, 'vid': 'v00abc'},
    };

// node: Buffer.from(qrcXml).toString('base64')，qrcXml 见 _qrcExpected 上方说明
const _qrcB64 =
    'PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz4KPFFyY0luZm9zPjxMeXJpY0luZm8gTHlyaWNDb3VudD0iMSI+PEx5cmljXzEgTHlyaWNUeXBlPSIxIiBMeXJpY0NvbnRlbnQ9Ilt0aTrnn6XmiJFdClthcjrlm73po47loIJdClswLDUwMF3nn6XmiJEgLSDmrYzmiYsoMCw1MDApClsxMjM0NSwzMDAwXeefpSgxMjM0NSw0MDAp5oiRKDEyNzQ1LDYwMCkgJmFtcDvlv4MoMTMzNDUsNzAwKeWwvuW3tAoiLz48L0x5cmljSW5mbz48L1FyY0luZm9zPg==';
// node: 桌面端 parseTencentQrcLines(extractTencentQrcContent(xml)).lyric
const _qrcExpected = '[ti:知我]\n[ar:国风堂]\n[00:00.000]知我 - 歌手\n[00:12.345]知我 &心尾巴';
// node: Buffer.from('\uFEFF[00:01.00]知我\r\n[00:02.50]第二行').toString('base64')
const _lrcB64 = '77u/WzAwOjAxLjAwXeefpeaIkQ0KWzAwOjAyLjUwXeesrOS6jOihjA==';

void main() {
  group('签名（node 跑桌面端原函数得到的向量）', () {
    test('zzcSign', () {
      expect(zzcSign(''), 'zzcf0e03e5gx4qeiq5cfgdyqwu7sdqfsb5fro3aa45053');
      expect(zzcSign('hello'), 'zzcfa14dde89n1iwax0l5rimr0qwjexceiov4daaee8d6');
      expect(zzcSign('{"comm":{"ct":"11"},"req":{"query":"知我"}}'), 'zzc6a4f282rhpt3pkoqloulo29cstoambqixe27e92440');
      expect(zzcSign('abc' * 50), 'zzc5de100f3sffdhipgcgzo11vrfbobozzg00432f1cc');
    });

    test('hash33', () {
      expect(hash33(''), 0);
      expect(hash33('abc'), 108966);
      expect(hash33('@aBcDeFgHi', 5381), 790753682);
      expect(hash33('知我' * 12, 5381), 489463309);
      expect(hash33('x' * 300), 1107884704);
    });
  });

  group('规范化', () {
    test('normalizeTencent：identity / 音质 / 封面 / 时长', () {
      final t = normalizeTencent(_song())!;
      expect(t.id, 'tx:003abcMid');
      expect(t.nativeId, '003abcMid');
      expect(t.title, '知我');
      expect(t.artist, '国风堂 / 哦漏');
      expect(t.album, '知我专辑');
      expect(t.duration, 245);
      expect(t.cover, 'https://y.gtimg.cn/music/photo_new/T002R500x500M000albumMid9.jpg');
      expect(t.qualities, ['128k', '320k', 'flac', 'atmos']);
      expect(t.qualityDetails['flac'], {'size': 28000000});
      expect(t.identity, {'songId': '1234567', 'songMid': '003abcMid', 'albumMid': 'albumMid9', 'strMediaMid': 'mediaMid1'});
      expect(t.mvId, 'v00abc');
    });

    test('无专辑（albumMid=空）用歌手图；毫秒时长转秒；content 包装', () {
      final t = normalizeTencent({'content': _song(albumMid: '空', interval: 245000)})!;
      expect(t.cover, 'https://y.gtimg.cn/music/photo_new/T001R500x500M000singerMid1.jpg');
      expect(t.duration, 245);
      expect(normalizeTencent({'name': '无 id'}), isNull);
    });

    test('没有音质信息时给 128k', () {
      final t = normalizeTencent({'mid': 'm1', 'name': 'x'})!;
      expect(t.qualities, ['128k']);
      expect(t.identity['songId'], 'm1');
      expect(t.cover, isNull);
    });
  });

  group('接口', () {
    test('歌曲搜索走 client_search_cp', () async {
      late Uri url;
      final p = _platform((req) async {
        url = req.url;
        return _json({
          'code': 0,
          'data': {
            'song': {
              'list': [_song(), _song(mid: '', id: 0)],
              'totalnum': 300,
            },
          },
        });
      });
      final r = await p.search('  知我 ', SearchType.song);
      expect(url.host, 'c.y.qq.com');
      expect(url.path, '/soso/fcgi-bin/client_search_cp');
      expect(url.queryParameters['w'], '知我');
      expect(url.queryParameters['t'], '0');
      expect(r.songs, hasLength(1));
      expect(r.songs.first.nativeId, '003abcMid');
      expect(r.total, 300);
      expect(r.hasMore, isTrue);
    });

    test('专辑 / 歌手 / MV 搜索', () async {
      final p = _platform((req) async {
        final t = req.url.queryParameters['t'];
        if (t == '8') {
          return _json({
            'data': {
              'album': {
                'list': [
                  {'albumMID': 'alb1', 'albumName': '知我', 'singerName': '国风堂', 'albumPic': ''},
                ],
                'totalnum': 1,
              },
            },
          });
        }
        if (t == '9') {
          return _json({
            'data': {
              'singer': {
                'list': [
                  {'singerMID': 'sg1', 'singerName': '<em>国风堂</em>', 'songNum': 88, 'singerPic': 'http://y.gtimg.cn/s.jpg'},
                ],
                'totalnum': 1,
              },
            },
          });
        }
        return _json({
          'data': {
            'mv': {
              'list': [
                {'vid': 'v1', 'title': '知我 MV', 'singer_name': '国风堂', 'picurl': 'http://puui.qpic.cn/x.jpg'},
              ],
              'totalnum': 1,
            },
          },
        });
      });
      final album = (await p.search('知我', SearchType.album)).items.single;
      expect(album.type, CatalogType.album);
      expect(album.id, 'alb1');
      expect(album.subtitle, '国风堂');
      expect(album.cover, 'https://y.gtimg.cn/music/photo_new/T002R500x500M000alb1.jpg');
      final artist = (await p.search('知我', SearchType.artist)).items.single;
      expect(artist.type, CatalogType.artist);
      expect(artist.title, '国风堂');
      expect(artist.subtitle, '88 首歌曲');
      expect(artist.cover, 'http://y.gtimg.cn/s.jpg');
      final mv = (await p.search('知我', SearchType.mv)).songs.single;
      expect(mv.mvId, 'v1');
      expect(mv.artist, '国风堂');
    });

    test('歌单搜索：musics.fcg + zzcSign(请求体)', () async {
      final calls = <http.Request>[];
      final p = _platform((req) async {
        calls.add(req);
        return _json({
          'code': 0,
          'req': {
            'code': 0,
            'data': {
              'body': {
                'item_songlist': [
                  {'dissid': '7001', 'dissname': '<em>知我</em>歌单', 'nickname': '用户', 'logo': 'http://p.qpic.cn/x.jpg', 'listennum': 12345, 'song_count': 20},
                ],
                'meta': {'estimate_sum': 50},
              },
            },
          },
        });
      });
      final r = await p.search('知我', SearchType.playlist, limit: 10);
      expect(calls, hasLength(1));
      final req = calls.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/cgi-bin/musics.fcg');
      expect(req.url.queryParameters['sign'], zzcSign(req.body));
      expect(req.headers['User-Agent'], 'QQMusic 14090508(android 12)');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['comm']['ct'], '11');
      expect(body['comm']['rom'], 'HuaWei/EMOTION/EmotionUI_14.2.0');
      expect(body['req']['param']['query'], '知我');
      expect(body['req']['param']['search_type'], 3);
      expect(body['req']['param']['num_per_page'], 10);
      final item = r.items.single;
      expect(item.type, CatalogType.playlist);
      expect(item.id, '7001');
      expect(item.title, '知我歌单');
      expect(item.playCount, 12345);
      expect(item.trackCount, 20);
      expect(r.total, 50);
    });

    test('歌单搜索：签名接口报错时退回 musicu.fcg?data=', () async {
      final calls = <http.Request>[];
      final p = _platform((req) async {
        calls.add(req);
        if (req.url.path.endsWith('musics.fcg')) {
          return _json({
            'code': 2001,
            'req': {'code': -1},
          });
        }
        final data = jsonDecode(req.url.queryParameters['data']!) as Map<String, dynamic>;
        expect(data['req_0']['method'], 'DoSearchForQQMusicMobile');
        return _json({
          'code': 0,
          'req_0': {
            'code': 0,
            'data': {
              'body': {
                'item_songlist': [
                  {'dissid': '8', 'dissname': '老接口歌单', 'nickname': 'n', 'logo': ''},
                ],
                'meta': {'estimate_sum': 1},
              },
            },
          },
        });
      });
      final r = await p.search('知我', SearchType.playlist);
      expect(calls.map((c) => c.url.path), ['/cgi-bin/musics.fcg', '/cgi-bin/musicu.fcg']);
      expect(calls[1].method, 'GET');
      expect(r.items.single.title, '老接口歌单');
    });

    test('联想词', () async {
      final p = _platform((req) async => _json({
            'code': 0,
            'data': {
              'song': {
                'itemlist': [
                  {'name': '知我', 'singer': '国风堂'},
                  {'name': '知我', 'singer': '国风堂'},
                  {'name': '知否', 'singer': ''},
                ],
              },
            },
          }));
      expect(await p.suggest('知'), ['知我 - 国风堂', '知否']);
    });

    test('热搜；失败时返回空列表', () async {
      final ok = _platform((req) async => _json({
            'hotkey': {
              'data': {
                'vec_hotkey': [
                  {'query': '知我'},
                  {'query': ' '},
                  {'query': '晴天'},
                ],
              },
            },
          }));
      expect(await ok.hotSearch(), ['知我', '晴天']);
      final bad = _platform((req) async => http.Response('nope', 500));
      expect(await bad.hotSearch(), isEmpty);
    });

    test('榜单列表：过滤 201 / 隐藏 id / 隐藏名字，去掉「巅峰榜·」', () async {
      final p = _platform((req) async => _json({
            'code': 0,
            'data': {
              'topList': [
                {'id': 4, 'topTitle': '巅峰榜·流行指数', 'picUrl': 'http://y.gtimg.cn/music/photo_new/T003.jpg'},
                {'id': 201, 'topTitle': 'MV 榜'},
                {'id': 64, 'topTitle': '隐藏'},
                {'id': 99, 'topTitle': '国风热歌榜'},
              ],
            },
          }));
      final boards = await p.leaderboards();
      expect(boards, hasLength(1));
      expect(boards.single.id, '4');
      expect(boards.single.type, CatalogType.leaderboard);
      expect(boards.single.title, '流行指数');
      expect(boards.single.cover, 'http://y.gtimg.cn/music/photo_new/T003.jpg');
    });

    test('歌单广场：默认走 PlayListPlazaServer，标签走 PlayListCategoryServer', () async {
      final payloads = <Map<String, dynamic>>[];
      final p = _platform((req) async {
        final payload = jsonDecode(req.url.queryParameters['data']!) as Map<String, dynamic>;
        payloads.add(payload);
        final row = {
          'tid': 9001,
          'title': '歌单 A',
          'creator_info': {'nick': '小明'},
          'cover_url_medium': 'http://qpic.y.qq.com/a.jpg',
          'access_num': 98765,
          'song_ids': [1, 2, 3],
          'modify_time': 1700000000,
        };
        if (payload['playlist']['module'] == 'playlist.PlayListPlazaServer') {
          return _json({
            'playlist': {
              'data': {
                'v_playlist': [row],
                'total': 100,
              },
            },
          });
        }
        return _json({
          'playlist': {
            'data': {
              'content': {
                'v_item': [
                  {'basic': row},
                ],
              },
              'total_cnt': 1,
            },
          },
        });
      });
      final hot = await p.playlists(limit: 1);
      expect(payloads.last['playlist']['param']['order'], 5);
      expect(hot.items.single.id, '9001');
      expect(hot.items.single.creator, '小明');
      expect(hot.items.single.playCount, 98765);
      expect(hot.items.single.trackCount, 3);
      expect(hot.items.single.date, isNotNull);
      expect(hot.hasMore, isTrue);
      final latest = await p.playlists(category: '2::', limit: 30);
      expect(payloads.last['playlist']['param']['order'], 2);
      expect(latest.items, hasLength(1));
      final tagged = await p.playlists(category: '6', page: 2, limit: 30);
      expect(payloads.last['playlist']['module'], 'playlist.PlayListCategoryServer');
      expect(payloads.last['playlist']['param']['category_id'], 6);
      expect(payloads.last['playlist']['param']['page'], 1);
      expect(tagged.items.single.title, '歌单 A');
    });

    test('歌单分类', () async {
      final p = _platform((req) async => _json({
            'tags': {
              'data': {
                'v_group': [
                  {
                    'group_name': '语种',
                    'v_item': [
                      {'id': 165, 'name': '国语'},
                      {'id': 0, 'name': ''},
                    ],
                  },
                ],
              },
            },
          }));
      final cats = await p.playlistCategories();
      expect(cats.map((c) => c.id), ['2::', '5::', '全部', '165']);
      expect(cats.last.group, '语种');
    });

    test('歌单详情：本地分页', () async {
      late Uri url;
      final p = _platform((req) async {
        url = req.url;
        return _json({
          'code': 0,
          'cdlist': [
            {
              'dissname': '我的歌单',
              'desc': '简介',
              'logo': 'http://qpic.y.qq.com/logo.jpg',
              'nickname': '小明',
              'total_song_num': 2,
              'songlist': [_song(), _song(mid: '002second')],
            },
          ],
        });
      });
      final c = await p.collection(CatalogType.playlist, ' 7001 ', limit: 1, page: 2);
      expect(url.queryParameters['disstid'], '7001');
      expect(c.title, '我的歌单');
      expect(c.creator, '小明');
      expect(c.cover, 'http://qpic.y.qq.com/logo.jpg');
      expect(c.tracks.single.nativeId, '002second');
      expect(c.total, 2);
      expect(c.hasMore, isFalse);
    });

    test('榜单详情：先抓 top.html 的期数再 GetDetail', () async {
      Map<String, dynamic>? payload;
      final p = _platform((req) async {
        if (req.url.path.endsWith('top.html')) {
          return _text('<li class="x" data-listname="流行指数榜" data-tid="top/4" data-date="2026-11-03"></li>'
              '<li data-listname="热歌榜" data-tid="top/26" data-date="2026_44"></li>');
        }
        payload = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'code': 0,
          'toplist': {
            'code': 0,
            'data': {
              'songInfoList': [_song()],
            },
          },
        });
      });
      final c = await p.collection(CatalogType.leaderboard, '26', limit: 20);
      expect(payload!['toplist']['param'], {'topid': 26, 'num': 20, 'period': '2026_44'});
      expect(c.title, '热歌榜');
      expect(c.tracks.single.nativeId, '003abcMid');
      expect(c.hasMore, isFalse);
    });

    test('榜单详情：期数不可用时报错', () async {
      final p = _platform((req) async => _text('<html></html>'));
      await expectLater(p.collection(CatalogType.leaderboard, '4'), throwsA(isA<PlatformException>()));
    });

    test('专辑 / 歌手详情', () async {
      final payloads = <Map<String, dynamic>>[];
      final p = _platform((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        payloads.add(body);
        if (body.containsKey('album')) {
          return _json({
            'album': {
              'data': {
                'songList': [
                  {'songInfo': _song()},
                ],
                'totalNum': 12,
              },
            },
          });
        }
        return _json({
          'songs': {
            'data': {
              'songList': [
                {'songInfo': _song()},
              ],
              'totalNum': 1,
            },
          },
          'albums': {
            'data': {
              'albumList': [
                {'albumMid': 'x', 'singerName': '国风堂'},
              ],
            },
          },
        });
      });
      final album = await p.collection(CatalogType.album, 'albumMid9', limit: 1);
      expect(payloads.last['album']['param'], {'albumMid': 'albumMid9', 'begin': 0, 'num': 1});
      expect(album.title, '知我专辑');
      expect(album.creator, '国风堂');
      expect(album.cover, 'https://y.gtimg.cn/music/photo_new/T002R500x500M000albumMid9.jpg');
      expect(album.total, 12);
      expect(album.hasMore, isTrue);
      final artist = await p.collection(CatalogType.artist, 'singerMid1');
      expect(payloads.last.containsKey('albums'), isTrue);
      expect(artist.title, '国风堂');
      expect(artist.cover, 'https://y.gtimg.cn/music/photo_new/T001R500x500M000singerMid1.jpg');
      expect(artist.tracks, hasLength(1));
    });

    test('歌词：QRC XML（base64）转 LRC + 逐字，翻译是 base64 LRC', () async {
      Map<String, dynamic>? param;
      final p = _platform((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        param = body['req']['param'] as Map<String, dynamic>;
        return _json({
          'code': 0,
          'req': {
            'code': 0,
            'data': {'lyric': _qrcB64, 'trans': _lrcB64, 'roma': ''},
          },
        });
      });
      final track = normalizeTencent(_song())!;
      final l = await p.lyric(track);
      expect(param!['songID'], 1234567);
      expect(param!['crypt'], 0);
      expect(param!['qrc'], 1);
      expect(param!['interval'], 245);
      expect(l.lrc, _qrcExpected);
      expect(l.translation, '[00:01.00]知我\n[00:02.50]第二行');
      expect(l.romanization, isNull);
      final line = l.words![1];
      expect(line.start, 12345);
      expect(line.duration, 3000);
      expect(line.text, '知我 &心尾巴');
      expect(line.words.map((w) => (w.start, w.duration, w.text)).toList(), [(12345, 400, '知'), (12745, 600, '我'), (13345, 700, ' &心'), (14045, 1300, '尾巴')]);
    });

    test('歌词：没有数字 songId 时先查 get_song_detail_yqq；qrc=1 无可用歌词时用 qrc=0 再要', () async {
      final methods = <String>[];
      final p = _platform((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final method = body['req']['method'] as String;
        methods.add('$method/${body['req']['param']['qrc'] ?? ''}');
        if (method == 'get_song_detail_yqq') {
          expect(body['req']['param']['song_mid'], 'midOnly');
          return _json({
            'req': {
              'data': {
                'track_info': {'id': 777},
              },
            },
          });
        }
        expect(body['req']['param']['songID'], 777);
        final qrc = body['req']['param']['qrc'];
        return _json({
          'req': {
            'data': {'lyric': qrc == 1 ? 'A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4' : _lrcB64},
          },
        });
      });
      final l = await p.lyric(const PTrack(platform: 'tx', nativeId: 'midOnly', title: 't', artist: 'a', duration: 200));
      expect(methods, ['get_song_detail_yqq/', 'GetPlayLyricInfo/1', 'GetPlayLyricInfo/0']);
      expect(l.lrc, '[00:01.00]知我\n[00:02.50]第二行');
      expect(l.words, isNull);
    });

    test('decodeTencentText：明文 / base64 / 密文', () {
      expect(decodeTencentText('[00:01.00]明文'), '[00:01.00]明文');
      expect(decodeTencentText(_lrcB64), '[00:01.00]知我\n[00:02.50]第二行');
      expect(decodeTencentText('A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4'), '');
      expect(decodeTencentText(null), '');
    });
  });
}
