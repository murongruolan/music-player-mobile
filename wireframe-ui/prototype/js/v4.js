/* v4：品牌暂名 Lyra + App 图标、底部搜索栏与搜索结果、发现页平台推荐区与模块排序、
   底栏 9 种（一行 + 更多）、皮肤 15 套（顶部分类 Tab）、界面字体、我的页精简（云盘 = WebDAV）。
   在 features.js 之后加载，覆盖其中同名的页面 / 函数。 */
const APP_NAME = 'Lyra';
ICONS.video = '<rect x="3" y="5.5" width="13" height="13" rx="2.5"/><path d="m16 10 5-3v10l-5-3z"/>';
ICONS.trend = '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>';
ICONS.arrowUL = '<path d="M17 17 7 7M7 15V7h8"/>';
Object.assign(S, { appIcon:'gold', font:'system', qFocus:false, searchDone:false, rType:'综合', rPlat:'all', skinTab:'全部', newSongReg:'华语', davSeg:0,
  homeMods:[{ k:'custom', on:true }, { k:'mypl', on:true }, { k:'quick', on:true }, { k:'tabs', on:true }, { k:'platrec', on:true }] });
const HOME_MOD_N = { custom:['为你定制', '每日推荐、心动/雷达模式（需登录平台）'], mypl:['我的歌单', '平台上创建与收藏的歌单（需登录平台）'], quick:['快捷入口', '每日混音、私人电台、识曲、排行榜'], tabs:['精选 · 榜单 · 歌单', '推荐歌单与热门榜单'], platrec:['平台推荐', '新碟、官方榜、MV 等，随平台变化'] };

/* ================= App 图标（与鎏金主题色配套） ================= */
const LYRE = `<path d="M31 74C21 55 24 36 38 27M69 74C79 55 76 36 62 27" stroke-width="7"/><path d="M33 39h34" stroke-width="5.5"/><path d="M30 74q20 10 40 0" stroke-width="6.5"/><path d="M44 40v34M50 40v36M56 40v34" stroke-width="3"/><path d="M50 9l3 8 8 3-8 3-3 8-3-8-8-3 8-3z" stroke="none" fill="currentColor"/>`;
const APP_ICONS = [
  { id:'gold', n:'鎏金', d:'默认 · 与鎏金主题色配套' }, { id:'night', n:'夜空', d:'深色底 · 金色琴弦' },
  { id:'aurora', n:'极光', d:'与「极光」主题色配套' }, { id:'vinyl', n:'黑胶', d:'唱片纹理' },
  { id:'mono', n:'极简', d:'白底黑线' }, { id:'neon', n:'霓虹', d:'发光描边' },
  { id:'glass', n:'玻璃', d:'半透明磨砂' }, { id:'pixel', n:'像素', d:'8-bit' },
];
function appIconSvg(id, size = 64) {
  const bg = {
    gold:`<defs><radialGradient id="g1" cx="32%" cy="24%" r="90%"><stop offset="0" stop-color="#FFF4D6"/><stop offset=".42" stop-color="#F4D28A"/><stop offset="1" stop-color="#9A6B12"/></radialGradient></defs><rect width="100" height="100" rx="23" fill="url(#g1)"/>`,
    night:`<defs><radialGradient id="g2" cx="50%" cy="10%" r="100%"><stop offset="0" stop-color="#2A2C3E"/><stop offset="1" stop-color="#07080D"/></radialGradient><linearGradient id="g2b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF1C9"/><stop offset="1" stop-color="#C9A04A"/></linearGradient></defs><rect width="100" height="100" rx="23" fill="url(#g2)"/>${[[18, 20], [82, 16], [76, 60], [16, 66], [88, 86]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="1.1" fill="#fff" opacity=".7"/>`).join('')}`,
    aurora:`<defs><linearGradient id="g3" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6EE7C8"/><stop offset=".55" stop-color="#3D7BE0"/><stop offset="1" stop-color="#7B4FD6"/></linearGradient></defs><rect width="100" height="100" rx="23" fill="url(#g3)"/>`,
    vinyl:`<rect width="100" height="100" rx="23" fill="#101114"/><g fill="none" stroke="#2A2C33" stroke-width=".9">${[44, 40, 36, 32, 28, 24].map(r => `<circle cx="50" cy="50" r="${r}"/>`).join('')}</g><circle cx="50" cy="50" r="20" fill="#F4D28A"/>`,
    mono:`<rect width="100" height="100" rx="23" fill="#F6F6F4"/>`,
    neon:`<rect width="100" height="100" rx="23" fill="#0B0814"/>`,
    glass:`<defs><linearGradient id="g7" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".55"/><stop offset="1" stop-color="#ffffff" stop-opacity=".12"/></linearGradient></defs><rect width="100" height="100" rx="23" fill="#2B2E3D"/><rect x="1" y="1" width="98" height="98" rx="22" fill="url(#g7)" stroke="#fff" stroke-opacity=".5"/>`,
    pixel:`<rect width="100" height="100" rx="23" fill="#1B1532"/>`,
  }[id];
  const glyph = {
    gold:`<g fill="none" stroke="#1B1508" stroke-linecap="round" color="#1B1508">${LYRE}</g>`,
    night:`<g fill="none" stroke="url(#g2b)" stroke-linecap="round" color="#FFF1C9">${LYRE}</g>`,
    aurora:`<g fill="none" stroke="#fff" stroke-linecap="round" color="#fff">${LYRE}</g>`,
    vinyl:`<g transform="translate(50 50) scale(.36) translate(-50 -50)" fill="none" stroke="#1B1508" stroke-linecap="round" color="#1B1508">${LYRE}</g>`,
    mono:`<g fill="none" stroke="#111" stroke-linecap="round" color="#111">${LYRE}</g>`,
    neon:`<g fill="none" stroke-linecap="round" style="filter:drop-shadow(0 0 3px #FF5FD2)" stroke="#FF8FE0" color="#7DF9FF">${LYRE}</g>`,
    glass:`<g fill="none" stroke="#F4D28A" stroke-linecap="round" color="#fff">${LYRE}</g>`,
    pixel:`<g fill="#F4D28A">${[[44, 12], [50, 6], [50, 12], [56, 12], [50, 18], [26, 30], [26, 36], [26, 42], [32, 48], [32, 54], [38, 60], [68, 30], [68, 36], [68, 42], [62, 48], [62, 54], [56, 60], [32, 30], [38, 30], [44, 30], [50, 30], [56, 30], [62, 30], [38, 66], [44, 72], [50, 72], [56, 66], [44, 36], [44, 42], [44, 48], [44, 54], [56, 36], [56, 42], [56, 48], [56, 54]].map(([x, y]) => `<rect x="${x}" y="${y}" width="6" height="6"/>`).join('')}</g>`,
  }[id];
  return `<svg viewBox="0 0 100 100" width="${size}" height="${size}" class="aicon">${bg}${glyph}</svg>`;
}
const appIcon = (size = 64, cls = '') => `<div class="logo ai ${cls}" style="width:${size}px;height:${size}px">${appIconSvg(S.appIcon, size)}</div>`;
SHEETS.appIcon = () => ({ t:'App 图标', body:`
  <div class="hs-prev"><div class="hsp-grid">${Array.from({ length:7 }, (_, i) => `<i style="background:hsl(${i * 47} 40% ${S.theme === 'dark' ? 30 : 75}%)"></i>`).join('')}<div class="hsp-me" key="${S.appIcon}">${appIconSvg(S.appIcon, 54)}<span>${APP_NAME}</span></div>${'<i></i>'.repeat(4).replace(/<i><\/i>/g, () => `<i style="background:hsl(${Math.random() * 360} 35% ${S.theme === 'dark' ? 28 : 78}%)"></i>`)}</div></div>
  <div class="ai-grid">${APP_ICONS.map(a => `<button class="${S.appIcon === a.id ? 'on' : ''}" data-act="setIcon" data-v="${a.id}">${appIconSvg(a.id, 60)}<b>${a.n}</b><small>${a.d}</small></button>`).join('')}</div>
  <p class="hint" style="padding:6px var(--pad) 0">图标为「${APP_NAME}」暂名设计：天琴座（Lyra）的竖琴 + 织女星。更换后系统会提示一次。</p>` });
