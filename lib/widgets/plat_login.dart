// 平台账号登录（联网模式）：网易云扫码 / 导入 Cookie，QQ音乐导入 Cookie。
// 凭证经 AppState.savePlatformLogin 存系统钥匙串，只留在本机。演示模式的假流程在 sheets.dart 里。
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide PlatformException;
import 'package:qr/qr.dart';
import '../core/app_log.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart' show platformBy;
import '../data/models.dart' show Platform;
import '../platform/credentials.dart';
import '../platform/login/kugou_login.dart';
import '../platform/login/netease_login.dart';
import '../platform/models.dart' show PlatformException;
import '../platform/registry.dart' show platformError;
import '../ui/kit.dart';
import 'sheets.dart';

/// 打开某个平台的登录。[mode]：'扫码' / 'Cookie'（不支持的方式自动换成该平台支持的）。
void openRealPlatLogin(BuildContext context, String pid, {String mode = '扫码'}) {
  final p = platformBy(pid);
  if (pid == 'kuwo' || pid == 'migu') {
    return openPendingFeature(context, p.name, '${p.name}的公开内容不需要登录就能浏览和播放，平台本身也没有可接入的账号登录。');
  }
  if (!AppState.loginPlatforms.contains(pid)) {
    return openPendingFeature(context, '登录${p.name}', '${p.name}的手机验证码登录正在接入，完成后可以在这里登录。');
  }
  final modes = switch (pid) { 'netease' => const ['扫码', 'Cookie'], 'kugou' => const ['验证码'], _ => const ['Cookie'] };
  var m = modes.contains(mode) ? mode : modes.first;
  showLSheet(context, title: '登录${p.name}', builder: (c) => StatefulBuilder(builder: (c, set) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(children: [
            if (modes.length > 1) ...[Seg(modes, m, (v) => set(() => m = v), margin: EdgeInsets.zero), const SizedBox(height: 18)],
            if (m == '验证码') _KugouPhoneLogin(p) else if (m == '扫码') _NeteaseQrLogin(p) else _CookieLogin(p),
          ]),
        );
      }));
}

Future<void> _finish(BuildContext sheet, PlatformCredential cred, Platform p) async {
  final app = sheet.appRead;
  AppLog.instance.add('平台登录', '${p.name}登录成功（${cred.vipActive ? '会员' : '非会员'}）');
  await app.savePlatformLogin(cred);
  if (sheet.mounted) Navigator.of(sheet).pop();
  toast('已登录${p.name}${(cred.nickname?.isNotEmpty ?? false) ? ' · ${cred.nickname}' : ''}', 'check');
}

// ---------------------------------------------------------------- 网易云扫码

class _NeteaseQrLogin extends StatefulWidget {
  final Platform p;
  const _NeteaseQrLogin(this.p);
  @override
  State<_NeteaseQrLogin> createState() => _NeteaseQrLoginState();
}

