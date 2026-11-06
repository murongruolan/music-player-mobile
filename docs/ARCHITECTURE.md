# Lyra Mobile 架构文档

> 本文档描述 Lyra Mobile 的整体架构、核心模块及其交互关系

## 目录

- [技术栈](#技术栈)
- [整体架构](#整体架构)
- [核心模块](#核心模块)
- [数据流](#数据流)
- [外部依赖](#外部依赖)

## 技术栈

- **框架**: Flutter 3.24+ / Dart 3.5+
- **状态管理**: Provider + ChangeNotifier
- **音频引擎**: just_audio + audio_service
- **本地存储**: shared_preferences
- **网络**: Dio
- **iOS 扩展**: App Groups + Live Activities + PiP

## 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                             │
│  (Screens, Widgets, Skins, Animations)                      │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────┐
│                     State Management                         │
│  AppState (Provider) - 全局状态管理                          │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────┐
│                      Core Services                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ AudioEngine  │  │ LyricEngine  │  │ MusicService │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────┴───────────────────────────────┐
│                    Platform Services                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ iOS Native   │  │ Android      │  │ File System  │      │
│  │ (Live        │  │ Services     │  │ & Storage    │      │
│  │  Activities) │  │              │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## 核心模块

### 1. AppState (`lib/appstate.dart`)

**职责**: 全局状态管理中心

**核心字段**:
- `currentSongid`: 当前播放歌曲 ID
- `isPlaying`: 播放状态
- `songPosition` / `songDuration`: 播放进度
- `currentPlaylist`: 当前播放列表
- `homeAnnouncement`: 首页公告
- `downloadProgress`: 下载进度映射
- `liveActivityId`: iOS 灵动岛 ID

**核心方法**:
- `switchSkin()`: 切换播放皮肤
- `setUserPlayingStatus()`: 用户主动播放/暂停（触发 iOS 实时活动）
- `notifyDownloadProgress()`: 更新下载进度
- `seekTo()`: 跳转播放位置

**特点**:
- 继承 `ChangeNotifier`，通过 `notifyListeners()` 通知 UI 更新
- 使用 `Provider` 注入到 Widget 树顶层
- 所有状态变更都通过 AppState 方法，保证数据一致性

### 2. AudioEngine (`lib/audio/audio_engine.dart`)

**职责**: 音频播放核心引擎

**依赖**:
- `just_audio`: 音频播放器
- `audio_service`: 后台播放服务

**核心功能**:
- 音频加载（URL / 本地文件）
- 播放控制（播放、暂停、停止、跳转）
- 播放模式（顺序、随机、单曲循环）
- 后台播放和锁屏控制
- 进度监听（StreamSubscription）

**音源脚本集成**:
```dart
// 通过音源脚本获取播放 URL
final playUrl = await SourceManager.runScriptFunction(
  scriptPath, 
  'getPlayUrl', 
  [songid]
);
player.setUrl(playUrl);
```

**状态同步**:
- 监听 `player.positionStream` → 更新 AppState.songPosition
- 监听 `player.durationStream` → 更新 AppState.songDuration
- 监听 `player.playerStateStream` → 处理播放完成、错误等事件

### 3. LyricEngine (`lib/lyrics/lyric_engine.dart`)

**职责**: 歌词解析、匹配、渲染

**支持格式**:
- LRC (标准逐行歌词)
- YRCX (QQ 音乐逐字歌词)
- Apple Music 风格分段歌词

**核心功能**:
- 解析歌词文件（时间戳 + 文本）
- 根据播放进度匹配当前行/字
- 提供歌词数据给不同皮肤渲染

**数据结构**:
```dart
class LyricLine {
  final double startTime;
  final String text;
  final List<WordTiming>? words; // 逐字时间戳
}
```

**Apple Music 分段逻辑**:
- 将歌词按语义分段（chunk）
- 计算每段显示时长
- 支持点击跳转

### 4. MusicService (`lib/services/music_service.dart`)

**职责**: 后端 API 交互

**核心接口**:
- `fetchSongDetail(songid)`: 获取歌曲详情
- `fetchLyric(songid)`: 获取歌词
- `fetchPlaylist(playlistId)`: 获取歌单
- `search(keyword)`: 搜索歌曲
- `getUserLibrary()`: 获取用户收藏

**网络层**:
- 使用 Dio 进行 HTTP 请求
- 支持重试和错误处理
- 基于 `music-player-server` 后端

### 5. 音源脚本系统 (`lib/source_scripts/`)

**职责**: 动态加载外部音源

**原理**:
- 使用 Flutter `compute` 在 Isolate 中执行 JS/Lua 脚本
- 脚本提供函数：`search()`, `getPlayUrl()`, `getLyric()` 等
- 隔离沙箱，防止脚本阻塞主线程

**文件结构**:
```
source_scripts/
  ├── qq_music.js
  ├── netease.js
  └── kugou.js
```

**调用示例**:
```dart
final result = await SourceManager.runScriptFunction(
  'qq_music.js',
  'search',
  ['告白气球']
);
```

### 6. 播放皮肤系统 (`lib/player/skins.dart`)

**职责**: 播放界面多皮肤支持

**已实现皮肤**:
- **默认皮肤** (`DefaultSkin`): 经典唱片封面 + 进度条
- **Spring 皮肤** (`SpringSkin`): 歌词居中 + 毛玻璃背景
- **Apple Music 皮肤** (`AppleMusicLyric`): 分段歌词 + 点击跳转

**皮肤接口**:
```dart
abstract class PlayerSkin extends StatefulWidget {
  final SongDetail song;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  // ...
}
```

**切换皮肤**:
```dart
appState.switchSkin('apple_music');
```

### 7. iOS 扩展

#### 7.1 灵动岛/锁屏歌词 (`ios/LyraLiveActivity/`)

**技术**: Live Activities + ActivityKit

**功能**:
- 实时显示当前播放歌曲
- 锁屏显示歌词
- 灵动岛动态更新

**通信**: App Groups (`group.com.lyra.shared`)

**更新频率**: 每秒更新一次进度和歌词

#### 7.2 画中画 (`ios/LyraPiP/`)

**技术**: Picture-in-Picture Extension

**功能**:
- 小窗显示歌词
- 支持歌词染色（根据封面主色）
- 可拖动调整位置

### 8. 下载系统 (`lib/library/download/`)

**新架构** (v2, #72-76):
- **UI**: `downloads_screen.dart` - 下载列表界面
- **逻辑**: `download_manager.dart` - 下载任务管理
- **存储**: `download_storage.dart` - 本地文件管理

**功能**:
- 后台下载（Flutter Downloader）
- 进度显示（百分比 + 文件大小）
- 暂停/恢复/取消
- 错误重试
- 下载完成通知

**状态管理**:
```dart
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}
```

### 9. 投屏系统 (`lib/cast/`)

**支持协议**:
- **DLNA** (`dlna_service.dart`)
- **Chromecast** (`chromecast_service.dart`)

**功能**:
- 设备发现
- 音频推流
- 播放控制同步
- 日志记录（`cast_logger.dart`，#75）

## 数据流

### 播放流程

```
用户点击播放
    ↓
AppState.playSong(songid)
    ↓
AudioEngine.loadAndPlay(url)
    ↓
just_audio 开始播放
    ↓
positionStream 事件
    ↓
AppState.notifyListeners()
    ↓
UI 更新（进度条、歌词）
```

### 下载流程

```
用户点击下载按钮
    ↓
DownloadManager.startDownload(song)
    ↓
Flutter Downloader 开始下载
    ↓
下载进度回调
    ↓
AppState.notifyDownloadProgress()
    ↓
UI 更新进度条
    ↓
下载完成 → DownloadStorage.saveMetadata()
```

### iOS 实时活动流程

```
用户播放歌曲
    ↓
AppState.setUserPlayingStatus(true)
    ↓
调用 iOS Native Code (MethodChannel)
    ↓
ActivityKit.startActivity()
    ↓
显示在灵动岛/锁屏
    ↓
每秒更新歌词和进度 (Timer)
```

## 外部依赖

### 关键第三方库

| 库名 | 用途 | 版本 |
|------|------|------|
| `just_audio` | 音频播放器 | ^0.9.40 |
| `audio_service` | 后台播放服务 | ^0.18.15 |
| `provider` | 状态管理 | ^6.1.2 |
| `dio` | HTTP 客户端 | ^5.7.0 |
| `shared_preferences` | 本地存储 | ^2.3.2 |
| `flutter_downloader` | 文件下载 | ^1.11.8 |
| `cached_network_image` | 图片缓存 | ^3.4.1 |

### 后端服务

- **music-player-server**: Lyra 后端 API
  - 接口: `/api/song/:id`, `/api/playlist/:id`, `/api/search` 等
  - 部署: `https://api.lyra.music` (示例)

### 音源脚本

- 脚本存放在 `assets/source_scripts/`
- 运行时动态加载
- 支持热更新（无需重新发布 App）

## 目录结构

```
lib/
├── main.dart                  # 入口文件
├── appstate.dart              # 全局状态管理
├── screens/                   # 页面
│   ├── home/                  # 首页
│   ├── discover/              # 发现
│   ├── search/                # 搜索
│   ├── library/               # 我的音乐
│   │   └── download/          # 下载管理
│   └── player/                # 播放器
├── audio/                     # 音频引擎
│   └── audio_engine.dart
├── lyrics/                    # 歌词引擎
│   └── lyric_engine.dart
├── player/                    # 播放器皮肤
│   ├── skins.dart
│   └── apple_music_lyric.dart
├── services/                  # 服务层
│   ├── music_service.dart
│   └── auth_service.dart
├── source_scripts/            # 音源脚本管理
│   └── source_manager.dart
├── cast/                      # 投屏
│   ├── dlna_service.dart
│   └── cast_logger.dart
└── widgets/                   # 通用组件
    ├── song_tile.dart
    └── player_bottom_sheet.dart

ios/
├── Runner/                    # 主应用
├── LyraLiveActivity/          # 灵动岛扩展
└── LyraPiP/                   # 画中画扩展

android/
└── app/src/main/
    ├── AndroidManifest.xml
    └── kotlin/                # Android 原生代码
```

## 开发指南

### 添加新功能

1. **确定范围**: 是 UI、核心逻辑还是平台特性？
2. **更新 AppState**: 如果需要全局状态，先扩展 AppState
3. **创建 Widget**: 在 `lib/screens/` 或 `lib/widgets/` 下创建
4. **测试**: 使用模拟器/真机测试，确保 CI 通过
5. **文档**: 更新本文档和 `HANDOVER.md`

### 调试技巧

- **查看日志**: `flutter logs` 或 Android Studio / Xcode 控制台
- **热重载**: `r` (热重载) / `R` (热重启)
- **断点调试**: VS Code / Android Studio 断点
- **性能分析**: Flutter DevTools

### 发布流程

1. **本地测试**: `flutter test && flutter analyze`
2. **创建 PR**: 按照 `CONTRIBUTING.md` 规范
3. **CI 检查**: 等待 GitHub Actions 通过
4. **合并到 main**: Squash and merge
5. **打包 IPA/APK**: 在 Codemagic 上触发构建

## 常见问题

### Q: 为什么歌词不显示？

A: 检查：
1. 歌曲是否有歌词（调用 MusicService.fetchLyric）
2. LyricEngine 是否正确解析
3. 播放进度是否正常更新

### Q: iOS 灵动岛不更新？

A: 检查：
1. App Groups 配置是否正确
2. Live Activity 是否已启动
3. 查看 Xcode 控制台是否有错误

### Q: 下载失败怎么办？

A: 检查：
1. 网络权限（AndroidManifest.xml / Info.plist）
2. 存储权限
3. 查看 `download_manager.dart` 的错误日志

---

**最后更新**: 2024-11-06  
**维护者**: Lyra Team  
**反馈**: 在 GitHub Issues 中提出问题
