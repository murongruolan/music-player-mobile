import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/net/json.dart';
import 'package:lyra/platform/audio_match.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/models.dart';

void main() {
  test('解析真实命中样本：歌曲、歌手、封面、命中位置', () {
    final hits = AudioMatchApi.parse(asJson(jsonDecode(File('test/fixtures/audio_match_response.json').readAsStringSync())));
    expect(hits, isNotEmpty);
    final h = hits.first;
    expect(h.track.platform, Plat.wy);
    expect(h.track.nativeId, '3453304463');
    expect(h.track.title, '降温');
    expect(h.track.artist, 'Zzh');
    expect(h.track.cover, isNotNull);
    expect(h.startMs, 20020);
  });

  test('未识别：result 为 null / 空', () {
    expect(AudioMatchApi.parse({'code': 200, 'data': {'result': null}}), isEmpty);
    expect(AudioMatchApi.parse({'code': 200, 'data': {'result': []}}), isEmpty);
    expect(() => AudioMatchApi.parse({'code': 400}), throwsA(isA<PlatformException>()));
  });

  test('请求参数与桌面端 POC 一致', () async {
    late Uri seen;
    late Map<String, String> headers;
    final api = AudioMatchApi(PlatformHttp(client: MockClient((r) async {
      seen = r.url;
      headers = r.headers;
      return http.Response('{"code":200,"data":{"result":null}}', 200);
    })));
    await api.query('a+b/c=', times: 2);
    expect(seen.host, 'interface.music.163.com');
    expect(seen.path, '/api/music/audio/match');
    expect(seen.queryParameters, {'sessionId': '0123456789abcdef', 'algorithmCode': 'shazam_v2', 'duration': '3', 'rawdata': 'a+b/c=', 'times': '2', 'decrypt': '1'});
    expect(headers['Referer'], 'https://music.163.com/');
  });
}
