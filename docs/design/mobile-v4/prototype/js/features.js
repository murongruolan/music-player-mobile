/* v3：平台登录态与个性化发现页、导入（歌单 / 音源）、智能换源重构、我的页去重（接力 / 一起听 / 云盘）、
   皮肤重整（新增 待机·横屏 / 磁带 / 像素 / 杂志）、皮肤与背景分开设置。
   本文件在 pages.js / settings.js / player.js 之后加载，会覆盖其中的同名页面。 */

const PLAT_FEAT = {
  netease:{ nick:'小栗子', lv:8, vip:'黑胶VIP', like:128, mine:12, fav:8,
    hero:[{ k:'daily', t:'每日推荐', d:'每天 06:00 按你的口味更新' }, { k:'heart', t:'心动模式', d:'从你喜欢的歌出发，越听越懂你' }],
    mySeg:['我创建的', '我收藏的'], extra:null },
  qq:{ nick:'阿栗', lv:6, vip:'绿钻', like:342, mine:9, fav:15,
    hero:[{ k:'daily', t:'每日 30 首', d:'每天为你挑 30 首' }, { k:'radar', t:'雷达推荐', d:'扫描你的口味，雷达捕捉新歌' }],
    mySeg:['我喜欢', '个人歌单'], extra:'新歌推荐' },
  kugou:{ nick:'阿栗', lv:5, vip:'概念VIP', like:96, mine:4, fav:6,
    hero:[{ k:'daily', t:'每日推荐', d:'今日为你精选' }, { k:'heart', t:'猜你喜欢', d:'私人电台，一直播下去' }], mySeg:['我喜欢', '自建歌单'], extra:'新歌首发' },
  kuwo:{ nick:'阿栗', lv:4, vip:'豪华VIP', like:51, mine:3, fav:2,
    hero:[{ k:'daily', t:'每日推荐', d:'今日为你精选' }, { k:'radar', t:'私人 FM', d:'按口味连续播放' }], mySeg:['我喜欢', '自建歌单'], extra:null },
  migu:{ nick:'阿栗', lv:3, vip:'白金会员', like:20, mine:2, fav:1,
    hero:[{ k:'daily', t:'每日推荐', d:'今日为你精选' }, { k:'radar', t:'新歌雷达', d:'首发新歌第一时间推给你' }], mySeg:['我喜欢', '自建歌单'], extra:'新歌首发' },
};
const PLAT_UNLOCK = [['sun', '每日推荐'], ['heartf', '心动 / 雷达'], ['library', '你的歌单'], ['cloud', '收藏同步']];