ACT.setIcon = d => { S.appIcon = d.v; render(); const m = document.querySelector('.hsp-me'); m && m.animate([{ transform:'scale(.6) rotate(-12deg)', opacity:.3 }, { transform:'none', opacity:1 }], { duration:520, easing:'cubic-bezier(.3,1.5,.5,1)' }); toast(`App 图标：${APP_ICONS.find(a => a.id === d.v).n}`, 'grid'); };

/* ================= 界面字体 ================= */
const FONTS = [
  { id:'system', n:'系统默认', f:'' },
  { id:'round', n:'圆润', f:'"SF Pro Rounded","HarmonyOS Sans SC","MiSans","Nunito","PingFang SC",system-ui,sans-serif' },
  { id:'serif', n:'书卷', f:'"Songti SC","Noto Serif SC","Source Han Serif SC",Georgia,serif' },
  { id:'kai', n:'楷意', f:'"Kaiti SC","STKaiti","KaiTi","LXGW WenKai",serif' },
  { id:'mono', n:'等宽', f:'ui-monospace,"SF Mono","Sarasa Mono SC","JetBrains Mono",Menlo,monospace' },
];
SHEETS.fonts = () => ({ t:'界面字体', body:`<div class="fonts">${FONTS.map(f => `<button class="${S.font === f.id ? 'on' : ''}" data-act="setFont" data-v="${f.id}" style="${f.f ? `font-family:${f.f}` : ''}"><b>${f.n}</b><span>夜航的星图 Aa 0123</span><i>${ic('check')}</i></button>`).join('')}</div>
  ${group('', [item({ icon:'plus', color:'blue', label:'导入字体', sub:'支持 .ttf / .otf，导入后只在本 App 内生效', act:'sheetToast', args:{ msg:'已打开文件选择器', icon:'font' } })])}` });
ACT.setFont = d => { S.font = d.v; render(); };
const _applyAccent = applyAccent;
applyAccent = function () { _applyAccent(); const f = FONTS.find(x => x.id === S.font); document.documentElement.style.setProperty('--font', f && f.f ? f.f : '-apple-system,"SF Pro Text","PingFang SC","HarmonyOS Sans SC","MiSans","Noto Sans SC","Microsoft YaHei",system-ui,sans-serif'); };

/* ================= 首页内容与顺序（可拖动排序） ================= */
SHEETS.homeOrder = () => ({ t:'首页内容与顺序', sub:'按住右侧拖动', body:`
  <div class="ho-list">${S.homeMods.map((m, i) => `<div class="ho-it ${m.on ? '' : 'off'}" data-i="${i}" data-flip="ho:${m.k}"><div class="ho-tx"><b>${HOME_MOD_N[m.k][0]}</b><small>${HOME_MOD_N[m.k][1]}</small></div>
    <div class="sw ${m.on ? 'on' : ''}" data-act="homeMod" data-v="${i}"></div><span class="ho-h">${ic('drag')}</span></div>`).join('')}</div>
  <p class="hint" style="padding:8px var(--pad) 0">登录平台前，「为你定制」和「我的歌单」位置会显示登录引导。</p>` });
ACT.homeMod = (d, e) => { e && e.stopPropagation(); const m = S.homeMods[+d.v]; m.on = !m.on; render(); };
(function bindReorder() {
  let r = null;
  document.addEventListener('pointerdown', e => {
    const h = e.target.closest('.ho-h'); if (!h) return;
    e.stopPropagation(); e.preventDefault();
    const it = h.closest('.ho-it'); r = { it, i:+it.dataset.i, y0:e.clientY, h:it.offsetHeight + 8, list:[...it.parentElement.children] };
    it.classList.add('lift');
  }, true);
  window.addEventListener('pointermove', e => {
    if (!r) return; const dy = e.clientY - r.y0; r.it.style.transform = `translateY(${dy}px) scale(1.03)`;
    const to = Math.max(0, Math.min(r.list.length - 1, r.i + Math.round(dy / r.h)));
    r.list.forEach((el, j) => { if (el === r.it) return; let s = 0; if (r.i < to && j > r.i && j <= to) s = -r.h; if (r.i > to && j < r.i && j >= to) s = r.h; el.style.transform = s ? `translateY(${s}px)` : ''; });
    r.to = to;
  });
  window.addEventListener('pointerup', () => {
    if (!r) return; const { i, to } = r; r = null;
    if (to != null && to !== i) { const [m] = S.homeMods.splice(i, 1); S.homeMods.splice(to, 0, m); }
    render();
  });
})();

/* ================= 底部导航：9 种，设置页只露一行 + 更多 ================= */
BAR_STYLES.push(['cutout', '凹槽'], ['dock', '程序坞'], ['bubble', '气泡'], ['text', '纯文字']);
const BAR_DESC = { liquid:'折射高光 + 可拖动水滴', island:'悬浮胶囊，选中项展开文字', capsule:'4 项 + 独立搜索钮', frosted:'迷你播放条与底栏连成一块', classic:'贴底通栏，最省电', cutout:'选中项升起成圆，底栏随之凹陷', dock:'图标按下放大，下方小圆点', bubble:'每项一颗独立气泡', text:'只有文字，选中项加粗下划线' };
const _navTarget = navTarget;
navTarget = function (nv, on) {
  if (!on) return null;
  const c = on.offsetLeft + on.offsetWidth / 2;
  if (nv.classList.contains('cutout')) return { l:c - 27, w:54 };
  if (nv.classList.contains('dock')) return { l:c - 3, w:6 };
  if (nv.classList.contains('bubble')) return { l:c - 24, w:48 };
  if (nv.classList.contains('text')) return { l:c - 12, w:24 };
  return _navTarget(nv, on);
};
const _placeNav = placeNav;
placeNav = function (scr, prev) {
  _placeNav(scr, prev);
  const nv = scr.querySelector('.nav.cutout'), on = nv && nv.querySelector('.nv.on');
  if (on) nv.style.setProperty('--x', on.offsetLeft + on.offsetWidth / 2 + 'px');
};
const MINI_BOTTOM = { liquid:102, island:102, capsule:100, frosted:83, classic:91, cutout:126, dock:98, bubble:96, text:90 };
function barPv4(k) {
  if (['liquid', 'island', 'capsule', 'frosted', 'classic'].includes(k)) return barPv(k);
  const dots = n => Array.from({ length:n }, (_, i) => `<i class="${i === 1 ? 'a' : ''}"></i>`).join('');
  return `<div class="pv"><div style="position:absolute;left:8px;right:8px;bottom:30px;height:11px;border-radius:5px;background:var(--s3)"></div><div class="bpv4 ${k}"><b></b>${dots(5)}</div></div>`;
}
function barRow() {
  const order = [S.bar, ...BAR_STYLES.map(b => b[0]).filter(k => k !== S.bar)].slice(0, 3);
  return `<div class="opt-grid four">${order.map(k => `<button class="${S.bar === k ? 'on' : ''}" data-act="bar" data-v="${k}">${barPv4(k)}${BAR_STYLES.find(b => b[0] === k)[1]}</button>`).join('')}
    <button data-act="sheet" data-v="barStyles"><div class="pv more">${ic('grid')}<span>+${BAR_STYLES.length - 3}</span></div>更多</button></div>`;
}
SHEETS.barStyles = () => ({ t:'底部导航样式', sub:`${BAR_STYLES.length} 种`, body:`<div class="opt-grid">${BAR_STYLES.map(([k, n]) => `<button class="${S.bar === k ? 'on' : ''}" data-act="barPick" data-v="${k}">${barPv4(k)}<b>${n}</b><small class="bdesc">${BAR_DESC[k]}</small></button>`).join('')}</div>` });
ACT.barPick = d => { S.bar = d.v; S.navMin = false; render(); toast(`底栏：${BAR_STYLES.find(b => b[0] === d.v)[1]}`, 'grid'); };

