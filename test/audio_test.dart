// 播放链路纯逻辑测试：格式识别 / 测试桩确定性 / EQ 曲线映射。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/audio/equalizer.dart';
import 'package:lyra/audio/formats.dart';
import 'package:lyra/audio/track_resolver.dart';
import 'package:lyra/data/mock.dart';

void main() {
  group('formats', () {
    test('扩展名识别', () {
      expect(formatOfUri(Uri.parse('https://a.b/song.flac')), 'flac');
      expect(formatOfUri(Uri.parse('https://a.b/song.FLAC?token=1')), 'flac');
      expect(formatOfUri(Uri.parse('https://a.b/no-ext')), '');
      expect(formatOfUri(Uri.parse('https://a.b/')), '');
    });

    test('支持矩阵', () {
      expect(isLikelySupported(Uri.parse('https://a.b/s.mp3')), isTrue);
      expect(isLikelySupported(Uri.parse('https://a.b/s.flac')), isTrue);
      expect(isLikelySupported(Uri.parse('https://a.b/s.opus')), isTrue);
      expect(isLikelySupported(Uri.parse('https://a.b/s.ape')), isFalse); // 冷格式明确拒绝
      expect(isLikelySupported(Uri.parse('https://a.b/stream')), isTrue); // 无扩展名交给平台尝试
    });

    test('人话格式名', () {
      expect(formatLabel('flac'), 'FLAC');
      expect(formatLabel('m4a'), 'M4A');
      expect(formatLabel('ape'), 'APE');
    });
  });

  group('DemoTrackResolver', () {
    test('同 id 确定性映射，且落在 1..16', () async {
      final r = DemoTrackResolver();
      final u1 = await r.resolve(songs[0]);
      final u2 = await r.resolve(songs[0]);
      final u3 = await r.resolve(songs[23]);
      expect(u1, u2); // 确定性
      expect(u1!.path, endsWith('.mp3'));
      expect(u3!.path, endsWith('.mp3'));
      final n1 = int.parse(u1.path.split('-').last.split('.').first);
      expect(n1, inInclusiveRange(1, 16));
    });

    test('不同 id 尽量分散到不同测试曲', () async {
      final r = DemoTrackResolver();
      final a = await r.resolve(songs[0]);
      final b = await r.resolve(songs[1]);
      expect(a, isNot(b));
    });
  });

  group('mapCurveToBands', () {
    test('设备波段频率恰为 UI 频点时直取', () {
      final out = mapCurveToBands([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [31, 1000, 16000]);
      expect(out, [1, 6, 10]);
    });

    test('对数频域插值：频点之间取对数线性值', () {
      // 500 与 1000 的几何中点 ≈ 707.1Hz → (5 + 0) / 2 = 2.5
      final out = mapCurveToBands([0, 0, 0, 0, 5, 0, 0, 0, 0, 0], [707.1]);
      expect(out[0], closeTo(2.5, 0.01));
    });

    test('超出 UI 范围取端点值', () {
      final out = mapCurveToBands([3, 0, 0, 0, 0, 0, 0, 0, 0, -4], [20, 20000]);
      expect(out, [3, -4]);
    });

    test('clamp 到 ±12', () {
      final out = mapCurveToBands([12, 12, 12, 12, 12, 12, 12, 12, 12, 12], [1000, 30000], maxDb: 12);
      expect(out.every((v) => v >= -12 && v <= 12), isTrue);
    });

    test('典型 5 段设备：返回 5 个值且在合法范围', () {
      final out = mapCurveToBands([...eqPresets['流行']!], [60, 230, 910, 3600, 14000]);
      expect(out.length, 5);
      expect(out.every((v) => v >= -12 && v <= 12), isTrue);
    });
  });
}
