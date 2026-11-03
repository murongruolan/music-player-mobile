// 云同步引擎（与桌面端 cloud-sync.ts 的语义一致，同一账号多端互通）。
//
// 每种文档在本机记 {revision, fingerprint}（持久化）：
// - 同步一种文档：pull(sinceRevision) → 有变化就 apply（合并）→ 合并后本机还有云端没有的数据，或本机指纹和上次同步时不同 → push。
//   本机从没同步过时 sinceRevision = 0，拿完整快照合并。
// - push：baseRevision = 本机记的 revision。服务端返回冲突时带回远端快照 → 合并 → 用新 revision 再推一次（只重试一次）。
// - 实时：只有 [live] 里的文档（默认 settings、library）自动同步。本机变化防抖 2 秒后推送；
//   WebSocket（/sync/ws）收到其他设备的 {type:"changed", docType, revision} 后拉取。
//   连不上 WebSocket 时退回每 5 分钟拉一次（pull 没变化时服务端只查元数据）。不用 /sync/wait 长轮询（每 20 秒占一个请求，免费额度扛不住）。
// - 其余文档（听歌统计、音源脚本、收藏、歌单）由用户在界面上手动上传 / 恢复。
// - 403 / 40301（非赞助用户）：停止并进入 needSponsor，界面引导激活。
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../api/sync_api.dart';
import '../net/net.dart';
import '../net/rate_limiter.dart' show Clock;
import 'sync_doc.dart';
import 'sync_socket.dart';
import 'ws_stub.dart' if (dart.library.io) 'ws_io.dart' as ws;

enum SyncPhase {
  /// 没开启（未登录 / 关闭了实时同步）。
  off,
  syncing,

  /// 已同步，等待变化。
  idle,

  /// 断网，恢复后自动再试。
  offline,
  error,

  /// 不是赞助用户。
  needSponsor,
}

@immutable
class SyncStatus {
  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? error;

  /// WebSocket 实时通知是否连着。
  final bool realtime;
  const SyncStatus(this.phase, {this.lastSyncAt, this.error, this.realtime = false});

  SyncStatus copy({SyncPhase? phase, DateTime? lastSyncAt, String? error, bool clearError = false, bool? realtime}) =>
      SyncStatus(phase ?? this.phase, lastSyncAt: lastSyncAt ?? this.lastSyncAt, error: clearError ? null : (error ?? this.error), realtime: realtime ?? this.realtime);
}

class DocState {
  int revision;
  String? fingerprint;
  String updatedAt;
  DocState({this.revision = 0, this.fingerprint, this.updatedAt = ''});
  Json toJson() => {'r': revision, 'f': fingerprint, 'u': updatedAt};
  factory DocState.fromJson(Json j) => DocState(revision: j.integer('r'), fingerprint: j.strOrNull('f'), updatedAt: j.str('u'));
}

/// 手动操作的结果，界面用它提示。
class SyncOpResult {
  final bool changed;
  final int revision;
  const SyncOpResult(this.changed, this.revision);
}

class SyncEngine {
  final SyncApi api;
  final ApiClient _client;
  final KvStore _prefs;
  final Map<String, SyncDoc> docs;
  final Set<String> live;
  final SocketConnector _connect;
  final Clock _now;
  final Duration debounce, pollEvery;
  final void Function(String)? log;

  final status = ValueNotifier(const SyncStatus(SyncPhase.off));
  final _state = <String, DocState>{};
  bool _running = false, _loaded = false;
  Future<void> _tail = Future.value();
  final _dirty = <String>{};
  Timer? _debounceT, _pollT, _pingT, _reconnectT;
  SyncSocket? _sock;
  StreamSubscription<String>? _sockSub;
  Duration _wsDelay = const Duration(seconds: 5);
  final _rand = Random();

  static const _key = 'sync.state.v1';

