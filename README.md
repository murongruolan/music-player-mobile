# Lyra（暂名）· 移动端

Lyra 的 iOS / Android 客户端，Flutter 实现。目前是完整的前端界面与交互，数据全部来自 mock，接口后续对接。

- 设计稿：[`docs/design/mobile-v4/`](docs/design/mobile-v4/)（`DESIGN.md` 规范、`tokens.json` 设计令牌、`prototype/` 可交互原型，浏览器打开 `prototype/index.html`）。
- 零第三方依赖（只用 Flutter SDK）。
- 状态集中在 `lib/core/state.dart`（`AppState`，`ChangeNotifier`），UI 通过 `context.app` 读写；主题、主题色、底栏样式、皮肤、字体等设置实时生效。

开发流程、分支与提交规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 运行

需要 Flutter stable（Dart ≥ 3.5）。

```bash
flutter pub get
flutter run                 # 真机 / 模拟器
flutter run -d chrome       # Web
flutter analyze && flutter test
```

Web 端可以用 `?shot=<状态>` 直接打开某个页面（用于截图和走查），例如：

| URL 参数 | 打开 |
|---|---|
| `?shot=login` / `forgot` / `disclaimer` | 登录流程 |
| `?shot=discover` · `discover.nologin` · `discover.qq` · `discover.light` · `picker` | 发现页（已登录 / 未登录 / QQ / 浅色 / 音源面板） |
| `?shot=search` · `daily` · `library.pl` · `library.local` · `me` · `me.clip` | 各 Tab（`me.clip` 带剪贴板口令横幅） |
| `?shot=popup` · `notice` | 弹窗公告 / 公告页 |
| `?shot=player.<皮肤>` | 播放器，皮肤 id 见 `lib/data/mock.dart` 的 `skins` |
| `?shot=sheet.<名称>` | more / import / platlogin / eq / skins / bars / icons / queue / home / quality |
| 修饰符 | `.light` 浅色、`.acc2` 第 3 个主题色、`.bar-island` 底栏样式、`.paused` 暂停 |

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml)

| Job | 什么时候跑 | 做什么 |
|---|---|---|
| `check` | 每次推送、每个 PR | `flutter analyze`（有 error 即失败）、`flutter test`（有失败即失败） |
| `build` | PR、推送到 `main`、手动触发，或提交信息带 `[apk]` / `[shots]` | Web 构建 + 截图、Android APK（按 ABI 拆分） |

产物在 Actions 运行页底部的 Artifacts：`apk`（手机装 arm64-v8a）、`shots`（截图，默认 `tool/shots-quick.json` 的十几个状态；提交信息带 `[shots]` 或手动触发勾选「完整截图」时跑 `tool/shots.json` 全部状态，横屏状态以 `@land` 结尾）、`check-logs`。

## 目录

