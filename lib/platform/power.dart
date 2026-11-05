// 后台播放保活：电池优化豁免（Doze 白名单）的 Dart 侧桥。
//
// 锁屏/后台被杀问题分两层：
// - 系统层：前台服务 + PARTIAL_WAKE_LOCK 已由 audio_service 承担（播放期间自动持锁）；
// - 厂商层：Doze / 各 ROM 的后台耗电管控没有统一 API，标准做法是请求电池优化豁免
//   （QQ/网易同款）。豁免状态只影响「系统会不会限制我们」，不改变任何播放逻辑。
//
// 非 Android 平台 / 模拟器缺通道：静默返回 true（无需豁免），界面显示「已豁免」不误导。

import 'package:flutter/services.dart';

class PowerKeepAlive {
  PowerKeepAlive._();

  static const _ch = MethodChannel('lyra/power');

  /// 当前是否已豁免电池优化。查询失败（非 Android / 通道未就绪）视为已豁免。
  static Future<bool> batteryIgnored() async {
    try {
      return await _ch.invokeMethod<bool>('isBatteryIgnored') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// 弹系统确认框请求豁免。返回是否成功拉起了系统页。
  static Future<bool> requestBatteryIgnore() async {
    try {
      return await _ch.invokeMethod<bool>('requestBatteryIgnore') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
