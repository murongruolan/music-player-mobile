// settings 同步文档的内容：外观、播放、歌词、下载等本机设置。
// 只同步「跟人走」的偏好；「实时同步」开关本身（cloudSync）每台设备自己决定，不同步。
// 读取时只认识的键才生效，类型不对的忽略——别的版本 / 别的客户端推上来的未知字段不会把本机设置弄坏。
import 'package:flutter/material.dart';
import '../net/json.dart';
import 'state.dart';

typedef _F<T> = (T Function(Settings), void Function(Settings, T));

final Map<String, _F<bool>> _bools = {
  'trans': ((s) => s.trans, (s, v) => s.trans = v),
  'roma': ((s) => s.roma, (s, v) => s.roma = v),
  'conv': ((s) => s.conv, (s, v) => s.conv = v),
  'blur': ((s) => s.blur, (s, v) => s.blur = v),
  'glow': ((s) => s.glow, (s, v) => s.glow = v),
  'fade': ((s) => s.fade, (s, v) => s.fade = v),
  'autoplay': ((s) => s.autoplay, (s, v) => s.autoplay = v),
  'autoOpen': ((s) => s.autoOpen, (s, v) => s.autoOpen = v),
  'keepAwake': ((s) => s.keepAwake, (s, v) => s.keepAwake = v),
  'smart': ((s) => s.smart, (s, v) => s.smart = v),
  'gradual': ((s) => s.gradual, (s, v) => s.gradual = v),
  'crossScript': ((s) => s.crossScript, (s, v) => s.crossScript = v),
  'crossPlat': ((s) => s.crossPlat, (s, v) => s.crossPlat = v),
  'autoNext': ((s) => s.autoNext, (s, v) => s.autoNext = v),
  'nQ': ((s) => s.nQ, (s, v) => s.nQ = v),
  'nS': ((s) => s.nS, (s, v) => s.nS = v),
  'nA': ((s) => s.nA, (s, v) => s.nA = v),
  'allowDown': ((s) => s.allowDown, (s, v) => s.allowDown = v),
  'floatLyric': ((s) => s.floatLyric, (s, v) => s.floatLyric = v),
  'floatLock': ((s) => s.floatLock, (s, v) => s.floatLock = v),
  'btLyric': ((s) => s.btLyric, (s, v) => s.btLyric = v),
  'sbLyric': ((s) => s.sbLyric, (s, v) => s.sbLyric = v),
  'dlCover': ((s) => s.dlCover, (s, v) => s.dlCover = v),
  'dlLyric': ((s) => s.dlLyric, (s, v) => s.dlLyric = v),
  'wifiOnly': ((s) => s.wifiOnly, (s, v) => s.wifiOnly = v),
  'cache': ((s) => s.cache, (s, v) => s.cache = v),
  'vinylSpin': ((s) => s.vinylSpin, (s, v) => s.vinylSpin = v),
  'haptics': ((s) => s.haptics, (s, v) => s.haptics = v),
  'pitch': ((s) => s.pitch, (s, v) => s.pitch = v),
  'finishSong': ((s) => s.finishSong, (s, v) => s.finishSong = v),
  'fadeStop': ((s) => s.fadeStop, (s, v) => s.fadeStop = v),
  'autoBackup': ((s) => s.autoBackup, (s, v) => s.autoBackup = v),
  'crash': ((s) => s.crash, (s, v) => s.crash = v),
  'navAutoMin': ((s) => s.navAutoMin, (s, v) => s.navAutoMin = v),
  'clipDetect': ((s) => s.clipDetect, (s, v) => s.clipDetect = v),
  'reduceMotion': ((s) => s.reduceMotion, (s, v) => s.reduceMotion = v),
  'standbyAuto': ((s) => s.standbyAuto, (s, v) => s.standbyAuto = v),
  'autoDowngrade': ((s) => s.autoDowngrade, (s, v) => s.autoDowngrade = v),
  'mobileLow': ((s) => s.mobileLow, (s, v) => s.mobileLow = v),
};

final Map<String, _F<double>> _doubles = {
  'lfs': ((s) => s.lfs, (s, v) => s.lfs = v),
  'ltfs': ((s) => s.ltfs, (s, v) => s.ltfs = v),
  'lgap': ((s) => s.lgap, (s, v) => s.lgap = v),
  'loff': ((s) => s.loff, (s, v) => s.loff = v),
  'dlConc': ((s) => s.dlConc, (s, v) => s.dlConc = v),
};

final Map<String, _F<String>> _strings = {
  'onlineQ': ((s) => s.onlineQ, (s, v) => s.onlineQ = v),
  'dlQ': ((s) => s.dlQ, (s, v) => s.dlQ = v),
  'mode': ((s) => s.mode, (s, v) => s.mode = v),
  'fontSize': ((s) => s.fontSize, (s, v) => s.fontSize = v),
};