class _NeteaseQrLoginState extends State<_NeteaseQrLogin> {
  String? key, error, nick;
  QrImage? img;
  var state = NeteaseQrState.waiting;
  Timer? _t;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _t?.cancel();
    setState(() {
      key = null;
      img = null;
      error = null;
      nick = null;
      state = NeteaseQrState.waiting;
    });
    try {
      final k = await context.appRead.neteaseLogin.qrKey();
      if (!mounted) return;
      final qr = QrCode.fromData(data: context.appRead.neteaseLogin.qrContent(k), errorCorrectLevel: QrErrorCorrectLevel.M);
      setState(() {
        key = k;
        img = QrImage(qr);
      });
      _t = Timer.periodic(const Duration(milliseconds: 2500), (_) => _poll());
    } catch (e) {
      _logFail('网易云取二维码', e);
      if (mounted) setState(() => error = _msg(e));
    }
  }

  Future<void> _poll() async {
    final k = key;
    if (k == null || _busy) return;
    _busy = true;
    try {
      final app = context.appRead;
      final r = await app.neteaseLogin.qrCheck(k);
      if (!mounted || k != key) return;
      switch (r.state) {
        case NeteaseQrState.waiting:
          break;
        case NeteaseQrState.scanned:
          setState(() {
            state = r.state;
            nick = r.nickname;
          });
        case NeteaseQrState.expired:
          _t?.cancel();
          setState(() => state = r.state);
        case NeteaseQrState.failed:
          _t?.cancel();
          AppLog.instance.add('平台登录', '网易云扫码失败：${r.message}');
          setState(() {
            state = r.state;
            error = r.message;
          });
        case NeteaseQrState.ok:
          _t?.cancel();
          setState(() => state = r.state);
          final cred = await app.neteaseLogin.credentialFrom(r.cookie);
          if (mounted) await _finish(context, cred, widget.p);
      }
    } catch (e) {
      // 单次轮询失败（网络抖动）不打断，下一次再试；拿账号信息失败才显示
      if (mounted && state == NeteaseQrState.ok) {
        _logFail('网易云读取账号信息', e);
        setState(() {
          state = NeteaseQrState.failed;
          error = _msg(e);
        });
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final dim = state == NeteaseQrState.expired || state == NeteaseQrState.failed || state == NeteaseQrState.scanned || state == NeteaseQrState.ok;
    final tip = switch (state) {
      NeteaseQrState.waiting => img == null ? (error == null ? '正在获取二维码…' : '二维码没有获取到') : '打开网易云音乐 App，扫一扫登录',
      NeteaseQrState.scanned => '${(nick?.isNotEmpty ?? false) ? '$nick，' : ''}已扫码，请在手机上确认',
      NeteaseQrState.ok => '登录成功，正在读取账号信息…',
      NeteaseQrState.expired => '二维码已过期',
      NeteaseQrState.failed => '登录没有成功',
    };
    return Column(children: [
      GestureDetector(
        onTap: state == NeteaseQrState.expired || state == NeteaseQrState.failed || error != null ? _start : null,
        child: Container(
          width: 210,
          height: 210,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Stack(alignment: Alignment.center, children: [
            if (img != null) AnimatedOpacity(duration: Tk.base, opacity: dim ? .15 : 1, child: CustomPaint(size: const Size(182, 182), painter: _QrImagePainter(img!))),
            if (img == null && error == null) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF333333))),
            if (state == NeteaseQrState.scanned) const Icon(Icons.phonelink_ring_rounded, size: 56, color: Color(0xFF333333)),
            if (state == NeteaseQrState.ok) Icon(Icons.check_circle_rounded, size: 56, color: pal.ok),
            if (state == NeteaseQrState.expired || state == NeteaseQrState.failed || (img == null && error != null))
              const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.refresh_rounded, size: 44, color: Color(0xFF333333)), SizedBox(height: 4), Text('点击刷新', style: TextStyle(color: Color(0xFF333333), fontSize: 13))]),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Text(tip, textAlign: TextAlign.center, style: ts(14, w: FontWeight.w600, c: state == NeteaseQrState.ok ? pal.ok : pal.t1)),
      const SizedBox(height: 4),
      Text(error ?? '登录信息只保存在本机', textAlign: TextAlign.center, style: ts(12, c: error != null ? pal.danger : pal.t3, h: 1.5)),
      const SizedBox(height: 8),
    ]);
  }
}

class _QrImagePainter extends CustomPainter {
  final QrImage img;
  const _QrImagePainter(this.img);
  @override
  void paint(Canvas canvas, Size s) {
    final n = img.moduleCount;
    final cell = s.width / n;
    final p = Paint()..color = const Color(0xFF111111);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .3, cell + .3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrImagePainter o) => o.img != img;
}

// ---------------------------------------------------------------- 导入 Cookie

class _CookieLogin extends StatefulWidget {
  final Platform p;
  const _CookieLogin(this.p);
  @override
  State<_CookieLogin> createState() => _CookieLoginState();
}

class _CookieLoginState extends State<_CookieLogin> {
  final tc = TextEditingController();
  String? error;
  bool busy = false;

