import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyra/cloud/dav_store.dart';
import 'package:lyra/cloud/webdav.dart';
import 'package:lyra/net/storage.dart';
import 'package:lyra/sync/cloud_models.dart';

// Nextcloud 风格：根地址带路径，href 是绝对路径且中文 / 空格已编码
const _multistatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
 <d:response><d:href>/remote.php/dav/files/ali/Music/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/ali/Music/%E6%97%A0%E6%8D%9F/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/ali/Music/%E9%9B%BE%E6%B8%AF%20-%20%E5%A4%9C%E8%88%AA%E6%98%9F%E5%9B%BE.flac</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>98400000</d:getcontentlength>
  <d:getlastmodified>Tue, 04 Nov 2026 10:09:32 GMT</d:getlastmodified></d:prop></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/ali/Music/cover.jpg</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>2000</d:getcontentlength></d:prop></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/ali/Music/.DS_Store</d:href>
  <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
</d:multistatus>''';

void main() {
  final base = WebDavClient.normalizeBase('https://cloud.example.com/remote.php/dav/files/ali');

  test('根地址补 / 和 https', () {
    expect(base.toString(), 'https://cloud.example.com/remote.php/dav/files/ali/');
    expect(WebDavClient.normalizeBase('nas.local:5006').toString(), 'https://nas.local:5006/');
  });

  test('解析 Multi-Status：去掉目录自身和隐藏文件，路径相对根地址并解码', () {
    final l = WebDavClient.parseMultistatus(_multistatus, base, '/Music/');
    expect(l.map((e) => e.name), ['无损', 'cover.jpg', '雾港 - 夜航星图.flac']);
    expect(l.first.isDir, isTrue);
    expect(l.first.path, '/Music/无损/');
    final song = l.last;
    expect(song.path, '/Music/雾港 - 夜航星图.flac');
    expect(song.isAudio, isTrue);
    expect(song.size, 98400000);
    expect(song.modified, DateTime.utc(2026, 11, 4, 10, 9, 32));
    expect(l[1].isAudio, isFalse);
  });

  test('urlOf 逐段编码中文和空格', () {
    final c = WebDavClient('https://dav.jianguoyun.com/dav/', 'u', 'p');
    expect(c.urlOf('/音乐/a b.flac').toString(), 'https://dav.jianguoyun.com/dav/%E9%9F%B3%E4%B9%90/a%20b.flac');
    expect(c.urlOf('/').toString(), 'https://dav.jianguoyun.com/dav/');
    expect(c.authHeaders['Authorization'], 'Basic ${base64.encode(utf8.encode('u:p'))}');
  });

  test('PROPFIND 请求：Depth 1 + Basic；401 → 账号密码错误', () async {
    late http.BaseRequest seen;
    final ok = WebDavClient('https://cloud.example.com/remote.php/dav/files/ali/', 'ali', 'pw', client: MockClient((r) async {
      seen = r;
      return http.Response(_multistatus, 207, headers: {'content-type': 'application/xml; charset=utf-8'});
    }));
    final l = await ok.list('/Music');
    expect(seen.method, 'PROPFIND');
    expect(seen.headers['Depth'], '1');
    expect(seen.url.path, '/remote.php/dav/files/ali/Music/');
    expect(l.length, 3);

    final bad = WebDavClient('https://x.example/', 'a', 'b', client: MockClient((_) async => http.Response('', 401)));
    await expectLater(bad.list('/'), throwsA(isA<DavException>().having((e) => e.kind, 'kind', DavErrorKind.auth)));
    final notDav = WebDavClient('https://x.example/', 'a', 'b', client: MockClient((_) async => http.Response('', 405)));
    await expectLater(notDav.list('/'), throwsA(isA<DavException>().having((e) => e.kind, 'kind', DavErrorKind.notDav)));
  });

  test('文件名猜歌名 / 歌手', () {
    expect(guessTitleArtist('雾港 - 夜航星图.flac'), (title: '夜航星图', artist: '雾港'));
    expect(guessTitleArtist('01. 星尘信件.flac', fallbackArtist: '雾港'), (title: '星尘信件', artist: '雾港'));
    expect(guessTitleArtist('无题.mp3'), (title: '无题', artist: ''));
  });

  test('DavStore：密码存钥匙串，曲目 → 带认证的播放地址；删服务器后播不了', () async {
    final kv = MemoryKvStore();
    final store = DavStore(kv, () {});
    const s = DavServer(id: 'd1', name: '家里的 NAS', url: 'https://nas.local:5006/', user: 'ali', root: '/Music/');
    await store.save(s, password: 'pw');
    final again = DavStore(kv, () {});
    await again.load();
    expect(again.servers.single.name, '家里的 NAS');

    final t = DavStore.trackOf(s, const DavEntry(path: '/Music/雾港 - 远光/01. 夜航星图.flac', name: '01. 夜航星图.flac', isDir: false));
    expect(t.platform, davPlatform);
    expect(t.title, '夜航星图');
    expect(t.artist, '雾港'); // 从文件夹名「雾港 - 远光」取
    expect(t.album, '雾港 - 远光');
    final p = again.playOf(t)!;
    expect(p.uri.toString(), startsWith('https://nas.local:5006/Music/'));
    expect(p.headers['Authorization'], 'Basic ${base64.encode(utf8.encode('ali:pw'))}');

    await again.remove('d1');
    expect(again.playOf(t), isNull);
  });

  test('云盘歌曲只存本机：不进云同步，合并时也不丢', () {
    const s = DavServer(id: 'd1', name: 'NAS', url: 'https://nas.local/', user: 'u');
    final dav = DavStore.trackOf(s, const DavEntry(path: '/a.flac', name: 'a.flac', isDir: false));
    const wy = CloudTrack(id: 'wy:1', platform: 'wy', songId: '1', title: 't', artist: 'a');
    final lib = CloudLibrary(favorites: [dav, wy]);
    final sync = lib.toPayload() as Map;
    expect(((sync['items'] as Map)['tracks'] as List).length, 1);
    final local = lib.toPayload(keepDav: true) as Map;
    expect(((local['items'] as Map)['tracks'] as List).length, 2);
    // 远端只有 wy:1：本机多出来的云盘歌曲不算需要推送
    expect(CloudLibrary.mergeFavorites([dav, wy], [wy]).$2, isFalse);
    // 远端歌单更新时，本机歌单里的云盘歌曲接回去
    final t0 = DateTime.utc(2026, 1, 1), t1 = DateTime.utc(2026, 2, 1);
    final mine = CloudPlaylist(id: 'p', name: 'x', tracks: [wy, dav], updatedAt: t0, createdAt: t0);
    final theirs = CloudPlaylist(id: 'p', name: 'x2', tracks: [wy], updatedAt: t1, createdAt: t0);
    final merged = CloudLibrary.mergePlaylists([mine], [theirs]).$1.single;
    expect(merged.name, 'x2');
    expect(merged.tracks.map((t) => t.id), ['wy:1', dav.id]);
  });
}
