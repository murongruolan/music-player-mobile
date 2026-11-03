/* v4.1：音乐云盘（WebDAV）完整设计。
   在 v4.js 之后加载，覆盖 PAGES.cloud 并新增：添加服务器（选择服务 → 填写 → 测试）、服务器设置、文件浏览、
   云盘音乐（歌曲 / 专辑 / 歌手）、专辑详情、扫描进度、离线状态、备份与恢复、证书信任、文件 / 文件夹操作面板。
   设计说明见 ../DESIGN.md「v4.1 音乐云盘（WebDAV）」。 */
ICONS.file = '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>';
ICONS.image = '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/>';
ICONS.upload = '<path d="M12 16V4M7 9l5-5 5 5"/><path d="M5 20h14"/>';
ICONS.server = '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>';
ICONS.alert = '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>';
ICONS.storage = '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>';
ICONS.pin = '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>';

/* ---------------- 示例数据 ---------------- */
const DAV_PROVIDERS = [
  { id:'jgy', n:'坚果云', d:'国内网盘 · 免费 1 GB/月上传', url:'https://dav.jianguoyun.com/dav/', c:'#3D8BF4', m:'坚', tip:'坚果云要用「应用密码」，不能用登录密码：网页版 → 账户信息 → 安全选项 → 第三方应用管理 → 添加应用。' },
  { id:'alist', n:'Alist', d:'聚合阿里云盘 / 115 / OneDrive 等', url:'https://alist.example.com/dav/', c:'#2FB47C', m:'A', tip:'地址以 /dav/ 结尾；账号要在 Alist 后台勾选 WebDAV 读取权限。' },
  { id:'nc', n:'Nextcloud', d:'自建私有云', url:'https://cloud.example.com/remote.php/dav/files/用户名/', c:'#2CB5D6', m:'N', tip:'地址里要带上你的用户名；开了两步验证的账号需要用「应用密码」。' },
  { id:'syno', n:'群晖', d:'Synology NAS · WebDAV Server 套件', url:'https://nas.local:5006/', c:'#6E7385', m:'群', tip:'先在套件中心安装并启用「WebDAV Server」：http 端口 5005，https 端口 5006。外网访问需要 DDNS 或端口转发。' },
  { id:'qnap', n:'威联通', d:'QNAP NAS', url:'https://nas.local:8081/', c:'#7C6CF2', m:'Q', tip:'控制台 → 网络与文件服务 → WebDAV 中启用，并给共享文件夹开 WebDAV 权限。' },
  { id:'custom', n:'自定义', d:'任何 WebDAV 服务', url:'https://', c:'#C9A04A', m:'+', tip:'支持标准 WebDAV（RFC 4918）。需要服务器支持 Range 请求，才能拖动进度条。' },
];
const DAV_SERVERS0 = [
  { id:'nas', n:'家里的 NAS', pv:'syno', host:'nas.local:5006', user:'ali', root:'/Music', ms:86, used:1.2, total:3.6, unit:'TB', tracks:1284, albums:86, artists:142, scanned:'2 小时前', cert:'self', cache:1.1 },
  { id:'jgy', n:'坚果云', pv:'jgy', host:'dav.jianguoyun.com', user:'ali@example.com', root:'/我的坚果云/音乐', ms:142, used:6.8, total:10, unit:'GB', tracks:96, albums:9, artists:31, scanned:'昨天', cert:'ok', cache:.2 },
];
// 文件树：f = 文件夹 [名称, 子项数说明]；a = 音频 [文件名, 歌曲 id, 格式, 规格, 大小 MB, 附带文件]；x = 不支持 [文件名, 格式, 大小]；o = 其它文件数
const DAV_TREE = {
  '/Music': { f:[['无损', '128 首 · 6 个文件夹'], ['Live 现场', '36 首'], ['车载', '64 首'], ['新下载', '12 首'], ['Hi-Res 母带', '24 首']], a:[['雾港 - 夜航星图.flac', 0, 'FLAC', '24bit/96kHz', 98.4, ['lrc', 'cover']], ['澄音 - 玻璃海.mp3', 4, 'MP3', '320kbps', 9.1, ['lrc']]], o:2 },
  '/Music/无损': { f:[['雾港 - 远光', '12 首 · folder.jpg'], ['回声实验室 - 磁场', '10 首'], ['林间灯塔 - 潮汐', '9 首']], a:[['霁 - 光年以外.flac', 7, 'FLAC', '16bit/44.1kHz', 31.2, ['cover']], ['夜行列车 - 霓虹雨.flac', 11, 'FLAC', '16bit/44.1kHz', 27.8, ['lrc', 'cover']], ['北纬二十三 - 落日飞行.m4a', 10, 'ALAC', '24bit/48kHz', 52.6, []], ['苏米 - 余温.wav', 6, 'WAV', '16bit/44.1kHz', 29.5, ['lrc']], ['Track 07.flac', 12, 'FLAC', '16bit/44.1kHz', 33.1, []]], x:[['回声实验室 - 白噪音.ape', 'APE', 41.3], ['DSD 测试.dsf', 'DSF', 212.0]], o:4 },
  '/Music/无损/雾港 - 远光': { f:[], a:[['01. 夜航星图.flac', 0, 'FLAC', '24bit/96kHz', 98.4, ['lrc']], ['02. 星尘信件.flac', 12, 'FLAC', '24bit/96kHz', 102.7, ['lrc']], ['03. 余温.flac', 6, 'FLAC', '24bit/96kHz', 77.0, []]], o:2 },
};
const DAV_BACKUPS = [
  ['2026-11-02 03:00', '自动 · iPhone 15', 128, 14, '182 KB'], ['2026-11-01 03:00', '自动 · iPhone 15', 127, 14, '181 KB'],
  ['2026-10-30 21:14', '手动 · 桌面端', 121, 13, '176 KB'], ['2026-10-24 03:00', '自动 · iPhone 15', 118, 12, '170 KB'],
];
const DAV_RECENT = [[0, 'FLAC', '24bit'], [7, 'FLAC', ''], [11, 'FLAC', ''], [10, 'ALAC', '24bit'], [4, 'MP3', ''], [6, 'WAV', ''], [12, 'FLAC', '24bit'], [17, 'FLAC', '']];

