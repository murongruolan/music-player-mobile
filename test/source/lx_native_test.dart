// lx.utils 的 Dart 实现对齐 Node（向量由 Node 22 的 crypto / zlib 生成）。
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/source/lx_native.dart';

const _spki = '-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC21Fxoy9mUp5lPm8RBp6GDNZGW\nG811XBxmJuPonpkKxWvs0oYiaOKykjAlKxvw3/NniP7aHXoEnb8xvI61GIhJG8t+\nFcI8gSW8wMrhHh/iWVfyxnc2gDaTgmgnf6dDp3vbMc/WBmddQ4/xP7DuTInkQGs1\n9DZkSdZqL6wF34135QIDAQAB\n-----END PUBLIC KEY-----\n';
const _pkcs1 = '-----BEGIN RSA PUBLIC KEY-----\nMIGJAoGBALbUXGjL2ZSnmU+bxEGnoYM1kZYbzXVcHGYm4+iemQrFa+zShiJo4rKS\nMCUrG/Df82eI/todegSdvzG8jrUYiEkby34VwjyBJbzAyuEeH+JZV/LGdzaANpOC\naCd/p0One9sxz9YGZ11Dj/E/sO5MieRAazX0NmRJ1movrAXfjXflAgMBAAE=\n-----END RSA PUBLIC KEY-----\n';
const _rsa = 'gCIe4Mbt8ty2abChe6l78hIhXLZIT18UZgUmbAQY3mpHvW8CnNa5ZhY1Op6SWwtH80XTSHdcmbFq1oxd6X4eWLwihWOkEGwvh7PXxA18kU95iUP3gmwL43dL8eaflY8Mqffpi9eAb8yCRQf1rO50r/Ej7UiMBpUZbkbzT5ESM90=';

Uint8List _u(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('md5 与 Node 一致', () {
    expect(lxNative('md5', base64Encode(_u('洛雪 lx'))), 'f94bf3f3f4472a8031d8b01d0e2758f8');
  });

  test('AES ECB / CBC + PKCS7 与 Node createCipheriv 一致', () {
    expect(base64Encode(lxAes(_u('hello lyra'), 'aes-128-ecb', _u('0123456789abcdef'), Uint8List(0))), 'zInOeCyna90HZ1CD9QSEag==');
    expect(base64Encode(lxAes(_u('hello lyra, 你好'), 'aes-128-cbc', _u('0123456789abcdef'), _u('fedcba9876543210'))), 'xPu9LAa/yFWPAoBQqQ+NGxdrcwNm353NQfJQSdtoMZg=');
    expect(() => lxAes(_u('x'), 'aes-128-gcm', _u('0123456789abcdef'), Uint8List(0)), throwsArgumentError);
    expect(() => lxAes(_u('x'), 'aes-256-cbc', _u('0123456789abcdef'), Uint8List(16)), throwsArgumentError);
  });

  test('RSA 无填充：SPKI / PKCS#1 公钥都能用，结果与 Node publicEncrypt 一致', () {
    expect(base64Encode(lxRsaNoPadding(_u('lyra-rsa-test'), _spki)), _rsa);
    expect(base64Encode(lxRsaNoPadding(_u('lyra-rsa-test'), _pkcs1)), _rsa);
  });

  test('随机字节长度受限', () {
    expect(base64Decode(lxNative('random', '16')).length, 16);
    expect(base64Decode(lxNative('random', '999999')).length, 65536);
  });

  test('zlib 往返', () {
    final z = lxZlib('deflate', base64Encode(_u('lyra lyra lyra')));
    expect(utf8.decode(base64Decode(lxZlib('inflate', z))), 'lyra lyra lyra');
  });

  test('HTTP：表单 / JSON / 原始字节，响应体能解析 JSON 就解析', () async {
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      return http.Response(r.url.path == '/json' ? '{"ok":1}' : 'plain', 200, headers: {'x-a': 'b'});
    });
    final a = jsonDecode(await lxHttp(client, 'https://t.test/json', {'method': 'post', 'form': {'a': 1, 'b': null}, 'headers': {'X-K': 2}}));
    expect(a['response']['statusCode'], 200);
    expect(a['response']['body'], {'ok': 1});
    expect(utf8.decode(base64Decode(a['response']['raw'])), '{"ok":1}');
    expect(seen.last.method, 'POST');
    expect(seen.last.body, 'a=1');
    expect(seen.last.headers['X-K'], '2');
    final b = jsonDecode(await lxHttp(client, 'https://t.test/x', {'method': 'POST', 'body': {'k': 'v'}}));
    expect(b['response']['body'], 'plain');
    expect(jsonDecode(seen.last.body), {'k': 'v'});
    expect(seen.last.headers['content-type'], startsWith('application/json'));
    final bad = jsonDecode(await lxHttp(client, 'file:///etc/passwd', const {}));
    expect(bad['error'], isNotNull);
  });
}
