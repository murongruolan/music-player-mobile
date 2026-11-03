// 打印各平台全部歌单分类（名称 / 分组 / id）和排行榜名称，用来设计首页「心情 / 场景 / 曲风」与「新歌榜」的匹配规则。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/platform/models.dart';
import 'package:lyra/platform/registry.dart';
import 'live_util.dart';

void main() {
  final hub = PlatformHub(http: liveHttp());
  for (final c in Plat.all) {
    test('$c 分类与榜单清单', () async {
      final cats = await probe('$c categories', () => hub.playlistCategories(c), (l) => '${l.length} 个');
      if (cats != null) stdout.writeln('CATS $c: ${cats.map((x) => '${x.name}[${x.group}](${x.id})').join(' | ')}');
      final boards = await probe('$c boards', () => hub.leaderboards(c), (l) => '${l.length} 个');
      if (boards != null) stdout.writeln('BOARDS $c: ${boards.map((x) => '${x.title}(${x.id})${x.subtitle.isEmpty ? '' : '「${x.subtitle}」'}${x.cover == null ? '' : '🖼'}').join(' | ')}');
      final pls = await probe('$c playlists', () => hub.playlists(c, limit: 12), (p) => '${p.items.length} 个');
      if (pls != null && pls.items.isNotEmpty) stdout.writeln('PL $c: cover=${pls.items.first.cover} creator=${pls.items.first.creator} play=${pls.items.first.playCountText} tracks=${pls.items.first.trackCount}');
    }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));
  }
}