function davReset() {
  S.dav = { servers:DAV_SERVERS0.map(x => ({ ...x })), cur:'nas', path:'/Music', view:'歌曲', scan:null, offline:false, backing:null, sort:'名称' };
  S.davAdd = { step:0, pv:3, test:'idle', adv:false };
  S.davSeg = 0;
  S.davPlaying = false;
  Object.assign(S.set, { davAutoScan:true, davScanWifi:true, davMatch:true, davBkAuto:true, davBkWifi:true, davSelf:true, davCacheOn:true });
}
davReset();
const davSrv = () => S.dav.servers.find(x => x.id === S.dav.cur) || S.dav.servers[0];
const davPv = id => DAV_PROVIDERS.find(p => p.id === id) || DAV_PROVIDERS[5];
const pvBadge = (p, size = 30) => `<span class="dv-pb" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .44)}px;background:${p.c}">${p.m}</span>`;
const fmtTag = (f, spec) => `<b class="dv-ft ${/FLAC|ALAC|WAV/.test(f) ? 'lossless' : ''} ${/24bit/.test(spec || '') ? 'hr' : ''}">${f}${/24bit/.test(spec || '') ? ' · 24bit' : ''}</b>`;
const mb = v => v >= 1000 ? (v / 1024).toFixed(1) + ' GB' : v.toFixed(1) + ' MB';

