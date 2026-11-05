// Mock 数据：与原型 data.js / v4.js 完全一致。接口对接后由 Repository 替换。
import 'models.dart';

const _songs = [
  ['夜航星图', '雾港', '远光', 218, 'Hi-Res', 38], ['潮汐信号', '林间灯塔', '潮汐', 201, 'SQ', 198],
  ['银色引力', '回声实验室', '磁场', 243, 'SQ', 220], ['慢速漂流', '北纬二十三', '慢速', 189, 'HQ', 160],
  ['玻璃海', '澄音', '玻璃海', 232, 'Atmos', 186], ['凌晨四点的城市', '夜行列车', '不夜', 254, 'SQ', 265],
  ['余温', '苏米', '余温', 176, 'HQ', 12], ['光年以外', '霁', '光年', 265, 'Hi-Res', 250],
  ['白噪音', '回声实验室', '磁场', 198, 'SQ', 210], ['风从山谷来', '林间灯塔', '潮汐', 214, 'HQ', 120],
  ['落日飞行', '北纬二十三', '慢速', 207, 'SQ', 24], ['霓虹雨', '夜行列车', '不夜', 229, 'SQ', 300],
  ['星尘信件', '雾港', '远光', 237, 'Hi-Res', 48], ['海盐汽水', '苏米', '余温', 184, 'HQ', 172],
  ['失重练习', '澄音', '玻璃海', 221, 'SQ', 275], ['第七个夏天', '霁', '光年', 248, 'SQ', 30],
  ['Afterglow', 'Nova Lane', 'Afterglow', 203, 'SQ', 330], ['Midnight Drive', 'The Static Hours', 'Night Shift', 226, 'Hi-Res', 235],
  ['Paper Planes', 'Lumi', 'Lumi', 191, 'HQ', 95], ['Satellite Heart', 'Nova Lane', 'Afterglow', 212, 'Atmos', 285],
  ['云端漫步', '雾港', '远光', 199, 'SQ', 205], ['深蓝档案', '回声实验室', '磁场', 244, 'Hi-Res', 228],
  ['Lighthouse', 'Lumi', 'Lumi', 208, 'SQ', 175], ['晴天电台', '苏米', '余温', 187, 'HQ', 52],
];

final songs = [
  for (var i = 0; i < _songs.length; i++)
    Song(i, _songs[i][0] as String, _songs[i][1] as String, _songs[i][2] as String, _songs[i][3] as int,
        _songs[i][4] as String, (_songs[i][5] as int).toDouble(), i % 4),
];

const playlists = [
  Playlist(0, '深夜城市漫游 · 霓虹与雨', by: 'Lyra 编辑部', count: 42, playCount: '38.2万', hue: 250, variant: 2),
  Playlist(1, '专注 · 无人声电子', by: 'Lyra 编辑部', count: 60, playCount: '112万', hue: 200, variant: 1),
  Playlist(2, '周末通勤的轻快节拍', by: '阿栗', count: 35, playCount: '8.6万', hue: 30, variant: 3),
  Playlist(3, '后摇与星空', by: 'Lyra 编辑部', count: 28, playCount: '21.4万', hue: 225, variant: 0),
  Playlist(4, '华语独立 · 新声', by: 'Lyra 编辑部', count: 50, playCount: '64.1万', hue: 160, variant: 2),
  Playlist(5, '雨天钢琴', by: 'Mo', count: 24, playCount: '5.3万', hue: 190, variant: 1),
  Playlist(6, '跑步 160 BPM', by: 'Lyra 编辑部', count: 40, playCount: '17.7万', hue: 10, variant: 3),
  Playlist(7, 'Lo-fi 夜读', by: 'Lyra 编辑部', count: 66, playCount: '93.0万', hue: 280, variant: 0),
];

final myPlaylistsSeed = [
  const Playlist(100, '我喜欢的音乐', count: 128, hue: 42, variant: 0, mine: true),
  const Playlist(101, '开车专用', count: 46, hue: 12, variant: 3, mine: true),
  const Playlist(102, '睡前十首', count: 10, hue: 230, variant: 1, mine: true),
  const Playlist(103, '从桌面端导入 · 收藏夹', count: 213, hue: 265, variant: 2, mine: true, tag: '导入'),
];