/* ================= 发现页：按平台登录态个性化 ================= */
function fanCovers(ids) { return `<div class="fan">${ids.map((id, i) => `<div class="cv" style="${coverStyle(SONGS[id].h, SONGS[id].v)};--i:${i}"></div>`).join('')}</div>`; }
function heroCard(h, i) {
  const daily = h.k === 'daily';
  const vis = daily ? `<div class="hc-date"><b>02</b><span>NOV</span></div>${fanCovers([4, 11, 17])}`
    : h.k === 'heart' ? `<svg class="ekg" viewBox="0 0 160 44"><path d="M0 24h38l6-10 7 22 8-30 7 30 6-12h88"/></svg><div class="hc-heart">${ic('heartf')}</div>`
    : `<div class="rdr"><i></i><i></i><i></i><b></b>${[[30, 40], [64, 22], [52, 70], [78, 58]].map(([x, y], k) => `<em style="left:${x}%;top:${y}%;--d:${k * .6}s"></em>`).join('')}</div>`;
  return `<div class="hcard ${h.k}" style="${daily ? coverStyle(300, 2) : ''};--d:${i * 70}ms" data-act="${daily ? 'push' : 'playAll'}" ${daily ? 'data-v="playlist" data-id="1"' : 'data-list="hot" data-shuffle="1"'}>
    ${vis}<div class="hc-tx"><b>${h.t}</b><small>${h.d}</small></div>
    <button class="hc-play" data-act="playAll" data-list="${daily ? 'daily' : 'hot'}">${ic('play')}</button></div>`;
}
function platPersonal() {
  const p = plat(), f = PLAT_FEAT[p.id], seg = f.mySeg[S.myPlSeg] || f.mySeg[0];
  const pls = (S.myPlSeg ? PLAYLISTS.slice(2, 6) : [{ ...MY_PLAYLISTS[0], t:seg === '我喜欢' ? '我喜欢的音乐' : '我喜欢的音乐', n:f.like }, ...MY_PLAYLISTS.slice(1)]);
  return `
  <div class="m pacct" data-act="push" data-v="accounts3p" style="--pc:${p.c};--pc2:${p.c2}">
    <div class="pa-av">${S.platLogin[p.id][0]}${platBadge(p, 18)}</div>
    <div style="flex:1;min-width:0"><b>${S.platLogin[p.id]}</b><div class="pa-meta"><span class="lv">Lv.${f.lv}</span><span class="vip">${f.vip}</span></div></div>
    <div class="pa-num"><b data-count="${f.like}">${f.like}</b><small>喜欢</small></div><div class="pa-num"><b data-count="${f.mine + f.fav}">${f.mine + f.fav}</b><small>歌单</small></div></div>
  <div class="sec"><h2>为你定制</h2><span class="more">${platBadge(p, 16)}&nbsp;${p.n}</span></div>
  <div class="hrow m">${f.hero.map(heroCard).join('')}</div>
  ${f.extra ? `<div class="sec"><h2>${f.extra}</h2><button class="more" data-act="playAll" data-list="all">播放${ic('play')}</button></div>
    <div class="hs">${[19, 8, 13, 22, 10, 3].map(id => { const s = SONGS[id]; return `<div class="nsong" data-act="play" data-id="${id}" data-list="all">${cover(s, '', 56)}<div><b>${s.t}</b><small>${s.a}</small></div></div>`; }).join('')}</div>` : ''}
  <div class="sec"><h2>我的歌单</h2><button class="more" data-act="tab" data-v="library">全部${ic('right')}</button></div>
  <div class="m mypl-seg">${f.mySeg.map((n, i) => `<button class="${S.myPlSeg === i ? 'on' : ''}" data-act="myPlSeg" data-v="${i}">${n}<small>${i ? f.fav : (n === '我喜欢' ? f.like : f.mine)}</small></button>`).join('')}<i style="--i:${S.myPlSeg}"></i></div>
  <div class="mypl m" key="${S.myPlSeg}">${pls.slice(0, 4).map((x, i) => `<div class="mp" data-act="push" data-v="playlist" data-id="${x.id}" style="--d:${i * 50}ms"><div class="cv" style="${coverStyle(x.h, x.v)}">${i === 0 && !S.myPlSeg ? `<span class="mp-like">${ic('heartf')}</span>` : ''}</div><div style="min-width:0"><b>${x.t}</b><small>${x.n} 首</small></div></div>`).join('')}</div>`;
}
function platLoginCard() {
  const p = plat();
  return `<div class="m plogin" style="--pc:${p.c};--pc2:${p.c2}">
    <div class="pl-glow"></div>
    <div class="pl-top">${platBadge(p, 44)}<div><b>登录${p.n}</b><small>解锁你在 ${p.n.replace('音乐', '')} 的专属内容</small></div></div>
    <div class="pl-un">${PLAT_UNLOCK.map(([i, n], k) => `<span style="--d:${k * 80}ms">${ic(i)}${n}</span>`).join('')}</div>
    <div class="pl-btns"><button class="btn pri" data-act="platLogin" data-v="${p.id}">${ic('scan')}扫码登录</button><button class="btn sec" data-act="platLogin" data-v="${p.id}" data-mode="手机号">其他方式</button></div>
    <p>登录信息只保存在本机 · 不登录也能搜索和播放</p></div>`;
}
PAGES.discover = { tabPage:true, render:() => {
  const p = plat(), logged = isIn(p.id);
  return `
  ${largeHead('发现', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button>
    <button class="ib" data-act="push" data-v="announcements">${ic('bell')}<i class="dot"></i></button>
    <button class="avatar" data-act="tab" data-v="me" style="margin-left:4px">栗</button>`)}
  <div style="padding:2px var(--pad) 14px">${srcBar()}</div>
  ${S.loading ? skeleton() : logged ? platPersonal() + `<div style="height:8px"></div>` : `${platLoginCard()}
    <div class="bn" style="margin-top:18px">${BANNERS.map((b, i) => `<div class="b" style="${coverStyle(b.hue, i)};background-size:140% 140%" data-act="push" data-v="playlist" data-id="${i}"><div class="k">${b.k}</div><div class="h">${b.h}</div><div class="d">${b.d}</div></div>`).join('')}</div>
    <div class="dots">${BANNERS.map((b, i) => `<i class="${i === S.banner ? 'on' : ''}"></i>`).join('')}</div>`}
  ${S.loading ? '' : `
  <div class="qk">
    <button data-act="tab" data-v="daily"><span class="ic">${ic('sun')}</span>每日混音</button>
    <button data-act="playAll" data-list="hot" data-shuffle="1"><span class="ic">${ic('wave')}</span>私人电台</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="homeTab" data-v="榜单"><span class="ic">${ic('chart')}</span>排行榜</button></div>
  <div style="margin-top:22px">${seg(['精选', '榜单', '歌单'], S.homeTab, 'homeTab')}</div>
  ${S.homeTab === '精选' ? `
    <div class="sec"><h2>${logged ? '推荐歌单' : '热门歌单'}</h2><button class="more" data-act="homeTab" data-v="歌单">更多${ic('right')}</button></div>
    <div class="hs">${PLAYLISTS.slice(0, 6).map(x => `<div class="pl" data-act="push" data-v="playlist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, x.v)}"><span class="pc">${ic('play')}${x.pc}</span></div><div class="t">${x.t}</div></div>`).join('')}</div>
    <div class="sec"><h2>热门榜单</h2><button class="more" data-act="homeTab" data-v="榜单">全部${ic('right')}</button></div>
    <div class="card m" style="padding:6px 0">${LISTS.hot().slice(0, 5).map((id, i) => songRow(SONGS[id], { num:i, list:'hot', noSwipe:true, tail:`<button class="ib heart ${S.liked.has(id) ? 'on' : ''}" data-act="like" data-id="${id}">${ic(S.liked.has(id) ? 'heartf' : 'heart')}</button>` })).join('')}</div>`
  : S.homeTab === '榜单' ? `<div style="padding-top:14px">${[['飙升榜', 300, [11, 17, 5]], ['新歌榜', 40, [8, 13, 19]], ['热歌榜', 200, [0, 2, 4]], ['Hi-Res 榜', 160, [7, 21, 12]]].map(([n, h, ids]) => `
      <div class="card m" style="margin-bottom:12px;padding:14px;display:flex;gap:14px" data-act="push" data-v="playlist" data-id="${h % 8}">
        <div class="cv" style="${coverStyle(h, 2)};width:88px;height:88px;border-radius:14px;display:flex;align-items:flex-end;padding:8px"><b style="position:relative;font-size:15px;color:#fff">${n}</b></div>
        <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:6px">${ids.map((id, i) => `<div style="font-size:13px;color:var(--t2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><b style="color:${i === 0 ? 'var(--accent-text)' : 'var(--t1)'};margin-right:6px">${i + 1}</b>${SONGS[id].t} - ${SONGS[id].a}</div>`).join('')}<div style="font-size:11px;color:var(--t3)">${p.n} · 每日 10:00 更新</div></div></div>`).join('')}</div>`
  : `<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px 14px;padding:16px var(--pad) 0">${PLAYLISTS.map(x => `<div class="pl" style="width:auto" data-act="push" data-v="playlist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, x.v)};width:100%;height:auto;aspect-ratio:1"><span class="pc">${ic('play')}${x.pc}</span></div><div class="t">${x.t}</div></div>`).join('')}</div>`}`}`; } };
ACT.myPlSeg = d => { S.myPlSeg = +d.v; render(); };

