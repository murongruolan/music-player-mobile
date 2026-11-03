// 扫码登录（Device Code Flow）。
// - 已登录的设备确认 / 拒绝授权码：[confirm]（手机扫电视、车机、桌面端）。
// - 未登录的设备取码并轮询：[requestCode] / [poll]（在登录页用另一台已登录的设备授权这台手机）。
import '../net/net.dart';

enum DeviceLoginStatus { pending, granted, denied, expired }

class DevicePoll {
  final DeviceLoginStatus status;

  /// granted 时与登录接口同构：{accessToken, refreshToken, expiresIn, user}
  final Json? data;
  const DevicePoll(this.status, [this.data]);
}

class DeviceLoginApi {
  final ApiClient _c;
  DeviceLoginApi(this._c);

  /// 从二维码内容里取出 6 位授权码。支持 {"type":"sollin-login","code":"382914"}、带 code 参数的链接和纯数字。
  static String? parseCode(String raw) {
    final t = raw.trim();
    final m = RegExp(r'"code"\s*:\s*"?(\d{6})"?').firstMatch(t) ?? RegExp(r'[?&]code=(\d{6})\b').firstMatch(t) ?? RegExp(r'^(\d{6})$').firstMatch(t);
    return m?.group(1);
  }

  /// 未登录设备取一次性授权码（6 位，5 分钟有效）。返回 (code, 有效秒数)。
  Future<(String, int)> requestCode() => _c.post('/auth/device/code', auth: false, body: {'device': _c.device.toJson()}, decode: (d) {
        final j = asJson(d);
        return (j.str('code'), j.integer('expiresIn', 300));
      });

  /// 轮询授权状态（建议 3 秒左右一次）。granted 的结果只能领取一次。
  Future<DevicePoll> poll(String code) => _c.post('/auth/device/poll', auth: false, body: {'code': code}, decode: (d) {
        final j = asJson(d);
        final st = DeviceLoginStatus.values.where((s) => s.name == j.str('status')).firstOrNull ?? DeviceLoginStatus.pending;
        return DevicePoll(st, st == DeviceLoginStatus.granted ? j : null);
      });

  /// 允许 / 拒绝。授权码过期、已处理或不存在时抛 business / 40001；设备数超限抛 40301。
  Future<void> confirm(String code, {bool grant = true}) async {
    await _c.post('/auth/device/confirm', body: {'code': code, 'action': grant ? 'grant' : 'deny'});
  }
}
