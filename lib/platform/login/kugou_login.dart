// 酷狗登录：手机验证码登录 + token 刷新。对齐原版 App（kugou_account_service / kugou_crypto）。
//
// 信封（登录两接口 login_by_verifycode / login_by_token）：
//   公共参数 + plat/t1/t2/t3 + clienttime_ms + key(paramsKey) + params(随机AES密文) + pk(RSA({clienttime_ms,key}))，
//   最后 signature = md5( join(排序后的 "k=v") + 盐 )。
//   响应里的 data 用 paramsKey 作 seed 的 AES-CBC 解出明文（{token,userid,vip_type,...}）。
//
// 人机验证（发验证码返回 ssa-code 时）：原版会用 sid/edt 走 get_verify_info 预检。这里不复刻传感器指纹，
// 遇到就提示用户去酷狗官方 App 完成验证后重试（见 KugouCaptchaRequired）。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import '../../net/json.dart';
import '../credentials.dart';
import '../crypto_util.dart';
import '../http.dart';
import '../models.dart';

const _kgSalt = 'OIlwieks28dk2k092lksi2UIkp';
const _kgUa = 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';
const _kgCharset = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// 登录信封 RSA（1024 位，e=65537），只加密 {clienttime_ms, key}。
final BigInt _kgRsaMod = BigInt.parse(
    'c8006ed03842d2628209bd314984ca5ed6cfe06e30c95f9d4704d9c49791d7a935ba950ecb0bc8ebf5f5994f0bac927a7eb151b3c1de343303fa539c83136eccfd7d7e511e2dbce18eaa9f784c9b50d443e75865979e0a5e216e46c684066a8d6b998580bbaa22d73f5790286bb14742e83244e44db6d707ffe162c5c7002d45',
    radix: 16);
final BigInt _kgRsaExp = BigInt.from(65537);

/// 固定信封的服务端对称密钥：md5("1005" + 盐 + "20489")。
String kugouParamsKey() => md5Hex('1005$_kgSalt' '20489');

/// 登录信封签名：按 key 字典序拼 `k=v`（非 String 值先 jsonEncode），尾接盐取 MD5。
String kugouLoginSignature(Map<String, Object?> params) {
  final keys = params.keys.toList()..sort();
  final buf = StringBuffer();
  for (final k in keys) {
    final v = params[k];
    buf.write('$k=${v == null ? '' : (v is String ? v : jsonEncode(v))}');
  }
  buf.write(_kgSalt);
  return md5Hex(buf.toString());
}

/// 随机 AES：seed 的 md5 前 16 当 key、后 16 当 IV，CBC 加密 JSON → base64。返回 (密文, key, iv)。
({String cipher, String key, String iv}) kugouAesEncrypt(Object data, Random random) {
  final seed = List.generate(16 + random.nextInt(9), (_) => _kgCharset[random.nextInt(_kgCharset.length)]).join();
  final digest = md5Hex(seed);
  final key = digest.substring(0, 16), iv = digest.substring(16);
  return (cipher: base64.encode(aesCbcEncrypt(jsonEncode(data), key, iv)), key: key, iv: iv);
}

/// 用 seed 的 md5（前16 key、后16 iv）AES-CBC 解 hex 密文 → 明文字符串。
String kugouAesDecrypt(String cipherHex, String seed) {
  final digest = md5Hex(seed);
  return utf8.decode(aesCbcDecrypt(hexDecode(cipherHex), digest.substring(0, 16), digest.substring(16)), allowMalformed: true);
}

/// 裸 RSA（m^e mod n）→ 小写 hex。
String kugouRsaRawEncrypt(Object data) {
  final text = data is String ? data : jsonEncode(data);
  final bytes = utf8.encode(text);
  if (bytes.length > 128) throw const PlatformException(Plat.kg, 'RSA 数据长度超过密钥长度');
  return hexLower(rsaNoPadding(Uint8List.fromList(bytes), _kgRsaMod, _kgRsaExp, size: 128));
}

/// 设备指纹：mid / uuid 为随机数字串，dfid 由随机字符串派生。
class KugouDevice {
  final String mid, dfid;
  KugouDevice(this.mid, this.dfid);
  factory KugouDevice.random(Random r) {
    String digits(int n) => List.generate(n, (_) => r.nextInt(10)).join();
    final raw = List.generate(24, (_) => _kgCharset[r.nextInt(_kgCharset.length)]).join();
    return KugouDevice(digits(16), md5Hex(raw).substring(0, 24));
  }

  Map<String, Object?> defaultParams() => {
        'dfid': dfid,
        'mid': mid,
        'uuid': '$mid-$dfid',
        'appid': '1005',
        'clientver': '20489',
        'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
}

/// 发验证码返回了 ssa-code（需要人机验证）时抛出。
class KugouCaptchaRequired implements Exception {
  const KugouCaptchaRequired();
  @override
  String toString() => '需要人机验证';
}

class KugouLogin {
  final PlatformHttp http;
  final Random _random;
  KugouLogin(this.http, {Random? random}) : _random = random ?? Random.secure();

  static final _mobileRe = RegExp(r'^1\d{10}$');

