// 鉴权：使用须知 → 登录 / 注册（人机验证 + 邮箱验证码 + 强度条）→ 找回密码（3 步）；版本停用页。
// 人机验证为通用组件 [Captcha]：图形字符 / 滑块拼图 / 文字点选，由服务端决定类型（这里可手动切换演示）。
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../ui/brand.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';

final _isEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
int pwScore(String p) {
  if (p.isEmpty) return 0;
  var s = 0;
  if (p.length >= 8) s++;
  if (RegExp('[A-Z]').hasMatch(p) && RegExp('[a-z]').hasMatch(p)) s++;
  if (RegExp(r'\d').hasMatch(p)) s++;
  if (RegExp(r'[^\w]').hasMatch(p)) s++;
  return math.max(1, s);
}

class AuthFlow extends StatelessWidget {
  const AuthFlow({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final page = switch (app.authPage) {
      'forgot' => const ForgotPage(),
      'versionDisabled' => const VersionDisabledPage(),
      'disclaimer' => const DisclaimerPage(),
      _ => const LoginPage(),
    };
    return PalScope(
      pal: context.pal.forceDark,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 420), child: KeyedSubtree(key: ValueKey(app.authPage), child: page)),
    );
  }
}

/// 深色玻璃卡（从底部升起）。
class _AuthCard extends StatelessWidget {
  final Widget child;
  const _AuthCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Tk.out,
      builder: (_, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 60 * (1 - v)), child: ch)),
      child: Glass(
        radius: 30,
        blur: 14,
        color: const Color(0xA812121A),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool compact;
  final String sub;
  const _Brand({this.compact = false, this.sub = '听见光的形状'});
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(children: [
        const AppLogo(size: 48, float: true),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Lyra', style: ts(26, w: FontWeight.w800, c: Colors.white, ls: -.4)), Text(sub, style: ts(13, c: const Color(0xB3FFFFFF)))]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const AppLogo(size: 64, float: true),
      const SizedBox(height: 20),
      Text('Lyra', style: ts(34, w: FontWeight.w800, c: Colors.white, ls: -.6)),
      const SizedBox(height: 4),
      Text(sub, style: ts(15, c: const Color(0xB3FFFFFF))),
    ]);
  }
}

// ======================= 使用须知 =======================
class DisclaimerPage extends StatefulWidget {
  final bool readOnly;
  const DisclaimerPage({super.key, this.readOnly = false});
  @override
  State<DisclaimerPage> createState() => _DisclaimerPageState();
}