/* ================= 平台登录 Sheet ================= */
function qrSvg(seed) {
  let a = seed * 9301 + 49297; const r = () => ((a = (a * 16807) % 2147483647) / 2147483647);
  const N = 25, c = []; const finder = (x, y) => { for (let i = 0; i < 7; i++) for (let j = 0; j < 7; j++) { const e = i === 0 || i === 6 || j === 0 || j === 6 || (i > 1 && i < 5 && j > 1 && j < 5); if (e) c.push([x + i, y + j]); } };
  finder(0, 0); finder(N - 7, 0); finder(0, N - 7);
  for (let i = 0; i < N; i++) for (let j = 0; j < N; j++) { const inF = (i < 8 && j < 8) || (i > N - 9 && j < 8) || (i < 8 && j > N - 9); if (!inF && r() > .52) c.push([i, j]); }
  return `<svg viewBox="-1 -1 ${N + 2} ${N + 2}" class="qr">${c.map(([x, y]) => `<rect x="${x}" y="${y}" width="1.02" height="1.02" rx=".2"/>`).join('')}</svg>`;
}
SHEETS.platLogin = () => {
  const p = PLATFORMS.find(x => x.id === S.dlg.plat), st = S.dlg.st || 0, mode = S.dlg.mode || '扫码';
  return { t:'', body:`<div class="plsheet" style="--pc:${p.c};--pc2:${p.c2}">
    <div class="pls-h">${platBadge(p, 40)}<div><b>登录${p.n}</b><small>用于同步该平台的歌单、收藏与每日推荐</small></div></div>
    ${seg(['扫码', '手机号', 'Cookie'], mode, 'loginMode')}
    ${mode === '扫码' ? `<div class="qrbox ${st ? 'scanned' : ''}">${qrSvg(p.c.length + p.id.length)}<div class="qr-logo">${platBadge(p, 34)}</div>
        ${st ? `<div class="qr-ok"><div class="avatar">栗</div><b>${st === 2 ? '登录成功' : '已扫码'}</b><small>${st === 2 ? '正在同步你的歌单…' : '请在手机上确认登录'}</small></div>` : '<i class="qr-scan"></i>'}</div>
      <p class="pls-tip">${st ? '' : `打开 <b>${p.n} App</b>，点击左上角「扫一扫」<span class="dots3"><i></i><i></i><i></i></span>`}</p>
      ${st ? '' : `<button class="btn ghost block" data-act="qrScan">原型演示：模拟扫码成功</button>`}`
    : mode === '手机号' ? `<div style="padding:16px 0 0"><div class="fld">${ic('phone')}<input placeholder="手机号" value="138 0000 0000"></div><div class="fld" style="margin-top:10px">${ic('key')}<input placeholder="短信验证码"><button class="act" data-act="toast" data-msg="验证码已发送" data-icon="phone">获取</button></div><button class="btn pri block" style="margin-top:16px" data-act="qrScan">登录</button></div>`
    : `<div style="padding:16px 0 0"><textarea class="ta" placeholder="从浏览器开发者工具中复制 Cookie 粘贴到这里"></textarea><button class="btn pri block" style="margin-top:12px" data-act="qrScan">验证并登录</button></div>`}
  </div>` };
};
ACT.platLogin = d => { S.dlg = { plat:d.v || S.plat, st:0, mode:d.mode || '扫码' }; S.picker = false; S.sheet = { v:'platLogin' }; render(); };
ACT.loginMode = d => { S.dlg.mode = d.v; render(); };
ACT.qrScan = () => {
  S.dlg.st = 1; render();
  setTimeout(() => { S.dlg.st = 2; render(); }, 1100);
  setTimeout(() => {
    const pid = S.dlg.plat; S.platLogin[pid] = PLAT_FEAT[pid].nick; S.sheet = null;
    if (S.plat === pid && S.tab === 'discover' && !S.stack.length) reloadContent(false); else render();
    toast(`已登录${PLATFORMS.find(x => x.id === pid).n}`, 'check');
  }, 2000);
};
ACT.platLogout = d => { delete S.platLogin[d.v]; render(); toast(`已退出${PLATFORMS.find(x => x.id === d.v).n}`, 'logout'); };
PAGES.accounts3p = { render:() => `${appBar('平台账号')}
  <div class="note">${ic('link')}<span>登录平台账号后，发现页会显示该平台的每日推荐、心动/雷达模式和你的歌单。账号凭据只保存在本机。</span></div>
  ${group('平台', PLATFORMS.map(p => `<div class="it">${platBadge(p, 30)}<div class="lb"><b>${p.n}</b><small>${isIn(p.id) ? `已登录 · ${S.platLogin[p.id]} · ${PLAT_FEAT[p.id].vip}` : '未登录'}</small></div><button class="btn ${isIn(p.id) ? 'sec' : 'pri'} sm" data-act="${isIn(p.id) ? 'platLogout' : 'platLogin'}" data-v="${p.id}">${isIn(p.id) ? '退出' : '登录'}</button></div>`))}` };

