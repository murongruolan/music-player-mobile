// 曲目播放地址解析。引擎只认「一个能播的 URI」，从曲目到 URI 的映射由实现方负责。
//
// 正式实现是 lib/source/music_resolver.dart（洛雪音源脚本在 QuickJS 里解析出直链），main.dart 注入。
// [DemoTrackResolver] 用公开测试音频，只留给引擎的单元测试。

import '../data/models.dart';

/// 为什么要解析这首歌。
enum ResolveReason {
  /// 正常播放：可以用缓存的地址。
  play,

  /// 上一个地址加载失败 / 播放中断（403、链接过期）：不用缓存，重新取地址。
  reload,

  /// 上一个地址是试听片段（时长明显短于歌曲时长，或没播到 85% 就结束了）：换一个音源 / 平台。
  trial,
}

abstract class TrackResolver {
  /// 返回可播放的 URI；null 表示当前无法解析（引擎会跳过并走下一首）。
  Future<Uri?> resolve(Song song, {String quality = 'SQ', ResolveReason reason = ResolveReason.play});
}

/// 测试桩：按曲目 id 确定性地映射到公开测试音频（SoundHelix 示例曲，MP3）。
/// 确定性很重要——同一个 id 每次都拿到同一个 URL，方便回归与通知栏验证。
class DemoTrackResolver implements TrackResolver {
  static const _base = 'https://www.soundhelix.com/examples/mp3/';
  static const _count = 16; // SoundHelix-Song-1 .. 16

  @override
  Future<Uri?> resolve(Song song, {String quality = 'SQ', ResolveReason reason = ResolveReason.play}) async {
    final n = song.id % _count + 1;
    return Uri.parse('$_base/SoundHelix-Song-$n.mp3');
  }
}