  SyncEngine({
    required ApiClient client,
    required KvStore prefs,
    required List<SyncDoc> docs,
    this.live = const {DocType.settings, DocType.library},
    SocketConnector? connect,
    Clock? now,
    this.debounce = const Duration(seconds: 2),
    this.pollEvery = const Duration(minutes: 5),
    void Function(String)? log,
  })  : api = SyncApi(client),
        _client = client,
        _prefs = prefs,
        docs = {for (final d in docs) d.type: d},
        _connect = connect ?? ws.connectSyncSocket,
        _now = now ?? DateTime.now,
        log = log ?? client.log {
    for (final d in docs) {
      d.onLocalChange = () => _localChanged(d.type);
    }
  }

  bool get running => _running;
  DocState stateOf(String type) => _state[type] ?? DocState();

  // ---------------------------------------------------------------- 生命周期

  /// 开始实时同步：先完整同步一遍 [live] 文档，再连 WebSocket。调用方负责判断已登录、赞助、开关打开。
  Future<void> start() async {
    if (_running) return;
    await _load();
    _running = true;
    await syncLive();
    if (_running) unawaited(_connectWs());
  }

  /// 停止实时同步（关闭开关、退出登录、非赞助）。已排队的推送会先发完。
  Future<void> stop({SyncPhase phase = SyncPhase.off}) async {
    _running = false;
    _debounceT?.cancel();
    _pollT?.cancel();
    _closeWs();
    await _tail;
    status.value = status.value.copy(phase: phase, realtime: false);
  }

  /// 退出登录：停止并清掉本机的同步进度（下一个账号从头同步）。
  Future<void> reset() async {
    await stop();
    _state.clear();
    _dirty.clear();
    await _prefs.delete(_key);
    status.value = const SyncStatus(SyncPhase.off);
  }

  /// App 回到前台：WebSocket 断了就重连，并补一次同步（30 秒内同步过就跳过）。
  void resumed() {
    if (!_running) return;
    final last = status.value.lastSyncAt;
    if (last == null || _now().difference(last) > const Duration(seconds: 30)) unawaited(syncLive());
    if (_sock == null) {
      _reconnectT?.cancel();
      unawaited(_connectWs());
    }
  }

  /// App 进后台：把防抖中的推送立刻发出去。
  void paused() {
    if (_dirty.isEmpty) return;
    _debounceT?.cancel();
    unawaited(_flushDirty());
  }

  void dispose() {
    _running = false;
    _debounceT?.cancel();
    _pollT?.cancel();
    _closeWs();
    status.dispose();
  }

  // ---------------------------------------------------------------- 同步

  /// 同步全部实时文档。
  Future<void> syncLive() => _guard(() async {
        for (final t in live) {
          final d = docs[t];
          if (d != null && d.available) await _syncOne(d);
        }
      });

  /// 手动上传：用本机覆盖云端（force）。
  Future<SyncOpResult> upload(String type) async {
    late SyncOpResult r;
    await _guard(() async {
      await _load();
      final d = _doc(type);
      final p = d.export();
      final res = await api.push(type, p, baseRevision: stateOf(type).revision, force: true);
      _remember(type, res.revision, res.updatedAt, fingerprint(p));
      r = SyncOpResult(true, res.revision);
    }, rethrowErrors: true);
    return r;
  }

  /// 手动从云端恢复：拉完整快照。[replace] = 覆盖本机，否则合并（合并后本机有多出来的数据会再推上去）。
  Future<SyncOpResult> download(String type, {bool replace = true}) async {
    late SyncOpResult r;
    await _guard(() async {
      await _load();
      final d = _doc(type);
      final res = await api.pull(type);
      if (!res.changed || res.payload == null) {
        r = SyncOpResult(false, res.revision);
        return;
      }
      final extra = d.apply(res.payload, replace: replace);
      _remember(type, res.revision, res.updatedAt, fingerprint(d.export()));
      if (extra) await _push(d);
      r = SyncOpResult(true, stateOf(type).revision);
    }, rethrowErrors: true);
    return r;
  }

