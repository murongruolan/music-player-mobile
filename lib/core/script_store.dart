// 音源脚本（洛雪 lx 自定义源）的本机存储：导入、解析头部信息、删除、持久化、lx_sources 云同步。
//
// 脚本头部是 JSDoc 注释：@name / @description / @version / @author / @homepage。
// 支持的平台和音质只有运行脚本（lx.send('inited', {sources})）才能确定；运行时还没接入，
// 这里先从源码里按 `kw: {` / `"tx":` 之类的写法粗略识别，界面上标注「以运行结果为准」。
import 'dart:async';
import 'dart:convert';
import '../data/models.dart';
import '../net/storage.dart';
import '../sync/cloud_models.dart';
import '../sync/docs.dart';
import 'state.dart';

/// 云端平台代码 → App 内平台 id。
const _codeToPlat = {'wy': 'netease', 'tx': 'qq', 'kg': 'kugou', 'kw': 'kuwo', 'mg': 'migu'};

class ParsedScript {
  final String name, version, author, description, homepage;
  final List<String> platforms, qualities;
  const ParsedScript({required this.name, required this.version, this.author = '', this.description = '', this.homepage = '', this.platforms = const [], this.qualities = const []});

  /// 解析失败（不像脚本）时返回 null。
  static ParsedScript? parse(String src) {
    if (src.trim().length < 20) return null;
    final looksJs = RegExp(r'(function|=>|lx\.|EVENT_NAMES|module\.exports|const |let |var )').hasMatch(src);
    if (!looksJs) return null;
    String tag(String k) => RegExp('@$k[ \\t]+([^\\r\\n]*)').firstMatch(src)?.group(1)?.trim().replaceAll(RegExp(r'\*+/$'), '').trim() ?? '';
    final plats = <String>[];
    for (final e in _codeToPlat.entries) {
      if (RegExp('(^|[\\s{,])["\']?${e.key}["\']?\\s*:\\s*\\{').hasMatch(src)) plats.add(e.value);
    }
    final q = <String>{};
    if (RegExp(r'128k|320k').hasMatch(src)) q.add('HQ');
    if (RegExp(r'\bflac\b|"flac"|' "'flac'").hasMatch(src)) q.add('SQ');
    if (src.contains('flac24bit') || src.contains('hires')) q.add('Hi-Res');
    final name = tag('name');
    return ParsedScript(
      name: name.isEmpty ? '未命名音源' : name,
      version: tag('version'),
      author: tag('author'),
      description: tag('description'),
      homepage: tag('homepage'),
      platforms: plats,
      qualities: q.toList(),
    );
  }
}

class ScriptStore implements SourcesBinding {
  final AppState _app;
  final KvStore? _prefs;
  final _sources = <CloudSource>[];
  String? _activeId;

  /// 本机修改后通知同步（lx_sources 是手动同步文档，这里只是标记变化）。
  void Function()? onLocalChange;

  static const _k = 'sources.v1';
  static const maxBytes = 2 * 1024 * 1024;

  ScriptStore(this._app, this._prefs);

  List<CloudSource> get sources => List.unmodifiable(_sources);
  CloudSource? byId(String id) => _sources.where((s) => s.id == id).firstOrNull;

  /// 导入一个脚本。同名同作者的视为更新，覆盖旧的。返回导入后的条目。
  CloudSource add(String raw, ParsedScript meta, {String? sourceUrl}) {
    final old = _sources.where((s) => s.name == meta.name && s.author == meta.author).firstOrNull;
    final s = CloudSource(
      id: old?.id ?? 'user_api_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      name: meta.name,
      rawScript: raw,
      description: meta.description,
      version: meta.version,
      author: meta.author,
      homepage: meta.homepage,
      sourceUrl: sourceUrl ?? old?.sourceUrl,
      isActive: old?.isActive ?? _sources.isEmpty,
      addedAt: old?.addedAt ?? DateTime.now().toUtc(),
      raw: old?.raw ?? const {},
    );
    if (old != null) {
      _sources[_sources.indexOf(old)] = s;
    } else {
      _sources.add(s);
    }
    _activeId ??= s.id;
    _changed();
    return s;
  }

  void remove(String id) {
    _sources.removeWhere((s) => s.id == id);
    if (_activeId == id) _activeId = _sources.firstOrNull?.id;
    _changed();
  }

  // ---------------------------------------------------------------- SourcesBinding

  @override
  (List<CloudSource>, String?) read() => ([..._sources], _activeId);

  @override
  void write(List<CloudSource> sources, String? activeId) {
    _sources
      ..clear()
      ..addAll(sources);
    _activeId = activeId ?? _sources.firstOrNull?.id;
    _refreshApp();
    unawaited(_save());
  }

  // ---------------------------------------------------------------- 内部

  void _changed() {
    _refreshApp();
    unawaited(_save());
    onLocalChange?.call();
  }

  /// 同步到 AppState.scripts（界面用的模型）和每个平台的脚本顺序。
  void _refreshApp() {
    _app.scripts
      ..clear()
      ..addAll([
        for (final s in _sources)
          () {
            final m = ParsedScript.parse(s.rawScript);
            final plats = (m == null || m.platforms.isEmpty) ? _codeToPlat.values.toList() : m.platforms;
            return Script(s.id, s.name, s.version.isEmpty ? '-' : s.version, plats, m?.qualities ?? const [], 0, 0);
          }(),
      ]);
    for (final e in _app.scriptOrder.entries) {
      e.value
        ..clear()
        ..addAll([for (final s in _app.scripts) if (s.platforms.contains(e.key)) s.id]);
    }
    if (_app.script != 'auto' && _app.scripts.every((s) => s.id != _app.script)) _app.script = 'auto';
    _app.notify();
  }

  Future<void> load() async {
    final raw = await _prefs?.read(_k);
    if (raw == null) return;
    try {
      final (l, a) = CloudSource.parse(jsonDecode(raw));
      _sources
        ..clear()
        ..addAll(l);
      _activeId = a;
      _refreshApp();
    } catch (_) {}
  }

  Future<void> _save() async {
    await _prefs?.write(_k, jsonEncode(CloudSource.payload(_sources, _activeId)));
  }

  Future<void> reset() async {
    _sources.clear();
    _activeId = null;
    _refreshApp();
    await _prefs?.delete(_k);
  }
}
