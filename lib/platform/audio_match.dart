// 听歌识曲 · 识别接口：网易 shazam_v2，无鉴权 GET。指纹在本机算（见 lib/audio/fingerprint.dart），
// 这里只把 base64 指纹发出去、解析命中的歌。不上传原始录音。
//
// 参数照桌面端 POC（docs 已随交接移除，结论见 PR 描述）：sessionId 用固定占位值，不要随机生成。
import '../net/json.dart';
import 'http.dart';
import 'models.dart';
import 'netease.dart' show neteaseSong;

/// 一条识别结果。
class AudioMatchHit {
  final PTrack track;

  /// 录音片段在这首歌里的位置（毫秒）。
  final int startMs;
  const AudioMatchHit(this.track, this.startMs);
}

class AudioMatchApi {
  final PlatformHttp http;
  AudioMatchApi(this.http);

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36';

  /// 查询一次。[times] 是第几次尝试（同一次识别里递增）。没识别出来返回空列表。
  Future<List<AudioMatchHit>> query(String fingerprint, {int seconds = 3, int times = 1}) async {
    final url = Uri.https('interface.music.163.com', '/api/music/audio/match', {
      'sessionId': '0123456789abcdef',
      'algorithmCode': 'shazam_v2',
      'duration': '$seconds',
      'rawdata': fingerprint,
      'times': '$times',
      'decrypt': '1',
    });
    final j = asJson(await http.json(Plat.wy, 'GET', url, headers: const {'User-Agent': _ua, 'Referer': 'https://music.163.com/'}));
    return parse(j);
  }

  /// 解析响应（单测直接用样本）。code != 200 视为接口出错。
  static List<AudioMatchHit> parse(Json j) {
    if (j.integer('code') != 200) throw PlatformException(Plat.wy, '识曲服务暂时不可用（${j['code']}）');
    final result = asJson(j['data'])['result'];
    if (result is! List) return const [];
    return [
      for (final r in result)
        if (r is Map)
          if (neteaseSong(asJson(r['song'])) case final t?) AudioMatchHit(t, asJson(r).integer('startTime')),
    ];
  }
}
