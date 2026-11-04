// WebDAV 客户端（RFC 4918 的最小子集）：测试连接、列目录（PROPFIND Depth: 1）、拼带认证的播放地址。
// 坚果云 / Alist / Nextcloud / 群晖 / 威联通都是标准 WebDAV，只用 Basic 认证。
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 云盘支持播放的音频扩展名（平台播放器能直接解码的）。
const davAudioExts = {'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus'};

/// 目录里的一项。
class DavEntry {
  /// 相对服务器根地址的路径（已解码），目录以 `/` 结尾。
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;
  const DavEntry({required this.path, required this.name, required this.isDir, this.size = 0, this.modified});

  String get ext {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isAudio => !isDir && davAudioExts.contains(ext);
}

/// 连接测试 / 请求失败的类别。
enum DavErrorKind { auth, notFound, notDav, cert, network, other }

class DavException implements Exception {
  final DavErrorKind kind;
  final String message;
  const DavException(this.kind, this.message);
  @override
  String toString() => message;
}

class WebDavClient {
  /// 服务器根地址，如 `https://dav.jianguoyun.com/dav/`（总是以 `/` 结尾）。
  final Uri base;
  final String user, password;
  final http.Client? _given;
  final Duration timeout;

  /// 真正发请求时才建（只拼播放地址时用不到）。
  late final http.Client _http = _given ?? http.Client();

