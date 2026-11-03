// 检查更新：GET /updates/check?platform=&appVersion=（后端 releases 表，管理后台「版本发布」维护）。
import 'package:flutter/foundation.dart';
import '../net/net.dart';

class ReleaseInfo {
  final String version, notes, url;
  final String? minVersion;
  final DateTime? publishedAt;
  const ReleaseInfo({required this.version, this.notes = '', this.url = '', this.minVersion, this.publishedAt});
  factory ReleaseInfo.fromJson(Json j) => ReleaseInfo(version: j.str('version'), notes: j.str('notes'), url: j.str('url'), minVersion: j.strOrNull('minVersion'), publishedAt: j.time('publishedAt'));
}

class UpdateCheck {
  /// 当前版本低于强更阈值，必须更新后才能继续使用。
  final bool versionDisabled;
  final bool hasUpdate;
  final ReleaseInfo? latest;
  const UpdateCheck({required this.versionDisabled, required this.hasUpdate, this.latest});
  factory UpdateCheck.fromJson(Json j) => UpdateCheck(versionDisabled: j.boolean('versionDisabled'), hasUpdate: j.boolean('hasUpdate'), latest: j.objOrNull('latest') == null ? null : ReleaseInfo.fromJson(j.obj('latest')));
}

class UpdateApi {
  final ApiClient _c;
  UpdateApi(this._c);

  static String get platform => kIsWeb ? 'web' : switch (defaultTargetPlatform) { TargetPlatform.iOS => 'ios', TargetPlatform.macOS => 'macos', TargetPlatform.windows => 'windows', TargetPlatform.linux => 'linux', _ => 'android' };

  /// 不需要登录。结果缓存 10 分钟（启动检查和「关于」页共用）。
  Future<UpdateCheck> check() => _c.get('/updates/check',
      auth: false,
      query: {'platform': platform, 'appVersion': _c.device.appVersion},
      cacheTtl: const Duration(minutes: 10),
      staleOnError: true,
      decode: (d) => UpdateCheck.fromJson(asJson(d)));
}
