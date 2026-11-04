// 当前网络类型（connectivity_plus）。用于：空闲预载只在 Wi-Fi 下进行、移动网络下降低在线音质。
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetKind {
  /// Wi-Fi / 有线。
  unmetered,

  /// 蜂窝网络。
  mobile,

  /// 判断不了（插件不可用、测试环境、VPN 等）。按调用方的保守策略处理。
  unknown,
}

Future<NetKind> currentNetwork() async {
  try {
    final r = await Connectivity().checkConnectivity();
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) return NetKind.unmetered;
    if (r.contains(ConnectivityResult.mobile)) return NetKind.mobile;
    return NetKind.unknown;
  } catch (_) {
    return NetKind.unknown;
  }
}

/// 网络类型变化记进应用日志（Wi-Fi ↔ 移动网络 ↔ 断网），排查播放 / 同步问题时用。
void watchNetworkForLog(void Function(String) log) {
  try {
    Connectivity().onConnectivityChanged.listen((r) => log('网络变为 ${r.map((e) => e.name).join('+')}'), onError: (Object _) {});
  } catch (_) {}
}