class _DisclaimerPageState extends State<DisclaimerPage> {
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final top = MediaQuery.of(context).padding.top;
    return PalScope(
      pal: pal.forceDark,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Ambient(
          child: ListView(padding: EdgeInsets.fromLTRB(26, top + 40, 26, 40), children: [
            if (widget.readOnly) Align(alignment: Alignment.centerLeft, child: IBtn('left', color: Colors.white, onTap: () => Navigator.of(context).pop())),
            const AppLogo(size: 64),
            const SizedBox(height: 22),
            Text('使用须知', style: ts(30, w: FontWeight.w800, c: Colors.white)),
            const SizedBox(height: 6),
            Text('开始之前，请花一分钟了解以下内容', style: ts(14, c: const Color(0x9EFFFFFF))),
            const SizedBox(height: 22),
            Glass(
              radius: 22,
              color: const Color(0xA812121A),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (final (i, (icon, t, d)) in const [
                    ('shield', '隐私', '聆听记录仅用于生成每日混音与统计，可随时在设置中清除。'),
                    ('layers', '音源', '解析脚本由你自行添加并对其合法性负责，Lyra 不提供、不存储任何音频内容。'),
                    ('cloud', '同步', '收藏与歌单可同步到你的账号或自建 WebDAV，同步内容不含音频文件。'),
                    ('info', '版本', '如当前版本被停止服务，App 会提示你更新到可用版本。'),
                  ].indexed)
                    Rise(
                      i,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(width: 30, height: 30, decoration: BoxDecoration(color: const Color(0x29F4D28A), borderRadius: BorderRadius.circular(9)), child: Icon(ic(icon), size: 18, color: const Color(0xFFF4D28A))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: ts(15, w: FontWeight.w600, c: Colors.white)), const SizedBox(height: 2), Text(d, style: ts(12.5, c: const Color(0x8CFFFFFF), h: 1.5))])),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 14),
              Press(
                onTap: () => app.update(() => app.agreed = !app.agreed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    _Check(app.agreed),
                    const SizedBox(width: 10),
                    Expanded(child: Text('我已阅读并同意《用户协议》与《隐私政策》', style: ts(13, c: const Color(0xBFFFFFFF)))),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              AnimatedOpacity(
                duration: Tk.base,
                opacity: app.agreed ? 1 : .45,
                child: Btn('同意并继续', block: true, onTap: () {
                  if (!app.agreed) {
                    toast('请先阅读并勾选同意', 'info');
                    return;
                  }
                  app.update(() {
                    app.seenDisclaimer = true;
                    app.authPage = 'login';
                  });
                }),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final bool on;
  const _Check(this.on);
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AnimatedContainer(
      duration: Tk.base,
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: on ? pal.acc : Colors.transparent, borderRadius: BorderRadius.circular(6), border: Border.all(color: on ? pal.acc : const Color(0x66FFFFFF), width: 1.5)),
      child: on ? Icon(ic('check'), size: 14, color: pal.ink) : null,
    );
  }
}

// ======================= 登录 / 注册 =======================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String seg = '登录';
  final id = TextEditingController(), pwd = TextEditingController(), email = TextEditingController(), rpwd = TextEditingController(), code = TextEditingController();
  final err = <String, String>{};
  int shake = 0, cd = 0;
  bool busy = false, remember = true, capOk = false, done = false;
  Timer? cdt;
  final capKey = GlobalKey<CaptchaState>();

  @override
  void initState() {
    super.initState();
    for (final c in [email, rpwd]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    cdt?.cancel();
    super.dispose();
  }

  void _err(Map<String, String> e) => setState(() {
        err
          ..clear()
          ..addAll(e);
        shake++;
      });

  Future<void> _busy(VoidCallback f) async {
    setState(() => busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => busy = false);
    f();
  }

  void _send() {
    if (cd > 0) return;
    if (!_isEmail.hasMatch(email.text)) return _err({'email': '先填写正确的邮箱'});
    if (!capOk) {
      capKey.currentState?.fail('请先完成人机验证');
      return;
    }
    setState(() => cd = 60);
    toast('验证码已发送至 ${email.text.replaceFirstMapped(RegExp(r'^(.).*(@.*)$'), (m) => '${m[1]}***${m[2]}')}', 'mail');
    cdt?.cancel();
    cdt = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => cd--);
      if (cd <= 0) t.cancel();
    });
  }

  void _login() {
    final e = <String, String>{};
    if (id.text.trim().isEmpty) e['id'] = '请输入邮箱或用户 ID';
    if (pwd.text.length < 6) e['pwd'] = '密码至少 6 位';
    if (e.isNotEmpty) return _err(e);
    _busy(_enter);
  }

  void _enter() {
    final app = context.appRead;
    app.update(() => app.authed = true);
  }