  bool get _qq => widget.p.id == 'qq';

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) return toast('剪贴板里没有内容', 'info');
    setState(() {
      tc.text = t;
      error = null;
    });
  }

  Future<void> _submit() async {
    final raw = tc.text.trim();
    if (raw.isEmpty) return setState(() => error = '先粘贴 Cookie');
    setState(() {
      busy = true;
      error = null;
    });
    final app = context.appRead;
    try {
      final cred = _qq ? await app.qqLogin.credentialFrom(raw) : await app.neteaseLogin.credentialFrom(raw);
      if (_qq && cred.extra[CredKey.txKeyst] == null && mounted) {
        toast('已登录，但 Cookie 里没有 qm_keyst，会员歌曲可能取不到播放地址', 'info');
      }
      if (mounted) await _finish(context, cred, widget.p);
    } catch (e) {
      _logFail('${widget.p.name} Cookie 登录', e);
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final how = _qq
        ? '在电脑浏览器登录 y.qq.com，打开开发者工具 → 网络，任选一个 y.qq.com 的请求，复制请求头里的整段 Cookie（需要包含 uin，会员取链还需要 qm_keyst）。'
        : '在电脑浏览器登录 music.163.com，打开开发者工具 → 网络，任选一个 music.163.com 的请求，复制请求头里的整段 Cookie（至少包含 MUSIC_U）。';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LField(controller: tc, label: _qq ? '粘贴 Cookie（uin=…; qm_keyst=…）' : '粘贴 Cookie（MUSIC_U=…）', icon: 'code', lines: 4, error: error, onChanged: (_) => setState(() => error = null)),
      const SizedBox(height: 8),
      Text(how, style: ts(12, c: pal.t3, h: 1.6)),
      const SizedBox(height: 6),
      Text('Cookie 只保存在本机钥匙串，用于以你的身份请求${widget.p.name}接口，不会上传。', style: ts(12, c: pal.t3, h: 1.6)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Btn.sec('粘贴', icon: 'paste', onTap: busy ? null : _paste)),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: Btn('验证并登录', busy: busy, onTap: busy ? null : _submit)),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}

String _msg(Object e) => e is PlatformException ? e.message : platformError(e);

/// 登录失败：界面上显示的原因同时写进应用日志（设置 → 关于 → 应用日志），方便排查。
void _logFail(String where, Object e) => AppLog.instance.add('平台登录', '$where失败：${e is PlatformException ? e.message : e}');

// ---------------------------------------------------------------- 酷狗手机验证码

class _KugouPhoneLogin extends StatefulWidget {
  final Platform p;
  const _KugouPhoneLogin(this.p);
  @override
  State<_KugouPhoneLogin> createState() => _KugouPhoneLoginState();
}

class _KugouPhoneLoginState extends State<_KugouPhoneLogin> {
  final phone = TextEditingController();
  final code = TextEditingController();
  KugouDevice? device;
  String? error;
  int cd = 0;
  Timer? _cdt;
  bool busy = false;

  @override
  void dispose() {
    _cdt?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (cd > 0) return;
    final app = context.appRead;
    final dev = device ??= KugouDevice.random(Random());
    setState(() {
      error = null;
      busy = true;
    });
    try {
      await app.kugouLogin.sendCode(phone.text, dev);
      if (!mounted) return;
      setState(() => cd = 60);
      _cdt = Timer.periodic(const Duration(seconds: 1), (t) {
        if (cd <= 1) {
          t.cancel();
          if (mounted) setState(() => cd = 0);
        } else {
          setState(() => cd--);
        }
      });
      toast('验证码已发送', 'phone');
    } on KugouCaptchaRequired {
      AppLog.instance.add('平台登录', '酷狗发验证码：需要人机验证');
      if (mounted) setState(() => error = '酷狗要求人机验证，请在酷狗官方 App 登录一次后再回来，或改用其它平台');
    } catch (e) {
      _logFail('酷狗发验证码', e);
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _login() async {
    if (code.text.trim().isEmpty) return setState(() => error = '请输入验证码');
    final app = context.appRead;
    final dev = device;
    if (dev == null) return setState(() => error = '请先获取验证码');
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final cred = await app.kugouLogin.loginByCode(phone.text, code.text.trim(), dev);
      if (mounted) await _finish(context, cred, widget.p);
    } catch (e) {
      _logFail('酷狗验证码登录', e);
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LField(controller: phone, label: '手机号', icon: 'phone', keyboard: TextInputType.phone, onChanged: (_) => setState(() => error = null)),
      const SizedBox(height: 10),
      LField(controller: code, label: '短信验证码', icon: 'key', keyboard: TextInputType.number, suffix: cd > 0 ? '${cd}s' : '获取验证码', onSuffix: busy ? null : _send, error: error, onChanged: (_) => setState(() => error = null)),
      const SizedBox(height: 14),
      Btn('登录', block: true, busy: busy, onTap: busy ? null : _login),
      const SizedBox(height: 10),
      Text('登录信息只保存在本机钥匙串，用于以你的身份获取播放地址。', style: ts(12, c: pal.t3, h: 1.6)),
      const SizedBox(height: 8),
    ]);
  }
}
