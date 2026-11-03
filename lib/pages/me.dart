// 我的：账号卡 · 本周聆听 · 那年今日 · 快捷工具（云盘 / 下载 / 识曲 / 睡眠定时）· 设置分组。
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../net/api_config.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/sheets.dart';
import 'common.dart';
import 'detail.dart';
import 'misc.dart';
import 'scan.dart';
import 'settings.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final otd = app.online ? null : songs[12]; // 「那年今日」需要一年以上的聆听记录，联网模式暂不显示
    // 登录后展示真实资料（AppState.account），演示 / 截图回落 mock
    final acc = app.account;
    final name = acc?.nickname ?? (app.online ? 'Lyra 用户' : '阿栗');
    return TabPage(
      title: '我的',
      controller: tabScroll[4],
      actions: [IBtn('scan', onTap: () => pushFull(context, const ScanPage())), IBtn('gear', onTap: () => push(context, const AppearancePage()))],
      children: [
        Rise(
          0,
          CardBox(
            onTap: () => push(context, const AccountPage()),
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Avatar(avatarText(app), size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: ts(19, w: FontWeight.w700, c: pal.t1)),
                  const SizedBox(height: 3),
                  Text(acc == null ? (app.online ? '' : 'UID 10086427 · ali@example.com') : 'UID ${acc.uid} · ${acc.email}', style: ts(12.5, c: pal.t2)),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (acc != null && !acc.isActivated)
                      const Badge2('未激活', icon: 'crown')
                    else
                      const Badge2('已激活', acc: true, icon: 'crown'),
                    for (final id in app.platLogin.keys) Padding(padding: const EdgeInsets.only(left: 6), child: PlatBadge(platformBy(id), size: 22)),
                  ]),
                ]),
              ),
              Icon(ic('right'), color: pal.t3),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Rise(1, const _WeekCard()),
        const SizedBox(height: 12),
        if (otd != null) Rise(
          2,
          CardBox(
            onTap: () => app.play(otd.id, list: 'all'),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Cover.song(otd, size: 52, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(ic('history'), size: 13, color: pal.accText), const SizedBox(width: 4), Text('那年今日 · 2025.11.02', style: ts(11.5, w: FontWeight.w600, c: pal.accText))]),
                  const SizedBox(height: 4),
                  Text('一年前的今天，你把「${otd.title}」听了 9 遍', maxLines: 2, style: ts(13.5, w: FontWeight.w600, c: pal.t1, h: 1.35)),
                ]),
              ),
              IBtn('play', bg: pal.s2, size: 40),
            ]),
          ),
        ),
        QuickGrid([
          ('cloud', '音乐云盘', () => push(context, const CloudPage())),
          ('download', '下载管理', () => push(context, const DownloadPage())),
          ('mic', '听歌识曲', () => pushFull(context, const ScanPage(match: true))),
          ('moon', app.timer > 0 ? '${app.timer} 分钟' : '睡眠定时', () => openTimer(context)),
        ]),
        const SizedBox(height: 22),
        Group(title: '个性化', children: [
          Item(icon: 'palette', color: 'violet', label: '外观与界面', val: '${accents[app.accent].name} · ${barStyles[app.bar]}', onTap: () => push(context, const AppearancePage())),
          Item(icon: 'quote', color: 'pink', label: '歌词', val: app.set.trans ? '显示翻译' : null, onTap: () => push(context, const LyricsSettingsPage())),
          Item(icon: 'layers', color: 'cyan', label: '系统歌词', sub: '悬浮歌词 · 蓝牙/车机 · 状态栏', onTap: () => push(context, const SysLyricsPage())),
        ]),
        Group(title: '播放', children: [
          Item(icon: 'play', color: 'orange', label: '播放与音质', val: app.quality, onTap: () => push(context, const PlaybackPage())),
          Item(icon: 'globe', color: 'red', label: '平台与解析脚本', val: '${app.platform.short} · ${app.curScript.name}', onTap: () => push(context, const SourcesPage())),
          Item(icon: 'zap', color: 'gold', label: '智能换源', val: app.set.smart ? '已开启' : '已关闭', onTap: () => push(context, const SmartPage())),
          Item(icon: 'sliders', color: 'teal', label: '均衡器', val: app.eqOn ? app.eqPreset : '关闭', onTap: () => openEq(context)),
        ]),
        Group(title: '账号与数据', children: [
          Item(icon: 'link', color: 'green', label: '平台账号', val: '已登录 ${app.platLogin.length} 个', onTap: () => push(context, const PlatAccountsPage())),
          Item(icon: 'refresh', color: 'blue', label: '账号备份与同步', onTap: () => push(context, const BackupPage())),
          Item(icon: 'bell', color: 'orange', label: '公告', val: app.unread > 0 ? '${app.unread} 条未读' : null, onTap: () => push(context, const AnnouncementsPage())),
          Item(icon: 'info', color: 'gray', label: '关于与更新', val: app.online ? 'v${ApiConfig.appVersion}' : 'v2.4.0', onTap: () => push(context, const AboutPage())),
        ]),
      ],
    );
  }
}

