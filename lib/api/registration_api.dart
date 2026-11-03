// 注册流程：注册设置、人机验证下发、邮箱验证码、注册。
// 登录 / 刷新 / 退出在网络层（net.auth），注册成功后也用 net.auth.signedIn() 保存令牌。
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

/// 人机验证下发结果（POST /auth/captcha/generate）。
/// type == 'none'：服务端未启用验证码，passToken 传空即可；
/// type == 'captchala'：需要拉起 captcha.la 组件（桌面端走 iframe 桥接页，移动端 WebView 版待接入）。
class CaptchaData {
  final String type, appKey, action;
  const CaptchaData({required this.type, this.appKey = '', this.action = 'register'});

  bool get none => type == 'none';

  factory CaptchaData.fromJson(Json j) => CaptchaData(
        type: j.str('type'),
        appKey: j.str('appKey'),
        action: j.str('action', 'register'),
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

  /// 人机验证配置（服务端决定类型）。
  Future<CaptchaData> captcha() => _c.post(
        '/auth/captcha/generate',
        auth: false,
        decode: (d) => CaptchaData.fromJson(asJson(d)),
      );

  /// 发送邮箱验证码（注册用）。验证码未启用时 passToken 传空字符串。
  /// 后端对已存在的邮箱静默忽略（返回 sent:true），客户端无需也无法据此探测账号。
  Future<void> sendCode(String email, String passToken) => _c.post(
        '/auth/send-verification-code',
        auth: false,
        body: {'email': email.trim(), 'passToken': passToken},
      );

  /// 注册。返回登录态数据（{accessToken, refreshToken, expiresIn, user}），
  /// 成功后调用 net.auth.signedIn(data) 保存令牌并拿到用户信息。
  /// [verificationCode] 在服务端关闭邮箱验证时传空；[passToken] 在未启用人机验证时传空。
  Future<Object?> register({
    required String email,
    required String password,
    String verificationCode = '',
    String passToken = '',
  }) =>
      _c.post('/auth/register-with-code', auth: false, body: {
        'email': email.trim(),
        'password': password,
        'verificationCode': verificationCode.trim(),
        'passToken': passToken,
      });
}