/* ---------------- 云盘首页 ---------------- */
function davServerCard() {
  const s = davSrv(), p = davPv(s.pv), off = S.dav.offline;
  return `<div class="m card dv-srv ${off ? 'off' : ''}" data-act="sheet" data-v="davServers">
    <div class="dv-srv-ic">${pvBadge(p, 44)}<i></i></div>
    <div class="dv-srv-tx"><b>${s.n}<span class="dv-chev">${ic('down')}</span></b>
      <small>${off ? '连接失败 · 401 未授权 · 3 分钟前' : `${p.n} · ${s.host} · ${s.ms}ms`}</small>
      ${off ? '' : `<div class="dv-cap"><i style="width:${s.used / s.total * 100}%"></i></div><small class="dv-capt">已用 ${s.used} / ${s.total} ${s.unit}</small>`}</div>
    <button class="ib" data-act="push" data-v="davServer" title="服务器设置">${ic('gear')}</button></div>
  ${off ? `<div class="m dv-offbar">${ic('alert')}<div><b>连不上「${s.n}」</b><small>账号或密码可能已修改。现在显示的是上次的索引，只能播放已缓存的 46 首。</small></div><button class="btn sm pri" data-act="davRetry">重试</button></div>` : ''}`;
}
function davEmpty() {
  return `${appBar('音乐云盘')}
  <div class="dv-hero"><div class="dv-hero-art"><i></i><i></i><i></i>${ic('cloud')}</div>
    <h2>播放 NAS 和网盘里的音乐</h2><p>连接 WebDAV 服务器，直接在线播放无损文件；收藏和歌单也可以备份到这里。不经过任何音乐平台。</p></div>
  <div class="dv-why m">${[['vinyl', '无损直播', 'FLAC / ALAC / WAV 原样播放，支持拖动进度'], ['image', '自动整理', '读取标签、同目录歌词和封面，按专辑 / 歌手归类'], ['refresh', '收藏备份', '收藏与歌单定时备份成 JSON，换手机一键恢复']].map(([i, t, d]) => `<div><span>${ic(i)}</span><b>${t}</b><small>${d}</small></div>`).join('')}</div>
  <div class="grp-t" style="padding-left:var(--pad)">选择你的服务</div>
  <div class="dv-prov m">${DAV_PROVIDERS.map((p, i) => `<button data-act="davStart" data-v="${i}">${pvBadge(p, 36)}<b>${p.n}</b><small>${p.d}</small></button>`).join('')}</div>
  <p class="hint" style="padding:14px var(--pad) 0">账号密码只保存在本机的系统钥匙串里，不会上传到 Lyra 服务器。</p>`;
}
function davMusic() {
  const s = davSrv(), sc = S.dav.scan, v = S.dav.view;
  const idx = sc ? `<div class="m card dv-scan"><div class="dv-scan-h"><i class="spinner sm"></i><b>正在扫描 ${sc.dir}</b><button class="chip" data-act="davScanStop">暂停</button></div>
      <div class="dv-bar"><i style="width:${sc.p * 100}%"></i></div>
      <small>已发现 ${sc.found} 首 · 读取标签 ${Math.round(sc.p * 100)}% · 只读取文件开头和结尾，不会下载整首</small></div>`
    : `<div class="m card dv-idx"><div class="dv-idx-n">${[[s.tracks.toLocaleString(), '首'], [s.albums, '张专辑'], [s.artists, '位歌手']].map(([n, u]) => `<div><b>${n}</b><small>${u}</small></div>`).join('')}</div>
      <div class="dv-idx-f"><small>${ic('clock')}上次扫描 ${s.scanned} · 新增 3 首</small><button class="btn sec sm" data-act="davScan">${ic('refresh')}扫描</button></div></div>`;
  const views = ['歌曲', '专辑', '歌手', '文件夹'];
  let body = '';
  if (v === '歌曲') body = `<div class="dv-acts"><button class="btn pri sm" data-act="playAll" data-list="all">${ic('play')}播放全部</button><button class="btn sec sm" data-act="playAll" data-list="all" data-shuffle="1">${ic('shuffle')}随机</button><span class="chip" data-act="toast" data-msg="可按最近添加 / 歌名 / 歌手 / 专辑排序" data-icon="sort">${ic('sort')}最近添加</span></div>
    ${DAV_RECENT.map(([id, f, spec]) => songRow(SONGS[id], { list:'all', tail:`${fmtTag(f, spec)}<button class="ib" data-act="sheet" data-v="davFile" data-id="${id}" style="color:var(--t3)">${ic('more')}</button>` })).join('')}
    <p class="hint" style="padding:10px var(--pad) 0">歌曲信息来自文件标签；没有标签的按「歌手 - 歌名」文件名识别${S.set.davMatch ? '，缺歌词和封面时从音乐平台补全' : ''}。</p>`;
  if (v === '专辑') body = `<div class="dv-albums">${[[0, '远光', 12, 'FLAC 24bit'], [2, '磁场', 10, 'FLAC'], [1, '潮汐', 9, 'FLAC'], [5, '不夜', 11, 'MP3'], [10, '慢速', 8, 'ALAC'], [16, 'Afterglow', 14, 'FLAC'], [6, '余温', 7, 'WAV'], [7, '光年', 10, 'FLAC 24bit']].map(([id, al, n, f], i) => { const x = SONGS[id]; return `<div class="dv-alb" data-act="push" data-v="davAlbum" data-id="${id}" style="--d:${i * 30}ms"><div class="cv" style="${coverStyle(x.h, x.v)}">${/24/.test(f) ? '<span class="dv-hr">Hi-Res</span>' : ''}</div><b>${al}</b><small>${x.a} · ${n} 首 · ${f.split(' ')[0]}</small></div>`; }).join('')}</div>`;
  if (v === '歌手') body = `<div>${[...new Set(SONGS.slice(0, 20).map(x => x.a))].slice(0, 9).map((a, i) => { const n = SONGS.filter(x => x.a === a).length * 7 + i; const x = SONGS.find(y => y.a === a); return `<div class="row" data-act="push" data-v="davAlbum" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, 1)};border-radius:24px"></div><div class="tx"><div class="t">${a}</div><div class="s"><span>${n} 首 · ${Math.max(1, Math.round(n / 9))} 张专辑</span></div></div><span style="color:var(--t3);padding-right:14px">${ic('right')}</span></div>`; }).join('')}</div>`;
  return `${idx}<div class="chips tight dv-views">${views.map(x => `<button class="chip ${x === v ? 'on' : ''}" data-act="davView" data-v="${x}">${x}</button>`).join('')}</div><div key="${v}">${body}</div>`;
}
function davFiles() {
  const path = S.dav.path, node = DAV_TREE[path] || DAV_TREE['/Music'], parts = path.split('/').filter(Boolean);
  const crumb = `<div class="dv-crumb">${parts.map((p, i) => { const to = '/' + parts.slice(0, i + 1).join('/'); return `${i ? `<span>${ic('right')}</span>` : ''}<button class="${i === parts.length - 1 ? 'on' : ''}" data-act="davCd" data-v="${to}">${i === 0 ? ic('server') : ''}${p}</button>`; }).join('')}</div>`;
  const total = node.f.length + node.a.length + (node.x || []).length;
  const tools = `<div class="dv-tools"><small>${node.f.length} 个文件夹 · ${node.a.length} 首可播放${node.x && node.x.length ? ` · ${node.x.length} 个不支持` : ''}</small>${node.a.length ? `<button class="chip on" data-act="playAll" data-list="all">${ic('play')}播放</button>` : ''}<span class="chip" data-act="davSortCycle">${ic('sort')}${S.dav.sort}</span><button class="ib" data-act="sheet" data-v="davFolder">${ic('more')}</button></div>`;
  const folders = node.f.map(([n, d]) => `<div class="dv-row" data-act="davCd" data-v="${path}/${n}"><span class="dv-fi">${ic('folder')}</span><div class="dv-tx"><b>${n}</b><small>${d}</small></div><span class="dv-go">${ic('right')}</span></div>`).join('');
  const files = node.a.map(([fn, id, f, spec, size, side]) => { const x = SONGS[id];
    return `<div class="dv-row file" data-act="play" data-id="${id}" data-list="all">${cover(x, 'dv-cv')}<div class="dv-tx"><b>${fn}</b><small>${fmtTag(f, spec)}<span>${spec} · ${mb(size)} · ${fmt(x.dur)}</span></small></div>
      <span class="dv-side">${side.includes('lrc') ? `<i title="同目录歌词">${ic('quote')}</i>` : ''}${side.includes('cover') ? `<i title="同目录封面">${ic('image')}</i>` : ''}</span>
      <button class="ib" data-act="sheet" data-v="davFile" data-id="${id}" style="color:var(--t3)">${ic('more')}</button></div>`; }).join('');
  const bad = (node.x || []).map(([fn, f, size]) => `<div class="dv-row off" data-act="toast" data-msg="${f} 需要额外的解码器，暂不支持播放；可以在电脑上转成 FLAC" data-icon="info"><span class="dv-fi">${ic('file')}</span><div class="dv-tx"><b>${fn}</b><small><b class="dv-ft">${f}</b><span>${mb(size)} · 暂不支持播放</span></small></div><span class="dv-go">${ic('info')}</span></div>`).join('');
  const other = node.o ? `<div class="dv-other">${ic('layers')}另有 ${node.o} 个非音频文件（封面图、.lrc 歌词、.cue），已自动关联到同名歌曲</div>` : '';
  return `${crumb}${tools}<div class="m card dv-list">${folders}${files}${bad}${total ? '' : '<div class="dv-emptydir">这个文件夹里没有音乐</div>'}</div>${other}`;
}
function davBackup() {
  const bk = S.dav.backing;
  return `<div class="m card dv-bk-st">
      <div class="dv-bk-ic">${ic(bk ? 'upload' : 'check')}</div>
      <div style="flex:1;min-width:0"><b>${bk ? `正在备份… ${Math.round(bk * 100)}%` : '上次备份 · 今天 03:00'}</b><small>${bk ? '上传 lyra-backup-20261102-1530.json 到 /Lyra/backups' : `${davSrv().n} · 收藏 128 首 · 歌单 14 个 · 182 KB`}</small>
        ${bk ? `<div class="dv-bar"><i style="width:${bk * 100}%"></i></div>` : ''}</div>
      ${bk ? '' : `<button class="btn pri sm" data-act="davBackupNow">${ic('upload')}立即备份</button>`}</div>
    ${group('自动备份', [
      item({ icon:'refresh', color:'teal', label:'每天自动备份', sub:'打开 App 时检查，距上次超过 24 小时就备份', sw:'davBkAuto' }),
      item({ icon:'wifi', color:'blue', label:'只在 Wi-Fi 下备份', sw:'davBkWifi' }),
      item({ icon:'history', color:'violet', label:'保留份数', val:'最近 7 份', act:'toast', args:{ msg:'可选 3 / 7 / 30 份，超出后自动删除最旧的', icon:'history' } }),
      item({ icon:'folder', color:'orange', label:'备份位置', val:'/Lyra/backups', act:'sheet', args:{ v:'davPick' } }),
    ], '备份内容是收藏、歌单和设置的 JSON，与「账号备份」格式相同，桌面端也能读取；不包含音频文件。')}
    <div class="grp-t" style="padding-left:var(--pad)">历史备份 · ${DAV_BACKUPS.length} 份</div>
    <div class="grp">${DAV_BACKUPS.map(([t, by, like, pl, size], i) => `<div class="it" data-act="davRestore" data-v="${i}"><div class="tile" style="background:${i ? TILE.gray : TILE.green}">${ic('cloud')}</div><div class="lb"><b>${t}</b><small>${by} · 收藏 ${like} · 歌单 ${pl} · ${size}</small></div><div class="val">恢复${ic('right')}</div></div>`).join('')}</div>`;
}
PAGES.cloud = { render:() => {
  if (!S.dav.servers.length) return davEmpty();
  const segs = ['音乐', '文件', '备份'];
  const body = [davMusic, davFiles, davBackup][S.davSeg]();
  return `${appBar('音乐云盘', { right:`<button class="ib" data-act="push" data-v="davAdd">${ic('plus')}</button>` })}
    ${davServerCard()}
    <div style="margin:2px 0 8px">${seg(segs, segs[S.davSeg], 'davSeg3')}</div>
    <div class="segbody" key="${S.davSeg}">${body}</div>`;
} };

