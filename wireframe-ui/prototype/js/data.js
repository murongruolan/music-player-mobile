/* 示例数据：歌名、歌手、歌词均为自拟，不对应任何真实作品。封面用 CSS 渐变按色相生成。 */
const SONGS = [
  ['夜航星图','雾港','远光',218,'Hi-Res',38],['潮汐信号','林间灯塔','潮汐',201,'SQ',198],
  ['银色引力','回声实验室','磁场',243,'SQ',220],['慢速漂流','北纬二十三','慢速',189,'HQ',160],
  ['玻璃海','澄音','玻璃海',232,'Atmos',186],['凌晨四点的城市','夜行列车','不夜',254,'SQ',265],
  ['余温','苏米','余温',176,'HQ',12],['光年以外','霁','光年',265,'Hi-Res',250],
  ['白噪音','回声实验室','磁场',198,'SQ',210],['风从山谷来','林间灯塔','潮汐',214,'HQ',120],
  ['落日飞行','北纬二十三','慢速',207,'SQ',24],['霓虹雨','夜行列车','不夜',229,'SQ',300],
  ['星尘信件','雾港','远光',237,'Hi-Res',48],['海盐汽水','苏米','余温',184,'HQ',172],
  ['失重练习','澄音','玻璃海',221,'SQ',275],['第七个夏天','霁','光年',248,'SQ',30],
  ['Afterglow','Nova Lane','Afterglow',203,'SQ',330],['Midnight Drive','The Static Hours','Night Shift',226,'Hi-Res',235],
  ['Paper Planes','Lumi','Lumi',191,'HQ',95],['Satellite Heart','Nova Lane','Afterglow',212,'Atmos',285],
  ['云端漫步','雾港','远光',199,'SQ',205],['深蓝档案','回声实验室','磁场',244,'Hi-Res',228],
  ['Lighthouse','Lumi','Lumi',208,'SQ',175],['晴天电台','苏米','余温',187,'HQ',52],
].map(([t,a,al,dur,q,h],id)=>({id,t,a,al,dur,q,h,v:id%4}));