const banners = [
  PromoBanner('独家首发', '《远光》全新专辑', '雾港 · 10 首 Hi-Res 母带', 38),
  PromoBanner('粒子舞台', '把音乐变成星系', '新动效皮肤上线，跟着节拍旋转', 250),
  PromoBanner('每周精选', '夜行列车的城市之歌', '凌晨四点，霓虹未眠', 300),
  PromoBanner('活动', '2026 年度聆听报告', '回顾你的 1,284 小时', 160),
];

const hotSearch = ['夜航星图', '银色引力 现场版', '玻璃海', '凌晨四点的城市', 'Midnight Drive', '光年以外', '霓虹雨', 'Afterglow', '失重练习', '星尘信件'];

const _lyrics = [
  ['城市在身后熄灭最后一盏灯', 'The city behind us turns off its final light'],
  ['我把耳机调到你说话的频率', 'I tune my headphones to the frequency of your voice'],
  ['云层很低 像一封没寄出的信', 'Clouds hang low, like a letter never sent'],
  ['风从北方来 带着潮湿的星', 'Wind from the north, carrying damp stars'],
  ['我们沿着航线 数过所有的黎明', 'Along the route we counted every dawn'],
  ['你说光会迟到 但从不缺席', 'You said the light runs late, but never fails to come'],
  ['夜航的星图 在掌心慢慢展开', 'The night-flight star map slowly unfolds in my palm'],
  ['每一颗都写着 你还在', 'Every star reads: you are still here'],
  ['穿过雾 穿过海', 'Through the fog, across the sea'],
  ['穿过所有安静的告白', 'Through every quiet confession'],
  ['如果引力也会疲惫', 'If gravity ever grows tired'],
  ['就让我做你的轨道', 'Let me be your orbit'],
  ['夜航的星图 在掌心慢慢展开', 'The night-flight star map slowly unfolds in my palm'],
  ['每一颗都写着 你还在', 'Every star reads: you are still here'],
  ['天亮之前 我们不说再见', 'Before daybreak, we don’t say goodbye'],
  ['只把灯 留给下一次遇见', 'We only leave the light on for the next time we meet'],
];
final lyrics = [..._mockLyrics];

/// 设置页里的歌词预览固定用演示歌词（联网模式下 [lyrics] 是当前歌曲的真实歌词，行数不定）。
final previewLyrics = List<LyricLine>.unmodifiable(_mockLyrics);
final _mockLyrics = [
  for (var i = 0; i < _lyrics.length; i++)
    LyricLine(4 + i * 5.2, 5.2, _lyrics[i][0], _lyrics[i][1], i < 6 ? '主歌' : i < 10 ? '副歌' : i < 12 ? '桥段' : '副歌'),
];

const platforms = [
  Platform('netease', '网易云音乐', '云', 0xFFE5383B, 0xFF9E1C24),
  Platform('qq', 'QQ音乐', 'Q', 0xFF2FBE6F, 0xFF137A43),
  Platform('kugou', '酷狗音乐', 'K', 0xFF2C8BFF, 0xFF1450B8),
  Platform('kuwo', '酷我音乐', '我', 0xFFF5A623, 0xFFB46A05),
  Platform('migu', '咪咕音乐', '咪', 0xFFE3307C, 0xFF8E1248),
];
Platform platformBy(String id) => platforms.firstWhere((p) => p.id == id, orElse: () => platforms.first);

const scriptsSeed = [
  Script('a', '解析脚本 A', '1.4.2', ['netease', 'qq', 'kugou', 'kuwo', 'migu'], ['SQ', 'Hi-Res'], 320, 98),
  Script('b', '解析脚本 B', '0.9.0', ['netease', 'qq', 'kuwo'], ['HQ', 'SQ'], 540, 91),
  Script('c', '解析脚本 C', '2.1.0', ['kugou', 'migu', 'qq'], ['HQ'], 1180, 76),
  Script('d', '解析脚本 D', '0.3.1', ['netease', 'kugou'], ['SQ', 'Atmos'], 420, 94),
];