/* ================= 搜索：输入框放在底部（拇指区），迷你播放条变成旁边的唱片圆钮 ================= */
const FINE = matchMedia('(pointer:fine)').matches;
const _mini = mini;
mini = function () {
  if (S.tab !== 'search' || S.stack.length) return _mini();
  const s = song(), q = S.searchQ, p = Math.min(1, S.pos / s.dur);
  return `<div class="sdock ${S.qFocus ? 'focus' : ''} ${S.bar}" style="--mb:${S.qFocus ? (FINE ? 268 : 12) : MINI_BOTTOM[S.bar]}px">
    <div class="sbar" data-act="qFocus">${ic('search')}<input id="q" placeholder="在 ${S.rPlat === 'all' ? '全部平台' : PLATFORMS.find(x => x.id === S.rPlat).n} 中搜索" value="${q}" autocomplete="off" enterkeyhint="search">
      ${q ? `<button class="sb-c" data-act="clearQ">${ic('close')}</button>` : `<button class="sb-c" data-act="openScan" data-v="match">${ic('mic')}</button>`}</div>
    ${S.qFocus ? `<button class="sb-cancel" data-act="qBlur">取消</button>` : `<button class="sdisc ${S.playing ? '' : 'paused'}" data-act="openPlayer" style="--p:${p}">${cover(s)}<i class="sd-ring"></i><span class="sd-st">${ic(S.playing ? 'pause' : 'play')}</span></button>`}</div>
    ${S.qFocus && FINE ? fakeKbd() : ''}`;
};
function fakeKbd() {
  const rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  return `<div class="kbd">${rows.map((r, i) => `<div class="kr">${i === 2 ? '<b class="kw">⇧</b>' : ''}${[...r].map(c => `<b data-act="key" data-v="${c}">${c}</b>`).join('')}${i === 2 ? '<b class="kw" data-act="key" data-v="⌫">⌫</b>' : ''}</div>`).join('')}
    <div class="kr"><b class="kw">123</b><b class="kw">中</b><b class="ksp" data-act="key" data-v=" ">空格</b><b class="kgo" data-act="doSearch">搜索</b></div></div>`;
}
const _nav = nav;
nav = function () { const h = _nav(); return S.tab === 'search' && S.qFocus && !S.stack.length ? h.replace('<nav class="nav', '<nav class="nav kbhide') : h; };
ACT.qFocus = () => { if (S.qFocus) return; S.qFocus = true; S._focusQ = true; render(); };
ACT.qBlur = () => { S.qFocus = false; render(); };
ACT.key = d => { S.searchQ = d.v === '⌫' ? S.searchQ.slice(0, -1) : S.searchQ + d.v; S.searchDone = false; S._focusQ = true; render(); };
ACT.doSearch = () => { const q = S.searchQ.trim(); if (!q) return; if (!S.history.includes(q)) S.history.unshift(q); S.searchDone = true; S.qFocus = false; S.rType = '综合'; S._stagger = true; render(); };
ACT.sq = d => { S.searchQ = d.q; S.tab = 'search'; S.stack = []; ACT.doSearch(); };
ACT.clearQ = () => { S.searchQ = ''; S.searchDone = false; S.qFocus = true; S._focusQ = true; render(); };
ACT.rType = d => { S.rType = d.v; S._stagger = true; render(); };
ACT.rPlat = d => { S.rPlat = d.v; S._stagger = true; render(); };
document.addEventListener('input', e => { if (e.target.id === 'q') S.searchDone = false; }, true);
document.addEventListener('keydown', e => { if (e.target.id === 'q' && e.key === 'Enter') { S.searchQ = e.target.value; ACT.doSearch(); } });
document.addEventListener('focusin', e => { if (e.target.id === 'q' && !S.qFocus) { S.qFocus = true; S._focusQ = true; setTimeout(render, 0); } });

