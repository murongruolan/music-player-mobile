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
      // 封面：mock 曲目没有真实封面，缺省显示 App 图标；接入真实封面后补 artUri。
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

  /// 清空通知（卸载音源 / 退出登录）。
  void clearNowPlaying() {
    mediaItem.add(null);
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
  }
}
