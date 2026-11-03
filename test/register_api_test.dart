// 注册流程接口：注册设置 / 人机验证下发 / 发送验证码 / 注册并保存会话。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/api/registration_api.dart';
import 'package:lyra/net/net.dart';

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'rid', 'data': data}), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response err(int status, int code, String message) =>
    http.Response(jsonEncode({'code': code, 'message': message, 'requestId': 'rid-err', 'data': null}), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> loginData() => {
      'accessToken': 'at-1',
      'refreshToken': 'rt-1',
      'expiresIn': 7200,
      'user': {'uid': '1', 'email': 'new@example.com', 'nickname': 'new', 'isActivated': false},
    };

void main() {
  late List<http.Request> calls;
  late Future<http.Response> Function(http.Request) handler;
  late Net net;

  setUp(() async {
    calls = [];
    handler = (r) async => ok(null);
    net = await Net.memory(
      httpClient: MockClient((r) async {
        calls.add(r);
        return handler(r);
      }),
      baseUrl: 'https://api.test/api/v1',
    );
  });

  test('settings 解析注册开关与设备上限', () async {
    handler = (r) async => ok({'open': true, 'emailVerificationRequired': true, 'maxDevices': 5});
    final s = await RegistrationApi(net.client).settings();
    expect(calls.single.method, 'GET');
    expect(s.open, isTrue);
    expect(s.emailVerificationRequired, isTrue);
    expect(s.maxDevices, 5);
  });

  test('captcha 两种下发：captchala / none', () async {
    handler = (r) async => ok({'type': 'captchala', 'appKey': 'k-1', 'action': 'register'});
    final c1 = await RegistrationApi(net.client).captcha();
    expect(c1.none, isFalse);
    expect(c1.appKey, 'k-1');
    handler = (r) async => ok({'type': 'none', 'captchaId': '', 'imageData': ''});
    final c2 = await RegistrationApi(net.client).captcha();
    expect(c2.none, isTrue);
  });

  test('sendCode 走 POST 且邮箱去空格、passToken 透传', () async {
    await RegistrationApi(net.client).sendCode(' a@b.com ', '');
    final r = calls.single;
    expect(r.method, 'POST');
    expect(r.url.path.endsWith('/auth/send-verification-code'), isTrue);
    expect(jsonDecode(r.body), {'email': 'a@b.com', 'passToken': ''});
  });

  test('register 走 POST /auth/register-with-code 并保存会话', () async {
    handler = (r) async => ok(loginData());
    final data = await RegistrationApi(net.client).register(email: ' New@Example.com ', password: 'Abcd1234!', verificationCode: '123456');
    final r = calls.single;
    expect(r.method, 'POST');
    expect(r.url.path.endsWith('/auth/register-with-code'), isTrue);
    // 客户端只做 trim，大小写归一由服务端处理
    expect(jsonDecode(r.body), {'email': 'New@Example.com', 'password': 'Abcd1234!', 'verificationCode': '123456', 'passToken': ''});
    // 注册即登录：会话应已保存，之后带令牌的请求可用
    final acc = await net.auth.signedIn(data);
    expect(acc.email, 'new@example.com');
    expect(acc.isActivated, isFalse);
    expect(net.session.tokens, isNotNull);
  });

  test('注册业务错误抛 ApiException 且带后端文案', () async {
    handler = (r) async => err(400, 40001, '邮箱验证码错误或已过期');
    await expectLater(
      RegistrationApi(net.client).register(email: 'a@b.com', password: 'Abcd1234!', verificationCode: '000000'),
      throwsA(isA<ApiException>().having((e) => e.userMessage, 'userMessage', '邮箱验证码错误或已过期')),
    );
  });
}
