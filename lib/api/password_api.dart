// 找回密码（ForgotPage 三步流）：发验证码 → 设新密码。重设成功后该账号的所有会话都会被吊销。
import '../net/net.dart';

class PasswordApi {
  final ApiClient _c;
  PasswordApi(this._c);

  /// 发送重置验证码（10 分钟有效）。邮箱不存在时服务端也返回成功，不泄露账号是否存在。
  Future<void> forgot(String email) async {
    await _c.post('/auth/forgot-password', auth: false, body: {'email': email.trim()});
  }

  /// 验证码错误 / 过期：business 40001；账号被禁用：40301。
  Future<void> reset({required String email, required String code, required String password}) async {
    await _c.post('/auth/reset-password', auth: false, body: {'email': email.trim(), 'verificationCode': code.trim(), 'password': password});
  }
}