/* ---------------- 添加服务器：选择服务 → 填写 → 测试 ---------------- */
function davTestCard() {
  const t = S.davAdd.test, p = davPv(DAV_PROVIDERS[S.davAdd.pv].id);
  if (t === 'idle') return '';
  if (t === 'testing') return `<div class="dv-test ing"><i class="spinner sm"></i><div><b>正在连接…</b><small>读取根目录 · 检查 Range 支持</small></div></div>`;
  if (t === 'ok') return `<div class="dv-test ok">${ic('check')}<div><b>连接成功 · 92ms</b><small>${p.id === 'syno' ? 'Synology WebDAV Server' : p.n} · 可用空间 2.4 TB</small>
    <ul><li>${ic('check')}可以列目录</li><li>${ic('check')}支持断点续传（可拖动进度）</li><li>${ic('check')}可以写入（用于备份）</li></ul></div></div>`;
  if (t === 'auth') return `<div class="dv-test bad">${ic('lock')}<div><b>账号或密码不正确（401）</b><small>${p.id === 'jgy' ? '坚果云必须用「应用密码」，不能用登录密码。' : '请检查用户名和密码；开了两步验证的服务需要用应用密码。'}</small>${p.id === 'jgy' ? `<button class="chip" data-act="toast" data-msg="已在浏览器打开坚果云安全选项" data-icon="ext">${ic('ext')}去生成应用密码</button>` : ''}</div></div>`;
  if (t === 'cert') return `<div class="dv-test warn">${ic('shield')}<div><b>证书不受信任</b><small>这台服务器用的是自签名证书（NAS 常见）。确认是你自己的设备后，可以只信任这一张证书。</small><button class="chip" data-act="dialog" data-v="davCert">${ic('eye')}查看证书</button></div></div>`;
  return `<div class="dv-test bad">${ic('wifi')}<div><b>连接超时</b><small>检查地址和端口；手机和 NAS 不在同一个局域网时，需要 DDNS、端口转发或 QuickConnect 之类的外网地址。</small></div></div>`;
}
PAGES.davAdd = { render:() => {
  const a = S.davAdd, p = DAV_PROVIDERS[a.pv];
  if (a.step === 0) return `${appBar('添加服务器')}
    <div class="dv-steps"><b class="on">1 选择服务</b><i></i><b>2 填写账号</b></div>
    <div class="dv-prov list m">${DAV_PROVIDERS.map((x, i) => `<button class="${i === a.pv ? 'on' : ''}" data-act="davPick1" data-v="${i}">${pvBadge(x, 40)}<div><b>${x.n}</b><small>${x.d}</small></div>${ic('right')}</button>`).join('')}</div>
    <p class="hint" style="padding:14px var(--pad) 0">没有 WebDAV？群晖、威联通、Nextcloud、Alist 都自带；阿里云盘、115 等可以通过 Alist 挂成 WebDAV。</p>`;
  const ok = a.test === 'ok';
  return `${appBar(`添加 · ${p.n}`)}
    <div class="dv-steps"><b data-act="davBack0">1 选择服务</b><i class="on"></i><b class="on">2 填写账号</b></div>
    <div class="note">${ic('info')}<span>${p.tip}</span></div>
    <div class="dv-form m">
      <label>名称</label><div class="fld">${ic('edit')}<input value="${p.id === 'syno' ? '家里的 NAS' : p.n}"></div>
      <label>服务器地址</label><div class="fld">${ic('globe')}<input value="${p.url}"></div>
      <label>用户名</label><div class="fld">${ic('user')}<input value="${a.test === 'idle' ? '' : 'ali'}" placeholder="用户名 / 邮箱"></div>
      <label>${p.id === 'jgy' ? '应用密码' : '密码'}</label><div class="fld ${a.test === 'auth' ? 'err' : ''}">${ic('lock')}<input type="password" value="${a.test === 'idle' ? '' : 'xxxxxxxx'}" placeholder="${p.id === 'jgy' ? '在坚果云生成的应用密码' : '密码 / 应用专用密码'}">${ic('eye')}</div>
      <label>音乐目录</label><div class="fld" data-act="${ok ? 'sheet' : 'toast'}" data-v="davPick" data-msg="连接成功后可以浏览选择" data-icon="folder">${ic('folder')}<input value="${ok ? '/Music' : '/'}" readonly><span class="dv-sel">${ok ? '选择' : ''}${ic('right')}</span></div>
    </div>
    <button class="dv-adv m" data-act="davAdv">${ic(a.adv ? 'up' : 'down')}高级选项</button>
    ${a.adv ? group('', [
      item({ icon:'shield', color:'orange', label:'允许自签名证书', sub:'只信任这台服务器的这一张证书（记住指纹），证书变了会再次询问', sw:'davSelf' }),
      item({ icon:'clock', color:'gray', label:'请求超时', val:'15 秒', act:'toast', args:{ msg:'可选 10 / 15 / 30 秒', icon:'clock' } }),
      item({ icon:'zap', color:'gold', label:'并发连接数', val:'2', act:'toast', args:{ msg:'坚果云等有频率限制的服务建议保持 1–2', icon:'zap' } }),
    ]) : ''}
    ${davTestCard()}
    <div class="dv-foot m"><button class="btn sec" data-act="davTest">${ic('wifi')}测试连接</button><button class="btn ${ok ? 'pri' : 'sec dim'}" data-act="davSave">保存</button></div>`;
} };

