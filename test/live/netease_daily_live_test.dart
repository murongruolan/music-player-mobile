// 网易云每日推荐 / 私人 FM 联网冒烟。LIVE=1 时运行。
// 没有账号：只能验证游客 Cookie 下私人 FM 能不能拿到歌，以及每日推荐在未登录时返回 301。
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/login/netease_login.dart';
import 'package:lyra/platform/netease.dart';
import 'live_util.dart';

void main() {
  test('netease daily / fm live', () async {
    final http = liveHttp();
    final p = NeteasePlatform(http);
    final anon = await probe('anonymous cookie', () => NeteaseLogin(http).anonymousCookie(), (c) => c.isEmpty ? '空' : '${c.length} 字符，含 MUSIC_A=${c.contains('MUSIC_A=')}');
    for (var i = 1; i <= 3; i++) {
      await probe('personalFm 游客 #$i', () => p.personalFm(anon ?? ''), (l) => '${l.length} 首：${l.map((t) => '${t.title}-${t.artist}').join('，')}');
    }
    await probe('personalFm 无 Cookie', () => p.personalFm(''), (l) => '${l.length} 首：${l.map((t) => t.title).join('，')}');
    await probe('dailySongs 游客（应当 301）', () => p.dailySongs(anon ?? ''), (l) => '${l.length} 首');
  }, skip: !live);
}
