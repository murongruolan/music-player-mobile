// 数据模型。字段与原型 data.js 对应，接口对接时由 Repository 填充。

class Song {
  final int id;
  final String title, artist, album, quality;
  final int dur; // 秒
  final double hue;
  final int variant;
  const Song(this.id, this.title, this.artist, this.album, this.dur, this.quality, this.hue, this.variant);
  bool get plainQ => quality == 'HQ' || quality == '128k';
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
  const Playlist(this.id, this.title, {this.by = '', required this.count, this.playCount = '', required this.hue, required this.variant, this.mine = false, this.tag});
}

class LyricLine {
  final double t, d;
  final String text, trans, section;
  const LyricLine(this.t, this.d, this.text, this.trans, this.section);
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