/* ---------------- 服务器设置 ---------------- */
PAGES.davServer = { render:() => {
  const s = davSrv(), p = davPv(s.pv);
  return `${appBar('服务器设置')}
    <div class="m card dv-srvd">${pvBadge(p, 52)}<div style="flex:1;min-width:0"><b>${s.n}</b><small>${p.n} · ${s.host}</small><div class="dv-pills"><span class="ok">${ic('check')}已连接 ${s.ms}ms</span><span>${s.tracks.toLocaleString()} 首</span><span>已用 ${s.used}/${s.total} ${s.unit}</span></div></div></div>
    ${group('连接', [
      item({ icon:'edit', color:'violet', label:'名称', val:s.n, act:'toast', args:{ msg:'修改名称', icon:'edit' } }),
      item({ icon:'globe', color:'blue', label:'地址', val:s.host, act:'toast', args:{ msg:'修改地址后会重新测试连接', icon:'globe' } }),
      item({ icon:'user', color:'teal', label:'账号', val:s.user, act:'toast', args:{ msg:'修改账号或密码', icon:'lock' } }),
      item({ icon:'shield', color:s.cert === 'self' ? 'orange' : 'green', label:'证书', sub:s.cert === 'self' ? '自签名 · 已信任 · SHA-256 3A:7F:…:C2' : '受信任的证书', val:'', act:'dialog', args:{ v:'davCert' } }),
    ])}
    ${group('音乐', [
      item({ icon:'folder', color:'orange', label:'音乐目录', val:s.root, act:'sheet', args:{ v:'davPick' } }),
      item({ icon:'refresh', color:'green', label:'打开云盘时增量扫描', sub:'只看有变化的文件夹（按修改时间）', sw:'davAutoScan' }),
      item({ icon:'wifi', color:'blue', label:'只在 Wi-Fi 下扫描', sw:'davScanWifi' }),
      item({ icon:'image', color:'pink', label:'从音乐平台补全歌词和封面', sub:'文件里没有、同目录也没有时，按歌名和歌手去平台找', sw:'davMatch' }),
      item({ icon:'trash', color:'gray', label:'重建索引', sub:`上次完整扫描 ${s.scanned}`, act:'toast', args:{ msg:'已清空索引，重新扫描中', icon:'refresh' } }),
    ])}
    ${group('缓存', [
      item({ icon:'download', color:'teal', label:'边听边缓存', sub:`已缓存 ${s.cache} GB · 上限 4 GB，满了先清最久没听的`, sw:'davCacheOn' }),
      item({ icon:'storage', color:'gray', label:'清除这台服务器的缓存', val:`${s.cache} GB`, act:'toast', args:{ msg:'已清除缓存', icon:'trash' } }),
    ], '离线时只能播放已缓存的歌；「下载到本机」的歌曲在「下载管理」里，不受上限影响。')}
    ${S.dav.cur !== 'nas' ? '' : group('', [item({ icon:'check', color:'blue', label:'设为当前服务器', val:'当前', chev:false })])}
    ${group('', [item({ icon:'trash', color:'red', label:'删除这台服务器', danger:true, chev:false, act:'dialog', args:{ v:'davDel' } })])}`;
} };

/* ---------------- 专辑详情（按目录 + 标签归类） ---------------- */
PAGES.davAlbum = { render:p => {
  const x = SONGS[p.id ?? 0], ids = [x.id, ...SONGS.filter(y => y.al === x.al && y.id !== x.id).map(y => y.id), 6, 12].slice(0, 8);
  return `${appBar(x.al, { fade:true, right:`<button class="ib" data-act="sheet" data-v="davFolder">${ic('more')}</button>` })}
    <div class="dv-ah"><div class="cv" style="${coverStyle(x.h, x.v)}"></div><h2>${x.al}</h2><span>${x.a} · 2025</span>
      <div class="dv-pills center"><span>${ids.length} 首</span><span class="hr">FLAC · 24bit/96kHz</span><span>612 MB</span></div>
      <small class="dv-path">${ic('folder')}/Music/无损/${x.a} - ${x.al} · 封面来自 folder.jpg</small></div>
    <div class="dv-acts center"><button class="btn pri" data-act="playAll" data-list="all">${ic('play')}播放</button><button class="ib big" data-act="playAll" data-list="all" data-shuffle="1">${ic('shuffle')}</button><button class="ib big" data-act="toast" data-msg="已加入下载 · ${ids.length} 首" data-icon="download">${ic('download')}</button><button class="ib big" data-act="sheet" data-v="addTo">${ic('plus')}</button></div>
    <div>${ids.map((id, i) => songRow(SONGS[id], { num:i, noCover:true, list:'all', tail:`<span class="dv-dur">${fmt(SONGS[id].dur)}</span><button class="ib" data-act="sheet" data-v="davFile" data-id="${id}" style="color:var(--t3)">${ic('more')}</button>` })).join('')}</div>`;
} };

/* ---------------- 面板 ---------------- */
SHEETS.davServers = () => ({ t:'切换服务器', body:`<div class="grp" style="margin-top:4px">${S.dav.servers.map(s => { const p = davPv(s.pv); return `<div class="it" data-act="davSwitch" data-v="${s.id}">${pvBadge(p, 30)}<div class="lb"><b>${s.n}</b><small>${p.n} · ${s.host} · ${s.tracks} 首</small></div><div class="val">${s.id === S.dav.cur ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : `${s.ms}ms`}</div></div>`; }).join('')}
  <div class="it" data-act="push" data-v="davAdd"><div class="tile" style="background:${TILE.gray}">${ic('plus')}</div><div class="lb"><b>添加服务器</b><small>坚果云 / Alist / Nextcloud / 群晖 / 威联通</small></div></div></div>
  <p class="hint" style="padding:0 var(--pad)">每台服务器的索引、缓存分开保存；切换后音乐库「本地 → 云盘」显示当前服务器的歌。</p>` });