const skinCats = ['动效', '拟物', '花样', '极简'];
const skins = [
  Skin('spring', '律动', '动效', 'Apple Music 风格：封面形变、弹簧瀑布或波浪歌词、内嵌队列', usesBg: true, tag: '默认'),

  Skin('particles', '粒子', '动效', '与桌面端同源的 3D 点云，可拖动旋转'),
  Skin('pulse', '声波', '动效', '扩散声波环 + 节拍频谱', usesBg: true),
  Skin('vinyl', '唱片', '拟物', '黑胶旋转、唱针起落', usesBg: true),
  Skin('cassette', '磁带', '拟物', '双卷轴转动、磁带随进度从左卷到右、VU 表跟着跳', tag: '新'),
  Skin('film', '胶片', '拟物', '竖向胶片带：队列封面一帧帧滚过，颗粒与漏光', tag: '新'),
  Skin('pixel', '像素', '花样', '8-bit 像素封面、方块频谱、CRT 扫描线', tag: '新'),
  Skin('stage', '舞台', '花样', '按段落切换的大字提词器', usesBg: true),
  Skin('poster', '写真', '花样', '封面满屏 + 压在照片上的大字歌词'),
  Skin('neon', '霓虹', '花样', '砖墙上的霓虹灯管：歌名闪烁点亮，灯光随节拍明暗', tag: '新'),
  Skin('terminal', '终端', '花样', '命令行风格：播放日志、ASCII 进度与频谱', tag: '新'),
  Skin('magazine', '杂志', '极简', '纸张底色、超大号排版，当前歌词作为引文', tag: '新'),
  Skin('dial', '表盘', '极简', '手表表盘：60 格刻度环就是进度条，指针随播放走动', tag: '新'),
  Skin('minimal', '极简', '极简', '纯文本列表，最省电'),
  // 横屏皮肤：普通态（封面 · 控制 · 歌词 · 右侧功能坞）↔ 全屏态（沉浸大字），交叉淡化切换
  Skin('standby', '待机', '横屏', '两侧随节拍荡开的波光；不操作时进全屏衬线大字歌词 + 时钟', tag: '横屏'),
  Skin('land_vinyl', '唱片', '横屏', '模糊封面背景，旋转黑胶 + 右侧歌词；全屏时大唱片压在屏边', tag: '新'),
  Skin('land_clock', '时钟', '横屏', '床头 / 桌面待机：大时钟 + 当前歌词，全屏只留时钟和一句', tag: '新'),
];

/// 横屏皮肤（播放器全屏、锁横屏）。
bool isLandscapeSkin(String id) => skinBy(id).cat == '横屏';
Skin skinBy(String id) => skins.firstWhere((s) => s.id == id, orElse: () => skins.first);

const qualities = [
  Quality('128k', '标准', '128kbps · 约 3MB'), Quality('HQ', '较高', '320kbps · 约 8MB'),
  Quality('SQ', '无损', 'FLAC 16bit/44.1kHz · 约 28MB'), Quality('Hi-Res', '高解析', 'FLAC 24bit/96kHz · 约 76MB'),
  Quality('Dolby', '杜比音效', 'E-AC-3 · 设备需支持'), Quality('Atmos', '全景声', '空间音频 · 耳机效果最佳'),
];

const eqPresets = <String, List<double>>{
  '平直': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], '流行': [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2], '摇滚': [4, 3, 1, -1, -2, -1, 1, 3, 4, 4],
  '人声': [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1], '古典': [3, 2, 1, 0, -1, -1, 0, 2, 3, 4], '低音增强': [6, 5, 4, 2, 0, -1, -1, 0, 0, 0],
  '电子': [5, 4, 1, 0, -2, 1, 0, 2, 4, 5],
};
const eqBands = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

const barStyles = <String, String>{
  'liquid': '液态玻璃', 'island': '浮岛', 'capsule': '胶囊', 'frosted': '磨砂一体', 'classic': '经典',
  'cutout': '凹槽', 'dock': '程序坞', 'bubble': '气泡', 'text': '纯文字',
};
const barDesc = <String, String>{
  'liquid': '高透明玻璃 + 可拖动的水滴指示器', 'island': '悬浮胶囊，选中项展开文字', 'capsule': '4 项 + 独立搜索圆钮',
  'frosted': '与迷你播放条连成一整块', 'classic': '贴底实色，最省电', 'cutout': '选中图标升起，底栏挖出凹口',
  'dock': '居中窄条，按下放大上跳', 'bubble': '每项一颗独立玻璃气泡', 'text': '只有文字，选中加粗',
};

