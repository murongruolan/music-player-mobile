// 悬浮歌词 / 画中画歌词 + 桌面图标：Dart 侧对接原生（通道 lyra/native）。
// - Android：系统悬浮窗（需要「显示在其他应用上层」权限），App 在后台且正在播放时显示；
// - iOS：画中画小窗（系统不允许画悬浮窗），用户在设置里打开，之后切到后台自动进画中画。
// 只在换句 / 暂停 / 换歌 / 拖进度时推送，句内染色进度由原生按时钟自己算。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../data/mock.dart';
import 'app_log.dart';
import 'state.dart';
import 'tokens.dart';
import '../ui/kit.dart' show showLDialog, BtnKind, rootNav;

const _ch = MethodChannel('lyra/native');

bool get nativeSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get isIOS => !kIsWeb && Platform.isIOS;

/// 悬浮歌词样式（本机，不同步：位置 / 字号跟屏幕有关）。
class FloatStyle {
  double size = 18;
  int color = 0; // 0 = 跟随主题色，否则 ARGB
  double bg = .45;
  int y = -1; // 距屏幕顶部的像素，-1 = 默认位置
  bool trans = false; // 第二行显示翻译（没有翻译时显示下一句）
  int layout = 1; // iOS 画中画：0 = 两行居中，1 = 本句左上 / 下一句右下

  Map<String, dynamic> toJson() => {'size': size, 'color': color, 'bg': bg, 'y': y, 'trans': trans, 'layout': layout};
  void load(Map<String, dynamic> j) {
    size = (j['size'] as num? ?? size).toDouble();
    color = (j['color'] as num? ?? color).toInt();
    bg = (j['bg'] as num? ?? bg).toDouble();
    y = (j['y'] as num? ?? y).toInt();
    trans = j['trans'] as bool? ?? trans;
    layout = (j['layout'] as num? ?? layout).toInt();
  }
}

class FloatLyricCtl {
  FloatLyricCtl(this._app);
  final AppState _app;
  final style = FloatStyle();
  static const _kStyle = 'float.style.v1';

  bool _foreground = true;
  int? _lastColor;
  bool? _lastLock;
  bool _shown = false;
  String? _sig;
  DateTime _pushedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    if (!nativeSupported) return;
    try {
      final raw = await _app.net?.prefs.read(_kStyle);
      if (raw != null) style.load(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    _ch.setMethodCallHandler(_onNative);
    await _pushStyle();
  }

  void _saveStyle() => unawaited(_app.net?.prefs.write(_kStyle, jsonEncode(style.toJson())));

  Future<dynamic> _onNative(MethodCall c) async {
    switch (c.method) {
      case 'float.moved':
        style.y = (c.arguments as num).toInt();
        _saveStyle();
      case 'float.size':
        style.size = (c.arguments as num).toDouble();
        _saveStyle();
        _app.notify();
      case 'float.locked':
        _app.update(() => _app.set.floatLock = c.arguments == true);
      case 'float.closed':
        _shown = false;
        if (!isIOS || _app.set.floatLyric) _app.update(() => _app.set.floatLyric = false);
      case 'float.toggle':
        // 画中画小窗 / 悬浮歌词上的播放 / 暂停键（Android 不带参数 = 切换）
        if (c.arguments == null || (c.arguments == true) != _app.playing) _app.toggle();
      case 'float.prev':
        _app.prev();
      case 'float.next':
        _app.next();
      case 'float.open':
        break; // 原生侧已拉起 App
      case 'float.skip':
        final d = (c.arguments as num?)?.toDouble() ?? 0;
        _app.seek(_app.pos.value + d);
      case 'float.failed':
        _shown = false;
        _app.notice?.call('画中画歌词没能打开：${c.arguments}', 'info');
    }
    return null;
  }

  Future<T?> _call<T>(String m, [Object? args]) async {
    if (!nativeSupported) return null;
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    } catch (e) {
      AppLog.instance.add('悬浮歌词', '$m 失败：$e');
      return null;
    }
  }

