// 均衡器曲线映射。纯逻辑，供测试覆盖。
//
// UI 固定 10 段（31Hz..16kHz，-12..+12dB，见 mock.dart 的 eqPresets / eqBands），
// 而 Android Equalizer 的实际段数由设备决定（常见 5-6 段，中心频率各机不同）。
// 这里把 UI 的 10 点曲线在对数频域上插值到设备实际的波段上，硬件能力如何都能套用。

import 'dart:math' as math;

/// 10 段 UI 曲线的中心频率（Hz），与 eqBands 一一对应。
const uiBandHz = <double>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// 把 10 段 UI 曲线映射到设备实际波段。
///
/// [curveDb]：UI 上 10 个点的增益（dB，-12..12）。
/// [deviceBandHz]：设备各波段的中心频率（Hz，需升序）。
/// 返回与 [deviceBandHz] 等长的增益列表（dB，clamp 到 ±[maxDb]）。
///
/// 算法：对数频域线性插值。设备波段频率超出 UI 覆盖范围（<31 或 >16k）时，
/// 取最近端点的值（不外推斜率）。
List<double> mapCurveToBands(List<double> curveDb, List<double> deviceBandHz, {double maxDb = 12}) {
  assert(curveDb.length == uiBandHz.length, 'UI 曲线必须是 ${uiBandHz.length} 段');
  return [for (final hz in deviceBandHz) _sampleCurve(curveDb, hz).clamp(-maxDb, maxDb)];
}

double _sampleCurve(List<double> curveDb, double hz) {
  // 端点外：取最近端点的值。
  if (hz <= uiBandHz.first) return curveDb.first;
  if (hz >= uiBandHz.last) return curveDb.last;
  for (var i = 0; i < uiBandHz.length - 1; i++) {
    final lo = uiBandHz[i], hi = uiBandHz[i + 1];
    if (hz >= lo && hz <= hi) {
      // 对数频域插值：log(hz) 在 log(lo)..log(hi) 区间的线性位置。
      final t = (math.log(hz) - math.log(lo)) / (math.log(hi) - math.log(lo));
      return curveDb[i] + (curveDb[i + 1] - curveDb[i]) * t;
    }
  }
  return curveDb.last; // 不可达（上面端点已拦）
}

/// UI 预设增益是整数 -12..12；落到设备波段时保留一位小数即可，避免浮点噪声。
double round1(double v) => (v * 10).roundToDouble() / 10;