SHEETS.davFile = () => { const x = SONGS[S.sheet.id] || SONGS[0], row = Object.values(DAV_TREE).flatMap(n => n.a).find(a => a[1] === x.id) || [`${x.a} - ${x.t}.flac`, x.id, 'FLAC', '16bit/44.1kHz', 30.2, []];
  return { t:'', head:`<div class="dv-fh">${cover(x, '', 56)}<div style="min-width:0"><b>${x.t}</b><small>${x.a} · ${x.al}</small><small class="dv-path">${ic('folder')}${row[0]}</small></div></div>`, body:`<div class="grp">${[
    ['play', 'blue', '播放', 'play'], ['next', 'violet', '下一首播放', 'rowNext'], ['plus', 'green', '加入歌单', 'addTo'], ['heart', 'red', '收藏到「我喜欢」', 'like'],
    ['download', 'teal', '下载到本机', 'dl'], ['info', 'gray', '文件信息', 'info'], ['link', 'orange', '复制文件地址', 'copy'],
  ].map(([i, c, n, k]) => `<div class="it" data-act="davFileAct" data-v="${k}" data-id="${x.id}"><div class="tile" style="background:${TILE[c]}">${ic(i)}</div><div class="lb"><b>${n}</b>${k === 'dl' ? `<small>${row[2]} · ${mb(row[4])} · 下载后离线也能听</small>` : ''}</div></div>`).join('')}</div>` }; };
SHEETS.davInfo = () => { const x = SONGS[S.sheet.id] || SONGS[0];
  const rows = [['文件', `/Music/无损/${x.a} - ${x.t}.flac`], ['格式', 'FLAC · 24bit / 96kHz · 双声道'], ['码率', '3,412 kbps'], ['大小', '98.4 MB'], ['时长', fmt(x.dur)], ['修改时间', '2026-10-18 22:41'],
    ['歌名 / 歌手', `${x.t} / ${x.a}　<em>内嵌标签</em>`], ['专辑', `${x.al}　<em>内嵌标签</em>`], ['封面', '<em>同目录 cover.jpg</em>'], ['歌词', '<em>同名 .lrc（含翻译）</em>']];
  return { t:'文件信息', body:`<div class="m card dv-info">${rows.map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join('')}</div>
    <p class="hint" style="padding:10px var(--pad) 0">信息来源的优先级：文件内嵌标签 → 同目录的 .lrc 和封面图 → 文件名「歌手 - 歌名」→ 音乐平台补全（可在服务器设置里关闭）。</p>
    <div style="padding:12px var(--pad) 0"><button class="btn sec block" data-act="sheetToast" data-msg="已用文件名重新识别" data-icon="refresh">${ic('edit')}信息不对？改为按文件名识别</button></div>` }; };
SHEETS.davFolder = () => ({ t:S.dav.path.split('/').pop() || '/', sub:'文件夹', body:`<div class="grp">${[
  ['play', 'blue', '播放全部', '按文件名顺序，包含子文件夹', '已开始播放 · 128 首', 'play'], ['shuffle', 'violet', '随机播放', '', '随机播放 · 128 首', 'shuffle'],
  ['plus', 'green', '全部加入歌单', '', '已加入「车载」· 128 首', 'plus'], ['download', 'teal', '下载整个文件夹', '约 3.8 GB · 只在 Wi-Fi 下下载', '已加入下载队列 · 128 首', 'download'],
  ['refresh', 'orange', '重新扫描这个文件夹', '读取新文件和修改过的标签', '正在扫描 /Music/无损', 'refresh'], ['pin', 'gold', '设为音乐目录', '扫描和「音乐」页只看这个文件夹', '已设为音乐目录', 'pin'],
].map(([i, c, n, d, msg, icn]) => `<div class="it" data-act="sheetToast" data-msg="${msg}" data-icon="${icn}"><div class="tile" style="background:${TILE[c]}">${ic(i)}</div><div class="lb"><b>${n}</b>${d ? `<small>${d}</small>` : ''}</div></div>`).join('')}</div>` });
SHEETS.davPick = () => ({ t:'选择文件夹', sub:davSrv().n, body:`<div class="dv-crumb sheet"><button>${ic('server')}根目录</button><span>${ic('right')}</span><button class="on">Music</button></div>
  <div class="grp">${['无损', 'Live 现场', '车载', '新下载', 'Hi-Res 母带'].map(n => `<div class="it" data-act="toast" data-msg="打开 /Music/${n}" data-icon="folder"><div class="tile" style="background:${TILE.blue}">${ic('folder')}</div><div class="lb"><b>${n}</b></div><div class="val">${ic('right')}</div></div>`).join('')}</div>
  <div style="padding:0 var(--pad);display:flex;gap:10px"><button class="btn sec" style="flex:1" data-act="sheetToast" data-msg="已新建文件夹" data-icon="plus">${ic('plus')}新建文件夹</button><button class="btn pri" style="flex:1.4" data-act="sheetToast" data-msg="已选择 /Music" data-icon="check">选择「/Music」</button></div>` });
// 云盘歌曲的播放链路（播放器 → ··· → 播放链路）
const _trace = SHEETS.trace;
SHEETS.trace = () => {
  if (!S.davPlaying) return _trace();
  return { t:'播放链路', sub:song().t, dark:S.playerOpen, body:`<div style="padding:0 var(--pad)">
    <div class="dv-chain">${[['ok', '00:00.000', 'WebDAV · 家里的 NAS', 'GET /Music/无损/雾港 - 夜航星图.flac', '206 部分内容 · Range: bytes=0-'], ['ok', '00:00.086', '解码', 'FLAC 24bit/96kHz', '开始播放 · 首包 512 KB'], ['ok', '00:00.120', '歌词', '同名 .lrc', '已加载 · 含翻译'], ['warn', '00:12.400', '缓存', '边听边存', '已缓存 38% · 上限 4 GB']].map(([t, ts, src, a, r]) => `<div class="dv-ch ${t}"><i></i><div><small>${ts} · ${src}</small><b>${a}</b><span>${r}</span></div></div>`).join('')}</div>
    <p class="hint" style="padding-top:8px">云盘歌曲直接从你的服务器读取，不经过音源脚本，也不受智能换源影响。</p></div>` };
};

