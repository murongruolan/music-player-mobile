import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/lyric_store.dart';
import 'package:lyra/platform/models.dart';

void main() {
  test('开头的歌名/词曲/编曲信息不进入歌词视图', () {
    const lrc = '''
[00:00.00]欧若拉 - 张韶涵 (Angela Zhang)
[00:00.00]词：施立
[00:00.00]曲：李天龙
[00:00.00]编曲：吕绍淳
[00:18.36]神秘北极圈 阿拉斯加的山巅
[00:22.10]谁的脸 出现海角的天边
''';
    final lines = toLyricLines(const Lyric(lrc), 236);
    expect(lines.first.text, '神秘北极圈 阿拉斯加的山巅');
    expect(lines.length, 2);
  });
}