  /// 推一份指定载荷（例如「清除听歌记录」推空文档）。
  Future<void> pushPayload(String type, Object payload) => _guard(() async {
        await _load();
        final res = await api.push(type, payload, baseRevision: stateOf(type).revision, force: true);
        _remember(type, res.revision, res.updatedAt, fingerprint(payload));
      }, rethrowErrors: true);

  SyncDoc _doc(String type) {
    final d = docs[type];
    if (d == null || !d.available) throw ApiException(ApiErrorKind.business, '「${d?.label ?? type}」暂未接入云同步');
    return d;
  }

  Future<void> _syncOne(SyncDoc d) async {
    final st = stateOf(d.type);
    final res = await api.pull(d.type, sinceRevision: st.fingerprint == null ? 0 : st.revision);
    if (res.changed && res.payload != null) {
      final extra = d.apply(res.payload);
      _remember(d.type, res.revision, res.updatedAt, fingerprint(d.export()));
      log?.call('[sync] ${d.type} 拉取 r${res.revision}${extra ? '，本机有新增，回推' : ''}');
      if (extra) await _push(d);
      return;
    }
    // 云端没变化：云端为空且本机有数据，或本机指纹和上次同步时不同 → 推
    final fp = fingerprint(d.export());
    if ((res.revision == 0 && !d.isEmpty) || (st.fingerprint != null && fp != st.fingerprint)) {
      await _push(d);
    } else {
      _remember(d.type, res.revision, res.updatedAt.isEmpty ? st.updatedAt : res.updatedAt, st.fingerprint ?? fp);
    }
  }

  Future<void> _push(SyncDoc d, {int attempt = 0}) async {
    final p = d.export();
    final res = await api.push(d.type, p, baseRevision: stateOf(d.type).revision);
    if (!res.conflict) {
      _remember(d.type, res.revision, res.updatedAt, fingerprint(p));
      log?.call('[sync] ${d.type} 推送 r${res.revision}');
      return;
    }
    // 冲突：别的设备先推了。合并远端快照，基于新 revision 再推一次
    log?.call('[sync] ${d.type} 冲突（云端 r${res.revision}），合并');
    final extra = res.payload != null && d.apply(res.payload);
    _remember(d.type, res.revision, res.updatedAt, fingerprint(d.export()));
    if (extra && attempt == 0) await _push(d, attempt: 1);
  }

  void _remember(String type, int rev, String updatedAt, String fp) {
    _state[type] = DocState(revision: rev, fingerprint: fp, updatedAt: updatedAt);
    unawaited(_save());
  }

  // ---------------------------------------------------------------- 本机变化

  void _localChanged(String type) {
    if (!_running || !live.contains(type)) return;
    _dirty.add(type);
    _debounceT?.cancel();
    _debounceT = Timer(debounce, () => unawaited(_flushDirty()));
  }

  Future<void> _flushDirty() => _guard(() async {
        final l = [..._dirty];
        _dirty.clear();
        for (final t in l) {
          final d = docs[t];
          if (d == null || !d.available) continue;
          final fp = fingerprint(d.export());
          if (fp == stateOf(t).fingerprint) continue; // 改了又改回去
          await _push(d);
        }
      });

  // ---------------------------------------------------------------- 串行执行 + 错误处理

  /// 所有网络操作串行执行，状态统一在这里更新。
  Future<void> _guard(Future<void> Function() f, {bool rethrowErrors = false}) {
    final c = Completer<void>();
    _tail = _tail.then((_) async {
      status.value = status.value.copy(phase: SyncPhase.syncing);
      try {
        await f();
        status.value = status.value.copy(phase: _running ? SyncPhase.idle : SyncPhase.off, lastSyncAt: _now(), clearError: true);
        c.complete();
      } on ApiException catch (e, s) {
        _onError(e);
        rethrowErrors ? c.completeError(e, s) : c.complete();
      } catch (e, s) {
        status.value = status.value.copy(phase: SyncPhase.error, error: '$e');
        rethrowErrors ? c.completeError(e, s) : c.complete();
      }
    });
    return c.future;
  }

