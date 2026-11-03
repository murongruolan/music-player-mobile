/* 入口：左侧目录（跳转到任意页面/状态）+ 总览模式（所有页面平铺）+ 启动。 */
function reset() {
  if (typeof davReset === 'function') davReset();
  Object.assign(S, { authed:true, stack:[], sheet:null, dialog:null, playerOpen:false, lyricMode:false, amView:'cover', searchQ:'', matchState:'listen', scanMode:'scan', scanResult:null, picker:false, loading:false, navMin:false, clip:null, forgotStep:0, dlg:{}, qFocus:false, searchDone:false, rType:'综合', rPlat:'all', skinTab:'全部', davSeg:0, bar:S.bar, myPlSeg:0, platLogin:{ netease:'小栗子' }, plat:'netease', script:'auto', amWave:'spring', _anim:null, _playerAnim:false, _lyrIdx:-1, tab:'discover' });
}
const tabTo = t => () => { S.tab = t; };
const pushTo = (id, params = {}) => () => { S.stack = [{ id, params }]; };
const playerSkin = (sk, extra) => () => { S.playerOpen = true; S.skin = sk; S.pos = 34; if (extra) extra(); };
const sheetOn = (v, inPlayer = true) => () => { if (inPlayer) { S.playerOpen = true; S.skin = 'vinyl'; } S.sheet = { v, id:S.cur }; };
const scanTo = (mode, res, extra) => () => { S.stack = [{ id:'scan' }]; S.scanMode = mode; S.scanResult = res; if (extra) extra(); };
const A = (o) => Object.assign(S.auth, { err:{}, capOk:false, clicks:[], cap:'', code:'', pwd:'', pwd2:'', done:false, busy:false, cd:0, capMode:'text' }, o);
const JUMPS = [
  ['入门与账号', [
    ['使用须知', () => { S.authed = false; S.authPage = 'disclaimer'; }],
    ['登录', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '登录'; A({ id:'ali@example.com' }); }],
    ['登录 · 输入错误', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '登录'; A({ id:'', err:{ id:'请输入邮箱或用户 ID', pwd:'密码至少 6 位' } }); }],
    ['注册 · 图形字符验证', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '注册'; A({ email:'ali@example.com', pwd:'Night2026', capMode:'text' }); }],
    ['注册 · 滑块拼图验证', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '注册'; A({ email:'ali@example.com', pwd:'Night2026', capMode:'slide' }); }],
    ['注册 · 文字点选验证', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '注册'; A({ email:'ali@example.com', pwd:'Night2026', capMode:'click', clicks:[[54, 40]] }); }],
    ['注册 · 验证通过', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '注册'; A({ email:'ali@example.com', pwd:'Night2026!', capMode:'slide', capOk:true, code:'482915', cd:48 }); S.agree = true; }],
    ['注册 · 成功', () => { S.authed = false; S.authPage = 'login'; S.loginSeg = '注册'; A({ email:'ali@example.com', done:true }); }],
    ['找回密码 · 验证身份', () => { S.authed = false; S.authPage = 'forgot'; S.forgotStep = 0; A({ email:'ali@example.com', capMode:'click' }); }],
    ['找回密码 · 重设', () => { S.authed = false; S.authPage = 'forgot'; S.forgotStep = 1; A({ email:'ali@example.com', pwd:'Night', pwd2:'' }); }],
    ['找回密码 · 完成', () => { S.authed = false; S.authPage = 'forgot'; S.forgotStep = 2; A({}); }],
    ['版本停用', () => { S.authed = false; S.authPage = 'versionDisabled'; }],
  ]],
  ['主界面（5 个 Tab）', [
    ['发现 · 网易云已登录', tabTo('discover')], ['发现 · 网易云平台推荐区', () => { S._scrollTo = 1250; }], ['发现 · QQ音乐已登录', () => { S.plat = 'qq'; S.platLogin.qq = '阿栗'; }], ['发现 · 平台未登录', () => { S.plat = 'kugou'; }], ['平台登录 · 扫码', () => { S.plat = 'kugou'; S.dlg = { plat:'kugou', st:0, mode:'扫码' }; S.sheet = { v:'platLogin' }; }], ['平台登录 · 已扫码', () => { S.plat = 'kugou'; S.dlg = { plat:'kugou', st:1, mode:'扫码' }; S.sheet = { v:'platLogin' }; }], ['发现 · 平台与脚本选择器', () => { S.picker = true; }], ['发现 · 切换平台加载中', () => { S.plat = 'qq'; S.loading = true; }], ['发现 · 榜单', () => { S.homeTab = '榜单'; }],
    ['搜索 · 默认', tabTo('search')], ['搜索 · 输入中（键盘）', () => { S.tab = 'search'; S.searchQ = '星'; S.qFocus = true; }], ['搜索 · 结果综合', () => { S.tab = 'search'; S.searchQ = '雾港'; S.searchDone = true; }], ['搜索 · 结果歌曲 · QQ', () => { S.tab = 'search'; S.searchQ = '雾港'; S.searchDone = true; S.rType = '歌曲'; S.rPlat = 'qq'; }], ['搜索 · 结果 MV', () => { S.tab = 'search'; S.searchQ = '雾港'; S.searchDone = true; S.rType = 'MV'; }], ['搜索 · 结果专辑', () => { S.tab = 'search'; S.searchQ = '雾港'; S.searchDone = true; S.rType = '专辑'; }],
    ['每日混音', tabTo('daily')],
    ['音乐库 · 我喜欢', () => { S.tab = 'library'; S.libSeg = 'like'; }], ['音乐库 · 歌单', () => { S.tab = 'library'; S.libSeg = 'playlists'; }],
    ['音乐库 · 最近', () => { S.tab = 'library'; S.libSeg = 'recent'; }], ['音乐库 · 本地', () => { S.tab = 'library'; S.libSeg = 'local'; S.azLetter = null; }],
    ['我的', tabTo('me')], ['音乐云盘', pushTo('cloud')], ['底栏收起（滚动后）', () => { S.bar = 'liquid'; S.tab = 'library'; S.libSeg = 'like'; S.navMin = true; }],
  ]],
  ...(typeof DAV_JUMPS !== 'undefined' ? [['音乐云盘 · WebDAV', DAV_JUMPS]] : []),
  ['底部导航 · 5 种形态', BAR_STYLES.map(([k, n]) => [`底栏 · ${n}`, () => { S.bar = k; S.tab = 'daily'; }])],
  ['二级页', [
    ['歌单详情', pushTo('playlist', { id:0 })], ['歌手', pushTo('artist', { id:0 })], ['听歌统计', pushTo('stats')],
    ['扫一扫', scanTo('scan', null)], ['扫一扫 · 电视登录确认', scanTo('scan', 'tv')], ['扫一扫 · 歌单码', scanTo('scan', 'playlist')], ['扫一扫 · 分享码', scanTo('scan', 'song')],
    ['听歌识曲 · 聆听', scanTo('match', null)], ['听歌识曲 · 结果', scanTo('match', null, () => { S.matchState = 'found'; })],
    ['剪贴板口令横幅', () => { S.clip = 17; }],
    ['公告', pushTo('announcements')], ['下载管理', pushTo('download')],
  ]],
  ['播放器 · 11 套皮肤', [
    ...SKINS.map(k => [`皮肤 · ${k.n}`, playerSkin(k.id)]),
    ['律动 · 弹簧瀑布歌词', playerSkin('spring', () => { S.amView = 'lyrics'; })], ['律动 · 波浪漂浮歌词', playerSkin('spring', () => { S.amView = 'lyrics'; S.amWave = 'wave'; })], ['律动 · 内嵌队列', playerSkin('spring', () => { S.amView = 'queue'; })],
    ['粒子 · 事件视界', playerSkin('particles', () => { S.particle = 'disk'; })],
    ['粒子 · 全息地球', playerSkin('particles', () => { S.particle = 'globe'; })],
  ]],
  ['播放器面板', [
    ['播放队列', sheetOn('queue')], ['歌曲更多', sheetOn('more')], ['音质', sheetOn('quality')], ['睡眠定时', sheetOn('timer')],
    ['倍速', sheetOn('speed')], ['投放设备', sheetOn('cast')], ['皮肤与背景', sheetOn('skin')], ['歌词快调', sheetOn('lyricq')],
    ['均衡器', sheetOn('eq')], ['歌词分享卡', sheetOn('shareCard')], ['分享口令', sheetOn('shareCode')], ['播放链路', sheetOn('trace')],
  ]],
  ['设置', [
    ['外观与界面', pushTo('appearance')], ['歌词', pushTo('lyrics')], ['系统歌词', pushTo('syslyrics')], ['播放与音质', pushTo('playback')],
    ['智能换源', pushTo('smart')], ['平台与解析脚本', pushTo('sources')], ['平台账号', pushTo('accounts3p')], ['账号中心', pushTo('account')],
    ['登录设备', pushTo('devices')], ['备份与同步', pushTo('backup')], ['关于与更新', pushTo('about')],
    ['导入歌单弹窗', () => { S.tab = 'library'; S.libSeg = 'playlists'; S.dlg = { plat:'netease', val:'', step:0 }; S.dialog = 'importPlaylist'; }], ['导入歌单 · 已识别', () => { S.tab = 'library'; S.libSeg = 'playlists'; S.dlg = { plat:'qq', val:'https://y.qq.com/n/ryqq/playlist/8837261540', step:0, detected:true }; S.dialog = 'importPlaylist'; }], ['导入歌单 · 确认', () => { S.tab = 'library'; S.libSeg = 'playlists'; S.dlg = { plat:'netease', val:'x', step:2 }; S.dialog = 'importPlaylist'; }], ['新建歌单弹窗', () => { S.tab = 'library'; S.libSeg = 'playlists'; S.dlg = { val:'' }; S.dialog = 'newPlaylist'; }],
    ['导入音源（抽屉）', () => { S.stack = [{ id:'sources' }]; S.sheet = { v:'importScript' }; }], ['粘贴脚本弹窗', () => { S.stack = [{ id:'sources' }]; S.dlg = { val:SAMPLE_SCRIPT, step:0 }; S.dialog = 'pasteScript'; }], ['粘贴脚本 · 确认', () => { S.stack = [{ id:'sources' }]; S.dlg = { val:SAMPLE_SCRIPT, step:2 }; S.dialog = 'pasteScript'; }],
    ['皮肤选择', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'skin' }; }], ['皮肤选择 · 极简分类', () => { S.stack = [{ id:'appearance' }]; S.skinTab = '极简'; S.sheet = { v:'skin' }; }], ['底栏样式 · 更多', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'barStyles' }; }], ['App 图标', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'appIcon' }; }], ['界面字体', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'fonts' }; }], ['首页内容与顺序', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'homeOrder' }; }], ['播放器背景', () => { S.stack = [{ id:'appearance' }]; S.sheet = { v:'bg' }; }], ['激活码（Sheet）', () => { S.stack = [{ id:'account' }]; S.sheet = { v:'activate' }; }],
  ]],
  ['弹窗与反馈', [
    ['会话过期', () => { S.dialog = 'session'; }], ['重要公告确认', () => { S.stack = [{ id:'announcements' }]; S.dialog = 'announce'; }],
    ['版本更新', () => { S.stack = [{ id:'about' }]; S.dialog = 'update'; }], ['退出登录确认', () => { S.stack = [{ id:'account' }]; S.dialog = 'logout'; }],
  ]],
];
const JUMP_FLAT = JUMPS.flatMap(([g, l]) => l.map(([n, fn]) => ({ g, n, fn })));
let curJump = '发现 · 网易云已登录';
function go(name) {
  const j = JUMP_FLAT.find(x => x.n === name); if (!j) return;
  reset(); S.homeTab = '精选'; j.fn(); curJump = name; S._freshScroll = true; render();
  if (name === '音乐库 · 本地') { S.azLetter = 'Y'; showAz(); }
  if (name === '听歌识曲 · 聆听') ACT.match();
  if (S._scrollTo) { const p = topPage(); if (p) p.scrollTop = S._scrollTo; S._scrollTo = 0; }
}

