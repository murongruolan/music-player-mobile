# 接口对接约定

后端：[`music-player-server`](https://github.com/murongruolan/music-player-server)（Cloudflare Workers 免费套餐），前缀 `/api/v1`。
所有请求都走 `lib/net/` 的统一封装，页面和 `AppState` 不直接用 `http`。

## 结构

```
lib/net/                网络层（一般不用改）
  net.dart              总装：Net.create() / Net.memory()，App 里只有一个 Net（AppState.api）
  api_client.dart       ApiClient：get / post / put / delete，信封解析、令牌、限流、重试、缓存、合并、取消
  api_error.dart        ApiException + ApiCode（后端错误码）
  auth_service.dart     登录 / 刷新 / 退出 + Account 模型（net.auth）
  session.dart          令牌与持久化，onEnd 通知会话结束
  rate_limiter.dart     客户端令牌桶 + 被限流后的冷却
  api_config.dart       接口地址（--dart-define=API_BASE_URL 或运行时覆盖）、超时
  json.dart             JsonRead：j.str / integer / boolean / time / obj / list …，字段缺失不崩
  device.dart           上报的设备信息（deviceId 首次启动生成并持久化）
  storage.dart          KvStore：SecureKvStore（钥匙串）/ MemoryKvStore（测试）
lib/api/                具体接口，按页面 / 模块一个文件，一个 XxxApi 类
```

## 写一个接口

```dart
// lib/api/announcement_api.dart
import '../net/net.dart';

class AnnouncementApi {
  final ApiClient _c;
  AnnouncementApi(this._c);

  Future<List<Notice>> list() => _c.get('/announcements',
      cacheTtl: const Duration(minutes: 2), staleOnError: true,
      decode: (d) => asJson(d).list('items', Notice.fromJson));

  Future<void> ack(String id) async {
    await _c.post('/announcements/$id/ack');
    _c.clearCache('/announcements');   // 写操作后让列表重新拉
  }
}
```

- 模型写 `factory X.fromJson(Json j)`，全部用 `JsonRead` 取字段（给默认值），不要 `j['x'] as String`。
- `decode` 里抛的任何异常都会变成 `ApiErrorKind.parse`。
- 不需要登录的接口传 `auth: false`；默认需要登录，没登录时直接报 `unauthorized`，不会发请求。
- 示例见 [`lib/api/registration_api.dart`](../../lib/api/registration_api.dart)。

## 在 AppState / 页面里调用

```dart
try {
  loading = true; notifyListeners();
  notices = await AnnouncementApi(api.client).list();
} on ApiException catch (e) {
  if (!e.isCancelled) toast(e.userMessage, 'info');
} finally {
  loading = false; notifyListeners();
}
```

- `e.userMessage` 可以直接展示：业务错误用后端返回的中文文案，网络 / 超时 / 限流 / 服务器错误给统一文案。
- 会话失效不需要页面处理：封装会清掉令牌，`AppState.sessionEnded` 回到登录页，`main.dart` 弹「登录已失效」。
- 登录类接口成功后调用 `api.auth.signedIn(data)` 保存令牌（注册、旧版登录同理），退出用 `api.auth.logout()`。
- 测试 / 截图里 `AppState()` 不带 `Net`（`net == null`），页面在这种情况下保持 mock 数据。

## 鉴权规则（与后端 `src/auth.ts` 对应）

| 情况 | 封装的处理 |
|---|---|
| 访问令牌 2 小时，离过期不到 60 秒 | 请求前先刷新 |
| 业务码 40101 | 刷新一次后重试原请求；并发请求共用同一次刷新 |
| 业务码 40102 / 刷新返回其他 4xx | 清会话，通知 `SessionEnd.expired` |
| HTTP 401 + 业务码 40001（密码错误） | 当普通业务错误，不刷新 |
| 刷新时断网 / 5xx | 保留会话，下次再试 |

刷新令牌会轮换，旧的立刻作废；拿旧令牌再刷新会被当成重放并吊销全部会话。所以**不要自己调 `/auth/refresh`**，需要时用 `client.refreshTokens()`（单飞）。

## 请求频率

后端每天 10 万次请求额度，`/auth/*` 每 IP 每分钟 60 次。封装里：

- 全局令牌桶 4 次/秒（突发 8），`/auth/*` 30 次/分钟（突发 5）。超出时排队，排队超过 10 秒报 `rateLimited`。
- 收到 42901 / 429：该桶冷却 2 秒起、指数增长到 60 秒（加抖动），冷却期内的请求不发出去直接报 `rateLimited`。
- GET 在网络错误 / 超时 / 5xx 时自动重试 2 次（0.4 秒、0.8 秒起，加抖动）；冷却不超过 5 秒的限流也会等完再重试。POST / PUT / DELETE 不重试，确实幂等的接口可以传 `retry: true`。
- 相同的 GET 在途时只发一次。

写接口时要注意的：

- 很少变化的数据（注册设置、能力列表、公告、更新检查）加 `cacheTtl`，配合 `staleOnError: true`。
- 不要在 `build()`、滚动回调、定时器里直接发请求；进入页面拉一次，下拉刷新再拉。
- 搜索联想这类高频输入先防抖（300 ms 以上），并用 `CancelToken` 丢掉过期结果。
- 统计上报用 `/stats/track-batch` 攒批发送，不要一条一发。
- 同步优先用 WebSocket（`/sync/ws`），不要短间隔轮询 `/sync/pull`。

## 已知问题

- `*.workers.dev` 在中国大陆被 SNI 阻断，正式使用需要给后端绑定自定义域名，然后用 `--dart-define=API_BASE_URL=https://域名/api/v1` 构建，或调用 `api.config.setOverride(url)`。
- 后端没有返回 CORS 头，Flutter Web（含 CI 截图）调不通接口；手机端不受影响。
