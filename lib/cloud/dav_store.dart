// 音乐云盘的服务器列表：地址、账号、音乐目录，连同密码一起存系统钥匙串（Net.store），只留在本机。
// 云盘里的歌登记进歌曲目录时，平台记为 `dav`，歌曲 id = `<服务器 id>|<文件路径>`；播放时由 MusicResolver
// 换成带 Basic 认证头的地址（见 [DavStore.playOf]）。
import 'dart:convert';
import 'dart:math';
import '../net/storage.dart';
import '../sync/cloud_models.dart';
import 'webdav.dart';

/// 平台代码：云盘歌曲。
const davPlatform = 'dav';

class DavServer {
  final String id, name, url, user, root;
  const DavServer({required this.id, required this.name, required this.url, required this.user, this.root = '/'});

  String get host => Uri.tryParse(WebDavClient.normalizeBase(url).toString())?.host ?? url;

  DavServer copyWith({String? name, String? root}) => DavServer(id: id, name: name ?? this.name, url: url, user: user, root: root ?? this.root);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'url': url, 'user': user, 'root': root};
  static DavServer? fromJson(Object? j) {
    if (j is! Map || j['id'] == null || j['url'] == null) return null;
    return DavServer(id: '${j['id']}', name: '${j['name'] ?? ''}', url: '${j['url']}', user: '${j['user'] ?? ''}', root: '${j['root'] ?? '/'}');
  }
}

/// 常见服务的预设：名称、默认地址、填写提示。
const davProviders = <(String, String, String)>[
  ('坚果云', 'https://dav.jianguoyun.com/dav/', '坚果云要用「应用密码」，不能用登录密码：网页版 → 账户信息 → 安全选项 → 第三方应用管理 → 添加应用。'),
  ('Alist', 'https://', '地址填 Alist 的地址加 /dav/，例如 https://alist.example.com/dav/；账号要在 Alist 后台开 WebDAV 读取权限。'),
  ('Nextcloud', 'https://', '地址形如 https://你的域名/remote.php/dav/files/用户名/；开了两步验证的账号要用应用密码。'),
  ('群晖', 'https://', '先在套件中心启用「WebDAV Server」：https 端口 5006，例如 https://nas.local:5006/。外网访问需要 DDNS 或端口转发。'),
  ('威联通', 'https://', '控制台 → 网络与文件服务 → WebDAV 中启用，并给共享文件夹开 WebDAV 权限。'),
  ('自定义', 'https://', '任何标准 WebDAV 服务都可以。服务器要支持 Range 请求，才能拖动进度条。'),
];

class DavStore {
  final KvStore? _store;
  final void Function() _changed;
  DavStore(this._store, this._changed);

  static const _k = 'dav.servers.v1';
  final _servers = <DavServer>[];
  final _passwords = <String, String>{};

  List<DavServer> get servers => List.unmodifiable(_servers);
  DavServer? byId(String id) => _servers.where((s) => s.id == id).firstOrNull;

  Future<void> load() async {
    final s = _store;
    if (s == null) return;
    try {
      final j = jsonDecode(await s.read(_k) ?? '{}');
      if (j is! Map) return;
      _servers
        ..clear()
        ..addAll((j['servers'] as List? ?? const []).map(DavServer.fromJson).whereType<DavServer>());
      final p = j['passwords'];
      if (p is Map) _passwords.addAll({for (final e in p.entries) '${e.key}': '${e.value}'});
    } catch (_) {
      // 数据损坏：当作没有服务器
    }
  }

  /// 新建服务器 id。
  static String newId() => 'd${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 16).toRadixString(36)}';

  Future<void> save(DavServer server, {String? password}) async {
    final i = _servers.indexWhere((s) => s.id == server.id);
    i < 0 ? _servers.add(server) : _servers[i] = server;
    if (password != null) _passwords[server.id] = password;
    await _persist();
  }

  Future<void> remove(String id) async {
    _servers.removeWhere((s) => s.id == id);
    _passwords.remove(id);
    await _persist();
  }

  Future<void> _persist() async {
    _changed();
    await _store?.write(_k, jsonEncode({'servers': [for (final s in _servers) s.toJson()], 'passwords': _passwords}));
  }

  /// 服务器的客户端；服务器不存在时返回 null。
  WebDavClient? clientOf(String serverId) {
    final s = byId(serverId);
    if (s == null) return null;
    return WebDavClient(s.url, s.user, _passwords[s.id] ?? '');
  }

  /// 云盘文件 → 歌曲目录里的曲目（歌名 / 歌手从文件名猜，专辑用所在文件夹名）。
  static CloudTrack trackOf(DavServer s, DavEntry e) {
    final parts = e.path.split('/').where((x) => x.isNotEmpty).toList();
    final folder = parts.length >= 2 ? parts[parts.length - 2] : s.name;
    final folderArtist = folder.contains(' - ') ? folder.substring(0, folder.indexOf(' - ')).trim() : '';
    final g = guessTitleArtist(e.name, fallbackArtist: folderArtist);
    final songId = '${s.id}|${e.path}';
    return CloudTrack(
      id: '$davPlatform:$songId',
      platform: davPlatform,
      songId: songId,
      title: g.title,
      artist: g.artist.isEmpty ? '云盘' : g.artist,
      album: folder,
      raw: {'qualities': [e.ext == 'flac' || e.ext == 'wav' ? 'flac' : '320k'], 'dav': {'server': s.id, 'path': e.path, 'size': e.size}},
    );
  }

  /// 云盘歌曲的播放地址 + 认证头。服务器已删除时返回 null。
  ({Uri uri, Map<String, String> headers})? playOf(CloudTrack t) {
    final i = t.songId.indexOf('|');
    if (i <= 0) return null;
    final c = clientOf(t.songId.substring(0, i));
    if (c == null) return null;
    return (uri: c.urlOf(t.songId.substring(i + 1)), headers: c.authHeaders);
  }
}
