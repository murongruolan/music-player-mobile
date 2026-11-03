// lx.utils 在 Dart 侧的实现：md5 / AES / RSA（无填充）/ 随机字节 / zlib，以及 lx.request 的 HTTP。
// 行为对齐桌面端 source-worker.ts（Node crypto / zlib）与 source-manager.ts#handleHttp。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import '../platform/crypto_util.dart' as cu;

/// 同步操作：参数和返回值都是字符串（字节用 base64）。
String lxNative(String op, String arg) {
  switch (op) {
    case 'md5':
      return cu.md5Hex(base64Decode(arg));
    case 'random':
      return base64Encode(cu.randomBytes((int.tryParse(arg) ?? 0).clamp(0, 65536)));
    case 'aes':
      final a = jsonDecode(arg) as Map<String, dynamic>;
      return base64Encode(lxAes(base64Decode(a['data'] as String), a['mode'] as String, base64Decode(a['key'] as String), base64Decode((a['iv'] as String?) ?? '')));
    case 'rsa':
      final a = jsonDecode(arg) as Map<String, dynamic>;
      return base64Encode(lxRsaNoPadding(base64Decode(a['data'] as String), a['key'] as String));
  }
  throw ArgumentError('unsupported op $op');
}

/// Node `createCipheriv(mode, key, iv)` + 默认 PKCS7 填充。支持 aes-{128,192,256}-{cbc,ecb}。
Uint8List lxAes(Uint8List data, String mode, Uint8List key, Uint8List iv) {
  final m = RegExp(r'^aes-(128|192|256)-(cbc|ecb)$').firstMatch(mode.toLowerCase());
  if (m == null) throw ArgumentError('不支持的加密模式：$mode');
  if (key.length * 8 != int.parse(m[1]!)) throw ArgumentError('密钥长度与 $mode 不符');
  return m[2] == 'ecb' ? cu.aesEcbEncrypt(data, key) : cu.aesCbcEncrypt(data, key, iv);
}

/// Node `publicEncrypt({key, padding: RSA_NO_PADDING}, 左侧补零到 128 字节的 data)`。
Uint8List lxRsaNoPadding(Uint8List data, String pem) {
  final (n, e) = parseRsaPublicKey(pem);
  final size = (n.bitLength + 7) >> 3;
  if (data.length > size) throw ArgumentError('数据比 RSA 密钥长');
  final padded = Uint8List(size)..setRange(size - data.length, size, data);
  return cu.rsaNoPadding(padded, n, e, size: size);
}

/// PEM 公钥 → (模数, 指数)。支持 `BEGIN PUBLIC KEY`（SPKI）与 `BEGIN RSA PUBLIC KEY`（PKCS#1）。
(BigInt, BigInt) parseRsaPublicKey(String pem) {
  final body = pem.replaceAll(RegExp(r'-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), '');
  final der = base64Decode(body);
  final r = _Der(der);
  var seq = r.read(0x30);
  final first = _Der(seq);
  final tag = der.length > 2 ? first.peekTag() : -1;
  if (tag == 0x30) {
    // SPKI：SEQUENCE { SEQUENCE algo, BIT STRING { SEQUENCE { n, e } } }
    first.read(0x30);
    final bits = first.read(0x03);
    seq = _Der(Uint8List.sublistView(bits, 1)).read(0x30);
  }
  final ints = _Der(seq);
  final n = _big(ints.read(0x02)), e = _big(ints.read(0x02));
  return (n, e);
}

BigInt _big(Uint8List b) => b.fold(BigInt.zero, (v, x) => (v << 8) | BigInt.from(x));

class _Der {
  final Uint8List b;
  int i = 0;
  _Der(this.b);
  int peekTag() => b[i];
  Uint8List read(int tag) {
    if (b[i] != tag) throw const FormatException('公钥格式不正确');
    i++;
    var len = b[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i++];
      }
    }
    final out = Uint8List.sublistView(b, i, i + len);
    i += len;
    return out;
  }
}

/// zlib inflate / deflate（与 Node zlib 一致：带 zlib 头）。
String lxZlib(String op, String b64) {
  final data = base64Decode(b64);
  if (op == 'inflate') return base64Encode(ZLibDecoder().decodeBytes(data));
  if (op == 'deflate') return base64Encode(ZLibEncoder().encodeBytes(data));
  throw ArgumentError('unsupported zlib op $op');
}

/// lx.request 的 HTTP。返回桥上的 JSON：{response:{statusCode,statusMessage,headers,bytes,body,raw}} 或 {error}。
Future<String> lxHttp(http.Client client, String url, Map<String, dynamic> options) async {
  try {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) throw const FormatException('Blocked URL');
    final method = (options['method'] is String ? options['method'] as String : 'GET').toUpperCase();
    final headers = <String, String>{
      if (options['headers'] is Map) for (final e in (options['headers'] as Map).entries) '${e.key}': '${e.value}',
    };
    final timeoutMs = options['timeout'] is num ? (options['timeout'] as num).toInt().clamp(1000, 60000) : 15000;
    final raw = options['body'] ?? options['form'] ?? options['formData'];
    http.BaseRequest req;
    if (options['formData'] is Map) {
      final mr = http.MultipartRequest(method, u);
      for (final e in (raw as Map).entries) {
        if (e.value != null) mr.fields['${e.key}'] = '${e.value}';
      }
      req = mr;
    } else {
      final r = http.Request(method, u);
      if (options['form'] is Map) {
        r.bodyFields = {for (final e in (raw as Map).entries) if (e.value != null) '${e.key}': '${e.value}'};
      } else if (raw is Map && raw['__b64'] is String) {
        r.bodyBytes = base64Decode(raw['__b64'] as String);
      } else if (raw is String) {
        r.body = raw;
      } else if (raw != null) {
        r.body = jsonEncode(raw);
        if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) headers['Content-Type'] = 'application/json';
      }
      req = r;
    }
    req.headers.addAll(headers);
    final res = await client.send(req).then(http.Response.fromStream).timeout(Duration(milliseconds: timeoutMs));
    final bytes = res.bodyBytes;
    final text = utf8.decode(bytes, allowMalformed: true);
    Object? body = text;
    try {
      body = jsonDecode(text);
    } catch (_) {}
    return jsonEncode({
      'response': {
        'statusCode': res.statusCode,
        'statusMessage': res.reasonPhrase ?? '',
        'headers': res.headers,
        'bytes': bytes.length,
        'body': body,
        // 原始字节只在不太大时带上（脚本偶尔用来解析二进制）
        if (bytes.length <= 2 * 1024 * 1024) 'raw': base64Encode(bytes),
      },
    });
  } on TimeoutException {
    return jsonEncode({'error': '请求超时'});
  } catch (e) {
    return jsonEncode({'error': e is FormatException ? e.message : '$e'});
  }
}