  /// 主题色（ARGB）：style.color 为 0 时用当前主题的强调色。
  int get _color => style.color != 0 ? style.color : accents[_app.accent.clamp(0, accents.length - 1)].fill.toARGB32();

  Future<void> _pushStyle() => _call('float.style', {'size': style.size.toDouble(), 'color': _color, 'bg': style.bg.toDouble(), 'locked': _app.set.floatLock, 'y': style.y, 'layout': style.layout});

  /// 样式改了（设置页 / 主题色 / 锁定）。
  Future<void> applyStyle() async {
    _saveStyle();
    await _pushStyle();
    _sig = null;
  }

  Future<bool> canDraw() async => await _call<bool>('float.canDraw') ?? false;
  Future<void> requestPermission() => _call('float.request');

  /// 设置页打开 / 关闭开关。返回是否真的打开了（Android 没授权时为 false，并跳去授权页）。
  Future<bool> setEnabled(bool on) async {
    if (!on) {
      _app.update(() => _app.set.floatLyric = false);
      await _hide();
      return false;
    }
    if (!isIOS && !await canDraw()) {
      // 先说明要什么权限、去哪开，用户点「去设置」才跳（直接跳系统页，不熟悉手机的人会看不懂）
      if (!await explainOverlayPermission('桌面悬浮歌词')) return false;
      _pendingEnable = true; // 从系统授权页回来时自动打开
      await requestPermission();
      return false;
    }
    _pendingEnable = false;
    _app.update(() => _app.set.floatLyric = true);
    await _pushStyle();
    if (isIOS) {
      // 画中画必须在前台由用户操作打开；之后切后台系统会自动带走小窗
      _sig = null;
      tick(force: true);
      _shown = await _call<bool>('float.show') ?? false;
    } else {
      _sync();
    }
    return true;
  }

  bool _pendingEnable = false;
  int _showFails = 0;
  DateTime _retryAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 需要「显示在其他应用上层」权限时的说明弹窗。返回 true = 用户点了「去设置」。
  static Future<bool> explainOverlayPermission(String feature) async {
    final ctx = rootNav.currentContext;
    if (ctx == null) return true;
    final c = Completer<bool>();
    await showLDialog<void>(ctx,
        icon: 'layers',
        title: '需要悬浮窗权限',
        body: '「$feature」要显示在其他应用上面，需要你在系统设置里允许 Lyra「显示在其他应用的上层」（有的手机叫「悬浮窗」）。\n\n点「去设置」后，在列表里找到 Lyra 打开开关，再返回 Lyra 就会自动开启。',
        dismissible: true,
        actions: [
          ('暂不开启', BtnKind.sec, () => c.complete(false)),
          ('去设置', BtnKind.pri, () => c.complete(true)),
        ]);
    if (!c.isCompleted) c.complete(false);
    return c.future;
  }

  void setForeground(bool fg) {
    _foreground = fg;
    // 回到前台：Android 上悬浮歌词一律收起（不管 Dart 这边记的状态，防止原生窗口残留，
    // 例如换桌面图标时 Activity 被系统重建）
    if (fg && !isIOS && nativeSupported) {
      _shown = false;
      unawaited(_call('float.hide'));
    }
    if (fg && _pendingEnable) {
      _pendingEnable = false;
      unawaited(canDraw().then((ok) {
        if (!ok) return;
        unawaited(setEnabled(true));
        _app.notice?.call('已开启桌面悬浮歌词，切到后台播放时显示', 'layers');
      }));
    }
    if (!isIOS) _sync();
  }

  bool get _wantAndroid => _app.set.floatLyric && !_foreground && _app.hasSong && _app.playing;

