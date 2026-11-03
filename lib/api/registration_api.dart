// 接口写法示例：一个模块一个类，构造时拿 ApiClient，方法里只写路径、参数和解析。
import '../net/net.dart';

class RegistrationSettings {
  final bool open, emailVerificationRequired;
  final int maxDevices;
  const RegistrationSettings({required this.open, required this.emailVerificationRequired, required this.maxDevices});

  factory RegistrationSettings.fromJson(Json j) => RegistrationSettings(
        open: j.boolean('open'),
        emailVerificationRequired: j.boolean('emailVerificationRequired'),
        maxDevices: j.integer('maxDevices', 10),
      );
}

class RegistrationApi {
  final ApiClient _c;
  RegistrationApi(this._c);

  /// 注册开关、是否需要邮箱验证码。变化很少，缓存 5 分钟；断网时用旧值。
  Future<RegistrationSettings> settings() => _c.get(
        '/auth/registration-settings',
        auth: false,
        cacheTtl: const Duration(minutes: 5),
        staleOnError: true,
        decode: (d) => RegistrationSettings.fromJson(asJson(d)),
      );
}
