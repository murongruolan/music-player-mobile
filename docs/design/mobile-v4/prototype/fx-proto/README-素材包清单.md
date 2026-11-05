# WAVE 波光 + 彩胶唱片 · 复现素材包（清单）

> 全部素材来自真机 root 抓取（QQ 音乐 14.4.0.8，VIP3 态），这是复现所需的**全部实体**。
> 预览：`index.html`（双面板）/ `compare.html`（WAVE 真仿对照调参）。基准视频：`wave.mp4`。

## 目录结构

```
├── index.html                  双面板预览（WAVE 实录视频 + 彩胶真帧回放）
├── compare.html                WAVE 真仿同帧对照（左实录/右复刻，滑杆调参）
├── wave.mp4                    真机实录 64s（验收基准，裁切后 640px）
├── 复刻规格-WAVE与彩胶.md      完整规格（机制/参数表/实施路线/边界声明）
├── ref/                        WAVE 录屏参考帧 ×2（f293=满帧状态 / f053=歌词另帧）
│
├── shader_official/            ★ 解密后的官方 shader + 配置
│   ├── WaveFragment.decrypted.glsl   WAVE 波光 fragment 全文（221 行，运行时内存取证）
│   ├── BlurVertex.glsl / BlurFragment.glsl   AEKit 15-tap 高斯后处理（柔滑感的来源，必加）
│   ├── default_template.json         AITemplate 歌词通道配置（7 通道/字体/动画/颜色占位符）
│   └── hs_setting.json               横屏用户可调参数结构
│
├── assets_wave/                ★ WAVE 官方资源包（7030935.zip 解包，与机内逐字节一致）
│   ├── qm_custom_wave/input.json     时间线：1624×780 @25fps，0-150 帧，cycle=1
│   ├── qm_custom_wave/image/bg.png   sDiffMap 底图（横向黑白渐变=被涟漪扭曲采样）
│   ├── qm_custom_wave/shader/Basic{Vertex,Fragment}.glsl   明文基座 shader
│   ├── qm_custom_wave/shader/WaveFragment.enc   加密原件（已由解密原文替代，见 shader_official）
│   ├── Cache/shader/Anim*.enc        歌词逐字三段动画 shader（加密；行为由文件名描述：
│   │                                 In=入 GatherIn 聚合 / Middle=Static 循环 / Out=FadeOut 离场，
│   │                                 Key=当前字(放大) / Normal=普通字——复现按名实现等效动画即可）
│   ├── Cache/font/tce000001/NotoSerifSC-Black-fix   歌词衬线字体
│   └── default_template.json         同 shader_official（歌词通道全配置）
│
├── assets_vinyl/               ★ 彩胶官方真帧 + 双变体配置
│   ├── frames/frame_000..124.png     125 帧 RGBA 流光叠层（750×1624，25fps 5s 循环）★直接播放即 1:1
│   └── config/style_vinylDisc_4000002.json / style_litheColorful_4000003.json
│       多彩透明胶片/浅色轻盈 双变体官方配色（magicColor/textColor 深浅切换）
│
└── params/                     参数文件
    ├── calibrated_params.json            WAVE uniform 校准值（可编程读取）+ 五环初值
    ├── style_AITemplate_4000008.json     AITemplate 皮肤配置原件
    └── hs_setting.json                   横屏用户参数结构
```

## WAVE 复刻速查（细节见 复刻规格-WAVE与彩胶.md）

1. **shader**：`shader_official/WaveFragment.decrypted.glsl` 原文直译（GLSL→AGSL/RuntimeShader 或 WebGL），数学零改动
2. **sDiffMap**：`assets_wave/qm_custom_wave/image/bg.png`（黑→白渐变被涟漪扭曲采样 + blendMultiply cMagicColor）
3. **uniform 初值**：`params/calibrated_params.json`（cMagic #4b73be / 波高 0.06·0.08 / 波宽 0.13·0.26 / 半径 0.82·0.78 / 曲线强度 0.03）
4. **必加后处理**：高斯模糊 ~5px（官方 AEKit 15-tap 的等效——没有它波纹是生硬条纹）
5. **画布比例**：1624:780 锁定（比例错则装饰环几何全错）
6. **歌词层**：主歌词居中 + 首字放大 110sp+blur 垫底（default_template.json：color 占位符 &magiclyric1 跟主题色）
7. **音乐联动**：cCurveIntensity/Sharpness = 实时音频能量；cWaveCircle1-5.x = 节拍触发扩散环进度

## 彩胶复刻速查

1. `assets_vinyl/frames/` 125 帧序列直接播放（帧率 25fps）= 官方流光原样
2. 双主题配置照 `config/style_*.json`（textHighLightColor #d9f2b6 跟随高亮）
3. 换碟动画 = 旧碟飞出/新碟落入（官方 IridescentDiscAlbumFlySwitchView 机制）
4. 横屏素材待补：VIP 有效期内预览循环播 + 55s 录屏即得

## 已确认不可得（无需再尝试）

- WaveFragment.enc 加密键（加固 so 内；但**解密原文已交付**，加密层无意义）
- uniform 运行时逐帧数值（引擎逐帧动态计算 + 反钩盾；用对照页拟合已对齐）
- 彩胶 alpha 视频原件（密码未破；帧序列已替代）
