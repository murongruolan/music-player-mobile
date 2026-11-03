// 设备信息：登录 / 注册 / 刷新时随请求上报（后端按 deviceId 做设备管理和上限控制）。
// deviceId 首次启动随机生成并持久化；卸载重装会变成新设备。
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'device_os_stub.dart' if (dart.library.io) 'device_os_io.dart' as os;
import 'json.dart';
import 'storage.dart';

class DeviceInfo {
  final String deviceId, deviceName, platform, systemVersion, appVersion;
  const DeviceInfo({required this.deviceId, required this.deviceName, required this.platform, required this.systemVersion, required this.appVersion});

  Json toJson() => {'deviceId': deviceId, 'deviceName': deviceName, 'platform': platform, 'systemVersion': systemVersion, 'appVersion': appVersion};

  static const _key = 'device.id.v1';

  static Future<DeviceInfo> load(KvStore store, {required String appVersion}) async {
    var id = await store.read(_key);
    if (id == null || id.isEmpty) {
      id = _newId();
      await store.write(_key, id);
    }
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    return DeviceInfo(
      deviceId: id,
      deviceName: os.deviceName(platform),
      platform: platform,
      systemVersion: os.systemVersion(),
      appVersion: appVersion,
    );
  }

  static String _newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return 'm-${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