/// 本周聆听卡：柱状图在右侧独立区域，不会盖住文字（v4 修复）。
class _WeekCard extends StatelessWidget {
  const _WeekCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.online) return const _RealWeekCard();
    final pal = context.pal;
    const vals = [42, 65, 38, 80, 54, 96, 71];
    return CardBox(
      onTap: () => push(context, const StatsPage()),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本周聆听 · 11.2 – 11.8', style: ts(12, c: pal.t3)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              CountUp(6.2, decimals: 1, style: ts(30, w: FontWeight.w800, c: pal.t1, num: true)),
              const SizedBox(width: 3),
              Text('小时', style: ts(13, c: pal.t3)),
              const SizedBox(width: 8),
              Text('↑18%', style: ts(12.5, w: FontWeight.w700, c: pal.ok)),
            ]),
            const SizedBox(height: 8),
            const Wrap(spacing: 6, children: [Badge2('连续 12 天'), Badge2('最爱 · 雾港')]),
          ]),
        ),
        SizedBox(
          width: 128,
          height: 76,
          child: Column(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: vals[i] / 100),
                        duration: Duration(milliseconds: 700 + i * 50),
                        curve: Tk.out,
                        builder: (_, v, __) => FractionallySizedBox(heightFactor: v, child: Container(decoration: BoxDecoration(color: i == 6 ? pal.acc : pal.acc.withValues(alpha: .35), borderRadius: BorderRadius.circular(3)))),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Row(children: [for (final d in '一二三四五六日'.split('')) Expanded(child: Text(d, textAlign: TextAlign.center, style: ts(9.5, c: pal.t3)))]),
          ]),
        ),
      ]),
    );
  }
}

/// 本周聆听卡（真实数据）：近 7 天时长、与上 7 天对比、连续聆听天数、最常听的歌手。
class _RealWeekCard extends StatelessWidget {
  const _RealWeekCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final st = app.cloud.stats;
    final week = st.summary(7);
    final prev = st.summary(14).ms - week.ms;
    final mins = st.dailyMinutes(7);
    final maxM = mins.fold<int>(1, (a, b) => b > a ? b : a);
    final plays = st.dailyPlays(366);
    var streak = 0;
    for (var i = plays.length - 1; i >= 0 && plays[i] > 0; i--) {
      streak++;
    }
    final top = st.topArtists(7, limit: 1);
    final delta = prev > 0 ? ((week.ms - prev) / prev * 100).round() : null;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - 6);
    const wd = '一二三四五六日';
    return CardBox(
      onTap: () => push(context, const StatsPage()),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('近 7 天聆听 · ${from.month}.${from.day} – ${now.month}.${now.day}', style: ts(12, c: pal.t3)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              CountUp(week.ms / 3600000, decimals: 1, style: ts(30, w: FontWeight.w800, c: pal.t1, num: true)),
              const SizedBox(width: 3),
              Text('小时', style: ts(13, c: pal.t3)),
              if (delta != null) ...[
                const SizedBox(width: 8),
                Text('${delta >= 0 ? '↑' : '↓'}${delta.abs()}%', style: ts(12.5, w: FontWeight.w700, c: delta >= 0 ? pal.ok : pal.t3)),
              ],
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (streak > 1) Badge2('连续 $streak 天'),
              if (top.isNotEmpty) Badge2('最爱 · ${top.first.$1}'),
              if (week.plays == 0) const Badge2('还没有聆听记录'),
            ]),
          ]),
        ),
        SizedBox(
          width: 128,
          height: 76,
          child: Column(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(heightFactor: (mins[i] / maxM).clamp(.04, 1.0), child: Container(decoration: BoxDecoration(color: i == 6 ? pal.acc : pal.acc.withValues(alpha: .35), borderRadius: BorderRadius.circular(3)))),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Row(children: [for (var i = 0; i < 7; i++) Expanded(child: Text(wd[DateTime(now.year, now.month, now.day - 6 + i).weekday - 1], textAlign: TextAlign.center, style: ts(9.5, c: pal.t3)))]),
          ]),
        ),
      ]),
    );
  }
}
