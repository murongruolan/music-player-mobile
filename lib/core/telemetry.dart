// 埋点：攒批上报到 POST /stats/track-batch（只有一条时用 /stats/track），失败退避重试。
//
// - 事件先写入本地队列（持久化，最多 200 条，超出丢最旧的），App 被杀也不丢。
// - 攒 30 秒发一次；队列到 20 条时 2 秒后就发；App 进后台时立刻发。
// - 一次最多 50 条。断网 / 限流 / 5xx：30 秒起指数退避，最长 30 分钟；其它业务错误丢掉这一批（多半是格式问题，重试也没用）。
// - 接口需要登录：没登录时只入队，登录后再发。
// - 请求体与桌面端一致：{eventName, deviceId, deviceName, platform, appVersion, buildNumber, timestamp, properties}；
//   批量为 {events:[{eventName, timestamp, properties}], deviceId, deviceName, platform, appVersion, buildNumber}。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../net/api_config.dart';
import '../net/net.dart';

class Telemetry with WidgetsBindingObserver {
  final Net? _net;
  final DateTime Function() _now;
  final Duration batchDelay, soonDelay;
  final _queue = <Json>[];
  Timer? _t;
  bool _sending = false, _observing = false, _loaded = false;
  int _failures = 0;
  DateTime? _retryAt;

  static const _key = 'telemetry.queue.v1';
  static const maxQueue = 200, maxBatch = 50, soonAt = 20;

  Telemetry(this._net, {DateTime Function()? now, this.batchDelay = const Duration(seconds: 30), this.soonDelay = const Duration(seconds: 2)}) : _now = now ?? DateTime.now;

  int get pending => _queue.length;

  Future<void> init() async {
    await _load();
    final n = _net;
    if (n != null && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      // 登录后把攒着的发出去
      n.session.onChanged.listen((t) {
        if (t != null && _queue.isNotEmpty) _schedule(soonDelay);
      });
    }
    if (_queue.isNotEmpty) _schedule(soonDelay);
  }

  /// 记录一个事件。[props] 只放必要的、非个人隐私的字段。
  void track(String name, [Map<String, Object?> props = const {}]) {
    if (_net == null) return; // 演示模式不上报
    _queue.add({'eventName': name, 'timestamp': _now().toUtc().toIso8601String(), 'properties': props});
    if (_queue.length > maxQueue) _queue.removeRange(0, _queue.length - maxQueue);
    unawaited(_save());
    _schedule(_queue.length >= soonAt ? soonDelay : batchDelay);
  }

  /// 立刻发送（进后台时调用；退避期内不发）。
  Future<void> flush() async {
    _t?.cancel();
    _t = null;
    await _send();
  }

  void _schedule(Duration d) {
    final retry = _retryAt;
    if (retry != null) {
      final left = retry.difference(_now());
      if (left > d) d = left;
    }
    if (_t != null) return; // 已经排着了，不推迟
    _t = Timer(d, () {
      _t = null;
      unawaited(_send());
    });
  }

  Future<void> _send() async {
    final n = _net;
    if (n == null || _sending || _queue.isEmpty || !n.session.isLoggedIn) return;
    if (_retryAt != null && _now().isBefore(_retryAt!)) {
      _schedule(Duration.zero); // 退避期内：排到退避结束
      return;
    }
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(maxBatch).toList();
        final d = n.device;
        final common = {'deviceId': d.deviceId, 'deviceName': d.deviceName, 'platform': d.platform, 'appVersion': d.appVersion, 'buildNumber': ApiConfig.buildNumber};
        try {
          if (batch.length == 1) {
            await n.client.post('/stats/track', body: {...common, ...batch.first}, timeout: const Duration(seconds: 10));
          } else {
            await n.client.post('/stats/track-batch', body: {...common, 'events': batch}, timeout: const Duration(seconds: 15));
          }
        } on ApiException catch (e) {
          if (e.isNetwork || e.isRateLimited || e.kind == ApiErrorKind.server || e.isUnauthorized) {
            _failures++;
            final wait = Duration(seconds: math.min(1800, 30 * math.pow(2, _failures - 1).toInt()));
            _retryAt = _now().add(wait);
            _schedule(wait);
            return;
          }
          // 其它错误：丢掉这一批
        }
        _queue.removeRange(0, batch.length);
        _failures = 0;
        _retryAt = null;
      }
    } finally {
      _sending = false;
      await _save();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) unawaited(flush());
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _net?.prefs.read(_key);
    if (raw == null) return;
    try {
      for (final e in jsonDecode(raw) as List) {
        if (e is Map) _queue.add(e.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    await _net?.prefs.write(_key, jsonEncode(_queue));
  }

  void dispose() {
    _t?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}
