// 云同步 / 云备份接口。整个 /sync/* 家族都要求赞助用户（后端 requireSponsor → 403 / 40301）。
// 实时通知只用 WebSocket（/sync/ws）。旧的长轮询 /sync/wait 每 20 秒占一个请求，太费 CF 免费额度，
// 后端已标为过渡期回退通道，客户端不封装、不调用。
import '../net/net.dart';

/// 后端支持的同步文档类型。
abstract final class DocType {
  static const settings = 'settings', library = 'library', playlists = 'playlists', favorites = 'favorites', listeningStats = 'listening_stats', lxSources = 'lx_sources';
  static const all = [settings, library, playlists, favorites, listeningStats, lxSources];
}

class PullResult {
  final bool changed;
  final int revision;
  final String updatedAt;
  final Object? payload;
  const PullResult(this.changed, this.revision, this.updatedAt, this.payload);
  factory PullResult.fromJson(Json j) => PullResult(j.boolean('changed'), j.integer('revision'), j.str('updatedAt'), j['payload']);
}

class PushResult {
  final bool conflict;
  final int revision;
  final String updatedAt;

  /// 冲突时：服务端当前的快照。
  final Object? payload;
  const PushResult(this.conflict, this.revision, this.updatedAt, this.payload);
  factory PushResult.fromJson(Json j) => PushResult(j.boolean('conflict'), j.integer('revision'), j.str('updatedAt'), j['payload']);
}

class SyncApi {
  final ApiClient _c;
  SyncApi(this._c);

  /// sinceRevision 之后有变化才带 payload。没变化时服务端只查元数据，很便宜。
  Future<PullResult> pull(String docType, {int sinceRevision = 0}) =>
      _c.get('/sync/pull', query: {'docType': docType, 'sinceRevision': sinceRevision}, dedupe: true, decode: (d) => PullResult.fromJson(asJson(d)));

  /// 基于 [baseRevision] 推送。落后于服务端时返回 conflict + 远端快照；[force] 直接覆盖。
  Future<PushResult> push(String docType, Object payload, {required int baseRevision, bool force = false}) => _c.post(
        '/sync/push',
        body: {'docType': docType, 'baseRevision': baseRevision, 'force': force, 'deviceName': _c.device.deviceName, 'payload': payload},
        timeout: const Duration(seconds: 30),
        decode: (d) => PushResult.fromJson(asJson(d)),
      );

  /// WebSocket 地址：wss://<host>/api/v1/sync/ws?token=…&deviceId=…
  Uri wsUri() {
    final u = _c.config.uri('/sync/ws', {'token': _c.session.tokens?.accessToken ?? '', 'deviceId': _c.device.deviceId});
    return u.replace(scheme: u.scheme == 'http' ? 'ws' : 'wss');
  }
}

class BackupMeta {
  final int id, size;
  final String kind, deviceName, appVersion;
  final DateTime? createdAt;
  const BackupMeta({required this.id, required this.size, required this.kind, required this.deviceName, required this.appVersion, this.createdAt});
  factory BackupMeta.fromJson(Json j) => BackupMeta(
        id: j.integer('id'),
        size: j.integer('size'),
        kind: j.str('kind', 'full'),
        deviceName: j.str('deviceName'),
        appVersion: j.str('appVersion'),
        createdAt: j.time('createdAt'),
      );
}

class BackupApi {
  final ApiClient _c;
  BackupApi(this._c);

  /// 服务端每个用户只保留最新 3 份，超出删最老的。
  static const keep = 3;

  Future<BackupMeta> upload(Object payload, {String kind = 'full'}) => _c.post(
        '/backup/upload',
        body: {'kind': kind, 'deviceName': _c.device.deviceName, 'appVersion': _c.device.appVersion, 'payload': payload},
        timeout: const Duration(seconds: 60),
        decode: (d) {
          final j = asJson(d);
          return BackupMeta(id: j.integer('id'), size: 0, kind: kind, deviceName: _c.device.deviceName, appVersion: _c.device.appVersion, createdAt: j.time('createdAt'));
        },
      );

  Future<List<BackupMeta>> list() => _c.get('/backup/list', decode: (d) => asJson(d).list('items', BackupMeta.fromJson));

  /// 取一份备份的完整内容（payload）。
  Future<(BackupMeta, Object?)> get(int id) => _c.get('/backup/$id', timeout: const Duration(seconds: 60), decode: (d) {
        final j = asJson(d);
        return (BackupMeta.fromJson(j), j['payload']);
      });

  /// 最新一份；没有时抛 business / 40401。
  Future<(BackupMeta, Object?)> latest() => _c.get('/backup/latest', timeout: const Duration(seconds: 60), decode: (d) {
        final j = asJson(d);
        return (BackupMeta.fromJson(j), j['payload']);
      });
}
