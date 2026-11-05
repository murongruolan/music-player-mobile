// 每日推荐：网易云直连为主（登录后按账号推荐，每天 6:00 更新），没登录网易云时用私人 FM 兜底。
// 不经过 Lyra 服务端。结果按「日期 + 账号」在内存里缓存，同一天重复打开不重复请求。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/models.dart';
import '../platform/netease.dart';
import '../platform/registry.dart' show platformError;
import '../sync/cloud_models.dart' show CloudTrack;
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

  static const _kCache = 'daily.cache.v1';

  /// 打开每日页时调：内存里有今天的就什么都不做；没有就先拿本机缓存（上次打开时的结果）秒开，
  /// 再在后台拉新的。拉回来的和正在显示的一样就不替换（不闪），不一样才换。
  /// 私人 FM 每次都不一样：有缓存时直接用缓存，不在后台换掉，点刷新才换一批。
  Future<void> ensure() async {
    final key = '${dayOf(DateTime.now())}|${_app.platCreds.of(Plat.wy)?.nickname ?? _cookie.hashCode}|${loggedIn ? 'u' : 'g'}';
    if (key == _key && (ids.isNotEmpty || loading)) return _running ?? Future.value();
    _key = key;
    final cached = await _readCache(key);
    if (cached != null) {
      mode = cached.$1;
      note = cached.$3;
      ids = cached.$2;
      error = null;
      notifyListeners();
      if (mode == DailyMode.fm) return;
    }
    return refresh();
  }

  Future<(DailyMode, List<int>, String?)?> _readCache(String key) async {
    try {
      final raw = await _app.net?.prefs.read(_kCache);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['key'] != key) return null;
      final tracks = [for (final t in (j['tracks'] as List? ?? const [])) CloudTrack.fromDesktop(Map<String, dynamic>.from(t as Map))];
      if (tracks.isEmpty) return null;
      return (j['mode'] == 'fm' ? DailyMode.fm : DailyMode.daily, [for (final t in tracks) _app.library.register(t)], j['note'] as String?);
    } catch (_) {
      return null;
    }
  }

  void _writeCache(List<PTrack> tracks) {
    final key = _key;
    if (key == null || tracks.isEmpty) return;
    unawaited(_app.net?.prefs.write(_kCache, jsonEncode({'key': key, 'mode': mode == DailyMode.fm ? 'fm' : 'daily', 'note': note, 'tracks': [for (final t in tracks) t.toCloud().toDesktop()]})));
  }

  /// 重新拉。FM 模式下等于「换一批」。
  Future<void> refresh() {
    final r = _running;
    if (r != null) return r;
    late final Future<void> f;
    f = _load().whenComplete(() {
      if (identical(_running, f)) _running = null; // reset 后开始的新一轮不被旧的清掉
    });
    return _running = f;
  }

  Future<void> _load() async {
    final gen = _gen;
    bool stale() => gen != _gen;
    final wy = _wy;
    if (wy == null) {
      error = '当前环境没有接入网易云';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners(); // 页面只在还没有内容时显示骨架屏；已有内容（缓存）时后台静默刷新
    try {
      if (loggedIn) {
        try {
          final t = await wy.dailySongs(_cookie);
          if (t.isNotEmpty) {
            _set(DailyMode.daily, t, null, gen: gen);
            return;
          }
        } on NeteaseAuthException {
          // 标记失效会触发 reset()，由它按游客身份重新拉（这一轮作废）
          AppLog.instance.add('每日推荐', '网易云登录已过期，改用私人 FM');
          await _app.platCreds.markExpired(Plat.wy, '每日推荐返回 301');
          return;
        }
      }
      final fm = await _fm(wy, gen);
      _set(DailyMode.fm, fm, loggedIn ? '每日推荐暂时拿不到，先听听私人 FM' : '登录网易云后，这里会换成按你口味生成的每日推荐', gen: gen);
    } catch (e) {
      // 已经显示着缓存的内容时，后台刷新失败不打断（下次再试）
      if (!stale() && ids.isEmpty) error = platformError(e);
      AppLog.instance.add('每日推荐', '获取失败：$e');
    } finally {
      if (!stale()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 私人 FM 凑一批：每轮并发 3 个请求，去重，最多 8 轮。页面上还空着时，第一轮拿到的先显示出来。
  Future<List<PTrack>> _fm(NeteasePlatform wy, int gen) async {
    final showPartial = ids.isEmpty;
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
      if (gen != _gen) break; // 已重置：不再接着凑
      if (showPartial && out.isNotEmpty && out.length < fmTarget) {
        mode = DailyMode.fm;
        ids = [for (final t in out) _app.library.register(t.toCloud())];
        notifyListeners();
      }
      if (batch.every((b) => b.isEmpty)) break;
    }
    if (out.isEmpty && last != null) throw last!;
    return out.take(fmTarget).toList();
  }

  void _set(DailyMode m, List<PTrack> tracks, String? why, {int? gen}) {
    if (gen != null && gen != _gen) return; // 已经 reset 过：旧结果丢掉
    final next = [for (final t in tracks) _app.library.register(t.toCloud())];
    final same = m == mode && why == note && next.length == ids.length && Iterable.generate(next.length).every((i) => next[i] == ids[i]);
    mode = m;
    note = why;
    if (!same) ids = next; // 和正在显示的一样就不换（列表不重建、不闪）
    _writeCache(tracks);
    error = tracks.isEmpty ? (m == DailyMode.fm ? '私人 FM 暂时没有返回歌曲，稍后再试' : '今天的推荐还没生成') : null;
  }

  /// 退出登录 / 切换网易云账号后清掉缓存。
  /// 每次 reset +1：重置前开始的加载回来后作废（登录 / 换账号时正在拉的游客 FM 不能写进新账号的缓存）。
  int _gen = 0;

  void reset() {
    _gen++;
    _running = null;
    _key = null;
    ids = const [];
    note = null;
    error = null;
    loading = false;
    notifyListeners();
    // 每日页正开着（登录后返回）：直接按新账号重新拉，不留空白页
    if (hasListeners) unawaited(ensure());
  }
}
