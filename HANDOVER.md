# Lyra 音乐播放器 - 开发交接文档

> 作者：小克（AI Agent）  
> 日期：2026-11-06  
> 适用版本：main 分支（截至 PR #76）

---

## 一、项目概况

### 1.1 项目介绍
**Lyra** 是一个跨平台的音乐播放器（Flutter 实现），支持 Android 和 iOS。

**核心特性**：
- **多音源脚本**：导入洛雪音乐音源脚本（网易云、QQ 音乐、酷狗等），本地执行解析播放地址
- **15 套播放器皮肤**：律动（Apple Music 风格）、待机、粒子、声波、唱片、磁带、胶片、像素、舞台、写真、霓虹、终端、杂志、表盘、极简
- **歌词引擎**：瀑布弹簧切行、逐字填充 + 辉光、距离模糊、点按跳转、手动拖动
- **投屏播放**：DLNA 投屏到电视、车机，支持进度同步和音量控制
- **云同步**：WebDAV 音乐云盘、歌单 / 音源脚本云同步、多设备登录管理
- **下载管理**：边听边缓存、后台并发下载、断点续传
- **iOS 特性**：灵动岛 / 锁屏歌词（Live Activity）、画中画歌词（PiP）
- **Android 特性**：桌面悬浮歌词、蓝牙歌词推送、状态栏歌词
- **音频匹配**：听歌识曲（ACRCloud）、本地歌曲自动匹配在线歌词封面
- **每日推荐**：网易云每日推荐 + 私人 FM 兜底
- **分享码**：`[Lyra]V1·wy·186016·晴天-周杰伦` 格式的歌曲 / 歌单分享

**技术栈**：
- **语言**：Dart 3.5+ / Flutter 3.24+
- **音频引擎**：just_audio 0.10.6 + audio_service
- **状态管理**：ChangeNotifier（`lib/core/state.dart` 的 `AppState`）
- **持久化**：shared_preferences + Flutter Secure Storage（钥匙串）
- **网络**：http + dio
- **投屏**：upnp_flutter（DLNA）
- **iOS 扩展**：LyraWidget（WidgetKit + ActivityKit）

### 1.2 仓库信息
- **远端**：https://github.com/murongruolan/music-player-mobile
- **主分支**：`main`（受保护，只能通过 PR 合入）
- **原型分支**：`proto/standby-wave`（待机皮肤原型，含 QQ 音乐提取的专有素材，**不合入 main**）

