// 平台登录接口的联网冒烟：LIVE=1 flutter test test/live/login_live_test.dart
// 不需要账号：只验证接口地址、加密和返回格式对得上（取二维码 key、轮询得到「等待扫码」、游客 Cookie、
// 无效 Cookie 被正确识别为未登录）。只有「取二维码 key」失败算测试失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/login/netease_login.dart';
import 'package:lyra/platform/login/qq_login.dart';
import 'live_util.dart';

void main() {
  test('netease login live', () async {
    final l = NeteaseLogin(liveHttp());
    final key = await probe('qrKey', l.qrKey, (k) => 'unikey 长度 ${k.length}', required: true);
    if (key != null) {
      await probe('qrCheck (未扫码)', () => l.qrCheck(key), (r) => '${r.state} ${r.message}');
    }
    await probe('anonymousCookie', l.anonymousCookie, (c) => '含 MUSIC_A：${c.contains('MUSIC_A=')}，键 ${c.split(';').length} 个');
    await probe('credentialFrom (无效 Cookie)', () => l.credentialFrom('MUSIC_U=invalid; __csrf=x'), (c) => '意外成功：${c.nickname}');
  }, skip: !live, timeout: const Timeout(Duration(minutes: 2)));

  test('qq login live', () async {
    final l = QqLogin(liveHttp());
    await probe('credentialFrom (无效 Cookie)', () => l.credentialFrom('uin=o0010001; euin=abc; qm_keyst=invalid'), (c) => '意外成功：${c.nickname}');
  }, skip: !live, timeout: const Timeout(Duration(minutes: 2)));
}