  /// 把业务字段包进固定信封（defaultParams + signature），JSON POST。发验证码 / 校验等走这个。
  Future<Json> _postPlain(String url, KugouDevice device, Map<String, Object?> fields) async {
    final params = <String, Object?>{...device.defaultParams(), ...fields};
    params['signature'] = kugouLoginSignature(params);
    return asJson(await http.json(Plat.kg, 'POST', Uri.parse(url),
        headers: {'User-Agent': _kgUa, 'Content-Type': 'application/json'}, body: jsonEncode(params)));
  }

  /// ① 发送验证码。号码非法抛 PlatformException；返回 ssa-code 抛 [KugouCaptchaRequired]。
  Future<void> sendCode(String mobileRaw, KugouDevice device) async {
    final mobile = mobileRaw.replaceAll(RegExp(r'\s+'), '');
    if (!_mobileRe.hasMatch(mobile)) throw const PlatformException(Plat.kg, '请输入正确的手机号');
    final j = await _postPlain('http://login.user.kugou.com/v7/send_mobile_code', device, {'businessid': 5, 'mobile': mobile, 'plat': 3});
    if (j['ssa-code'] != null && '${j['ssa-code']}'.isNotEmpty && '${j['ssa-code']}' != '0') throw const KugouCaptchaRequired();
    final status = (j['status'] as num?)?.toInt() ?? (j['error_code'] == null ? 1 : 0);
    if (status != 1 && j['error_code'] != null && '${j['error_code']}' != '0') {
      throw PlatformException(Plat.kg, _msg(j, '验证码发送失败'));
    }
  }

  /// ② 验证码登录。
  Future<PlatformCredential> loginByCode(String mobileRaw, String code, KugouDevice device) async {
    final mobile = mobileRaw.replaceAll(RegExp(r'\s+'), '');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final paramsKey = kugouParamsKey();
    final aes = kugouAesEncrypt({'mobile': mobile, 'code': code}, _random);
    final masked = mobile.length >= 11 ? '${mobile.substring(0, 3)}*****${mobile.substring(10)}' : mobile;
    final body = <String, Object?>{
      ...device.defaultParams(),
      'plat': 1,
      'support_multi': 1,
      't1': 0,
      't2': 0,
      't3': 'MCwwLDAsMCwwLDAsMCwwLDA=',
      'clienttime_ms': nowMs,
      'mobile': masked,
      'key': paramsKey,
      'params': aes.cipher,
      'pk': kugouRsaRawEncrypt({'clienttime_ms': nowMs, 'key': aes.key}),
    };
    body['signature'] = kugouLoginSignature(body);
    final j = asJson(await http.json(Plat.kg, 'POST', Uri.parse('https://loginserviceretry.kugou.com/v7/login_by_verifycode'),
        headers: {'User-Agent': _kgUa, 'Content-Type': 'application/json'}, body: jsonEncode(body)));
    return _credFrom(j, paramsKey, device);
  }

  PlatformCredential _credFrom(Json j, String paramsKey, KugouDevice device) {
    final err = '${j['error_code'] ?? j['status'] ?? '1'}';
    if (err != '0' && err != '1') throw PlatformException(Plat.kg, _msg(j, '酷狗登录失败'));
    // data 可能是密文（用 paramsKey 解）或已是明文对象
    Json inner;
    final data = j['data'];
    if (data is Map) {
      inner = asJson(data);
    } else if (data is String && data.isNotEmpty) {
      inner = asJson(jsonDecode(kugouAesDecrypt(data, paramsKey)));
    } else {
      throw PlatformException(Plat.kg, _msg(j, '酷狗登录失败'));
    }
    final token = '${inner['token'] ?? ''}';
    final userId = '${inner['userid'] ?? inner['user_id'] ?? ''}';
    if (token.isEmpty || userId.isEmpty || userId == '0') throw const PlatformException(Plat.kg, '酷狗登录失败：返回里没有 token');
    final vipType = '${inner['vip_type'] ?? inner['su_vip_y'] ?? ''}';
    final vipToken = '${inner['vip_token'] ?? ''}';
    final nickname = '${inner['nickname'] ?? inner['nick_name'] ?? inner['username'] ?? ''}';
    final avatar = '${inner['pic'] ?? inner['avatar'] ?? inner['img'] ?? ''}';
    final ts = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final cookie = 'KugooID=$userId; userid=$userId; t=$ts; token=$token; t1=$ts; dfid=${device.dfid}; mid=${device.mid}; vip_type=$vipType; vip_token=$vipToken';
    final isVip = vipType.isNotEmpty && vipType != '0';
    return PlatformCredential(
      platform: Plat.kg,
      cookie: cookie,
      userId: userId,
      nickname: nickname.isEmpty ? '酷狗用户' : nickname,
      avatarUrl: avatar.isEmpty ? null : avatar.replaceFirst('{size}', '150'),
      isVip: isVip,
      vipLabel: isVip ? '酷狗 VIP' : null,
      extra: {
        CredKey.kgToken: token,
        if (vipToken.isNotEmpty) CredKey.kgVipToken: vipToken,
        CredKey.kgDfid: device.dfid,
        CredKey.kgMid: device.mid,
      },
      savedAt: DateTime.now(),
    );
  }

  static String _msg(Json j, String fallback) {
    final m = '${j['error_msg'] ?? j['data'] ?? j['msg'] ?? ''}';
    return m.isEmpty || m == 'null' ? fallback : m;
  }
}