```
lib/                        应用代码
  main.dart                 入口：AppScope → MaterialApp → 鉴权 / 主界面
  core/
    tokens.dart             设计令牌（深浅色、6 种主题色、动效曲线、设置图标色）
    state.dart              AppState：播放、设置、平台登录、队列、歌单……（对应原型 core.js 的 S / ACT）
    shots.dart              ?shot= 演示入口
  data/
    models.dart             Song / Playlist / LyricLine / Platform / Script / Skin …
    mock.dart               全部 mock 数据（与原型 data.js / v4.js 一致）
  ui/
    kit.dart                通用组件：Press 按压、Btn、LChip、Seg、LSwitch、LSlider、Group/Item、SongRow（左滑操作）、
                            HeartBtn、Marquee、Glass、Rise 浮现、CountUp、Shimmer 骨架屏、Toast、showLSheet、showLDialog
    cover.dart              按色相生成的渐变封面（接入真实封面后作为占位 / 兜底）
    brand.dart              App 图标 8 款（竖琴 + 织女星）、环境光背景
    icons.dart              图标名 → Material Rounded
  shell/
    shell.dart              外壳：嵌套 Navigator（二级页推入 + 左缘返回）、迷你播放条、底栏、滚动收起
    nav.dart                9 种底栏：液态玻璃 / 浮岛 / 胶囊 / 磨砂一体 / 经典 / 凹槽 / 程序坞 / 气泡 / 纯文字
    mini.dart               迷你播放条（左右滑切歌、上滑打开播放器）
    clip_banner.dart        剪贴板口令横幅
  pages/
    discover.dart           发现（源条、未登录登录卡、Banner、为你定制、我的歌单、精选/榜单/歌单、平台推荐区）
    search.dart             搜索（底部输入栏 + 唱片圆钮、联想、结果页：类型 Tab + 平台筛选 + 相关搜索）
    daily.dart / library.dart / me.dart
    detail.dart             歌单详情（多选）、歌手、听歌统计
    settings.dart           外观与界面、歌词、系统歌词、播放与音质、智能换源、平台与解析脚本（导入音源）
    misc.dart               公告、平台账号、下载、账号中心、登录设备、备份与同步、音乐云盘（WebDAV）、关于
    scan.dart               扫一扫 + 听歌识曲
    common.dart             TabPage（大标题折叠、回到顶部、下拉刷新）/ SubPage（视差头图）
  widgets/
    picker.dart             音源选择器（平台 → 解析脚本，从源条展开）
    sheets.dart             全部 Sheet：歌曲更多、加入/新建/导入歌单、平台登录、分享口令、定时、均衡器、音质、倍速、
                            投放、歌词卡、播放链路、队列（拖动排序）、底栏样式、App 图标、字体；LField 输入框
    announce.dart           公告弹窗（普通 / 弹窗；可关闭 / 必须确认；多条翻页）
  auth/auth.dart            使用须知、登录 / 注册（通用人机验证：图形字符 / 滑块拼图 / 文字点选）、找回密码、版本停用
  player/
    player.dart             播放器路由（升起 / 下拉关闭）、背景层、顶栏 / 信息 / 进度 / 主控 / 辅助行、歌词快调
    lyrics.dart             歌词引擎：瀑布弹簧、逐字填充 + 辉光、距离模糊、点按跳转、手动拖动 + 4s 回弹、波浪漂浮
    skins.dart              15 套皮肤 + 缩略图
    particles.dart          粒子舞台（星系 / 事件视界 / 全息地球 / 陀螺核心，可拖动旋转）
test/                       组件测试（每个 Tab、9 种底栏、二级页、15 套皮肤、全部 Sheet、浅色主题）
tool/                       CI 截图脚本与截图列表
android/ ios/ web/          平台工程
docs/design/
  mobile-v4/                移动端设计规范与可交互原型（实现以此为准）
  fx-presets/               粒子动效预设（GLSL / three.js），粒子皮肤正式版的参考
```

## 对接接口

UI 不直接读 mock：所有数据都经过 `AppState` 或 `mock.dart` 的常量。建议的替换顺序：

1. 新建 `lib/data/repo.dart`，定义 `abstract class Repo { Future<List<Song>> daily(); Future<SearchResult> search(String q, {String type, String platform}); … }`，先写一个 `MockRepo` 返回现在的常量。
2. 在 `AppState` 里注入 `Repo`，把 `listOf()`、`switchPlatform()`、`reload()`、`login()` 等方法改成调用 `Repo`（它们已经是异步 / 带 loading 状态的写法）。
3. 播放：`AppState._tick()` 现在用计时器模拟进度。接入 `just_audio` / `audio_service` 后，把 `pos`、`playing`、`next()`、`seek()` 改成驱动播放器即可，歌词、进度条、皮肤都只监听 `pos`。
4. 封面：`Cover` 组件保留为占位；有图片 URL 后包一层 `Image.network`，加载失败时回退到渐变封面。
5. 设置持久化：`Settings` 是普通字段，接 `shared_preferences` 时在 `AppState.update()` 里统一保存。

## 已知限制

- 播放为计时模拟，没有声音；均衡器、投放、识曲、扫码都是界面与流程演示。
- 粒子皮肤用 Canvas 画 2600 点，正式版建议改为 `FragmentProgram` 复用 `docs/design/fx-presets/` 里的 GLSL。
- 字体「圆润 / 书卷 / 楷意 / 等宽」依赖设备上已有的字体；需要统一效果时把字体文件放进 `assets/fonts` 并在 `pubspec.yaml` 声明。
- 平板双栏布局未实现（DESIGN.md 第 10 节只给了规则）。
