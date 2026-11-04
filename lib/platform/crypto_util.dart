// 平台接口用到的基础加密工具（纯 Dart，Web 也能编译）。各平台特有的签名放在各自文件里。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

String md5Hex(Object input) => c.md5.convert(_bytes(input)).toString();
String sha1Hex(Object input) => c.sha1.convert(_bytes(input)).toString();

Uint8List _bytes(Object input) => input is String ? Uint8List.fromList(utf8.encode(input)) : Uint8List.fromList(input as List<int>);

Uint8List _pkcs7(Uint8List data) {
  final pad = 16 - data.length % 16;
  return Uint8List.fromList([...data, ...List.filled(pad, pad)]);
}

Uint8List _unpad(Uint8List data) {
  if (data.isEmpty) return data;
  final p = data.last;
  return p > 0 && p <= 16 && p <= data.length ? Uint8List.sublistView(data, 0, data.length - p) : data;
}

Uint8List _run(BlockCipher cipher, Uint8List input) {
  final out = Uint8List(input.length);
  for (var o = 0; o < input.length; o += 16) {
    cipher.processBlock(input, o, out, o);
  }
  return out;
}

/// AES-128-ECB，PKCS7 填充。
Uint8List aesEcbEncrypt(Object plain, Object key) {
  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(_bytes(key)));
  return _run(cipher, _pkcs7(_bytes(plain)));
}

Uint8List aesEcbDecrypt(Uint8List data, Object key) {
  final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(_bytes(key)));
  return _unpad(_run(cipher, data));
}

/// AES-128-CBC，PKCS7 填充。
Uint8List aesCbcEncrypt(Object plain, Object key, Object iv) {
  final cipher = CBCBlockCipher(AESEngine())..init(true, ParametersWithIV(KeyParameter(_bytes(key)), _bytes(iv)));
  return _run(cipher, _pkcs7(_bytes(plain)));
}

/// AES-128-CBC 解密，去 PKCS7 填充。
Uint8List aesCbcDecrypt(Uint8List data, Object key, Object iv) {
  final cipher = CBCBlockCipher(AESEngine())..init(false, ParametersWithIV(KeyParameter(_bytes(key)), _bytes(iv)));
  return _unpad(_run(cipher, data));
}

/// 无填充 RSA（m^e mod n），网易 weapi 用。[data] 按大端整数处理，输出 [size] 字节。
Uint8List rsaNoPadding(Uint8List data, BigInt modulus, BigInt exponent, {int size = 128}) {
  var m = BigInt.zero;
  for (final b in data) {
    m = (m << 8) | BigInt.from(b);
  }
  var r = m.modPow(exponent, modulus);
  final out = Uint8List(size);
  for (var i = size - 1; i >= 0; i--) {
    out[i] = (r & BigInt.from(0xff)).toInt();
    r = r >> 8;
  }
  return out;
}

String hexUpper(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
String hexLower(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List hexDecode(String hex) => Uint8List.fromList([for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

/// zlib 解压（酷狗 KRC 等）。
Uint8List inflateZlib(List<int> data) => Uint8List.fromList(ZLibDecoder().decodeBytes(data));

final _rand = Random.secure();
Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rand.nextInt(256)));
