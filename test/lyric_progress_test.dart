import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/data/models.dart';

void main() {
  test('行尾最后一个字在切行前强制收满，不会永远差最后一帧', () {
    // 4 个字，最后一个字 2.85s 开始、0.15s 结束，正好压到下一句 3.0s。
    const line = LyricLine(1, 2, '测试歌词', '', '', words: [
      LyricWord(0, .5, 0, 1),
      LyricWord(1.2, .5, 1, 2),
      LyricWord(2.2, .5, 2, 3),
      LyricWord(2.85, .15, 3, 4),
    ]);

    // 下一句 t=3.0 之前 0.1s：旧实现只会在最后一个字内插值（约 1/3），
    // 切行后永远不亮；新实现应该已经按 1.0 完整画出。
    expect(line.progressAt(2.9), 1.0);

    // 不能影响正常的中段填充：2.6s 在第三个字（2.2–2.7）内，应插值到 70%。
    expect(line.progressAt(2.6), closeTo(.7, .01));
  });
}