const appIcons = [
  ['gold', '鎏金', '默认 · 与鎏金主题色配套'], ['night', '夜空', '深色底 · 金色琴弦'], ['aurora', '极光', '与「极光」主题色配套'],
  ['vinyl', '黑胶', '唱片纹理'], ['mono', '极简', '白底黑线'], ['neon', '霓虹', '发光描边'], ['glass', '玻璃', '半透明磨砂'], ['pixel', '像素', '8-bit'],
];
const fonts = [
  ['system', '系统默认'], ['round', '圆润'], ['serif', '书卷'], ['kai', '楷意'], ['mono', '等宽'],
];

const homeModNames = <String, List<String>>{
  'custom': ['为你定制', '每日推荐、心动/雷达模式（需登录平台）'],
  'mypl': ['我的歌单', '平台上创建与收藏的歌单（需登录平台）'],
  'quick': ['快捷入口', '每日混音、私人电台、识曲、排行榜'],
  'tabs': ['精选 · 榜单 · 歌单', '推荐歌单与热门榜单'],
  'platrec': ['平台推荐', '新碟、官方榜、MV 等，随平台变化'],
};

const announcements = [
  Announcement('a1', '重要', '11-02', '服务条款与隐私政策更新',
      '我们更新了《隐私政策》中关于聆听记录的说明：\n\n1. 聆听记录只用于生成每日混音与听歌统计，不会用于广告。\n2. 你可以在「我的 → 听歌统计」随时清除全部记录。\n3. 第三方平台账号凭据只保存在本机，不会上传。\n\n继续使用即表示你已阅读并同意更新后的条款。',
      important: true, popup: true, closable: false),
  Announcement('a2', '活动', '11-01', '双 11 · 年度会员 5 折', '11 月 1 日至 11 月 11 日，年度会员 5 折，并赠送「表盘」「霓虹」两套限定皮肤。已是会员的用户续费同享。', popup: true),
  Announcement('a3', '更新', '10-30', '新皮肤：待机 · 波光', '待机皮肤改为全屏横屏：两侧随节拍荡开的波光，中间是衬线大字歌词。横放手机并充电时自动进入。', popup: true),
  Announcement('a4', '更新', '10-28', 'v2.4.0 已发布', '新增律动 / 灵动皮肤、液态玻璃底栏，修复后台播放偶发中断。'),
  Announcement('a5', '维护', '10-12', '同步服务维护完成', '10 月 12 日 02:00–04:00 同步服务维护已结束，感谢等待。'),
];

const loginDevices = [
  Device('iPhone 15 Pro', 'iOS 19.1 · 本机', '当前在线', current: true),
  Device('Lyra for Windows', 'Windows 11 · 桌面端', '2 小时前'),
  Device('客厅电视', 'Android TV 13', '昨天 21:40'),
];

const castDevices = [
  CastDevice('客厅电视', 'DLNA · 电视', '上次 昨天'),
  CastDevice('书房音箱', 'DLNA · 音箱', '上次 3 天前'),
  CastDevice('车载蓝牙', '蓝牙 · 车机', '上次 上周'),
];

const playTrace = [
  ['21:40:02.118', '网易云 · 自动选择', '请求 SQ 播放地址', 'ok'],
  ['21:40:02.441', '解析脚本 A', '返回 403（会员歌曲）', 'fail'],
  ['21:40:02.452', '解析脚本 D', '降级尝试 SQ', 'fail'],
  ['21:40:02.903', 'QQ音乐 · 解析脚本 A', '按「歌名 + 歌手 + 时长」匹配到同一首', 'ok'],
  ['21:40:03.210', 'QQ音乐 · 解析脚本 A', '取流成功 · FLAC 16/44.1 · 27.8MB', 'ok'],
];

const styleTiles = [['城市流行', 300.0], ['后摇', 225.0], ['Lo-fi', 280.0], ['电子', 200.0], ['民谣', 30.0], ['钢琴', 190.0]];
const tasteChips = [['城市流行', 34], ['电子', 22], ['后摇', 16], ['华语独立', 14], ['Lo-fi', 9]];
const davFolders = [['无损', '128 首'], ['Live 现场', '36 首'], ['车载', '64 首']];