/* ---------------- 弹窗 ---------------- */
FORM_DIALOGS.davCert = () => `<h3 class="fd-t">信任这张证书？</h3><p class="fd-s">nas.local:5006 的证书不是公共机构签发的。只有确认这是你自己的设备时才信任。</p>
  <div class="m card dv-info" style="margin:14px 0 0">${[['颁发给', 'nas.local'], ['颁发者', 'Synology Inc. (自签名)'], ['有效期', '2025-03-02 至 2027-03-02'], ['SHA-256', '3A:7F:1C:9E:44:B0:…:8D:C2']].map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join('')}</div>
  <p class="fd-s" style="margin-top:10px">信任后只认这一个指纹；证书一旦变化会再次询问，防止被人冒充。</p>
  <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn pri" data-act="davTrust">信任并继续</button></div>`;
FORM_DIALOGS.davRestore = () => { const b = DAV_BACKUPS[S.dlg.i || 0], mode = S.dlg.mode || 'merge';
  return `<h3 class="fd-t">从备份恢复</h3><p class="fd-s">${b[0]} · ${b[1]}</p>
  <div class="fd-stat" style="margin:12px 0 4px"><span><b>${b[2]}</b>首收藏</span><span><b>${b[3]}</b>个歌单</span><span><b>${b[4]}</b></span></div>
  <div class="dv-mode">${[['merge', '合并', '保留本机现有的，补上备份里多出来的（推荐）'], ['replace', '覆盖', '本机的收藏和歌单换成备份里的内容']].map(([k, n, d]) => `<button class="${mode === k ? 'on' : ''}" data-act="davRMode" data-v="${k}"><i></i><div><b>${n}</b><small>${d}</small></div></button>`).join('')}</div>
  <p class="fd-s" style="margin-top:10px">${ic('shield')} 恢复前会先把本机当前的数据备份一份，恢复错了也能找回。</p>
  <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn ${mode === 'replace' ? 'danger' : 'pri'}" data-act="davRestoreGo">${mode === 'replace' ? '覆盖恢复' : '合并恢复'}</button></div>`; };
DIALOGS.davDel = { i:'trash', t:'删除「家里的 NAS」？', p:'会删除这台服务器的账号、索引和 1.1 GB 缓存。服务器上的文件不受影响；已加入歌单和收藏的云盘歌曲会显示为「不可用」。', a:[['取消', 'closeDialog', 'sec'], ['删除', 'davDelGo', 'danger']] };

/* ---------------- 动作 ---------------- */
Object.assign(ACT, {
  davSeg3: d => { S.davSeg = ['音乐', '文件', '备份'].indexOf(d.v); S._stagger = true; render(); },
  davView: d => { if (d.v === '文件夹') { S.davSeg = 1; S._stagger = true; return render(); } S.dav.view = d.v; S._stagger = true; render(); },
  davCd: d => { S.dav.path = d.v; S._stagger = true; render(); const p = topPage(); p && p.scrollTo({ top:0 }); },
  davSortCycle: () => { const o = ['名称', '最近添加', '歌手']; S.dav.sort = o[(o.indexOf(S.dav.sort) + 1) % o.length]; render(); toast(`按${S.dav.sort}排序`, 'sort'); },
  davScan: () => { S.dav.scan = { dir:'/Music/无损', found:0, p:0 }; render(); const t = setInterval(() => { if (!S.dav.scan) return clearInterval(t); S.dav.scan.p = Math.min(1, S.dav.scan.p + .12); S.dav.scan.found += 41; if (S.dav.scan.p >= 1) { clearInterval(t); S.dav.scan = null; toast('扫描完成 · 新增 3 首，更新 2 个标签', 'check'); } render(); }, 450); },
  davScanStop: () => { S.dav.scan = null; render(); toast('已暂停扫描，下次打开时继续', 'pause'); },
  davRetry: () => { S.dav.offline = false; render(); toast('已重新连接 · 86ms', 'wifi'); },
  davSwitch: d => { S.dav.cur = d.v; S.sheet = null; S.dav.path = '/Music'; render(); toast(`已切换到「${davSrv().n}」`, 'server'); },
  davStart: d => { S.davAdd = { step:1, pv:+d.v, test:'idle', adv:false }; ACT.push({ v:'davAdd' }); },
  davPick1: d => { S.davAdd.pv = +d.v; S.davAdd.step = 1; S.davAdd.test = 'idle'; render(); },
  davBack0: () => { S.davAdd.step = 0; render(); },
  davAdv: () => { S.davAdd.adv = !S.davAdd.adv; render(); },
  davTest: () => { S.davAdd.test = 'testing'; render(); setTimeout(() => { if (S.davAdd.test !== 'testing') return; const pv = DAV_PROVIDERS[S.davAdd.pv].id; S.davAdd.test = pv === 'syno' ? 'cert' : 'ok'; render(); }, 1100); },
  davTrust: () => { S.dialog = null; S.davAdd.test = 'ok'; render(); toast('已信任这张证书', 'shield'); },
  davSave: () => { if (S.davAdd.test !== 'ok') return toast('先测试连接，成功后才能保存', 'info'); S.stack = [{ id:'cloud' }]; S.davSeg = 0; S.dav.scan = { dir:'/Music', found:0, p:.05 }; render(); toast('已添加服务器，开始扫描音乐目录', 'cloud'); },
  davBackupNow: () => { S.dav.backing = .1; render(); const t = setInterval(() => { S.dav.backing += .3; if (S.dav.backing >= 1) { clearInterval(t); S.dav.backing = null; toast('已备份 · 182 KB', 'cloud'); } render(); }, 380); },
  davRestore: d => { S.dlg = { i:+d.v, mode:'merge' }; S.dialog = 'davRestore'; render(); },
  davRMode: d => { S.dlg.mode = d.v; render(); },
  davRestoreGo: () => { const m = S.dlg.mode; S.dialog = null; render(); toast(m === 'replace' ? '已覆盖恢复 · 恢复前的数据已另存一份' : '已合并 · 新增收藏 3 首、歌单 1 个', 'check'); },
  davDelGo: () => { S.dialog = null; S.dav.servers = S.dav.servers.filter(x => x.id !== S.dav.cur); S.dav.cur = S.dav.servers[0]?.id; S.stack = [{ id:'cloud' }]; render(); toast('已删除服务器', 'trash'); },
  davFileAct: d => {
    const k = d.v, id = +d.id;
    if (k === 'info') { S.sheet = { v:'davInfo', id }; return render(); }
    if (k === 'addTo') { S.sheet = { v:'addTo', id }; return render(); }
    S.sheet = null;
    if (k === 'play') { playSong(id, 'all'); S.davPlaying = true; render(); return toast('从「家里的 NAS」播放', 'cloud'); }
    if (k === 'rowNext') { render(); return toast(`「${SONGS[id].t}」将在下一首播放`, 'next'); }
    if (k === 'like') { S.liked.add(id); render(); return toast('已添加到「我喜欢」', 'heartf'); }
    render(); toast({ dl:'已加入下载队列', copy:'已复制 WebDAV 地址（不含密码）' }[k], k === 'dl' ? 'download' : 'copy');
  },
});