  void _register() {
    final app = context.appRead;
    final e = <String, String>{};
    if (!_isEmail.hasMatch(email.text)) e['email'] = '邮箱格式不正确';
    if (pwScore(rpwd.text) < 2 || rpwd.text.length < 8) e['rpwd'] = '密码至少 8 位，并包含数字或字母大小写';
    if (!capOk) {
      if (e.isNotEmpty) return _err(e);
      capKey.currentState?.fail('请先完成人机验证');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.text)) e['code'] = '请输入 6 位邮箱验证码';
    if (e.isNotEmpty) return _err(e);
    if (!app.agreed) {
      toast('请先勾选同意协议', 'info');
      return;
    }
    _busy(() => setState(() => done = true));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final mq = MediaQuery.of(context);
    final reg = seg == '注册';
    Widget form;
    if (reg && done) {
      form = Column(key: const ValueKey('done'), children: [
        const SizedBox(height: 10),
        const _DrawCheck(),
        const SizedBox(height: 14),
        Text('注册成功', style: ts(22, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 6),
        Text('欢迎加入 Lyra，已为你登录 ${email.text}', textAlign: TextAlign.center, style: ts(13.5, c: const Color(0xB3FFFFFF))),
        const SizedBox(height: 22),
        Btn('开始听歌', block: true, onTap: _enter),
      ]);
    } else if (!reg) {
      form = Column(key: const ValueKey('login'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LField(controller: id, label: '邮箱或用户 ID', icon: 'user', error: err['id'], shake: err.containsKey('id') ? shake : 0, onChanged: (_) => setState(() => err.remove('id'))),
        const SizedBox(height: 12),
        LField(controller: pwd, label: '密码', icon: 'lock', password: true, error: err['pwd'], shake: err.containsKey('pwd') ? shake : 0, onChanged: (_) => setState(() => err.remove('pwd'))),
        const SizedBox(height: 10),
        Row(children: [
          Press(onTap: () => setState(() => remember = !remember), child: Row(children: [_Check(remember), const SizedBox(width: 8), Text('保持登录', style: ts(13, c: const Color(0xB3FFFFFF)))])),
          const Spacer(),
          Press(onTap: () => app.update(() => app.authPage = 'forgot'), child: Text('忘记密码？', style: ts(13, c: const Color(0xB3FFFFFF)))),
        ]),
        const SizedBox(height: 16),
        Btn('登录', block: true, busy: busy, onTap: _login),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [const Expanded(child: Divider(color: Color(0x26FFFFFF))), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('或', style: ts(12, c: const Color(0x80FFFFFF)))), const Expanded(child: Divider(color: Color(0x26FFFFFF)))]),
        ),
        Btn('已登录的设备扫码', icon: 'scan', kind: BtnKind.ghost, block: true, onTap: () => toast('用已登录的手机扫电视 / 桌面上的二维码即可', 'scan')),
      ]);
    } else {
      final sc = pwScore(rpwd.text);
      form = Column(key: const ValueKey('reg'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LField(controller: email, label: '邮箱', icon: 'mail', ok: _isEmail.hasMatch(email.text), error: err['email'], shake: err.containsKey('email') ? shake : 0, keyboard: TextInputType.emailAddress, onChanged: (_) => setState(() => err.remove('email'))),
        const SizedBox(height: 12),
        LField(controller: rpwd, label: '设置密码', icon: 'lock', password: true, error: err['rpwd'], shake: err.containsKey('rpwd') ? shake : 0, onChanged: (_) => setState(() => err.remove('rpwd'))),
        _PwMeter(sc),
        const SizedBox(height: 12),
        Captcha(key: capKey, onPass: (v) => setState(() => capOk = v)),
        const SizedBox(height: 12),
        LField(controller: code, label: '邮箱验证码', icon: 'key', keyboard: TextInputType.number, error: err['code'], shake: err.containsKey('code') ? shake : 0, suffix: cd > 0 ? '${cd}s' : '获取验证码', onSuffix: _send, onChanged: (_) => setState(() => err.remove('code'))),
        const SizedBox(height: 12),
        Press(onTap: () => app.update(() => app.agreed = !app.agreed), child: Row(children: [_Check(app.agreed), const SizedBox(width: 8), Expanded(child: Text('我已阅读并同意《用户协议》与《隐私政策》', style: ts(12.5, c: const Color(0xB3FFFFFF))))])),
        const SizedBox(height: 16),
        Btn('注册', block: true, busy: busy, onTap: _register),
      ]);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Ambient(
        child: ListView(padding: EdgeInsets.fromLTRB(16, mq.padding.top + (reg ? 30 : 70), 16, mq.padding.bottom + 30), children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _Brand(compact: reg)),
          SizedBox(height: reg ? 26 : 60),
          _AuthCard(
            child: Column(children: [
              if (!(reg && done)) ...[
                Seg(const ['登录', '注册'], seg, (v) => setState(() {
                      seg = v;
                      err.clear();
                      done = false;
                    }), margin: EdgeInsets.zero),
                const SizedBox(height: 18),
              ],
              AnimatedSize(duration: const Duration(milliseconds: 360), curve: Tk.out, child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: form)),
            ]),
          ),
          const SizedBox(height: 16),
          Center(child: Press(onTap: () => app.update(() => app.authPage = 'versionDisabled'), child: Text('演示：版本停用页', style: ts(11.5, c: const Color(0x4DFFFFFF))))),
        ]),
      ),
    );
  }
}

