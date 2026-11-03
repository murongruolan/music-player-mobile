// 六种同步文档的本机适配。
//
// - settings：本机设置（实时同步）。只在 Lyra 移动端之间有意义；带 client 标记，读取时只认识的键才生效。
// - listening_stats：听歌统计（手动上传 / 恢复）。
// - library / favorites / playlists：音乐库。需要内容层提供 [LibraryBinding]；没接入前不可用（不会把 mock 数据推上去）。
// - lx_sources：音源脚本。需要 [SourcesBinding]；同上。
import '../api/sync_api.dart';
import '../core/listening_stats.dart';
import '../net/json.dart';
import 'cloud_models.dart';
import 'sync_doc.dart';

class SettingsDoc extends SyncDoc {
  final Json Function() read;
  final void Function(Json) write;
  SettingsDoc(this.read, this.write);

  @override
  String get type => DocType.settings;
  @override
  String get label => '设置';
  @override
  bool get isEmpty => false;
  @override
  Object export() => {'format': 1, 'client': 'lyra-mobile', 'settings': read()};

  /// 设置以云端为准（没有合并的意义），本机不会有「多出来」的数据。
  @override
  bool apply(Object? remote, {bool replace = false}) {
    final j = asJson(remote);
    write(j.objOrNull('settings') ?? j);
    return false;
  }
}

class StatsDoc extends SyncDoc {
  final ListeningStats stats;
  StatsDoc(this.stats) {
    stats.onLocalChange = () => onLocalChange?.call();
  }

  @override
  String get type => DocType.listeningStats;
  @override
  String get label => '听歌统计';
  @override
  bool get isEmpty => stats.cloudEmpty;
  @override
  Object export() => stats.toPayload();
  @override
  bool apply(Object? remote, {bool replace = false}) => stats.apply(remote, replace: replace);
}

/// 内容层（本地音乐库）实现它，音乐库相关的三种文档才可用。
abstract class LibraryBinding {
  CloudLibrary read();
  void write(CloudLibrary lib);
}

/// 内容层（音源脚本管理）实现它，lx_sources 才可用。
abstract class SourcesBinding {
  (List<CloudSource>, String?) read();
  void write(List<CloudSource> sources, String? activeId);
}

class LibraryDoc extends SyncDoc {
  final LibraryBinding? binding;
  LibraryDoc(this.binding);
  @override
  String get type => DocType.library;
  @override
  String get label => '音乐库';
  @override
  bool get available => binding != null;
  @override
  bool get isEmpty => binding?.read().isEmpty ?? true;
  @override
  Object export() => binding!.read().toPayload();
  @override
  bool apply(Object? remote, {bool replace = false}) {
    final r = CloudLibrary.parse(remote);
    if (replace) {
      binding!.write(r);
      return false;
    }
    final (m, extra) = CloudLibrary.merge(binding!.read(), r);
    binding!.write(m);
    return extra;
  }
}

class FavoritesDoc extends SyncDoc {
  final LibraryBinding? binding;
  FavoritesDoc(this.binding);
  @override
  String get type => DocType.favorites;
  @override
  String get label => '收藏';
  @override
  bool get available => binding != null;
  @override
  bool get isEmpty => binding?.read().favorites.isEmpty ?? true;
  @override
  Object export() => CloudLibrary.favoritesPayload(binding!.read().favorites);
  @override
  bool apply(Object? remote, {bool replace = false}) {
    final cur = binding!.read();
    final r = CloudLibrary.parseFavorites(remote);
    final (l, extra) = replace ? (r, false) : CloudLibrary.mergeFavorites(cur.favorites, r);
    binding!.write(CloudLibrary(favorites: l, playlists: cur.playlists));
    return extra;
  }
}

class PlaylistsDoc extends SyncDoc {
  final LibraryBinding? binding;
  PlaylistsDoc(this.binding);
  @override
  String get type => DocType.playlists;
  @override
  String get label => '歌单';
  @override
  bool get available => binding != null;
  @override
  bool get isEmpty => binding?.read().playlists.isEmpty ?? true;
  @override
  Object export() => CloudLibrary.playlistsPayload(binding!.read().playlists);
  @override
  bool apply(Object? remote, {bool replace = false}) {
    final cur = binding!.read();
    final r = CloudLibrary.parsePlaylists(remote);
    final (l, extra) = replace ? (r, false) : CloudLibrary.mergePlaylists(cur.playlists, r);
    binding!.write(CloudLibrary(favorites: cur.favorites, playlists: l));
    return extra;
  }
}

class SourcesDoc extends SyncDoc {
  final SourcesBinding? binding;
  SourcesDoc(this.binding);
  @override
  String get type => DocType.lxSources;
  @override
  String get label => '音源脚本';
  @override
  bool get available => binding != null;
  @override
  bool get isEmpty => binding?.read().$1.isEmpty ?? true;
  @override
  Object export() {
    final (l, active) = binding!.read();
    return CloudSource.payload(l, active);
  }

  @override
  bool apply(Object? remote, {bool replace = false}) {
    final (r, rActive) = CloudSource.parse(remote);
    final (cur, active) = binding!.read();
    final (l, extra) = replace ? (r, false) : CloudSource.merge(cur, r);
    binding!.write(l, replace ? rActive : (active ?? rActive));
    return extra;
  }
}