/* ---------------- 音乐库 · 本地：本机 / 云盘 ---------------- */
const _libR = PAGES.library.render;
PAGES.library.render = () => {
  let h = _libR();
  if (S.libSeg !== 'local') return h;
  const s = davSrv();
  const card = s ? `<div class="m card dv-libcard" data-act="push" data-v="cloud">${pvBadge(davPv(s.pv), 42)}<div style="flex:1;min-width:0"><b>云盘 · ${s.n}</b><small>${s.tracks.toLocaleString()} 首 · ${s.albums} 张专辑 · 上次扫描 ${s.scanned}</small></div><span class="dv-go">${ic('right')}</span></div>`
    : `<div class="m card dv-libcard add" data-act="push" data-v="cloud"><span class="dv-fi">${ic('cloud')}</span><div style="flex:1"><b>连接 NAS 或网盘</b><small>WebDAV · 在线播放服务器上的音乐</small></div><span class="dv-go">${ic('right')}</span></div>`;
  return h.replace('<div style="display:flex;gap:8px;padding:14px var(--pad) 4px"><span class="chip on">歌曲</span>', `${card}<div style="display:flex;gap:8px;padding:14px var(--pad) 4px"><span class="chip on">歌曲</span>`);
};

/* ---------------- 目录（main.js 读取） ---------------- */
const davSet = fn => () => { S.stack = [{ id:'cloud' }]; fn && fn(); };
const davAddAt = (step, pv, test, extra) => () => { S.stack = [{ id:'davAdd' }]; S.davAdd = { step, pv, test, adv:false }; extra && extra(); };
const DAV_JUMPS = [
  ['云盘 · 未添加服务器', davSet(() => { S.dav.servers = []; })],
  ['云盘 · 音乐 · 歌曲', davSet()],
  ['云盘 · 音乐 · 专辑', davSet(() => { S.dav.view = '专辑'; })],
  ['云盘 · 音乐 · 歌手', davSet(() => { S.dav.view = '歌手'; })],
  ['云盘 · 正在扫描', davSet(() => { S.dav.scan = { dir:'/Music/无损', found:312, p:.45 }; })],
  ['云盘 · 文件 · 根目录', davSet(() => { S.davSeg = 1; })],
  ['云盘 · 文件 · 子文件夹（含不支持格式）', davSet(() => { S.davSeg = 1; S.dav.path = '/Music/无损'; })],
  ['云盘 · 文件操作', davSet(() => { S.davSeg = 1; S.dav.path = '/Music/无损'; S.sheet = { v:'davFile', id:11 }; })],
  ['云盘 · 文件信息', davSet(() => { S.davSeg = 1; S.sheet = { v:'davInfo', id:0 }; })],
  ['云盘 · 文件夹操作', davSet(() => { S.davSeg = 1; S.dav.path = '/Music/无损'; S.sheet = { v:'davFolder' }; })],
  ['云盘 · 专辑详情', () => { S.stack = [{ id:'cloud' }, { id:'davAlbum', params:{ id:0 } }]; }],
  ['云盘 · 切换服务器', davSet(() => { S.sheet = { v:'davServers' }; })],
  ['云盘 · 连接失败（离线）', davSet(() => { S.dav.offline = true; })],
  ['云盘 · 备份', davSet(() => { S.davSeg = 2; })],
  ['云盘 · 正在备份', davSet(() => { S.davSeg = 2; S.dav.backing = .62; })],
  ['云盘 · 从备份恢复', davSet(() => { S.davSeg = 2; S.dlg = { i:0, mode:'merge' }; S.dialog = 'davRestore'; })],
  ['添加服务器 · 选择服务', davAddAt(0, 3, 'idle')],
  ['添加服务器 · 填写（坚果云）', davAddAt(1, 0, 'idle')],
  ['添加服务器 · 测试中', davAddAt(1, 1, 'testing')],
  ['添加服务器 · 连接成功', davAddAt(1, 1, 'ok')],
  ['添加服务器 · 应用密码错误', davAddAt(1, 0, 'auth')],
  ['添加服务器 · 自签名证书', davAddAt(1, 3, 'cert', () => { S.davAdd.adv = true; })],
  ['添加服务器 · 信任证书', davAddAt(1, 3, 'cert', () => { S.dialog = 'davCert'; })],
  ['添加服务器 · 连接超时', davAddAt(1, 4, 'timeout')],
  ['添加服务器 · 选择音乐目录', davAddAt(1, 3, 'ok', () => { S.sheet = { v:'davPick' }; })],
  ['服务器设置', () => { S.stack = [{ id:'cloud' }, { id:'davServer' }]; }],
  ['删除服务器确认', () => { S.stack = [{ id:'cloud' }, { id:'davServer' }]; S.dialog = 'davDel'; }],
  ['音乐库 · 本地（含云盘入口）', () => { S.tab = 'library'; S.libSeg = 'local'; S.azLetter = null; }],
  ['播放器 · 云盘歌曲播放链路', () => { S.playerOpen = true; S.skin = 'vinyl'; S.davPlaying = true; S.sheet = { v:'trace', id:S.cur }; }],
];