class _PwMeter extends StatelessWidget {
  final int s;
  const _PwMeter(this.s);
  @override
  Widget build(BuildContext context) {
    const cols = [Color(0xFFFF6B6B), Color(0xFFFFC266), Color(0xFF8AB4FF), Color(0xFF4CD39B)];
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Row(children: [
        for (var i = 1; i <= 4; i++)
          Expanded(child: AnimatedContainer(duration: Tk.base, height: 4, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: i <= s ? cols[s - 1] : const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(width: 6),
        SizedBox(width: 118, child: Text(const ['至少 8 位，建议混合字母、数字和符号', '弱', '一般', '较强', '强'][s], maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, c: s == 0 ? const Color(0x80FFFFFF) : cols[s - 1]))),
      ]),
    );
  }
}

/// 对勾描绘动画。
class _DrawCheck extends StatelessWidget {
  const _DrawCheck();
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Tk.out,
      builder: (_, v, __) => Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(color: pal.ok.withValues(alpha: .15), shape: BoxShape.circle),
        child: CustomPaint(painter: _CheckPainter(v, pal.ok)),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color c;
  _CheckPainter(this.t, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width * .28, s.height * .52)
      ..lineTo(s.width * .44, s.height * .67)
      ..lineTo(s.width * .73, s.height * .36);
    final m = p.computeMetrics().first;
    canvas.drawPath(m.extractPath(0, m.length * t), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c);
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t;
}

// ======================= 人机验证（通用组件） =======================
class Captcha extends StatefulWidget {
  final ValueChanged<bool> onPass;
  const Captcha({super.key, required this.onPass});
  @override
  State<Captcha> createState() => CaptchaState();
}

class CaptchaState extends State<Captcha> with TickerProviderStateMixin {
  static const capText = 'K7F3';
  static const clickChars = [('夜', 62.0, 48.0), ('航', 210.0, 112.0), ('星', 128.0, 132.0), ('光', 262.0, 40.0), ('海', 30.0, 120.0), ('风', 180.0, 30.0)];
  static const clickTarget = ['夜', '航', '星'];
  static const slideX = 196.0;
  String mode = 'text';
  bool ok = false;
  int seed = 1;
  double slide = 0, used = 0;
  bool sliding = false, slideFail = false;
  DateTime? t0;
  final clicks = <Offset>[];
  final tc = TextEditingController();
  late final sh = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final rf = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void dispose() {
    sh.dispose();
    rf.dispose();
    super.dispose();
  }

  void fail(String msg) {
    sh.forward(from: 0);
    toast(msg, 'info');
  }

  void _pass() {
    setState(() => ok = true);
    widget.onPass(true);
  }

