import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/source/lx_track.dart';
import 'package:lyra/source/source_manager.dart';
import 'package:lyra/sync/cloud_models.dart';

/// 只支持 [plat]、音质 [qs] 的脚本；musicUrl 返回 `https://cdn.test/<名字>/<平台>/<id>.<音质>`。
/// songmid 以 x 开头时报错。
String script(String name, String plat, List<String> qs) => '''
const { EVENT_NAMES, on, send } = globalThis.lx;
let n = 0;
on(EVENT_NAMES.request, ({ source, info }) => {
  n++;
  const id = info.musicInfo.songmid;
  if (id.startsWith('x')) return Promise.reject(new Error('$name 解析失败'));
  return Promise.resolve('https://cdn.test/$name/' + source + '/' + id + '.' + info.type + '?n=' + n);
});
send(EVENT_NAMES.inited, { sources: { $plat: { name: '$plat', type: 'music', actions: ['musicUrl'], qualitys: ${jsonEncode(qs)} } } });
''';

CloudSource src(String id, String body) => CloudSource(id: id, name: id, rawScript: body);

Map<String, dynamic> track(String platform, String id, {List<String> q = const ['128k', '320k', 'flac']}) => {
      'id': '$platform:$id',
      'platform': platform,
      'title': '晴天',
      'artist': '周杰伦',
      'album': '叶惠美',
      'duration': 269,
      'qualities': q,
      'identity': {'id': id},
    };

void main() {
  test('音质回退：从偏好往下找歌曲和音源都有的档位', () {
    expect(pickQuality('flac', ['128k', '320k', 'flac'], ['128k', '320k']), '320k');
    expect(pickQuality('320k', ['128k', '320k', 'flac'], ['128k', '320k', 'flac']), '320k');
    expect(pickQuality('flac24bit', ['hires', 'flac'], ['flac24bit', 'flac']), 'flac24bit');
    expect(pickQuality('master', ['128k'], ['320k']), isNull);
    expect(lxQualityOf('SQ'), 'flac');
    expect(appQualityOf('320k'), 'HQ');
  });

  test('musicInfo：各平台的 id 取法与桌面端一致', () {
    final tx = toLegacyTrack({...track('tx', '0039MnYb0qxYhV'), 'identity': {'id': '0039MnYb0qxYhV', 'songId': '97773', 'strMediaMid': 'M1', 'albumMid': 'A1'}}, '320k');
    expect(tx['songmid'], '97773');
    expect(tx['strMediaMid'], 'M1');
    expect((tx['meta'] as Map)['qq'], {'mid': 'M1', 'songid': '97773'});
    expect(tx['interval'], '4:29');
    final kg = toLegacyTrack({...track('kg', 'ABCDEF0123456789ABCDEF0123456789'), 'identity': {'id': 'ABCDEF0123456789ABCDEF0123456789', 'albumAudioId': '555', 'hash': 'H'}}, '128k');
    expect(kg['songmid'], '555');
    expect(kg['hash'], 'H');
    final mg = toLegacyTrack({...track('mg', '600'), 'identity': {'id': '600', 'contentId': 'C9', 'copyrightId': '600'}}, '128k');
    expect(mg['songmid'], 'C9');
    final kw = toLegacyTrack({...track('kw', 'MUSIC_42'), 'id': 'kw:MUSIC_42', 'identity': {}}, '128k');
    expect(kw['songmid'], '42');
    expect(kw['types'], [for (final q in ['128k', '320k', 'flac']) {'type': q, 'size': null}]);
  });

  test('本机曲目 → 桌面端 Track（V2 字段名也认）', () {
    final t = lxTrackOf(const CloudTrack(id: 'kg:abc', platform: 'kg', songId: 'abc', title: 't', artist: 'a', durationSec: 10, raw: {'songHash': 'HASH', 'albumAudioId': '9', 'availableQualities': ['128k', 'flac']}));
    expect(t['identity'], containsPair('hash', 'HASH'));
    expect(t['identity'], containsPair('albumAudioId', '9'));
    expect(t['qualities'], ['128k', 'flac']);
  });

  test('同一首歌的判断（桌面端 isSameTrack）', () {
    const a = (title: '晴天', artist: '周杰伦', album: '叶惠美', duration: 269);
    expect(isSameTrack(a, (title: '晴天 (Live)', artist: '周杰伦', album: '', duration: 271)), isTrue);
    expect(isSameTrack(a, (title: '晴天', artist: '周杰伦、五月天', album: '', duration: 0)), isTrue);
    expect(isSameTrack(a, (title: '晴天', artist: '周杰伦', album: '', duration: 300)), isFalse);
    expect(isSameTrack(a, (title: '雨天', artist: '别人', album: '', duration: 269)), isFalse);
  });

  group('解析播放地址', () {
    late SourceManager m;
    setUp(() => m = SourceManager(client: MockClient((_) async => http.Response('', 404))));
    tearDown(() => m.dispose());

    test('依次尝试：不支持平台的、解析失败的跳过，用第一个成功的；结果缓存', () async {
      final a = src('a', script('A', 'tx', ['128k'])); // 不支持 kw
      final b = src('b', script('B', 'kw', ['128k', '320k']));
      final r = await m.resolveUrl(track('kw', '42'), 'flac', [a, b]);
      expect(r.url, 'https://cdn.test/B/kw/42.320k?n=1');
      expect(r.quality, '320k');
      expect(r.sourceId, 'b');
      expect(m.capabilities.keys, containsAll(['a', 'b']));
      final again = await m.resolveUrl(track('kw', '42'), 'flac', [a, b]);
      expect(again.fromCache, isTrue);
      expect(again.url, r.url);
      final fresh = await m.resolveUrl(track('kw', '42'), 'flac', [a, b], forceRefresh: true);
      expect(fresh.url, endsWith('n=2'));
    });

    test('全部失败时报最后一个错误', () async {
      final b = src('b', script('B', 'kw', ['128k']));
      await expectLater(m.resolveUrl(track('kw', 'x1'), '128k', [b]), throwsA(isA<ResolveException>().having((e) => e.message, 'm', contains('B 解析失败'))));
      await expectLater(m.resolveUrl(track('wy', '1'), '128k', [b]), throwsA(isA<ResolveException>().having((e) => e.message, 'm', contains('不支持'))));
      await expectLater(m.resolveUrl(track('kw', '1'), '128k', const []), throwsA(isA<ResolveException>()));
    });

    test('脚本初始化失败记录原因；脚本内容变了会重启', () async {
      final bad = src('bad', 'throw new Error("nope")');
      await expectLater(m.resolveUrl(track('kw', '1'), '128k', [bad]), throwsA(isA<ResolveException>().having((e) => e.message, 'm', contains('初始化失败'))));
      expect(m.initErrors['bad'], contains('nope'));
      final fixed = src('bad', script('F', 'kw', ['128k']));
      final r = await m.resolveUrl(track('kw', '1'), '128k', [fixed]);
      expect(r.url, startsWith('https://cdn.test/F/'));
      expect(m.initErrors.containsKey('bad'), isFalse);
    });
  });

  test('PTrack.toCloud → lxTrackOf 保留 identity 与音质', () {
    const p = PTrack(platform: 'tx', nativeId: 'mid1', title: 't', artist: 'a', duration: 100, qualities: ['128k', 'flac'], identity: {'songId': '77', 'strMediaMid': 'm'});
    final t = lxTrackOf(p.toCloud());
    expect(t['qualities'], ['128k', 'flac']);
    expect(toLegacyTrack(t, '128k')['songmid'], '77');
  });
}
