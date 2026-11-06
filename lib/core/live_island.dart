// 灵动岛 / 锁屏歌词（iOS 16.1+ 的实时活动）：Dart 侧。
// 原生在 ios/Runner/LiveIsland.swift，界面在 ios/LyraWidget（小组件扩展）。
// - 系统只允许 App 在前台时开始活动：在前台开始播放时开始，之后切后台照常更新；
// - 只在换句 / 暂停 / 换歌 / 拖进度时推送，进度条由系统按时间自己走；
// - 没有灵动岛的机型（iOS 16.1+）也会在锁屏显示。
import 'dart:async';

import 'package:flutter/services.dart';

import '../data/mock.dart';
import 'app_log.dart';
import 'float_lyric.dart' show isIOS;
import 'state.dart';

const _ch = MethodChannel('lyra/native');

class LiveIslandCtl {
  LiveIslandCtl(this._app);
  final AppState _app;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  bool _started = false; // 活动已开始：之后暂停也继续推送（显示暂停态）
  bool _busy = false;
  String? _sig;
  double _anchor = 0; // 上次推送的「进度 0 的时刻」（秒），差太多说明拖了进度
  DateTime _pushedAt = _epoch;
  DateTime _retryAt = _epoch;
  String? _lastError;

  /// 系统是否允许（iOS 16.1+ 且用户没在系统设置里关掉实时活动）。
  Future<bool> supported() async {
    if (!isIOS) return false;
    try {
      return await _ch.invokeMethod<bool>('island.supported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 设置页关掉开关。
  void setEnabled(bool on) {
    _app.update(() => _app.set.islandLyric = on);
    _retryAt = _epoch;
    if (!on) unawaited(end());
  }

  Future<void> end() async {
    final was = _started;
    _started = false;
    _sig = null;
    if (!isIOS || !was) return;
    try {
      await _ch.invokeMethod<void>('island.end');
    } catch (_) {}
  }

  /// AppState._tick 每 50ms 调一次。
  void tick() {
    if (!isIOS) return;
    if (!_app.set.islandLyric || !_app.hasSong) {
      if (_started) unawaited(end());
      return;
    }
    if (!_started && !_app.playing) return; // 没在播就不弹出来
    final now = DateTime.now();
    if (_busy || now.isBefore(_retryAt)) return;

    final ls = lyrics;
    final has = ls.length >= 2;
    final k = has ? _app.lyricIndex.clamp(0, ls.length - 1) : 0;
    final speed = _app.speed <= 0 ? 1.0 : _app.speed.toDouble();
    final pos = _app.smoothPos.toDouble();
    final anchor = now.millisecondsSinceEpoch / 1000 - pos / speed;
    final tint = _app.floatLyric.playedColor & 0xFFFFFF;
    final trans = _app.floatLyric.style.trans;
    final dur = _app.song.dur.toDouble();
    final sig = '${_app.cur}|${_app.lyricsVersion}|$k|${_app.playing}|$tint|$dur|$trans|$speed';
    final since = now.difference(_pushedAt).inMilliseconds;
    final seeked = _app.playing && (anchor - _anchor).abs() > 1.5;
    // 歌词没变时每 15 秒补推一次（封面是异步下载的，补上缩略图）
    final due = sig != _sig || seeked || (_app.playing && since > 15000);
    if (!due || since < 800) return; // 系统对频繁更新会限流：最快 0.8 秒一次

    String line = '', next = '';
    if (has) {
      final l = ls[k];
      line = l.text.trim().isEmpty ? '♪' : l.text.trim();
      final tr = l.trans.trim();
      next = trans && tr.isNotEmpty ? tr : (k + 1 < ls.length ? ls[k + 1].text.trim() : '');
    }
    final s = _app.song;
    _sig = sig;
    _anchor = anchor;
    _pushedAt = now;
    _busy = true;
    unawaited(() async {
      String? r;
      try {
        r = await _ch.invokeMethod<String>('island.update', {
          'title': s.title,
          'artist': s.artist,
          'line': line,
          'next': next,
          'playing': _app.playing,
          'pos': pos,
          'dur': dur,
          'speed': speed,
          'tint': tint,
        });
      } on MissingPluginException {
        r = 'unsupported';
      } catch (e) {
        r = 'error: $e';
      } finally {
        _busy = false;
      }
      _onResult(r ?? 'unsupported');
    }());
  }

  void _onResult(String r) {
    final now = DateTime.now();
    if (r == 'ok') {
      _started = true;
      _lastError = null;
      return;
    }
    _sig = null; // 没推成：下次重试
    switch (r) {
      case 'background':
        _started = false;
        _retryAt = now.add(const Duration(seconds: 3)); // 回到前台就能开始
      case 'disabled':
        _started = false;
        _retryAt = now.add(const Duration(seconds: 30)); // 用户在系统设置里关了实时活动
      case 'unsupported':
        _started = false;
        _retryAt = now.add(const Duration(days: 1)); // iOS 16.1 以下
      default:
        if (r != _lastError) AppLog.instance.add('灵动岛', r);
        _lastError = r;
        _retryAt = now.add(const Duration(seconds: 10));
    }
  }
}
