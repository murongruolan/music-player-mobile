/* 核心：状态、路由、渲染、交互、动效与手势。
   对应 Flutter：S ≈ 全局状态；PAGES ≈ 路由表；SHEETS ≈ showModalBottomSheet；FLIP ≈ Hero / AnimatedPositioned。 */
const S = {
  authed:true, authPage:'login', loginSeg:'登录', forgotStep:0, agree:false,
  theme:'dark', accent:0, bar:'liquid', skin:'spring', bg:'flow', tone:'dark', bright:45,
  tab:'discover', stack:[], sheet:null, dialog:null, playerOpen:false, lyricMode:false, amView:'cover',
  playing:true, cur:0, pos:31, vol:.7, queue:SONGS.slice(0,16).map(s=>s.id), queueName:'深夜城市漫游 · 霓虹与雨',
  mode:'loop', liked:new Set([0,4,7,12,17]), speed:1, quality:'SQ', timer:0,
  libSeg:'like', searchQ:'', searchTab:'song', homeTab:'精选', banner:0,
  plat:'netease', script:'auto', picker:false, loading:false, navMin:false,
  particle:'galaxy', amWave:'spring', smartPlat:'netease', myPlSeg:0, dlg:{}, eq:[...EQ_PRESETS['流行']], eqPreset:'流行', eqOn:true, castDev:null,
  matchState:'listen', azLetter:null, scanMode:'scan', scanResult:null, clip:null, history:['夜航星图','雾港','Lo-fi','玻璃海'],
  set:{ trans:true, roma:false, conv:false, blur:true, glow:true, lfs:26, ltfs:15, lgap:10, loff:0,
    fade:true, autoplay:false, autoOpen:false, keepAwake:true, smart:true, gradual:true, crossScript:true,
    crossPlat:true, autoNext:true, nQ:true, nS:true, nA:false, allowDown:true, floatLyric:false, floatLock:false,
    btLyric:true, sbLyric:false, dlConc:3, dlCover:true, dlLyric:true, wifiOnly:true, cache:true, vinylSpin:true,
    haptics:true, pitch:true, finishSong:true, cloudSync:true, autoBackup:true, crash:true, navAutoMin:true, clipDetect:true, reduceMotion:false },
};
S.platLogin = { netease:'小栗子' };
const isIn = pid => !!S.platLogin[pid];
const song = () => SONGS[S.cur];
const plat = () => PLATFORMS.find(p => p.id === S.plat);
const scriptsOf = pid => SCRIPTS.filter(s => s.p.includes(pid));
const curScript = () => S.script === 'auto' ? { n:'自动选择', ms:scriptsOf(S.plat)[0]?.ms || 0, ok:99 } : SCRIPTS.find(s => s.id === S.script);
const LISTS = {
  hot: () => [0,2,4,5,17,7,11,16,14,12],
  daily: () => SONGS.map(s=>s.id).sort((a,b)=>((a*37+11)%24)-((b*37+11)%24)),
  like: () => [...S.liked],
  all: () => SONGS.map(s=>s.id),
  local: () => SONGS.slice().sort((a,b)=>a.t.localeCompare(b.t,'zh')).map(s=>s.id),
};
const listOf = k => (LISTS[k] ? LISTS[k]() : LISTS.all());