/* ================= 表单弹窗：导入歌单 / 新建歌单 / 导入音源 ================= */
const PL_LINK = { netease:'https://music.163.com/playlist?id=7458102936', qq:'https://y.qq.com/n/ryqq/playlist/8837261540', kugou:'https://www.kugou.com/songlist/gcid_3zk8q2xz/', kuwo:'https://www.kuwo.cn/playlist_detail/3489016', migu:'https://music.migu.cn/v3/music/playlist/228114498' };
const SAMPLE_SCRIPT = `/**
 * @name 解析脚本 E
 * @version 1.0.0
 * @platforms netease, qq, kugou
 * @quality HQ, SQ
 */
export async function resolve({ platform, id, quality }) {
  // 返回可播放的地址
}`;
const val = id => { const el = document.getElementById(id); return el ? el.value : ''; };
const FORM_DIALOGS = {
  importPlaylist: () => {
    const d = S.dlg, p = PLATFORMS.find(x => x.id === d.plat);
    if (d.step === 1) return `<div class="fd-load"><i class="spinner"></i><b>正在解析歌单…</b><small>${p.n} · 读取歌曲列表与封面</small></div>`;
    if (d.step === 2) { const pl = PLAYLISTS[3]; return `<h3 class="fd-t">确认导入</h3>
      <div class="fd-prev"><div class="cv" style="${coverStyle(pl.h, pl.v)}"></div><div><b>${pl.t}</b><small>${platBadge(p, 16)} ${p.n} · ${pl.by}</small><div class="fd-stat"><span><b>42</b>首</span><span class="ok"><b>40</b>可播放</span><span class="warn"><b>2</b>暂无音源</span></div></div></div>
      ${group('', [item({ label:'保持与原歌单同步', sub:'原歌单更新时自动同步新增歌曲', sw:'cloudSync' })])}
      <div class="fd-acts"><button class="btn sec" data-act="dlgBack">返回</button><button class="btn pri" data-act="dlgDone">导入到音乐库</button></div>`; }
    return `<h3 class="fd-t">导入歌单</h3><p class="fd-s">把其他平台的歌单复制到 Lyra</p>
      <div class="fd-lbl">来源平台</div>
      <div class="fd-plats">${PLATFORMS.map(x => `<button class="${x.id === d.plat ? 'on' : ''}" data-act="dlgPlat" data-v="${x.id}">${platBadge(x, 30)}<span>${x.n.replace('音乐', '')}</span>${x.id === d.plat ? '<i data-flip="fdring"></i>' : ''}</button>`).join('')}</div>
      <div class="fd-lbl">歌单链接或 ID</div>
      <div class="fld ${d.detected ? 'ok' : ''}">${ic('link')}<input id="dlgIn" placeholder="粘贴分享链接，或输入歌单 ID" value="${d.val || ''}"></div>
      ${d.detected ? `<div class="fd-det">${ic('check')}已识别为 ${p.n} 歌单链接，平台已自动切换</div>` : `<div class="fd-det mute">支持分享链接、短链和纯数字 ID，粘贴链接会自动识别平台</div>`}
      <div class="fd-acts three"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn sec" data-act="dlgPaste">${ic('copy')}粘贴</button><button class="btn pri" data-act="dlgImport">确认导入</button></div>`;
  },
  newPlaylist: () => `<h3 class="fd-t">新建歌单</h3>
    <div class="fd-cv"><div class="cv" style="${coverStyle(140, 2)}"></div><button data-act="toast" data-msg="从相册选择封面" data-icon="album">${ic('edit')}</button></div>
    <div class="fld">${ic('edit')}<input id="dlgIn" placeholder="歌单名称" value="${S.dlg.val || ''}"></div>
    ${group('', [item({ label:'设为私密', sub:'只有自己能看到', sw:'pitch' })])}
    <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn pri" data-act="newPlDone">创建</button></div>`,
  urlScript: () => `<h3 class="fd-t">从链接导入音源</h3><p class="fd-s">输入解析脚本的下载地址（.js）</p>
    <div class="fld">${ic('link')}<input id="dlgIn" placeholder="https://…/script.js" value="${S.dlg.val || ''}"></div>
    ${S.dlg.step === 1 ? `<div class="fd-det"><i class="spinner sm"></i>正在下载并校验…</div>` : '<div class="fd-det mute">只从你信任的来源导入，脚本会在沙箱中运行</div>'}
    <div class="fd-acts three"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn sec" data-act="urlPaste">${ic('copy')}粘贴</button><button class="btn pri" data-act="scriptImport" data-src="url">导入</button></div>`,
  pasteScript: () => {
    const d = S.dlg;
    if (d.step === 2) return `<h3 class="fd-t">确认导入音源</h3>
      <div class="fd-meta"><div class="pk-ic" style="background:var(--accent);color:var(--accent-ink)">${ic('code')}</div><div><b>解析脚本 E <em>v1.0.0</em></b><small>支持 ${['netease', 'qq', 'kugou'].map(id => platBadge(PLATFORMS.find(x => x.id === id), 16)).join('')} · HQ / SQ</small></div></div>
      <div class="fd-det">${ic('shield')}已通过格式校验，脚本将在沙箱中运行，无法访问你的账号凭据</div>
      <div class="fd-acts"><button class="btn sec" data-act="dlgBack">返回修改</button><button class="btn pri" data-act="scriptDone">导入</button></div>`;
    return `<h3 class="fd-t">粘贴脚本</h3><p class="fd-s">直接粘贴或手写解析脚本代码</p>
      <div class="ta-wrap"><textarea id="dlgTa" class="ta code" spellcheck="false" placeholder="/** @name 脚本名称 @version 1.0.0 */&#10;export async function resolve(...) { }">${d.val || ''}</textarea><span class="ta-n">${(d.val || '').split('\n').length} 行</span></div>
      ${d.step === 1 ? `<div class="fd-det"><i class="spinner sm"></i>正在校验脚本…</div>` : ''}
      <div class="fd-acts three"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn sec" data-act="scriptPaste">${ic('copy')}粘贴脚本</button><button class="btn pri" data-act="scriptImport" data-src="paste">导入</button></div>`;
  },
};
ACT.openDlg = d => { S.sheet = null; S.dlg = { plat:S.plat, val:'', step:0 }; S.dialog = d.v; render(); };
ACT.dlgPlat = d => { S.dlg.val = val('dlgIn'); S.dlg.plat = d.v; S.dlg.detected = false; render(); };
ACT.dlgPaste = () => { const order = PLATFORMS.map(x => x.id); const pid = S.dlg.detected ? order[(order.indexOf(S.dlg.plat) + 1) % order.length] : S.dlg.plat; S.dlg.plat = pid; S.dlg.val = PL_LINK[pid]; S.dlg.detected = true; render(); };
ACT.dlgImport = () => { S.dlg.val = val('dlgIn'); if (!S.dlg.val.trim()) return toast('先粘贴歌单链接或输入 ID', 'info'); S.dlg.step = 1; render(); setTimeout(() => { if (S.dialog === 'importPlaylist') { S.dlg.step = 2; render(); } }, 1100); };
ACT.dlgBack = () => { S.dlg.step = 0; render(); };
ACT.dlgDone = () => { const pl = PLAYLISTS[3]; MY_PLAYLISTS.splice(1, 0, { id:200 + MY_PLAYLISTS.length, t:pl.t, n:40, h:pl.h, v:pl.v, tag:'导入' }); S.dialog = null; S.tab = 'library'; S.libSeg = 'playlists'; S.stack = []; S._stagger = true; render(); toast(`已导入「${pl.t}」· 40 首`, 'download'); };
ACT.newPlDone = () => { const n = val('dlgIn').trim() || '新建歌单'; MY_PLAYLISTS.splice(1, 0, { id:300 + MY_PLAYLISTS.length, t:n, n:0, h:140, v:2 }); S.dialog = null; S._stagger = true; S.libSeg = 'playlists'; render(); toast(`已创建「${n}」`, 'check'); };
ACT.urlPaste = () => { S.dlg.val = 'https://example.com/lyra/script-e.js'; render(); };
ACT.scriptPaste = () => { S.dlg.val = SAMPLE_SCRIPT; render(); const t = document.getElementById('dlgTa'); t && t.animate([{ background:'var(--accent-soft)' }, { background:'' }], { duration:700 }); };
ACT.scriptImport = d => {
  S.dlg.val = d.src === 'url' ? val('dlgIn') : val('dlgTa');
  if (!S.dlg.val.trim()) return toast(d.src === 'url' ? '先输入脚本地址' : '先粘贴脚本内容', 'info');
  S.dlg.step = 1; render();
  setTimeout(() => { if (d.src === 'url') { S.dialog = 'pasteScript'; S.dlg.val = SAMPLE_SCRIPT; } S.dlg.step = 2; render(); }, 900);
};
ACT.scriptDone = () => { if (!SCRIPTS.find(x => x.id === 'e')) SCRIPTS.push({ id:'e', n:'解析脚本 E', v:'1.0.0', p:['netease', 'qq', 'kugou'], q:['HQ', 'SQ'], ms:380, ok:95 }); S.dialog = null; render(); toast('已导入解析脚本 E', 'code'); };
SHEETS.importScript = () => ({ t:'导入音源', body:`${group('', [
  item({ icon:'link', color:'blue', label:'从链接导入', sub:'输入解析脚本的下载地址', act:'openDlg', args:{ v:'urlScript' } }),
  item({ icon:'folder', color:'orange', label:'从文件导入', sub:'选择本机的 .js 脚本文件', act:'sheetToast', args:{ msg:'已打开文件选择器', icon:'folder' } }),
  item({ icon:'code', color:'violet', label:'粘贴内容', sub:'直接粘贴或手写脚本代码', act:'openDlg', args:{ v:'pasteScript' } }),
])}<p class="hint" style="padding:0 var(--pad)">解析脚本只负责把歌曲解析成可播放的地址。导入歌单请到「音乐库 → 歌单」右上角。</p>` });
delete SHEETS.import;