### 1.3 目录结构
```
music-player-mobile/
├── lib/                      # Dart 源码
│   ├── main.dart            # 入口：初始化 App、音频引擎、恢复会话
│   ├── core/                # 核心逻辑
│   │   ├── state.dart       # AppState（全局状态管理，ChangeNotifier）
│   │   ├── float_lyric.dart # 悬浮歌词 / 画中画歌词（Android / iOS）
│   │   ├── live_island.dart # 灵动岛 / 锁屏歌词（iOS Live Activity）
│   │   ├── daily_feed.dart  # 每日推荐（网易云 + 私人 FM）
│   │   ├── library_store.dart # 音乐库（收藏歌曲 / 歌单 / 专辑）
│   │   ├── lyric_store.dart # 歌词缓存与解析（lrc / yrc / krc / qrc / mrc）
│   │   ├── script_store.dart # 音源脚本管理
│   │   ├── cloud.dart       # 听歌统计（本地持久化）
│   │   ├── dav_store.dart   # WebDAV 云盘
│   │   ├── taste.dart       # 关注歌手 / 不感兴趣
│   │   ├── telemetry.dart   # 埋点（匿名统计）
│   │   └── ...
│   ├── audio/               # 音频引擎
│   │   ├── audio_engine.dart # AudioEngine（just_audio 封装）
│   │   ├── media_handler.dart # LyraMediaHandler（audio_service，锁屏 / 通知栏）
│   │   └── equalizer.dart    # Android 均衡器
│   ├── source/              # 音源脚本执行
│   │   ├── music_resolver.dart # MusicResolver（解析歌曲播放地址）
│   │   ├── source_manager.dart # 音源脚本加载 / 缓存
│   │   ├── direct/          # 平台直链解析（NetEase / QQ / Kuwo / ...）
│   │   └── ...
│   ├── cast/                # 投屏
│   │   ├── cast_controller.dart # CastController（DLNA 投屏逻辑）
│   │   └── dlna.dart         # DLNA 设备发现 / 播放控制
│   ├── download/            # 下载管理
│   │   └── downloads.dart    # DownloadManager（并发下载 / 断点续传）
│   ├── net/                 # 网络层
│   │   ├── net.dart         # Net（http 封装 + 持久化）
│   │   ├── session.dart     # Session（登录会话 / token 刷新）
│   │   ├── auth_service.dart # AuthService（Lyra 账号登录 / 注册）
│   │   └── api_client.dart  # ApiClient（HTTP 拦截器 / 自动重试）
│   ├── api/                 # 后端 API
│   │   ├── account_api.dart # 账号相关（profile / devices / ...）
│   │   ├── sync_api.dart    # 云同步（music / playlists / scripts）
│   │   ├── update_api.dart  # 更新检查
│   │   └── ...
│   ├── platform/            # 平台登录（NetEase / QQ / Kuwo / ...）
│   │   ├── credentials.dart # PlatformCredentials（钥匙串存储）
│   │   ├── netease_login.dart
│   │   ├── qq_login.dart
│   │   └── ...
│   ├── player/              # 播放器 UI
│   │   ├── player.dart      # PlayerPage（全屏播放器）
│   │   ├── skins.dart       # 15 套皮肤（SpringSkin / VinylSkin / ...）
│   │   ├── lyrics.dart      # LyricView（通用歌词引擎）
│   │   ├── apple_music_lyric.dart # AppleMusicLyric（SpringSkin 专用）
│   │   ├── landscape.dart   # 横屏皮肤（vinyl / clock）
│   │   └── particles.dart   # 粒子系统（ParticlesSkin）
│   ├── pages/               # 页面
│   │   ├── discover_online.dart # 发现页（联网模式）
│   │   ├── library.dart     # 音乐库
│   │   ├── daily.dart       # 每日推荐
│   │   ├── settings.dart    # 设置
│   │   ├── me.dart          # 我的（账号 / 平台登录）
│   │   └── ...
│   ├── widgets/             # 通用组件
│   │   ├── sheets.dart      # BottomSheet（歌曲详情 / 歌单导入 / ...）
│   │   ├── import_playlist.dart # 歌单导入
│   │   └── ...
│   ├── ui/                  # UI 工具
│   │   ├── kit.dart         # 通用组件（Avatar / Press / LSlider / ...）
│   │   ├── cover.dart       # 封面图（UaImage / Cover）
│   │   ├── cover_tint.dart  # 封面取色
│   │   ├── icons.dart       # 图标映射
│   │   └── ...
│   ├── data/                # 数据模型
│   │   ├── models.dart      # Song / LyricLine / Platform / ...
│   │   └── mock.dart        # Mock 数据（演示模式）
│   ├── shell/               # 外壳
│   │   └── shell.dart       # TabsHost（底部导航 / Tab 切换）
│   └── cloud/               # 云同步模型
│       └── cloud_models.dart
├── ios/                      # iOS 原生代码
│   ├── Runner/
│   │   ├── AppDelegate.swift # 原生桥接（画中画 / 灵动岛 / 桌面图标）
│   │   ├── LiveIsland.swift  # 灵动岛 / 锁屏歌词（ActivityKit）
│   │   └── Info.plist
│   ├── LyraWidget/           # Widget Extension（灵动岛界面）
│   │   ├── LyraWidgetBundle.swift
│   │   ├── LyraLiveActivity.swift
│   │   └── Info.plist
│   ├── Shared/
│   │   └── LyraActivityAttributes.swift # Live Activity 数据结构
│   └── Runner.xcodeproj/
├── android/                  # Android 原生代码
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── res/
├── test/                     # 测试
│   ├── smoke_test.dart       # 冒烟测试（演示模式页面渲染）
│   ├── online_pages_test.dart # 联网页面测试
│   └── ...
├── ci/                       # CI 辅助脚本
│   ├── logs.sh               # 提取 GitHub Actions 日志
│   └── ...
├── .github/
│   └── workflows/
│       ├── ci.yml            # 主 CI（analyze / test / build apk / web）
│       └── ios-build.yml     # iOS 编译验证（PR 改了 ios/ 时触发）
├── codemagic.yaml            # Codemagic CI（iOS 未签名 IPA 打包）
├── CONTRIBUTING.md           # 贡献指南
└── pubspec.yaml              # 依赖配置
```

