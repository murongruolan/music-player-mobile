// 应用日志与崩溃记录（设置 → 关于与更新 → 诊断）。
// - 日志：内存里最近 400 条（提示气泡、播放错误、debugPrint、崩溃摘要），「应用日志」把它们复制到剪贴板；
// - 崩溃：FlutterError / 未捕获的异步错误，本机保留最近 20 条（prefs），开了「自动上报崩溃」时经埋点上报。
import 'dart:collection';
import 'dart:convert';
import '../net/storage.dart';

class CrashRecord {
  final DateTime at;
  final String message, stack;
  const CrashRecord(this.at, this.message, this.stack);
  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'message': message, 'stack': stack};
  static CrashRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return CrashRecord(at, '${j['message'] ?? ''}', '${j['stack'] ?? ''}');
  }
}

class AppLog {
  AppLog._();
  static final instance = AppLog._();

  static const _max = 400, _maxCrash = 20, _kCrash = 'diag.crashes.v1';
  final _lines = ListQueue<String>();
  final _crashes = <CrashRecord>[];
  KvStore? _prefs;

  /// 新崩溃的上报出口（main.dart 按「自动上报崩溃」开关接到埋点）。
  void Function(CrashRecord c)? onCrash;

  /// 最新的在前。
  List<CrashRecord> get crashes => List.unmodifiable(_crashes);
  int get length => _lines.length;

  Future<void> attach(KvStore? prefs) async {
    _prefs = prefs;
    if (prefs == null) return;
    try {
      final l = jsonDecode(await prefs.read(_kCrash) ?? '[]');
      if (l is List) _crashes.insertAll(0, l.map(CrashRecord.fromJson).whereType<CrashRecord>());
    } catch (_) {}
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String stamp(DateTime t) => '${t.month}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  void add(String tag, String msg) {
    _lines.addLast('${stamp(DateTime.now())} [$tag] ${msg.replaceAll('\n', ' ⏎ ')}');
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
  }

  void crash(Object error, StackTrace? stack) {
    final st = (stack?.toString() ?? '').split('\n').take(40).join('\n');
    final c = CrashRecord(DateTime.now(), '$error'.trim(), st);
    _crashes.insert(0, c);
    if (_crashes.length > _maxCrash) _crashes.removeRange(_maxCrash, _crashes.length);
    add('崩溃', c.message.split('\n').first);
    _prefs?.write(_kCrash, jsonEncode([for (final x in _crashes) x.toJson()]));
    onCrash?.call(c);
  }

  void clearCrashes() {
    _crashes.clear();
    _prefs?.delete(_kCrash);
  }

  /// 复制给开发者的全文：[header]（版本、设备）+ 最近的日志 + 最近 3 条崩溃的堆栈。
  String dump(String header) {
    final b = StringBuffer(header)..writeln()..writeln('---- 日志（${_lines.length} 条）----');
    for (final l in _lines) {
      b.writeln(l);
    }
    if (_crashes.isNotEmpty) {
      b.writeln('---- 崩溃（共 ${_crashes.length} 条，最近 3 条）----');
      for (final c in _crashes.take(3)) {
        b
          ..writeln('${stamp(c.at)} ${c.message}')
          ..writeln(c.stack)
          ..writeln();
      }
    }
    return b.toString();
  }
}
