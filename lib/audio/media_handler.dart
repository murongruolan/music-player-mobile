// 通知栏媒体通知（audio_service / MediaSession）。
//
// 提供：播放/暂停、上一首/下一首、拖动进度，以及自定义「收藏」按钮
// （图标随收藏状态切换，点击走 [onAction]('like') 由 AppState 处理）。
// 后台播放、锁屏控制、蓝牙/耳机线控都由 MediaSession 统一承接。

import 'package:audio_service/audio_service.dart';

import '../data/models.dart';

class LyraMediaHandler extends BaseAudioHandler {
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
  }) async {
    mediaItem.add(MediaItem(
      id: 'lyra-song-${song.id}',
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: duration,
      // 封面：真实歌曲带平台封面地址；mock 曲目没有，缺省显示 App 图标
      artUri: song.cover == null ? null : Uri.tryParse(song.cover!.replaceFirst(RegExp(r'^http://(?=[^/]*(126\.net|gtimg\.cn|qq\.com|qpic\.cn))'), 'https://')),
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
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: playbackState.value.speed,
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

  /// 清空通知（卸载音源 / 退出登录）。
  void clearNowPlaying() {
    mediaItem.add(null);
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
  }
}
