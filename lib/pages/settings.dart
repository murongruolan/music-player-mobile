// 设置页：外观与界面 · 歌词 · 系统歌词 · 播放与音质 · 智能换源 · 平台与解析脚本（含导入音源）。
// 每项都绑定 AppState.set 的字段，接口对接时把 Settings 持久化即可。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import '../core/script_store.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../data/models.dart';
import '../source/lx_runtime.dart';
import '../sync/cloud_models.dart';
import '../player/lyrics.dart';
import '../player/player.dart';
import '../player/skins.dart';
import '../ui/brand.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/picker.dart';
import '../widgets/sheets.dart';
import 'common.dart';

// ======================= 外观与界面 =======================
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final sk = skinBy(app.skin);
    final order = [app.bar, ...barStyles.keys.where((k) => k != app.bar)].take(3).toList();
    return SubPage(title: '外观与界面', children: [
      Group(title: '主题', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Seg(const ['深色', '浅色', '跟随系统'], {ThemeMode.dark: '深色', ThemeMode.light: '浅色', ThemeMode.system: '跟随系统'}[app.themeMode]!, (v) => app.update(() => app.themeMode = {'深色': ThemeMode.dark, '浅色': ThemeMode.light}[v] ?? ThemeMode.system), margin: EdgeInsets.zero),
        ),
        const Item(label: '主题色', sub: '按钮、进度条、选中态与歌词高亮，实时生效', chev: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final (i, a) in accents.indexed)
              Press(
                onTap: () => app.update(() => app.accent = i),
                scale: .85,
                child: AnimatedContainer(
                  duration: Tk.base,
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: app.accent == i ? a.fill : Colors.transparent, width: 2)),
                  child: Container(decoration: BoxDecoration(color: a.fill, shape: BoxShape.circle), child: app.accent == i ? Icon(ic('check'), size: 18, color: a.ink) : null),
                ),
              ),
          ]),
        ),
      ]),
      Group(title: '底部导航样式', foot: barDesc[app.bar], children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            for (final k in order) ...[Expanded(child: BarPreviewTile(k, on: app.bar == k, onTap: () => app.update(() {
                  app.bar = k;
                  app.navMin = false;
                }))), const SizedBox(width: 8)],
            Expanded(
              child: Press(
                onTap: () => openBarStyles(context),
                child: Column(children: [
                  Container(height: 92, decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(14)), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic('grid'), color: pal.t2), Text('+${barStyles.length - 3}', style: ts(12, c: pal.t3))]))),
                  const SizedBox(height: 6),
                  Text('更多', style: ts(13, c: pal.t1)),
                ]),
              ),
            ),
          ]),
        ),
        Item(icon: 'down', color: 'blue', label: '滚动时自动收起', sub: '向下滚动时底栏收成小圆钮，迷你播放条并入同一行', sw: app.set.navAutoMin, onSw: (v) => app.update(() => app.set.navAutoMin = v)),
      ]),
      Group(title: '播放器', children: [
        Item(icon: 'vinyl', color: 'violet', label: '播放器皮肤', sub: sk.desc, val: sk.name, onTap: () => openSkins(context)),
        Item(icon: 'layers', color: 'blue', label: '播放器背景', sub: sk.usesBg ? '律动、声波、唱片、舞台使用' : '当前皮肤「${sk.name}」自带背景，不受此项影响', val: const {'blur': '模糊封面', 'static': '静态流光', 'flow': '动态流光'}[app.bg], onTap: () => openBg(context)),
        Item(icon: 'vinyl', color: 'gray', label: '唱片旋转', sw: app.set.vinylSpin, onSw: (v) => app.update(() => app.set.vinylSpin = v)),
        Item(icon: 'phone', color: 'gold', label: '横屏充电时进入待机', sub: '手机横放并充电时，自动切到「待机」皮肤', sw: app.set.standbyAuto, onSw: (v) => app.update(() => app.set.standbyAuto = v)),
        Item(icon: 'sun', color: 'orange', label: '播放页屏幕常亮', sub: '播放页打开期间保持屏幕点亮', sw: app.set.keepAwake, onSw: (v) { app.update(() => app.set.keepAwake = v); v ? WakelockPlus.enable() : WakelockPlus.disable(); }),
      ]),
      Group(title: '界面', children: [
        Item(icon: 'font', color: 'teal', label: '界面字体', val: fonts.firstWhere((f) => f[0] == app.font)[1], onTap: () => openFonts(context)),
        Item(lead: AppIcon(app.appIcon, size: 30), label: 'App 图标', val: appIcons.firstWhere((a) => a[0] == app.appIcon)[1], onTap: () => openAppIcons(context)),
        Item(icon: 'compass', color: 'cyan', label: '首页内容与顺序', val: '${app.homeMods.where((m) => m.value).length} 个模块', onTap: () => openHomeOrder(context)),
        Item(icon: 'zap', color: 'green', label: '触感反馈', sw: app.set.haptics, onSw: (v) => app.update(() => app.set.haptics = v)),
        Item(icon: 'eye', color: 'gray', label: '减少动态效果', sub: '关闭形变、弹簧、流光等动画', sw: app.set.reduceMotion, onSw: (v) => app.update(() => app.set.reduceMotion = v)),
      ]),
    ]);
  }
}