const PLAYLISTS = [
  {id:0,t:'深夜城市漫游 · 霓虹与雨',by:'Lyra 编辑部',n:42,pc:'38.2万',h:250,v:2},
  {id:1,t:'专注 · 无人声电子',by:'Lyra 编辑部',n:60,pc:'112万',h:200,v:1},
  {id:2,t:'周末通勤的轻快节拍',by:'阿栗',n:35,pc:'8.6万',h:30,v:3},
  {id:3,t:'后摇与星空',by:'Lyra 编辑部',n:28,pc:'21.4万',h:225,v:0},
  {id:4,t:'华语独立 · 新声',by:'Lyra 编辑部',n:50,pc:'64.1万',h:160,v:2},
  {id:5,t:'雨天钢琴',by:'Mo',n:24,pc:'5.3万',h:190,v:1},
  {id:6,t:'跑步 160 BPM',by:'Lyra 编辑部',n:40,pc:'17.7万',h:10,v:3},
  {id:7,t:'Lo-fi 夜读',by:'Lyra 编辑部',n:66,pc:'93.0万',h:280,v:0},
];
const MY_PLAYLISTS = [
  {id:100,t:'我喜欢的音乐',n:128,h:42,v:0,me:true},{id:101,t:'开车专用',n:46,h:12,v:3},
  {id:102,t:'睡前十首',n:10,h:230,v:1},{id:103,t:'从桌面端导入 · 收藏夹',n:213,h:265,v:2,tag:'导入'},
];
const BANNERS = [
  {k:'独家首发',h:'《远光》全新专辑',d:'雾港 · 10 首 Hi-Res 母带',hue:38},
  {k:'粒子舞台',h:'把音乐变成星系',d:'新动效皮肤上线，跟着节拍旋转',hue:250},
  {k:'每周精选',h:'夜行列车的城市之歌',d:'凌晨四点，霓虹未眠',hue:300},
  {k:'活动',h:'2026 年度聆听报告',d:'回顾你的 1,284 小时',hue:160},
];
const HOT = ['夜航星图','银色引力 现场版','玻璃海','凌晨四点的城市','Midnight Drive','光年以外','霓虹雨','Afterglow','失重练习','星尘信件'];
const SOURCES = ['全部来源','内置 · 曲库','脚本源 · A','脚本源 · B','本地'];
const LYRICS = [
  ['城市在身后熄灭最后一盏灯','The city behind us turns off its final light'],
  ['我把耳机调到你说话的频率','I tune my headphones to the frequency of your voice'],
  ['云层很低 像一封没寄出的信','Clouds hang low, like a letter never sent'],
  ['风从北方来 带着潮湿的星','Wind from the north, carrying damp stars'],
  ['我们沿着航线 数过所有的黎明','Along the route we counted every dawn'],
  ['你说光会迟到 但从不缺席','You said the light runs late, but never fails to come'],
  ['夜航的星图 在掌心慢慢展开','The night-flight star map slowly unfolds in my palm'],
  ['每一颗都写着 你还在','Every star reads: you are still here'],
  ['穿过雾 穿过海','Through the fog, across the sea'],
  ['穿过所有安静的告白','Through every quiet confession'],
  ['如果引力也会疲惫','If gravity ever grows tired'],
  ['就让我做你的轨道','Let me be your orbit'],
  ['夜航的星图 在掌心慢慢展开','The night-flight star map slowly unfolds in my palm'],
  ['每一颗都写着 你还在','Every star reads: you are still here'],
  ['天亮之前 我们不说再见','Before daybreak, we don’t say goodbye'],
  ['只把灯 留给下一次遇见','We only leave the light on for the next time we meet'],
].map(([o,tr],i)=>({t:4+i*5.2,d:5.2,o,tr,sec:i<6?'主歌':i<10?'副歌':i<12?'桥段':'副歌'}));
const ACCENTS = [
  {n:'鎏金',c:'#F4D28A',lt:'#93650F',ink:'#1B1508'},{n:'星蓝',c:'#8AB4FF',lt:'#2F5FD0',ink:'#08142B'},
  {n:'极光',c:'#6EE7C8',lt:'#0E8A6C',ink:'#04201A'},{n:'霓紫',c:'#B79CFF',lt:'#6B45D6',ink:'#160A33'},
  {n:'樱粉',c:'#FF9CC2',lt:'#C23A72',ink:'#2B0816'},{n:'赤焰',c:'#FF7A66',lt:'#C93C28',ink:'#2B0A05'},
];
/* 音乐平台（第一优先级）→ 解析脚本（第二优先级，按平台过滤）。平台标识用文字徽标，不使用官方 Logo。 */
const PLATFORMS = [
  {id:'netease',n:'网易云音乐',m:'云',c:'#E5383B',c2:'#9E1C24',login:'小栗子'},
  {id:'qq',n:'QQ音乐',m:'Q',c:'#2FBE6F',c2:'#137A43',login:''},
  {id:'kugou',n:'酷狗音乐',m:'K',c:'#2C8BFF',c2:'#1450B8',login:''},
  {id:'kuwo',n:'酷我音乐',m:'我',c:'#F5A623',c2:'#B46A05',login:''},
  {id:'migu',n:'咪咕音乐',m:'咪',c:'#E3307C',c2:'#8E1248',login:''},
];
const SCRIPTS = [
  {id:'a',n:'解析脚本 A',v:'1.4.2',p:['netease','qq','kugou','kuwo','migu'],q:['SQ','Hi-Res'],ms:320,ok:98},
  {id:'b',n:'解析脚本 B',v:'0.9.0',p:['netease','qq','kuwo'],q:['HQ','SQ'],ms:540,ok:91},
  {id:'c',n:'解析脚本 C',v:'2.1.0',p:['kugou','migu','qq'],q:['HQ'],ms:1180,ok:76},
  {id:'d',n:'解析脚本 D',v:'0.3.1',p:['netease','kugou'],q:['SQ','Atmos'],ms:420,ok:94},
];
/* 播放器皮肤：按风格分 4 类，彼此差异明显。bg:true = 使用「播放器背景」设置 */
const SKIN_CATS = ['动效', '拟物', '花样', '极简'];
const SKINS = [
  {id:'spring',n:'律动',cat:'动效',bg:true,d:'Apple Music 风格：封面形变、弹簧瀑布或波浪歌词、内嵌队列',tag:'默认'},
  {id:'standby',n:'待机',cat:'动效',d:'横屏充电时自动进入：大字时钟 + 随节拍荡开的流体波纹',tag:'横屏'},
  {id:'particles',n:'粒子',cat:'动效',d:'与桌面端同源的 3D 点云，可拖动旋转'},
  {id:'pulse',n:'声波',cat:'动效',bg:true,d:'扩散声波环 + 节拍频谱'},
  {id:'vinyl',n:'唱片',cat:'拟物',bg:true,d:'黑胶旋转、唱针起落'},
  {id:'cassette',n:'磁带',cat:'拟物',d:'双卷轴转动、磁带随进度从左卷到右、VU 表跟着跳',tag:'新'},
  {id:'pixel',n:'像素',cat:'花样',d:'8-bit 像素封面、方块频谱、CRT 扫描线',tag:'新'},
  {id:'stage',n:'舞台',cat:'花样',bg:true,d:'按段落切换的大字提词器'},
  {id:'poster',n:'写真',cat:'花样',d:'封面满屏 + 压在照片上的大字歌词'},
  {id:'magazine',n:'杂志',cat:'极简',d:'纸张底色、超大号排版，当前歌词作为引文',tag:'新'},
  {id:'minimal',n:'极简',cat:'极简',d:'纯文本列表，最省电'},
];
const QUALITIES = [
  {k:'128k',n:'标准',d:'128kbps · 约 3MB'},{k:'HQ',n:'较高',d:'320kbps · 约 8MB'},
  {k:'SQ',n:'无损',d:'FLAC 16bit/44.1kHz · 约 28MB'},{k:'Hi-Res',n:'高解析',d:'FLAC 24bit/96kHz · 约 76MB'},
  {k:'Dolby',n:'杜比音效',d:'E-AC-3 · 设备需支持'},{k:'Atmos',n:'全景声',d:'空间音频 · 耳机效果最佳'},
];
const EQ_PRESETS = {平直:[0,0,0,0,0,0,0,0,0,0],流行:[-1,1,3,4,3,0,-1,-1,1,2],摇滚:[4,3,1,-1,-2,-1,1,3,4,4],人声:[-2,-1,0,2,4,4,3,1,0,-1],古典:[3,2,1,0,-1,-1,0,2,3,4],低音增强:[6,5,4,2,0,-1,-1,0,0,0],电子:[5,4,1,0,-2,1,0,2,4,5]};
const EQ_BANDS = ['31','62','125','250','500','1k','2k','4k','8k','16k'];

function coverStyle(h, v = 0) {
  const a = `hsl(${h} 72% 62%)`, b = `hsl(${(h + 40) % 360} 62% 34%)`, c = `hsl(${(h + 320) % 360} 70% 14%)`;
  const g = [
    `radial-gradient(circle at 30% 28%, hsl(${h} 90% 82%) 0 13%, transparent 14%), radial-gradient(circle at 70% 75%, ${a} 0 30%, transparent 62%), linear-gradient(140deg, ${b}, ${c})`,
    `repeating-radial-gradient(circle at 72% 78%, hsl(${h} 80% 70% / .45) 0 5px, transparent 5px 13px), linear-gradient(160deg, ${a}, ${c})`,
    `conic-gradient(from 210deg at 62% 40%, ${a}, ${b}, ${c}, hsl(${h} 80% 72%), ${a})`,
    `linear-gradient(162deg, hsl(${h} 74% 66%) 0 38%, transparent 38.5%), radial-gradient(circle at 80% 85%, hsl(${(h + 60) % 360} 80% 60% / .7), transparent 50%), linear-gradient(20deg, ${b}, ${c})`,
  ][v % 4];
  return `background:${g}`;
}
const fmt = s => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