---

## 二、开发规范

### 2.1 Git 工作流

**分支策略**：
- `main`：主分支，受保护，只能通过 PR 合入，CI 必须全绿
- `feat/*`：功能分支（如 `feat/live-activity`）
- `fix/*`：修复分支（如 `fix/playback-timing`）
- `proto/*`：原型分支（如 `proto/standby-wave`），**不合入 main**

**PR 流程**：
1. 从 `main` 拉新分支：`git checkout -b feat/xxx`
2. 开发 + 提交
3. Push 到远端：`git push -u origin feat/xxx`
4. 开 PR（GitHub）：
   ```bash
   gh api repos/murongruolan/music-player-mobile/pulls \
     -f title="feat: 功能描述" \
     -f head="feat/xxx" \
     -f base="main" \
     -f body="详细说明" \
     --jq .html_url
   ```
5. CI 运行（analyze + test + build apk/web）
6. CI 全绿后，Squash Merge 到 main：
   ```bash
   gh api -X PUT repos/murongruolan/music-player-mobile/pulls/{PR号}/merge \
     -f merge_method=squash \
     -f commit_title="feat: 功能描述 (#PR号)" \
     --jq .merged
   ```
7. 删除远端分支：
   ```bash
   gh api -X DELETE repos/murongruolan/music-player-mobile/git/refs/heads/feat/xxx
   ```
8. 本地清理：
   ```bash
   git checkout main
   git pull --ff-only
   git branch -D feat/xxx
   ```

### 2.2 提交规范（Conventional Commits）

**格式**：`<type>(<scope>): <subject>`

**Type**：
- `feat`：新功能
- `fix`：修复 bug
- `refactor`：重构（不改变行为）
- `perf`：性能优化
- `style`：代码风格（格式化、空格等，不改变逻辑）
- `docs`：文档
- `test`：测试
- `build`：构建系统 / 依赖更新
- `ci`：CI 配置
- `chore`：杂务（不影响代码的其它改动）

**Scope**（可选）：
- `player`：播放器相关
- `ios`：iOS 专属
- `android`：Android 专属
- `cast`：投屏
- `download`：下载
- `lyric`：歌词
- `api`：后端 API
- `ui`：UI 组件

**示例**：
```
feat(ios): 灵动岛 / 锁屏歌词（实时活动）
fix(player): iOS 进度条走完歌还在唱、切歌时旧歌事件串到新歌
refactor(ui): 重构 Avatar 组件，增加加载失败自动重试
docs: 更新 README，添加 iOS 编译说明
```

**PR 标题**：和最终 squash commit 一致，格式 `<type>: <描述>`

### 2.3 代码风格

