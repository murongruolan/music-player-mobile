// captcha.la 人机验证的内嵌 WebView 桥接。
// 桥接页加载 captcha.la 官方 loader（与桌面端 AuthModal.vue 同一集成方式），
// 把验证控件渲染成「绑定框」形态；onSuccess 的 passToken 经 JavascriptChannel 回传 Dart。
//
// passToken 单用：发验证码（邮箱验证开启）或注册（邮箱验证关闭）时由调用方传给服务端。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/state.dart';
import '../core/tokens.dart';
import '../ui/icons.dart';

class CaptchaLaBridge extends StatefulWidget {
  final String appKey;
  final String action;
  final ValueChanged<String>? onVerified; // passToken
  final ValueChanged<String>? onError; // 错误文案
  const CaptchaLaBridge({super.key, required this.appKey, this.action = 'register', this.onVerified, this.onError});

  @override
  State<CaptchaLaBridge> createState() => _CaptchaLaBridgeState();
}

class _CaptchaLaBridgeState extends State<CaptchaLaBridge> {
  late final WebViewController _ctl;
  var _ready = false;
  var _verified = false;

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _ready = true),
      ))
      ..addJavaScriptChannel('CaptchaChannel', onMessageReceived: (m) {
        if (!mounted) return;
        try {
          final j = jsonDecode(m.message) as Map<String, dynamic>;
          final token = j['token'] as String?;
          final error = j['error'] as String?;
          if (token != null && token.isNotEmpty) {
            setState(() => _verified = true);
            widget.onVerified?.call(token);
          } else {
            widget.onError?.call(error ?? '人机验证失败，请重试');
          }
        } catch (_) {
          widget.onError?.call('人机验证回调解析失败');
        }
      })
      ..loadHtmlString(_bridgeHtml(appKey: widget.appKey, action: widget.action));
  }

  /// 重新验证（失败 / token 已被消费后重试）。
  void retry() {
    setState(() => _verified = false);
    _ctl.runJavaScript('typeof startCaptcha === "function" && startCaptcha();');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _verified ? pal.ok.withValues(alpha: .08) : pal.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _verified ? pal.ok.withValues(alpha: .5) : pal.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ic(_verified ? 'check' : 'shield'), size: 15, color: _verified ? pal.ok : pal.t2),
          const SizedBox(width: 6),
          Expanded(child: Text(_verified ? '人机验证已通过' : '人机验证（captcha.la）', style: ts(13, w: FontWeight.w600, c: _verified ? pal.ok : pal.t1))),
          if (!_ready) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: WebViewWidget(controller: _ctl),
        ),
      ]),
    );
  }
}

/// 桥接页：captcha.la 官方 loader + bind 控件 + token 回传通道。
/// 样式与桌面端 AuthModal.vue 的 .captcha-bind 一致（深色由 WebView 外部留白适配）。
String _bridgeHtml({required String appKey, required String action}) {
  final cfg = jsonEncode({'appKey': appKey, 'action': action});
  return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html,body{margin:0;padding:0;background:transparent;font-family:-apple-system,system-ui,sans-serif;}
  .captcha-bind{display:flex;align-items:center;gap:10px;padding:10px 12px;border:1px solid #e5e7eb;border-radius:8px;cursor:pointer;background:#fff;user-select:none;margin:2px 0 6px;min-height:44px;box-sizing:border-box;}
  .captcha-bind .cb-box{width:18px;height:18px;border:2px solid #d1d5db;border-radius:4px;display:inline-flex;align-items:center;justify-content:center;font-size:13px;color:#16a34a;flex:none;}
  .captcha-bind .cb-text{flex:1;font-size:14px;color:#374151;}
  .captcha-bind .cb-brand{font-size:12px;color:#9ca3af;}
  .captcha-bind.verified{border-color:#16a34a;}
  .captcha-bind.verified .cb-box{border-color:#16a34a;}
</style></head>
<body>
<div id="sollin-captcha-bind"></div>
<script src="https://cdn.captcha-cdn.net/captchala-loader.js"></script>
<script>
  var cfg = $cfg;
  function post(msg) { try { CaptchaChannel.postMessage(JSON.stringify(msg)); } catch (e) {} }
  function startCaptcha() {
    try {
      if (typeof Captchala === 'undefined') { post({error: '验证组件加载失败'}); return; }
      Captchala.init({ appKey: cfg.appKey, product: 'bind', action: cfg.action || 'register', lang: 'auto' })
        .onSuccess(function (res) { post({ token: (res && res.token) || '' }); })
        .onError(function (err) { post({ error: String((err && err.message) || '人机验证失败') }); })
        .bindTo('#sollin-captcha-bind');
      document.documentElement.style.background = 'transparent';
    } catch (e) { post({ error: String(e && e.message || e) }); }
  }
  if (typeof window.loadCaptchala === 'function') {
    window.loadCaptchala(startCaptcha, function () { post({ error: '验证组件加载失败' }); });
  } else {
    setTimeout(startCaptcha, 600); // loader 就绪兜底
  }
</script>
</body></html>''';
}
