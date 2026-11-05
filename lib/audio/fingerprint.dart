// 听歌识曲 · 本机算指纹：在一个看不见的 WebView 里跑网易的指纹 WASM（assets/audio_match/）。
// Dart 里没有 WebAssembly 运行时（音源脚本用的 QuickJS 也不支持），所以借系统 WebView。
//
// 用法：把 [FingerprintEngine.view] 放进页面（1×1 像素，看不见；Android WebView 不挂到界面上时定时器会被限流），
// 等 [ready] 完成后调用 [compute]。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/app_log.dart';

class FingerprintEngine {
  late final WebViewController _ctl;
  final _ready = Completer<void>();
  final _pending = <int, Completer<String>>{};
  int _next = 0;

  FingerprintEngine() {
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('AfpChannel', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/audio_match/afp.html');
  }

  /// 指纹页加载完、GenerateFP 可用。
  Future<void> get ready => _ready.future.timeout(const Duration(seconds: 15), onTimeout: () => throw StateError('识曲组件加载超时'));

  /// 放进界面的 1×1 WebView。
  Widget view() => SizedBox(width: 1, height: 1, child: WebViewWidget(controller: _ctl));

  void _onMessage(JavaScriptMessage m) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(m.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (j.containsKey('ready')) {
      if (_ready.isCompleted) return;
      j['ready'] == true ? _ready.complete() : _ready.completeError(StateError('识曲组件加载失败'));
      return;
    }
    final c = _pending.remove(j['id']);
    if (c == null) return;
    final fp = j['fp'];
    if (fp is String && fp.isNotEmpty) {
      AppLog.instance.add('识曲', '指纹 ${j['ms']}ms · ${fp.length} 字符');
      c.complete(fp);
    } else {
      c.completeError(StateError('指纹计算失败：${j['error'] ?? '未知原因'}'));
    }
  }

  /// [pcm16]：8kHz 单声道 16 位小端 PCM（3 秒 = 48000 字节）。返回 base64 指纹。
  Future<String> compute(Uint8List pcm16) async {
    await ready;
    final id = _next++;
    final c = _pending[id] = Completer<String>();
    await _ctl.runJavaScript('lyraFP("${base64Encode(pcm16)}", $id)');
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(id);
      throw StateError('指纹计算超时');
    });
  }
}
