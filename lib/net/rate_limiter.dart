// 限流冷却：客户端不主动限速，只在服务端返回 42901 / HTTP 429 后让对应的桶冷却一段时间，
// 冷却期内的请求直接报 rateLimited、不发出去，避免被限流时继续打服务端（后端在 CF 免费套餐上）。
//
// 桶：/auth/* 走 'auth'（服务端对它单独按 IP 限流），其余走 'global'。
// 冷却时长：服务端给了 Retry-After 就用它；否则 2 秒起、连续被限流时翻倍，上限 60 秒，再加最多 25% 抖动。
import 'dart:math';

typedef Clock = DateTime Function();
typedef Sleeper = Future<void> Function(Duration);

/// 冷却期内请求被拒绝时抛出；[retryAfter] 是剩余冷却时间。
class RateLimitedLocally implements Exception {
  final Duration retryAfter;
  const RateLimitedLocally(this.retryAfter);
  @override
  String toString() => 'RateLimitedLocally(${retryAfter.inMilliseconds}ms)';
}

class _Cool {
  DateTime? until;
  int strikes = 0;
}

class RateLimiter {
  final Clock now;
  final Random _rand;
  final Duration baseCooldown, maxCooldown;
  final _buckets = <String, _Cool>{};

  RateLimiter({Clock? now, Random? random, this.baseCooldown = const Duration(seconds: 2), this.maxCooldown = const Duration(seconds: 60)})
      : now = now ?? DateTime.now,
        _rand = random ?? Random();

  /// 剩余冷却时间；不在冷却期返回 null。
  Duration? cooldownOf(String key) {
    final until = _buckets[key]?.until;
    if (until == null) return null;
    final left = until.difference(now());
    return left > Duration.zero ? left : null;
  }

  /// 发请求前检查：任一桶在冷却期内 → 抛 [RateLimitedLocally]。
  void check(List<String> keys) {
    for (final k in keys) {
      final cd = cooldownOf(k);
      if (cd != null) throw RateLimitedLocally(cd);
    }
  }

  /// 服务端返回了限流：进入冷却。返回本次冷却时长。
  Duration penalize(String key, {Duration? retryAfter}) {
    final b = _buckets.putIfAbsent(key, _Cool.new);
    b.strikes++;
    var d = retryAfter ?? baseCooldown * pow(2, b.strikes - 1).toInt();
    if (d > maxCooldown) d = maxCooldown;
    d += Duration(milliseconds: (d.inMilliseconds * .25 * _rand.nextDouble()).round());
    b.until = now().add(d);
    return d;
  }

  /// 请求成功：清掉连续限流计数。
  void reward(String key) {
    final b = _buckets[key];
    if (b != null && b.strikes > 0 && cooldownOf(key) == null) b.strikes = 0;
  }
}