void openHomeOrder(BuildContext context) {
  showLSheet(context, title: '首页内容与顺序', sub: '按住拖动排序', scroll: false, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ReorderableListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          onReorder: (a, b) => app.moveHomeMod(a, b > a ? b - 1 : b),
          proxyDecorator: (ch, _, a) => AnimatedBuilder(animation: a, builder: (_, __) => Transform.scale(scale: 1 + .04 * a.value, child: Material(color: Colors.transparent, elevation: 10 * a.value, borderRadius: BorderRadius.circular(16), child: ch))),
          children: [
            for (final (i, m) in app.homeMods.indexed)
              Container(
                key: ValueKey(m.key),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.line)),
                child: Row(children: [
                  ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(14), child: Icon(ic('drag'), color: pal.t3))),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(homeModNames[m.key]![0], style: ts(15, w: FontWeight.w600, c: pal.t1)), Text(homeModNames[m.key]![1], style: ts(11.5, c: pal.t3))])),
                  Padding(padding: const EdgeInsets.all(12), child: LSwitch(m.value, (v) => app.setHomeMod(m.key, v))),
                ]),
              ),
          ],
        ),
      ),
      const Hint('「为你定制」「我的歌单」需要登录当前平台后才会显示'),
    ]);
  });
}

void openSkins(BuildContext context, {bool dark = false}) {
  var tab = '全部';
  showLSheet(context, title: '播放器皮肤', sub: '${skins.length} 套', dark: dark, builder: (c) => StatefulBuilder(builder: (c, set) {
        final app = c.app;
        final pal = c.pal;
        final list = skins.where((s) => tab == '全部' || s.cat == tab).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [
              for (final t in ['全部', ...skinCats])
                Padding(padding: const EdgeInsets.only(right: 8), child: LChip(t, on: t == tab, onTap: () => set(() => tab = t), trailing: Text('${t == '全部' ? skins.length : skins.where((s) => s.cat == t).length}', style: ts(11, c: pal.t3, num: true)))),
            ]),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .78,
              children: [
                for (final s in list)
                  Press(
                    onTap: () {
                      app.update(() => app.skin = s.id);
                      toast('皮肤：${s.name}', 'vinyl');
                    },
                    child: AnimatedContainer(
                      duration: Tk.base,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: pal.s1, borderRadius: BorderRadius.circular(18), border: Border.all(color: app.skin == s.id ? pal.acc : pal.line, width: app.skin == s.id ? 2 : 1)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: RepaintBoundary(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SkinThumb(s.id)))),
                        const SizedBox(height: 8),
                        Row(children: [Text(s.name, style: ts(14, w: FontWeight.w700, c: pal.t1)), const SizedBox(width: 6), if (s.tag != null) Badge2(s.tag!, acc: s.tag == '新' || s.tag == '默认'), const Spacer(), Text(s.cat, style: ts(11, c: pal.t3))]),
                        const SizedBox(height: 2),
                        Text(s.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(11, c: pal.t3, h: 1.35)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          if (app.skin == 'spring') ...[
            const SizedBox(height: 12),
            Group(title: '律动 · 歌词动效', children: [
              Padding(padding: const EdgeInsets.all(12), child: Seg(const ['弹簧瀑布', '波浪漂浮'], app.amWave == 'spring' ? '弹簧瀑布' : '波浪漂浮', (v) => app.update(() => app.amWave = v == '弹簧瀑布' ? 'spring' : 'wave'), margin: EdgeInsets.zero)),
            ]),
          ],
        ]);
      }));
}

void openBg(BuildContext context, {bool dark = false}) {
  showLSheet(context, title: '播放器背景', dark: dark, builder: (c) {
    final app = c.app;
    final pal = c.pal;
    final sk = skinBy(app.skin);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!sk.usesBg)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pal.warn.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Text('当前皮肤「${sk.name}」自带背景，这里的设置在律动、声波、唱片、舞台中生效。', style: ts(12.5, c: pal.warn, h: 1.5)),
          ),
        Row(children: [
          for (final (k, n) in const [('blur', '模糊封面'), ('static', '静态流光'), ('flow', '动态流光')]) ...[
            Expanded(
              child: Press(
                onTap: () => app.update(() => app.bg = k),
                child: Column(children: [
                  AnimatedContainer(
                    duration: Tk.base,
                    height: 150,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: app.bg == k ? pal.acc : Colors.transparent, width: 2)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(14), child: PlayerBackground(song: app.song, mode: k, tone: app.tone, dim: app.dim, preview: true)),
                  ),
                  const SizedBox(height: 6),
                  Text(n, style: ts(12.5, w: app.bg == k ? FontWeight.w700 : FontWeight.w500, c: app.bg == k ? pal.accText : pal.t1)),
                ]),
              ),
            ),
            if (k != 'flow') const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 16),
        Seg(const ['暗色调', '亮色调'], app.tone == 'dark' ? '暗色调' : '亮色调', (v) => app.update(() => app.tone = v == '暗色调' ? 'dark' : 'light'), margin: EdgeInsets.zero),
        const SizedBox(height: 12),
        LSlider(label: '压暗程度', value: app.dim, min: 0, max: 80, step: 1, fmt: (v) => '${v.round()}%', onChanged: (v) => app.update(() => app.dim = v)),
      ]),
    );
  });
}