Json exportSettings(AppState a) => {
      'theme': a.themeMode.name,
      'accent': a.accent,
      'bar': a.bar,
      'skin': a.skin,
      'bg': a.bg,
      'tone': a.tone,
      'appIcon': a.appIcon,
      'font': a.font,
      'dim': a.dim,
      'amWave': a.amWave,
      'particle': a.particle,
      'quality': a.quality,
      'homeMods': [for (final e in a.homeMods) [e.key, e.value]],
      'eq': a.eq,
      'eqPreset': a.eqPreset,
      'eqOn': a.eqOn,
      'crossOrder': a.crossOrder,
      'prefs': {
        for (final e in _bools.entries) e.key: e.value.$1(a.set),
        for (final e in _doubles.entries) e.key: e.value.$1(a.set),
        for (final e in _strings.entries) e.key: e.value.$1(a.set),
      },
    };

/// 应用云端设置。只改变化了的值；返回是否有改动。
bool importSettings(AppState a, Json j) {
  var changed = false;
  void str(String k, String cur, void Function(String) set) {
    final v = j[k];
    if (v is String && v.isNotEmpty && v != cur) {
      set(v);
      changed = true;
    }
  }

  final theme = ThemeMode.values.where((m) => m.name == j['theme']).firstOrNull;
  if (theme != null && theme != a.themeMode) {
    a.themeMode = theme;
    changed = true;
  }
  final acc = j['accent'];
  if (acc is int && acc >= 0 && acc < 6 && acc != a.accent) {
    a.accent = acc;
    changed = true;
  }
  str('bar', a.bar, (v) => a.bar = v);
  str('skin', a.skin, (v) => a.skin = v);
  str('bg', a.bg, (v) => a.bg = v);
  str('tone', a.tone, (v) => a.tone = v);
  str('appIcon', a.appIcon, (v) => a.appIcon = v);
  str('font', a.font, (v) => a.font = v);
  str('amWave', a.amWave, (v) => a.amWave = v);
  str('particle', a.particle, (v) => a.particle = v);
  str('quality', a.quality, (v) => a.quality = v);
  str('eqPreset', a.eqPreset, (v) => a.eqPreset = v);
  final dim = j['dim'];
  if (dim is num && dim.toDouble() != a.dim) {
    a.dim = dim.toDouble().clamp(0, 100).toDouble();
    changed = true;
  }
  final eqOn = j['eqOn'];
  if (eqOn is bool && eqOn != a.eqOn) {
    a.eqOn = eqOn;
    changed = true;
  }
  final eq = j['eq'];
  if (eq is List && eq.length == a.eq.length && eq.every((e) => e is num)) {
    final l = [for (final e in eq) (e as num).toDouble()];
    if (!_listEq(l, a.eq)) {
      a.eq = l;
      changed = true;
    }
  }
  final hm = j['homeMods'];
  if (hm is List) {
    final known = {for (final e in a.homeMods) e.key};
    final l = [for (final e in hm) if (e is List && e.length == 2 && known.contains(e[0]) && e[1] is bool) MapEntry<String, bool>(e[0] as String, e[1] as bool)];
    if (l.length == known.length && !_listEq(l.map((e) => '${e.key}=${e.value}').toList(), a.homeMods.map((e) => '${e.key}=${e.value}').toList())) {
      a.homeMods
        ..clear()
        ..addAll(l);
      changed = true;
    }
  }
  final co = j['crossOrder'];
  if (co is List && co.every((e) => e is String)) {
    final l = co.cast<String>();
    if (l.toSet().containsAll(a.crossOrder) && l.length == a.crossOrder.length && !_listEq(l, a.crossOrder)) {
      a.crossOrder
        ..clear()
        ..addAll(l);
      changed = true;
    }
  }
  final p = j['prefs'];
  if (p is Map) {
    for (final e in _bools.entries) {
      final v = p[e.key];
      if (v is bool && v != e.value.$1(a.set)) {
        e.value.$2(a.set, v);
        changed = true;
      }
    }
    for (final e in _doubles.entries) {
      final v = p[e.key];
      if (v is num && v.toDouble() != e.value.$1(a.set)) {
        e.value.$2(a.set, v.toDouble());
        changed = true;
      }
    }
    for (final e in _strings.entries) {
      final v = p[e.key];
      if (v is String && v.isNotEmpty && v != e.value.$1(a.set)) {
        e.value.$2(a.set, v);
        changed = true;
      }
    }
  }
  return changed;
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
