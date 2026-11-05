// 下载全链路：队列管理 → resolver 取流 → 分块下载写盘 → 封面 / 歌词落盘 → 持久化清单 → 离线可播。
//
// 设计要点：
// - 已下载的歌在 MusicResolver.resolve 里优先返回本地文件（断网也能播），注册表就是本 store；
// - 队列并发数 = 设置里的 dlConc（改设置立即影响取任务速度）；
// - 「仅 Wi-Fi」通过 connectivity_plus 感知网络类型，移动网络下任务排队等待；
// - 文件落在 App 文档目录 lyra-downloads/ 下（音频 + cover.jpg + lyric.lrc），
//   卸载即清，不污染用户媒体库（后续本地扫描再提供「加入系统媒体库」）。

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/mock.dart';
import '../sync/cloud_models.dart';
import '../data/models.dart';
import '../net/net.dart';
import '../platform/lyric_parse.dart';
import '../platform/models.dart';
import '../core/network.dart';
import '../ui/cover.dart' show Cover, coverUrl;
import '../core/app_log.dart';
import '../core/state.dart';
import '../source/lx_track.dart' show appQualityOf;

/// 一条已完成的下载。
class DownloadItem {
  final String key; // LibraryStore track id（platform:songId）
  final String title, artist, platform, quality;
  final String file, coverFile, lyricFile;
  final int sizeBytes;
  final DateTime at;

  const DownloadItem({
    required this.key,
    required this.title,
    required this.artist,
    required this.platform,
    required this.quality,
    required this.file,
    required this.sizeBytes,
    required this.at,
    this.coverFile = '',
    this.lyricFile = '',
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'artist': artist,
        'platform': platform,
        'quality': quality,
        'file': file,
        if (coverFile.isNotEmpty) 'cover': coverFile,
        if (lyricFile.isNotEmpty) 'lyric': lyricFile,
        'size': sizeBytes,
        'at': at.millisecondsSinceEpoch,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        key: j['key'] as String,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        platform: j['platform'] as String? ?? '',
        quality: j['quality'] as String? ?? '',
        file: j['file'] as String,
        coverFile: j['cover'] as String? ?? '',
        lyricFile: j['lyric'] as String? ?? '',
        sizeBytes: j['size'] as int? ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
      );
}

/// 没下完的任务（排队中 / 暂停 / 中断）。持久化后下次启动还在，半截文件按 [part] 续传。
class _Task {
  _Task(this.song, {this.reason, this.received = 0, this.total = 0});
  final Song song;
  String? reason; // 暂停原因（null = 用户手动暂停 / 排队中）
  int received, total; // 已写入 .part 的字节 / 文件总大小（未知为 0）
}

class DownloadStore extends ChangeNotifier {
  DownloadStore(this._app, this._prefs);

  final AppState _app;
  final KvStore? _prefs;
  static const _kDownloads = 'downloads.v1';
  static const _kTasks = 'downloads.tasks.v1';

  List<DownloadItem> items = []; // 已完成（持久化）
  final waiting = <Song>[]; // 排队中
  final progress = <String, double>{}; // 进行中 key → 0..1
  final running = <String>{}; // 正在下载的 key
  final _paused = <String, _Task>{}; // 暂停 / 中断的任务（按加入顺序）
  final _tasks = <String, _Task>{}; // 所有没下完的任务：key → 进度
  final _clients = <String, http.Client>{}; // 正在下载的连接（暂停 = 关掉它）
  final _stop = <String, String>{}; // 请求停下的任务：'pause' / 'cancel'
  String? dir;
  bool _ready = false;

  List<Song> get waitingSongs => List.unmodifiable(waiting);
  List<Song> get pausedSongs => [for (final t in _paused.values) t.song];

  Song? songByKey(String key) => _tasks[key]?.song ?? songs.where((s) => _keyOf(s) == key).firstOrNull;

  void removeWaiting(Song w) {
    final k = _keyOf(w);
    waiting.remove(w);
    if (k != null) _drop(k);
    notifyListeners();
    _pump();
  }