// ======================= 歌词 =======================
class LyricsSettingsPage extends StatelessWidget {
  const LyricsSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.set;
    void u(VoidCallback f) => app.update(f);
    return SubPage(title: '歌词', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 190,
            child: Stack(children: [
              Positioned.fill(child: PlayerBackground(song: app.song, mode: 'flow', tone: 'dark', dim: 40)),
              Positioned.fill(child: PalScope(pal: context.pal.forceDark, child: const LyricPreview())),
            ]),
          ),
        ),
      ),
      Group(title: '显示', children: [
        Item(icon: 'globe', color: 'blue', label: '显示翻译', sw: s.trans, onSw: (v) => u(() => s.trans = v)),
        Item(icon: 'font', color: 'violet', label: '显示罗马音', sw: s.roma, onSw: (v) => u(() => s.roma = v)),
        Item(icon: 'refresh', color: 'teal', label: '简繁转换', sub: '即将支持 · 按系统语言自动转换'),
        Item(icon: 'eye', color: 'gray', label: '非当前行模糊', sw: s.blur, onSw: (v) => u(() => s.blur = v)),
        Item(icon: 'sparkle', color: 'gold', label: '逐字辉光', sub: '有逐字时间轴时按字填充，否则按行均匀插值', sw: s.glow, onSw: (v) => u(() => s.glow = v)),
      ]),
      Group(title: '字号与间距', children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: LSlider(label: '正文', value: s.lfs, min: 16, max: 40, step: 1, fmt: (v) => '${v.round()}px', onChanged: (v) => u(() => s.lfs = v))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: LSlider(label: '翻译', value: s.ltfs, min: 11, max: 22, step: 1, fmt: (v) => '${v.round()}px', onChanged: (v) => u(() => s.ltfs = v))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: LSlider(label: '行距', value: s.lgap, min: 4, max: 24, step: 1, fmt: (v) => '${v.round()}px', onChanged: (v) => u(() => s.lgap = v))),
      ]),
      Group(title: '时间', foot: '正值 = 歌词提前出现。也可在播放页「歌词快调」里按 0.5 秒微调', children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: LSlider(label: '整体偏移', value: s.loff, min: -3, max: 3, step: .1, fmt: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}s', onChanged: (v) => u(() => s.loff = v))),
      ]),
      Group(title: '来源', children: [
        Item(icon: 'layers', color: 'orange', label: '歌词来源优先级', val: '内置 → 平台 → 本地', onTap: () => toast('长按拖动调整顺序', 'drag')),
        Item(icon: 'folder', color: 'green', label: '读取同名 .lrc 文件', sub: '本地音乐优先使用同目录歌词', sw: s.cache, onSw: (v) => u(() => s.cache = v)),
      ]),
    ]);
  }
}

// ======================= 系统歌词 =======================
class SysLyricsPage extends StatelessWidget {
  const SysLyricsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.set;
    void u(VoidCallback f) => app.update(f);
    return SubPage(title: '系统歌词', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 14),
        child: Container(
          height: 120,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2D3A5C), Color(0xFF141826)])),
          child: Stack(children: [
            Positioned(
              left: 14,
              right: 14,
              top: 30,
              child: Glass(
                radius: 14,
                color: const Color(0x73000000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    AppIcon(app.appIcon, size: 26),
                    const SizedBox(width: 10),
                    Expanded(child: Text(previewLyrics[6].text, style: ts(15, w: FontWeight.w700, c: Colors.white))),
                    Icon(ic(s.floatLock ? 'lock' : 'drag'), color: Colors.white70, size: 18),
                  ]),
                ),
              ),
            ),
            Positioned(left: 16, bottom: 10, child: Text('桌面悬浮歌词预览', style: ts(11, c: const Color(0x8CFFFFFF)))),
          ]),
        ),
      ),
      Group(title: '悬浮歌词（Android）', children: [
        Item(icon: 'layers', color: 'violet', label: '桌面悬浮歌词', sub: '需要「显示在其他应用上层」权限', sw: s.floatLyric, onSw: (v) => u(() => s.floatLyric = v)),
        Item(icon: 'lock', color: 'gray', label: '锁定位置', sub: '锁定后点击穿透，不影响其他应用', sw: s.floatLock, onSw: (v) => u(() => s.floatLock = v)),
        Item(icon: 'palette', color: 'pink', label: '样式', val: '圆角卡片 · 18px', onTap: () => toast('可调整字号、颜色和背景透明度', 'palette')),
      ]),
      Group(title: '车机与蓝牙', children: [
        Item(icon: 'bluetooth', color: 'blue', label: '蓝牙歌词推送', sub: '把当前行写入蓝牙媒体信息，车机屏幕可见', sw: s.btLyric, onSw: (v) => u(() => s.btLyric = v)),
        Item(icon: 'car', color: 'teal', label: '推送顺序', val: '歌词 · 歌名', onTap: () => toast('可选：仅歌词 / 歌词·歌名 / 歌名·歌词', 'car')),
      ]),
      Group(title: '状态栏', children: [Item(icon: 'phone', color: 'orange', label: '状态栏歌词', sub: '仅部分 Android 定制系统支持', sw: s.sbLyric, onSw: (v) => u(() => s.sbLyric = v))]),
    ]);
  }
}

