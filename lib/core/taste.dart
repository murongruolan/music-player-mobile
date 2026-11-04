// 本机口味记录：关注的歌手、标记「不感兴趣」的歌。只存在本机（prefs），不上云。
// 用途：「我的 → 关注的歌手」列表；私人电台 / 歌手电台排除不感兴趣的歌。
import 'dart:convert';
import '../net/storage.dart';

/// 关注的歌手。[catalogId] 是平台歌手 id（有的话点进去直接打开平台歌手页）。
class FollowedArtist {
  final String name, platform;
  final String? catalogId, cover;
  final DateTime at;
  const FollowedArtist(this.name, this.platform, {this.catalogId, this.cover, required this.at});

  Map<String, Object?> toJson() => {'name': name, 'platform': platform, if (catalogId != null) 'id': catalogId, if (cover != null) 'cover': cover, 'at': at.toIso8601String()};
  static FollowedArtist? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return FollowedArtist(name, '${j['platform'] ?? ''}', catalogId: j['id'] as String?, cover: j['cover'] as String?, at: DateTime.tryParse('${j['at']}') ?? DateTime.now());
  }
}

class TasteStore {
  final KvStore? _prefs;
  final void Function() _changed;
  TasteStore(this._prefs, this._changed);

  static const _kFollow = 'taste.followed.v1', _kDislike = 'taste.disliked.v1';

  final _followed = <FollowedArtist>[];

  /// 不感兴趣的歌（曲目 key，如 `wy:123`）。
  final disliked = <String>{};

  /// 最近关注的在前。
  List<FollowedArtist> get followed => List.unmodifiable(_followed);

  static String _norm(String n) => n.trim().toLowerCase();
  bool follows(String name) => _followed.any((f) => _norm(f.name) == _norm(name));

  Future<void> load() async {
    final p = _prefs;
    if (p == null) return;
    try {
      final f = jsonDecode(await p.read(_kFollow) ?? '[]');
      if (f is List) _followed
        ..clear()
        ..addAll(f.map(FollowedArtist.fromJson).whereType<FollowedArtist>());
      final d = jsonDecode(await p.read(_kDislike) ?? '[]');
      if (d is List) disliked
        ..clear()
        ..addAll(d.map((e) => '$e'));
    } catch (_) {
      // 数据损坏：当作空的
    }
  }

  /// 关注 / 取消关注。返回关注后的状态。
  bool toggleFollow(String name, String platform, {String? catalogId, String? cover}) {
    final on = !follows(name);
    if (on) {
      _followed.insert(0, FollowedArtist(name.trim(), platform, catalogId: catalogId, cover: cover, at: DateTime.now()));
    } else {
      _followed.removeWhere((f) => _norm(f.name) == _norm(name));
    }
    _save();
    return on;
  }

  /// 补上平台歌手 id（关注时还不知道、之后查到了）。
  void attachCatalog(String name, String platform, String catalogId, {String? cover}) {
    final i = _followed.indexWhere((f) => _norm(f.name) == _norm(name));
    if (i < 0 || _followed[i].catalogId != null) return;
    final f = _followed[i];
    _followed[i] = FollowedArtist(f.name, platform, catalogId: catalogId, cover: cover ?? f.cover, at: f.at);
    _save();
  }

  void dislike(String key) {
    if (key.isEmpty || !disliked.add(key)) return;
    // 只留最近 500 条
    if (disliked.length > 500) disliked.remove(disliked.first);
    _save();
  }

  void undislike(String key) {
    if (disliked.remove(key)) _save();
  }

  void _save() {
    _changed();
    final p = _prefs;
    if (p == null) return;
    p.write(_kFollow, jsonEncode([for (final f in _followed) f.toJson()]));
    p.write(_kDislike, jsonEncode([...disliked]));
  }
}
