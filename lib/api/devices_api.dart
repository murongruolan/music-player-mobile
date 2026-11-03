// 登录设备管理：列表与移除（DevicesPage）。
import '../net/net.dart';

/// 一台登录设备（GET /auth/devices 的 items 元素）。
class DeviceRecord {
  final int id;
  final String deviceId, deviceName, platform, systemVersion, appVersion, lastSeenAt, lastIp, createdAt;
  final bool isCurrent;

  const DeviceRecord({
    required this.id,
    this.deviceId = '',
    this.deviceName = '',
    this.platform = '',
    this.systemVersion = '',
    this.appVersion = '',
    this.lastSeenAt = '',
    this.lastIp = '',
    this.createdAt = '',
    this.isCurrent = false,
  });

  factory DeviceRecord.fromJson(Json j) => DeviceRecord(
        id: j.integer('id'),
        deviceId: j.str('deviceId'),
        deviceName: j.str('deviceName'),
        platform: j.str('platform'),
        systemVersion: j.str('systemVersion'),
        appVersion: j.str('appVersion'),
        lastSeenAt: j.str('lastSeenAt'),
        lastIp: j.str('lastIp'),
        createdAt: j.str('createdAt'),
        isCurrent: j.boolean('isCurrent'),
      );

  /// 列表图标：电视 / 桌面端 / 手机。平台字段 + 设备名一起判断，兼容自定义 deviceName。
  bool get isTv => _hay.contains('tv') || deviceName.contains('电视') || deviceName.contains('TV');
  bool get isDesktop => _hay.contains('win') || _hay.contains('mac') || _hay.contains('linux') || _hay.contains('desktop');
  String get _hay => '${platform.toLowerCase()} $deviceName';
}

/// 设备列表 + 服务端允许的最大设备数（登录 / 扫码授权共用这个上限）。
class DeviceList {
  final List<DeviceRecord> devices;
  final int maxDevices;
  const DeviceList({required this.devices, required this.maxDevices});

  factory DeviceList.fromJson(Json j) => DeviceList(
        devices: j.list('devices', DeviceRecord.fromJson),
        maxDevices: j.integer('maxDevices', 10),
      );
}

class DevicesApi {
  final ApiClient _c;
  DevicesApi(this._c);

  /// 登录设备列表。进入页面拉一次，移除后重新拉取；不缓存（isCurrent 随请求上下文变化）。
  Future<DeviceList> list() => _c.get('/auth/devices', decode: (d) => DeviceList.fromJson(asJson(d)));

  /// 移除一台设备（幂等，允许重试）。成功后本地清缓存，下次 list 拿到最新。
  Future<void> remove(int id) async {
    await _c.delete('/auth/devices/$id', retry: true);
    _c.clearCache('/auth/devices');
  }
}
