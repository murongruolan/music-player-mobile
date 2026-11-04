// DLNA/UPnP 投屏：SSDP 设备发现 + AVTransport SOAP 控制。纯 Dart，零第三方依赖
//（UPnP 协议本身 = UDP 组播发现 + HTTP/SOAP 控制，dart:io + http + xml 即可覆盖）。
//
// 支持：MediaRenderer 发现 → 投放（SetAVTransportURI + Play）→ 播放/暂停/停止/拖动 →
// 进度与状态轮询（GetPositionInfo / GetTransportInfo）。
// 声音由渲染端（电视/音箱）自行拉流播放，要求取流 URL 对局域网可见（平台直链 / 音源脚本直链均满足）。

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const _ssdpAddr = '239.255.255.250';
const _ssdpPort = 1900;
const _avtService = 'urn:schemas-upnp-org:service:AVTransport:1';

/// 局域网里发现的一台 DLNA 渲染设备。
class DlnaDevice {
  final String name; // friendlyName
  final String udn; // USN 去掉 :: 后缀，唯一标识
  final String location; // 设备描述 XML 的 URL
  final String controlUrl; // AVTransport SOAP 控制地址
  final String? modelName;

  const DlnaDevice({
    required this.name,
    required this.udn,
    required this.location,
    required this.controlUrl,
    this.modelName,
  });

  @override
  bool operator ==(Object other) => other is DlnaDevice && other.udn == udn;
  @override
  int get hashCode => udn.hashCode;

  @override
  String toString() => 'DlnaDevice($name, $modelName)';
}

class CastException implements Exception {
  final String message;
  const CastException(this.message);
  @override
  String toString() => message;
}

class Dlna {
  Dlna._();

  /// 组播 M-SEARCH 发现局域网内的 MediaRenderer。返回按名称排序、USN 去重后的设备列表。
  /// 超时后逐台拉取描述 XML 解析 friendlyName / AVTransport 控制地址；单台失败不影响其余。
  static Future<List<DlnaDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException catch (e) {
      throw CastException('无法监听本地 UDP 端口（$e）');
    }
    final seen = <String, String>{}; // udn → location
    try {
      // MediaRenderer 直查 + rootdevice 兜底（部分固件只应答 rootdevice / ssdp:all）
      socket.send(_mSearch('urn:schemas-upnp-org:device:MediaRenderer:1'), InternetAddress(_ssdpAddr), _ssdpPort);
      socket.send(_mSearch('upnp:rootdevice'), InternetAddress(_ssdpAddr), _ssdpPort);
      final sub = socket.listen((event) {
        final dg = socket.receive();
        if (dg == null) return;
        final hit = parseSsdpResponse(String.fromCharCodes(dg.data));
        if (hit != null) seen[hit.$1] = hit.$2;
      });
      await Future<void>.delayed(timeout);
      sub.cancel();
    } finally {
      socket.close();
    }
    if (seen.isEmpty) return const [];

    final devices = await Future.wait(
      seen.entries.map((e) async {
        try {
          return await describe(e.value, fallbackUdn: e.key);
        } on Exception {
          return null; // 单台解析失败跳过
        }
      }),
    );
    final out = devices.whereType<DlnaDevice>().toList();
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// 一条 M-SEARCH 报文。
  static Uint8List _mSearch(String st) {
    final text = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_ssdpAddr:$_ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $st\r\n'
        '\r\n';
    return Uint8List.fromList(text.codeUnits);
  }

  /// 解析 SSDP 响应：返回 (USN, LOCATION)。非 200 响应 / 缺字段 / 纯 ContentDirectory 返回 null。
  static (String, String)? parseSsdpResponse(String raw) {
    final upper = raw.toUpperCase();
    if (!upper.startsWith('HTTP/1.1 200') && !upper.startsWith('HTTP/1.0 200')) return null;
    final location = _header(raw, 'LOCATION');
    final usn = _header(raw, 'USN');
    if (location == null || usn == null) return null;
    if (!isLanUrl(location)) return null; // 只跟进局域网地址：别的设备伪造的公网 LOCATION 不去请求
    final st = (_header(raw, 'ST') ?? '').toLowerCase();
    if (st.contains('contentdirectory') && !st.contains('mediarenderer')) return null;
    final udn = usn.split('::').first.trim();
    return (udn.isEmpty ? location : udn, location);
  }

