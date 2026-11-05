// 每日推荐：网易云直连为主（登录后按账号推荐，每天 6:00 更新），没登录网易云时用私人 FM 兜底。
// 不经过 Lyra 服务端。结果按「日期 + 账号」在内存里缓存，同一天重复打开不重复请求。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/models.dart';
import '../platform/netease.dart';
import '../platform/registry.dart' show platformError;
import 'app_log.dart';
import 'state.dart';

enum DailyMode { daily, fm }

class DailyFeed extends ChangeNotifier {
  DailyFeed(this._app);
  final AppState _app;

  /// 私人 FM 一次接口只给 1~3 首：凑够这么多首再展示。
  static const fmTarget = 12;

  DailyMode mode = DailyMode.daily;
  List<int> ids = const [];
  bool loading = false;
  String? error;

  /// 登录失效 / 没登录时给用户的说明（显示在头卡下方）。
  String? note;
  String? _key; // 日期 + 账号：变了才重新拉
  Future<void>? _running;

  NeteasePlatform? get _wy {
    final p = _app.content.of(Plat.wy);
    return p is NeteasePlatform ? p : null;
  }

  String get _cookie => _app.platCreds.of(Plat.wy)?.cookie ?? '';
  bool get loggedIn => _cookie.isNotEmpty;

  /// 网易 6:00 换新：6 点前算前一天。
  static String dayOf(DateTime t) {
    final d = t.subtract(const Duration(hours: 6));
    return '${d.year}-${d.month}-${d.day}';
  }

  /// 打开每日页时调：缓存还有效就什么都不做。
  Future<void> ensure() {
    final key = '${dayOf(DateTime.now())}|${_app.platCreds.of(Plat.wy)?.nickname ?? _cookie.hashCode}|${loggedIn ? 'u' : 'g'}';
    if (key == _key && (ids.isNotEmpty || loading)) return _running ?? Future.value();
    _key = key;
    return refresh();
  }

  /// 重新拉。FM 模式下等于「换一批」。
  Future<void> refresh() => _running ??= _load().whenComplete(() => _running = null);

  Future<void> _load() async {
    final wy = _wy;
    if (wy == null) {
      error = '当前环境没有接入网易云';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (loggedIn) {
        try {
          final t = await wy.dailySongs(_cookie);
          if (t.isNotEmpty) {
            _set(DailyMode.daily, t, null);
            return;
          }
        } on NeteaseAuthException {
          await _app.platCreds.markExpired(Plat.wy, '每日推荐返回 301');
          AppLog.instance.add('每日推荐', '网易云登录已过期，改用私人 FM');
          _set(DailyMode.fm, await _fm(wy), '网易云登录已过期，重新登录后显示你的每日推荐');
          return;
        }
      }
      _set(DailyMode.fm, await _fm(wy), loggedIn ? '每日推荐暂时拿不到，先听听私人 FM' : '登录网易云后，这里会换成按你口味生成的每日推荐');
    } catch (e) {
      error = platformError(e);
      AppLog.instance.add('每日推荐', '获取失败：$error');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 私人 FM 凑一批：每轮并发 3 个请求，去重，最多 8 轮。
  Future<List<PTrack>> _fm(NeteasePlatform wy) async {
    final cookie = loggedIn ? _cookie : (_app.platCreds.anonymousCookie(Plat.wy) ?? '');
    final seen = <String>{};
    final out = <PTrack>[];
    Object? last;
    for (var round = 0; round < 8 && out.length < fmTarget; round++) {
      final batch = await Future.wait([
        for (var i = 0; i < 3; i++)
          wy.personalFm(cookie).catchError((Object e) {
            last = e;
            return <PTrack>[];
          }),
      ]);
      for (final t in batch.expand((b) => b)) {
        if (seen.add(t.id) && !_app.isDislikedKey(t.id)) out.add(t);
      }
      if (batch.every((b) => b.isEmpty)) break;
    }
    if (out.isEmpty && last != null) throw last!;
    return out.take(fmTarget).toList();
  }

  void _set(DailyMode m, List<PTrack> tracks, String? why) {
    mode = m;
    note = why;
    ids = [for (final t in tracks) _app.library.register(t.toCloud())];
    error = tracks.isEmpty ? (m == DailyMode.fm ? '私人 FM 暂时没有返回歌曲，稍后再试' : '今天的推荐还没生成') : null;
  }

  /// 退出登录 / 切换网易云账号后清掉缓存。
  void reset() {
    _key = null;
    ids = const [];
    note = null;
    error = null;
    notifyListeners();
  }
}
