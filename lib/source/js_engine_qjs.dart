import 'package:flutter_qjs/flutter_qjs.dart';
import 'js_engine.dart';

JsEngine createJsEngine({int timeoutMs = 5000, int memoryLimit = 64 * 1024 * 1024}) => _Qjs(FlutterQjs(stackSize: 1024 * 1024, timeout: timeoutMs, memoryLimit: memoryLimit));

class _Qjs implements JsEngine {
  final FlutterQjs q;
  JSInvokable? _set;
  _Qjs(this.q);

  @override
  dynamic evaluate(String code, {String? name}) => q.evaluate(code, name: name);

  @override
  void setGlobal(String key, Object? value) {
    final set = _set ??= q.evaluate('(function (k, v) { globalThis[k] = v; })') as JSInvokable;
    set.invoke([key, value]);
  }

  @override
  void close() {
    _set?.free();
    _set = null;
    q.close();
  }
}