const hl = (t, q) => { const i = t.toLowerCase().indexOf(q.toLowerCase()); return i < 0 ? t : `${t.slice(0, i)}<em>${t.slice(i, i + q.length)}</em>${t.slice(i + q.length)}`; };
function suggest(q) {
  const out = [], ql = q.toLowerCase();
  SONGS.forEach(s => { if (s.t.toLowerCase().includes(ql)) out.push(['music', s.t, `歌曲 · ${s.a}`]); });
  [...new Set(SONGS.map(s => s.a))].forEach(a => { if (a.toLowerCase().includes(ql)) out.push(['user', a, '歌手']); });
  [...new Set(SONGS.map(s => s.al))].forEach(a => { if (a.toLowerCase().includes(ql)) out.push(['album', a, '专辑']); });
  ['现场版', '伴奏', '翻唱', '歌词', 'DJ 版'].forEach(x => out.push(['search', `${q} ${x}`, '']));
  return out.slice(0, 9);
}
const pidOf = id => PLATFORMS[id % PLATFORMS.length].id;
function resRow(s, i) {
  const p = PLATFORMS.find(x => x.id === (S.rPlat === 'all' ? pidOf(s.id) : S.rPlat));
  return songRow(s, { list:'all' }).replace('<span>' + s.a + ' · ' + s.al + '</span>', `<span>${hl(s.a, S.searchQ)} · ${s.al}</span>`).replace(`<div class="t">${s.t}</div>`, `<div class="t">${hl(s.t, S.searchQ)}</div>`).replace('<b class="qb', `${platBadge(p, 14)}<b class="qb`);
}
function mvCard(i, w = 220) { const s = SONGS[(i * 5 + 3) % SONGS.length]; return `<div class="mv" style="width:${w}px" data-act="toast" data-msg="播放 MV：${s.t}" data-icon="video"><div class="cv mv-th" style="${coverStyle(s.h + 20, s.v)}"><span class="mv-d">${fmt(150 + i * 23)}</span><span class="mv-p">${ic('play')}</span></div><b>${s.t} (Official MV)</b><small>${s.a} · ${(i * 37 + 12) % 90 + 3}万次播放</small></div>`; }
function searchResults() {
  const q = S.searchQ.trim(), ql = q.toLowerCase();
  let res = SONGS.filter(s => (s.t + s.a + s.al).toLowerCase().includes(ql)); if (!res.length) res = SONGS.slice(0, 8);
  if (S.rPlat !== 'all') res = res.concat(SONGS.slice(4, 9)).slice(0, 8);
  const artist = SONGS.find(s => s.a.toLowerCase().includes(ql)) || SONGS[0];
  const counts = PLATFORMS.map((p, i) => 12 + ((q.length * 7 + i * 13) % 40));
  const types = ['综合', '歌曲', '歌单', '专辑', '艺术家', 'MV'];
  const T = S.rType;
  const head = `<div class="rhead">
    <div class="rtypes" style="--i:${types.indexOf(T)}">${types.map(t => `<button class="${t === T ? 'on' : ''}" data-act="rType" data-v="${t}" data-flip="${t === T ? 'rtind' : ''}">${t}</button>`).join('')}</div>
    <div class="rplats"><button class="${S.rPlat === 'all' ? 'on' : ''}" data-act="rPlat" data-v="all">全部平台<small>${counts.reduce((a, b) => a + b, 0)}</small></button>${PLATFORMS.map((p, i) => `<button class="${S.rPlat === p.id ? 'on' : ''}" data-act="rPlat" data-v="${p.id}">${platBadge(p, 18)}${p.n.replace('音乐', '')}<small>${counts[i]}</small></button>`).join('')}</div></div>`;
  const related = `<div class="rrel"><span>${ic('trend')}相关搜索</span>${[`${q} 现场`, `${artist.a}`, `${q} 歌词`, `${artist.al}`, `${q} 翻唱`].map(x => `<button data-act="sq" data-q="${x}">${x}</button>`).join('')}</div>`;
  const songs = n => `<div>${res.slice(0, n).map(resRow).join('')}</div>`;
  const albums = `<div class="hs">${[artist.al, '现场 · 2025', '单曲合集', '远光 (Deluxe)'].map((a, i) => `<div class="alb" data-act="push" data-v="playlist" data-id="${i}"><div class="cv" style="${coverStyle(artist.h + i * 30, i)}"></div><i class="alb-disc"></i><b>${hl(a, q)}</b><small>${artist.a} · ${2026 - i}</small></div>`).join('')}</div>`;
  const pls = `<div>${PLAYLISTS.slice(0, 5).map(p => `<div class="row" data-act="push" data-v="playlist" data-id="${p.id}"><div class="cv" style="${coverStyle(p.h, p.v)}"></div><div class="tx"><div class="t">${hl(p.t, q)}</div><div class="s"><span>${p.n} 首 · ${p.by} · ${p.pc}次播放</span></div></div><span style="color:var(--t3);padding-right:12px">${ic('right')}</span></div>`).join('')}</div>`;
  const artists = `<div class="hs">${[...new Set(SONGS.map(s => s.a))].slice(0, 6).map((a, i) => `<div class="art" data-act="push" data-v="artist" data-id="${SONGS.find(s => s.a === a).id}"><div class="cv" style="${coverStyle(i * 60 + 20, 1)}"></div><b>${hl(a, q)}</b><small>${12 - i} 万关注</small></div>`).join('')}</div>`;
  const mvs = w => `<div class="hs">${[0, 1, 2, 3].map(i => mvCard(i, w)).join('')}</div>`;
  let body = '';
  if (T === '综合') body = `
    <div class="card m best" data-act="push" data-v="artist" data-id="${artist.id}"><div class="cv" style="${coverStyle(artist.h, 1)}"></div><div style="flex:1"><small>最佳匹配 · 艺术家</small><b>${hl(artist.a, q)}</b><span>${SONGS.filter(s => s.a === artist.a).length} 首单曲 · 3 张专辑 · 12 万关注</span></div><button class="ib play-c" data-act="playAll" data-list="all">${ic('play')}</button></div>
    <div class="sec"><h2>单曲</h2><button class="more" data-act="rType" data-v="歌曲">全部${ic('right')}</button></div>${songs(4)}
    <div class="sec"><h2>专辑</h2><button class="more" data-act="rType" data-v="专辑">全部${ic('right')}</button></div>${albums}
    <div class="sec"><h2>歌单</h2><button class="more" data-act="rType" data-v="歌单">全部${ic('right')}</button></div>${PLAYLISTS.slice(0, 3).map(p => `<div class="row" data-act="push" data-v="playlist" data-id="${p.id}"><div class="cv" style="${coverStyle(p.h, p.v)}"></div><div class="tx"><div class="t">${hl(p.t, q)}</div><div class="s"><span>${p.n} 首 · ${p.pc}次播放</span></div></div></div>`).join('')}
    <div class="sec"><h2>MV</h2><button class="more" data-act="rType" data-v="MV">全部${ic('right')}</button></div>${mvs(220)}
    <div class="sec"><h2>艺术家</h2></div>${artists}`;
  if (T === '歌曲') body = `<div style="display:flex;gap:8px;padding:6px var(--pad) 4px"><button class="btn pri sm" data-act="playAll" data-list="all">${ic('play')}播放全部</button><span class="chip">${ic('sort')}综合排序</span><span class="chip">${ic('hd')}只看无损</span></div>${songs(10)}`;
  if (T === '歌单') body = pls;
  if (T === '专辑') body = `<div class="agrid">${[artist.al, '现场 · 2025', '单曲合集', '远光 (Deluxe)', '夜航', '星图 EP'].map((a, i) => `<div class="alb" data-act="push" data-v="playlist" data-id="${i}"><div class="cv" style="${coverStyle(artist.h + i * 30, i)}"></div><i class="alb-disc"></i><b>${hl(a, q)}</b><small>${artist.a} · ${2026 - i}</small></div>`).join('')}</div>`;
  if (T === '艺术家') body = `<div>${[...new Set(SONGS.map(s => s.a))].slice(0, 8).map((a, i) => `<div class="row" data-act="push" data-v="artist" data-id="${SONGS.find(s => s.a === a).id}"><div class="cv" style="${coverStyle(i * 60 + 20, 1)};border-radius:24px"></div><div class="tx"><div class="t">${hl(a, q)}</div><div class="s"><span>${12 - i} 万关注 · ${SONGS.filter(s => s.a === a).length} 首</span></div></div><button class="btn sec sm" style="margin-right:14px" data-act="toast" data-msg="已关注 ${a}" data-icon="heartf">关注</button></div>`).join('')}</div>`;
  if (T === 'MV') body = `<div class="mvgrid">${[0, 1, 2, 3, 4, 5].map(i => mvCard(i, 0)).join('')}</div>`;
  return `${head}${related}<div class="rbody" key="${T}${S.rPlat}">${body}</div>`;
}
PAGES.search = { tabPage:true, render:() => {
  const q = S.searchQ.trim();
  if (q && S.searchDone) return `<div class="lh" style="padding-bottom:4px"><h1 style="font-size:24px">「${q}」</h1><button class="ib" data-act="clearQ">${ic('close')}</button></div>${searchResults()}`;
  if (q) return `${largeHead('搜索')}<div class="sugg">
    <div class="sg-row go" data-act="doSearch">${ic('search')}<b>搜索「${q}」</b><span>${S.rPlat === 'all' ? '全部平台' : PLATFORMS.find(x => x.id === S.rPlat).n}</span></div>
    ${suggest(q).map(([i, t, d], k) => `<div class="sg-row" data-act="sq" data-q="${t}" style="--d:${k * 30}ms">${ic(i)}<b>${hl(t, q)}</b><span>${d}</span><i class="sg-fill" data-act="fillQ" data-q="${t}">${ic('arrowUL')}</i></div>`).join('')}</div>`;
  return `${largeHead('搜索')}
    ${S.history.length ? `<div class="sec" style="padding-top:8px"><h2 style="font-size:16px">搜索历史</h2><button class="more" data-act="clearHist">${ic('trash')}</button></div>
    <div class="chips" style="flex-wrap:wrap">${S.history.map(h => `<button class="chip" data-act="sq" data-q="${h}">${h}</button>`).join('')}</div>` : ''}
    <div class="sec"><h2 style="font-size:16px">热搜榜</h2><span class="more">每小时更新</span></div>
    <div class="card m" style="padding:4px 0">${HOT.map((h, i) => `<div class="row" data-act="sq" data-q="${h}" style="height:48px"><div class="no ${i < 3 ? 'top' : ''}">${i + 1}</div><div class="tx"><div class="t" style="font-size:14.5px;font-weight:550">${h}</div></div>${i === 0 ? '<span class="badge acc">热</span>' : i === 3 || i === 7 ? '<span class="badge">新</span>' : ''}<span style="width:12px"></span></div>`).join('')}</div>
    <div class="sec"><h2 style="font-size:16px">按风格探索</h2></div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:0 var(--pad)">${[['城市流行', 300], ['后摇', 225], ['Lo-fi', 280], ['电子', 200], ['民谣', 30], ['钢琴', 190]].map(([n, h], i) => `<div class="cv card" style="${coverStyle(h, i)};height:76px;border-radius:16px;padding:12px;display:flex;align-items:flex-end;border:0" data-act="sq" data-q="${n}"><b style="position:relative;color:#fff;font-size:15px">${n}</b></div>`).join('')}</div>`;
} };
ACT.fillQ = (d, e) => { e && e.stopPropagation(); S.searchQ = d.q + ' '; S._focusQ = true; S.qFocus = true; render(); };
ICONS.music = '<circle cx="7" cy="17" r="3"/><circle cx="17" cy="15" r="3"/><path d="M10 17V5l10-2v12"/>';