**Dart**：
- 遵循 [Effective Dart](https://dart.dev/guides/language/effective-dart)
- 使用 `flutter analyze` 检查，CI 会运行
- 允许的 info 级别警告：
  - `unintended_html_in_doc_comment`（文档注释里的尖括号）
  - `avoid_renaming_method_parameters`（重写方法时参数名缩写）
  - `prefer_null_aware_operators`（某些地方显式 null 检查更清晰）
  - `curly_braces_in_flow_control_structures`（单行 if 不强制加花括号）
  - `sort_child_properties_last`（children 参数位置）
  - `deprecated_member_use`（ReorderableListView.onReorder，等插件更新）
  - `unnecessary_import`（dart:typed_data 在某些平台需要）
- **不允许 error 或 warning**，CI 会失败

**命名**：
- 类名：`PascalCase`（如 `AppState`）
- 变量 / 方法：`camelCase`（如 `floatLyric`）
- 私有变量 / 方法：`_camelCase`（如 `_loaded`）
- 常量：`camelCase` 或 `kConstantName`（如 `const bottomH = 262.0`）
- 文件名：`snake_case`（如 `apple_music_lyric.dart`）

**注释**：
- 文件头部注释：说明模块职责（如 `// Apple Music 风格歌词：分块、智能模糊...`）
- 复杂逻辑：块注释说明原理（如 `// 切歌时从停旧歌到新歌开始加载之间，不再把旧歌的进度 / 时长事件转给 AppState`）
- 公开 API：dartdoc 注释（`///`）

**其它**：
- 中文注释（项目用户主要是中国大陆）
- 用户可见的字符串用中文
- 日志用中文（`AppLog.instance.add('播放', '加载成功 ...')`）

### 2.4 测试

**必须通过的测试**：
- `test/smoke_test.dart`：演示模式冒烟测试（所有页面能渲染）
- `test/online_pages_test.dart`：联网模式页面测试
- `test/audio_match_page_test.dart`：音频匹配页面
- `test/platform/*_test.dart`：平台解析逻辑
- CI 会运行 `flutter test`，**必须全部通过**

**不自动添加测试**：除非用户明确要求，不要主动添加测试（开发速度优先）

### 2.5 严谨程度

**高优先级**：
- **正确性第一**：功能要正确实现，不能有明显 bug
- **不回归真实代码**：改原型 / 文档时，绝对不能误碰生产代码
- **CI 必须全绿**：analyze、test、build 都要通过
- **不信任本地 agent**：代码由本地 agent 提交时，需要人工 review 才能合入

**中优先级**：
- **代码可读性**：变量命名清晰、逻辑分层合理
- **性能优化**：避免不必要的重建 / 重排版（如歌词引擎的 CustomPainter）
- **用户体验**：动画流畅（60fps）、操作反馈及时

**低优先级**：
- **完美的架构**：能用就行，不必过度抽象
- **100% 测试覆盖**：核心逻辑有测试即可

---

## 三、核心模块详解

### 3.1 状态管理（`lib/core/state.dart`）

**AppState**：全局状态管理（ChangeNotifier），所有页面通过 `context.app` 或 `context.appRead` 访问。

**核心字段**：
- **播放相关**：`cur`（当前歌曲 id）、`queue`（播放队列）、`playing`（播放 / 暂停）、`pos`（播放位置，ValueNotifier）、`speed`（倍速）、`mode`（播放模式：loop / shuffle / one）
- **歌曲列表**：`songs`（所有歌曲，含 mock + 真实）、`lyrics`（当前歌词）
- **音乐库**：`lib`（LibraryStore，收藏歌曲 / 歌单 / 专辑）
- **音频引擎**：`engine`（AudioEngine，就一个实例）
- **投屏**：`casting`（是否投屏中）、`castDev`（投屏设备名）
- **设置**：`set`（Settings，各种开关和偏好）
- **网络**：`net`（Net，HTTP 客户端 + 持久化）、`online`（是否联网模式）
- **账号**：`authed`（是否登录）、`account`（Account，用户信息）

**核心方法**：
- **播放控制**：`play(id)`、`prev()`、`next()`、`toggle()`、`seek(sec)`、`setSpeed(s)`
- **队列管理**：`playAll(ids, name)`、`addToQueue(id)`
- **音乐库操作**：`toggleLike(id)`、`liked`（收藏的歌曲 id 集合）
- **通知**：`update(callback)`（修改状态并 notifyListeners）、`notify()`（只 notifyListeners）

**注意事项**：
- `pos` 是 `ValueNotifier<double>`，组件通过 `ValueListenableBuilder` 监听
- `smoothPos`：引擎约 200ms 报一次进度，两次之间按时间往前推（逐帧动画用）
- `engineDuration`：引擎返回的实际曲目时长，优先级高于 `song.dur`（元数据时长）

### 3.2 音频引擎（`lib/audio/audio_engine.dart`）

**AudioEngine**：封装 just_audio，单例播放器。

**核心逻辑**：
- **加载**：`playSong(song, autoplay, loopOne, startAt)` → `_load(reason)` → `resolver.resolve(song, reason)` → `setAudioSource(source)`
- **试听版处理**：`_shortOf(song, d)`（时长 < 85% 元数据）→ 重新加载 `reason: trial`
- **iOS 精确时长**：时长和 `song.dur` 差 >4s 且 >2.5%（VBR MP3 估算错）→ 用 `preferPreciseDurationAndTiming` 重新加载
- **LockCachingAudioSource**：边听边缓存，仅 Android + 无请求头 + reason==play 时使用（iOS 跳过）
- **回调**：`onPosition`、`onDuration`、`onPlaying`、`onCompleted`、`onError`（由 AppState 订阅）
- **事件过滤**：`_accept` 标志，切歌时从开始停旧歌到新歌 setAudioSource 之前为 false，防止旧歌的进度 / 时长事件串到新歌

**重要字段**：
- `_seq`：加载代次，每次 `playSong` +1，用于判断是否被新点播顶掉
- `_loaded`：是否已加载可播放音源
- `_accept`：是否接受 position / duration 事件
- `_precise`：需要精确时长加载的歌曲（按 cacheKey 记）

### 3.3 音源脚本（`lib/source/`）

**MusicResolver**：解析歌曲播放地址。

**解析顺序**（`resolve` 方法）：
1. 平台直链（`resolveDirect`）：如果歌曲有 `platformId`，先尝试平台 API 拿直链
2. 音源脚本（`resolveViaScript`）：调用洛雪音源脚本
3. 跨平台备选（`resolveCrossPlatformAlt`）：如果上面都失败，尝试其它平台
4. 试听版兜底（reason==trial 时）

**SourceManager**：
- 加载脚本（`loadAllScripts`）：从持久化读取，或导入新脚本
- URL 缓存（`_urlCache`）：按 `sourceId:trackId:quality` 缓存，TTL 默认 30 分钟
- 试听检测（`checkUrl`）：HEAD 请求拿 `Content-Length`，< `dur*4000*0.85` 视为试听版

**DirectLinkResolver**（`lib/source/direct/direct.dart`）：
- 平台直链解析（NetEase / QQ / Kuwo / Kugou / Migu）
- URL 缓存（`_cache`）：按 `directCacheKey` 缓存，TTL 默认 10 分钟
- 需要平台凭证（`app.platCreds`，钥匙串存储）

### 3.4 歌词引擎（`lib/player/lyrics.dart` 和 `apple_music_lyric.dart`）

**LyricView**（通用歌词引擎，用于唱片 / 声波 / 粒子等皮肤）：
- **瀑布弹簧切行**：每行延迟 46ms，带过冲（`Tk.softSpring`）
- **逐字填充 + 辉光**：先画未唱的暗色，再按已唱位置逐行裁剪画亮色
- **距离模糊**：远处行用 `MaskFilter.blur`（文字自带的模糊，不用 ImageFiltered）
- **点按跳转**：点击行跳转到该时间
- **手动拖动**：拖动后显示「回到当前」按钮，4s 后自动回弹
- **波浪漂浮**：`wave=true` 时，非当前行随正弦波浮动
- **实现**：CustomPainter（整块歌词是一个 Painter，不是一列 Text 组件），换歌 / 改宽度时排版一次，播放中零排版

**AppleMusicLyric**（Apple Music 风格，SpringSkin 专用）：
- **分块**：有翻译时本句+翻译为一块；无翻译时相邻两行同段且间隔<3s则两句合成一块
- **智能模糊**：只有正在唱的块清晰，用户滚动时全清晰，停滚 1.5s 后自动恢复模糊
- **点击反馈**：点击块时显示半透明背景，250ms 后渐隐，跳转到该块开始时间
- **控制台自动收起**：用户滚动时控制台下移隐藏，点击歌词块外空白时重新显示
- **自动滚动**：播放中自动滚动到当前块，让它在屏幕 30% 的位置

### 3.5 投屏（`lib/cast/`）

**CastController**：
- **设备发现**：`startScan()` → DLNA 搜索
- **连接**：`connect(device)` → 播放器切到投屏模式
- **播放控制**：`setPlaying()`、`seek()`、`stop()`
- **进度同步**：轮询渲染端进度（`_poll`），连续 3 次失败才停止
- **音量控制**：`setVolume()`（通过 DLNA RenderingControl）

**DlnaDevice**：
- 封装 upnp_flutter 的 `Device`
- 提供 `load(url)`、`play()`、`pause()`、`seek(ms)`、`getPosition()`、`getDuration()` 等方法

### 3.6 下载管理（`lib/download/downloads.dart`）

**DownloadManager**：
- **并发下载**：`set.dlConc`（默认 3）个任务并发
- **断点续传**：HEAD 拿 `Content-Length`，本地文件存在且大小<总长则 `Range: bytes=已下载-` 继续下载
- **取消处理**：下载中取消删除临时文件，封面 / 歌词阶段取消也删除文件
- **持久化**：`_saveQueue()` 保存下载队列（prefs）

### 3.7 iOS 扩展

**灵动岛 / 锁屏歌词**（Live Activity，iOS 16.1+）：
- **Dart 侧**：`lib/core/live_island.dart` → `LiveIslandCtl.tick()` → MethodChannel `island.update`
- **Swift 侧**：`ios/Runner/LiveIsland.swift` → `IslandActivity.update()` → `activity.update(ActivityContent(state: ...))`
- **界面**：`ios/LyraWidget/LyraLiveActivity.swift`（SwiftUI + WidgetKit）
- **数据结构**：`ios/Shared/LyraActivityAttributes.swift`（App 和 Widget Extension 共享）
- **限制**：只能在 App 前台时开始，之后切后台照常更新；系统「正在播放」也会同时存在

**画中画歌词**（PiP）：
- **Dart 侧**：`lib/core/float_lyric.dart` → MethodChannel `float.update`
- **Swift 侧**：`ios/Runner/AppDelegate.swift` → `LyricPiP.update()` → 逐帧画到 `AVSampleBufferDisplayLayer` → `AVPictureInPictureController`
- **进度插值**：Dart 传 `keys`（fillKeys，逐字时间的折线关键点），原生按时钟插值
- **两套排列**：`layout=1` 本句左上 / 下一句右下（默认），`layout=0` 两行居中

---

## 四、CI/CD

### 4.1 GitHub Actions（`.github/workflows/ci.yml`）

**触发条件**：
- Pull Request
- Push 到 `main`（feature 分支 push 不触发，除非 commit message 含 `[ci]` / `[apk]` / `[shots]`）

**Job**：
- `check`：`flutter analyze` + `flutter test`
- `apk`：`flutter build apk --release`（产物名 `apk`，保留 14 天）
- `web`：`flutter build web`

**并行运行**，总耗时约 3-5 分钟。

### 4.2 iOS 编译（`.github/workflows/ios-build.yml`）

**触发条件**：
- Pull Request 改了 `ios/` 或该 workflow 本身
- 手动触发（`workflow_dispatch`）

**Job**：
- `ios`：`flutter build ios --debug --no-codesign`（验证能编译，不出包）
- `ipa`（仅 `workflow_dispatch`）：`flutter build ios --release --no-codesign` + 打包 `lyra-ios-unsigned.ipa`（未签名，需要 Sideloadly / AltStore 侧载）

**问题**：macOS runner 经常排队后被取消，不稳定。实际 iOS 打包用 Codemagic。

### 4.3 Codemagic（`codemagic.yaml`）

**用途**：打 iOS 未签名 IPA（M2 实例，比 GitHub Actions 快且稳定）

**触发**：手动（codemagic.io 页面点 Start build，选 `main` 分支，refresh workflow dropdown）

**产物**：`lyra-ios-unsigned.ipa`（未签名，Sideloadly / AltStore 侧载重签，免费账号 7 天有效）

**注意**：
- 免费档每月 500 macOS M2 分钟，一个 IPA 实测 10-20 分钟
- Android APK 仍走 GitHub Actions

---

## 五、常见任务

### 5.1 添加新功能

1. 从 `main` 拉新分支：`git checkout -b feat/xxx`
2. 开发 + 测试（`flutter run`）
3. 提交：`git commit -m "feat: 功能描述"`
4. Push：`git push -u origin feat/xxx`
5. 开 PR：
   ```bash
   gh api repos/murongruolan/music-player-mobile/pulls \
     -f title="feat: 功能描述" \
     -f head="feat/xxx" \
     -f base="main" \
     -f body="详细说明" \
     --jq .html_url
   ```
6. 等 CI 全绿
7. Squash merge：
   ```bash
   gh api -X PUT repos/murongruolan/music-player-mobile/pulls/{PR号}/merge \
     -f merge_method=squash \
     -f commit_title="feat: 功能描述 (#PR号)"
   ```
8. 删除分支 + 清理本地

### 5.2 修复 Bug

和添加新功能类似，分支名用 `fix/xxx`，commit 用 `fix: 问题描述`。

### 5.3 打包 iOS IPA

1. 去 https://codemagic.io/
2. 选择 `music-player-mobile` 项目
3. 选择 workflow `iOS 未签名 IPA`
4. Start build，选 `main` 分支（**refresh dropdown** 才能看到最新 commit）
5. 等 10-20 分钟
6. 下载 `lyra-ios-unsigned.ipa`
7. 用 Sideloadly / AltStore 侧载（免费账号，7 天有效）

### 5.4 查看 CI 日志

**方法 1**：GitHub Actions 页面

**方法 2**：脚本（提取 analyze / test 日志）
```bash
# 先拿 run id
gh api "repos/murongruolan/music-player-mobile/actions/runs?branch=main&per_page=1" \
  --jq '.workflow_runs[0].id'

# 提取日志
/projects/sandbox/ci/logs.sh <run_id>

# 查看
cat /projects/sandbox/ci/logs/analyze.txt
cat /projects/sandbox/ci/logs/test.txt
```

---

## 六、最近改动（#72-76）

### #72 bug 审计（8 项）
- 随机播放可能重复当前这首
- 恢复队列时，如果当前是本地歌曲，位置会错
- 投屏换设备没有先断开旧设备
- 登录或退出后，每日推荐被旧请求的结果覆盖（代次计数）
- 投屏进度一次查询失败就停止更新（改为连续 3 次失败才停）
- 横屏切皮肤时会提前恢复竖屏（引用计数）
- 悬浮歌词显示失败后无限重试（指数退避）
- 下载在封面、歌词阶段点取消不生效

### #73 灵动岛 / 锁屏歌词（iOS 16.1+）
- LyraWidget 小组件扩展（ActivityKit）
- 灵动岛小条：左封面，右当前歌词
- 长按展开：封面、歌名歌手、本句 + 下一句、进度条
- 锁屏同时显示
- 设置 → 歌词 → 「灵动岛歌词」开关（默认开）
- 限制：必须在前台开始播放后才会出现

### #74 iOS 头像 / 画中画歌词
- **头像加载失败自动重试**：新装首启「允许联网」还没点时，第一次请求必失败。现在加载失败会自动重试（1.5s 起翻倍，最多 5 次）
- **画中画歌词染色**：改用和 App 内歌词同一套时间（逐字歌词按字走），染色宽度按实际排版宽度算
- **画中画新增排列**：「本句左上、下一句右下」（默认），设置里可切回两行居中

### #75 播放引擎修复
- **iOS 进度条走完歌还在唱**：VBR MP3 时长估算不准（差几十秒）。加载后如果时长差 >4s 且 >2.5%，用 `preferPreciseDurationAndTiming` 重新加载，并记住这首歌
- **日志记两个时长**：「加载成功 …ms · 时长 Xs（歌曲 Ys）」
- **切歌时旧歌事件串到新歌**：停旧歌到新歌 setAudioSource 之间，不再把旧歌的进度 / 时长转给 AppState
- **被顶掉的旧加载不做收尾**：不再替新歌设播放态 / 通知

### #76 律动皮肤歌词改 Apple Music 风格
- **分块**：有翻译时本句+翻译为一块；无翻译时相邻两行同段且间隔<3s则两句合成一块
- **智能模糊**：只有正在唱的块清晰，用户滚动时全清晰，停滚 1.5s 后自动恢复模糊
- **点击反馈**：点击块时显示半透明背景，250ms 后渐隐，跳转到该块开始时间
- **控制台自动收起**：用户滚动时控制台下移隐藏，点击歌词块外空白时重新显示
- **自动滚动**：播放中自动滚动到当前块，让它在屏幕 30% 的位置

---

## 七、已知问题与限制

### 7.1 iOS
- **macOS runner 不稳定**：GitHub Actions 的 iOS 编译经常排队后被取消，用 Codemagic 代替
- **免费账号侧载限制**：每周 10 个 App ID，LyraWidget 扩展占一个，签名 7 天有效
- **灵动岛系统限制**：只能在前台开始，系统「正在播放」会同时存在
- **画中画系统限制**：需要正在播放（音频会话活动），切到后台自动进画中画

### 7.2 Android
- **均衡器仅 Android**：iOS 的 just_audio 没有 androidEqualizer* 方法
- **悬浮歌词需要权限**：「显示在其他应用上层」权限
- **状态栏歌词**：仅部分定制系统支持（MIUI / ColorOS / ...）

### 7.3 通用
- **音源脚本依赖洛雪**：需要用户自己导入，仓库不包含
- **封面 / 歌词网络请求**：需要 UA 才能拿到图片（网易 / QQ 图床拦截默认 UA）
- **VBR MP3 时长不准**：iOS AVPlayer 估算错，已在 #75 修复（精确时长重新加载）
- **试听版检测不完美**：只能靠 Content-Length 或播放时长判断

---

## 八、联系方式

**项目维护者**：穆容若岚（murongruolan）  
**GitHub**：https://github.com/murongruolan/music-player-mobile  
**本次交接 AI Agent**：小克（Kiro）

---

## 九、附录

### 9.1 常用命令

```bash
# 运行（演示模式）
flutter run

# 运行（联网模式，需要后端）
flutter run --dart-define=BACKEND_URL=https://your-backend.com

# 分析
flutter analyze

# 测试
flutter test

# 打 Android APK
flutter build apk --release

# 打 iOS（本地，需要 macOS + Xcode）
flutter build ios --release --no-codesign

# 查看远端分支
gh api repos/murongruolan/music-player-mobile/branches --jq '.[].name'

# 查看最近 PR
gh api "repos/murongruolan/music-player-mobile/pulls?state=all&per_page=10" \
  --jq '.[]|[.number,.title,.state,.merged]|@tsv'

# 查看 main 分支最近 commit
git log --oneline -10 origin/main
```

### 9.2 关键文件快速索引

- **全局状态**：`lib/core/state.dart` → `AppState`
- **音频引擎**：`lib/audio/audio_engine.dart` → `AudioEngine`
- **播放器 UI**：`lib/player/player.dart` → `PlayerPage`
- **皮肤**：`lib/player/skins.dart` → 15 套皮肤
- **歌词**：`lib/player/lyrics.dart`（通用）、`lib/player/apple_music_lyric.dart`（SpringSkin）
- **音源脚本**：`lib/source/music_resolver.dart` → `MusicResolver`
- **投屏**：`lib/cast/cast_controller.dart` → `CastController`
- **下载**：`lib/download/downloads.dart` → `DownloadManager`
- **iOS 画中画**：`ios/Runner/AppDelegate.swift` → `LyricPiP`
- **iOS 灵动岛**：`ios/Runner/LiveIsland.swift` + `ios/LyraWidget/LyraLiveActivity.swift`
- **CI**：`.github/workflows/ci.yml`、`codemagic.yaml`

---

**祝开发顺利！有问题欢迎随时在 GitHub Issues 或 PR 里讨论。**

**感谢这段时间的合作，期待 Lyra 越来越好！🎵**

— 小克，2026-11-06
