import 'dart:math' as math;
// 数据模型。字段与原型 data.js 对应，接口对接时由 Repository 填充。

class Song {
  final int id;
  final String title, artist, album, quality;
  final int dur; // 秒
  final double hue;
  final int variant;

  /// 真实歌曲的全局标识 `<平台代码>:<平台歌曲 id>`（mock 歌曲为 null）。
  final String? key;

  /// 封面地址（没有时用按色相生成的渐变封面）。
  final String? cover;
  const Song(this.id, this.title, this.artist, this.album, this.dur, this.quality, this.hue, this.variant, {this.key, this.cover});
  bool get plainQ => quality == 'HQ' || quality == '128k';

  /// 没有正在播放的歌时给预览 / 占位用（设置页的背景、歌词预览等）。
  static const placeholder = Song(-1, 'Lyra', '', '', 0, '', 260, 2);

  /// 复制并覆盖部分字段（真实播放时用引擎返回的实际时长替换 mock 时长）。
  /// key / cover 必须跟随复制（真实歌曲的标识与封面不能丢）。
  Song copyWith({int? dur}) => Song(id, title, artist, album, dur ?? this.dur, quality, hue, variant, key: key, cover: cover);
}

class Playlist {
  final int id;
  final String title, by;
  final int count;
  final String playCount;
  final double hue;
  final int variant;
  final bool mine;
  final String? tag;

  /// 真实歌单的歌曲（歌曲目录里的 id）。mock 歌单为空，用 [count] 显示数量。
  final List<int> ids;

  /// 真实歌单的云端 id、类型（created 自建 / collected 收藏的平台歌单）与平台来源。
  final String? key, platform, externalId;
  final String kind;
  final DateTime? updatedAt, createdAt;
  final String? cover;
  const Playlist(this.id, this.title, {this.by = '', required this.count, this.playCount = '', required this.hue, required this.variant, this.mine = false, this.tag, this.ids = const [], this.key, this.platform, this.externalId, this.kind = 'created', this.updatedAt, this.createdAt, this.cover});

  bool get isReal => key != null;
}

/// 逐字（逐词）时间：[start] / [dur] 秒，对应 [LyricLine.text] 里 UTF-16 下标 [from, to)。
class LyricWord {
  final double start, dur;
  final int from, to;
  const LyricWord(this.start, this.dur, this.from, this.to);
}

class LyricLine {
  final double t, d;
  final String text, trans, section;

  /// 逐字时间（网易 yrc / 酷狗 krc / 酷我 / 咪咕 mrc / QQ qrc）。没有时按行时长估算。
  final List<LyricWord>? words;
  const LyricLine(this.t, this.d, this.text, this.trans, this.section, {this.words});

  /// 只有行时间时，「唱完这一行」大约用多久。行间隔里常含前奏 / 间奏，直接按整段间隔铺开
  /// 会让填充比演唱慢一截（唱完了填充才走一半），所以按字数估一个演唱时长封顶。
  double get _sungDur {
    final n = text.trim().length;
    final est = 0.8 + n * 0.32;
    return math.max(0.6, math.min(d * .92, est));
  }

  /// 在时间 [p]（秒）时这一行已唱到的位置，0..1（按字符比例；逐字时间精确到字内插值）。
  double progressAt(double p) {
    final w = words;
    final len = text.length;
    if (w == null || w.isEmpty || len == 0) return ((p - t) / _sungDur).clamp(0.0, 1.0);
    if (p <= w.first.start) return w.first.from / len;
    for (final x in w) {
      if (p < x.start) return x.from / len; // 词与词之间的停顿：停在下一个词开头
      if (p < x.start + x.dur) {
        final f = x.dur <= 0 ? 1.0 : (p - x.start) / x.dur;
        return (x.from + (x.to - x.from) * f) / len;
      }
    }
    return 1;
  }
}

class Platform {
  final String id, name, mark;
  final int c1, c2;
  const Platform(this.id, this.name, this.mark, this.c1, this.c2);
  String get short => name.replaceAll('音乐', '');
}

class Script {
  final String id, name, ver;
  final List<String> platforms, qualities;
  final int ms, ok;
  const Script(this.id, this.name, this.ver, this.platforms, this.qualities, this.ms, this.ok);
}

class Skin {
  final String id, name, cat, desc;
  final bool usesBg;
  final String? tag;
  const Skin(this.id, this.name, this.cat, this.desc, {this.usesBg = false, this.tag});
}

class Quality {
  final String key, name, desc;
  const Quality(this.key, this.name, this.desc);
}

class PromoBanner {
  final String kicker, title, desc;
  final double hue;
  const PromoBanner(this.kicker, this.title, this.desc, this.hue);
}

/// 公告。[popup] = 进入 App 时弹窗展示；否则只出现在公告页。
/// [closable] = 弹窗可直接关闭 / 被「全部已读」带走；false 时必须单独点「我已知晓」确认。
class Announcement {
  final String id, type, date, title, body;
  final bool important, popup, closable;
  const Announcement(this.id, this.type, this.date, this.title, this.body, {this.important = false, this.popup = false, this.closable = true});
}

class Device {
  final String name, os, last;
  final bool current;
  const Device(this.name, this.os, this.last, {this.current = false});
}

class CastDevice {
  final String name, kind, last;
  const CastDevice(this.name, this.kind, this.last);
}