  WebDavClient(String url, this.user, this.password, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : base = normalizeBase(url),
        _given = client;

  /// 规范化根地址：补 https、去掉多余空白、结尾补 `/`。
  static Uri normalizeBase(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    if (!u.endsWith('/')) u = '$u/';
    return Uri.parse(u);
  }

  /// Basic 认证头。播放云盘歌曲时引擎也要带上它。
  Map<String, String> get authHeaders => {'Authorization': 'Basic ${base64.encode(utf8.encode('$user:$password'))}'};

  /// 相对路径 → 完整地址（逐段编码，中文和空格都能用）。
  Uri urlOf(String path) {
    final segs = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    final dir = path.endsWith('/') && segs.isNotEmpty ? '/' : '';
    return base.resolve(segs.isEmpty ? '' : '$segs$dir');
  }

  /// 测试连接：能列出 [path]（默认根目录）就算成功。返回耗时（毫秒）。
  Future<int> test([String path = '/']) async {
    final sw = Stopwatch()..start();
    await list(path);
    return sw.elapsedMilliseconds;
  }

  /// 列出目录 [path]（相对根地址，如 `/Music/`）下的文件和子目录，不含目录自身。
  /// 目录在前、文件在后，各自按名称排序。
  Future<List<DavEntry>> list(String path) async {
    final dirPath = path.endsWith('/') ? path : '$path/';
    final url = urlOf(dirPath);
    final req = http.Request('PROPFIND', url)
      ..headers.addAll({...authHeaders, 'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'})
      ..body = '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:displayname/></d:prop></d:propfind>';
    http.Response res;
    try {
      res = await _http.send(req).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const DavException(DavErrorKind.network, '连接超时：检查地址和端口；手机和 NAS 不在同一局域网时需要外网地址');
    } catch (e) {
      final m = '$e';
      if (m.contains('CERTIFICATE') || m.contains('HandshakeException')) {
        throw const DavException(DavErrorKind.cert, '服务器证书不受信任（自签名证书暂不支持，请用有正规证书的地址）');
      }
      throw DavException(DavErrorKind.network, '连不上服务器：${m.length > 80 ? m.substring(0, 80) : m}');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const DavException(DavErrorKind.auth, '账号或密码不正确（坚果云要用「应用密码」，不能用登录密码）');
    }
    if (res.statusCode == 404) throw const DavException(DavErrorKind.notFound, '目录不存在，检查地址或音乐目录');
    if (res.statusCode == 405 || res.statusCode == 501) throw const DavException(DavErrorKind.notDav, '这个地址不是 WebDAV 服务（检查是否漏了 /dav/ 之类的路径）');
    if (res.statusCode != 207 && res.statusCode != 200) throw DavException(DavErrorKind.other, '服务器返回 ${res.statusCode}');
    return parseMultistatus(utf8.decode(res.bodyBytes, allowMalformed: true), base, dirPath);
  }

  /// 解析 PROPFIND 的 207 Multi-Status。[dirPath] 是被列出的目录（会从结果里去掉）。
  static List<DavEntry> parseMultistatus(String body, Uri base, String dirPath) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      throw const DavException(DavErrorKind.notDav, '服务器返回的不是 WebDAV 目录列表');
    }
    String? text(XmlElement e, String local) => e.descendants.whereType<XmlElement>().where((x) => x.name.local == local).firstOrNull?.innerText.trim();
    final basePath = Uri.decodeFull(base.path);
    final self = _norm(basePath + dirPath.replaceFirst(RegExp(r'^/'), ''));
    final out = <DavEntry>[];
    for (final r in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
      final href = text(r, 'href');
      if (href == null || href.isEmpty) continue;
      var p = hrefPath(href);
      if (_norm(p) == self) continue; // 目录自身
      final isDir = r.descendants.whereType<XmlElement>().any((x) => x.name.local == 'collection');
      // 转成相对根地址的路径
      if (p.startsWith(basePath)) p = '/${p.substring(basePath.length)}';
      if (isDir && !p.endsWith('/')) p = '$p/';
      final trimmed = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
      final name = trimmed.substring(trimmed.lastIndexOf('/') + 1);
      if (name.isEmpty || name.startsWith('.')) continue; // 隐藏文件（.DS_Store 等）
      out.add(DavEntry(
        path: p,
        name: name,
        isDir: isDir,
        size: int.tryParse(text(r, 'getcontentlength') ?? '') ?? 0,
        modified: _httpDate(text(r, 'getlastmodified')),
      ));
    }
    out.sort((a, b) => a.isDir != b.isDir ? (a.isDir ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static String _norm(String p) => p.endsWith('/') ? p : '$p/';

  /// href → 解码后的路径。不用 Uri.parse：有的服务器（如 Alist）文件名里的 `#` `?` 不编码，
  /// Uri.parse 会把它们当成片段 / 查询截掉，文件名就丢了扩展名。
  static String hrefPath(String href) {
    var h = href.trim();
    final m = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*').firstMatch(h);
    if (m != null) h = h.substring(m.end);
    if (!h.startsWith('/')) h = '/$h';
    try {
      return Uri.decodeComponent(h.replaceAll('+', '%2B'));
    } catch (_) {
      return h; // 编码不合法（含裸 %）：原样用
    }
  }

  static DateTime? _httpDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return HttpDateParser.parse(s);
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_given == null) _http.close();
  }
}

/// RFC 1123 日期（`Tue, 04 Nov 2026 10:09:32 GMT`）。解析失败抛异常，由调用方吞掉。
abstract final class HttpDateParser {
  static const _m = {'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12};
  static DateTime parse(String s) {
    final p = s.replaceAll(',', '').split(RegExp(r'\s+'));
    final t = p[4].split(':').map(int.parse).toList();
    return DateTime.utc(int.parse(p[3]), _m[p[2]]!, int.parse(p[1]), t[0], t[1], t[2]);
  }
}

/// 从文件名猜歌名 / 歌手：`歌手 - 歌名.flac` 或 `01. 歌名.flac`。猜不出歌手时用 [fallbackArtist]。
({String title, String artist}) guessTitleArtist(String fileName, {String fallbackArtist = ''}) {
  var base = fileName;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.replaceFirst(RegExp(r'^\d{1,3}\s*[.\-_、]\s*'), '').trim(); // 去掉曲目序号
  final i = base.indexOf(' - ');
  if (i > 0) return (title: base.substring(i + 3).trim(), artist: base.substring(0, i).trim());
  return (title: base, artist: fallbackArtist);
}
