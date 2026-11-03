// 解析 JSON 的小工具：写接口模型时少写类型判断，字段缺失 / 类型不对时给默认值而不是崩溃。
//
//   final u = User(uid: j.str('uid'), rank: j.integer('membershipRank'), vip: j.boolean('isActivated'));
//   final items = j.list('items', Announcement.fromJson);

typedef Json = Map<String, dynamic>;

extension JsonRead on Json {
  String str(String k, [String fallback = '']) {
    final v = this[k];
    if (v == null) return fallback;
    return v is String ? v : v.toString();
  }

  String? strOrNull(String k) {
    final v = this[k];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  int integer(String k, [int fallback = 0]) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    if (v is bool) return v ? 1 : 0;
    return fallback;
  }

  int? intOrNull(String k) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double number(String k, [double fallback = 0]) {
    final v = this[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  bool boolean(String k, [bool fallback = false]) {
    final v = this[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return fallback;
  }

  /// RFC3339 字符串或毫秒时间戳。
  DateTime? time(String k) {
    final v = this[k];
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  Json obj(String k) {
    final v = this[k];
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  }

  Json? objOrNull(String k) {
    final v = this[k];
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  /// 对象数组；元素不是对象时跳过。
  List<T> list<T>(String k, T Function(Json) f) {
    final v = this[k];
    if (v is! List) return <T>[];
    return [for (final e in v) if (e is Map) f(e.cast<String, dynamic>())];
  }

  List<String> strings(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return [for (final e in v) if (e != null) e.toString()];
  }
}

/// 把信封里的 data 当作对象读；不是对象时给空对象。
Json asJson(Object? data) => data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
