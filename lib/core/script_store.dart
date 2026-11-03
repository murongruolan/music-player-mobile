// 音源脚本（洛雪 lx 自定义源）的本机存储：导入、解析头部信息、删除、持久化、lx_sources 云同步。
//
// 脚本头部是 JSDoc 注释：@name / @description / @version / @author / @homepage。
// 支持的平台和音质以运行脚本（lx.send('inited', {sources})）的结果为准（[SourceManager]，lib/source/）；
// 还没运行过的脚本先从源码里按 `kw: {` / `"tx":` 之类的写法粗略识别。
import 'dart:async';
import 'dart:convert';
import '../data/models.dart';
import '../net/storage.dart';
import '../sync/cloud_models.dart';
import '../source/lx_runtime.dart';
import '../source/lx_track.dart';
import '../source/source_manager.dart';
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

  static const _k = 'sources.v1', _kCaps = 'sources.caps.v1';
  static const maxBytes = 2 * 1024 * 1024;

  /// 脚本运行实例与播放地址解析。
  late final SourceManager manager = SourceManager()..onChanged = _capsChanged;

  /// 上次运行得到的能力（脚本 id → 平台 → 能力），持久化，启动时不用先跑脚本就能显示。
  final _caps = <String, Map<String, LxCapability>>{};

  ScriptStore(this._app, this._prefs);

  String? get activeId => _activeId;
  Map<String, LxCapability>? capsOf(String id) => manager.capabilities[id] ?? _caps[id];
  String? initErrorOf(String id) => manager.initErrors[id];

  /// 播放时尝试的顺序：手动选中的脚本（app.script）→ 当前音源 → 其它。
  List<CloudSource> forPlayback() {
    final out = <CloudSource>[];
    void add(String? id) {
      final s = id == null ? null : byId(id);
      if (s != null && !out.contains(s)) out.add(s);
    }

    if (_app.script != 'auto') add(_app.script);
    add(_activeId);
    for (final s in _sources) {
      add(s.id);
    }
    return out;
  }

  void setActive(String id) {
    if (byId(id) == null) return;
    _activeId = id;
    for (var i = 0; i < _sources.length; i++) {
      final s = _sources[i];
      if (s.isActive != (s.id == id)) _sources[i] = CloudSource(id: s.id, name: s.name, rawScript: s.rawScript, description: s.description, version: s.version, author: s.author, homepage: s.homepage, sourceUrl: s.sourceUrl, isActive: s.id == id, addedAt: s.addedAt, raw: s.raw);
    }
    _changed();
  }

  /// 记下校验时得到的能力（导入前已经跑过一次脚本）。
  void rememberCaps(String id, Map<String, LxCapability> caps) {
    _caps[id] = caps;
    _refreshApp();
    unawaited(_saveCaps());
  }

  void _capsChanged() {
    _caps.addAll(manager.capabilities);
    _refreshApp();
    unawaited(_saveCaps());
  }

  Future<void> _saveCaps() async {
    await _prefs?.write(_kCaps, jsonEncode({for (final e in _caps.entries) e.key: {for (final c in e.value.entries) c.key: c.value.toJson()}}));
  }

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
    manager.stop(id);
    _caps.remove(id);
    unawaited(_saveCaps());
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
            final caps = capsOf(s.id);
            if (caps != null) {
              final plats = [for (final e in caps.entries) if (_codeToPlat[e.key] != null && e.value.actions.contains('musicUrl')) _codeToPlat[e.key]!];
              final qs = <String>{for (final c in caps.values) for (final q in c.qualities) appQualityOf(q)};
              const order = ['128k', 'HQ', 'SQ', 'Hi-Res', 'Dolby', 'Atmos'];
              return Script(s.id, s.name, s.version.isEmpty ? '-' : s.version, plats, [for (final q in order) if (qs.contains(q)) q], 0, 0);
            }
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
    try {
      final c = await _prefs?.read(_kCaps);
      if (c != null) {
        for (final e in (jsonDecode(c) as Map).entries) {
          _caps['${e.key}'] = {
            for (final p in (e.value as Map).entries)
              '${p.key}': LxCapability('${(p.value as Map)['name'] ?? p.key}', [for (final a in (p.value as Map)['actions'] as List? ?? const []) '$a'], [for (final q in (p.value as Map)['qualities'] as List? ?? const []) '$q']),
          };
        }
      }
    } catch (_) {}
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
    manager.dispose();
    _caps.clear();
    await _prefs?.delete(_kCaps);
    _sources.clear();
    _activeId = null;
    _refreshApp();
    await _prefs?.delete(_k);
  }
}