  void _refresh() {
    rf.forward(from: 0);
    setState(() {
      ok = false;
      seed++;
      clicks.clear();
      tc.clear();
      slide = 0;
    });
    widget.onPass(false);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget body;
    if (ok) {
      body = TweenAnimationBuilder<double>(
        key: const ValueKey('ok'),
        tween: Tween(begin: .85, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: const Cubic(.3, 1.5, .5, 1),
        builder: (_, v, ch) => Transform.scale(scale: v, child: ch),
        child: SizedBox(
          height: 70,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_rounded, color: pal.ok, size: 28),
            const SizedBox(width: 10),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('验证通过', style: ts(15, w: FontWeight.w700, c: pal.ok)),
              Text(const {'text': '字符正确', 'click': '点选顺序正确'}[mode] ?? '拼图已对齐 · 用时 ${used.toStringAsFixed(1)}s', style: ts(12, c: const Color(0x99FFFFFF))),
            ]),
          ]),
        ),
      );
    } else if (mode == 'text') {
      body = Row(key: const ValueKey('text'), children: [
        GestureDetector(
          onTap: _refresh,
          child: Stack(alignment: Alignment.bottomRight, children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: CustomPaint(size: const Size(120, 44), painter: _CapPainter(seed))),
            RotationTransition(turns: rf, child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.refresh_rounded, size: 14, color: Colors.white70))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.centerLeft,
            child: TextField(controller: tc, maxLength: 4, style: ts(15, c: Colors.white, ls: 2), cursorColor: pal.acc, decoration: InputDecoration(isCollapsed: true, counterText: '', border: InputBorder.none, hintText: '输入字符', hintStyle: ts(13.5, c: const Color(0x66FFFFFF)))),
          ),
        ),
        const SizedBox(width: 8),
        IBtn('check', size: 44, bg: pal.acc, color: pal.ink, onTap: () => tc.text.toUpperCase() == capText ? _pass() : fail('字符不正确，换一张试试')),
      ]);
    } else if (mode == 'slide') {
      body = LayoutBuilder(
        key: const ValueKey('slide'),
        builder: (c, cs) {
          final w = cs.maxWidth;
          final sx = slideX / 300 * w;
          const piece = 44.0;
          return Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 130,
                child: Stack(children: [
                  Positioned.fill(child: Cover(hue: 268.0 + seed * 23, variant: 2, size: 0, radius: 0)),
                  Positioned(left: sx, top: 40, child: Container(width: piece, height: piece, decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white54)))),
                  AnimatedPositioned(
                    duration: Duration(milliseconds: sliding ? 0 : 420),
                    curve: Tk.softSpring,
                    left: 8 + slide,
                    top: 40,
                    child: Container(
                      width: piece,
                      height: piece,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 8)], border: Border.all(color: Colors.white, width: 1.5)),
                      child: ClipRRect(borderRadius: BorderRadius.circular(7), child: OverflowBox(alignment: Alignment.topLeft, maxWidth: w, maxHeight: 130, child: Transform.translate(offset: Offset(-sx, -40), child: SizedBox(width: w, height: 130, child: Cover(hue: 268.0 + seed * 23, variant: 2, size: 0, radius: 0))))),
                    ),
                  ),
                  Positioned(right: 4, top: 4, child: IBtn('refresh', size: 30, iconSize: 16, color: Colors.white, bg: const Color(0x59000000), onTap: _refresh)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: Tk.base,
              height: 44,
              decoration: BoxDecoration(color: slideFail ? pal.danger.withValues(alpha: .18) : const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(22)),
              child: Stack(alignment: Alignment.centerLeft, children: [
                Center(child: Opacity(opacity: (1 - slide / 80).clamp(0, 1), child: Text('向右拖动滑块完成拼图', style: ts(13, c: const Color(0x80FFFFFF))))),
                AnimatedContainer(duration: Duration(milliseconds: sliding ? 0 : 420), width: slide + 44, decoration: BoxDecoration(color: pal.acc.withValues(alpha: .22), borderRadius: BorderRadius.circular(22))),
                AnimatedPositioned(
                  duration: Duration(milliseconds: sliding ? 0 : 420),
                  curve: Tk.softSpring,
                  left: slide,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => setState(() {
                      sliding = true;
                      slideFail = false;
                      t0 = DateTime.now();
                    }),
                    onHorizontalDragUpdate: (d) => setState(() => slide = (slide + d.delta.dx).clamp(0, w - 48)),
                    onHorizontalDragEnd: (_) {
                      sliding = false;
                      if ((slide + 8 - sx).abs() < 7 * w / 300 + 2) {
                        used = DateTime.now().difference(t0!).inMilliseconds / 1000;
                        _pass();
                      } else {
                        setState(() {
                          slide = 0;
                          slideFail = true;
                        });
                        toast('没对齐，再试一次', 'info');
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (mounted) setState(() => slideFail = false);
                        });
                      }
                    },
                    child: Container(width: 44, height: 44, decoration: BoxDecoration(color: slideFail ? pal.danger : pal.acc, shape: BoxShape.circle), child: Icon(ic('right'), color: pal.ink)),
                  ),
                ),
              ]),
            ),
          ]);
        },
      );
    } else {
      body = LayoutBuilder(
        key: const ValueKey('click'),
        builder: (c, cs) {
          final w = cs.maxWidth;
          final k = w / 300;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('请依次点击 ', style: ts(13, c: const Color(0xB3FFFFFF))),
              for (final (i, ch) in clickTarget.indexed)
                AnimatedContainer(
                  duration: Tk.base,
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: clicks.length > i ? pal.acc : const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(6)),
                  child: Text(ch, style: ts(14, w: FontWeight.w800, c: clicks.length > i ? pal.ink : Colors.white)),
                ),
              const Spacer(),
              IBtn('refresh', size: 30, iconSize: 16, color: Colors.white70, onTap: _refresh),
            ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTapDown: (d) {
                setState(() => clicks.add(d.localPosition));
                if (clicks.length < 3) return;
                final good = [
                  for (var i = 0; i < 3; i++)
                    () {
                      final t = clickChars.firstWhere((e) => e.$1 == clickTarget[i]);
                      return (clicks[i] - Offset((t.$2 + 14) * k, t.$3 + 16)).distance < 30;
                    }(),
                ].every((x) => x);
                if (good) {
                  _pass();
                } else {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (!mounted) return;
                    setState(clicks.clear);
                    fail('顺序或位置不对，再试一次');
                  });
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 170,
                  child: Stack(children: [
                    Positioned.fill(child: Cover(hue: 200.0 + seed * 31, variant: 1, size: 0, radius: 0)),
                    for (final (i, (ch, x, y)) in clickChars.indexed)
                      Positioned(left: x * k, top: y, child: Transform.rotate(angle: (((i * 37) % 50) - 25) * math.pi / 180, child: Text(ch, style: ts(26, w: FontWeight.w800, c: Colors.white).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)])))),
                    for (final (i, p) in clicks.indexed)
                      Positioned(left: p.dx - 11, top: p.dy - 11, child: Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: pal.acc, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('${i + 1}', style: ts(11, w: FontWeight.w800, c: pal.ink)))),
                  ]),
                ),
              ),
            ),
          ]);
        },
      );
    }
    return AnimatedBuilder(
      animation: sh,
      builder: (_, ch) => Transform.translate(offset: Offset(math.sin(sh.value * math.pi * 6) * 8 * (1 - sh.value), 0), child: ch),
      child: AnimatedContainer(
        duration: Tk.base,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: ok ? pal.ok.withValues(alpha: .1) : const Color(0x0DFFFFFF), borderRadius: BorderRadius.circular(16), border: Border.all(color: ok ? pal.ok.withValues(alpha: .5) : const Color(0x1AFFFFFF))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(ic('shield'), size: 15, color: const Color(0xB3FFFFFF)),
            const SizedBox(width: 5),
            Text('人机验证', style: ts(12.5, w: FontWeight.w600, c: const Color(0xB3FFFFFF))),
            const Spacer(),
            for (final (k, n) in const [('text', '图形字符'), ('slide', '滑块拼图'), ('click', '文字点选')])
              Press(
                onTap: () {
                  setState(() {
                    mode = k;
                    ok = false;
                    clicks.clear();
                    slide = 0;
                    tc.clear();
                  });
                  widget.onPass(false);
                },
                child: Container(margin: const EdgeInsets.only(left: 4), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: mode == k ? const Color(0x26FFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(7)), child: Text(n, style: ts(11, w: FontWeight.w600, c: mode == k ? Colors.white : const Color(0x80FFFFFF)))),
              ),
          ]),
          const SizedBox(height: 10),
          AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: body),
          const SizedBox(height: 6),
          Text('类型由服务端下发，此处可切换演示', style: ts(10.5, c: const Color(0x59FFFFFF))),
        ]),
      ),
    );
  }
}

