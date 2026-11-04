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
