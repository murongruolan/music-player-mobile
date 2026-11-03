// 每日混音：头卡（按日期换色相）· 口味画像 · 30 首（左滑 / ··· 里可「不感兴趣」）。
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/tokens.dart';
import '../data/mock.dart';
import '../shell/shell.dart';
import '../ui/cover.dart';
import '../ui/kit.dart';
import 'common.dart';
import 'detail.dart';

class DailyPage extends StatelessWidget {
  const DailyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final ids = app.listOf('daily');
    final now = DateTime.now();
    const months = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    const weeks = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return TabPage(
      title: '每日混音',
      controller: tabScroll[2],
      onRefresh: app.reload,
      actions: [IBtn('refresh', onTap: () async {
        await app.reload();
        toast('已根据最新聆听重新生成', 'refresh');
      })],
      children: app.loading
          ? [const SkeletonPage()]
          : [
              Rise(
                0,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Tk.pad),
                  child: Cover(
                    hue: 268.0 + now.day * 11,
                    variant: 2,
                    width: double.infinity,
                    height: 200,
                    radius: 26,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x1A000000), Color(0xA6000000)])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(now.day.toString().padLeft(2, '0'), style: ts(54, w: FontWeight.w800, c: Colors.white, h: .9, num: true)),
                          const SizedBox(width: 8),
                          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${months[now.month - 1]}\n${weeks[now.weekday - 1]}', style: ts(12, w: FontWeight.w600, c: const Color(0xD9FFFFFF), h: 1.3))),
                        ]),
                        const Spacer(),
                        Text('今天的 30 首', style: ts(22, w: FontWeight.w800, c: Colors.white)),
                        const SizedBox(height: 3),
                        Text('根据你最近 30 天的 214 次聆听生成 · 明天 06:00 更新', style: ts(12.5, c: const Color(0xCCFFFFFF))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Btn('播放全部', icon: 'play', small: true, onTap: () => app.playAll('daily', name: '每日混音')),
                          const SizedBox(width: 10),
                          Btn('随机', icon: 'shuffle', small: true, kind: BtnKind.glass, onTap: () => app.playAll('daily', shuffle: true, name: '每日混音')),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
              Sec('你的口味画像', size: 16, more: '详情', onMore: () => push(context, const StatsPage())),
              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tk.pad), children: [
                  for (final (i, t) in tasteChips.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: LChip('${t[0]}', on: i == 0, trailing: Text('${t[1]}%', style: ts(12.5, w: FontWeight.w700, c: i == 0 ? pal.accText : pal.t2, num: true))),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              for (final (i, id) in ids.take(18).indexed) Rise(i + 2, SongRow(songs[id], list: 'daily', listName: '每日混音', ctx: 'daily', key: ValueKey(id))),
              const Hint('向左滑动歌曲可快速收藏或下一首播放；··· 里选「不感兴趣」，明天的推荐会参考你的反馈', align: TextAlign.center, padding: EdgeInsets.all(14)),
            ],
    );
  }
}
