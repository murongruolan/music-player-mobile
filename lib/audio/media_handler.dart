// 通知栏媒体通知（audio_service / MediaSession）。
//
// 提供：播放/暂停、上一首/下一首、拖动进度，以及自定义「收藏」按钮
// （图标随收藏状态切换，点击走 [onAction]('like') 由 AppState 处理）。
// 后台播放、锁屏控制、蓝牙/耳机线控都由 MediaSession 统一承接。

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 封面图床（网易 / QQ）按 UA 拦截默认 UA，下载封面要带浏览器 UA（和 App 内封面一致）。
const _coverUa = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

class LyraMediaHandler extends BaseAudioHandler {
  // —— iOS 锁屏 / 控制中心 / 灵动岛的封面 ——
  // audio_service 在 iOS 上用自带的下载器（默认 UA）取网络封面，被网易 / QQ 图床拒掉，所以一直没有封面。
  // 这里自己带 UA 下载到临时目录，交给它本地文件地址（file://），它会直接读文件。
  final _artFiles = <String, String>{};
  final _artLoading = <String>{};

  static String _artKey(String url) => url.hashCode.toUnsigned(32).toRadixString(16);

  Future<void> _fetchArt(String url, String mediaId) async {
    if (_artLoading.contains(url)) return;
    _artLoading.add(url);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/np-art-${_artKey(url)}.jpg');
      if (!await f.exists() || await f.length() < 1024) {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.userAgentHeader, _coverUa);
        final res = await req.close().timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) return;
        final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        if (bytes.length < 1024) return;
        await f.writeAsBytes(bytes, flush: true);
      }
      _artFiles[url] = f.path;
      if (_artFiles.length > 40) _artFiles.remove(_artFiles.keys.first);
      // 还是这首：补上封面
      final m = mediaItem.value;
      if (m != null && m.id == mediaId) mediaItem.add(m.copyWith(artUri: Uri.file(f.path)));
    } catch (_) {
      // 拿不到封面：锁屏显示 App 图标，不影响播放
    } finally {
      client.close(force: true);
      _artLoading.remove(url);
    }
  }

  /// 通知栏 / 线控动作统一路由给 AppState（'play' 'pause' 'next' 'prev' 'like'）。
  void Function(String action)? onAction;

  static const _channelId = 'app.lyra.mobile.playback';
  static const _channelName = '正在播放';

  @override
  Future<void> play() async => onAction?.call('play');

  @override
  Future<void> pause() async => onAction?.call('pause');

  @override
  Future<void> skipToNext() async => onAction?.call('next');

  @override
  Future<void> skipToPrevious() async => onAction?.call('prev');

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? arguments]) async {
    if (name == 'like') onAction?.call('like');
    return null;
  }

  /// 刷新「正在播放」卡片：媒体信息 + 控制按钮（收藏按钮图标随 [liked] 切换）。
  Future<void> setNowPlaying(
    Song song, {
    required bool playing,
    required bool liked,
    required Duration position,
    required Duration duration,
    bool loading = false,
    double? speed,
  }) async {
    final id = 'lyra-song-${song.id}';
    final cover = song.cover == null ? null : song.cover!.replaceFirst(RegExp(r'^http://(?=[^/]*(126\.net|gtimg\.cn|qq\.com|qpic\.cn))'), 'https://');
    Uri? art;
    if (cover != null) {
      if (_isIOS && cover.startsWith('http')) {
        final local = _artFiles[cover];
        if (local != null) {
          art = Uri.file(local);
        } else {
          // 同一首歌重复推送（暂停 / 收藏）时先沿用已有封面，不闪
          final prev = mediaItem.value;
          if (prev != null && prev.id == id) art = prev.artUri;
          unawaited(_fetchArt(cover, id));
        }
      } else {
        art = Uri.tryParse(cover);
      }
    }
    // 播放器还没给出时长（刚加载 / 投放中）时用歌曲自带时长：iOS 进度条和剩余时间才有刻度
    final dur = duration > Duration.zero ? duration : Duration(seconds: song.dur > 0 ? song.dur : 0);
    mediaItem.add(MediaItem(
      id: id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: dur,
      // 封面：真实歌曲带平台封面地址；mock 曲目没有，缺省显示 App 图标
      artUri: art,
    ));

    final controls = <MediaControl>[
      MediaControl(androidIcon: 'drawable/ic_notif_prev', label: '上一首', action: MediaAction.skipToPrevious),
      playing
          ? MediaControl(androidIcon: 'drawable/ic_notif_pause', label: '暂停', action: MediaAction.pause)
          : MediaControl(androidIcon: 'drawable/ic_notif_play', label: '播放', action: MediaAction.play),
      MediaControl(androidIcon: 'drawable/ic_notif_next', label: '下一首', action: MediaAction.skipToNext),
      // 自定义「收藏」按钮：图标随收藏态切换，点击走 customAction('like') → AppState.toggleLike
      MediaControl.custom(
        androidIcon: liked ? 'drawable/ic_notif_liked' : 'drawable/ic_notif_like',
        label: '收藏',
        name: 'like',
      ),
    ];

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {MediaAction.seek},
      // 加载中（切歌后还没拿到地址 / 缓冲）：卡片先换成新歌，状态标成 loading
      processingState: loading ? AudioProcessingState.loading : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      // iOS 用 位置 + 速度 + 更新时间 自己推算锁屏进度：倍速播放时要报真实速度，否则进度条走得不对
      speed: speed ?? playbackState.value.speed,
    ));
  }

  /// 通知栏 / 锁屏 / 蓝牙拖动进度条。
  void Function(Duration position)? onSeekTo;

  @override
  Future<void> seek(Duration position) async => onSeekTo?.call(position);

  /// 蓝牙歌词推送：只改媒体信息里的标题 / 副标题（车机、蓝牙耳机、锁屏显示的就是这两行）。
  void setMediaText(String title, String artist) {
    final m = mediaItem.value;
    if (m == null || (m.title == title && m.artist == artist)) return;
    mediaItem.add(m.copyWith(title: title, artist: artist));
  }

  /// 投放到 DLNA 设备时，手机音量键改的是渲染端音量（0..100）。
  void Function(int volume)? onRemoteVolume;
  void Function(int direction)? onRemoteAdjust;

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async => onRemoteVolume?.call(volumeIndex);

  @override
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) async {
    final d = direction == AndroidVolumeDirection.raise ? 1 : (direction == AndroidVolumeDirection.lower ? -1 : 0);
    if (d != 0) onRemoteAdjust?.call(d);
  }

  /// [volume] 非空：媒体会话切成远程播放（音量键 / 系统音量条控制渲染端）；null：回到本机音量。
  void setRemoteVolume(int? volume) {
    // 远程音量（音量键调渲染端）是 Android MediaSession 的能力，iOS 上不发
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final info = volume == null
        ? LocalAndroidPlaybackInfo()
        : RemoteAndroidPlaybackInfo(volumeControlType: AndroidVolumeControlType.absolute, maxVolume: 100, volume: volume.clamp(0, 100));
    if (androidPlaybackInfo.valueOrNull == info) return;
    androidPlaybackInfo.add(info);
  }

  /// 清空通知（卸载音源 / 退出登录）。
  void clearNowPlaying() {
    mediaItem.add(null);
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
  }
}