function buildSide() {
  const side = document.getElementById('side');
  side.innerHTML = `<h1>Lyra（暂名）· 移动端 UI 原型 v4</h1><div class="sub">390×844 · 可直接点击操作<br>手机浏览器打开会自动全屏</div>
    <div class="opts" style="margin-bottom:6px"><button id="viewBtn" data-view>${VIEW === 'board' ? '← 交互模式' : '总览全部页面'}</button></div>
    <h2>主题</h2><div class="opts">${[['dark', '深色'], ['light', '浅色']].map(([k, n]) => `<button data-o="theme" data-v="${k}">${n}</button>`).join('')}</div>
    <h2>主题色</h2><div class="opts">${ACCENTS.map((a, i) => `<button data-o="accent" data-v="${i}" style="border-left:10px solid ${a.c}">${a.n}</button>`).join('')}</div>
    <h2>底栏样式</h2><div class="opts">${BAR_STYLES.map(([k, n]) => `<button data-o="bar" data-v="${k}">${n}</button>`).join('')}</div>
    ${JUMPS.map(([g, l]) => `<h2>${g}</h2>${l.map(([n]) => `<a data-j="${n}">${n}</a>`).join('')}`).join('')}`;
  side.onclick = e => {
    const j = e.target.closest('[data-j]'), o = e.target.closest('[data-o]'), v = e.target.closest('[data-view]');
    if (v) { location.search = VIEW === 'board' ? '' : '?view=board'; return; }
    if (j) { if (VIEW === 'board') { location.search = '?go=' + encodeURIComponent(j.dataset.j); return; } go(j.dataset.j); }
    if (o) { const k = o.dataset.o; S[k] = k === 'accent' ? +o.dataset.v : o.dataset.v; VIEW === 'board' ? buildBoard() : render(); syncSide(); }
  };
  syncSide();
}
function syncSide() {
  document.querySelectorAll('#side [data-j]').forEach(a => a.classList.toggle('on', a.dataset.j === curJump));
  document.querySelectorAll('#side [data-o]').forEach(b => b.classList.toggle('on', String(S[b.dataset.o]) === b.dataset.v));
}