  /// Android：后台 + 正在播放才显示（App 里已经有歌词，前台不重复挡视线；暂停时收起）。
  void _sync() {
    if (isIOS || !nativeSupported) return;
    final want = _wantAndroid;
    if (want && !_shown) {
      if (DateTime.now().isBefore(_retryAt)) return; // 上次没显示成功：退避，别每 50ms 重试一次
      _shown = true;
      unawaited(() async {
        final ok = await _call<bool>('float.show') ?? false;
        if (!ok) {
          _shown = false;
          _showFails++;
          _retryAt = DateTime.now().add(Duration(seconds: math.min(60, 2 << math.min(5, _showFails))));
          // 权限被收回：关掉开关，免得一直静默失败
          if (!await canDraw()) _app.update(() => _app.set.floatLyric = false);
          return;
        }
        _showFails = 0;
        _sig = null;
        tick(force: true);
      }());
    } else if (!want && _shown) {
      unawaited(_hide());
    }
  }

  Future<void> _hide() async {
    _shown = false;
    await _call('float.hide');
  }

  /// AppState._tick 每 50ms 调一次：句子 / 播放态 / 歌变了才推送；播放中每 5 秒校一次时钟。
  void tick({bool force = false}) {
    if (!nativeSupported) return;
    if (!_app.set.floatLyric) {
      // 开关关着但窗口还在（异常残留）：收起
      if (_shown && !isIOS) unawaited(_hide());
      return;
    }
    if (!isIOS) _sync();
    if (_color != _lastColor || _app.set.floatLock != _lastLock) {
      _lastColor = _color;
      _lastLock = _app.set.floatLock;
      unawaited(_pushStyle()); // 换了主题色 / 在设置里解锁
    }
    if (!_shown && !(isIOS && force)) return;
    if (!_app.hasSong) return;
    final ls = lyrics;
    final has = ls.length >= 2;
    final k = has ? _app.lyricIndex.clamp(0, ls.length - 1) : 0;
    final sig = '${_app.cur}|${_app.lyricsVersion}|$k|${_app.playing}|${style.trans}';
    final now = DateTime.now();
    if (!force && sig == _sig && !(_app.playing && now.difference(_pushedAt).inSeconds >= 5)) return;
    _sig = sig;
    _pushedAt = now;
    final s = _app.song;
    String text, next;
    double start = 0, end = 0;
    var keys = const <double>[];
    if (has) {
      final l = ls[k];
      keys = l.fillKeys();
      text = l.text.trim().isEmpty ? '♪' : l.text.trim();
      final tr = l.trans.trim();
      next = style.trans && tr.isNotEmpty ? tr : (k + 1 < ls.length ? ls[k + 1].text.trim() : '');
      start = l.t;
      end = k + 1 < ls.length ? ls[k + 1].t : l.t + l.d;
      if (l.d > 0 && l.t + l.d < end) end = l.t + l.d;
    } else {
      text = s.title;
      next = s.artist;
    }
    unawaited(_call('float.update', {
      'text': text,
      'next': next,
      'start': start.toDouble(),
      'end': end.toDouble(),
      'pos': (_app.smoothPos + _app.set.loff).toDouble(),
      'playing': _app.playing,
      'speed': _app.speed.toDouble(),
      'keys': keys, // 句内染色关键点（和 App 内歌词同一套时间）
    }));
  }

  // ---------------------------------------------------------------- 桌面图标

  Future<String?> currentIcon() => _call<String>('icon.current');

  /// 换桌面图标。返回是否成功（不支持的平台 / 系统拒绝为 false）。
  /// Android 换图标会让系统重建 Activity：顺手把悬浮歌词收起，回到前台时按开关重新决定。
  Future<bool> setIcon(String id) async {
    final ok = await _call<bool>('icon.set', {'id': id}) ?? false;
    if (!isIOS && !_wantAndroid) {
      _shown = false;
      unawaited(_call('float.hide'));
    }
    return ok;
  }
}