// ======================= 播放与音质 =======================
class PlaybackPage extends StatelessWidget {
  const PlaybackPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.set;
    void u(VoidCallback f) => app.update(f);
    return SubPage(title: '播放与音质', children: [
      Group(title: '音质', children: [
        Item(icon: 'hd', color: 'orange', label: '在线播放音质', val: app.quality, onTap: () => openQuality(context)),
        Item(icon: 'download', color: 'blue', label: '下载音质', val: s.dlQ, onTap: () => _pickQ(context, (q) => u(() => s.dlQ = q))),
        Item(icon: 'wifi', color: 'cyan', label: '移动网络使用较低音质', sub: '非 Wi-Fi 时自动使用 HQ', sw: s.mobileLow, onSw: (v) => u(() => s.mobileLow = v)),
        Item(icon: 'down', color: 'gray', label: '不可用时自动降级', sw: s.allowDown, onSw: (v) => u(() => s.allowDown = v)),
      ]),
      Group(title: '播放行为', children: [
        Item(icon: 'repeat', color: 'violet', label: '默认播放模式', val: app.modeName, onTap: app.cycleMode),
        Item(icon: 'speed', color: 'teal', label: '播放速度', val: '${app.speed.toStringAsFixed(2)}×', onTap: () => openSpeed(context)),
        Item(icon: 'wave', color: 'green', label: '淡入淡出', sub: '暂停与恢复时音量平滑过渡', sw: s.fade, onSw: (v) => u(() { s.fade = v; app.applyFadeToEngine(); })),
        Item(icon: 'play', color: 'orange', label: '启动时自动播放', sw: s.autoplay, onSw: (v) => u(() => s.autoplay = v)),
        Item(icon: 'up', color: 'pink', label: '启动时打开播放页', sw: s.autoOpen, onSw: (v) => u(() => s.autoOpen = v)),
        Item(icon: 'cloud', color: 'blue', label: '边听边缓存', sub: '播放过的歌缓存到本机，下次秒开', sw: s.cache, onSw: (v) => u(() { s.cache = v; app.applyCacheToEngine(); })),
      ]),
      Group(title: '高级', children: [
        Item(icon: 'zap', color: 'gold', label: '智能换源', val: s.smart ? '已开启' : '已关闭', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmartPage()))),
        Item(icon: 'sliders', color: 'teal', label: '均衡器', val: app.eqOn ? app.eqPreset : '关闭', onTap: () => openEq(context)),
        Item(icon: 'moon', color: 'violet', label: '睡眠定时', val: app.timer > 0 ? '${app.timer} 分钟' : '关闭', onTap: () => openTimer(context)),
        Item(icon: 'code', color: 'gray', label: '播放链路', sub: '查看当前歌曲的取流与换源记录', onTap: () => openTrace(context)),
      ]),
    ]);
  }

  void _pickQ(BuildContext context, ValueChanged<String> f) {
    showLSheet(context, title: '下载音质', builder: (c) => Column(children: [
          for (final q in qualities.take(4))
            Item(lead: SizedBox(width: 50, child: QBadge(q.key)), label: q.name, sub: q.desc, onTap: () {
              f(q.key);
              Navigator.of(c).pop();
            }),
        ]));
  }
}

// ======================= 智能换源（两阶段） =======================
class SmartPage extends StatefulWidget {
  const SmartPage({super.key});
  @override
  State<SmartPage> createState() => _SmartPageState();
}

