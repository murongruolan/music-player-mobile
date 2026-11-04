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

class DownloadStore extends ChangeNotifier {
  DownloadStore(this._app, this._prefs);

  final AppState _app;
  final KvStore? _prefs;
  static const _kDownloads = 'downloads.v1';

  List<DownloadItem> items = []; // 已完成（持久化）
  final waiting = <Song>[]; // 排队中
  final progress = <String, double>{}; // 进行中 key → 0..1
  final running = <String>{}; // 正在下载的 key
  String? dir;
  bool _ready = false;

  List<Song> get waitingSongs => List.unmodifiable(waiting);

  Song? songByKey(String key) => songs.where((s) => _keyOf(s) == key).firstOrNull;

  void removeWaiting(Song w) {
    waiting.remove(w);
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
  double progressOf(String key) => progress[key] ?? 0;

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
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      items = [for (final j in list) DownloadItem.fromJson(j)].where((it) => io.File(it.file).existsSync()).toList();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final raw = jsonEncode([for (final it in items) it.toJson()]);
    await _prefs?.write(_kDownloads, raw);
  }

  /// 加入下载队列（去重：已下载 / 排队中 / 进行中的跳过）。错误经 notice 上报。
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
    if (running.contains(key) || waiting.any((w) => _keyOf(w) == key)) {
      _app.notice?.call('「${song.title}」已在下载队列中', 'info');
      return;
    }
    waiting.add(song);
    notifyListeners();
    _pump();
  }

  Future<void> enqueueAll(Iterable<Song> songs) async {
    for (final s in songs) {
      await enqueue(s);
    }
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

  Future<void> _download(Song song, String key) async {
    if (dir == null) {
      running.remove(key);
      _app.notice?.call('存储目录不可用，无法下载', 'info');
      _pump();
      return;
    }
    if (_app.set.wifiOnly && await currentNetwork() != NetKind.unmetered) {
      running.remove(key);
      _app.notice?.call('「${song.title}」没有下载：当前不是 Wi-Fi（设置里开了「仅 Wi-Fi 下载」）', 'info');
      _pump();
      return;
    }
    progress[key] = 0;
    notifyListeners();

    final client = http.Client();
    String? audioFile;
    try {
      // 取链失败（ResolveException）也要走 finally，否则任务会一直卡在「下载中」
      final rp = await _app.resolver?.resolve(song);
      if (rp == null) throw const DownloadException('拿不到可下载的音频地址');
      final uri = rp.uri;
      if (!uri.isScheme('http') && !uri.isScheme('https')) throw const DownloadException('音频地址不可下载');

      final quality = _app.resolver?.last?.quality;
      final base = '${dir!}${io.Platform.pathSeparator}${_safeName('${song.title} - ${song.artist}')}_${key.hashCode.abs()}';
      final req = http.Request('GET', uri)
        ..followRedirects = true
        ..headers.addAll(rp.headers); // 直链可能要求 Referer（酷我 / 咪咕），不带会 403
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw DownloadException('下载地址返回 ${res.statusCode}');
      // 扩展名按响应类型 / 地址判断（m4a 也常见）
      final type = '${res.headers['content-type'] ?? ''} ${uri.path}'.toLowerCase();
      final ext = type.contains('flac') ? '.flac' : (type.contains('mp4') || type.contains('m4a') || type.contains('aac')) ? '.m4a' : '.mp3';
      audioFile = '$base$ext';
      final total = res.contentLength ?? 0;
      final sink = io.File(audioFile).openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          final p = received / total;
          if ((p - (progress[key] ?? 0)) > 0.01) {
            progress[key] = p;
            notifyListeners();
          }
        }
      }
      await sink.flush();
      await sink.close();
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
            sizeBytes: received,
            at: DateTime.now(),
            coverFile: coverFile,
            lyricFile: lyricFile,
          ));
      await _persist();
      _app.notice?.call('「${song.title}」下载完成', 'download');
      audioFile = null; // 成功：不清理
    } on DownloadException catch (e) {
      progress.remove(key);
      _app.notice?.call('「${song.title}」$e', 'info');
    } catch (e) {
      progress.remove(key);
      _app.notice?.call('「${song.title}」下载失败：$e', 'info');
    } finally {
      client.close();
      if (audioFile != null) _cleanup(audioFile); // 失败留下的半截文件
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
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override
  String toString() => message;
}