/* ================= 音乐库：Tab 顺序 + 右上角 导入 / 新建 ================= */
const _libRender = PAGES.library.render;
PAGES.library.render = () => {
  let h = _libRender();
  h = h.replace(/<div class="lh"><h1>音乐库<\/h1>[\s\S]*?<\/div>/, `<div class="lh"><h1>音乐库</h1><button class="ib" data-act="openDlg" data-v="importPlaylist" title="导入歌单">${ic('download')}</button><button class="ib" data-act="openDlg" data-v="newPlaylist" title="新建歌单">${ic('plus')}</button></div>`);
  h = h.replace(/<div class="seg [^"]*" style="--n:4;--i:\d">[\s\S]*?<\/div>/, seg(['我喜欢', '歌单', '最近', '本地'], { like:'我喜欢', recent:'最近', playlists:'歌单', local:'本地' }[S.libSeg], 'libSegCN'));
  h = h.replace(/<button class="card" style="aspect-ratio:1[\s\S]*?<\/button>\s*<button class="card"[\s\S]*?<\/button>/, '');
  return h;
};
ACT.libSegCN = d => { S.libSeg = { 我喜欢:'like', 最近:'recent', 歌单:'playlists', 本地:'local' }[d.v]; S._stagger = true; render(); };
SHEETS.newPlaylist = SHEETS.newPlaylist; // 加入歌单 Sheet 里的「新建歌单」也改为弹窗
const _addTo = SHEETS.addTo; SHEETS.addTo = () => { const r = _addTo(); r.body = r.body.replace(`data-act="sheet" data-v="newPlaylist"`, `data-act="openDlg" data-v="newPlaylist"`); return r; };

/* ================= 平台与解析脚本 ================= */
const _srcRender = PAGES.sources.render;
PAGES.sources.render = () => _srcRender().replace(/data-act="sheet" data-v="import"/g, 'data-act="sheet" data-v="importScript"').replace('从文件、链接或剪贴板导入', '从链接、文件或粘贴内容导入');

/* ================= 智能换源：按"同平台 → 跨平台"两个阶段重排 ================= */
PAGES.smart = { render:() => {
  const sp = PLATFORMS.find(x => x.id === S.smartPlat), on = S.set.smart;
  const flow = [['down', '降音质', 'gradual'], ['code', '换脚本', 'crossScript'], ['globe', '换平台', 'crossPlat'], ['next', '下一首', 'autoNext']];
  return `${appBar('智能换源')}
  <div class="m sm-flow ${on ? '' : 'off'}"><div class="smf-t">播放失败时，依次尝试</div>
    <div class="smf-row">${flow.map(([i, n, k], j) => `${j ? '<i class="smf-ar"></i>' : ''}<div class="smf-n ${S.set[k] ? 'on' : ''}" style="--d:${j * 120}ms"><span>${ic(i)}</span><b>${j + 1}</b>${n}</div>`).join('')}</div>
    <div class="smf-band"><span style="flex:2">同一平台内</span><span style="flex:1">跨平台</span><span style="flex:.9">兜底</span></div></div>
  ${group('', [item({ icon:'zap', color:'gold', label:'启用智能换源', sw:'smart' })])}
  ${on ? `
  <div class="grp-t">第一阶段 · 同一平台内</div>
  ${group('', [item({ icon:'down', color:'orange', label:'① 逐级降低音质', sub:'Hi-Res → SQ → HQ → 128k，仍用当前脚本', sw:'gradual' }),
    item({ icon:'code', color:'violet', label:'② 换用同平台的其他解析脚本', sub:'歌曲仍来自同一个平台，只是换一个脚本去解析', sw:'crossScript' }),
    `<div class="sm-pick"><span>脚本顺序</span>${PLATFORMS.map(x => `<button class="${x.id === S.smartPlat ? 'on' : ''}" data-act="smartPlat" data-v="${x.id}">${platBadge(x, 22)}</button>`).join('')}</div>`,
    `<div class="sm-list" key="${sp.id}">${scriptsOf(sp.id).sort((a, b) => b.ok - a.ok).map((sc, i) => `<div class="it" style="--d:${i * 50}ms"><b class="sm-no">${i + 1}</b><div class="lb"><b>${sc.n}</b><small>成功率 ${sc.ok}% · ${sc.ms}ms</small></div>${signal(sc.ms)}<span style="color:var(--t3);margin-left:8px">${ic('drag')}</span></div>`).join('')}</div>`],
    `正在编辑 <b>${sp.n}</b> 的脚本顺序。每个平台各有一份，切换上方徽标查看。`)}
  <div class="grp-t">第二阶段 · 跨平台</div>
  ${group('', [item({ icon:'globe', color:'blue', label:'③ 到其他平台搜索同一首歌', sub:'按歌名 + 歌手 + 时长（±3 秒）匹配，找到后用该平台自己的脚本顺序解析', sw:'crossPlat' }),
    ...PLATFORMS.filter(x => x.id !== S.plat).map((x, i) => `<div class="it">${platBadge(x, 30)}<div class="lb"><b>${x.n}</b><small>${isIn(x.id) ? '已登录 · 可匹配会员歌曲' : '未登录 · 只匹配免费歌曲'}</small></div><div class="val" style="gap:8px">${i + 1}<span style="color:var(--t3)">${ic('drag')}</span></div></div>`)],
    `当前平台（${plat().n}）失败后，按这个顺序换平台。这里排的是<b>平台</b>，不是脚本。`)}
  <div class="grp-t">兜底</div>
  ${group('', [item({ icon:'next', color:'red', label:'④ 全部失败时播放下一首', sw:'autoNext' })])}
  ${group('提醒', [item({ label:'音质降级时提醒', sw:'nQ' }), item({ label:'切换脚本时提醒', sw:'nS' }), item({ label:'换平台或跳到下一首时提醒', sw:'nA' })])}` : ''}`; } };
ACT.smartPlat = d => { S.smartPlat = d.v; render(); };

/* ================= 我的：去重 + 新功能（接力 / 一起听 / 云盘） ================= */
PAGES.me = { tabPage:true, render:() => `
  ${largeHead('我的', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button><button class="ib" data-act="push" data-v="appearance">${ic('gear')}</button>`)}
  <div class="m card" style="padding:18px;display:flex;gap:14px;align-items:center" data-act="push" data-v="account">
    <div class="avatar lg">栗</div>
    <div style="flex:1;min-width:0"><b style="font-size:19px">阿栗</b>
      <div style="font-size:12.5px;color:var(--t2);margin-top:3px">UID 10086427 · ali@example.com</div>
      <div style="display:flex;gap:6px;margin-top:8px"><span class="badge acc">${ic('crown')}已激活</span>${Object.keys(S.platLogin).map(id => platBadge(PLATFORMS.find(x => x.id === id), 22)).join('')}</div></div>${ic('right')}</div>
  <div class="m handoff" data-act="handoff">
    <div class="ho-dev">${ic('grid')}<i></i></div>
    <div style="flex:1;min-width:0"><small>桌面端 · 2 分钟前</small><b>玻璃海 · 澄音</b><div class="ho-bar"><i style="width:46%"></i></div></div>
    <button class="btn pri sm">${ic('play')}接着听</button></div>
  <div class="m card report" data-act="push" data-v="stats">
    <div class="rp-h"><b>本周聆听</b><span>11.2 – 11.8 ${ic('right')}</span></div>
    <div class="rp-b"><div><b data-count="6.2">6.2</b><small>小时 · 比上周多 18%</small><div class="rp-tags"><span>连续 12 天</span><span>最爱 · 雾港</span></div></div>
      <div class="bars grow mini">${[42, 65, 38, 80, 54, 96, 71].map((v, i) => `<div><b style="height:${v}%;--d:${i * 50}ms;${i === 6 ? '' : 'opacity:.5'}"></b></div>`).join('')}</div></div></div>
  <div class="qk feat">
    <button data-act="push" data-v="together"><span class="ic">${ic('user')}<em>新</em></span>一起听</button>
    <button data-act="push" data-v="cloud"><span class="ic">${ic('cloud')}</span>音乐云盘</button>
    <button data-act="push" data-v="download"><span class="ic">${ic('download')}</span>下载管理</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button></div>
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
    item({ icon:'cloud', color:'blue', label:'备份与同步', val:'WebDAV', act:'push', args:{ v:'backup' } }),
    item({ icon:'bell', color:'orange', label:'公告', val:'1 条未读', act:'push', args:{ v:'announcements' } }),
    item({ icon:'info', color:'gray', label:'关于与更新', val:'v2.4.0', act:'push', args:{ v:'about' } }),
  ])}` };
ACT.handoff = () => { playSong(4); S.pos = 102; ACT.openPlayer(); toast('已从桌面端接力 · 1:42', 'grid'); };

PAGES.together = { render:() => { const s = song(); return `${appBar('一起听')}
  <div class="m tg-room">
    <div class="tg-h"><span class="badge acc"><i class="live"></i>房间进行中</span><b>房间号 8F2K</b></div>
    <div class="tg-now">${cover(s, '', 72)}<div style="flex:1;min-width:0"><small>大家正在听</small><b>${s.t}</b><span>${s.a} · 进度已同步</span></div></div>
    <div class="tg-mem">${['栗', '满', 'Mo', '+'].map((n, i) => `<div class="tg-av ${i === 3 ? 'add' : ''}" style="--d:${i * 80}ms">${n === '+' ? ic('plus') : n}${i < 3 ? `<i class="${i === 1 ? 'talk' : ''}"></i>` : ''}</div>`).join('')}<small>3 人在听 · 小满正在发言</small></div>
    <div class="tg-rx">${['🔥', '😭', '🎧', '👏'].map(e => `<button data-act="react" data-v="${e}">${e}</button>`).join('')}<div class="tg-float"></div></div>
    <div class="tg-acts"><button class="btn pri" style="flex:1" data-act="sheet" data-v="shareCode">${ic('share')}邀请好友</button><button class="btn sec" data-act="toast" data-msg="已离开房间" data-icon="logout">离开</button></div></div>
  ${group('房间设置', [item({ label:'只有房主能切歌', sw:'pitch' }), item({ label:'允许成员加歌到队列', sw:'finishSong' }), item({ label:'语音聊天', sub:'按住麦克风说话，播放音量自动降低', sw:'fade' })])}
  <p class="hint" style="padding:0 var(--pad)">每个人用自己的音源播放，房间只同步歌曲和进度，不转发音频。</p>`; } };
ACT.react = (d, e) => {
  const box = document.querySelector('.tg-float'); if (!box) return;
  for (let i = 0; i < 6; i++) { const el = document.createElement('span'); el.textContent = d.v; el.style.left = 20 + Math.random() * 60 + '%'; box.appendChild(el);
    el.animate([{ transform:'translateY(0) scale(.6)', opacity:1 }, { transform:`translateY(-${110 + Math.random() * 60}px) translateX(${(Math.random() - .5) * 60}px) scale(1.2)`, opacity:0 }], { duration:1100 + Math.random() * 500, delay:i * 70, easing:'cubic-bezier(.2,.7,.3,1)', fill:'both' }).onfinish = () => el.remove(); }
};
PAGES.cloud = { render:() => `${appBar('音乐云盘', { right:`<button class="ib" data-act="toast" data-msg="选择要上传的音频文件" data-icon="download">${ic('plus')}</button>` })}
  <div class="m card cl-cap"><div class="cl-h"><b>12.4 GB</b><span>/ 50 GB</span></div><div class="cl-bar"><i style="width:24.8%"></i></div>
    <div class="cl-leg"><span><i style="background:var(--accent)"></i>无损 9.1 GB</span><span><i style="background:var(--info)"></i>其他 3.3 GB</span><span>612 首</span></div></div>
  <div class="note">${ic('cloud')}<span>上传自己的音乐，在所有设备上播放。上传后自动匹配歌词和封面，平台没有的歌也能听。</span></div>
  <div class="grp-t" style="padding-left:var(--pad)">正在上传 · 2</div>
  ${[[22, .72], [9, .31]].map(([id, p]) => { const s = SONGS[id]; return `<div class="row">${cover(s)}<div class="tx"><div class="t">${s.t}</div><div class="cl-up"><i style="width:${p * 100}%"></i></div><div class="s">${Math.round(p * 100)}% · FLAC 32 MB</div></div><button class="ib" style="color:var(--t3)">${ic('close')}</button></div>`; }).join('')}
  <div class="grp-t" style="padding-left:var(--pad)">已上传</div>
  ${[3, 14, 18, 21, 6].map((id, i) => songRow(SONGS[id], { list:'all', tail:`<span class="badge ${i === 2 ? '' : 'acc'}" style="margin-right:12px">${i === 2 ? '未匹配' : '已匹配'}</span>` })).join('')}` };

/* ================= 外观：皮肤与背景分开 ================= */
SHEETS.skin = () => {
  const cur = SKINS.find(k => k.id === S.skin);
  return { t:'播放器皮肤', sub:`${SKINS.length} 套`, dark:true, body:`
    ${SKIN_CATS.map(c => `<div class="sk-cat">${c}</div><div class="sk-grid">${SKINS.filter(k => k.cat === c).map(k => `<button class="sk-card ${S.skin === k.id ? 'on' : ''}" data-act="skin" data-v="${k.id}">
      <div class="pv ${k.id === 'standby' ? 'land' : ''}" style="background:#0B0C12">${skinThumb(k.id)}</div>
      <div class="sk-n"><b>${k.n}</b>${k.tag ? `<em>${k.tag}</em>` : ''}</div><small>${k.d}</small></button>`).join('')}</div>`).join('')}
    ${cur.id === 'spring' ? `<div class="grp-t">律动 · 歌词动效</div><div style="padding:0 0 10px">${seg(['弹簧瀑布', '波浪漂浮'], S.amWave === 'wave' ? '波浪漂浮' : '弹簧瀑布', 'amWaveCN', 'dark')}</div>` : ''}
    ${cur.bg ? `<div style="padding:4px var(--pad) 10px"><button class="btn sec block" data-act="sheet" data-v="bg">${ic('layers')}背景：${{ blur:'模糊封面', static:'静态流光', flow:'动态流光' }[S.bg]}</button></div>` : ''}` };
};
ACT.amWaveCN = d => { S.amWave = d.v === '波浪漂浮' ? 'wave' : 'spring'; render(); };
SHEETS.bg = () => {
  const s = song(), sk = SKINS.find(k => k.id === S.skin);
  const pv = k => `<div class="bgpv ${k}">${k === 'blur' ? `<i style="${coverStyle(s.h, s.v)}"></i>` : `<div class="flow">${flowBlobs(s)}</div>`}<b style="background:rgba(${S.tone === 'dark' ? '5,6,10' : '255,255,255'},${S.tone === 'dark' ? S.bright / 100 : S.bright / 300})"></b></div>`;
  return { t:'播放器背景', dark:true, body:`
    ${sk.bg ? '' : `<div class="note">${ic('info')}<span>当前皮肤「${sk.n}」自带背景。这里的设置会用在 律动 / 声波 / 唱片 / 舞台。</span></div>`}
    <div class="bg-opts">${[['blur', '模糊封面', '封面高斯模糊铺满'], ['static', '静态流光', '封面取色，不动'], ['flow', '动态流光', '光斑缓慢流动']].map(([k, n, d]) => `<button class="${S.bg === k ? 'on' : ''}" data-act="bgSet" data-v="${k}">${pv(k)}<b>${n}</b><small>${d}</small></button>`).join('')}</div>
    <div class="grp-t">色调</div><div style="padding:0 0 4px">${seg(['暗色', '亮色'], S.tone === 'dark' ? '暗色' : '亮色', 'toneCN', 'dark')}</div>
    <div class="sl" style="padding:12px var(--pad)"><label>压暗程度</label><input type="range" min="0" max="80" step="1" value="${S.bright}" data-st="bright" data-unit="%" style="--v:${S.bright / .8}%"><output data-out="bright">${S.bright}%</output></div>` };
};
ACT.bgSet = d => { S.bg = d.v; render(); };

/* ================= 新皮肤 ================= */
const SKIN_RENDER = {};
const clock = () => { const d = new Date(); return [String(d.getHours()).padStart(2, '0'), String(d.getMinutes()).padStart(2, '0')]; };
SKIN_RENDER.standby = s => { const [h, m] = clock(), k = Math.max(0, lyrIdx());
  return `<div class="player stby ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}" style="--h:${s.h}">
    <canvas class="sb-cv"></canvas>
    <button class="ib sb-x" data-act="closePlayer">${ic('close')}</button>
    <div class="sb-l"><div class="sb-clock">${h}<i>:</i>${m}</div><div class="sb-date">11月2日 星期一 · ${ic('zap')} 充电中 82%</div>
      <div class="sb-lyr">${LYRICS[k].o}</div></div>
    <div class="sb-r">${cover(s, 'sb-cv2', 132, 'data-hero')}<div class="sb-ti"><b>${s.t}</b><span>${s.a}</span></div>
      <div class="sb-pg"><i data-b="mfill"></i></div>
      <div class="sb-ctl"><button class="ib" data-act="prev">${ic('prev')}</button><button class="ib big" data-act="toggle">${ic(S.playing ? 'pause' : 'play')}</button><button class="ib" data-act="next">${ic('next')}</button></div></div></div>`; };
SKIN_RENDER.cassette = s => `<div class="player cass ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw">${topBar()}<div class="pmid">
    <div class="tape" data-hero>
      <div class="tp-label" style="${coverStyle(s.h, s.v)}"><div class="tp-paper"><b>${s.t}</b><span>${s.a} · SIDE A · ${fmt(s.dur)}</span></div></div>
      <div class="tp-win"><div class="reel l"><i class="tp-tape"></i><i class="hub"></i></div><div class="tp-mid"></div><div class="reel r"><i class="tp-tape"></i><i class="hub"></i></div></div>
      <div class="tp-bot"><i></i><i></i><i></i><i></i></div><b class="tp-brand">LYRA · C-60</b></div>
    <div class="vu">${['L', 'R'].map(c => `<div class="vu-m"><div class="vu-scale">${[-20, -10, -5, 0, '+3'].map(n => `<span>${n}</span>`).join('')}</div><i class="needle"></i><b>${c}</b></div>`).join('')}</div>
    ${info(s)}${lines3()}</div>${progress(s)}
    <div class="ctl keys"><button class="key" data-act="prev">${ic('prev')}</button><button class="key ${S.playing ? 'down' : ''}" data-act="toggle">${ic('play')}</button><button class="key ${S.playing ? '' : 'down'}" data-act="toggle">${ic('pause')}</button><button class="key" data-act="next">${ic('next')}</button></div></div></div>`;
SKIN_RENDER.pixel = s => { const k = Math.max(0, lyrIdx());
  return `<div class="player pix ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw">${topBar()}<div class="pmid">
    <div class="px-hd"><span class="blink">▶</span> NOW PLAYING <span class="px-lv">LV.${String(S.cur + 1).padStart(2, '0')}</span></div>
    <div class="px-frame"><canvas class="px-art" width="16" height="16" data-hero></canvas></div>
    <div class="px-ti"><b>${s.t}</b><span>${s.a}</span></div>
    <canvas class="px-spec" width="64" height="20"></canvas>
    <div class="px-lyr"><span class="tw">${LYRICS[k].o}</span><i class="cur"></i></div></div>
    <div class="px-prog"><div class="px-bar"><i data-b="mfill"></i></div><div class="tm"><span data-b="pos">${fmt(S.pos)}</span><span>${fmt(s.dur)}</span></div></div>
    <div class="ctl px-ctl"><button data-act="mode">${ic(MODE_IC[S.mode])}</button><button data-act="prev">${ic('prev')}</button><button class="big" data-act="toggle">${ic(S.playing ? 'pause' : 'play')}</button><button data-act="next">${ic('next')}</button><button data-act="sheet" data-v="queue">${ic('queue')}</button></div></div></div>`; };
SKIN_RENDER.magazine = s => { const k = Math.max(0, lyrIdx());
  return `<div class="player mag ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">
  <div class="pw"><div class="mg-top"><button class="ib" data-act="closePlayer">${ic('down')}</button><span>LYRA · NO.${String(S.cur + 1).padStart(2, '0')} · NOV 2026</span><button class="ib" data-act="sheet" data-v="more" data-id="${s.id}" data-ctx="player">${ic('more')}</button></div>
    <div class="pmid">
      <div class="mg-kick">${s.al.toUpperCase()} — ${S.quality}</div>
      <h1 class="mg-title">${s.t}</h1>
      <div class="mg-by">by <b>${s.a}</b><button class="mg-like ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${S.liked.has(s.id) ? '已收藏' : '收藏'}</button></div>
      <div class="mg-row"><figure>${cover(s, '', 0, 'data-hero')}<figcaption>Fig. 1 — 封面</figcaption></figure>
        <blockquote class="mg-q"><span>“</span><p class="lines-q">${LYRICS[k].o}</p><small>${LYRICS[k].sec} · ${String(k + 1).padStart(2, '0')}</small></blockquote></div></div>
    <div class="mg-prog"><span data-b="pos">${fmt(S.pos)}</span><div class="mg-bar"><i data-b="mfill"></i></div><span>${fmt(s.dur)}</span></div>
    <div class="mg-ctl"><button data-act="prev">PREV</button><button class="big" data-act="toggle">${S.playing ? 'PAUSE' : 'PLAY'}</button><button data-act="next">NEXT</button></div></div></div>`; };

/* 皮肤缩略图 */
const _thumb = skinThumb;
skinThumb = id => {
  const l = (a, w = 60) => `<div class="l ${a ? 'a' : ''}" style="width:${w}%"></div>`;
  const T = {
    standby:`<div style="position:absolute;inset:0;background:radial-gradient(ellipse at 80% 120%,hsl(38 80% 50% / .6),transparent 60%),repeating-radial-gradient(circle at 80% 110%,transparent 0 6px,rgba(244,210,138,.25) 6px 7px)"></div><b style="position:absolute;left:8px;top:10px;font:200 26px var(--font-num);color:#fff">9:41</b><div style="position:absolute;right:8px;top:12px;width:30px;height:30px;border-radius:6px;${coverStyle(38, 0)}"></div>`,
    cassette:`<div style="position:absolute;inset:0;background:#1a1612"></div><div style="position:absolute;left:12%;right:12%;top:22%;height:50%;border-radius:6px;background:#2b2621;box-shadow:inset 0 0 0 2px #3a332c"><div style="position:absolute;left:8%;right:8%;top:10%;height:26%;border-radius:2px;${coverStyle(30, 0)}"></div><i style="position:absolute;left:22%;bottom:16%;width:16px;height:16px;border-radius:50%;border:3px solid #ddd;box-sizing:border-box"></i><i style="position:absolute;right:22%;bottom:16%;width:16px;height:16px;border-radius:50%;border:3px solid #ddd;box-sizing:border-box"></i></div>`,
    pixel:`<div style="position:absolute;inset:0;background:#0b0a1a;background-image:repeating-linear-gradient(transparent 0 2px,rgba(0,0,0,.35) 2px 3px)"></div><div style="position:absolute;left:30%;top:16%;width:40%;height:44%;image-rendering:pixelated;background:conic-gradient(from 90deg,#ff6ec7 25%,#7b5cff 0 50%,#ffd166 0 75%,#2ee6c5 0);background-size:25% 25%"></div><div style="position:absolute;left:18%;right:18%;bottom:14%;height:14%;background:repeating-linear-gradient(90deg,var(--accent) 0 4px,transparent 4px 6px)"></div>`,
    magazine:`<div style="position:absolute;inset:0;background:#EFE9DF"></div><b style="position:absolute;left:8px;top:8px;font:900 22px/1 Georgia,serif;color:#111">夜航</b><div style="position:absolute;left:8px;bottom:10px;width:34%;height:36%;${coverStyle(38, 0)}"></div><i style="position:absolute;right:8px;bottom:14px;width:40%;height:3px;background:#111;box-shadow:0 -7px 0 #111,0 -14px 0 #999"></i>`,
  };
  return T[id] ? `<div class="skin-pv">${T[id]}</div>` : _thumb(id);
};

/* ================= 每帧：新皮肤的动画 ================= */
const SB = { rings:[], lastBeat:0, t0:performance.now() };
function pixelArt(cv, s) {
  const g = cv.getContext('2d'); let a = s.id * 7919 + 17; const r = () => ((a = (a * 16807) % 2147483647) / 2147483647);
  const pal = [`hsl(${s.h} 80% 62%)`, `hsl(${(s.h + 40) % 360} 70% 42%)`, `hsl(${(s.h + 320) % 360} 75% 22%)`, `hsl(${s.h} 95% 85%)`];
  g.fillStyle = pal[2]; g.fillRect(0, 0, 16, 16);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 8; x++) { const v = r(); const d = Math.hypot(x - 7.5, y - 7.5); const c = d < 4 + r() * 2 ? (v > .3 ? 0 : 3) : v > .72 ? 1 : -1; if (c >= 0) { g.fillStyle = pal[c]; g.fillRect(x, y, 1, 1); g.fillRect(15 - x, y, 1, 1); } }
  cv.dataset.done = s.id;
}
function skinTick(beat, p) {
  if (!S.playerOpen) return;
  const s = song();
  if (S.skin === 'cassette') {
    const pl = document.querySelector('.cass'); if (!pl) return;
    pl.style.setProperty('--pl', (1 - p).toFixed(3)); pl.style.setProperty('--pr', p.toFixed(3));
    pl.querySelectorAll('.needle').forEach((n, i) => { const v = S.playing ? .25 + beat * .6 + Math.abs(Math.sin(S.pos * (3 + i) )) * .15 : 0; n.style.transform = `rotate(${-50 + v * 90}deg)`; });
  }
  if (S.skin === 'pixel') {
    const art = document.querySelector('.px-art'); if (art && +art.dataset.done !== s.id) pixelArt(art, s);
    const sp = document.querySelector('.px-spec'); if (sp) { const g = sp.getContext('2d'); g.clearRect(0, 0, 64, 20);
      for (let i = 0; i < 16; i++) { const h = S.playing ? Math.round((Math.abs(Math.sin(S.pos * (1.7 + i * .29) + i)) * .6 + beat * .5) * 10) : 1;
        for (let j = 0; j < h; j++) { g.fillStyle = j > 7 ? '#ff6e6e' : j > 4 ? getComputedStyle(document.documentElement).getPropertyValue('--accent') : '#2ee6c5'; g.fillRect(i * 4, 19 - j * 2, 3, 1.5); } } }
    const k = Math.max(0, lyrIdx()), L = LYRICS[k], tw = document.querySelector('.px-lyr .tw');
    if (tw) { const n = Math.ceil(L.o.length * Math.min(1, (S.pos - L.t) / 1.2)); const t = L.o.slice(0, Math.max(0, n)); if (tw.textContent !== t) tw.textContent = t; }
  }
  if (S.skin === 'magazine') { const q = document.querySelector('.lines-q'), k = Math.max(0, lyrIdx()); if (q && q.textContent !== LYRICS[k].o) { q.textContent = LYRICS[k].o; q.animate([{ opacity:0, transform:'translateY(8px)' }, { opacity:1, transform:'none' }], { duration:500, easing:'ease-out' }); } }
  if (S.skin === 'standby') {
    const cv = document.querySelector('.sb-cv'); if (!cv) return;
    const W = cv.clientWidth, H = cv.clientHeight, dpr = Math.min(2, devicePixelRatio || 1);
    if (cv.width !== W * dpr) { cv.width = W * dpr; cv.height = H * dpr; }
    const g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);
    const now = performance.now() / 1000, t = now - SB.t0;
    const bph = Math.floor(S.pos * 112 / 60);
    if (S.playing && bph !== SB.lastBeat) { SB.lastBeat = bph; SB.rings.push({ t:now, x:W * (.62 + Math.random() * .2), y:H * (.55 + Math.random() * .3), s:bph % 4 === 0 ? 1 : .6 }); if (SB.rings.length > 14) SB.rings.shift(); }
    const grd = g.createLinearGradient(0, 0, W, H); grd.addColorStop(0, `hsl(${(s.h + 320) % 360} 60% 6%)`); grd.addColorStop(1, `hsl(${s.h} 55% 10%)`);
    g.fillStyle = grd; g.fillRect(0, 0, W, H);
    g.globalCompositeOperation = 'lighter';
    for (let b = 0; b < 6; b++) {        // 流体波带
      g.beginPath(); const amp = (14 + b * 5) * (S.playing ? .6 + beat * .8 : .25), base = H * (.42 + b * .1);
      for (let x = 0; x <= W; x += 8) { const y = base + Math.sin(x * .008 + t * (.5 + b * .13) + b) * amp + Math.sin(x * .021 - t * .8 + b * 2) * amp * .45; x ? g.lineTo(x, y) : g.moveTo(x, y); }
      g.lineTo(W, H); g.lineTo(0, H); g.closePath();
      g.fillStyle = `hsla(${(s.h + b * 14) % 360},80%,${45 + b * 4}%,${.07 + b * .012})`; g.fill();
      g.strokeStyle = `hsla(${(s.h + b * 14) % 360},90%,75%,${.18 - b * .02})`; g.lineWidth = 1.2; g.stroke();
    }
    SB.rings.forEach(r => {               // 节拍波纹
      const age = now - r.t; if (age > 3.2) return;
      for (let k = 0; k < 3; k++) { const rad = (age * 150 - k * 18) * r.s; if (rad <= 0) continue;
        g.beginPath(); g.ellipse(r.x, r.y, rad, rad * .42, 0, 0, Math.PI * 2);
        g.strokeStyle = `hsla(${s.h},90%,78%,${Math.max(0, (1 - age / 3.2) * (.5 - k * .14))})`; g.lineWidth = 2 - k * .5; g.stroke(); }
    });
    g.globalCompositeOperation = 'source-over';
    const ly = document.querySelector('.sb-lyr'), k = Math.max(0, lyrIdx()); if (ly && ly.textContent !== LYRICS[k].o) { ly.textContent = LYRICS[k].o; ly.animate([{ opacity:0, filter:'blur(6px)' }, { opacity:1, filter:'blur(0)' }], { duration:600 }); }
  }
}
