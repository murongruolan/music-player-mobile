# QQ 音乐动效复刻规格（WAVE 动感波光 / 彩胶唱片）— 运行时深挖成果

> 抓取方式：真机 root（QQ 14.4.0.8）：皮肤包落盘提取 + 引擎缓存帧序列提取 + 64s/55s 录屏 + 引擎内部日志通道钩取。
> 交付目录：`E:\sollin_player\fx-proto\`（index.html=双面板预览，compare.html=WAVE 真仿对照调参页，wave.mp4=真机实录）。

## 1. WAVE 动感波光（歌词动效）

### 1.1 结构（按录屏逐帧确认）
```
纯色画布 #26569B（rgb 38,86,155，全高一致——不是渐变）
├─ 左涟漪系统：圆心屏外左侧偏上(-0.14W, 0.16H)，暗弧
│   色向 (22,50,94) 压暗；幅度弱（扫线波动 ±3.5）
├─ 右涟漪系统：圆心屏外右侧(1.06W, 0.52H)，亮弧
│   色向 (54,124,224) 提亮 + 弧心柔光亮斑 rgba(120,175,255,.34)；幅度强（±14）
├─ 主歌词：居中，25sp 级，#d6e4ff
└─ 次要效果：当前句首字放大(110sp)+blur(6-7px)+暗蓝(12,26,80,.5)，垫在主歌词下
```
- 弧带间距 ≈ 0.185H，宽度粗带 0.16H（外柔）+ 细芯 0.05H，逐弧相位抖动 ~0.16
- 扩散速度慢（录屏实测弧带漂移 ~0.03 卡宽/秒），全层再 blur 一档
- 时间线（官方 input.json）：1624×780 @25fps，0→150 帧，cycle=1（6 秒循环）
- `image/bg.png`（横向黑白渐变）= 官方 shader 的**位移贴图**：以渐变亮度对涟漪纹理做横向偏移——这就是"丝滑"的实现手段

### 1.2 复刻路线
- **Canvas/WebGL**：见 `compare.html` 右侧实现（2D 双层描边+两级 blur+逐弧抖动，滑杆可调）——结构已对齐，参数照上表精调即可
- **对齐验收**：`wave.mp4`（真机实录）与实现并排同帧对比（compare.html 已做）

### 1.3 无法取得的部分（已尝试并确认）
- `WaveFragment.enc`（14KB）：官方效果层 shader，AES/DES 加密（键在加固 so 内；字典扫 DES/AES/RC4 全不中）
- 运行时深挖结论：解密后源码**仅瞬时驻内存**（解密→编译→即弃），进程内存无明文残留（三模式全扫仅命中编译后二进制缓存，uniform 名 `sDiffMap2`）；TEK 引擎（libTekEngineLib）内部 `desDecrypt` 为非导出符号；腾讯盾对 Frida 有延迟 SIGABRT 检测（连挂三次均死于 abort）
- 结论：shader 数学以录屏为 ground truth 调参复现，不追密文

## 2. 浅色轻盈彩胶 / 多彩透明唱片（播放页皮肤）

### 2.1 真身资产（已到手，可直接用）
- 官方流光叠层 = **125 帧 RGBA PNG 序列**（750×1624，25fps 5s 循环），真机缓存目录提取：
  `mobile-analysis/qqmusic/skins/pulled/cdn/playerEasterEggRes/a26415c0405db87721ffff7f72f2d615/`
- 官方另有 alpha 视频（`lightEffect.mp4`，CDN `dldir1v6.qq.com/.../6007451.zip`）与帧序列包（`6012542.zip`）——zip 带密码，但解密后的帧已在机内拿到（上者）
- 皮肤配置（`player_style.json`，两个官方变体）：
  - `vinylDisc` 多彩透明胶片（4000002）/ `litheColorful` 多彩透明胶片（4000003）
  - `color: {textHighLightColor:"#d9f2b6", magicColor:"#0d0d0d"/"#ffffff", textColor:"#ffffff"/"#000000"}`（深浅两主题）
  - `bg.type: 3`（封面模糊背景类）
- 非会员预览不动 = 流光帧/视频不下发或仅静态帧；**会员态预览循环后再录一次即得横屏版素材**（录屏手法现成）

### 2.2 复刻路线
- **首选**：直接用 125 帧真序列（Flutter 帧序列播放，等效官方 frameplayer）+ 封面唱片底 + `fly switch` 换碟动画（`IridescentDiscAlbumFlySwitchView` 机制：旧碟飞出新碟落入）
- 替代：shader 薄膜干涉模拟（彩虹偏移 + 沟槽环 + 镜面瓣），观感可调

## 3. 皮肤体系架构（运行时确认）
- 皮肤包落盘：`files/playerRes/playerStyleRes_<id>_<md5>/`（player_style.json + assets/）
- 引擎缓存帧：`sdcard/.../files/qqmusic/playerEasterEggRes/<md5>/frame_*.png`
- 运行时模板副本：`files/playerAITemplateRes/`（.enc 保持加密）
- 引擎：AEKit 授权（aekit.lic）+ TEK 渲染（libTekEngineLib.so，JNI: initWithJSON/startInitCustom/updateParam*/addOneWord 等 86 个）
- 灯牌 = 粉丝应援功能（"粉丝灯牌已点亮，可享Ta的专属音效"，¥1 点亮），非横屏皮肤——已确认无需复刻

## 4. 文件清单
```
fx-proto/
├── index.html        双面板预览（WAVE 实录 + 彩胶真帧回放）
├── compare.html      WAVE 真仿同帧对照（滑杆调参）
├── wave.mp4          真机实录 64s（裁切后 640px）
└── 复刻规格-WAVE与彩胶.md  本文件
mobile-analysis/qqmusic/skins/pulled/
├── playerRes/playerStyleRes_*/   五个真机皮肤包
├── cdn/playerEasterEggRes/       官方帧序列（含彩胶 125 帧）
└── ref/                          WAVE 录屏参考帧
```

---

## 5. 【最终轮 · VIP 态运行时深挖】官方 shader 原文到手（2026-11-06）

**突破**：内存扫描在编译后的缓存窗口内定位到**解密后的 WaveFragment 全文（221 行）**，已归档 `shader_official/WaveFragment.decrypted.glsl`，并用官方 bg.png 做纹理在 WebGL 中**原文跑通**（`wave-official-shader.html`，uniform 全滑杆）。

### 5.1 官方 uniform 参数体系（即"直接拿参数"的答案）
| uniform | 类型 | 语义 |
|---|---|---|
| `cMagicColor` | vec4 | **主题色，跟随专辑封面**（蓝色主题 ≈ #5AB2FF；录屏红色段即红 magic） |
| `cLyricsColor` / `cLyricsColorDeep` | vec4 | 歌词色 / 深歌词色 |
| `cWaveCircle1..5` | vec4 | **五圈扩散环**：x=环进度(时间)，y=速度，z=高度 |
| `cCurveIntensity` / `cCurveSharpness` | float | 曲线强度 / 锐度（音乐能量驱动：`left_data=cCurveIntensity*10`，`pow(right_data*0.1,5)` 叠加到右波高） |
| `cLeft/RightWaveHeight/Width/Speed/Radius` | float | 左右波六参（高/宽/速/半径） |
| `cLeft/RightCircleR` | float | 左右可见圆环半径 |
| `cCanvasSize` | vec2 | 1624×780 |
| `sDiffMap` | sampler | **官方 bg.png（横向黑白渐变）= 被涟漪场扭曲采样的底图** |

### 5.2 官方 shader 机制（原文逐行确认）
1. 底图 = `texture2D(sDiffMap, distorted_uv)`：bg.png 黑白渐变 × 涟漪位移采样 → 再 `blendMultiply(cMagicColor)` 上主题色——**背景色=主题色乘渐变，这就是"跟封面变色"的实现**
2. `ripple()` = `sin((dist·2π/width − speed·t)·2)·0.5+0.5` × 包络 `1−smoothstep(radius−width, radius+width, dist)` × height
3. 涟漪心精确坐标（st 空间）：右 (1628/1624, 384/780)，左 (−12/1624, 380/780)
4. **五圈扩散环**：`borderCircle(中心, waveR_N, waveR_N−0.04, blur)`，`waveR_N = cWaveCircleN.x × 0.0028`，与涟漪场相乘（左权重 0.7 / 右 0.3）——环扫过处涟漪增亮，即"一层层"的来源（但被 blur 柔化）
5. **6 个装饰圆环**：左侧 3 个（x=-0.018/-0.069/-0.04，r=0.5128/×1.38，宽 10px/780 等，Perlin 噪声调制 0.15）+ 右侧 2 个（x=0.95/0.98）——画面里的细圆环线
6. Perlin（simplex）噪声全场调制

### 5.3 运行时取值的最后一步（可选）
uniform 的**具体数值**在渲染时经 `glUniform*` 传入。如需逐值精确：Frida 钩 `glUniform4f/2f/1f`（过滤上述 uniform 名）+ 用户切效果即可捕获——但反 Frida SIGABRT 风险同前；备选 = 用对照滑杆对 `wave.mp4` 目视拟合（现成工具）。

### 5.4 文件清单增补
```
fx-proto/shader_official/
├── WaveFragment.decrypted.glsl   官方波光 shader 全文（221 行，解密态）
├── BlurVertex.glsl / BlurFragment.glsl   AEKit 15-tap 高斯模糊管线
├── default_template.json          AITemplate 文本通道/动画配置（VIP 态拉取）
└── hs_setting.json                横屏用户可调参数（灯牌色/字号等）
```
- 7030935.zip（官方 CDN，dlied5sdk.myapp.com）= 机内包逐字节一致版本，含 NotoSerifSC-Black-fix 歌词字体
- PLAYER_HS_PATTERN_TABLE 确认：pattern_id=4000008，name="歌词动效 · WAVE动感波光"，permission=3（VIP3），playerType=100

## 6. 校准后的默认参数（三轮迭代后与实录对齐，2026-11-06）
```
cMagicColor       = #4b73be（蓝主题；红主题 #b84a52；运行时实际跟随专辑封面主色）
cCurveIntensity   = 0.03   cCurveSharpness = 0.03
cLeftWaveHeight   = 0.06   cLeftWaveWidth  = 0.13   ← 波宽决定弧密度（2π/width），
cLeftWaveSpeed    = 0.30   cLeftWaveRadius = 0.82      官方值在 0.1 量级而非 1.0
cRightWaveHeight  = 0.08   cRightWaveWidth = 0.26
cRightWaveSpeed   = 0.24   cRightWaveRadius= 0.78
cLeftCircleR      = 0.30   cRightCircleR   = 0.05（右侧环贴边细缝）
画布宽高比        = 1624:780 锁定（比例错则装饰环几何全错）
```
**关键工艺点（踩过坑的）**：
1. 官方渲染后有一道 **15-tap 高斯模糊后处理**（AEKit 管线，BlurVertex/BlurFragment 已归档）——不加这层波纹就是生硬条纹，加 5px blur 即得"丝滑水彩"感
2. 涟漪半径收在 ~0.8（st 空间）：**两侧有波、中间平静**——歌词区无干扰
3. 装饰环（drawCircle，左右各一组细白弧）是官方设计原样存在，半径错会变成"两个大半圆"
4. cWaveCircle1-5 五环的运行时数值待精确（滑杆拟合或钩 glUniform*）
