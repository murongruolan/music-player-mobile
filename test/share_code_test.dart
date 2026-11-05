import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/core/share_code.dart';

void main() {
  test('歌曲口令：生成与解析', () {
    final code = songShareCode(platform: 'wy', id: '186016', title: '晴天', artist: '周杰伦');
    expect(code, '[Lyra]V1·wy·186016·晴天-周杰伦');
    final c = parseShareCode('好友：$code 快听') as SongShareCode;
    expect((c.platform, c.id, c.title), ('wy', '186016', '晴天'));
    expect(c.artist, '周杰伦 快听'); // 同一行后面的字算进歌手，只影响展示
  });

  test('歌名带「-」、字段里带分隔符', () {
    final code = songShareCode(platform: 'kg', id: 'ABCDEF0123456789ABCDEF0123456789', title: 'Love-Story·Live', artist: 'A-Lin');
    expect(code, '[Lyra]V1·kg·ABCDEF0123456789ABCDEF0123456789·Love-Story・Live-A-Lin');
    final c = parseShareCode(code) as SongShareCode;
    expect(c.id, 'ABCDEF0123456789ABCDEF0123456789');
    expect(c.title, 'Love-Story・Live-A');
  });

  test('歌单口令', () {
    final code = playlistShareCode(platform: 'tx', id: '8052190267', name: '夜跑\n歌单');
    expect(code, '[Lyra]V1·歌单·tx·8052190267·夜跑 歌单');
    final c = parseShareCode(code) as PlaylistShareCode;
    expect((c.platform, c.id, c.name), ('tx', '8052190267', '夜跑 歌单'));
    expect(shareSig(c), 'pl|tx|8052190267');
  });

  test('不认识的版本 / 平台 / 旧格式不识别', () {
    expect(parseShareCode('[Lyra]V2·wy·1·a-b'), isNull);
    expect(parseShareCode('[Lyra]V1·xx·1·a-b'), isNull);
    expect(parseShareCode('【Lyra歌曲·3·晴天】周杰伦'), isNull);
  });
}
