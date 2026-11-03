// 公告接口。后端只返回「当前用户还没处理过（confirm / read / dismiss）」的公告。
import '../net/net.dart';

/// 后端公告。level：info（普通）/ warning（重要）/ sticky（置顶）。
class RemoteAnnouncement {
  final String id, title, content, level;
  final bool dismissible;
  final DateTime? createdAt;
  const RemoteAnnouncement({required this.id, required this.title, required this.content, required this.level, required this.dismissible, this.createdAt});

  factory RemoteAnnouncement.fromJson(Json j) => RemoteAnnouncement(
        id: j.str('id'),
        title: j.str('title'),
        content: j.str('content'),
        level: j.str('level', 'info'),
        dismissible: j.boolean('dismissible', true),
        createdAt: j.time('createdAt'),
      );

  Json toJson() => {'id': id, 'title': title, 'content': content, 'level': level, 'dismissible': dismissible, 'createdAt': createdAt?.toUtc().toIso8601String()};
}

enum AnnouncementAction { confirm, read, dismiss }

class AnnouncementApi {
  final ApiClient _c;
  AnnouncementApi(this._c);

  Future<List<RemoteAnnouncement>> list() => _c.get('/announcements', decode: (d) => asJson(d).list('items', RemoteAnnouncement.fromJson));

  /// 上报处理结果。幂等（服务端 upsert），失败可以放心重试。
  Future<void> act(String id, AnnouncementAction action) async {
    await _c.post('/announcements/${Uri.encodeComponent(id)}/${action.name}', body: {'deviceId': _c.device.deviceId}, retry: true);
  }
}
