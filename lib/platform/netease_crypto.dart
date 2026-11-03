// 网易云接口加密：weapi（网页端）、eapi（客户端）、linuxapi（Linux 客户端转发）。
// 算法和常量与桌面端 platform-crypto.ts 逐字节一致（测试里有用 Node 跑原实现得到的向量）。
import 'dart:convert';
import 'dart:typed_data';
import 'crypto_util.dart';

const _presetKey = '0CoJUm6Qyw8W8jud';
const _iv = '0102030405060708';
const _eapiKey = 'e82ckenh8dichen8';
const _linuxKey = 'rFgB&h#%2?^eDg:Q';
const _base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// weapi RSA 公钥（1024 位，e = 65537）。模数取自桌面端 PEM：
/// MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
final _modulus = BigInt.parse(
  'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
  radix: 16,
);
final _exponent = BigInt.from(65537);

/// 16 位随机密钥：随机字节 % 62 映射到 base62 字符（与桌面端相同，有轻微取模偏差，无所谓）。
String neteaseRandomSecret() => String.fromCharCodes(randomBytes(16).map((b) => _base62.codeUnitAt(b % 62)));

/// payload 序列化：字符串原样使用，其它 jsonEncode（与 JSON.stringify 输出一致：不转义中文，保持键顺序）。
String _text(Object? payload) => payload is String ? payload : jsonEncode(payload);

/// weapi：两次 AES-128-CBC（先预置密钥、再随机密钥）+ 随机密钥反转后做无填充 RSA。
/// 返回 `params=...&encSecKey=...` 表单字符串。[secret] 仅供测试固定随机数（16 个 ASCII 字符）。
String weapi(Object? payload, {String? secret}) {
  final key = secret ?? neteaseRandomSecret();
  final first = base64Encode(aesCbcEncrypt(_text(payload), _presetKey, _iv));
  final params = base64Encode(aesCbcEncrypt(first, key, _iv));
  // 桌面端把 secret 反转后左侧补 0 到 128 字节再 RSA_NO_PADDING，等价于把反转后的字节当大端整数做 m^e mod n
  final reversed = Uint8List.fromList(utf8.encode(key).reversed.toList());
  final encSecKey = hexLower(rsaNoPadding(reversed, _modulus, _exponent, size: 128));
  return 'params=${Uri.encodeQueryComponent(params)}&encSecKey=$encSecKey';
}

/// eapi：`url-36cd479b6b5-text-36cd479b6b5-md5("nobody{url}use{text}md5forencrypt")` 做 AES-128-ECB，大写十六进制。
/// [url] 是 `/api/...` 形式的接口路径（不是实际请求的 `/eapi/...` 地址）。返回 `params=HEX`。
String eapi(String url, Object? payload) => 'params=${eapiParams(url, payload)}';

String eapiParams(String url, Object? payload) {
  final text = _text(payload);
  final digest = md5Hex('nobody${url}use${text}md5forencrypt');
  return hexUpper(aesEcbEncrypt('$url-36cd479b6b5-$text-36cd479b6b5-$digest', _eapiKey));
}

/// linuxapi：整个 `{method, url, params}` 做 AES-128-ECB，大写十六进制。返回 `eparams=HEX`。
String linuxapi(Object? payload) => 'eparams=${hexUpper(aesEcbEncrypt(_text(payload), _linuxKey))}';

/// 解出 eapi 明文（测试 / 调试用）：返回 `(url, payload 文本)`；格式不对返回 null。
({String url, String text})? eapiDecode(String hex) {
  final plain = utf8.decode(aesEcbDecrypt(hexDecode(hex), _eapiKey), allowMalformed: true);
  final parts = plain.split('-36cd479b6b5-');
  if (parts.length != 3) return null;
  return (url: parts[0], text: parts[1]);
}