  /// 按 LibraryStore 的 track key 查本地文件路径（resolver 离线优先用）。
  String? pathOf(String key) {
    final hit = items.where((e) => e.key == key).firstOrNull;
    if (hit == null) return null;
    return io.File(hit.file).existsSync() ? hit.file : null;
  }

  bool isDownloaded(String key) => pathOf(key) != null;
  bool isBusy(String key) => running.contains(key);
  bool isPaused(String key) => _paused.containsKey(key);
  String? pausedReason(String key) => _paused[key]?.reason;

  /// 0..1；暂停的任务给已下载的比例。
  double progressOf(String key) {
    final p = progress[key];
    if (p != null) return p;
    final t = _tasks[key];
    return t == null || t.total <= 0 ? 0 : (t.received / t.total).clamp(0.0, 1.0);
  }

  /// 已下载 / 总大小（字节），界面显示「3.2 / 9.8 MB」。
  (int, int) bytesOf(String key) => (_tasks[key]?.received ?? 0, _tasks[key]?.total ?? 0);

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      dir = '${docs.path}${io.Platform.pathSeparator}lyra-downloads';
      await io.Directory(dir!).create(recursive: true);
    } catch (_) {
      return; // 拿不到目录（少见）：下载入口处会提示
    }
    final raw = await _prefs?.read(_kDownloads);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        items = [for (final j in list) DownloadItem.fromJson(j)].where((it) => io.File(it.file).existsSync()).toList();
      } catch (_) {}
    }
    await _restoreTasks();
  }

  Future<void> _persist() async {
    final raw = jsonEncode([for (final it in items) it.toJson()]);
    await _prefs?.write(_kDownloads, raw);
  }

  // ---------------------------------------------------------------- 未完成任务的持久化

  Timer? _saveT;
  void _saveTasks() {
    final prefs = _prefs;
    if (prefs == null) return;
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 800), () {
      final out = <Map<String, dynamic>>[];
      for (final e in _tasks.entries) {
        final t = _app.library.trackOf(e.value.song.id);
        if (t == null) continue;
        out.add({'track': t.toDesktop(), 'received': e.value.received, 'total': e.value.total, if (e.value.reason != null) 'reason': e.value.reason});
      }
      unawaited(prefs.write(_kTasks, jsonEncode(out)));
    });
  }

  /// 上次没下完的任务：全部恢复成「暂停」，不在启动时偷偷开始下（省流量，也等音源就绪）。
  Future<void> _restoreTasks() async {
    final raw = await _prefs?.read(_kTasks);
    if (raw == null || raw.isEmpty) return;
    try {
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final track = CloudTrack.fromDesktop(Map<String, dynamic>.from(j['track'] as Map));
        if (isDownloaded(track.id)) continue;
        final id = _app.library.register(track);
        final song = songs[id];
        final t = _Task(song, reason: j['reason'] as String? ?? '上次退出时没下完', received: j['received'] as int? ?? 0, total: j['total'] as int? ?? 0);
        // 半截文件被清掉了：从头下
        if (!io.File(_partPath(song, track.id)).existsSync()) t.received = 0;
        _tasks[track.id] = t;
        _paused[track.id] = t;
      }
    } catch (_) {}
    if (_tasks.isNotEmpty) notifyListeners();
  }

  // ---------------------------------------------------------------- 队列

  /// 加入下载队列（去重：已下载 / 排队中 / 进行中的跳过；暂停中的直接继续）。错误经 notice 上报。
  Future<void> enqueue(Song song) async {
    final key = _keyOf(song);
    if (key == null) {
      _app.notice?.call('「${song.title}」缺少平台信息，无法下载', 'info');
      return;
    }
    if (isDownloaded(key)) {
      _app.notice?.call('「${song.title}」已经下载过了', 'info');
      return;
    }
    if (isPaused(key)) return resume(key);
    if (running.contains(key) || waiting.any((w) => _keyOf(w) == key)) {
      _app.notice?.call('「${song.title}」已在下载队列中', 'info');
      return;
    }
    waiting.add(song);
    _tasks[key] ??= _Task(song);
    _saveTasks();
    notifyListeners();
    _pump();
  }

  Future<void> enqueueAll(Iterable<Song> songs) async {
    for (final s in songs) {
      await enqueue(s);
    }
  }

  /// 暂停：下载中的断开连接（已下的部分留着续传），排队中的挪到暂停区。
  void pause(String key) {
    if (running.contains(key)) {
      _stop[key] = 'pause';
      _clients[key]?.close();
      return;
    }
    final w = waiting.where((s) => _keyOf(s) == key).firstOrNull;
    if (w == null) return;
    waiting.remove(w);
    final t = _tasks[key] ??= _Task(w);
    t.reason = null;
    _paused[key] = t;
    _saveTasks();
    notifyListeners();
  }

  /// 继续：放回队首，空位到了就从断点接着下（Range 请求）。
  Future<void> resume(String key) async {
    final t = _paused.remove(key);
    if (t == null) return;
    if (_app.set.wifiOnly && await currentNetwork() != NetKind.unmetered) {
      t.reason = '等待 Wi-Fi（设置里开了「仅 Wi-Fi 下载」）';
      _paused[key] = t;
      notifyListeners();
      _app.notice?.call('当前不是 Wi-Fi，「${t.song.title}」先不下载', 'info');
      return;
    }
    t.reason = null;
    waiting.insert(0, t.song);
    _saveTasks();
    notifyListeners();
    _pump();
  }

  void pauseAll() {
    for (final k in [...running, for (final s in waiting) _keyOf(s) ?? '']) {
      if (k.isNotEmpty) pause(k);
    }
  }

  Future<void> resumeAll() async {
    for (final k in [..._paused.keys]) {
      await resume(k);
    }
  }

  /// 删除任务：停掉下载、删半截文件。
  void cancel(String key) {
    if (running.contains(key)) {
      _stop[key] = 'cancel';
      _clients[key]?.close();
      return;
    }
    waiting.removeWhere((s) => _keyOf(s) == key);
    _paused.remove(key);
    _drop(key);
    notifyListeners();
  }

  void _drop(String key) {
    final t = _tasks.remove(key);
    if (t != null) _cleanup(_partPath(t.song, key));
    _saveTasks();
  }

  String? _keyOf(Song song) => _app.library.trackOf(song.id)?.id;

  /// 并发取任务：空位就填，直到排空或满载。dlConc 改小后不会立刻杀正在下的任务。
  void _pump() {
    while (running.length < _app.set.dlConc.round()) {
      Song? next;
      for (final s in waiting) {
        final k = _keyOf(s) ?? '';
        if (!running.contains(k)) {
          next = s;
          break;
        }
      }
      if (next == null) break;
      waiting.remove(next);
      running.add(_keyOf(next) ?? '');
      unawaited(_download(next, _keyOf(next) ?? ''));
    }
    notifyListeners();
  }

  String _baseOf(Song song, String key) => '${dir!}${io.Platform.pathSeparator}${_safeName('${song.title} - ${song.artist}')}_${key.hashCode.abs()}';
  String _partPath(Song song, String key) => dir == null ? '' : '${_baseOf(song, key)}.part';

  /// 暂停（或失败）后留下的任务：进度保留，放进暂停区。
  void _park(String key, Song song, String? reason) {
    final t = _tasks[key] ??= _Task(song);
    t.reason = reason;
    _paused[key] = t;
    _saveTasks();
  }

  Future<void> _download(Song song, String key) async {
    if (dir == null) {
      running.remove(key);
      _app.notice?.call('存储目录不可用，无法下载', 'info');
      _pump();
      return;
    }
    final task = _tasks[key] ??= _Task(song);
    if (_app.set.wifiOnly && await currentNetwork() != NetKind.unmetered) {
      running.remove(key);
      _park(key, song, '等待 Wi-Fi（设置里开了「仅 Wi-Fi 下载」）');
      _app.notice?.call('「${song.title}」先暂停：当前不是 Wi-Fi', 'info');
      _pump();
      return;
    }
    progress[key] = progressOf(key);
    notifyListeners();

    final client = http.Client();
    _clients[key] = client;
    final base = _baseOf(song, key);
    final part = '$base.part';
    io.IOSink? sink;
    var done = false;
    try {
      // 直链有时效：每次（包括续传）都重新取地址
      final rp = await _app.resolver?.resolve(song);
      if (rp == null) throw const DownloadException('拿不到可下载的音频地址');
      final uri = rp.uri;
      if (!uri.isScheme('http') && !uri.isScheme('https')) throw const DownloadException('音频地址不可下载');
      final quality = _app.resolver?.last?.quality;

      final partFile = io.File(part);
      var have = partFile.existsSync() ? partFile.lengthSync() : 0;
      Future<http.StreamedResponse> get(int from) {
        final req = http.Request('GET', uri)
          ..followRedirects = true
          ..headers.addAll(rp.headers) // 直链可能要求 Referer（酷我 / 咪咕），不带会 403
          ..headers.addAll({if (from > 0) 'Range': 'bytes=$from-'});
        return client.send(req).timeout(const Duration(seconds: 20));
      }

      var res = await get(have);
      if (res.statusCode == 416 && have > 0) {
        // 断点超出了新地址的文件大小（换了音质 / 音源）：从头下
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        have = 0;
        res = await get(0);
      }
      final ranged = res.statusCode == 206 && have > 0;
      if (res.statusCode != 200 && res.statusCode != 206) throw DownloadException('下载地址返回 ${res.statusCode}');
      if (!ranged) have = 0; // 服务器不支持断点：只能从头来
      final total = parseTotalBytes(res.headers['content-range'], res.contentLength, have);
      // 续传前后是不是同一个文件：总大小对不上就从头下（换了音质 / 音源）
      if (ranged && task.total > 0 && total > 0 && total != task.total) {
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        have = 0;
        res = await get(0);
        if (res.statusCode != 200) throw DownloadException('下载地址返回 ${res.statusCode}');
      }
      task
        ..total = have > 0 ? total : parseTotalBytes(res.headers['content-range'], res.contentLength, 0)
        ..received = have;
      if (have > 0) AppLog.instance.add('下载', '「${song.title}」从 ${(have / 1048576).toStringAsFixed(1)} MB 处续传');
      // 扩展名按响应类型 / 地址判断（m4a 也常见）
      final type = '${res.headers['content-type'] ?? ''} ${uri.path}'.toLowerCase();
      final ext = type.contains('flac') ? '.flac' : (type.contains('mp4') || type.contains('m4a') || type.contains('aac')) ? '.m4a' : '.mp3';
      sink = partFile.openWrite(mode: have > 0 ? io.FileMode.append : io.FileMode.write);
      var lastSave = DateTime.now();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        task.received += chunk.length;
        if (task.total > 0) {
          final p = task.received / task.total;
          if ((p - (progress[key] ?? 0)) > 0.01) {
            progress[key] = p;
            notifyListeners();
          }
        }
        if (DateTime.now().difference(lastSave) > const Duration(seconds: 3)) {
          lastSave = DateTime.now();
          _saveTasks(); // 进程被杀也能从差不多的位置接着下
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (task.total > 0 && task.received < task.total) throw DownloadException('连接提前断开（${task.received}/${task.total}）');
      final audioFile = '$base$ext';
      await partFile.rename(audioFile);
      progress.remove(key);

      final tr0 = _app.library.trackOf(song.id);
      final coverFile = _app.set.dlCover ? await _fetchCover(tr0, '$base-cover.jpg') : '';
      final lyricFile = _app.set.dlLyric ? await _fetchLyric(tr0, '$base.lrc') : '';
      final tr = _app.library.trackOf(song.id);

      items.insert(
          0,
          DownloadItem(
            key: key,
            title: song.title,
            artist: song.artist,
            platform: tr?.platform ?? '',
            quality: quality == null ? _app.set.onlineQ : appQualityOf(quality),
            file: audioFile,
            sizeBytes: task.received,
            at: DateTime.now(),
            coverFile: coverFile,
            lyricFile: lyricFile,
          ));
      await _persist();
      done = true;
      _tasks.remove(key);
      _saveTasks();
      _app.notice?.call('「${song.title}」下载完成', 'download');
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      progress.remove(key);
      final stop = _stop.remove(key);
      if (stop == 'cancel') {
        _drop(key);
      } else if (stop == 'pause') {
        _park(key, song, null);
      } else if (!done) {
        // 失败不再删半截文件：放进暂停区，点「继续」从断点接着下
        final why = e is DownloadException ? e.message : (e is TimeoutException ? '连接超时' : '网络中断');
        _park(key, song, '下载中断：$why');
        AppLog.instance.add('下载', '「${song.title}」中断：$e');
        _app.notice?.call('「${song.title}」下载中断（$why），已暂停，点继续可接着下', 'info');
      }
    } finally {
      _stop.remove(key);
      _clients.remove(key);
      client.close();
      running.remove(key);
      notifyListeners();
      _pump();
    }
  }

  Future<void> remove(DownloadItem item) async {
    items.removeWhere((e) => e.key == item.key);
    await _persist();
    _cleanup(item.file);
    if (item.coverFile.isNotEmpty) _cleanup(item.coverFile);
    if (item.lyricFile.isNotEmpty) _cleanup(item.lyricFile);
    notifyListeners();
  }

  Future<void> clear() async {
    for (final it in items) {
      _cleanup(it.file);
      if (it.coverFile.isNotEmpty) _cleanup(it.coverFile);
      if (it.lyricFile.isNotEmpty) _cleanup(it.lyricFile);
    }
    items = [];
    await _persist();
    notifyListeners();
  }

  void _cleanup(String path) {
    try {
      final f = io.File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _fetchCover(CloudTrack? t, String path) async {
    final url = t?.cover;
    if (url == null || url.isEmpty) return '';
    try {
      // 网易 / QQ 图床按 UA 拦截，Dart 默认 UA 一律 403（和封面加载同一个坑）
      final res = await http.get(Uri.parse(coverUrl(url) ?? url), headers: const {'User-Agent': Cover.ua}).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.length > 1024) {
        await io.File(path).writeAsBytes(res.bodyBytes);
        return path;
      }
    } catch (_) {}
    return '';
  }

  Future<String> _fetchLyric(CloudTrack? t, String path) async {
    if (t == null) return '';
    final identity = t.raw['identity'] is Map ? Map<String, dynamic>.from(t.raw['identity'] as Map) : <String, dynamic>{};
    final ptrack = PTrack(platform: t.platform, nativeId: t.songId, title: t.title, artist: t.artist, album: t.album, duration: t.durationSec, cover: t.cover, identity: identity);
    try {
      final l = await _app.content.lyric(ptrack).timeout(const Duration(seconds: 10));
      final lines = parseLrc(l.lrc);
      if (lines.isEmpty) return '';
      await io.File(path).writeAsString(lines.map((x) => '[${_lrcTime(x.time)}]${x.text}').join('\n'));
      return path;
    } catch (_) {
      return '';
    }
  }

  static String _lrcTime(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60, sec = s % 60, cs = (ms % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  static String _safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

/// 文件总大小：206 响应看 Content-Range 的「/总数」，否则 = 已有 + 本次长度；都不知道返回 0。
int parseTotalBytes(String? contentRange, int? contentLength, int have) {
  final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange ?? '');
  if (m != null) return int.parse(m[1]!);
  if (contentLength == null || contentLength <= 0) return 0;
  return have + contentLength;
}

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override
  String toString() => message;
}
