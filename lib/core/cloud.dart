// 账号云服务的总控：同步引擎、云备份、听歌统计。AppState 持有一个 [Cloud]。
//
// 实时同步什么时候开：已登录 + 赞助用户 + 「多端实时同步」开关打开。任一条件变化都会重新判断。
// 演示模式（没有 Net）：引擎为 null，听歌统计只记在内存里，页面展示 mock 数据。
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../api/sync_api.dart';
import '../net/net.dart';
import '../sync/docs.dart';
import '../sync/sync_doc.dart';
import '../sync/sync_engine.dart';
import 'listening_stats.dart';
import 'settings_sync.dart';
import 'state.dart';

class Cloud with WidgetsBindingObserver {
  final AppState _app;
  late final ListeningStats stats;
  late final SettingsDoc _settingsDoc;
  SyncEngine? engine;

  /// 音乐库 / 音源脚本接入后由内容层设置（见 [bindLibrary] / [bindSources]）。
  LibraryBinding? _library;
  SourcesBinding? _sources;

  String? _settingsFp;
  int? _statSong;
  bool _observing = false;

  Cloud(this._app) {
    if (_app.net != null) {
      _library = _app.library;
      _app.library.onLocalChange = () => libraryChanged();
      _sources = _app.sources;
      _app.sources.onLocalChange = () => sourcesChanged();
    }
    stats = ListeningStats(_app.net?.prefs, _app.notify);
    _settingsDoc = SettingsDoc(() => exportSettings(_app), (j) {
      if (importSettings(_app, j)) {
        _settingsFp = fingerprint(_settingsDoc.export()); // 别把云端刚下来的设置当成本机修改再推回去
        _app.notify();
      }
    });
    final n = _app.net;
    if (n != null) engine = _buildEngine(n);
  }

  SyncEngine _buildEngine(Net n) {
    final lib = LibraryDoc(_library), favs = FavoritesDoc(_library), pls = PlaylistsDoc(_library), src = SourcesDoc(_sources);
    final e = SyncEngine(client: n.client, prefs: n.prefs, docs: [_settingsDoc, lib, favs, pls, StatsDoc(stats), src]);
    // 内容层的本机修改 → 对应文档的防抖推送（只有实时文档会真的推，其余由用户手动上传）
    _libraryChanged = () {
      lib.onLocalChange?.call();
      favs.onLocalChange?.call();
      pls.onLocalChange?.call();
    };
    _sourcesChanged = () => src.onLocalChange?.call();
    return e;
  }

  void Function()? _libraryChanged, _sourcesChanged;

  /// 内容层（音乐库 / 音源脚本）本机修改后调用。
  void libraryChanged() => _libraryChanged?.call();
  void sourcesChanged() => _sourcesChanged?.call();

  /// 各文档（界面上列出来用）。
  List<SyncDoc> get docs => engine?.docs.values.toList() ?? const [];
  ValueNotifier<SyncStatus>? get status => engine?.status;