/* ================= 通用组件 ================= */
const cover = (s, cls = '', size, extra = '') => `<div class="cv ${cls}" style="${coverStyle(s.h, s.v)}${size ? `;width:${size}px;height:${size}px` : ''}" ${extra}></div>`;
function marquee(text, limit = 11) {
  return text.length > limit ? `<div class="mq run"><span><i>${text}</i><i>${text}</i></span></div>` : `<div class="mq"><span>${text}</span></div>`;
}
const platBadge = (p, size = 22) => `<span class="pb" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .5)}px;background:linear-gradient(140deg,${p.c},${p.c2})">${p.m}</span>`;
const signal = ms => { const n = ms < 400 ? 4 : ms < 700 ? 3 : ms < 1000 ? 2 : 1; return `<span class="sig s${n}">${[1, 2, 3, 4].map(i => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`; };
function songRow(s, o = {}) {
  const cur = S.cur === s.id && !o.noCur;
  const lead = o.num != null ? `<div class="no ${o.num < 3 ? 'top' : ''}">${o.num + 1}</div>` : '';
  const tail = o.tail ?? `${o.heart ? `<button class="ib heart ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}</button>` : ''}
    <button class="ib" data-act="sheet" data-v="more" data-id="${s.id}" data-ctx="${o.ctx || ''}" style="color:var(--t3)">${ic('more')}</button>`;
  const row = `<div class="row ${cur ? 'cur' : ''}" data-act="play" data-id="${s.id}" data-list="${o.list || 'all'}">
    ${lead}${o.noCover ? '' : cover(s)}
    <div class="tx"><div class="t">${s.t}</div><div class="s">${cur ? '<span class="eqm"><i></i><i></i><i></i></span>' : ''}<b class="qb ${s.q === '128k' || s.q === 'HQ' ? 'plain' : ''}">${s.q}</b><span>${s.a} · ${s.al}</span></div></div>
    ${tail}</div>`;
  if (o.noSwipe) return row;
  // 左滑操作：下一首播放 / 收藏 / 更多
  return `<div class="rw"><div class="ra">
    <button style="background:#3D8BF4" data-act="rowNext" data-id="${s.id}">${ic('next')}<span>下一首</span></button>
    <button style="background:var(--accent);color:var(--accent-ink)" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}<span>${S.liked.has(s.id) ? '已收藏' : '收藏'}</span></button>
    <button style="background:#6E7385" data-act="sheet" data-v="more" data-id="${s.id}" data-ctx="${o.ctx || ''}">${ic('more')}<span>更多</span></button></div>${row}</div>`;
}
function appBar(title, o = {}) {
  return `<div class="ab ${o.glass ? 'glass' : ''}"><button class="ib" data-act="back">${ic('left')}</button><div class="ttl" ${o.fade ? 'style="opacity:var(--tt,0)"' : ''}>${title}</div>${o.right || '<div class="sp"></div>'}</div>`;
}
/* Tab 页大标题：滚动时缩小淡出，紧凑标题栏淡入（iOS 式大标题折叠） */
function largeHead(title, right = '') {
  return `<div class="chdr"><b>${title}</b></div><div class="lh"><h1>${title}</h1>${right}</div>`;
}
const TILE = { violet:'#7C6CF2', blue:'#3D8BF4', orange:'#F2994A', green:'#2FB47C', red:'#EB5757', pink:'#E0559B', gold:'#C9A04A', cyan:'#2CB5D6', gray:'#6E7385', teal:'#1FA38E' };
function item(o) {
  const right = o.sw ? `<div class="sw ${S.set[o.sw] ? 'on' : ''}"></div>` : o.val != null ? `<div class="val">${o.val}${o.chev === false ? '' : ic('right')}</div>` : (o.chev === false ? '' : `<div class="val">${ic('right')}</div>`);
  const act = o.sw ? `data-act="tg" data-k="${o.sw}"` : o.act ? `data-act="${o.act}" ${Object.entries(o.args || {}).map(([k, v]) => `data-${k}="${v}"`).join(' ')}` : '';
  return `<div class="it ${o.icon ? '' : 'noic'} ${o.danger ? 'dz' : ''}" ${act}>
    ${o.icon ? `<div class="tile" style="background:${TILE[o.color] || o.color || TILE.gray}">${ic(o.icon)}</div>` : ''}
    <div class="lb"><b>${o.label}</b>${o.sub ? `<small>${o.sub}</small>` : ''}</div>${right}</div>`;
}
const group = (title, items, foot) => `${title ? `<div class="grp-t">${title}</div>` : ''}<div class="grp">${items.join('')}</div>${foot ? `<div class="hint" style="margin:-6px 6px 14px">${foot}</div>` : ''}`;
function slider(label, k, min, max, step, unit = '', fmtFn) {
  const v = S.set[k]; const pct = ((v - min) / (max - min)) * 100;
  return `<div class="sl"><label>${label}</label><input type="range" min="${min}" max="${max}" step="${step}" value="${v}" data-set="${k}" style="--v:${pct}%"><output data-out="${k}">${fmtFn ? fmtFn(v) : v + unit}</output></div>`;
}
/* 分段控件：选中块是独立元素，切换时用 FLIP 平滑滑动 */
function seg(opts, cur, act, cls = '') {
  const i = Math.max(0, opts.indexOf(cur));
  return `<div class="seg ${cls}" style="--n:${opts.length};--i:${i}"><i class="seg-ind" data-flip="seg:${opts.join('|')}"></i>${opts.map(o => `<button class="${o === cur ? 'on' : ''}" data-act="${act}" data-v="${o}">${o}</button>`).join('')}</div>`;
}

/* ================= 状态栏 / 导航 / 迷你播放条 ================= */
function statusBar(light) {
  return `<div class="sb ${light ? 'light' : ''}"><span>9:41</span><span class="ics">
    <svg viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
    <svg viewBox="0 0 18 12"><path d="M9 2.2c2.6 0 5 1 6.8 2.7l1.2-1.3A11.5 11.5 0 0 0 9 .4 11.5 11.5 0 0 0 1 3.6l1.2 1.3A9.7 9.7 0 0 1 9 2.2zm0 3.6c1.6 0 3.1.6 4.3 1.6l1.2-1.3A8 8 0 0 0 9 4a8 8 0 0 0-5.5 2.1l1.2 1.3A6.3 6.3 0 0 1 9 5.8zM9 9.4l2-2.1a3 3 0 0 0-4 0z"/></svg>
    <svg viewBox="0 0 27 12" style="width:27px"><rect x=".5" y=".5" width="23" height="11" rx="3" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="17" height="8" rx="1.6"/><rect x="24.5" y="4" width="1.8" height="4" rx=".8" opacity=".4"/></svg></span></div>`;
}
const NAV = [['discover','compass','发现'],['search','search','搜索'],['daily','sun','每日'],['library','library','音乐库'],['me','user','我的']];
const BAR_STYLES = [['liquid','液态玻璃'],['island','浮岛'],['capsule','胶囊'],['frosted','磨砂一体'],['classic','经典']];
function nav() {
  const items = S.bar === 'capsule' ? NAV.filter(n => n[0] !== 'search') : NAV;
  const nv = items.map(([k, i, n]) => `<button class="nv ${S.tab === k ? 'on' : ''} ${S._navJust === k ? 'just' : ''}" data-act="tab" data-v="${k}" data-ic="${i}">${ic(i)}<span>${n}</span></button>`).join('');
  const fab = S.bar === 'capsule' ? `<button class="fab ${S.tab === 'search' ? 'on' : ''}" data-act="tab" data-v="search">${ic('search')}</button>` : '';
  return `<nav class="nav ${S.bar} ${S.navMin ? 'min' : ''}"><i class="ind"></i><i class="spec"></i>${nv}</nav>${fab}`;
}
function mini() {
  const s = song();
  return `<div class="mini ${S.bar} ${S.navMin ? 'min' : ''}" data-act="openPlayer">${cover(s, 'mcv')}
    <div class="tx"><div class="mtx"><div class="t">${marquee(s.t, 12)}</div><div class="s">${S.castDev ? `投放到 ${S.castDev} · ` : ''}${s.a}</div></div></div>
    <button class="ib" data-act="toggle" style="width:44px"><span class="playb">${ic(S.playing ? 'pause' : 'play')}</span></button>
    <button class="ib nx" data-act="next">${ic('next')}</button>
    <div class="pg"><i data-b="mfill"></i></div></div>`;
}

/* ================= 渲染 ================= */
const scrollMem = {};
/* 当前最上层的页面（.page 后面还跟着迷你播放条等 div，不能用 :last-of-type） */
function topPage(root = document.getElementById('screen')) { const ps = root.querySelectorAll(':scope > .page'); return ps[ps.length - 1] || null; }
function pageHTML(id, params, cls) {
  const P = PAGES[id];
  return `<div class="page ${P.full ? 'noNav' : ''} ${P.tabPage ? 'tabp' : ''} ${cls}" data-sk="${id}${params && params.id != null ? ':' + params.id : ''}">${P.render(params || {})}</div>`;
}
function flipCapture(root) { const m = {}; root.querySelectorAll('[data-flip]').forEach(el => { m[el.dataset.flip] = el.getBoundingClientRect(); }); return m; }
function flipPlay(root, prev) {
  if (S.set.reduceMotion) return;
  root.querySelectorAll('[data-flip]').forEach(el => {
    const a = prev[el.dataset.flip]; if (!a) return; const b = el.getBoundingClientRect(); if (!b.width || !a.width) return;
    const dx = a.left - b.left, dy = a.top - b.top, sx = a.width / b.width, sy = a.height / b.height;
    if (Math.abs(dx) < .5 && Math.abs(dy) < .5 && Math.abs(sx - 1) < .01 && Math.abs(sy - 1) < .01) return;
    el.animate([{ transformOrigin:'0 0', transform:`translate(${dx}px,${dy}px) scale(${sx},${sy})` }, { transformOrigin:'0 0', transform:'none' }],
      { duration:+(el.dataset.flipDur || 520), easing:'cubic-bezier(.3,1.25,.5,1)' });
  });
}
function render() {
  const scr = document.getElementById('screen');
  if (S._freshScroll) { for (const k in scrollMem) delete scrollMem[k]; S._freshScroll = false; }
  else scr.querySelectorAll('[data-sk]').forEach(el => { scrollMem[el.dataset.sk] = el.scrollTop; });
  const prev = flipCapture(scr);
  const navPrev = navRect(scr);
  document.documentElement.dataset.theme = S.theme;
  const ph = document.getElementById('phone'); if (ph) ph.classList.toggle('land', !!(S.playerOpen && S.skin === 'standby'));
  scr.innerHTML = buildScreen();
  scr.querySelectorAll('[data-sk]').forEach(el => { if (scrollMem[el.dataset.sk]) el.scrollTop = scrollMem[el.dataset.sk]; });
  afterRender(scr, prev, navPrev);
  S._anim = null; S._playerAnim = false; S._stagger = false; S._tabDir = 0; S._navJust = null; S._coverIn = 0;
  if (typeof syncSide === 'function') syncSide();
}
function buildScreen() {
  let html = '', light = false;
  if (!S.authed) {
    html += pageHTML(S.authPage, {}, '');
    light = PAGES[S.authPage].lightBar;
  } else {
    const n = S.stack.length, top = n ? S.stack[n - 1] : null;
    if (top && S._anim === 'push') { const under = n >= 2 ? S.stack[n - 2] : { id:S.tab }; html += pageHTML(under.id, under.params, 'page-under'); }
    const enter = S._anim === 'push' ? 'page-enter' : S._tabDir ? (S._tabDir > 0 ? 'tab-in-r' : 'tab-in-l') : '';
    html += top ? pageHTML(top.id, top.params, enter) : pageHTML(S.tab, {}, enter);
    const full = top && PAGES[top.id].full;
    if (!full) html += `<div class="ptr"><i></i></div><button class="totop" data-act="totop">${ic('down')}</button>` + mini() + nav();
    if (top && PAGES[top.id].lightBar) light = true;
    if (S.picker) html += renderPicker();
  }
  if (S.playerOpen) { html += renderPlayer(); light = S.skin !== 'magazine'; }
  if (S.sheet) html += renderSheet();
  if (S.dialog) html += renderDialog();
  if (S.clip) html += clipBanner();
  if (!(S.playerOpen && S.skin === 'standby')) html += statusBar(light);
  return html;
}
function afterRender(scr, prev = {}, navPrev) {
  applyAccent();
  layoutLyrics(true);
  if (typeof mountFx === 'function') mountFx(scr);
  placeNav(scr, navPrev);
  flipPlay(scr, prev);
  const page = topPage(scr);
  if (page) { bindPageScroll(page, scr); onPageScroll(page, scr, true); }
  if (S._stagger && page) stagger(page);
  const bn = scr.querySelector('.bn');
  if (bn) { bn.addEventListener('scroll', () => bannerFx(bn, scr), { passive:true }); bannerFx(bn, scr); }
  const q = scr.querySelector('#q');
  if (q && S._focusQ) { q.focus(); q.setSelectionRange(q.value.length, q.value.length); S._focusQ = false; }
  if (S._heroFrom) heroIn(scr);
  if (S._coverIn) { const h = scr.querySelector('.player [data-hero]'); h && h.animate([{ transform:`translateX(${S._coverIn * 90}px) scale(.9)`, opacity:0 }, { transform:'none', opacity:1 }], { duration:460, easing:'cubic-bezier(.3,1.3,.5,1)' }); }
  if (S.clip) requestAnimationFrame(() => requestAnimationFrame(() => { const c = scr.querySelector('.clipbn'); c && c.classList.add('open'); }));
}
function applyAccent() {
  const a = ACCENTS[S.accent], r = document.documentElement.style;
  const sc = document.getElementById('screen'); if (sc) sc.classList.toggle('reduce', !!S.set.reduceMotion);
  const rgb = a.c.match(/\w\w/g).map(x => parseInt(x, 16));
  r.setProperty('--accent', a.c);
  r.setProperty('--accent-text', S.theme === 'light' ? a.lt : a.c);
  r.setProperty('--accent-ink', a.ink);
  r.setProperty('--accent-soft', `rgba(${rgb},${S.theme === 'light' ? .16 : .14})`);
  r.setProperty('--accent-glow', `rgba(${rgb},.38)`);
}

/* ---------- 导航指示器：液态拉伸（先伸向目标、再收拢，带过冲） ---------- */
function navRect(scr) { const n = scr.querySelector('.nav'), i = n && n.querySelector('.ind'); if (!i || !n) return null; const a = i.getBoundingClientRect(), b = n.getBoundingClientRect(); return a.width ? { l:a.left - b.left, w:a.width } : null; }
function navTarget(nv, on) {
  if (!on) return null;
  if (nv.classList.contains('classic')) return { l:on.offsetLeft + on.offsetWidth / 2 - 14, w:28 };
  const pad = nv.classList.contains('liquid') ? 4 : 0;
  return { l:on.offsetLeft + pad, w:on.offsetWidth - pad * 2 };
}
function placeNav(scr, prev) {
  const nv = scr.querySelector('.nav'); if (!nv) return;
  const ind = nv.querySelector('.ind'), on = nv.querySelector('.nv.on');
  const t = navTarget(nv, on);
  if (!t) { ind.style.opacity = 0; return; }
  ind.style.left = t.l + 'px'; ind.style.width = t.w + 'px'; ind.style.opacity = 1;
  if (prev && Math.abs(prev.l - t.l) > 1 && !S.set.reduceMotion) {
    const l0 = Math.min(prev.l, t.l), r0 = Math.max(prev.l + prev.w, t.l + t.w);
    const forward = t.l > prev.l;
    ind.animate([
      { left:prev.l + 'px', width:prev.w + 'px', transform:'scaleY(1)' },
      { left:(forward ? prev.l : l0) + 'px', width:(r0 - (forward ? prev.l : l0)) * .82 + 'px', transform:'scaleY(.84)', offset:.38 },
      { left:t.l + 'px', width:t.w + 'px', transform:'scaleY(1.06)', offset:.78 },
      { left:t.l + 'px', width:t.w + 'px', transform:'scaleY(1)' },
    ], { duration:560, easing:'cubic-bezier(.3,1.1,.4,1)' });
  }
}

/* ---------- 列表/卡片依次浮现 ---------- */
function stagger(page) {
  if (S.set.reduceMotion) return;
  const els = page.querySelectorAll('.lh,.sec,.row,.card,.pl,.grp,.qk button,.bn,.seg,.srcbar,.note,.hero-cv,.chips');
  let i = 0;
  els.forEach(el => { const r = el.getBoundingClientRect(); if (r.top > 900) return; el.style.setProperty('--d', Math.min(i++, 16) * 32 + 'ms'); el.classList.add('si'); });
  page.querySelectorAll('[data-count]').forEach(el => {
    const to = parseFloat(el.dataset.count), dec = (el.dataset.count.split('.')[1] || '').length, t0 = performance.now();
    const f = now => { const k = Math.min(1, (now - t0) / 900), e = 1 - Math.pow(1 - k, 3); el.textContent = (to * e).toFixed(dec); if (k < 1) requestAnimationFrame(f); };
    requestAnimationFrame(f);
  });
}

/* ---------- 滚动联动：大标题折叠 / 视差 / 底栏最小化 / 回到顶部 ---------- */
function bindPageScroll(page, scr) {
  page._lastY = page.scrollTop;
  page.addEventListener('scroll', () => onPageScroll(page, scr), { passive:true });
}
function onPageScroll(page, scr, init) {
  const y = page.scrollTop;
  page.style.setProperty('--sc', Math.min(1, Math.max(0, (y - 10) / 50)).toFixed(3));
  page.style.setProperty('--sy', Math.max(-120, Math.min(400, y)) + 'px'); page.style.setProperty('--syn', Math.max(-120, Math.min(400, y)));
  page.style.setProperty('--tt', Math.min(1, Math.max(0, (y - 200) / 60)).toFixed(3));
  const t = scr.querySelector('.totop'); if (t) t.classList.toggle('show', y > 700);
  if (init) return;
  const dy = y - (page._lastY || 0); page._lastY = y;
  if (!S.set.navAutoMin || S.tab === 'search' || !['liquid', 'island', 'classic', 'frosted'].includes(S.bar)) return;
  const want = y > 140 && dy > 4 ? true : (dy < -6 || y < 60) ? false : S.navMin;
  if (want !== S.navMin) {
    S.navMin = want;
    scr.querySelectorAll('.nav,.mini').forEach(el => el.classList.toggle('min', want));
    if (!want) setTimeout(() => placeNav(scr, null), 380);
  }
}
function bannerFx(bn, scr) {
  const w = bn.children[0].offsetWidth + 12, mid = bn.scrollLeft;
  [...bn.children].forEach((c, i) => {
    const d = (i * w - mid) / w;
    c.style.transform = `scale(${1 - Math.min(1, Math.abs(d)) * .07})`;
    c.style.backgroundPosition = `${50 + d * 30}% 50%`;
  });
  const i = Math.round(mid / w);
  if (i !== S.banner) { S.banner = i; scr.querySelectorAll('.dots i').forEach((dd, k) => dd.classList.toggle('on', k === i)); }
}

/* ---------- 迷你播放条 → 播放器：封面形变 ---------- */
function heroIn(scr) {
  const from = S._heroFrom; S._heroFrom = null;
  const h = scr.querySelector('.player [data-hero]'); if (!h || S.set.reduceMotion) return;
  const b = h.getBoundingClientRect();
  h.animate([{ transformOrigin:'0 0', transform:`translate(${from.left - b.left}px,${from.top - b.top}px) scale(${from.width / b.width})`, borderRadius:'40px' }, { transformOrigin:'0 0', transform:'none' }],
    { duration:620, easing:'cubic-bezier(.3,1.15,.4,1)' });
}
function heroOut(done) {
  const scr = document.getElementById('screen');
  const p = scr.querySelector('.player'), h = p && p.querySelector('[data-hero]'), m = scr.querySelector('.mini .cv');
  if (!p) return done();
  if (h && m && !S.set.reduceMotion) {
    const a = h.getBoundingClientRect(), b = m.getBoundingClientRect();
    h.animate([{ transformOrigin:'0 0', transform:'none' }, { transformOrigin:'0 0', transform:`translate(${b.left - a.left}px,${b.top - a.top}px) scale(${b.width / a.width})` }], { duration:420, easing:'cubic-bezier(.4,0,.2,1)', fill:'forwards' });
    p.classList.add('fadeout');
  } else p.classList.add('closing');
  setTimeout(done, 400);
}

/* ================= Toast ================= */
let toastT;
function toast(msg, icon = 'check') {
  const el = document.getElementById('toast');
  el.innerHTML = `<span class="ti">${ic(icon)}</span>${msg}`;
  el.classList.remove('show'); void el.offsetWidth; el.classList.add('show'); clearTimeout(toastT);
  toastT = setTimeout(() => el.classList.remove('show'), 1900);
}
function burst(el) {
  if (!el || S.set.reduceMotion) return;
  const r = el.getBoundingClientRect(), box = document.getElementById('phone').getBoundingClientRect();
  for (let i = 0; i < 10; i++) {
    const d = document.createElement('i'); d.className = 'spark';
    d.style.left = r.left - box.left + r.width / 2 + 'px'; d.style.top = r.top - box.top + r.height / 2 + 'px';
    document.getElementById('phone').appendChild(d);
    const a = i / 10 * Math.PI * 2, dist = 22 + Math.random() * 14;
    d.animate([{ transform:'translate(-50%,-50%) scale(1)', opacity:1 }, { transform:`translate(calc(-50% + ${Math.cos(a) * dist}px),calc(-50% + ${Math.sin(a) * dist}px)) scale(.2)`, opacity:0 }], { duration:560, easing:'cubic-bezier(.2,.8,.3,1)' }).onfinish = () => d.remove();
  }
}

/* ================= 播放 ================= */
function playSong(id, listKey) {
  if (listKey) { const l = listOf(listKey); if (l.includes(id)) S.queue = l; }
  if (!S.queue.includes(id)) S.queue = [id, ...S.queue];
  S.cur = id; S.pos = 0; S.playing = true; S._lyrIdx = -1;
}
function step(dir) {
  const q = S.queue, i = q.indexOf(S.cur);
  const n = S.mode === 'shuffle' ? q[(i + 3 + Math.floor(Math.random() * (q.length - 1))) % q.length] : q[(i + dir + q.length) % q.length];
  S.cur = n; S.pos = 0; S._lyrIdx = -1;
}
const lyrIdx = () => { const t = S.pos + S.set.loff; let k = -1; for (let i = 0; i < LYRICS.length; i++) if (LYRICS[i].t <= t) k = i; return k; };
const TAB_ORDER = NAV.map(n => n[0]);

/* ================= 动作表 ================= */
const ACT = {
  tab: d => {
    if (S.tab === d.v && !S.stack.length) { const p = topPage(); p && p.scrollTo({ top:0, behavior:'smooth' }); S.navMin = false; render(); return; }
    S._tabDir = Math.sign(TAB_ORDER.indexOf(d.v) - TAB_ORDER.indexOf(S.tab)) || 1; S._navJust = d.v;
    S.tab = d.v; S.stack = []; S.navMin = false; S.picker = false; S._stagger = true; render();
  },
  push: d => { S.stack.push({ id:d.v, params:{ id:d.id != null ? +d.id : undefined, kind:d.kind } }); S._anim = 'push'; S._stagger = true; S.sheet = null; S.picker = false; S.navMin = false; render(); },
  back: () => {
    if (!S.stack.length) return;
    const top = topPage(); if (top) top.classList.add('page-exit');
    setTimeout(() => { S.stack.pop(); render(); }, 230);
  },
  totop: () => { const p = topPage(); p && p.scrollTo({ top:0, behavior:'smooth' }); },
  play: d => { playSong(+d.id, d.list); render(); },
  rowNext: d => { const id = +d.id; S.queue = S.queue.filter(x => x !== id); S.queue.splice(S.queue.indexOf(S.cur) + 1, 0, id); closeRows(); toast(`「${SONGS[id].t}」将在下一首播放`, 'next'); },
  playAll: d => { const l = listOf(d.list); S.queue = l; if (d.shuffle) S.mode = 'shuffle'; playSong(l[0]); render(); toast(`开始播放 · ${l.length} 首`, 'play'); },
  toggle: (d, e) => { e && e.stopPropagation(); S.playing = !S.playing; render(); },
  next: (d, e) => { e && e.stopPropagation(); step(1); S._coverIn = 1; render(); },
  prev: () => { if (S.pos > 3) S.pos = 0; else { step(-1); S._coverIn = -1; } render(); },
  mode: () => { const m = ['loop', 'one', 'shuffle', 'order']; S.mode = m[(m.indexOf(S.mode) + 1) % 4]; render(); toast({ loop:'列表循环', one:'单曲循环', shuffle:'随机播放', order:'顺序播放' }[S.mode], { loop:'repeat', one:'repeat1', shuffle:'shuffle', order:'order' }[S.mode]); },
  like: (d, e) => {
    e && e.stopPropagation(); const id = d.id != null && d.id !== '' ? +d.id : S.cur; const on = !S.liked.has(id); on ? S.liked.add(id) : S.liked.delete(id);
    closeRows(true); render();
    const el = document.querySelector(`.player .heart[data-id="${id}"]`) || document.querySelector(`.heart[data-id="${id}"]`);
    if (el) { el.classList.add('pop'); if (on) burst(el); }
    toast(on ? '已添加到「我喜欢」' : '已取消收藏', on ? 'heartf' : 'heart');
  },
  openPlayer: () => { const m = document.querySelector('.mini .cv'); S._heroFrom = m ? m.getBoundingClientRect() : null; S.playerOpen = true; S._playerAnim = true; render(); },
  closePlayer: () => heroOut(() => { S.playerOpen = false; render(); }),
  lyricMode: () => { S.lyricMode = !S.lyricMode; render(); },
  amView: d => { S.amView = S.amView === d.v ? 'cover' : d.v; render(); },
  skin: d => { S.skin = d.v; S._lyrIdx = -1; S.amView = 'cover'; render(); if (d.v === 'standby') toast('横屏待机：手机横放充电时会自动进入', 'phone'); },
  particle: d => { S.particle = d.v; render(); },
  sheet: (d, e) => { e && e.stopPropagation(); closeRows(true); S.sheet = { v:d.v, id:d.id != null && d.id !== '' ? +d.id : S.cur, ctx:d.ctx }; render(); },
  closeSheet: () => {
    const sh = document.querySelector('.sheet'), sc = document.querySelector('.scrim');
    sh && sh.classList.add('closing'); sc && sc.classList.add('closing');
    setTimeout(() => { S.sheet = null; render(); }, 230);
  },
  dialog: d => { S.dialog = d.v; render(); },
  closeDialog: () => { const g = document.querySelector('.dlg'); g && g.classList.add('out'); setTimeout(() => { S.dialog = null; render(); }, 180); },
  // 开关：先在 DOM 上切换（让拇指的弹簧动画播完），再重绘
  tg: (d, e) => {
    S.set[d.k] = !S.set[d.k];
    const el = e && e.target.closest('[data-act=tg]'); const sw = el && el.querySelector('.sw');
    if (sw) { sw.classList.toggle('on', S.set[d.k]); setTimeout(render, 260); } else render();
  },
  setv: d => { S[d.k] = isNaN(+d.v) || d.v === '' ? d.v : +d.v; render(); if (d.toast) toast(d.toast); },
  accent: d => { S.accent = +d.v; render(); toast(`主题色：${ACCENTS[S.accent].n}`, 'palette'); },
  theme: d => { S.theme = d.v; render(); },
  bar: d => { S.bar = d.v; S.navMin = false; render(); toast(`底栏：${BAR_STYLES.find(b => b[0] === d.v)[1]}`, 'grid'); },
  homeTab: d => { S.homeTab = d.v; S._stagger = true; render(); },
  libSeg: d => { S.libSeg = d.v; render(); },
  sq: d => { S.searchQ = d.q; if (!S.history.includes(d.q)) S.history.unshift(d.q); S.tab = 'search'; S.stack = []; S._stagger = true; render(); },
  clearQ: () => { S.searchQ = ''; S._focusQ = true; render(); },
  clearHist: () => { S.history = []; render(); toast('已清空搜索历史', 'trash'); },
  quality: d => { S.quality = d.v; render(); toast(`音质已切换为 ${d.v}`, 'hd'); },
  timer: d => { S.timer = +d.v; render(); toast(+d.v ? `将在 ${d.v} 分钟后停止播放` : '已关闭定时', 'moon'); },
  speed: d => { S.speed = +d.v; render(); },
  cast: d => { S.castDev = d.v || null; S.sheet = null; render(); toast(d.v ? `已投放到 ${d.v}` : '已断开投放', 'cast'); },
  eqPreset: d => { S.eqPreset = d.v; S.eq = [...EQ_PRESETS[d.v]]; render(); },
  eqOn: () => { S.eqOn = !S.eqOn; render(); },
  loff: d => { S.set.loff = Math.round((S.set.loff + +d.v) * 10) / 10; render(); },
  seekLine: (d, e) => { e && e.stopPropagation(); S.pos = LYRICS[+d.i].t + .05 - S.set.loff; S._lyrIdx = -1; const l = document.querySelector('.lyr'); l && l.classList.remove('manual'); updateTick(true); toast(`跳转到 ${fmt(S.pos)}`, 'clock'); },
  lyrBack: () => { const l = document.querySelector('.lyr'); l && l.classList.remove('manual'); S._lyrIdx = -1; layoutLyrics(); },
  /* 音源：平台 → 脚本 */
  picker: () => { S.picker = !S.picker; render(); },
  closePicker: () => { const p = document.querySelector('.picker'); if (p) p.classList.add('out'); const sc = document.querySelector('.pk-scrim'); sc && sc.classList.add('closing'); setTimeout(() => { S.picker = false; render(); }, 220); },
  plat: d => { if (S.plat === d.v) return; S.plat = d.v; S.script = 'auto'; render(); reloadContent(false); },
  script: d => { S.script = d.v; render(); setTimeout(() => ACT.closePicker(), 260); toast(`解析：${curScript().n} · ${plat().n}`, 'code'); },
  login: () => { S.authed = true; S.tab = 'discover'; S.stack = []; S._stagger = true; render(); toast('欢迎回来，阿栗', 'sparkle'); },
  loginSeg: d => { S.loginSeg = d.v; render(); },
  authPage: d => { S.authPage = d.v; S.forgotStep = 0; render(); },
  forgotNext: () => { if (S.forgotStep < 2) { S.forgotStep++; render(); } else { S.authPage = 'login'; render(); toast('密码已重置，请重新登录', 'lock'); } },
  agree: () => { S.agree = !S.agree; render(); },
  enterApp: () => { if (!S.agree) return toast('请先阅读并勾选同意', 'info'); S.authPage = 'login'; render(); },
  logout: () => { S.dialog = null; S.authed = false; S.authPage = 'login'; render(); },
  toast: d => toast(d.msg, d.icon || 'check'),
  sheetToast: d => { S.sheet = null; render(); toast(d.msg, d.icon || 'check'); },
  match: () => { S.matchState = 'listen'; render(); clearTimeout(S._mt); S._mt = setTimeout(() => { S.matchState = 'found'; if (S.stack.at(-1)?.id === 'scan' && S.scanMode === 'match') { S._stagger = true; render(); } }, 3200); },
  scanMode: d => { S.scanMode = d.v === '听歌识曲' ? 'match' : 'scan'; S.scanResult = null; if (S.scanMode === 'match') ACT.match(); else render(); },
  scanSim: d => { S.scanResult = d.v; S._stagger = true; render(); },
  scanDone: d => {
    if (d.v === 'tv') { S.scanResult = 'tvdone'; render(); toast('客厅电视已登录', 'tv'); }
    if (d.v === 'playlist') { S.stack = [{ id:'playlist', params:{ id:3 } }]; S._anim = 'push'; S.scanResult = null; render(); }
    if (d.v === 'song') { playSong(7); S.stack = []; S.scanResult = null; ACT.openPlayer(); toast('已打开分享的歌曲', 'link'); }
  },
  clipPlay: () => { playSong(S.clip); S.clip = null; ACT.openPlayer(); toast('已播放好友分享的歌曲', 'link'); },
  clipClose: () => { const c = document.querySelector('.clipbn'); c && c.classList.remove('open'); setTimeout(() => { S.clip = null; render(); }, 420); },
};
function closeRows(silent) { document.querySelectorAll('.rw.open').forEach(r => { r.classList.remove('open'); r.querySelector('.row').style.transform = ''; }); }
function reloadContent(withToast = true) {
  S.loading = true; render();
  setTimeout(() => { S.loading = false; S._stagger = true; render(); if (withToast) toast('已刷新 · 12 条新推荐', 'refresh'); }, 750);
}

/* ================= 事件与手势 ================= */
function bindEvents() {
  const scr = document.getElementById('screen');
  let suppress = false;                                   // 手势结束后吞掉浏览器补发的 click
  scr.addEventListener('click', e => {
    if (suppress) { suppress = false; e.stopPropagation(); e.preventDefault(); return; }
    const el = e.target.closest('[data-act]');
    if (!e.target.closest('.rw.open .ra')) { if (document.querySelector('.rw.open') && !e.target.closest('.ra')) { closeRows(); if (e.target.closest('.rw')) return; } }
    if (!el || !scr.contains(el)) return;
    const fn = ACT[el.dataset.act];
    if (fn) { e.stopPropagation(); fn(el.dataset, e); }
  }, true);
  // 涟漪
  scr.addEventListener('pointerdown', e => {
    const el = e.target.closest('.row,.it,.btn,.chip,.qk button,.ib,.opt-grid button,.seg button,.pk-tile,.pk-row');
    if (!el) return;
    const r = el.getBoundingClientRect(), d = Math.max(r.width, r.height) * 2.2;
    const ink = document.createElement('span'); ink.className = 'ink';
    ink.style.cssText = `width:${d}px;height:${d}px;left:${e.clientX - r.left - d / 2}px;top:${e.clientY - r.top - d / 2}px`;
    if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
    el.style.overflow = 'hidden'; el.appendChild(ink);
    setTimeout(() => ink.remove(), 560);
  });
  // 滑杆与搜索输入
  scr.addEventListener('input', e => {
    const t = e.target;
    if (t.dataset.set) {
      const k = t.dataset.set, v = +t.value; S.set[k] = v;
      t.style.setProperty('--v', ((v - t.min) / (t.max - t.min)) * 100 + '%');
      const o = scr.querySelector(`[data-out="${k}"]`); if (o) o.textContent = k === 'loff' ? (v > 0 ? '+' : '') + v.toFixed(1) + 's' : (k === 'dlConc' ? v : v + 'px');
      document.querySelectorAll('.lyr,.lpv').forEach(l => { l.style.setProperty('--lfs', S.set.lfs + 'px'); l.style.setProperty('--ltfs', S.set.ltfs + 'px'); });
      layoutLyrics();
    } else if (t.dataset.st) {
      S[t.dataset.st] = +t.value; t.style.setProperty('--v', ((t.value - t.min) / (t.max - t.min)) * 100 + '%');
      const o = scr.querySelector(`[data-out="${t.dataset.st}"]`); if (o) o.textContent = t.dataset.st === 'speed' ? (+t.value).toFixed(2) + '×' : t.value + (t.dataset.unit || '');
      if (t.dataset.st === 'bright') document.querySelectorAll('.pbg').forEach(b => b.style.setProperty('--shade', S.tone === 'dark' ? S.bright / 100 : S.bright / 300));
    } else if (t.id === 'q') {
      if (e.isComposing) return;
      S.searchQ = t.value; S._focusQ = true; render();
    }
  });
  scr.addEventListener('compositionend', e => { if (e.target.id === 'q') { S.searchQ = e.target.value; S._focusQ = true; render(); } });

  /* ---- 统一手势分发：按按下位置决定是哪种手势，首次移动 8px 后锁定方向 ---- */
  let g = null;
  const phoneBox = () => document.getElementById('phone').getBoundingClientRect();
  scr.addEventListener('pointerdown', e => {
    if (e.button > 0) return;
    const t = e.target, P = phoneBox();
    const base = { x0:e.clientX, y0:e.clientY, t, id:e.pointerId, moved:false, axis:null, ts:performance.now() };
    if (t.closest('.prog .tr')) { g = { ...base, kind:'seek', tr:t.closest('.prog .tr') }; g.box = g.tr.getBoundingClientRect(); g.tr.parentElement.classList.add('drag'); scr.setPointerCapture(e.pointerId); seekMove(e); return; }
    if (t.closest('.eq .track')) { g = { ...base, kind:'eq', tr:t.closest('.eq .track') }; scr.setPointerCapture(e.pointerId); eqMove(e); return; }
    if (t.closest('.az')) { g = { ...base, kind:'az' }; azMove(e); return; }
    if (t.closest('canvas.fxc')) return;
    if (t.closest('input')) return;
    if (t.closest('.nav') && ['liquid', 'island', 'capsule'].includes(S.bar) && !S.navMin) { g = { ...base, kind:'nav', nav:t.closest('.nav') }; return; }
    if (t.closest('.sheet .grab,.sheet .sh')) { g = { ...base, kind:'sheet', el:t.closest('.sheet') }; return; }
    if (t.closest('.player')) {
      if (t.closest('.lyr')) { const l = t.closest('.lyr'), inn = l.querySelector('.lyr-in'); const m = /translateY\((-?[\d.]+)px/.exec(inn.style.transform); g = { ...base, kind:'lyr', l, inn, base:m ? +m[1] : 0 }; return; }
      g = { ...base, kind:'player', el:t.closest('.player'), hero:t.closest('[data-hero]') }; return;
    }
    if (t.closest('.mini')) { g = { ...base, kind:'mini', el:t.closest('.mini') }; return; }
    if (S.stack.length && e.clientX - P.left < 24) { g = { ...base, kind:'edge' }; return; }
    const rw = t.closest('.rw'); if (rw) { g = { ...base, kind:'row', rw, row:rw.querySelector('.row'), open:rw.classList.contains('open') }; }
    const page = t.closest('.page');
    if (page && !g) g = { ...base, kind:'page', page };
    else if (page && g) g.page = page;
  });
  scr.addEventListener('pointermove', e => {
    if (!g) return;
    const dx = e.clientX - g.x0, dy = e.clientY - g.y0;
    if (g.kind === 'seek') return seekMove(e);
    if (g.kind === 'eq') return eqMove(e);
    if (g.kind === 'az') return azMove(e);
    if (!g.axis) { if (Math.hypot(dx, dy) < 8) return; g.axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y'; g.moved = true; onGestureStart(g); }
    onGestureMove(g, dx, dy, e);
  });
  const end = e => {
    if (!g) return;
    const dx = e.clientX - g.x0, dy = e.clientY - g.y0, v = { x:dx / Math.max(16, performance.now() - g.ts), y:dy / Math.max(16, performance.now() - g.ts) };
    if (g.kind === 'seek') { const k = g.tr.closest('.prog').dataset.kind; if (k === 'vol') S.vol = g.p; else { S.pos = g.p * song().dur; S._lyrIdx = -1; } g.tr.parentElement.classList.remove('drag'); g.tr.style.transform = ''; }
    else if (g.kind === 'eq') render();
    else if (g.kind === 'az') setTimeout(() => { S.azLetter = null; showAz(); }, 500);
    else if (g.moved) { suppress = true; setTimeout(() => { suppress = false; }, 50); onGestureEnd(g, dx, dy, v); }
    g = null;
  };
  scr.addEventListener('pointerup', end);
  scr.addEventListener('pointercancel', end);

  function seekMove(e) {
    const raw = (e.clientX - g.box.left) / g.box.width, p = Math.min(1, Math.max(0, raw)); g.p = p;
    const f = g.tr.querySelector('.fill'), th = g.tr.querySelector('.th');
    f.style.width = p * 100 + '%'; if (th) th.style.left = p * 100 + '%';
    // 橡皮筋：拖出两端时轨道被拉长、变细
    const over = raw < 0 ? -raw : raw > 1 ? raw - 1 : 0;
    g.tr.style.transformOrigin = raw < 0 ? 'right center' : 'left center';
    g.tr.style.transform = over ? `scaleX(${1 + Math.min(over, .4) * .18}) scaleY(${1 - Math.min(over, .4) * .5})` : '';
    const pos = g.tr.parentElement.querySelector('[data-b=pos]'); if (pos && g.tr.closest('.prog').dataset.kind !== 'vol') pos.textContent = fmt(p * song().dur);
  }
  function eqMove(e) {
    const r = g.tr.getBoundingClientRect(); const v = Math.round((0.5 - (e.clientY - r.top) / r.height) * 24);
    S.eq[+g.tr.dataset.b] = Math.max(-12, Math.min(12, v)); S.eqPreset = '自定义'; drawEq();
    g.tr = document.querySelector(`.eq .track[data-b="${g.tr.dataset.b}"]`) || g.tr;
  }
  function azMove(e) { const sp = document.elementFromPoint(e.clientX, e.clientY); if (sp && sp.dataset && sp.dataset.l) { S.azLetter = sp.dataset.l; showAz(); } }
}

function onGestureStart(g) {
  if (g.kind === 'row' && g.axis === 'x') { g.rw.classList.add('drag'); document.querySelectorAll('.rw.open').forEach(r => { if (r !== g.rw) { r.classList.remove('open'); r.querySelector('.row').style.transform = ''; } }); }
  if (g.kind === 'row' && g.axis === 'y') g.kind = 'page';
  if (g.kind === 'edge' && g.axis === 'x') {
    const scr = document.getElementById('screen'), n = S.stack.length, under = n >= 2 ? S.stack[n - 2] : { id:S.tab };
    g.top = topPage(scr); if (!g.top) { g.kind = 'none'; return; }
    g.top.insertAdjacentHTML('beforebegin', pageHTML(under.id, under.params, 'page-under drag'));
    g.under = g.top.previousElementSibling;
  }
  if (g.kind === 'page') g.y0s = g.page.scrollTop;
  if (g.kind === 'nav') g.nav.classList.add('press');
  if (g.kind === 'player') g.el.style.transition = 'none';
}
function onGestureMove(g, dx, dy, e) {
  if (g.kind === 'row' && g.axis === 'x') { const x = Math.min(0, Math.max(-232, (g.open ? -216 : 0) + dx)); g.row.style.transform = `translateX(${x < -216 ? -216 + (x + 216) * .3 : x}px)`; }
  if (g.kind === 'edge' && g.axis === 'x') { const w = g.top.offsetWidth, x = Math.max(0, dx), p = x / w; g.top.style.transform = `translateX(${x}px)`; g.under.style.transform = `translateX(${-24 * (1 - p)}%)`; g.under.style.filter = `brightness(${.7 + .3 * p})`; }
  if (g.kind === 'page' && g.axis === 'y' && (g.page.dataset.sk === 'discover' || g.page.dataset.sk === 'daily') && g.y0s <= 0 && dy > 0) {
    const pull = Math.min(130, dy * .45); g.pull = pull;
    g.page.style.transform = `translateY(${pull}px)`;
    const ptr = document.querySelector('.ptr'); if (ptr) { ptr.style.opacity = Math.min(1, pull / 60); ptr.style.transform = `translate(-50%,${pull * .5}px) scale(${.5 + Math.min(1, pull / 70) * .5})`; ptr.querySelector('i').style.transform = `rotate(${pull * 4}deg)`; ptr.classList.toggle('ready', pull > 64); }
  }
  if (g.kind === 'mini') {
    if (g.axis === 'x') { g.el.querySelector('.mtx').style.transform = `translateX(${dx * .6}px)`; g.el.querySelector('.mtx').style.opacity = 1 - Math.min(.7, Math.abs(dx) / 160); }
    else if (dy < 0) g.el.style.transform = `translateY(${dy * .35}px) scale(${1 - dy * -.0006})`;
  }
  if (g.kind === 'player') {
    if (g.axis === 'y' && dy > 0) { g.el.style.transform = `translateY(${dy}px)`; g.el.style.borderRadius = Math.min(40, dy / 4) + 'px'; }
    if (g.axis === 'x' && g.hero) { g.hero.style.transform = `translateX(${dx}px) rotate(${dx * .02}deg)`; g.hero.style.opacity = 1 - Math.min(.5, Math.abs(dx) / 400); }
  }
  if (g.kind === 'sheet' && dy > 0) g.el.style.transform = `translateY(${dy}px)`;
  if (g.kind === 'lyr' && g.axis === 'y') { g.l.classList.add('manual'); g.inn.style.transform = `translateY(${g.base + dy}px)`; }
  if (g.kind === 'nav') {
    const ind = g.nav.querySelector('.ind'), r = g.nav.getBoundingClientRect(), w = ind.offsetWidth;
    const x = Math.max(4, Math.min(r.width - w - 4, e.clientX - r.left - w / 2));
    ind.style.transition = 'none'; ind.style.left = x + 'px';
  }
}
function onGestureEnd(g, dx, dy, v) {
  const sp = 'transform 420ms cubic-bezier(.3,1.25,.5,1)';
  if (g.kind === 'row') {
    g.rw.classList.remove('drag'); g.row.style.transition = sp;
    const open = (g.open ? -216 : 0) + dx < -90 || v.x < -.5;
    g.rw.classList.toggle('open', open); g.row.style.transform = open ? 'translateX(-216px)' : '';
    setTimeout(() => { g.row.style.transition = ''; }, 430);
  }
  if (g.kind === 'edge') {
    const w = g.top.offsetWidth, go = dx > w * .33 || v.x > .5;
    g.top.style.transition = 'transform 280ms cubic-bezier(.22,1,.36,1)'; g.under.style.transition = 'transform 280ms cubic-bezier(.22,1,.36,1),filter 280ms';
    g.top.style.transform = go ? 'translateX(100%)' : ''; g.under.style.transform = go ? 'none' : 'translateX(-24%)'; g.under.style.filter = go ? 'none' : '';
    setTimeout(() => { if (go) { S.stack.pop(); render(); } else g.under.remove(); }, 290);
  }
  if (g.kind === 'page' && g.pull != null) {
    const ptr = document.querySelector('.ptr');
    if (g.pull > 64) {
      g.page.style.transition = sp; g.page.style.transform = 'translateY(64px)'; ptr && ptr.classList.add('spin');
      setTimeout(() => { reloadContent(); }, 800);
    } else {
      g.page.style.transition = sp; g.page.style.transform = ''; if (ptr) { ptr.style.opacity = 0; ptr.style.transform = ''; }
    }
  }
  if (g.kind === 'mini') {
    const m = g.el.querySelector('.mtx');
    if (g.axis === 'x' && Math.abs(dx) > 60) { const dir = dx < 0 ? 1 : -1; m.style.transition = 'transform 200ms,opacity 200ms'; m.style.transform = `translateX(${-dir * 160}px)`; m.style.opacity = 0; setTimeout(() => { step(dir); render(); const n = document.querySelector('.mini .mtx'); n && n.animate([{ transform:`translateX(${dir * 120}px)`, opacity:0 }, { transform:'none', opacity:1 }], { duration:360, easing:'cubic-bezier(.3,1.2,.5,1)' }); }, 190); }
    else if (g.axis === 'y' && dy < -40) ACT.openPlayer();
    else { m.style.transition = sp; m.style.transform = ''; m.style.opacity = ''; g.el.style.transition = sp; g.el.style.transform = ''; }
  }
  if (g.kind === 'player') {
    g.el.style.transition = 'transform 360ms cubic-bezier(.3,1.2,.5,1),border-radius 360ms';
    if (g.axis === 'y' && (dy > 150 || v.y > .8)) { g.el.style.transition = 'transform 260ms ease-in'; g.el.style.transform = 'translateY(100%)'; setTimeout(() => { S.playerOpen = false; render(); }, 250); }
    else { g.el.style.transform = ''; g.el.style.borderRadius = ''; }
    if (g.axis === 'x' && g.hero) {
      if (Math.abs(dx) > 70 || Math.abs(v.x) > .6) { const dir = dx < 0 ? 1 : -1; g.hero.style.transition = 'transform 220ms ease-in,opacity 220ms'; g.hero.style.transform = `translateX(${-dir * 360}px) rotate(${-dir * 8}deg)`; g.hero.style.opacity = 0; setTimeout(() => { step(dir); S._coverIn = dir; render(); }, 200); }
      else { g.hero.style.transition = sp; g.hero.style.transform = ''; g.hero.style.opacity = ''; }
    }
  }
  if (g.kind === 'sheet') { if (dy > 110 || v.y > .7) ACT.closeSheet(); else { g.el.style.transition = sp; g.el.style.transform = ''; } }
  if (g.kind === 'lyr') { S._lyrDragged = true; const l = g.l; clearTimeout(S._lt); S._lt = setTimeout(() => { l.classList.remove('manual'); S._lyrIdx = -1; layoutLyrics(); }, 4000); }
  if (g.kind === 'nav') {
    g.nav.classList.remove('press');
    const ind = g.nav.querySelector('.ind'), c = ind.offsetLeft + ind.offsetWidth / 2;
    let best = null, bd = 1e9; g.nav.querySelectorAll('.nv').forEach(b => { const d = Math.abs(b.offsetLeft + b.offsetWidth / 2 - c); if (d < bd) { bd = d; best = b; } });
    ind.style.transition = '';
    if (best && best.dataset.v !== S.tab) ACT.tab({ v:best.dataset.v }); else placeNav(document.getElementById('screen'), { l:ind.offsetLeft, w:ind.offsetWidth });
  }
}
function showAz() {
  const b = document.querySelector('.azb'); document.querySelectorAll('.az span').forEach(s => s.classList.toggle('on', s.dataset.l === S.azLetter));
  if (b) { b.style.display = S.azLetter ? 'flex' : 'none'; b.textContent = S.azLetter || ''; if (S.azLetter) b.animate([{ transform:'scale(.6)' }, { transform:'scale(1)' }], { duration:220, easing:'cubic-bezier(.3,1.5,.5,1)' }); }
}

/* ================= 每帧更新 ================= */
let lastT = performance.now();
function updateTick(force) {
  const s = song(), p = Math.min(1, S.pos / s.dur);
  document.querySelectorAll('[data-b=pos]').forEach(el => { if (!el.closest('.drag')) el.textContent = fmt(S.pos); });
  document.querySelectorAll('[data-b=rem]').forEach(el => { el.textContent = '-' + fmt(s.dur - S.pos); });
  document.querySelectorAll('.prog:not([data-kind=vol]) [data-b=fill]').forEach(el => { if (!el.closest('.drag')) el.style.width = p * 100 + '%'; });
  document.querySelectorAll('.prog:not([data-kind=vol]) [data-b=thumb]').forEach(el => { if (!el.closest('.drag')) el.style.left = p * 100 + '%'; });
  document.querySelectorAll('[data-b=mfill]').forEach(el => el.style.width = p * 100 + '%');
  if (!S.playerOpen) return;
  const beatPh = (S.pos * 112 / 60) % 1, beat = S.playing ? Math.exp(-beatPh * 5) : 0;
  const pl = document.querySelector('.player'); if (pl) pl.style.setProperty('--beat', beat.toFixed(3));
  const k = lyrIdx();
  if (k !== S._lyrIdx || force) { S._lyrIdx = k; layoutLyrics(); updateLines(k); }
  if (k >= 0) {
    const L = LYRICS[k], fp = Math.min(1, Math.max(0, (S.pos + S.set.loff - L.t) / (L.d * .92)));
    document.querySelectorAll('.ll.on .w, .stage-l .now .w').forEach(w => w.style.setProperty('--p', fp.toFixed(3)));
    document.querySelectorAll('.ll.on .wd').forEach(w => { const a = +w.dataset.a, b = +w.dataset.b; w.style.setProperty('--wp', Math.min(1, Math.max(0, (fp - a) / (b - a))).toFixed(3)); });
  }
  if (typeof skinTick === 'function') skinTick(beat, p);
  const bars = document.querySelectorAll('.spec i');
  bars.forEach((b, i) => { const n = Math.abs(Math.sin(S.pos * (2.1 + i * .37) + i * 1.7)); const h = S.playing ? 10 + n * 60 * (0.55 + 0.45 * beat) * (1 - Math.abs(i - bars.length / 2) / bars.length) : 6; b.style.height = h + '%'; });
}
function updateLines(k) {
  const g = i => (LYRICS[i] ? LYRICS[i].o : '');
  document.querySelectorAll('.lines3').forEach(el => {
    el.innerHTML = `<div>${g(k - 1)}</div><div class="c">${g(k) || '♪'}</div><div>${g(k + 1)}</div>`;
    if (!S.set.reduceMotion) el.animate([{ transform:'translateY(14px)', opacity:.4 }, { transform:'none', opacity:1 }], { duration:420, easing:'cubic-bezier(.3,1.2,.5,1)' });
  });
  document.querySelectorAll('.stage-l').forEach(st => { st.innerHTML = stageHTML(k); });
}
function stageHTML(k) {
  const g = i => (LYRICS[i] ? LYRICS[i].o : ''), L = LYRICS[Math.max(0, k)];
  return `<div class="seclbl">${L.sec} · ${String(Math.max(0, k) + 1).padStart(2, '0')}/${LYRICS.length}</div><div class="prev" style="margin-top:18px">${g(k - 1)}</div><div class="now"><span class="w">${g(k) || '♪'}</span></div><div class="nx">${g(k + 1)}</div>`;
}
/* 歌词布局：普通模式整块位移；stagger 模式（律动皮肤）逐行位移 + 依距离递增延迟，形成"瀑布"弹簧效果 */
function layoutLyrics(reset) {
  document.querySelectorAll('.lyr').forEach(l => {
    if (l.classList.contains('manual')) return;
    const inn = l.querySelector('.lyr-in'); if (!inn) return;
    const k = Math.max(0, S._lyrIdx ?? lyrIdx()), cur = S._lyrIdx;
    const lines = inn.children;
    [...lines].forEach((el, i) => { el.classList.toggle('on', i === cur); el.classList.toggle('near', Math.abs(i - cur) === 1); });
    const line = lines[k]; if (!line) return;
    const anchor = l.clientHeight * (+l.dataset.anchor || .36);
    const off = anchor - line.offsetTop - line.offsetHeight / 2;
    if (l.classList.contains('stagger')) {
      inn.style.transform = '';
      [...lines].forEach((el, i) => {
        const d = i - k;
        el.style.transitionDelay = reset ? '0ms' : `${d >= 0 ? Math.min(d, 9) * 46 : 0}ms`;
        if (reset) el.style.transition = 'none';
        el.style.transform = `translateY(${off}px) scale(${i === cur ? 1 : .96})`;
        el.style.filter = S.set.blur && i !== cur ? `blur(${Math.min(Math.abs(d), 4) * .55}px)` : 'none';
        el.style.opacity = i === cur ? 1 : Math.max(.22, .55 - Math.abs(d) * .07);
        if (reset) requestAnimationFrame(() => { el.style.transition = ''; });
      });
      return;
    }
    if (reset) inn.style.transition = 'none';
    inn.style.transform = `translateY(${off}px)`;
    if (reset) requestAnimationFrame(() => { inn.style.transition = ''; });
  });
}
function loop(now) {
  const dt = Math.min(.1, (now - lastT) / 1000); lastT = now;
  if (S.playing) { S.pos += dt * S.speed; if (S.pos >= song().dur) { if (S.mode === 'one') S.pos = 0; else { step(1); render(); } } }
  updateTick();
  requestAnimationFrame(loop);
}
setInterval(() => {
  const bn = document.querySelector('.bn'); if (!bn || bn.matches(':hover')) return;
  const w = bn.children[0].offsetWidth + 12, n = bn.children.length;
  bn.scrollTo({ left:((S.banner + 1) % n) * w, behavior:'smooth' });
}, 4500);