/* 总览：每个状态渲染成一个缩小的手机，点击进入交互模式 */
function buildBoard() {
  const stage = document.querySelector('.stage');
  stage.style.cssText = 'display:block;overflow:auto;padding:24px 28px';
  document.documentElement.dataset.theme = S.theme; applyAccent();
  const saved = JSON.stringify({ accent:S.accent, theme:S.theme, bar:S.bar });
  let html = '';
  JUMPS.forEach(([g, l]) => {
    html += `<h2 class="bh">${g}</h2><div class="bgrid">`;
    l.forEach(([n, fn]) => {
      reset(); S.homeTab = '精选'; Object.assign(S, JSON.parse(saved)); fn(); S.playing = n.indexOf('暂停') < 0;
      const land = S.playerOpen && S.skin === 'standby';
      html += `<div class="bcell ${land ? 'wide' : ''}" data-go="${n}"><div class="phone ${land ? 'land' : ''}"><div class="notch"></div><div class="screen">${buildScreen()}</div><div class="homebar"></div></div><div class="bn-l">${n}</div></div>`;
    });
    html += '</div>';
  });
  stage.innerHTML = html;
  reset(); Object.assign(S, JSON.parse(saved));
  stage.querySelectorAll('.bcell').forEach(c => {
    c.onclick = () => { location.search = '?go=' + encodeURIComponent(c.dataset.go); };
    // 歌词与粒子在总览里按当前行静态排版
    c.querySelectorAll('.lyr').forEach(l => { const inn = l.querySelector('.lyr-in'), k = Math.max(0, lyrIdx()), line = inn.children[k]; if (line) { line.classList.add('on'); inn.style.transform = `translateY(${l.clientHeight * (+l.dataset.anchor || .36) - line.offsetTop - line.offsetHeight / 2}px)`; } });
    c.querySelectorAll('.ll.on .w,.stage-l .now .w').forEach(w => w.style.setProperty('--p', '.55'));
    c.querySelectorAll('.spec i').forEach((b, i) => b.style.height = 12 + Math.abs(Math.sin(i * 1.3)) * 70 * (1 - Math.abs(i - 12) / 24) + '%');
  });
  stage.querySelectorAll('canvas.fxc').forEach(cv => cv.dataset.static = '1');
  mountFx(stage);
}

const QS = new URLSearchParams(location.search);
const VIEW = QS.get('view') === 'board' ? 'board' : 'app';
window.addEventListener('DOMContentLoaded', () => {
  if (QS.get('theme')) S.theme = QS.get('theme');
  if (QS.get('accent')) S.accent = +QS.get('accent');
  if (QS.get('bar')) S.bar = QS.get('bar');
  buildSide();
  if (VIEW === 'board') { buildBoard(); return; }
  bindEvents();
  go(QS.get('go') || '发现 · 网易云已登录');
  // 首次打开演示：2.5 秒后检测到剪贴板口令，从刘海处展开横幅
  if (!QS.get('go') && !QS.get('noclip')) setTimeout(() => { if (!S.clip && !S.playerOpen && !S.sheet) { S.clip = 17; render(); } }, 2500);
  requestAnimationFrame(loop);
});
window.__sollin = { S, go, render, JUMPS:JUMP_FLAT.map(j => j.n) };
