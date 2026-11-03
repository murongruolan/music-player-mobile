// 真实联网冒烟测试的公共部分。平时跳过；LIVE=1 时运行（CI：手动触发 .github/workflows/platform-live.yml）。
// 每个用例把关键结果打印出来（数量、第一条），方便在 CI 日志里看各接口在海外 runner 上的实际表现。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/http.dart';

final bool live = Platform.environment['LIVE'] == '1';

PlatformHttp liveHttp() => PlatformHttp(log: (l) => stdout.writeln(l));

/// 跑一个接口：成功打印摘要，失败打印原因但不让整个文件失败（[required] = true 时失败算测试失败）。
Future<T?> probe<T>(String name, Future<T> Function() f, String Function(T) summary, {bool required = false}) async {
  try {
    final r = await f();
    stdout.writeln('✅ $name: ${summary(r)}');
    return r;
  } catch (e, s) {
    stdout.writeln('❌ $name: $e');
    if (required) fail('$name failed: $e\n$s');
    return null;
  }
}