  /// 设备描述地址必须是 http(s) 且主机是局域网 IPv4（10/8、172.16/12、192.168/16、169.254/16）。
  static bool isLanUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return false;
    final p = u.host.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
  }

  static String? _header(String raw, String name) {
    for (final line in raw.split('\r\n')) {
      final i = line.indexOf(':');
      if (i > 0 && line.substring(0, i).trim().toUpperCase() == name) return line.substring(i + 1).trim();
    }
    return null;
  }

  /// 拉取设备描述 XML：friendlyName + AVTransport 的 controlURL。
  static Future<DlnaDevice> describe(String location, {required String fallbackUdn}) async {
    final res = await http.get(Uri.parse(location)).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) throw CastException('设备描述请求失败（${res.statusCode}）');
    return deviceFromDescription(res.body, location: location, fallbackUdn: fallbackUdn);
  }

  /// 解析设备描述 XML（纯函数，测试覆盖）。
  static DlnaDevice deviceFromDescription(String xmlText, {required String location, required String fallbackUdn}) {
    final doc = XmlDocument.parse(xmlText);
    final root = doc.findAllElements('device').firstOrNull;
    if (root == null) throw const CastException('设备描述里没有 device 节点');
    final name = root.findElements('friendlyName').firstOrNull?.innerText.trim() ?? fallbackUdn;
    final model = root.findElements('modelName').firstOrNull?.innerText.trim();
    String? control;
    for (final svc in root.findAllElements('service')) {
      final type = svc.findElements('serviceType').firstOrNull?.innerText.trim() ?? '';
      if (type == _avtService) {
        final raw = svc.findElements('controlURL').firstOrNull?.innerText.trim() ?? '';
        if (raw.isNotEmpty) control = Uri.parse(location).resolve(raw).toString();
        break;
      }
    }
    if (control == null) throw const CastException('设备不支持 AVTransport（不是可投放的渲染端）');
    return DlnaDevice(name: name, udn: fallbackUdn, location: location, modelName: model, controlUrl: control);
  }

  // ------------------------------------------------------------ SOAP 控制

  /// 投放：SetAVTransportURI + Play。
  static Future<void> cast({required String controlUrl, required String uri, String? title, String? artist}) async {
    final didl = _didl(title: title ?? '未知曲目', artist: artist ?? '', uri: uri.toString());
    await _avt(
      controlUrl,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>${xmlEscape(uri.toString())}</CurrentURI>'
      '<CurrentURIMetaData>${xmlEscape(didl)}</CurrentURIMetaData>',
    );
    await play(controlUrl);
  }

  static Future<void> play(String controlUrl) => _avt(controlUrl, 'Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');
  static Future<void> pause(String controlUrl) => _avt(controlUrl, 'Pause', '<InstanceID>0</InstanceID>');
  static Future<void> stop(String controlUrl) => _avt(controlUrl, 'Stop', '<InstanceID>0</InstanceID>');

  /// 拖动到 [seconds]。渲染端对非法时间通常忽略，不需要客户端校验精度。
  static Future<void> seek(String controlUrl, double seconds) =>
      _avt(controlUrl, 'Seek', '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>${formatClock(seconds)}</Target>');

  /// 轮询：返回 (transportState, position, duration)。解析失败返回 0 / UNKNOWN，由调用方决定重试或断开。
  static Future<({String state, double position, double duration})> pollInfo(String controlUrl) async {
    final info = await _avt(controlUrl, 'GetPositionInfo', '<InstanceID>0</InstanceID>');
    final pos = clockToSeconds(_tag(info, 'RelTime'));
    final dur = clockToSeconds(_tag(info, 'TrackDuration'));
    final state = await _avt(controlUrl, 'GetTransportInfo', '<InstanceID>0</InstanceID>');
    return (state: _tag(state, 'CurrentTransportState') ?? 'UNKNOWN', position: pos, duration: dur);
  }

  /// 音量（RenderingControl 的 controlURL 与 AVTransport 不同时会失败，调用方静默降级）。
  static Future<void> setVolume({required String controlUrl, required int volume}) => _avt(
        controlUrl,
        'SetVolume',
        '<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>${volume.clamp(0, 100)}</DesiredVolume>',
        service: 'urn:schemas-upnp-org:service:RenderingControl:1',
      );

  // ------------------------------------------------------------ 内部

  static Future<String> _avt(String controlUrl, String action, String argsXml, {String service = _avtService}) async {
    final body =
        '<?xml version="1.0" encoding="utf-8" standalone="no"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$service">$argsXml</u:$action></s:Body></s:Envelope>';
    http.Response res;
    try {
      res = await http
          .post(Uri.parse(controlUrl), headers: {
            'SOAPACTION': '"$service#$action"',
            'Content-Type': 'text/xml; charset="utf-8"',
          }, body: body)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw CastException('设备响应超时');
    } on SocketException catch (e) {
      throw CastException('设备连接失败（$e）');
    }
    if (res.statusCode != 200) throw CastException('设备返回 ${res.statusCode}');
    return res.body;
  }

  static String? _tag(String xmlText, String tag) {
    final m = RegExp('<$tag[^>]*>([^<]*)</$tag>').firstMatch(xmlText);
    return m?.group(1)?.trim();
  }

  /// DIDL-Lite 元数据（最小集：标题 + 艺术家 + 音频类型）。多数渲染端缺省也能播。
  static String _didl({required String title, required String artist, required String uri}) => ''
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${xmlEscape(title)}</dc:title>'
      '<dc:creator>${xmlEscape(artist)}</dc:creator>'
      '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
      '<res protocolInfo="http-get:*:audio/*:*">${xmlEscape(uri)}</res>'
      '</item></DIDL-Lite>';

  /// XML 文本转义（URI / 标题里可能带 & 等）。
  static String xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 秒 → H:MM:SS（UPnP clock 格式，小时不补零与多数设备一致）。
  static String formatClock(double seconds) {
    final s = seconds < 0 ? 0 : seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// H:MM:SS(.ms) → 秒；解析失败 / Not available 返回 0。
  static double clockToSeconds(String? clock) {
    if (clock == null || clock.isEmpty || clock.toUpperCase().contains('NOT')) return 0;
    final parts = clock.split(':');
    if (parts.length < 3) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = double.tryParse(parts[2]) ?? 0;
    return h * 3600 + m * 60 + s;
  }
}

/// 防御辅助：把任意 num 夹到 [lo, hi]（dlna 内部的进度外推用）。
double clampDouble(double v, double lo, double hi) => math.max(lo, math.min(v, hi));
