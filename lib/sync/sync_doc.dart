// 一种同步文档（docType）在本机的读写方式。同步引擎只和它打交道，不关心具体数据结构。
//
// 载荷格式要与桌面端 / 原版移动端一致（同一个账号多端互通），见各实现文件的注释。
import 'dart:convert';

abstract class SyncDoc {
  /// docType：settings / library / playlists / favorites / listening_stats / lx_sources
  String get type;

  /// 界面上显示的名字。
  String get label;

  /// 本机数据是否已经接入。没接入（例如音乐库还是 mock）时引擎不会读写它，避免把假数据推到云端。
  bool get available => true;

  /// 本机没有任何数据（首次同步时，云端为空且本机也为空就不用推）。
  bool get isEmpty;

  /// 导出本机数据作为推送载荷。
  Object export();

  /// 应用云端载荷。
  /// [replace] = true：用云端覆盖本机（手动「从云端恢复」）；false：与本机合并。
  /// 返回 true 表示合并后本机还有云端没有的数据，需要再推一次。
  bool apply(Object? remote, {bool replace = false});

  /// 本机数据变化时调用（引擎订阅它做防抖推送）。
  void Function()? onLocalChange;
}

/// 稳定的 JSON 指纹：键排序后做 FNV-1a（两个种子拼成 64 位十六进制）。
/// 顶层的 exportedAt 不参与（每次导出都会变）。
String fingerprint(Object? payload) {
  var p = payload;
  if (p is Map && p.containsKey('exportedAt')) p = {...p}..remove('exportedAt');
  final s = utf8.encode(_stable(p));
  int h1 = 0x811c9dc5, h2 = 0x01000193 ^ 0x5bd1e995;
  for (final b in s) {
    h1 = ((h1 ^ b) * 0x01000193) & 0xffffffff;
    h2 = ((h2 ^ b) * 0x01000193) & 0xffffffff;
    h2 = ((h2 << 5) | (h2 >> 27)) & 0xffffffff;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
}

String _stable(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_stable(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_stable).join(',')}]';
  return jsonEncode(v);
}
