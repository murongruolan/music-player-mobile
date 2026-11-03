// 接口错误：统一成 ApiException，页面只需要 catch 这一种。
//
// 后端信封：{"code":0,"message":"ok","requestId":"...","data":...}
// code ≠ 0 即业务错误；错误码见 music-player-server/src/util.ts。

/// 后端业务错误码。
abstract final class ApiCode {
  static const ok = 0;

  /// 参数错误。注意：登录密码错误也是 40001（HTTP 401），不会触发刷新令牌。
  static const badParam = 40001;

  /// 访问令牌缺失 / 无效 / 过期 → 客户端刷新令牌后重试一次。
  static const unauthorized = 40101;

  /// 刷新令牌无效 / 过期 / 被重放 → 会话失效，需要重新登录。
  static const refreshInvalid = 40102;
  static const forbidden = 40301;
  static const notFound = 40401;
  static const conflict = 40901;
  static const rateLimited = 42901;
  static const internal = 50001;
}

enum ApiErrorKind {
  /// 没有网络 / DNS / 连接被重置。
  network,

  /// 超时。
  timeout,

  /// 后端返回了 code ≠ 0。
  business,

  /// 未登录或会话已失效（需要重新登录）。
  unauthorized,

  /// 被限流（服务端 42901 / HTTP 429，或客户端自己的冷却期内）。
  rateLimited,

  /// 服务端异常（5xx 且没有合法信封）。
  server,

  /// 响应不是合法 JSON / 字段不符合预期。
  parse,

  /// 请求被调用方取消。
  cancelled,
}

class ApiException implements Exception {
  final ApiErrorKind kind;

  /// 业务错误码；非业务错误时为 null。
  final int? code;
  final int? httpStatus;
  final String message;

  /// 服务端请求 ID，反馈问题时附上。
  final String? requestId;
  final Object? cause;

  /// 限流时：建议多久之后再试。
  final Duration? retryAfter;

  const ApiException(this.kind, this.message, {this.code, this.httpStatus, this.requestId, this.cause, this.retryAfter});

  bool get isNetwork => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
  bool get isRateLimited => kind == ApiErrorKind.rateLimited;
  bool get isCancelled => kind == ApiErrorKind.cancelled;

  /// 能直接展示给用户的一句话。业务错误用后端的 message（已是中文）。
  String get userMessage => switch (kind) {
        ApiErrorKind.network => '网络连接失败，请检查网络后重试',
        ApiErrorKind.timeout => '请求超时，请稍后重试',
        ApiErrorKind.unauthorized => message.isNotEmpty ? message : '登录已失效，请重新登录',
        ApiErrorKind.rateLimited => message.isNotEmpty ? message : '操作太频繁了，请稍后再试',
        ApiErrorKind.server => '服务器开小差了，请稍后重试',
        ApiErrorKind.parse => '数据异常，请稍后重试',
        ApiErrorKind.cancelled => '已取消',
        ApiErrorKind.business => message.isNotEmpty ? message : '请求失败（$code）',
      };

  @override
  String toString() => 'ApiException(${kind.name}, code=$code, http=$httpStatus, requestId=$requestId): $message';
}
