// 网络层的总装：配置、存储、会话、设备信息、请求客户端都在这里创建一次，App 里只持有一个 [Net]。
//
//   final net = await Net.create();          // 正式运行（系统钥匙串）
//   final net = await Net.memory();          // 测试 / 截图（内存存储，不碰平台插件）
//   final s = await RegistrationApi(net.client).settings();
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'device.dart';
import 'rate_limiter.dart';
import 'session.dart';
import 'storage.dart';

export 'api_client.dart' show ApiClient, CancelToken, Decoder;
export 'api_error.dart';
export 'auth_service.dart';
export 'json.dart';
export 'session.dart' show AuthTokens, Session, SessionEnd;

class Net {
  final KvStore store;
  final ApiConfig config;
  final Session session;
  final DeviceInfo device;
  final ApiClient client;
  final AuthService auth;

  Net._(this.store, this.config, this.session, this.device, this.client) : auth = AuthService(client);

  /// 正式运行：令牌存系统钥匙串，启动时恢复会话和自定义接口地址。
  static Future<Net> create() => build(SecureKvStore());

  /// 测试 / 截图：内存存储。[httpClient] 传 MockClient 可模拟后端。
  static Future<Net> memory({http.Client? httpClient, Clock? now, Sleeper? sleep, String? baseUrl}) =>
      build(MemoryKvStore(), httpClient: httpClient, now: now, sleep: sleep, baseUrl: baseUrl);

  static Future<Net> build(KvStore store, {http.Client? httpClient, Clock? now, Sleeper? sleep, String? baseUrl, RateLimiter? limiter}) async {
    final config = ApiConfig(store, baseUrl: baseUrl);
    await config.load();
    final session = Session(store);
    await session.restore();
    final device = await DeviceInfo.load(store, appVersion: ApiConfig.appVersion);
    final client = ApiClient(config: config, session: session, device: device, httpClient: httpClient, now: now, sleep: sleep, limiter: limiter);
    return Net._(store, config, session, device, client);
  }

  void dispose() {
    client.close();
    session.dispose();
  }
}