class _CapPainter extends CustomPainter {
  final int seed;
  _CapPainter(this.seed);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1D1E28));
    for (var i = 0; i < 5; i++) {
      canvas.drawPath(
          Path()
            ..moveTo(0, 8.0 + i * 8 + seed % 5)
            ..quadraticBezierTo(60, ((i * 17 + seed * 7) % 44).toDouble(), 120, ((i * 11 + seed * 3) % 44).toDouble()),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = hsl(i * 60.0 + seed * 20, .6, .6, .35));
    }
    for (var i = 0; i < 4; i++) {
      final tp = TextPainter(
        text: TextSpan(text: CaptchaState.capText[i], style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontFamily: 'serif', color: hsl(38.0 + i * 50, .8, .7))),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(22.0 + i * 25, 22);
      canvas.rotate((((i * 23 + seed * 9) % 36) - 18) * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 + (i.isOdd ? -3 : 4)));
      canvas.restore();
    }
    final dot = Paint()..color = const Color(0x59FFFFFF);
    for (var i = 0; i < 30; i++) {
      canvas.drawCircle(Offset(((i * 37 + seed * 13) % 120).toDouble(), ((i * 23 + seed * 5) % 44).toDouble()), .9, dot);
    }
  }

  @override
  bool shouldRepaint(_CapPainter o) => o.seed != seed;
}