class _SmartPageState extends State<SmartPage> {
  late String sp = context.appRead.plat;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final s = app.set;
    void u(VoidCallback f) => app.update(f);
    final flow = [('down', '降音质', s.gradual), ('code', '换脚本', s.crossScript), ('globe', '换平台', s.crossPlat), ('next', '下一首', s.autoNext)];
    final scripts = app.scriptsOf(sp);
    final cross = app.crossOrder.where((x) => x != app.plat).toList();
    return SubPage(title: '智能换源', children: [
      CardBox(
        padding: const EdgeInsets.all(14),
        child: Opacity(
          opacity: s.smart ? 1 : .4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('播放失败时，依次尝试', style: ts(12.5, c: pal.t3)),
            const SizedBox(height: 12),
            Row(children: [
              for (final (j, (i, n, on)) in flow.indexed) ...[
                if (j > 0) Icon(ic('right'), size: 16, color: pal.t4),
                Expanded(
                  child: Rise(
                    j,
                    Column(children: [
                      AnimatedContainer(duration: Tk.base, width: 40, height: 40, decoration: BoxDecoration(color: on ? pal.accSoft : pal.s2, borderRadius: BorderRadius.circular(13)), child: Icon(ic(i), size: 19, color: on ? pal.accText : pal.t4)),
                      const SizedBox(height: 4),
                      Text('${j + 1} $n', style: ts(11.5, w: FontWeight.w600, c: on ? pal.t1 : pal.t4)),
                    ]),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 20, child: _band(pal, '同一平台内', pal.acc)),
              const SizedBox(width: 4),
              Expanded(flex: 10, child: _band(pal, '跨平台', const Color(0xFF8AB4FF))),
              const SizedBox(width: 4),
              Expanded(flex: 9, child: _band(pal, '兜底', pal.t3)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Group(children: [Item(icon: 'zap', color: 'gold', label: '启用智能换源', sw: s.smart, onSw: (v) => u(() => s.smart = v))]),
      if (s.smart) ...[
        Group(title: '第一阶段 · 同一平台内', foot: '正在编辑 ${platformBy(sp).name} 的脚本顺序。每个平台各有一份，切换上方徽标查看。', children: [
          Item(icon: 'down', color: 'orange', label: '① 逐级降低音质', sub: 'Hi-Res → SQ → HQ → 128k，仍用当前脚本', sw: s.gradual, onSw: (v) => u(() => s.gradual = v)),
          Item(icon: 'code', color: 'violet', label: '② 换用同平台的其他解析脚本', sub: '歌曲仍来自同一个平台，只是换一个脚本去解析', sw: s.crossScript, onSw: (v) => u(() => s.crossScript = v)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(children: [
              Text('脚本顺序', style: ts(13, w: FontWeight.w600, c: pal.t2)),
              const Spacer(),
              for (final p in platforms)
                Press(
                  onTap: () => setState(() => sp = p.id),
                  child: AnimatedContainer(duration: Tk.base, margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.all(2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: sp == p.id ? pal.acc : Colors.transparent, width: 2)), child: PlatBadge(p, size: 22, dim: sp != p.id)),
                ),
            ]),
          ),
          ReorderableListView(
            key: ValueKey(sp),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => u(() {
              final l = app.scriptOrder[sp]!;
              final x = l.removeAt(a);
              l.insert(b > a ? b - 1 : b, x);
            }),
            children: [
              for (final (i, sc) in scripts.indexed)
                Container(
                  key: ValueKey(sc.id),
                  color: pal.s1,
                  child: Rise(
                    i,
                    Item(
                      lead: SizedBox(width: 30, child: Text('${i + 1}', textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, c: pal.accText, num: true))),
                      label: sc.name,
                      sub: '成功率 ${sc.ok}% · ${sc.ms}ms',
                      trailing: Row(children: [SignalBars(sc.ms), ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.only(left: 12), child: Icon(ic('drag'), color: pal.t3)))]),
                    ),
                  ),
                ),
            ],
          ),
        ]),
        Group(title: '第二阶段 · 跨平台', foot: '当前平台（${app.platform.name}）失败后，按这个顺序换平台。这里排的是平台，不是脚本。', children: [
          Item(icon: 'globe', color: 'blue', label: '③ 到其他平台搜索同一首歌', sub: '按歌名 + 歌手 + 时长（±3 秒）匹配，找到后用该平台自己的脚本顺序解析', sw: s.crossPlat, onSw: (v) => u(() => s.crossPlat = v)),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => u(() {
              final x = cross.removeAt(a);
              cross.insert(b > a ? b - 1 : b, x);
              app.crossOrder
                ..removeWhere((e) => e != app.plat)
                ..addAll(cross);
            }),
            children: [
              for (final (i, id) in cross.indexed)
                Container(
                  key: ValueKey(id),
                  color: pal.s1,
                  child: Item(
                    lead: PlatBadge(platformBy(id), size: 30),
                    label: platformBy(id).name,
                    sub: app.isIn(id) ? '已登录 · 可匹配会员歌曲' : '未登录 · 只匹配免费歌曲',
                    trailing: Row(children: [Text('${i + 1}', style: ts(14, c: pal.t3, num: true)), ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.only(left: 10), child: Icon(ic('drag'), color: pal.t3)))]),
                  ),
                ),
            ],
          ),
        ]),
        Group(title: '兜底', children: [Item(icon: 'next', color: 'red', label: '④ 全部失败时播放下一首', sw: s.autoNext, onSw: (v) => u(() => s.autoNext = v))]),
        Group(title: '提醒', children: [
          Item(label: '音质降级时提醒', sw: s.nQ, onSw: (v) => u(() => s.nQ = v)),
          Item(label: '切换脚本时提醒', sw: s.nS, onSw: (v) => u(() => s.nS = v)),
          Item(label: '换平台或跳到下一首时提醒', sw: s.nA, onSw: (v) => u(() => s.nA = v)),
        ]),
      ],
    ]);
  }

  Widget _band(Pal pal, String t, Color c) => Container(
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: ts(10.5, w: FontWeight.w600, c: c)),
      );
}

