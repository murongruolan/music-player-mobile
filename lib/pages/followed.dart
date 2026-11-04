// 我的 → 关注的歌手：本机记录的关注列表。点进去打开平台歌手页（没有平台 id 时先搜一下），右侧可直接放歌手电台。
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/state.dart';
import '../core/taste.dart';
import '../data/mock.dart';
import '../platform/models.dart';
import '../shell/shell.dart';
import '../source/source_manager.dart' show normalizeSinger;
import '../ui/cover.dart';
import '../ui/kit.dart';
import 'common.dart';
import 'detail.dart';
import 'radio.dart';
import 'remote.dart';

class FollowedArtistsPage extends StatelessWidget {
  const FollowedArtistsPage({super.key});

  Future<void> _open(BuildContext context, AppState app, FollowedArtist f) async {
    var id = f.catalogId;
    var plat = f.platform;
    if (id == null && app.online) {
      try {
        final o = await app.content.search(plat.isEmpty ? app.plat : plat, f.name, SearchType.artist, limit: 5);
        final hit = o.result.items.where((a) => normalizeSinger(a.title) == normalizeSinger(f.name)).firstOrNull;
        if (hit != null) {
          id = hit.id;
          plat = o.platform;
          app.taste.attachCatalog(f.name, plat, hit.id, cover: hit.cover);
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    if (id != null) return push(context, RemoteCollectionPage(platform: plat, type: CatalogType.artist, id: id, title: f.name, cover: f.cover));
    // 没有平台歌手页：退回到音乐库里的这位歌手
    final s = songs.where((x) => x.artist == f.name).firstOrNull;
    if (s != null) return push(context, ArtistPage(id: s.id));
    toast('没找到「${f.name}」的歌手页', 'info');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = context.pal;
    final list = app.taste.followed;
    return SubPage(title: '关注的歌手', children: [
      if (list.isEmpty)
        const EmptyState('user', '还没有关注的歌手', desc: '在歌手页右上角点爱心关注，之后在这里找到他们')
      else
        Group(children: [
          for (final f in list)
            Item(
              lead: Cover(hue: (f.name.hashCode % 360).toDouble(), variant: 1, size: 40, radius: 20, url: f.cover),
              label: f.name,
              sub: '关注于 ${f.at.month} 月 ${f.at.day} 日',
              onTap: () => unawaited(_open(context, app, f)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IBtn('wave', size: 36, onTap: () => unawaited(playArtistRadio(app, f.name, platform: f.platform.isEmpty ? null : f.platform))),
                IBtn('heartf', size: 36, color: pal.accText, onTap: () {
                  app.taste.toggleFollow(f.name, f.platform);
                  toast('已取消关注 ${f.name}', 'heart');
                }),
              ]),
            ),
        ]),
      const Hint('关注记录只保存在这台设备上。电台会在歌手所在平台搜索他的歌，打乱后连续播放。'),
    ]);
  }
}
