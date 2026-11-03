// 曲目播放地址解析。引擎只认「一个能播的 URI」，从曲目到 URI 的映射由实现方负责。
//
// 最终实现是 Kiro 负责的音源脚本 / 平台链路（lx 脚本在沙箱里解析出直链）。
// 在那之前 [DemoTrackResolver] 用公开测试音频顶上，让播放链路可以真实联调：
//   TODO(kiro): 音源脚本运行时就绪后，替换 AppState 注入的 resolver 实现。

import '../data/models.dart';

abstract class TrackResolver {
  /// 返回可播放的 URI；null 表示当前无法解析（引擎会跳过并走下一首）。
  Future<Uri?> resolve(Song song, {String quality = 'SQ'});
}

/// 测试桩：按曲目 id 确定性地映射到公开测试音频（SoundHelix 示例曲，MP3）。
/// 确定性很重要——同一个 id 每次都拿到同一个 URL，方便回归与通知栏验证。
class DemoTrackResolver implements TrackResolver {
  static const _base = 'https://www.soundhelix.com/examples/mp3/';
  static const _count = 16; // SoundHelix-Song-1 .. 16

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ'}) async {
    final n = song.id % _count + 1;
    return Uri.parse('$_base/SoundHelix-Song-$n.mp3');
  }
}