// ======================= 平台与解析脚本 =======================
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    return SubPage(title: '平台与解析脚本', actions: [IBtn('plus', onTap: () => openImportSource(context))], children: [
      _note(pal, 'info', '先选音乐平台，再选该平台的解析脚本。脚本由你自行导入，Lyra 只负责调度和播放，请仅使用你有权访问的内容。'),
      Padding(padding: const EdgeInsets.fromLTRB(Tk.pad + 6, 6, 0, 8), child: Text('当前', style: ts(12.5, w: FontWeight.w600, c: pal.t3))),
      // 平台登录接入前，联网模式下每个平台都显示「未登录」
      const Padding(padding: EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 18), child: SourceBar()),
      for (final p in platforms)
        Group(children: [
          Item(
            lead: PlatBadge(p, size: 30),
            label: p.name,
            sub: app.isIn(p.id) ? '已登录 · ${app.platLogin[p.id]}' : '未登录 · 每日推荐与个人歌单不可用',
            trailing: p.id == app.plat ? const Badge2('当前', acc: true) : Btn.sec('切换', small: true, onTap: () => app.switchPlatform(p.id)),
          ),
          for (final sc in app.scriptsOf(p.id))
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: app.online
                  ? Item(
                      label: '${sc.name}  v${sc.ver}',
                      sub: _scriptSub(app, sc),
                      trailing: app.sources.activeId == sc.id ? const Badge2('当前', acc: true) : null,
                      onTap: () => _scriptDetail(context, sc.id),
                    )
                  : Item(
                      label: '${sc.name}  v${sc.ver}',
                      sub: '${sc.qualities.join(' · ')} · 成功率 ${sc.ok}%',
                      trailing: Row(children: [SignalBars(sc.ms), SizedBox(width: 52, child: Text('${sc.ms}ms', textAlign: TextAlign.right, style: ts(12, w: FontWeight.w600, c: pal.t3, num: true)))]),
                    ),
            ),
        ]),
      if (app.online)
        _note(pal, app.scripts.isEmpty ? 'info' : 'check', app.scripts.isEmpty
            ? '还没有导入音源脚本，导入后才能播放。脚本保存在本机，赞助用户可在「备份与同步 → 分项同步 → 音源脚本」里和桌面端互通。'
            : '已导入 ${app.scripts.length} 个脚本。播放时先用「当前」音源，解析不出来再依次尝试其它脚本；原平台都不行时按「智能换源」设置找其它平台的同名歌。'),
      Group(children: [Item(icon: 'plus', color: 'blue', label: '导入解析脚本', sub: '从文件、链接或剪贴板导入', onTap: () => openImportSource(context))]),
    ]);
  }
}

Widget _note(Pal pal, String icon, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Tk.pad, 0, Tk.pad, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pal.accSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(ic(icon), size: 18, color: pal.accText), const SizedBox(width: 10), Expanded(child: Text(text, style: ts(12.5, c: pal.t2, h: 1.55)))]),
      ),
    );
Widget noteBox(BuildContext c, String icon, String text) => _note(c.pal, icon, text);

void openImportSource(BuildContext context) {
  showLSheet(context, title: '导入音源', builder: (c) => Column(children: [
        Group(children: [
          Item(icon: 'link', color: 'blue', label: '从链接导入', sub: '输入 .js 脚本地址', onTap: () {
            Navigator.of(c).pop();
            _scriptLink(context);
          }),
          Item(icon: 'folder', color: 'orange', label: '从文件导入', sub: '选择本地 .js 文件', onTap: () {
            Navigator.of(c).pop();
            if (context.appRead.online) {
              _pickScriptFile(context);
              return;
            }
            toast('已打开文件选择器', 'folder');
          }),
          Item(icon: 'paste', color: 'violet', label: '粘贴内容', sub: '直接粘贴脚本代码', onTap: () {
            Navigator.of(c).pop();
            _scriptPaste(context);
          }),
        ]),
        const Hint('导入前会先校验脚本，显示名称、版本、支持的平台与音质。脚本在沙箱中运行，无法访问你的账号凭据。'),
      ]));
}

void _scriptLink(BuildContext context) {
  final tc = TextEditingController();
  showLSheet(context, title: '从链接导入', builder: (c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
        child: Column(children: [
          LField(controller: tc, label: '脚本地址（https://…/source.js）', icon: 'link', autofocus: true),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Btn.sec('粘贴', icon: 'paste', onTap: () async {
              if (!context.appRead.online) {
                tc.text = 'https://example.com/lyra/source-e.js';
                return;
              }
              final d = await Clipboard.getData('text/plain');
              tc.text = d?.text?.trim() ?? '';
            })),
            const SizedBox(width: 10),
            Expanded(child: Btn('下一步', onTap: () {
              Navigator.of(c).pop();
              if (context.appRead.online) {
                _fetchScript(context, tc.text.trim());
              } else {
                _verify(context);
              }
            })),
          ]),
        ]),
      ));
}

