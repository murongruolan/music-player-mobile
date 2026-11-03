// 公告：列表、已读状态、本地历史、上报队列。
//
// 后端只返回「还没处理过」的公告，处理过的就不再下发，所以本机保存一份历史，公告页才能看到旧公告。
// 后端 → 界面的映射：
//   level warning → 「重要」（红色）；sticky → 「置顶」；info → 「通知」
//   dismissible = false → 必须单独点「我已知晓」（上报 confirm）
//   弹窗：level 不是 info，或者必须确认的公告
// 上报：弹窗里看过可关闭的 → dismiss；公告页点开 / 全部标为已读 → read；我已知晓 → confirm。
// 上报先记到本地队列再发，失败（断网）下次启动或刷新时补发；服务端幂等。
import 'dart:async';
import 'dart:convert';
import '../api/announcement_api.dart';
import '../data/mock.dart' as mock;
import '../data/models.dart';
import '../net/net.dart';

class Announcements {
  final Net? _net;
  final void Function() _changed;

  /// 演示模式（没有 Net）用 mock 数据。
  List<Announcement> items;
  final read = <String>{};
  final _outbox = <(String, AnnouncementAction)>[];
  final _history = <String, RemoteAnnouncement>{};
  bool loading = false, _restored = false;
  Timer? _flushT;
  bool _flushing = false;

  static const _kHistory = 'ann.history.v1', _kRead = 'ann.read.v1', _kOutbox = 'ann.outbox.v1';
  static const _maxHistory = 60;

  Announcements(this._net, this._changed) : items = _net == null ? [...mock.announcements] : [];

  int get unread => items.where((a) => !read.contains(a.id)).length;
  bool isRead(Announcement a) => read.contains(a.id);
  List<Announcement> get popups => items.where((a) => a.popup && !read.contains(a.id)).toList();

  /// 启动 / 公告页刷新时调用。未登录时什么都不做。
  Future<void> load() async {
    final n = _net;
    if (n == null || !n.session.isLoggedIn || loading) return;
    loading = true;
    _changed();
    try {
      if (!_restored) await _restore();
      final remote = await AnnouncementApi(n.client).list();
      final ids = remote.map((r) => r.id).toSet();
      // 本机历史里有、服务端不再下发的：已在别处处理过 → 本机也算已读
      for (final id in _history.keys) {
        if (!ids.contains(id)) read.add(id);
      }
      for (final r in remote) {
        _history[r.id] = r;
        // 本机已读但服务端还在下发：上次上报没成功，补一次
        if (read.contains(r.id) && !_outbox.any((e) => e.$1 == r.id)) {
          _outbox.add((r.id, r.dismissible ? AnnouncementAction.read : AnnouncementAction.confirm));
        }
      }
      _trim();
      _rebuild();
      await _save();
      unawaited(_flush());
    } on ApiException catch (_) {
      // 拉取失败：保留本机历史，不打扰用户
      if (items.isEmpty && _history.isNotEmpty) _rebuild();
    } finally {
      loading = false;
      _changed();
    }
  }

  /// 标记已读并上报。已读过的不重复上报。
  void mark(Announcement a, AnnouncementAction action) {
    if (read.contains(a.id)) return;
    read.add(a.id);
    _changed();
    if (_net == null) return;
    _outbox.add((a.id, action));
    unawaited(_save());
    _flushT?.cancel();
    _flushT = Timer(const Duration(milliseconds: 800), () => unawaited(_flush())); // 「全部已读」时攒一下再发
  }

  /// 退出登录：清掉本机公告数据（下一个账号重新拉取）。
  Future<void> reset() async {
    _flushT?.cancel();
    _history.clear();
    _outbox.clear();
    _restored = false;
    read.clear();
    items = _net == null ? [...mock.announcements] : [];
    final p = _net?.prefs;
    if (p != null) {
      await p.delete(_kHistory);
      await p.delete(_kRead);
      await p.delete(_kOutbox);
    }
    _changed();
  }

  void dispose() => _flushT?.cancel();

  // ---------------------------------------------------------------- 内部

  Future<void> _flush() async {
    final n = _net;
    if (n == null || _flushing || _outbox.isEmpty || !n.session.isLoggedIn) return;
    _flushing = true;
    final api = AnnouncementApi(n.client);
    try {
      while (_outbox.isNotEmpty) {
        final (id, action) = _outbox.first;
        try {
          await api.act(id, action);
        } on ApiException catch (e) {
          // 断网 / 限流 / 服务器错误：留在队列里下次再发；公告不存在等业务错误直接丢弃
          if (e.isNetwork || e.isRateLimited || e.kind == ApiErrorKind.server || e.isUnauthorized) break;
        }
        _outbox.removeAt(0);
      }
    } finally {
      _flushing = false;
      await _save();
    }
  }

  void _rebuild() {
    final l = _history.values.toList()..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    items = [for (final r in l) toModel(r)];
  }

  void _trim() {
    if (_history.length <= _maxHistory) return;
    final l = _history.values.toList()..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    for (final r in l.take(_history.length - _maxHistory)) {
      _history.remove(r.id);
      read.remove(r.id);
    }
  }

  static Announcement toModel(RemoteAnnouncement r) {
    final d = r.createdAt;
    final date = d == null ? '' : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final type = switch (r.level) { 'warning' => '重要', 'sticky' => '置顶', _ => '通知' };
    return Announcement(r.id, type, date, r.title, r.content, important: r.level == 'warning', popup: r.level != 'info' || !r.dismissible, closable: r.dismissible);
  }

  Future<void> _restore() async {
    _restored = true;
    final p = _net?.prefs;
    if (p == null) return;
    try {
      final h = await p.read(_kHistory);
      if (h != null) {
        for (final e in jsonDecode(h) as List) {
          if (e is Map) {
            final r = RemoteAnnouncement.fromJson(e.cast<String, dynamic>());
            _history[r.id] = r;
          }
        }
      }
      final rd = await p.read(_kRead);
      if (rd != null) read.addAll((jsonDecode(rd) as List).map((e) => '$e'));
      final ob = await p.read(_kOutbox);
      if (ob != null) {
        for (final e in jsonDecode(ob) as List) {
          if (e is List && e.length == 2) {
            final a = AnnouncementAction.values.where((x) => x.name == e[1]).firstOrNull;
            if (a != null) _outbox.add(('${e[0]}', a));
          }
        }
      }
    } catch (_) {
      // 本地数据损坏：当作没有
    }
  }

  Future<void> _save() async {
    final p = _net?.prefs;
    if (p == null) return;
    await p.write(_kHistory, jsonEncode([for (final r in _history.values) r.toJson()]));
    await p.write(_kRead, jsonEncode(read.where(_history.containsKey).toList()));
    await p.write(_kOutbox, jsonEncode([for (final (id, a) in _outbox) [id, a.name]]));
  }
}