// ======================= 找回密码 =======================
class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});
  @override
  State<ForgotPage> createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  int st = 0, shake = 0, cd = 0;
  bool busy = false, capOk = false;
  final email = TextEditingController(), code = TextEditingController(), p1 = TextEditingController(), p2 = TextEditingController();
  final err = <String, String>{};
  final capKey = GlobalKey<CaptchaState>();
  Timer? cdt;

  @override
  void initState() {
    super.initState();
    for (final c in [email, p1, p2]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    cdt?.cancel();
    super.dispose();
  }

  void _err(Map<String, String> e) => setState(() {
        err
          ..clear()
          ..addAll(e);
        shake++;
      });

  Future<void> _go(int to) async {
    setState(() => busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        busy = false;
        st = to;
      });
    }
  }

  void _send() {
    if (cd > 0) return;
    if (!_isEmail.hasMatch(email.text)) return _err({'email': '先填写正确的邮箱'});
    if (!capOk) {
      capKey.currentState?.fail('请先完成人机验证');
      return;
    }
    setState(() => cd = 60);
    toast('验证码已发送', 'mail');
    cdt = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => cd--);
      if (cd <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final mq = MediaQuery.of(context);
    Widget body;
    if (st == 0) {
      body = Column(key: const ValueKey(0), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('找回密码', style: ts(22, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 4),
        Text('验证邮箱后即可重新设置密码', style: ts(13, c: const Color(0x99FFFFFF))),
        const SizedBox(height: 16),
        LField(controller: email, label: '注册邮箱', icon: 'mail', ok: _isEmail.hasMatch(email.text), error: err['email'], shake: shake),
        const SizedBox(height: 12),
        Captcha(key: capKey, onPass: (v) => setState(() => capOk = v)),
        const SizedBox(height: 12),
        LField(controller: code, label: '邮箱验证码', icon: 'key', error: err['code'], shake: shake, suffix: cd > 0 ? '${cd}s' : '获取验证码', onSuffix: _send),
        const SizedBox(height: 18),
        Btn('下一步', block: true, busy: busy, onTap: () {
          final e = <String, String>{};
          if (!_isEmail.hasMatch(email.text)) e['email'] = '邮箱格式不正确';
          if (!capOk) {
            if (e.isNotEmpty) return _err(e);
            capKey.currentState?.fail('请先完成人机验证');
            return;
          }
          if (!RegExp(r'^\d{6}$').hasMatch(code.text)) e['code'] = '请输入 6 位邮箱验证码';
          if (e.isNotEmpty) return _err(e);
          _go(1);
        }),
      ]);
    } else if (st == 1) {
      body = Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('设置新密码', style: ts(22, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 4),
        Text('为 ${email.text.isEmpty ? 'a***@example.com' : email.text} 设置新密码', style: ts(13, c: const Color(0x99FFFFFF))),
        const SizedBox(height: 16),
        LField(controller: p1, label: '新密码', icon: 'lock', password: true, error: err['p1'], shake: shake),
        _PwMeter(pwScore(p1.text)),
        const SizedBox(height: 12),
        LField(controller: p2, label: '再次输入新密码', icon: 'lock', password: true, ok: p2.text.isNotEmpty && p2.text == p1.text, error: err['p2'], shake: shake),
        const SizedBox(height: 10),
        Text('重设后，其他已登录的设备需要重新登录', style: ts(12, c: const Color(0x80FFFFFF))),
        const SizedBox(height: 16),
        Btn('重设密码', block: true, busy: busy, onTap: () {
          final e = <String, String>{};
          if (p1.text.length < 8) e['p1'] = '至少 8 位';
          if (p2.text != p1.text) e['p2'] = '两次输入不一致';
          if (e.isNotEmpty) return _err(e);
          _go(2);
        }),
      ]);
    } else {
      body = Column(key: const ValueKey(2), children: [
        const SizedBox(height: 10),
        const _DrawCheck(),
        const SizedBox(height: 14),
        Text('密码已重设', style: ts(22, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 6),
        Text('请使用新密码登录', style: ts(13.5, c: const Color(0xB3FFFFFF))),
        const SizedBox(height: 22),
        Btn('返回登录', block: true, onTap: () {
          app.update(() => app.authPage = 'login');
          toast('请使用新密码登录', 'lock');
        }),
      ]);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Ambient(
        child: ListView(padding: EdgeInsets.fromLTRB(16, mq.padding.top + 8, 16, mq.padding.bottom + 30), children: [
          Align(alignment: Alignment.centerLeft, child: IBtn('left', color: Colors.white, onTap: () => app.update(() => app.authPage = 'login'))),
          const SizedBox(height: 10),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: _Brand(compact: true, sub: '账号安全中心')),
          const SizedBox(height: 26),
          _AuthCard(
            child: Column(children: [
              Row(children: [
                for (final (i, n) in const ['验证身份', '重设密码', '完成'].indexed) ...[
                  if (i > 0) Expanded(child: AnimatedContainer(duration: Tk.base, height: 2, color: i <= st ? pal.acc : const Color(0x26FFFFFF))),
                  Column(children: [
                    AnimatedContainer(duration: Tk.base, width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: i < st ? pal.acc : i == st ? pal.accSoft : const Color(0x14FFFFFF), border: Border.all(color: i <= st ? pal.acc : Colors.transparent)), child: i < st ? Icon(ic('check'), size: 15, color: pal.ink) : Text('${i + 1}', style: ts(12, w: FontWeight.w700, c: i == st ? pal.acc : const Color(0x80FFFFFF)))),
                    const SizedBox(height: 4),
                    Text(n, style: ts(11, c: i <= st ? Colors.white : const Color(0x66FFFFFF))),
                  ]),
                ],
              ]),
              const SizedBox(height: 20),
              AnimatedSize(duration: const Duration(milliseconds: 360), child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: body)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ======================= 版本停用 =======================
class VersionDisabledPage extends StatelessWidget {
  const VersionDisabledPage({super.key});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 88, height: 88, decoration: BoxDecoration(color: pal.warn.withValues(alpha: .14), borderRadius: BorderRadius.circular(28)), child: Icon(ic('info'), size: 42, color: pal.warn)),
              const SizedBox(height: 22),
              Text('当前版本已停止服务', style: ts(24, w: FontWeight.w800, c: pal.t1)),
              const SizedBox(height: 10),
              Text('v2.3.1 存在影响播放稳定性的问题，已被服务端停用。\n请更新到 v2.4.0 或更高版本继续使用。', textAlign: TextAlign.center, style: ts(14, c: pal.t2, h: 1.7)),
              const SizedBox(height: 22),
              CardBox(
                margin: EdgeInsets.zero,
                child: SizedBox(width: double.infinity, child: Text('v2.4.0 更新内容\n· 修复后台播放偶发中断\n· 律动 / 灵动两套新皮肤\n· 液态玻璃底栏', style: ts(13, c: pal.t2, h: 1.7))),
              ),
              const SizedBox(height: 22),
              Btn('立即更新（38.6 MB）', block: true, onTap: () => toast('正在下载更新包…', 'download')),
              const SizedBox(height: 12),
              Hint('此页面无法跳过', align: TextAlign.center, padding: EdgeInsets.zero),
              if (context.appRead.authPage == 'versionDisabled') Press(onTap: () => context.appRead.update(() => context.appRead.authPage = 'login'), child: Padding(padding: const EdgeInsets.all(10), child: Text('（演示）返回登录', style: ts(11.5, c: pal.t4)))),
              if (context.appRead.authed) Press(onTap: () => Navigator.of(context).pop(), child: Padding(padding: const EdgeInsets.all(10), child: Text('（演示）关闭', style: ts(11.5, c: pal.t4)))),
            ]),
          ),
        ),
      ),
    );
  }
}