void _scriptPaste(BuildContext context) {
  final tc = TextEditingController();
  showLSheet(context, title: '粘贴脚本', builder: (c) => StatefulBuilder(builder: (c, set) {
        final pal = c.pal;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: pal.s2, borderRadius: BorderRadius.circular(14)),
              child: TextField(controller: tc, maxLines: null, onChanged: (_) => set(() {}), style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: pal.t1, height: 1.5), decoration: InputDecoration.collapsed(hintText: '/* 在此粘贴脚本内容 */', hintStyle: TextStyle(color: pal.t3, fontFamily: 'monospace'))),
            ),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tc.text.isEmpty ? 0 : '\n'.allMatches(tc.text).length + 1} 行', textAlign: TextAlign.right, style: ts(11, c: pal.t3, num: true))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Btn.sec('取消', onTap: () => Navigator.of(c).pop())),
              const SizedBox(width: 8),
              Expanded(child: Btn.sec('粘贴脚本', onTap: () async {
                if (c.appRead.online) {
                  final d = await Clipboard.getData('text/plain');
                  set(() => tc.text = d?.text ?? '');
                  return;
                }
                set(() => tc.text = "/**\n * @name 解析脚本 E\n * @version 1.0.0\n * @platforms netease,qq\n * @quality HQ,SQ\n */\nexport async function resolve(song, quality) {\n  // ...\n}");
              })),
              const SizedBox(width: 8),
              Expanded(child: Btn('导入', onTap: tc.text.isEmpty ? null : () {
                Navigator.of(c).pop();
                if (c.appRead.online) {
                  _verifyReal(context, tc.text);
                } else {
                  _verify(context);
                }
              })),
            ]),
          ]),
        );
      }));
}

void _verify(BuildContext context) {
  final app = context.appRead;
  final pal = context.pal;
  showLDialog(context, icon: 'shield', title: '校验通过', content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final (k, v) in const [('名称', '解析脚本 E'), ('版本', 'v1.0.0'), ('平台', '网易云音乐 · QQ音乐'), ('音质', 'HQ · SQ'), ('沙箱', '无网络以外权限，无法读取账号')])
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [SizedBox(width: 44, child: Text(k, style: ts(13, c: pal.t3))), Expanded(child: Text(v, style: ts(13, w: FontWeight.w600, c: pal.t1)))])),
  ]), actions: [
    ('取消', BtnKind.sec, null),
    ('确认导入', BtnKind.pri, () {
      app.update(() {
        if (app.scripts.every((s) => s.id != 'e')) {
          app.scripts.add(const Script('e', '解析脚本 E', '1.0.0', ['netease', 'qq'], ['HQ', 'SQ'], 610, 88));
          app.scriptOrder['netease']!.add('e');
          app.scriptOrder['qq']!.add('e');
        }
      });
      toast('已导入「解析脚本 E」· 共 ${app.scripts.length} 个脚本', 'code');
    }),
  ]);
}

// ============ 联网模式：真实导入音源脚本 ============
Future<void> _fetchScript(BuildContext context, String url) async {
  final u = Uri.tryParse(url);
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return toast('请输入 http(s) 开头的脚本地址', 'info');
  toast('正在下载脚本…', 'download');
  try {
    final r = await http.get(u).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return toast('下载失败（HTTP ${r.statusCode}）', 'info');
    if (r.bodyBytes.length > ScriptStore.maxBytes) return toast('脚本超过 2 MB，不像是音源脚本', 'info');
    if (!context.mounted) return;
    _verifyReal(context, utf8.decode(r.bodyBytes, allowMalformed: true), sourceUrl: url);
  } catch (_) {
    toast('下载失败，请检查地址和网络', 'wifi');
  }
}

Future<void> _pickScriptFile(BuildContext context) async {
  XFile? f;
  try {
    // 不按扩展名过滤：不少文件管理器把 .js 标成 application/octet-stream，筛了反而选不到
    f = await openFile();
  } catch (_) {
    return toast('打不开文件选择器', 'info');
  }
  if (f == null) return;
  try {
    final size = await f.length();
    if (size > ScriptStore.maxBytes) return toast('文件超过 2 MB，不像是音源脚本', 'info');
    final raw = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    if (!context.mounted) return;
    await _verifyReal(context, raw);
  } catch (_) {
    toast('读取文件失败', 'info');
  }
}

String _platNames(Map<String, LxCapability> caps) => [
      for (final e in caps.entries)
        if (e.value.actions.contains('musicUrl')) const {'wy': '网易云', 'tx': 'QQ', 'kg': '酷狗', 'kw': '酷我', 'mg': '咪咕'}[e.key] ?? e.key,
    ].join(' · ');

String _qualityNames(Map<String, LxCapability> caps) {
  final all = <String>{for (final c in caps.values) ...c.qualities};
  return [for (final q in const ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'atmos_plus', 'master']) if (all.contains(q)) q].join(' · ');
}

String _scriptSub(AppState app, Script sc) {
  final err = app.sources.initErrorOf(sc.id);
  if (err != null) return '初始化失败：$err';
  final caps = app.sources.capsOf(sc.id);
  if (caps == null) return '${sc.qualities.isEmpty ? '音质以运行结果为准' : sc.qualities.join(' · ')} · 还没运行过';
  return '${_platNames(caps)}${sc.qualities.isEmpty ? '' : ' · ${sc.qualities.join(' · ')}'}';
}

