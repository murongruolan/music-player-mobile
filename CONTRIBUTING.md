# 开发规范

这个仓库由人和多个 AI agent（云端 Kiro、本地 agent）一起开发。下面的约定对所有人都适用，目的是互不覆盖、每次改动都能追溯和回滚。

## 分支

- `main`：始终可运行、CI 全绿。**不直接往 `main` 提交**，所有改动走 PR。
- 功能分支从最新的 `main` 拉出，命名 `<类型>/<简短描述>`，例如：
  - `feat/announcement-popup`
  - `fix/nav-indicator-stutter`
  - `perf/player-open`
  - `chore/ci-shots`
- 一个分支只做一件事。开始前先 `git pull`，避免和别人在同一处改动。
- 发现别人正在改同一个文件：先在 PR / issue 里说一声，或者等对方合并后再基于新 `main` 改。

## 提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：

```
<类型>(<范围>): <一句话说明，祈使句，不加句号>

<可选正文：为什么改、改了什么、有什么影响。一行不超过 72 字符。>
```

- 类型：`feat` 新功能 · `fix` 修 bug · `perf` 性能 · `refactor` 重构（行为不变）· `style` 纯格式 · `test` 测试 · `docs` 文档 · `chore` 构建 / 依赖 / CI
- 范围用模块名：`nav` `player` `lyrics` `discover` `search` `library` `me` `auth` `settings` `sheets` `picker` `announce` `ci` …
- 一个提交只做一件事；不相关的改动拆开提交。
- 示例：`fix(picker): remove underline on panel labels`

### CI 关键字

写在提交信息里（任意位置）：

| 关键字 | 效果 |
|---|---|
| `[apk]` | 在普通分支上也构建 APK 和快速截图 |
| `[shots]` | 构建 APK，并跑完整截图列表 |

PR 和 `main` 默认就会构建 APK 和快速截图，不需要加。

## PR

- 标题同提交信息格式。描述里写：改了什么、为什么、怎么验证（真机 / 模拟器 / CI 截图）。
- 涉及界面变化时，贴 CI 截图或模拟器截图。
- `check` job 必须通过（`flutter analyze` 无 error、`flutter test` 全过）才能合并。
- 合并方式：**Squash and merge**（`main` 上一个 PR 一个提交）。合并后删除分支。

## 代码约定

- 保持现有代码风格；提交前 `flutter analyze` 无 error。如果要全仓库统一跑 `dart format`，单独开一个 PR，不要和功能改动混在一起。
- 不引入第三方包前，先在 PR 里说明理由；能用 SDK 解决的不加依赖。引入后提交 `pubspec.lock`。
- 设计以 [`docs/design/mobile-v4/DESIGN.md`](docs/design/mobile-v4/DESIGN.md) 为准；颜色、字号、圆角、动效时长用 `lib/core/tokens.dart` 里的令牌，不写死。
- 新页面 / 新状态：在 `lib/core/shots.dart` 加一个 `?shot=` 入口，并加进 `tool/shots.json`，方便截图核对。
- 新组件 / 页面：在 `test/` 里至少保证能渲染、无布局溢出。
- 性能：避免常驻的 `repeat()` 动画；`BackdropFilter`、`ImageFiltered` 只用在必要的地方，并包 `RepaintBoundary`。
- 密钥、Cookie、接口地址不写进代码，用 `--dart-define` 或本地 `.env`（已在 `.gitignore`）。

## 目录归属

| 目录 | 内容 |
|---|---|
| `lib/` | 应用代码，结构见 README |
| `test/` | 组件测试 |
| `tool/` | CI 截图脚本与截图列表 |
| `android/` `ios/` `web/` | 平台工程，改动需在 PR 里说明 |
| `docs/design/` | 设计规范与原型，只读参考；设计更新时整体替换并在 PR 里注明版本 |