  /// 启动时调用（main 里）：读本地统计、注册前后台监听。
  Future<void> init() async {
    await stats.load();
    if (_app.net != null) {
      await _app.library.load();
      await _app.sources.load();
    }
    _settingsFp = fingerprint(_settingsDoc.export());
    if (_app.net != null && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    evaluate();
  }

  /// 登录状态、会员状态、开关变化后调用：该开就开，该关就关。
  void evaluate() {
    final e = engine;
    if (e == null) return;
    final want = _app.authed && (_app.net?.session.isLoggedIn ?? false) && _app.isSponsor && _app.set.cloudSync;
    if (want && !e.running) {
      unawaited(e.start());
    } else if (!want && e.running) {
      unawaited(e.stop(phase: _app.authed && !_app.isSponsor ? SyncPhase.needSponsor : SyncPhase.off));
    } else if (!want && !_app.isSponsor && _app.authed && e.status.value.phase != SyncPhase.needSponsor) {
      e.status.value = e.status.value.copy(phase: SyncPhase.needSponsor);
    }
  }

  /// AppState 每次 notifyListeners 后调用：检测设置变化。
  void onAppChanged() {
    final e = engine;
    if (e == null) return;
    final fp = fingerprint(_settingsDoc.export());
    if (fp != _settingsFp) {
      _settingsFp = fp;
      _settingsDoc.onLocalChange?.call();
    }
  }

  /// 播放进度推进时调用（AppState._tick）。
  void onPlayTick(int songId, double sec) {
    if (_statSong != songId) {
      _statSong = songId;
      final s = _app.songById(songId);
      final key = s.key;
      if (key != null && key.contains(':')) {
        _app.library.rememberPlayed(songId); // 「最近」页重启后还有封面
        final i = key.indexOf(':');
        stats.begin(key: key, source: key.substring(0, i), songId: key.substring(i + 1), name: s.title, artist: s.artist, album: s.album, durationSec: s.dur);
      } else {
        // mock 歌曲：source 记为 mock，只在本机统计，不上传
        stats.begin(key: 'mock:${s.id}', source: 'mock', songId: '${s.id}', name: s.title, artist: s.artist, album: s.album, durationSec: s.dur);
      }
    }
    stats.tick(sec);
  }

  /// 退出登录：停止同步并清掉同步进度。听歌统计是本机数据，保留。
  Future<void> reset() async => engine?.reset();

  // ---------------------------------------------------------------- 内容层接入

  void bindLibrary(LibraryBinding b) {
    _library = b;
    _rebuild();
  }

  void bindSources(SourcesBinding b) {
    _sources = b;
    _rebuild();
  }

  void _rebuild() {
    final n = _app.net;
    if (n == null) return;
    final old = engine;
    engine = _buildEngine(n);
    if (old != null) {
      unawaited(old.stop().then((_) => old.dispose()));
    }
    evaluate();
  }

  // ---------------------------------------------------------------- 云备份

  BackupApi get _backup => BackupApi(_app.api.client);

  /// 整体快照。格式与桌面端相近（listening_stats / lx_sources / library 结构相同），移动端设置放在 mobileSettings。
  Json snapshot() => {
        'version': 2,
        'client': 'lyra-mobile',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mobileSettings': exportSettings(_app),
        'listening_stats': stats.toPayload(),
        if (_library != null) 'library': _library!.read().toPayload(),
        if (_sources != null) 'lx_sources': SourcesDoc(_sources).export(),
      };

  Future<BackupMeta> backupNow() => _backup.upload(snapshot());

  Future<List<BackupMeta>> backups() => _backup.list();

  /// 恢复一份备份：设置、听歌统计用备份覆盖；音乐库 / 音源接入后同样覆盖。
  /// 返回恢复了哪些部分。实时同步开着时，恢复后把设置推上去（以备份为准）。
  Future<List<String>> restore(int id) async {
    final (_, payload) = await _backup.get(id);
    final j = asJson(payload);
    if (j.isEmpty) throw const ApiException(ApiErrorKind.business, '这份备份是空的');
    final done = <String>[];
    final ms = j.objOrNull('mobileSettings');
    if (ms != null) {
      importSettings(_app, ms);
      _settingsFp = null; // 让下一次 onAppChanged 当作本机修改推上去
      done.add('设置');
    }
    final st = j['listening_stats'];
    if (st != null) {
      stats.apply(st, replace: true);
      done.add('听歌统计');
    }
    if (_library != null && j['library'] != null) {
      LibraryDoc(_library).apply(j['library'], replace: true);
      done.add('音乐库');
    }
    if (_sources != null && j['lx_sources'] != null) {
      SourcesDoc(_sources).apply(j['lx_sources'], replace: true);
      done.add('音源脚本');
    }
    _app.notify();
    return done;
  }

  // ---------------------------------------------------------------- 听歌统计

  /// 清除听歌记录：本机清空；赞助用户同时把云端换成空文档（各端下次同步时以合并规则为准，
  /// 所以要彻底清掉，其他设备也需要各自清除）。
  Future<void> clearStats({bool cloud = true}) async {
    await stats.clear();
    final e = engine;
    if (cloud && e != null && _app.isSponsor) {
      await e.pushPayload(DocType.listeningStats, stats.toPayload());
    }
  }

  // ---------------------------------------------------------------- 前后台

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) engine?.resumed();
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      engine?.paused();
      unawaited(stats.flush());
    }
  }

  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    stats.dispose();
    engine?.dispose();
  }
}
