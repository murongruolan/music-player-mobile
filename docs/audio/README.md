# 音频播放链路

> 负责人边界：本目录（lib/audio/）+ 播放相关的 state.dart 段落 = 播放链路（本地 agent）；
> mock 内容、平台账号、音源脚本 = 另一条线（Kiro）。两边在 `TrackResolver` 接口汇合。

## 结构

```
lib/audio/
  audio_engine.dart    引擎：just_audio 封装 + 音频焦点 + EQ 下发 + 通知刷新
  media_handler.dart   audio_service MediaSession：通知栏卡片与按钮（含自定义收藏）
  track_resolver.dart  「曲目 → 可播 URI」接口；DemoTrackResolver 为测试桩
  equalizer.dart       UI 10 段曲线 → 设备实际波段的映射（纯逻辑）
  formats.dart         格式支持矩阵与识别（纯逻辑）
```

数据流：

```
UI（播放器/迷你条/SongRow）
   │  context.app.play(id) / toggle() / seek()
   ▼
AppState（队列与播放态仍是唯一事实源）
   │  playSong(song)                    ▲ position / duration / playing / completed 回调
   ▼                                    │
AudioEngine ── TrackResolver.resolve ──► URI（现在：DemoTrackResolver 测试桩；
   │                                     将来：Kiro 的音源脚本运行时实现同一接口）
   ├─ just_audio（Media3 / AVPlayer）
   ├─ audio_session（音频焦点：来电、他 App 播放 → 自动暂停恢复）
   └─ LyraMediaHandler（audio_service）──► 系统媒体通知（含收藏按钮）
```

- 引擎模式下 `AppState.pos / playing / engineDuration` 全部由引擎回调驱动；
  `_tick()` 模拟时钟只保留给截图模式（engine == null），同时继续喂听歌统计。
- `AppState.song` 在真实播放时用引擎返回的实际时长替换 mock 时长
  （`Song.copyWith(dur:)`），全 UI 的进度换算自动对齐，无需逐处修改。
- 通知栏动作（play/pause/next/prev/like）经 `onMediaAction` 路由回 AppState，
  收藏直接复用 `toggleLike`，UI 与通知栏两处状态天然一致。

## 依赖说明（为什么加第三方包）

Flutter SDK 没有任何媒体播放能力（只能录音/短音效）。`just_audio` 与
`audio_service` 是平台播放器（Android Media3/ExoPlayer、iOS AVPlayer）的标准封装，
即 Flutter 生态里的「SDK 路线」；`audio_session` 处理音频焦点，是官方推荐的配套包。
三者均为纯 platform-channel 封装，无原生魔改。

## 格式支持

| 格式 | 支持 | 说明 |
|---|---|---|
| MP3 / AAC / M4A | ✅ | 平台原生 |
| FLAC（16/24bit，Hi-Res） | ✅ | 平台原生 |
| WAV / OGG / Opus | ✅ | 平台原生 |
| APE / TTA / TAK / DSF | ❌ | 需 FFmpeg 扩展（本地编译成本高），音源脚本侧转码后再交给引擎；`formats.dart` 会明确报「暂不支持」而不是静默失败 |
| 杜比 / 全景声 | 视设备 | 解码能力跟随设备芯片 |

## 均衡器

- UI 固定 10 段（31Hz..16kHz，±12dB）；Android Equalizer 的实际段数由设备决定
  （常见 5-6 段）。`equalizer.dart` 把 10 点曲线在对数频域插值到设备波段。
- 仅 Android 生效。iOS 需自建 AVAudioEngine 链路（just_audio 不提供），后续评估；
  Web 无系统 EQ。
- 预设/开关/拖动的三个交互点都会调用 `AppState.applyEqToEngine()`。

## 与 Kiro 线的汇合点

`TrackResolver`（lib/audio/track_resolver.dart）是唯一接口。音源脚本运行时就绪后：
实现该接口（从脚本沙箱拿到直链 + 格式），main.dart 里把 `DemoTrackResolver` 换掉即可，
引擎、通知、EQ 全都不用动。`DemoTrackResolver` 当前使用公开测试音频
（soundhelix.com 示例 MP3），按曲目 id 确定性映射，仅用于联调，不含任何密钥。

## 已知限制

- 通知栏封面：mock 曲目无真实封面，显示 App 图标；接真实封面后在 MediaItem.artUri 补。
- 歌词时间轴仍是 mock 的（等音源/歌词链路），真实曲目下歌词进度仅供演示。
- iOS 均衡器、APE 系冷格式：见上。