  void _onError(ApiException e) {
    log?.call('[sync] 失败：$e');
    if (e.code == ApiCode.forbidden) {
      _running = false;
      _closeWs();
      status.value = status.value.copy(phase: SyncPhase.needSponsor, error: e.userMessage, realtime: false);
    } else if (e.isUnauthorized) {
      _running = false;
      _closeWs();
      status.value = status.value.copy(phase: SyncPhase.off, error: e.userMessage, realtime: false);
    } else if (e.isNetwork) {
      status.value = status.value.copy(phase: SyncPhase.offline, error: e.userMessage);
    } else {
      status.value = status.value.copy(phase: SyncPhase.error, error: e.userMessage);
    }
  }

  // ---------------------------------------------------------------- WebSocket

  Future<void> _connectWs() async {
    if (!_running || _sock != null) return;
    try {
      final t = _client.session.tokens;
      if (t != null && t.expiresWithin(const Duration(minutes: 2), _now())) await _client.refreshTokens();
      final s = await _connect(api.wsUri());
      if (s == null) return _fallback();
      if (!_running) {
        await s.close();
        return;
      }
      _sock = s;
      _wsDelay = const Duration(seconds: 5);
      _pollT?.cancel();
      status.value = status.value.copy(realtime: true);
      log?.call('[sync] 实时通知已连接');
      _pingT = Timer.periodic(const Duration(seconds: 45), (_) {
        try {
          _sock?.send('ping'); // 服务端自动回 pong，不唤醒 DO
        } catch (_) {}
      });
      _sockSub = s.messages.listen(_onWsMessage, onDone: _wsClosed, onError: (_) => _wsClosed(), cancelOnError: true);
    } catch (e) {
      // 不打印异常内容：里面可能带着含令牌的地址
      log?.call('[sync] 实时通知连接失败（${e.runtimeType}），${_wsDelay.inSeconds} 秒后重试');
      _fallback();
    }
  }

  void _onWsMessage(String m) {
    if (m == 'pong') return;
    Json j;
    try {
      j = asJson(jsonDecode(m));
    } catch (_) {
      return;
    }
    final type = j.str('docType', DocType.library);
    final rev = j.integer('revision');
    final d = docs[type];
    if (d == null || !d.available || !live.contains(type)) return;
    if (rev <= stateOf(type).revision) return; // 自己刚推的，或已经同步过
    unawaited(_guard(() async {
      if (rev > stateOf(type).revision) await _syncOne(d);
    }));
  }

  void _wsClosed() {
    _closeWs();
    if (!_running) return;
    status.value = status.value.copy(realtime: false);
    _fallback();
  }

  void _fallback() {
    if (!_running) return;
    _pollT ??= Timer.periodic(pollEvery, (_) => unawaited(syncLive()));
    _reconnectT?.cancel();
    final jitter = Duration(milliseconds: _rand.nextInt(1000));
    _reconnectT = Timer(_wsDelay + jitter, () => unawaited(_connectWs()));
    _wsDelay = _wsDelay * 2 > const Duration(seconds: 60) ? const Duration(seconds: 60) : _wsDelay * 2;
  }

  void _closeWs() {
    _pingT?.cancel();
    _reconnectT?.cancel();
    _sockSub?.cancel();
    _sockSub = null;
    final s = _sock;
    _sock = null;
    if (s != null) unawaited(s.close().catchError((_) {}));
  }

  // ---------------------------------------------------------------- 持久化

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _prefs.read(_key);
      if (raw == null) return;
      for (final e in asJson(jsonDecode(raw)).entries) {
        if (e.value is Map) _state[e.key] = DocState.fromJson(asJson(e.value));
      }
    } catch (_) {}
  }

  Future<void> _save() => _prefs.write(_key, jsonEncode({for (final e in _state.entries) e.key: e.value.toJson()}));
}
