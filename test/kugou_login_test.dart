// 酷狗登录的确定性单元测试（无真实短信）：签名 / paramsKey / RSA / 响应解密 / 凭证拼装。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/platform/credentials.dart';
import 'package:lyra/platform/crypto_util.dart';
import 'package:lyra/platform/http.dart';
import 'package:lyra/platform/login/kugou_login.dart';
import 'package:lyra/platform/models.dart';

void main() {
  test('paramsKey = md5(1005+salt+20489)', () {
    expect(kugouParamsKey(), md5Hex('1005OIlwieks28dk2k092lksi2UIkp20489'));
    expect(kugouParamsKey().length, 32);
  });

  test('登录签名：按 key 排序拼 k=v，尾接盐', () {
    final sig = kugouLoginSignature({'b': '2', 'a': '1', 'n': 3});
    expect(sig, md5Hex('a=1b=2n=3OIlwieks28dk2k092lksi2UIkp'));
  });

  test('RSA 裸加密输出 256 位 hex；超长报错', () {
    final hex = kugouRsaRawEncrypt({'clienttime_ms': 1700000000000, 'key': 'abcdef0123456789'});
    expect(hex.length, 256);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(hex), isTrue);
    expect(() => kugouRsaRawEncrypt('x' * 200), throwsA(isA<PlatformException>()));
  });

  test('AES 响应解密（paramsKey 作 seed）', () {
    final key = kugouParamsKey();
    final digest = md5Hex(key);
    final plain = jsonEncode({'token': 't123', 'userid': '42'});
    final cipherHex = hexLower(aesCbcEncrypt(plain, digest.substring(0, 16), digest.substring(16)));
    expect(kugouAesDecrypt(cipherHex, key), plain);
  });

  test('loginByCode：密文 data 解出 token，拼出 cookie 与 extra', () async {
    final key = kugouParamsKey();
    final digest = md5Hex(key);
    final inner = jsonEncode({'token': 'TK', 'userid': '1008611', 'vip_type': '1', 'vip_token': 'VT', 'nickname': '阿酷'});
    final dataHex = hexLower(aesCbcEncrypt(inner, digest.substring(0, 16), digest.substring(16)));
    final client = MockClient((req) async {
      expect(req.url.path, '/v7/login_by_verifycode');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      // 信封字段齐全
      expect(body['plat'], 1);
      expect(body['support_multi'], 1);
      expect(body['key'], key);
      expect(body['params'], isA<String>());
      expect((body['pk'] as String).length, 256);
      expect(body['mobile'], '138*****0000'); // 打码手机号
      expect(body['signature'], kugouLoginSignature({...body}..remove('signature')));
      return http.Response(jsonEncode({'error_code': 0, 'data': dataHex}), 200);
    });
    final login = KugouLogin(PlatformHttp(client: client));
    final dev = KugouDevice('1234567890123456', 'ABCDEF012345ABCDEF012345');
    final cred = await login.loginByCode('138 0000 0000', '123456', dev);
    expect(cred.platform, Plat.kg);
    expect(cred.userId, '1008611');
    expect(cred.isVip, isTrue);
    expect(cred.extra[CredKey.kgToken], 'TK');
    expect(cred.extra[CredKey.kgVipToken], 'VT');
    expect(cred.extra[CredKey.kgDfid], dev.dfid);
    expect(cred.cookie.contains('token=TK'), isTrue);
    expect(cred.cookie.contains('KugooID=1008611'), isTrue);
  });

  test('loginByCode：明文 data 也能解析', () async {
    final client = MockClient((req) async => http.Response(jsonEncode({'status': 1, 'data': {'token': 'T2', 'userid': '7', 'nickname': 'x'}}), 200));
    final login = KugouLogin(PlatformHttp(client: client));
    final cred = await login.loginByCode('13800000000', '000000', KugouDevice('1111222233334444', 'DDDDEEEEFFFF000011112222'));
    expect(cred.extra[CredKey.kgToken], 'T2');
    expect(cred.isVip, isFalse);
  });

  test('loginByCode：失败返回码 → PlatformException', () async {
    final client = MockClient((req) async => http.Response(jsonEncode({'error_code': 20020, 'error_msg': '验证码错误'}), 200));
    final login = KugouLogin(PlatformHttp(client: client));
    await expectLater(
      login.loginByCode('13800000000', '999999', KugouDevice('1111222233334444', 'DDDDEEEEFFFF000011112222')),
      throwsA(isA<PlatformException>().having((e) => e.message, 'msg', contains('验证码错误'))),
    );
  });

  test('sendCode：号码非法本地拦截；ssa-code → 需要人机验证', () async {
    final login1 = KugouLogin(PlatformHttp(client: MockClient((_) async => http.Response('{}', 200))));
    await expectLater(login1.sendCode('123', KugouDevice('1', '2')), throwsA(isA<PlatformException>()));

    final login2 = KugouLogin(PlatformHttp(client: MockClient((_) async => http.Response(jsonEncode({'ssa-code': '1', 'status': 0}), 200))));
    await expectLater(login2.sendCode('13800000000', KugouDevice('1', '2')), throwsA(isA<KugouCaptchaRequired>()));
  });
}