/// 导入前先在沙箱里跑一次脚本：能完成初始化（lx.send('inited')）才导入，并显示它声明的平台和音质。
Future<void> _verifyReal(BuildContext context, String raw, {String? sourceUrl}) async {
  final app = context.appRead;
  final pal = context.pal;
  final m = ParsedScript.parse(raw);
  if (m == null) return toast('这不像是洛雪音源脚本（没有找到 JavaScript 代码）', 'info');
  toast('正在校验脚本…', 'shield');
  Map<String, LxCapability> caps;
  try {
    caps = await app.sources.manager.probe(CloudSource(id: 'probe', name: m.name, rawScript: raw, description: m.description, version: m.version, author: m.author, homepage: m.homepage));
  } catch (e) {
    if (!context.mounted) return;
    showLDialog(context, icon: 'info', iconColor: pal.danger, title: '脚本校验失败', body: '「${m.name}」没有完成初始化：$e\n\n请确认这是洛雪（LX Music）格式的自定义源脚本。', actions: [('知道了', BtnKind.pri, null)]);
    return;
  }
  if (!context.mounted) return;
  final plats = _platNames(caps);
  showLDialog(context, icon: 'code', title: '导入这个音源脚本？', content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final (k, v) in [
      ('名称', m.name),
      ('版本', m.version.isEmpty ? '-' : m.version),
      ('作者', m.author.isEmpty ? '-' : m.author),
      ('平台', plats.isEmpty ? '没有声明可播放的平台' : plats),
      ('音质', _qualityNames(caps).isEmpty ? '-' : _qualityNames(caps)),
      ('大小', '${(raw.length / 1024).toStringAsFixed(1)} KB'),
    ])
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 44, child: Text(k, style: ts(13, c: pal.t3))), Expanded(child: Text(v, style: ts(13, w: FontWeight.w600, c: pal.t1)))])),
    if (m.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.description, style: ts(12.5, c: pal.t2, h: 1.5))),
    Padding(padding: const EdgeInsets.only(top: 8), child: Text('脚本在沙箱里运行，只能发网络请求，拿不到你的账号信息。脚本由你自行提供并对其合法性负责。', style: ts(11.5, c: pal.t3, h: 1.5))),
  ]), actions: [
    ('取消', BtnKind.sec, null),
    ('导入', BtnKind.pri, () {
      final s = app.sources.add(raw, m, sourceUrl: sourceUrl);
      app.sources.rememberCaps(s.id, caps);
      toast('已导入「${m.name}」· 共 ${app.scripts.length} 个脚本', 'code');
    }),
  ]);
}

void _scriptDetail(BuildContext context, String id) {
  final app = context.appRead;
  final s = app.sources.byId(id);
  if (s == null) return;
  showLSheet(context, title: s.name, sub: s.version.isEmpty ? null : 'v${s.version}', builder: (c) {
    final caps = c.app.sources.capsOf(id);
    final err = c.app.sources.initErrorOf(id);
    final active = c.app.sources.activeId == id;
    return Column(children: [
      Group(children: [
        if (s.author.isNotEmpty) Item(icon: 'user', color: 'blue', label: '作者', val: s.author, chev: false),
        if (s.description.isNotEmpty) Item(icon: 'info', color: 'gray', label: s.description, chev: false),
        if (s.sourceUrl != null) Item(icon: 'link', color: 'teal', label: '来源', sub: s.sourceUrl, chev: false),
        Item(icon: 'code', color: 'violet', label: '大小', val: '${(s.rawScript.length / 1024).toStringAsFixed(1)} KB', chev: false),
      ]),
      Group(title: '能力', children: [
        if (err != null) Item(icon: 'info', color: 'red', label: '初始化失败', sub: err, chev: false),
        if (caps == null && err == null) const Item(icon: 'clock', color: 'gray', label: '还没运行过', sub: '第一次播放时会启动这个脚本', chev: false),
        if (caps != null)
          for (final e in caps.entries)
            Item(icon: 'vinyl', color: 'green', label: e.value.name, sub: '${const {'wy': '网易云音乐', 'tx': 'QQ音乐', 'kg': '酷狗音乐', 'kw': '酷我音乐', 'mg': '咪咕音乐', 'local': '本地'}[e.key] ?? e.key} · ${e.value.qualities.isEmpty ? e.value.actions.join(' / ') : e.value.qualities.join(' · ')}', chev: false),
      ]),
      Group(children: [
        if (!active)
          Item(icon: 'check', color: 'blue', label: '设为当前音源', sub: '播放时优先使用', onTap: () {
            Navigator.of(c).pop();
            app.sources.setActive(id);
            toast('已切换到「${s.name}」', 'check');
          }),
        Item(icon: 'trash', color: 'red', label: '删除这个脚本', danger: true, chev: false, onTap: () {
          Navigator.of(c).pop();
          app.sources.remove(id);
          toast('已删除「${s.name}」', 'trash');
        }),
      ]),
    ]);
  });
}
