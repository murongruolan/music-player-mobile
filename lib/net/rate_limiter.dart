// 客户端限流：后端在 Cloudflare Workers 免费套餐上（每天 10 万次请求），
// /auth/* 还有每 IP 每分钟 60 次的限制。客户端自己先把请求节奏压住，别把配额打满。
//
// - 令牌桶：每个桶有容量（允许的突发）和补充速率；没有令牌就排队等待，而不是直接失败。
// - 冷却：收到 42901 / HTTP 429 后，该桶进入冷却期（指数退避 + 抖动），期间的请求直接报 rateLimited，
//   避免在被限流时继续打服务端。
import 'dart:async';
import 'dart:math';

typedef Clock = DateTime Function();
typedef Sleeper = Future<void> Function(Duration);

Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

class BucketSpec {
  /// 桶容量（允许的突发请求数）。
  final int capacity;

  /// 每补充一个令牌所需时间。
  final Duration refillEvery;
  const BucketSpec({required this.capacity, required this.refillEvery});

  /// 例：BucketSpec.perMinute(30, burst: 5)
  factory BucketSpec.perMinute(int n, {int? burst}) => BucketSpec(capacity: burst ?? n, refillEvery: Duration(microseconds: 60000000 ~/ n));
  factory BucketSpec.perSecond(double n, {required int burst}) => BucketSpec(capacity: burst, refillEvery: Duration(microseconds: (1000000 / n).round()));
}

class _Bucket {
  final BucketSpec spec;
  double tokens;
  DateTime last;
  DateTime? coolUntil;
  int strikes = 0;
  // 排队：保证先来先得，避免多个等待者同时醒来抢同一个令牌。
  Future<void> tail = Future<void>.value();
  _Bucket(this.spec, DateTime now)
      : tokens = spec.capacity.toDouble(),
        last = now;

  void refill(DateTime now) {
    final gained = now.difference(last).inMicroseconds / spec.refillEvery.inMicroseconds;
    if (gained > 0) {
      tokens = min(spec.capacity.toDouble(), tokens + gained);
      last = now;
    }
  }
}

/// 冷却期内请求被拒绝时抛出；[retryAfter] 是剩余冷却时间。
class RateLimitedLocally implements Exception {
  final Duration retryAfter;
  const RateLimitedLocally(this.retryAfter);
  @override
  String toString() => 'RateLimitedLocally(${retryAfter.inMilliseconds}ms)';
}

class RateLimiter {
  final Map<String, BucketSpec> specs;
  final Clock now;
  final Sleeper sleep;
  final Random _rand;

  /// 被限流后的冷却：base × 2^(连续次数-1)，上限 [maxCooldown]，再加最多 25% 的抖动。
  final Duration baseCooldown, maxCooldown;

  /// 排队等待超过它就不等了，直接报限流（避免界面卡很久）。
  final Duration maxWait;
  final _buckets = <String, _Bucket>{};

  RateLimiter({
    required this.specs,
    Clock? now,
    Sleeper? sleep,
    Random? random,
    this.baseCooldown = const Duration(seconds: 2),
    this.maxCooldown = const Duration(seconds: 60),
    this.maxWait = const Duration(seconds: 10),
  })  : now = now ?? DateTime.now,
        sleep = sleep ?? _defaultSleep,
        _rand = random ?? Random();

  /// 默认配置：全局 4 次/秒（突发 8）；/auth/* 30 次/分钟（突发 5），留出服务端 60 次/分钟的一半余量。
  factory RateLimiter.standard({Clock? now, Sleeper? sleep, Random? random}) => RateLimiter(
        specs: {
          'global': BucketSpec.perSecond(4, burst: 8),
          'auth': BucketSpec.perMinute(30, burst: 5),
        },
        now: now,
        sleep: sleep,
        random: random,
      );

  _Bucket _bucket(String key) => _buckets.putIfAbsent(key, () => _Bucket(specs[key] ?? specs['global']!, now()));

  /// 剩余冷却时间；不在冷却期返回 null。
  Duration? cooldownOf(String key) {
    final until = _buckets[key]?.coolUntil;
    if (until == null) return null;
    final left = until.difference(now());
    return left > Duration.zero ? left : null;
  }

  /// 依次从 [keys] 对应的桶里各取一个令牌；令牌不够时排队等待。
  /// 任一桶在冷却期内 → 抛 [RateLimitedLocally]。
  Future<void> acquire(List<String> keys) async {
    for (final k in keys) {
      await _acquireOne(k);
    }
  }

  Future<void> _acquireOne(String key) {
    final b = _bucket(key);
    final cd = cooldownOf(key);
    if (cd != null) return Future.error(RateLimitedLocally(cd));
    final prev = b.tail;
    final done = Completer<void>();
    b.tail = done.future;
    return prev.then((_) async {
      try {
        final started = now();
        while (true) {
          final cd = cooldownOf(key);
          if (cd != null) throw RateLimitedLocally(cd);
          final t = now();
          b.refill(t);
          if (b.tokens >= 1) {
            b.tokens -= 1;
            return;
          }
          final need = Duration(microseconds: ((1 - b.tokens) * b.spec.refillEvery.inMicroseconds).ceil());
          if (t.add(need).difference(started) > maxWait) throw RateLimitedLocally(need);
          await sleep(need);
        }
      } finally {
        done.complete();
      }
    });
  }

  /// 服务端返回了限流：进入冷却。返回本次冷却时长。
  Duration penalize(String key, {Duration? retryAfter}) {
    final b = _bucket(key);
    b.strikes++;
    var d = retryAfter ?? baseCooldown * pow(2, b.strikes - 1).toInt();
    if (d > maxCooldown) d = maxCooldown;
    d += Duration(milliseconds: (d.inMilliseconds * .25 * _rand.nextDouble()).round());
    b.coolUntil = now().add(d);
    b.tokens = 0;
    b.last = now();
    return d;
  }

  /// 请求成功：清掉连续限流计数。
  void reward(String key) {
    final b = _buckets[key];
    if (b != null && b.strikes > 0 && cooldownOf(key) == null) b.strikes = 0;
  }
}
