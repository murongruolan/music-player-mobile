// 账号中心与设备管理接口：解析、请求方法与路径、错误传递。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/api/account_api.dart';
import 'package:lyra/api/devices_api.dart';
import 'package:lyra/net/net.dart';

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'code': 0, 'message': 'ok', 'requestId': 'rid', 'data': data}), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response err(int status, int code, String message) =>
    http.Response(jsonEncode({'code': code, 'message': message, 'requestId': 'rid-err', 'data': null}), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> userJson({String nickname = '阿栗', String uid = '10086427', bool activated = true, String? qq}) => {
      'uid': uid,
      'email': 'ali@example.com',
      'nickname': nickname,
      'qq': qq,
      'isActivated': activated,
      'membership': {'rank': activated ? 1 : 0, 'name': activated ? 'Sponsor' : '', 'expiresAt': null},
      'createdAt': '2026-01-01T00:00:00Z',
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
    // 资料与设备接口都需要登录态；令牌只进内存存储，请求头是否带上由封装负责
    await net.auth.signedIn({
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'expiresIn': 7200,
      'user': userJson(),
    });
  });

  group('AccountApi', () {
    test('profile 解析用户与会员态', () async {
      handler = (r) async => ok(userJson());
      final a = await AccountApi(net.client).profile();
      expect(calls.single.method, 'GET');
      expect(calls.single.url.path.endsWith('/auth/profile'), isTrue);
      expect(a.uid, '10086427');
      expect(a.nickname, '阿栗');
      expect(a.isActivated, isTrue);
      expect(a.membershipName, 'Sponsor');
    });

    test('updateProfile 走 PUT 且只带上改的字段', () async {
      handler = (r) async => ok(userJson(nickname: '新名字'));
      final a = await AccountApi(net.client).updateProfile(nickname: '新名字');
      expect(calls.single.method, 'PUT');
      expect(jsonDecode(calls.single.body), {'nickname': '新名字'});
      expect(a.nickname, '新名字');
    });

    test('bindQQ 绑定走 PUT、解绑走 DELETE', () async {
      handler = (r) async => ok(userJson(qq: '123456'));
      await AccountApi(net.client).bindQQ('123456');
      expect(calls[0].method, 'PUT');
      expect(jsonDecode(calls[0].body), {'qq': '123456'});
      await AccountApi(net.client).bindQQ(null);
      expect(calls[1].method, 'DELETE');
    });

    test('redeemCode 走 POST /codes/activate 并解出 user', () async {
      handler = (r) async => ok({'user': userJson()});
      final a = await AccountApi(net.client).redeemCode(' ABCD-1234 ');
      expect(calls.single.method, 'POST');
      expect(calls.single.url.path.endsWith('/codes/activate'), isTrue);
      expect(jsonDecode(calls.single.body), {'code': 'ABCD-1234'});
      expect(a.isActivated, isTrue);
    });

    test('业务错误抛 ApiException 且带后端文案', () async {
      handler = (r) async => err(409, 40901, '激活码已被使用');
      await expectLater(AccountApi(net.client).redeemCode('X'), throwsA(isA<ApiException>().having((e) => e.userMessage, 'userMessage', '激活码已被使用')));
    });
  });

  group('DevicesApi', () {
    test('list 解析设备与上限', () async {
      handler = (r) async => ok({
            'devices': [
              {'id': 3, 'deviceId': 'dev-a', 'deviceName': 'iPhone 15 Pro', 'platform': 'ios', 'systemVersion': 'iOS 19.1', 'appVersion': '2.4.0', 'lastSeenAt': '2026-11-03T10:00:00Z', 'lastIp': '1.2.3.4', 'createdAt': '2026-01-01T00:00:00Z', 'isCurrent': true},
              {'id': 4, 'deviceName': '客厅电视', 'platform': 'android_tv', 'isCurrent': false},
            ],
            'maxDevices': 10,
          });
      final dl = await DevicesApi(net.client).list();
      expect(calls.single.method, 'GET');
      expect(dl.maxDevices, 10);
      expect(dl.devices.length, 2);
      expect(dl.devices[0].isCurrent, isTrue);
      expect(dl.devices[0].isTv, isFalse);
      expect(dl.devices[1].isTv, isTrue);
    });

    test('remove 走 DELETE 并带上 id', () async {
      handler = (r) async => ok(null);
      await DevicesApi(net.client).remove(7);
      expect(calls.single.method, 'DELETE');
      expect(calls.single.url.path.endsWith('/auth/devices/7'), isTrue);
    });
  });

  test('资料 / 激活拿到的 user 写入会话缓存（离线启动和会员判断用）', () async {
    handler = (r) async => ok({'user': userJson(nickname: '新昵称', activated: true)});
    final seen = <String?>[];
    net.session.onUser.listen((u) => seen.add(u?['nickname'] as String?));
    await AccountApi(net.client).redeemCode('CODE');
    await Future<void>.delayed(Duration.zero);
    expect(net.session.user!['nickname'], '新昵称');
    expect(seen, ['新昵称']);
    expect(net.auth.cached!.isSponsor, isTrue);
  });
}
