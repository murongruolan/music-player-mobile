// JS 引擎接口。移动端 / 桌面用 QuickJS（flutter_qjs，dart:ffi）；Web（截图构建）没有 dart:ffi，用桩实现。
export 'js_engine_stub.dart' if (dart.library.ffi) 'js_engine_qjs.dart' show createJsEngine;

abstract class JsEngine {
  /// 执行代码，返回值按 flutter_qjs 的规则转换（Promise → Future）。
  dynamic evaluate(String code, {String? name});

  /// 把 Dart 值（函数、Map、字符串…）挂到 globalThis[key]。
  void setGlobal(String key, Object? value);

  void close();
}