/* ================= 发现页：模块化 + 平台推荐区 ================= */
const PLAT_REC = {
  netease:['albums', 'newsongs', 'official', 'plcats', 'genres', 'mvrank', 'videos'],
  qq:['nowlisten', 'mood', 'fresh', 'official', 'mvrank'],
  kugou:['nowlisten', 'mood', 'fresh', 'official', 'videos'],
  kuwo:['newsongs', 'official', 'plcats', 'mvrank'],
  migu:['fresh', 'albums', 'official', 'videos'],
};
const sec = (t, more = '更多') => `<div class="sec"><h2>${t}</h2><button class="more">${more}${ic('right')}</button></div>`;
const REC = {
  albums:() => `${sec('新碟上架')}<div class="hs">${[2, 7, 12, 16, 21, 1].map((id, i) => { const s = SONGS[id]; return `<div class="alb" data-act="push" data-v="playlist" data-id="${i}"><div class="cv" style="${coverStyle(s.h, s.v)}"></div><i class="alb-disc"></i><b>${s.al}</b><small>${s.a}</small></div>`; }).join('')}</div>`,
  newsongs:() => `${sec('新歌速递', '播放')}<div class="chips tight">${['华语', '欧美', '日韩'].map(r => `<button class="chip ${S.newSongReg === r ? 'on' : ''}" data-act="newSongReg" data-v="${r}">${r}</button>`).join('')}</div>
    <div class="hs pages" key="${S.newSongReg}">${[0, 1, 2].map(c => `<div class="col3">${[0, 1, 2].map(r => { const s = SONGS[(c * 3 + r + (S.newSongReg === '欧美' ? 16 : S.newSongReg === '日韩' ? 8 : 0)) % SONGS.length]; return `<div class="c3r" data-act="play" data-id="${s.id}" data-list="all">${cover(s, '', 48)}<div><b>${s.t}</b><small>${s.a}</small></div><span>${ic('play')}</span></div>`; }).join('')}</div>`).join('')}</div>`,
  official:() => `${sec('官方榜')}<div class="hs">${[['飙升榜', 340, [11, 17, 5]], ['新歌榜', 30, [8, 13, 19]], ['热歌榜', 210, [0, 2, 4]], ['原创榜', 150, [7, 21, 12]]].map(([n, h, ids]) => `<div class="rk" style="--h:${h}" data-act="push" data-v="playlist" data-id="${h % 8}"><div class="rk-h"><b>${n}</b><small>每日更新</small></div>${ids.map((id, i) => `<div class="rk-r">${cover(SONGS[id], '', 40)}<b>${i + 1}</b><div><span>${SONGS[id].t}</span><small>${SONGS[id].a}</small></div><em class="${i === 0 ? 'up' : ''}">${i === 0 ? '▲3' : '—'}</em></div>`).join('')}</div>`).join('')}</div>`,
  plcats:() => `${sec('歌单分类', '全部')}<div class="cats">${['华语', '流行', '摇滚', '民谣', '电子', '说唱', '轻音乐', '爵士', '古典', 'ACG', '影视原声', '运动', '学习', '深夜', '治愈'].map((c, i) => `<button style="--d:${i * 20}ms">${c}</button>`).join('')}</div>`,
  genres:() => isIn(S.plat)
    ? `${sec('曲风偏好', '调整')}<div class="genre">${[['城市流行', 34, 300], ['电子', 22, 200], ['后摇', 16, 225], ['华语独立', 14, 30], ['Lo-fi', 9, 280], ['R&B', 5, 340]].map(([n, p, h], i) => `<div class="cv gtile" style="${coverStyle(h, i)}"><b>${n}</b><span><i style="width:${p * 2.6}%"></i></span><small>你的偏好 ${p}%</small></div>`).join('')}</div>`
    : `${sec('曲风分类', '全部')}<div class="genre">${[['流行', 300], ['摇滚', 0], ['电子', 200], ['民谣', 30], ['说唱', 340], ['古典', 225]].map(([n, h], i) => `<div class="cv gtile" style="${coverStyle(h, i)}"><b>${n}</b></div>`).join('')}</div>`,
  mvrank:() => `${sec('MV 排行')}<div class="m">${[0, 1, 2].map(i => { const s = SONGS[(i * 5 + 3) % SONGS.length]; return `<div class="mvr" data-act="toast" data-msg="播放 MV：${s.t}" data-icon="video"><b class="${i === 0 ? 'top' : ''}">${i + 1}</b><div class="cv mv-th" style="${coverStyle(s.h + 20, s.v)}"><span class="mv-d">${fmt(180 + i * 31)}</span></div><div><span>${s.t}</span><small>${s.a} · ${98 - i * 17}万次播放</small></div></div>`; }).join('')}</div>`,
  videos:() => `${sec('推荐视频')}<div class="hs">${[1, 2, 3, 4].map(i => mvCard(i)).join('')}</div>`,
  nowlisten:() => { const hr = new Date().getHours(), slot = hr < 6 ? ['深夜', '安静的夜'] : hr < 11 ? ['早晨', '清醒一下'] : hr < 14 ? ['午间', '午休小憩'] : hr < 18 ? ['下午', '适合专注'] : hr < 22 ? ['傍晚', '下班路上'] : ['夜晚', '睡前放松'];
    return `${sec('适合现在听', '换一批')}<div class="m now" style="${coverStyle(hr * 15, 2)}"><div class="now-t"><small>${String(hr).padStart(2, '0')}:${String(new Date().getMinutes()).padStart(2, '0')} · ${slot[0]}</small><b>${slot[1]}</b><span>根据时间和你最近常听的歌</span></div>
      <div class="now-c">${[3, 9, 15, 22].map((id, i) => `<div class="cv" style="${coverStyle(SONGS[id].h, SONGS[id].v)};--i:${i}"></div>`).join('')}</div><button class="hc-play" data-act="playAll" data-list="daily">${ic('play')}</button></div>
      <div class="chips tight" style="margin-top:12px">${['通勤', '学习', '运动', '开车', '睡前', '做饭'].map(n => `<button class="chip">${n}</button>`).join('')}</div>`; },
  mood:() => `${sec('换个心情听')}<div class="mood">${[['开心', 40, '☼'], ['放松', 170, '～'], ['伤感', 220, '﹏'], ['热血', 0, '⚡'], ['治愈', 140, '♡'], ['思念', 280, '☾']].map(([n, h, g], i) => `<button class="md" style="--h:${h};--d:${i * 40}ms" data-act="playAll" data-list="hot" data-shuffle="1"><i>${g}</i><b>${n}</b></button>`).join('')}</div>`,
  fresh:() => `${sec('新鲜上架', '播放')}<div>${[19, 8, 13, 22].map((id, i) => songRow(SONGS[id], { list:'all', noSwipe:true, tail:`<span class="badge ${i < 2 ? 'acc' : ''}" style="margin-right:14px">${['今天', '今天', '昨天', '3 天前'][i]}</span>` })).join('')}</div>`,
};
ACT.newSongReg = d => { S.newSongReg = d.v; render(); };
function platLoginCard4() {
  const p = plat();
  return `<div class="m plogin4" style="--pc:${p.c};--pc2:${p.c2}"><i class="pl-glow"></i>
    ${platBadge(p, 42)}<div class="pl4-tx"><b>登录${p.n}</b><small>${PLAT_UNLOCK.map(u => u[1]).join(' · ')}</small></div>
    <button class="btn pri sm" data-act="platLogin" data-v="${p.id}">${ic('scan')}登录</button></div>`;
}
function personalAcct() {
  const p = plat(), f = PLAT_FEAT[p.id];
  return `<div class="m pacct" data-act="push" data-v="accounts3p" style="--pc:${p.c};--pc2:${p.c2}">
    <div class="pa-av">${S.platLogin[p.id][0]}${platBadge(p, 18)}</div>
    <div style="flex:1;min-width:0"><b>${S.platLogin[p.id]}</b><div class="pa-meta"><span class="lv">Lv.${f.lv}</span><span class="vip">${f.vip}</span></div></div>
    <div class="pa-num"><b data-count="${f.like}">${f.like}</b><small>喜欢</small></div><div class="pa-num"><b data-count="${f.mine + f.fav}">${f.mine + f.fav}</b><small>歌单</small></div></div>`;
}
const MODS = {
  custom:() => { if (!isIn(S.plat)) return ''; const p = plat(), f = PLAT_FEAT[p.id];
    return `${personalAcct()}<div class="sec"><h2>为你定制</h2><span class="more">${platBadge(p, 16)}&nbsp;${p.n}</span></div><div class="hrow m">${f.hero.map(heroCard).join('')}</div>
      ${f.extra ? `<div class="sec"><h2>${f.extra}</h2><button class="more" data-act="playAll" data-list="all">播放${ic('play')}</button></div><div class="hs">${[19, 8, 13, 22, 10, 3].map(id => { const s = SONGS[id]; return `<div class="nsong" data-act="play" data-id="${id}" data-list="all">${cover(s, '', 56)}<div><b>${s.t}</b><small>${s.a}</small></div></div>`; }).join('')}</div>` : ''}`; },
  mypl:() => { if (!isIn(S.plat)) return ''; const f = PLAT_FEAT[S.plat], seg = f.mySeg[S.myPlSeg] || f.mySeg[0];
    const pls = S.myPlSeg ? PLAYLISTS.slice(2, 6) : [{ ...MY_PLAYLISTS[0], n:f.like }, ...MY_PLAYLISTS.slice(1)];
    return `<div class="sec"><h2>我的歌单</h2><button class="more" data-act="tab" data-v="library">全部${ic('right')}</button></div>
      <div class="m mypl-seg">${f.mySeg.map((n, i) => `<button class="${S.myPlSeg === i ? 'on' : ''}" data-act="myPlSeg" data-v="${i}">${n}<small>${i ? f.fav : (n === '我喜欢' ? f.like : f.mine)}</small></button>`).join('')}<i style="--i:${S.myPlSeg}"></i></div>
      <div class="mypl m" key="${S.myPlSeg}">${pls.slice(0, 4).map((x, i) => `<div class="mp" data-act="push" data-v="playlist" data-id="${x.id}" style="--d:${i * 50}ms"><div class="cv" style="${coverStyle(x.h, x.v)}">${i === 0 && !S.myPlSeg ? `<span class="mp-like">${ic('heartf')}</span>` : ''}</div><div style="min-width:0"><b>${i === 0 && !S.myPlSeg ? '我喜欢的音乐' : x.t}</b><small>${x.n} 首</small></div></div>`).join('')}</div>`; },
  quick:() => `<div class="qk">
    <button data-act="tab" data-v="daily"><span class="ic">${ic('sun')}</span>每日混音</button>
    <button data-act="playAll" data-list="hot" data-shuffle="1"><span class="ic">${ic('wave')}</span>私人电台</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="homeTab" data-v="榜单"><span class="ic">${ic('chart')}</span>排行榜</button></div>`,
  tabs:() => { const p = plat(), logged = isIn(p.id); return `<div style="margin-top:22px">${seg(['精选', '榜单', '歌单'], S.homeTab, 'homeTab')}</div>
    ${S.homeTab === '精选' ? `
      <div class="sec"><h2>${logged ? '推荐歌单' : '热门歌单'}</h2><button class="more" data-act="homeTab" data-v="歌单">更多${ic('right')}</button></div>
      <div class="hs">${PLAYLISTS.slice(0, 6).map(x => `<div class="pl" data-act="push" data-v="playlist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, x.v)}"><span class="pc">${ic('play')}${x.pc}</span></div><div class="t">${x.t}</div></div>`).join('')}</div>
      <div class="sec"><h2>热门榜单</h2><button class="more" data-act="homeTab" data-v="榜单">全部${ic('right')}</button></div>
      <div class="card m" style="padding:6px 0">${LISTS.hot().slice(0, 5).map((id, i) => songRow(SONGS[id], { num:i, list:'hot', noSwipe:true, tail:`<button class="ib heart ${S.liked.has(id) ? 'on' : ''}" data-act="like" data-id="${id}">${ic(S.liked.has(id) ? 'heartf' : 'heart')}</button>` })).join('')}</div>`
    : S.homeTab === '榜单' ? `<div style="padding-top:14px">${[['飙升榜', 300, [11, 17, 5]], ['新歌榜', 40, [8, 13, 19]], ['热歌榜', 200, [0, 2, 4]], ['Hi-Res 榜', 160, [7, 21, 12]]].map(([n, h, ids]) => `
        <div class="card m" style="margin-bottom:12px;padding:14px;display:flex;gap:14px" data-act="push" data-v="playlist" data-id="${h % 8}">
          <div class="cv" style="${coverStyle(h, 2)};width:88px;height:88px;border-radius:14px;display:flex;align-items:flex-end;padding:8px"><b style="position:relative;font-size:15px;color:#fff">${n}</b></div>
          <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:6px">${ids.map((id, i) => `<div style="font-size:13px;color:var(--t2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><b style="color:${i === 0 ? 'var(--accent-text)' : 'var(--t1)'};margin-right:6px">${i + 1}</b>${SONGS[id].t} - ${SONGS[id].a}</div>`).join('')}<div style="font-size:11px;color:var(--t3)">${p.n} · 每日 10:00 更新</div></div></div>`).join('')}</div>`
    : `<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px 14px;padding:16px var(--pad) 0">${PLAYLISTS.map(x => `<div class="pl" style="width:auto" data-act="push" data-v="playlist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, x.v)};width:100%;height:auto;aspect-ratio:1"><span class="pc">${ic('play')}${x.pc}</span></div><div class="t">${x.t}</div></div>`).join('')}</div>`}`; },
  platrec:() => `<div class="recdiv"><span>${platBadge(plat(), 18)}来自${plat().n}</span></div>${PLAT_REC[S.plat].map(k => `<div class="recsec">${REC[k]()}</div>`).join('')}`,
};
PAGES.discover = { tabPage:true, render:() => {
  const logged = isIn(S.plat);
  const mods = S.homeMods.filter(m => m.on).map(m => MODS[m.k]()).join('');
  return `${largeHead('发现', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button>
    <button class="ib" data-act="push" data-v="announcements">${ic('bell')}<i class="dot"></i></button>
    <button class="avatar" data-act="tab" data-v="me" style="margin-left:4px">栗</button>`)}
  <div style="padding:2px var(--pad) 12px">${srcBar()}</div>
  ${S.loading ? skeleton() : `${logged ? '' : platLoginCard4() + `<div class="bn" style="margin-top:16px">${BANNERS.map((b, i) => `<div class="b" style="${coverStyle(b.hue, i)};background-size:140% 140%" data-act="push" data-v="playlist" data-id="${i}"><div class="k">${b.k}</div><div class="h">${b.h}</div><div class="d">${b.d}</div></div>`).join('')}</div><div class="dots">${BANNERS.map((b, i) => `<i class="${i === S.banner ? 'on' : ''}"></i>`).join('')}</div>`}${mods}`}`; } };

/* ================= 我的：去掉接力 / 一起听；云盘 = WebDAV ================= */
PAGES.me = { tabPage:true, render:() => `
  ${largeHead('我的', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button><button class="ib" data-act="push" data-v="appearance">${ic('gear')}</button>`)}
  <div class="m card" style="padding:18px;display:flex;gap:14px;align-items:center" data-act="push" data-v="account">
    <div class="avatar lg">栗</div>
    <div style="flex:1;min-width:0"><b style="font-size:19px">阿栗</b>
      <div style="font-size:12.5px;color:var(--t2);margin-top:3px">UID 10086427 · ali@example.com</div>
      <div style="display:flex;gap:6px;margin-top:8px;align-items:center"><span class="badge acc">${ic('crown')}已激活</span>${Object.keys(S.platLogin).map(id => platBadge(PLATFORMS.find(x => x.id === id), 22)).join('')}</div></div>${ic('right')}</div>
  <div class="m card report4" data-act="push" data-v="stats">
    <div class="r4-tx"><small>本周聆听 · 11.2 – 11.8</small><div class="r4-n"><b data-count="6.2">6.2</b><span>小时</span><em>↑18%</em></div><div class="rp-tags"><span>连续 12 天</span><span>最爱 · 雾港</span></div></div>
    <div class="r4-bars">${[42, 65, 38, 80, 54, 96, 71].map((v, i) => `<i style="height:${v}%;--d:${i * 50}ms" class="${i === 6 ? 'on' : ''}"></i>`).join('')}<div class="r4-d">${'一二三四五六日'.split('').map(x => `<span>${x}</span>`).join('')}</div></div></div>
  <div class="m card otd" data-act="play" data-id="12" data-list="all">${cover(SONGS[12], '', 52)}<div style="flex:1;min-width:0"><small>${ic('history')}那年今日 · 2025.11.02</small><b>一年前的今天，你把「${SONGS[12].t}」听了 9 遍</b></div><span class="ib">${ic('play')}</span></div>
  <div class="qk feat">
    <button data-act="push" data-v="cloud"><span class="ic">${ic('cloud')}</span>音乐云盘</button>
    <button data-act="push" data-v="download"><span class="ic">${ic('download')}</span>下载管理</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="sheet" data-v="timer"><span class="ic">${ic('moon')}${S.timer ? `<em>${S.timer}′</em>` : ''}</span>睡眠定时</button></div>
  ${group('个性化', [
    item({ icon:'palette', color:'violet', label:'外观与界面', val:`${ACCENTS[S.accent].n} · ${BAR_STYLES.find(b => b[0] === S.bar)[1]}`, act:'push', args:{ v:'appearance' } }),
    item({ icon:'quote', color:'pink', label:'歌词', val:S.set.trans ? '显示翻译' : '', act:'push', args:{ v:'lyrics' } }),
    item({ icon:'layers', color:'cyan', label:'系统歌词', sub:'悬浮歌词 · 蓝牙/车机 · 状态栏', act:'push', args:{ v:'syslyrics' } }),
  ])}
  ${group('播放', [
    item({ icon:'play', color:'orange', label:'播放与音质', val:S.quality, act:'push', args:{ v:'playback' } }),
    item({ icon:'globe', color:'red', label:'平台与解析脚本', val:`${plat().n.replace('音乐', '')} · ${curScript().n}`, act:'push', args:{ v:'sources' } }),
    item({ icon:'zap', color:'gold', label:'智能换源', val:S.set.smart ? '已开启' : '已关闭', act:'push', args:{ v:'smart' } }),
    item({ icon:'sliders', color:'teal', label:'均衡器', val:S.eqOn ? S.eqPreset : '关闭', act:'sheet', args:{ v:'eq' } }),
  ])}
  ${group('账号与数据', [
    item({ icon:'link', color:'green', label:'平台账号', val:`已登录 ${Object.keys(S.platLogin).length} 个`, act:'push', args:{ v:'accounts3p' } }),
    item({ icon:'refresh', color:'blue', label:'账号备份与同步', act:'push', args:{ v:'backup' } }),
    item({ icon:'bell', color:'orange', label:'公告', val:'1 条未读', act:'push', args:{ v:'announcements' } }),
    item({ icon:'info', color:'gray', label:'关于与更新', val:'v2.4.0', act:'push', args:{ v:'about' } }),
  ])}` };
delete PAGES.together;
const DAV_FILES = [['folder', '无损', '128 首'], ['folder', 'Live 现场', '36 首'], ['folder', '车载', '64 首']];
PAGES.cloud = { render:() => `${appBar('音乐云盘', { right:`<button class="ib" data-act="openDlg" data-v="davAdd">${ic('plus')}</button>` })}
  <div class="m card dav-st"><div class="dav-ic">${ic('cloud')}<i></i></div><div style="flex:1;min-width:0"><b>家里的 NAS</b><small>WebDAV · dav.example.com · 已连接 86ms</small></div><button class="btn sec sm" data-act="toast" data-msg="连接正常 · 延迟 86ms" data-icon="wifi">测试</button></div>
  <div style="margin:4px 0 6px">${seg(['音乐', '备份'], ['音乐', '备份'][S.davSeg], 'davSegCN')}</div>
  ${S.davSeg === 0 ? `<p class="hint" style="padding:6px var(--pad) 10px">直接播放 WebDAV 上的音乐文件，歌词和封面读取同目录文件；不经过任何平台。</p>
    ${group('/Music', DAV_FILES.map(([i, n, d]) => `<div class="it" data-act="toast" data-msg="打开 /Music/${n}" data-icon="folder"><div class="tile" style="background:${TILE.blue}">${ic(i)}</div><div class="lb"><b>${n}</b><small>${d}</small></div><div class="val">${ic('right')}</div></div>`))}
    <div class="grp-t" style="padding-left:var(--pad)">最近添加</div>
    ${[3, 14, 18, 21, 6].map((id, i) => songRow(SONGS[id], { list:'all', tail:`<span class="badge" style="margin-right:12px">${['FLAC', 'FLAC', 'MP3', 'FLAC', 'M4A'][i]}</span>` })).join('')}`
  : `${group('收藏与歌单备份', [item({ icon:'refresh', color:'teal', label:'每天自动备份', sub:'凌晨 3:00 · 只在 Wi-Fi 下', sw:'autoBackup' }), item({ icon:'cloud', color:'blue', label:'立即备份', act:'toast', args:{ msg:'已上传 lyra-backup-20261102.json', icon:'cloud' } }), item({ icon:'download', color:'orange', label:'从备份恢复', val:'12 份', act:'toast', args:{ msg:'恢复前会先备份当前数据', icon:'info' } })], '备份内容为收藏与歌单 JSON，不包含音频文件')}`}
  ${group('服务器', [item({ icon:'globe', color:'violet', label:'家里的 NAS', sub:'dav.example.com · ali', val:'当前', act:'openDlg', args:{ v:'davAdd' } }), item({ icon:'plus', color:'gray', label:'添加服务器', sub:'坚果云 / Alist / Nextcloud / 群晖', act:'openDlg', args:{ v:'davAdd' } })])}` };
ACT.davSegCN = d => { S.davSeg = d.v === '备份' ? 1 : 0; S._stagger = true; render(); };
FORM_DIALOGS.davAdd = () => `<h3 class="fd-t">添加 WebDAV 服务器</h3><p class="fd-s">选择服务商可自动填好地址格式</p>
  <div class="cats" style="padding:12px 0 4px">${['坚果云', 'Alist', 'Nextcloud', '群晖', '自定义'].map((n, i) => `<button class="${i === (S.dlg.pv || 0) ? 'on' : ''}" data-act="davPv" data-v="${i}">${n}</button>`).join('')}</div>
  <div class="fld" style="margin-top:10px">${ic('globe')}<input placeholder="服务器地址" value="${['https://dav.jianguoyun.com/dav/', 'https://alist.example.com/dav/', 'https://cloud.example.com/remote.php/dav/', 'https://nas.local:5006/', 'https://'][S.dlg.pv || 0]}"></div>
  <div class="fld" style="margin-top:10px">${ic('user')}<input placeholder="用户名"></div>
  <div class="fld" style="margin-top:10px">${ic('lock')}<input type="password" placeholder="密码 / 应用专用密码"></div>
  <div class="fd-acts three"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn sec" data-act="toast" data-msg="连接成功 · 延迟 92ms" data-icon="wifi">测试</button><button class="btn pri" data-act="davSave">保存</button></div>`;
ACT.davPv = d => { S.dlg.pv = +d.v; render(); };
ACT.davSave = () => { S.dialog = null; render(); toast('已添加服务器', 'cloud'); };

/* ================= 皮肤：再加 4 套 + 顶部分类 Tab ================= */
SKINS.push(
  { id:'neon', n:'霓虹', cat:'花样', d:'砖墙上的霓虹灯管：歌名闪烁点亮，灯光随节拍明暗', tag:'新' },
  { id:'film', n:'胶片', cat:'拟物', d:'竖向胶片带：队列封面一帧帧滚过，颗粒与漏光', tag:'新' },
  { id:'terminal', n:'终端', cat:'花样', d:'命令行风格：播放日志、ASCII 进度与频谱', tag:'新' },
  { id:'dial', n:'表盘', cat:'极简', d:'手表表盘：60 格刻度环就是进度条，指针随播放走动', tag:'新' });
SHEETS.skin = () => {
  const cur = SKINS.find(k => k.id === S.skin), tabs = ['全部', ...SKIN_CATS];
  const list = SKINS.filter(k => S.skinTab === '全部' || k.cat === S.skinTab);
  return { t:'播放器皮肤', sub:`${SKINS.length} 套`, dark:true, body:`
    <div class="sk-tabs" style="--i:${tabs.indexOf(S.skinTab)};--n:${tabs.length}"><i></i>${tabs.map(t => `<button class="${S.skinTab === t ? 'on' : ''}" data-act="skinTab" data-v="${t}">${t}<small>${t === '全部' ? SKINS.length : SKINS.filter(k => k.cat === t).length}</small></button>`).join('')}</div>
    <div class="sk-grid" key="${S.skinTab}">${list.map((k, i) => `<button class="sk-card ${S.skin === k.id ? 'on' : ''}" data-act="skin" data-v="${k.id}" style="--d:${i * 35}ms">
      <div class="pv" style="background:#0B0C12">${skinThumb(k.id)}</div>
      <div class="sk-n"><b>${k.n}</b>${k.tag ? `<em>${k.tag}</em>` : ''}<span>${k.cat}</span></div><small>${k.d}</small></button>`).join('')}</div>
    ${cur.id === 'spring' ? `<div class="grp-t">律动 · 歌词动效</div><div style="padding:0 0 10px">${seg(['弹簧瀑布', '波浪漂浮'], S.amWave === 'wave' ? '波浪漂浮' : '弹簧瀑布', 'amWaveCN', 'dark')}</div>` : ''}
    ${cur.bg ? `<div style="padding:4px var(--pad) 10px"><button class="btn sec block" data-act="sheet" data-v="bg">${ic('layers')}背景：${{ blur:'模糊封面', static:'静态流光', flow:'动态流光' }[S.bg]}</button></div>` : ''}` };
};
ACT.skinTab = d => { S.skinTab = d.v; render(); };
const _th = skinThumb;
skinThumb = id => {
  const T = {
    neon:`<div style="position:absolute;inset:0;background:#1a0f14;background-image:linear-gradient(#24151c 1px,transparent 1px),linear-gradient(90deg,#24151c 1px,transparent 1px);background-size:18px 9px"></div><b style="position:absolute;left:0;right:0;top:28px;text-align:center;font:800 20px var(--font);color:#ffd6f5;text-shadow:0 0 6px #ff4fd8,0 0 14px #ff4fd8">夜航</b><i style="position:absolute;left:30%;right:30%;bottom:16px;height:28px;border:2px solid #7df9ff;border-radius:6px;box-shadow:0 0 10px #7df9ff"></i>`,
    film:`<div style="position:absolute;inset:0;background:#111"></div><div style="position:absolute;left:28%;right:28%;top:-10px;bottom:-10px;background:#1c1a17;border-left:7px dotted #555;border-right:7px dotted #555"><i style="display:block;height:34px;margin:12px 4px 6px;${coverStyle(38, 0)}"></i><i style="display:block;height:34px;margin:0 4px;${coverStyle(200, 1)}"></i></div>`,
    terminal:`<div style="position:absolute;inset:0;background:#07090a;padding:8px;font:9px/1.5 ui-monospace,monospace;color:#9fe6a0"><div>$ lyra play</div><div style="color:#F4D28A">[ok] resolved</div><div>[#####----]</div><div>▂▅▇▃▆▂▇▅</div></div>`,
    dial:`<div style="position:absolute;inset:0;background:#0b0c12"></div><div style="position:absolute;left:50%;top:50%;width:78px;height:78px;margin:-39px;border-radius:50%;background:conic-gradient(var(--accent) 0 40%,rgba(255,255,255,.12) 0);mask:radial-gradient(circle,transparent 33px,#000 34px);-webkit-mask:radial-gradient(circle,transparent 33px,#000 34px)"></div><div style="position:absolute;left:50%;top:50%;width:50px;height:50px;margin:-25px;border-radius:50%;${coverStyle(38, 0)}"></div>`,
  };
  return T[id] ? `<div class="skin-pv">${T[id]}</div>` : _th(id);
};
SKIN_RENDER.neon = s => `<div class="player neon ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw">${topBar()}<div class="pmid">
    <div class="ne-sign"><small>— NOW PLAYING —</small><b class="ne-t">${[...s.t].map((c, i) => `<span style="--i:${i}">${c}</span>`).join('')}</b><span class="ne-a">${s.a}</span></div>
    <div class="ne-frame" data-hero>${cover(s)}</div>
    ${lines3()}</div>${progress(s)}${controls()}</div></div>`;
SKIN_RENDER.film = s => { const q = S.queue, i = Math.max(0, q.indexOf(S.cur)), ids = Array.from({ length:9 }, (_, k) => q[(i - 2 + k + q.length) % q.length]);
  return `<div class="player film ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}"><i class="fm-leak"></i><i class="fm-grain"></i>
  <div class="pw">${topBar()}<div class="pmid">
    <div class="fm-strip"><div class="fm-run">${ids.concat(ids).map((id, k) => `<div class="fm-fr ${id === S.cur && k % 9 === 2 ? 'cur' : ''}" ${id === S.cur && k === 2 ? 'data-hero' : ''}><div class="cv" style="${coverStyle(SONGS[id].h, SONGS[id].v)}"></div><span>${String(k % 9 + 30).padStart(4, '0')}</span></div>`).join('')}</div></div>
    <div class="fm-meta"><span>24 FPS</span><span>ISO 400</span><span>FRAME ${String(Math.floor(S.pos * 24)).padStart(5, '0')}</span></div>
    ${info(s)}</div>${progress(s)}${controls()}</div></div>`; };
SKIN_RENDER.terminal = s => `<div class="player term ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw"><div class="tm-top"><button data-act="closePlayer">[ esc ]</button><span>lyra@phone: ~/music</span><button data-act="sheet" data-v="more" data-id="${s.id}" data-ctx="player">[ ··· ]</button></div>
  <div class="pmid tm-body">
    <div><b>$</b> lyra play --id ${s.id} --quality ${S.quality}</div>
    <div class="dim">[${plat().id}] 解析：${curScript().n} · ${curScript().ms}ms</div>
    <div class="ok">[ ok ] ${s.t} — ${s.a}</div>
    <div class="dim">album: ${s.al} · ${fmt(s.dur)} · 44.1kHz / 16bit</div>
    <pre class="tm-spec"></pre>
    <div class="tm-bar"></div>
    <div class="tm-lyr"></div>
    <div><b>$</b> <span class="tm-cur"></span></div></div>
  <div class="tm-ctl"><button data-act="prev">[ prev ]</button><button class="big" data-act="toggle">[ ${S.playing ? 'pause' : 'play'} ]</button><button data-act="next">[ next ]</button><button data-act="like" data-id="${s.id}">[ ${S.liked.has(s.id) ? '♥' : '♡'} ]</button></div></div></div>`;
SKIN_RENDER.dial = s => `<div class="player dial ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw">${topBar()}<div class="pmid">
    <div class="dl-face"><div class="dl-ticks">${Array.from({ length:60 }, (_, i) => `<i style="--a:${i * 6}deg" class="${i % 5 ? '' : 'h'}"></i>`).join('')}</div>
      <div class="dl-arc"></div><div class="dl-knob"><i></i></div>
      <div class="dl-cv" data-hero>${cover(s)}</div>
      <div class="dl-t"><b data-b="pos">${fmt(S.pos)}</b><small>/ ${fmt(s.dur)}</small></div></div>
    <div class="dl-info"><b>${s.t}</b><span>${s.a}</span></div>
    ${lines3()}</div>${controls()}</div></div>`;
const _tick = skinTick;
skinTick = function (beat, p) {
  _tick(beat, p);
  if (!S.playerOpen) return;
  const pl = document.querySelector('.player'); if (!pl) return;
  pl.style.setProperty('--prog', p.toFixed(4));
  if (S.skin === 'terminal') {
    const sp = pl.querySelector('.tm-spec'); if (sp) { const ch = ' ▁▂▃▄▅▆▇█'; sp.textContent = Array.from({ length:28 }, (_, i) => ch[S.playing ? Math.min(8, Math.round((Math.abs(Math.sin(S.pos * (1.3 + i * .21) + i)) * .65 + beat * .4) * 8)) : 0]).join(''); }
    const bar = pl.querySelector('.tm-bar'); if (bar) { const n = 26, f = Math.round(p * n); bar.textContent = `[${'#'.repeat(f)}${'-'.repeat(n - f)}] ${fmt(S.pos)}/${fmt(song().dur)}`; }
    const k = Math.max(0, lyrIdx()), L = LYRICS[k], ly = pl.querySelector('.tm-lyr'), cur = pl.querySelector('.tm-cur');
    if (ly) { const t = [k - 2, k - 1].filter(x => x >= 0).map(x => `<div class="dim">&gt; ${LYRICS[x].o}</div>`).join(''); if (ly.dataset.k != k) { ly.innerHTML = t; ly.dataset.k = k; } }
    if (cur) { const n = Math.ceil(L.o.length * Math.min(1, (S.pos - L.t) / 1.4)); cur.textContent = 'echo "' + L.o.slice(0, Math.max(0, n)) + (n >= L.o.length ? '"' : ''); }
  }
  if (S.skin === 'neon') pl.style.setProperty('--glow', (S.playing ? .55 + beat * .45 : .25).toFixed(3));
};

/* ================= 列入目录 ================= */
if (typeof window !== 'undefined') window.__v4 = true;
