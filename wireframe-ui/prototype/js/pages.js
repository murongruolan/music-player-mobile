/* 页面：鉴权流程、5 个 Tab、二级页、音源选择器、剪贴板口令横幅。
   full:true = 全屏页（无迷你播放条与底栏）；lightBar:true = 状态栏白字；tabPage:true = 一级页（大标题折叠）。 */
const PAGES = {};

/* ================= 鉴权 ================= */
PAGES.disclaimer = { full:true, lightBar:true, render:() => `
  <div class="ambient"><i></i><i></i><i></i></div>
  <div style="position:relative;padding:70px 26px 0;color:#F3F4F8">
    ${appIcon(64)}
    <h1 style="font-size:30px;font-weight:750;margin-top:22px">使用须知</h1>
    <p style="color:rgba(255,255,255,.62);font-size:14px;margin-top:6px">开始之前，请花一分钟了解以下内容</p>
    <div style="margin-top:22px;border-radius:22px;background:rgba(18,18,26,.66);backdrop-filter:blur(24px);border:1px solid rgba(255,255,255,.1);padding:6px 4px">
      ${[['shield','隐私','聆听记录仅用于生成每日混音与统计，可随时在设置中清除。'],['layers','音源','解析脚本由你自行添加并对其合法性负责，Lyra 不提供、不存储任何音频内容。'],['cloud','同步','收藏与歌单可同步到你的账号或自建 WebDAV，同步内容不含音频文件。'],['info','版本','如当前版本被停止服务，App 会提示你更新到可用版本。']]
        .map(([i, t, d]) => `<div class="it si" style="align-items:flex-start"><div class="tile" style="background:rgba(244,210,138,.16);color:#F4D28A">${ic(i)}</div><div class="lb"><b style="color:#fff">${t}</b><small style="color:rgba(255,255,255,.55)">${d}</small></div></div>`).join('')}
    </div>
    <button class="it" data-act="agree" style="width:100%;margin-top:14px;padding:6px 2px;gap:10px">
      <span class="ck ${S.agree ? 'on' : ''}">${ic('check')}</span>
      <span style="font-size:13px;color:rgba(255,255,255,.75);text-align:left">我已阅读并同意《用户协议》与《隐私政策》</span></button>
    <button class="btn pri block" data-act="enterApp" style="margin-top:14px;transition:opacity .3s;${S.agree ? '' : 'opacity:.45'}">同意并继续</button>
  </div>` };

PAGES.login = { full:true, lightBar:true, render:() => {
  const reg = S.loginSeg === '注册';
  return `<div class="ambient"><i></i><i></i><i></i></div>
  <div style="position:relative;padding:86px 28px 0;color:#fff">
    ${appIcon(64, 'float')}
    <h1 style="font-size:34px;font-weight:800;margin-top:20px;letter-spacing:-.02em">Lyra</h1>
    <p style="font-size:15px;color:rgba(255,255,255,.7);margin-top:4px">听见光的形状</p>
  </div>
  <div class="authcard">
    ${seg(['登录', '注册'], reg ? '注册' : '登录', 'loginSeg')}
    <div class="fold ${reg ? 'open' : ''}"><div>
      <div class="fld">${ic('mail')}<input placeholder="邮箱"></div>
      <div style="display:flex;gap:10px;margin-top:10px"><div class="fld" style="flex:1">${ic('shield')}<input placeholder="图形验证码"></div><div class="captcha" data-act="toast" data-msg="已刷新验证码" data-icon="refresh">7K3F</div></div>
      <div class="fld" style="margin:10px 0">${ic('key')}<input placeholder="邮箱验证码"><button class="act" data-act="toast" data-msg="验证码已发送至邮箱" data-icon="mail">发送</button></div></div></div>
    ${reg ? '' : `<div class="fld" style="margin-bottom:10px">${ic('mail')}<input placeholder="邮箱" value="ali@example.com"></div>`}
    <div class="fld">${ic('lock')}<input type="password" placeholder="密码" value="${reg ? '' : 'password'}">${ic('eye')}</div>
    <button class="btn pri block" data-act="${reg ? 'toast' : 'login'}" ${reg ? 'data-msg="注册申请已提交，审核通过后会邮件通知" data-icon="mail"' : ''} style="margin-top:16px">${reg ? '提交注册' : '登录'}</button>
    <div style="display:flex;justify-content:space-between;margin-top:14px;font-size:13px;color:rgba(255,255,255,.6)">
      <button data-act="authPage" data-v="forgot">忘记密码</button>
      <button data-act="toast" data-msg="${reg ? '申请审核中，预计 24 小时内完成' : '用已登录的手机扫电视上的二维码即可'}" data-icon="${reg ? 'clock' : 'scan'}">${reg ? '查看申请进度' : '已有账号的设备扫码登录'}</button></div>
  </div>`; } };

PAGES.forgot = { full:true, render:() => {
  const st = S.forgotStep;
  const body = [
    `<div class="fld">${ic('mail')}<input placeholder="注册邮箱" value="ali@example.com"></div><p class="hint" style="padding:10px 2px 0">我们会向这个邮箱发送 6 位验证码。</p>`,
    `<div style="display:flex;gap:8px;justify-content:space-between">${'482'.split('').concat(['', '', '']).map((c, i) => `<div class="otp ${i === 3 ? 'cur' : ''} ${c ? 'fill' : ''}" style="--d:${i * 50}ms">${c}${i === 3 ? '<i></i>' : ''}</div>`).join('')}</div><p class="hint" style="padding:12px 2px 0">验证码已发送至 a***@example.com · <b style="color:var(--accent-text)">52s</b> 后可重发</p>`,
    `<div class="fld">${ic('lock')}<input type="password" placeholder="新密码（至少 8 位）"></div><div class="pwbar"><i style="width:66%"></i></div><p class="hint" style="padding:6px 2px 10px">强度：中 · 建议加入符号</p><div class="fld">${ic('lock')}<input type="password" placeholder="再次输入新密码"></div>`,
  ][st];
  return `<div class="ab"><button class="ib" data-act="authPage" data-v="login">${ic('left')}</button><div class="ttl"></div><div class="sp"></div></div>
    <div style="padding:8px var(--pad) 0"><h1 style="font-size:28px;font-weight:750">${['找回密码', '输入验证码', '设置新密码'][st]}</h1><p style="color:var(--t2);font-size:14px;margin:6px 0 18px">第 ${st + 1} 步，共 3 步</p></div>
    <div class="steps">${[0, 1, 2].map(i => `<i class="${i <= st ? 'on' : ''}"></i>`).join('')}</div>
    <div style="padding:0 var(--pad)" class="stepbody">${body}<button class="btn pri block" style="margin-top:22px" data-act="forgotNext">${st < 2 ? '下一步' : '重置密码'}</button></div>`; } };

PAGES.versionDisabled = { full:true, render:() => `
  <div style="height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:0 36px;text-align:center">
    <div class="vd-ic">${ic('info')}</div>
    <h1 style="font-size:24px;font-weight:750;margin-top:22px">当前版本已停止服务</h1>
    <p style="color:var(--t2);font-size:14px;line-height:1.7;margin-top:10px">v2.3.1 存在影响播放稳定性的问题，已被服务端停用。<br>请更新到 v2.4.0 或更高版本继续使用。</p>
    <div class="card" style="width:100%;margin-top:22px;padding:14px 16px;text-align:left;font-size:13px;color:var(--t2);line-height:1.7"><b style="color:var(--t1)">v2.4.0 更新内容</b><br>· 修复后台播放偶发中断<br>· 律动 / 灵动两套新皮肤<br>· 液态玻璃底栏</div>
    <button class="btn pri block" style="margin-top:22px" data-act="toast" data-msg="正在下载更新包…" data-icon="download">立即更新（38.6 MB）</button>
    <p class="hint" style="margin-top:12px">此页面无法跳过</p></div>` };

/* ================= 音源：平台 → 解析脚本 ================= */
function srcBar(compact) {
  const p = plat(), sc = curScript();
  return `<button class="srcbar ${compact ? 'compact' : ''} ${S.picker ? 'open' : ''}" data-act="picker" data-flip="srcbar">
    <span class="sb-plat">${platBadge(p, compact ? 20 : 26)}<b>${p.n}</b></span>
    <span class="sb-div"></span>
    <span class="sb-scr">${signal(sc.ms)}<span>${sc.n}</span></span>
    <span class="sb-chev">${ic('down')}</span></button>`;
}
function renderPicker() {
  const p = plat(), list = scriptsOf(S.plat);
  return `<div class="pk-scrim scrim" data-act="closePicker"></div>
  <div class="picker">
    <div class="pk-h"><b>音乐平台</b><small>决定搜索、榜单、歌单的数据来源</small></div>
    <div class="pk-plats">${PLATFORMS.map(x => `<button class="pk-tile ${x.id === S.plat ? 'on' : ''}" data-act="plat" data-v="${x.id}">
      <span class="pk-logo" style="background:linear-gradient(140deg,${x.c},${x.c2})">${x.m}${x.id === S.plat ? '<i class="pk-ring" data-flip="pkring"></i>' : ''}</span>
      <span class="pk-n">${x.n.replace('音乐', '')}</span><span class="pk-s ${isIn(x.id) ? 'in' : ''}">${isIn(x.id) ? '已登录' : '未登录'}</span></button>`).join('')}</div>
    <div class="pk-h" style="margin-top:6px"><b>解析脚本</b><small>${p.n} 可用 ${list.length} 个 · 按成功率排序</small></div>
    <div class="pk-list" key="${S.plat}">
      <button class="pk-row ${S.script === 'auto' ? 'on' : ''}" data-act="script" data-v="auto" style="--d:0ms">
        <span class="pk-ic">${ic('zap')}</span><span class="pk-tx"><b>自动选择 <em class="badge acc">推荐</em></b><small>失败时按智能换源规则依次切换</small></span><span class="pk-ck">${ic('check')}</span></button>
      ${list.sort((a, b) => b.ok - a.ok).map((s, i) => `<button class="pk-row ${S.script === s.id ? 'on' : ''}" data-act="script" data-v="${s.id}" style="--d:${(i + 1) * 45}ms">
        <span class="pk-ic">${ic('code')}</span><span class="pk-tx"><b>${s.n} <em>v${s.v}</em></b><small>${s.q.map(q => `<span class="qb">${q}</span>`).join(' ')} · 成功率 ${s.ok}%</small></span>
        <span class="pk-sig">${signal(s.ms)}<small>${s.ms}ms</small></span><span class="pk-ck">${ic('check')}</span></button>`).join('')}
    </div>
    <div class="pk-f"><button data-act="push" data-v="sources">${ic('grid')}管理平台与脚本</button><button data-act="push" data-v="smart">${ic('zap')}智能换源</button></div>
  </div>`;
}
const skeleton = () => `<div class="skl" style="padding:0 var(--pad)"><i style="height:168px;border-radius:22px"></i><div style="display:flex;gap:12px;margin-top:22px">${'<i style="flex:1;height:54px;border-radius:18px"></i>'.repeat(4)}</div><i style="height:22px;width:40%;margin-top:26px"></i><div style="display:flex;gap:14px;margin-top:12px">${'<i style="width:140px;height:140px;border-radius:16px;flex:none"></i>'.repeat(3)}</div>${'<div style="display:flex;gap:12px;margin-top:16px;align-items:center"><i style="width:48px;height:48px;border-radius:10px"></i><div style="flex:1"><i style="height:14px;width:60%"></i><i style="height:11px;width:40%;margin-top:8px"></i></div></div>'.repeat(4)}</div>`;

/* ================= Tab：发现 ================= */
PAGES.discover = { tabPage:true, render:() => `
  ${largeHead('发现', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button>
    <button class="ib" data-act="push" data-v="announcements">${ic('bell')}<i class="dot"></i></button>
    <button class="avatar" data-act="tab" data-v="me" style="margin-left:4px">栗</button>`)}
  <div style="padding:2px var(--pad) 14px">${srcBar()}</div>
  ${S.loading ? skeleton() : `
  <div class="bn">${BANNERS.map((b, i) => `<div class="b" style="${coverStyle(b.hue, i)};background-size:140% 140%" data-act="push" data-v="playlist" data-id="${i}"><div class="k">${b.k}</div><div class="h">${b.h}</div><div class="d">${b.d}</div></div>`).join('')}</div>
  <div class="dots">${BANNERS.map((b, i) => `<i class="${i === S.banner ? 'on' : ''}"></i>`).join('')}</div>
  <div class="qk">
    <button data-act="tab" data-v="daily"><span class="ic">${ic('sun')}</span>每日混音</button>
    <button data-act="playAll" data-list="hot" data-shuffle="1"><span class="ic">${ic('wave')}</span>私人电台</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="homeTab" data-v="榜单"><span class="ic">${ic('chart')}</span>排行榜</button></div>
  <div style="margin-top:22px">${seg(['精选', '榜单', '歌单'], S.homeTab, 'homeTab')}</div>
  ${S.homeTab === '精选' ? `
    <div class="sec"><h2>${plat().n.replace('音乐', '')} · 为你推荐</h2><button class="more" data-act="homeTab" data-v="歌单">更多${ic('right')}</button></div>
    <div class="hs">${PLAYLISTS.slice(0, 6).map(p => `<div class="pl" data-act="push" data-v="playlist" data-id="${p.id}"><div class="cv" style="${coverStyle(p.h, p.v)}"><span class="pc">${ic('play')}${p.pc}</span></div><div class="t">${p.t}</div></div>`).join('')}</div>
    <div class="sec"><h2>热门榜单</h2><button class="more" data-act="homeTab" data-v="榜单">全部${ic('right')}</button></div>
    <div class="card m" style="padding:6px 0">${LISTS.hot().slice(0, 5).map((id, i) => songRow(SONGS[id], { num:i, list:'hot', noSwipe:true, tail:`<button class="ib heart ${S.liked.has(id) ? 'on' : ''}" data-act="like" data-id="${id}">${ic(S.liked.has(id) ? 'heartf' : 'heart')}</button>` })).join('')}</div>
    <div class="sec"><h2>新歌速递</h2><span class="more">本周 · 24 首</span></div>
    <div class="hs">${[8, 13, 19, 22, 3, 10].map(id => { const s = SONGS[id]; return `<div class="pl" style="width:120px" data-act="play" data-id="${id}" data-list="all"><div class="cv" style="${coverStyle(s.h, s.v)};width:120px;height:120px"></div><div class="t">${s.t}</div><div style="font-size:12px;color:var(--t2);margin-top:2px">${s.a}</div></div>`; }).join('')}</div>`
  : S.homeTab === '榜单' ? `<div style="padding-top:14px">${[['飙升榜', 300, [11, 17, 5]], ['新歌榜', 40, [8, 13, 19]], ['热歌榜', 200, [0, 2, 4]], ['Hi-Res 榜', 160, [7, 21, 12]]].map(([n, h, ids]) => `
      <div class="card m" style="margin-bottom:12px;padding:14px;display:flex;gap:14px" data-act="push" data-v="playlist" data-id="${h % 8}">
        <div class="cv" style="${coverStyle(h, 2)};width:88px;height:88px;border-radius:14px;display:flex;align-items:flex-end;padding:8px"><b style="position:relative;font-size:15px;color:#fff">${n}</b></div>
        <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:6px">${ids.map((id, i) => `<div style="font-size:13px;color:var(--t2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><b style="color:${i === 0 ? 'var(--accent-text)' : 'var(--t1)'};margin-right:6px">${i + 1}</b>${SONGS[id].t} - ${SONGS[id].a}</div>`).join('')}<div style="font-size:11px;color:var(--t3)">${plat().n} · 每日 10:00 更新</div></div></div>`).join('')}</div>`
  : `<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px 14px;padding:16px var(--pad) 0">${PLAYLISTS.map(p => `<div class="pl" style="width:auto" data-act="push" data-v="playlist" data-id="${p.id}"><div class="cv" style="${coverStyle(p.h, p.v)};width:100%;height:auto;aspect-ratio:1"><span class="pc">${ic('play')}${p.pc}</span></div><div class="t">${p.t}</div></div>`).join('')}</div>`}`}` };

/* ================= Tab：搜索 ================= */
PAGES.search = { tabPage:true, render:() => {
  const q = S.searchQ.trim();
  const head = `<div style="padding:4px var(--pad) 10px;display:flex;gap:10px;align-items:center">
    <div class="fld" style="flex:1;height:46px;border-radius:23px">${ic('search')}<input id="q" placeholder="在 ${plat().n} 中搜索" value="${S.searchQ}" autocomplete="off">${q ? `<button data-act="clearQ" style="color:var(--t3)">${ic('close')}</button>` : ''}</div>
    <button class="ib" data-act="openScan" data-v="match" style="background:var(--s2)">${ic('mic')}</button></div>
    <div style="padding:0 var(--pad) 6px">${srcBar(true)}</div>`;
  if (!q) return `${largeHead('搜索')}${head}
    ${S.history.length ? `<div class="sec" style="padding-top:12px"><h2 style="font-size:16px">搜索历史</h2><button class="more" data-act="clearHist">${ic('trash')}</button></div>
    <div class="chips" style="flex-wrap:wrap">${S.history.map(h => `<button class="chip" data-act="sq" data-q="${h}">${h}</button>`).join('')}</div>` : ''}
    <div class="sec"><h2 style="font-size:16px">热搜榜</h2><span class="more">${plat().n} · 每小时更新</span></div>
    <div class="card m" style="padding:4px 0">${HOT.map((h, i) => `<div class="row" data-act="sq" data-q="${h}" style="height:48px"><div class="no ${i < 3 ? 'top' : ''}">${i + 1}</div><div class="tx"><div class="t" style="font-size:14.5px;font-weight:550">${h}</div></div>${i === 0 ? '<span class="badge acc">热</span>' : i === 3 || i === 7 ? '<span class="badge">新</span>' : ''}<span style="width:12px"></span></div>`).join('')}</div>
    <div class="sec"><h2 style="font-size:16px">按风格探索</h2></div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:0 var(--pad)">${[['城市流行', 300], ['后摇', 225], ['Lo-fi', 280], ['电子', 200], ['民谣', 30], ['钢琴', 190]].map(([n, h], i) => `<div class="cv card" style="${coverStyle(h, i)};height:76px;border-radius:16px;padding:12px;display:flex;align-items:flex-end;border:0" data-act="sq" data-q="${n}"><b style="position:relative;color:#fff;font-size:15px">${n}</b></div>`).join('')}</div>`;
  const ql = q.toLowerCase();
  let res = SONGS.filter(s => (s.t + s.a + s.al).toLowerCase().includes(ql));
  const exact = res.length > 0; if (!exact) res = SONGS.slice(0, 8);
  const artist = SONGS.find(s => s.a.toLowerCase().includes(ql));
  return `${largeHead('搜索')}${head}<div style="margin:6px 0 8px">${seg(['单曲', '歌手', '专辑', '歌单'], { song:'单曲', artist:'歌手', album:'专辑', playlist:'歌单' }[S.searchTab] || '单曲', 'searchTab')}</div>
    ${artist ? `<div class="card m" style="margin-top:8px;padding:14px;display:flex;gap:14px;align-items:center" data-act="push" data-v="artist" data-id="${artist.id}">
      <div class="cv" style="${coverStyle(artist.h, 1)};width:64px;height:64px;border-radius:32px"></div>
      <div style="flex:1"><div style="font-size:11px;color:var(--t3);font-weight:600;letter-spacing:.06em">最佳匹配 · 歌手</div><b style="font-size:18px;display:block;margin-top:2px">${artist.a}</b><div style="font-size:12.5px;color:var(--t2);margin-top:2px">${SONGS.filter(s => s.a === artist.a).length} 首歌曲 · 1 张专辑</div></div>${ic('right')}</div>` : ''}
    ${exact ? '' : `<p class="hint" style="padding:14px var(--pad) 0">没有找到「${q}」的精确结果，为你展示相关内容</p>`}
    <div style="padding-top:8px">${res.map(s => songRow(s, { list:'all' })).join('')}</div>`; } };
ACT.searchTab = d => { S.searchTab = { 单曲:'song', 歌手:'artist', 专辑:'album', 歌单:'playlist' }[d.v]; render(); };

/* ================= Tab：每日混音 ================= */
PAGES.daily = { tabPage:true, render:() => {
  const ids = LISTS.daily();
  return `${largeHead('每日混音', `<button class="ib" data-act="reload">${ic('refresh')}</button>`)}
  ${S.loading ? skeleton() : `
  <div class="m daily-hero" style="${coverStyle(268, 2)}">
    <div class="dh-shade"></div>
    <div class="dh-date"><b>02</b><span>十一月<br>星期一</span></div>
    <div style="position:relative"><b style="font-size:22px">今天的 30 首</b><div style="font-size:12.5px;opacity:.8;margin-top:4px">根据你最近 30 天的 214 次聆听生成 · 明天 06:00 更新</div></div>
    <div style="position:relative;display:flex;gap:10px;margin-top:14px">
      <button class="btn pri sm" data-act="playAll" data-list="daily">${ic('play')}播放全部</button>
      <button class="btn sm" style="background:rgba(255,255,255,.18);color:#fff" data-act="playAll" data-list="daily" data-shuffle="1">${ic('shuffle')}随机</button></div></div>
  <div class="sec" style="padding-bottom:10px"><h2 style="font-size:16px">你的口味画像</h2><button class="more" data-act="push" data-v="stats">详情${ic('right')}</button></div>
  <div class="chips">${[['城市流行', 34], ['电子', 22], ['后摇', 16], ['华语独立', 14], ['Lo-fi', 9]].map(([n, p], i) => `<span class="chip ${i === 0 ? 'on' : ''}">${n} <b style="font-family:var(--font-num)">${p}%</b></span>`).join('')}</div>
  <div style="padding-top:12px">${ids.slice(0, 18).map(id => songRow(SONGS[id], { list:'daily', ctx:'daily' })).join('')}</div>
  <p class="hint" style="text-align:center;padding:14px">向左滑动歌曲可快速收藏或下一首播放；··· 里选「不感兴趣」，明天的推荐会参考你的反馈</p>`}`; } };
ACT.reload = () => reloadContent();

/* ================= Tab：音乐库 ================= */
PAGES.library = { tabPage:true, render:() => {
  const sg = S.libSeg;
  let body = '';
  if (sg === 'like') body = `
    <div class="m card like-hero">
      <div class="lk-ic">${ic('heartf')}</div>
      <div style="flex:1"><b style="font-size:17px">我喜欢的音乐</b><div style="font-size:12.5px;color:var(--t2);margin-top:3px;display:flex;gap:6px;align-items:center"><span data-count="${S.liked.size}">${S.liked.size}</span> 首 · <span style="color:var(--ok);display:inline-flex;align-items:center;gap:3px">${ic('cloud')}已同步</span> · 刚刚</div></div>
      <button class="ib" style="width:48px;height:48px;background:var(--accent);color:var(--accent-ink)" data-act="playAll" data-list="like">${ic('play')}</button></div>
    <div style="display:flex;gap:8px;padding:14px var(--pad) 4px"><span class="chip on">全部</span><span class="chip">已下载</span><span class="chip">Hi-Res</span><span class="chip">${ic('sort')}最近添加</span></div>
    ${[...S.liked].map(id => songRow(SONGS[id], { list:'like', heart:true })).join('')}`;
  if (sg === 'recent') body = `${[['今天', [S.cur, 5, 11, 2]], ['昨天', [7, 16, 18, 20, 9]], ['更早', [3, 14, 22]]].map(([g, ids]) => `<div class="grp-t" style="padding-left:var(--pad)">${g}</div>${ids.map(id => songRow(SONGS[id], { list:'all' })).join('')}`).join('')}`;
  if (sg === 'playlists') body = `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;padding:16px var(--pad) 0">
      <button class="card" style="aspect-ratio:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:var(--t2);border-style:dashed" data-act="sheet" data-v="newPlaylist">${ic('plus')}<span style="font-size:13px">新建歌单</span></button>
      <button class="card" style="aspect-ratio:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:var(--t2)" data-act="sheet" data-v="import">${ic('download')}<span style="font-size:13px">导入歌单</span><small style="font-size:11px;color:var(--t3)">平台链接 · 口令 · 文件</small></button>
      ${MY_PLAYLISTS.map(p => `<div class="pl" style="width:auto" data-act="push" data-v="playlist" data-id="${p.id}"><div class="cv" style="${coverStyle(p.h, p.v)};width:100%;height:auto;aspect-ratio:1">${p.tag ? `<span class="pc">${p.tag}</span>` : ''}</div><div class="t">${p.t}</div><div style="font-size:12px;color:var(--t3);margin-top:2px">${p.n} 首</div></div>`).join('')}</div>`;
  if (sg === 'local') {
    const ids = LISTS.local();
    body = `<div class="m card" style="margin-top:14px;padding:14px 16px;display:flex;gap:12px;align-items:center">
        <div style="width:42px;height:42px;border-radius:12px;background:var(--s2);display:flex;align-items:center;justify-content:center;color:var(--accent-text)">${ic('folder')}</div>
        <div style="flex:1"><b style="font-size:14.5px">本地 ${ids.length} 首 · 3.2 GB</b><div style="font-size:12px;color:var(--t3);margin-top:2px">/Music · /Download · 上次扫描 2 小时前</div></div>
        <button class="btn sec sm" data-act="toast" data-msg="扫描完成，新增 3 首，修复 2 个乱码标签" data-icon="refresh">扫描</button></div>
      <div style="display:flex;gap:8px;padding:14px var(--pad) 4px"><span class="chip on">歌曲</span><span class="chip">歌手</span><span class="chip">专辑</span><span class="chip">文件夹</span></div>
      ${ids.map(id => songRow(SONGS[id], { list:'local', ctx:'local' })).join('')}`;
  }
  return `${largeHead('音乐库', `<button class="ib" data-act="push" data-v="stats">${ic('chart')}</button><button class="ib" data-act="sheet" data-v="import">${ic('plus')}</button>`)}
    ${seg(['我喜欢', '最近', '歌单', '本地'], { like:'我喜欢', recent:'最近', playlists:'歌单', local:'本地' }[sg], 'libSegCN')}<div class="segbody">${body}</div>
    ${sg === 'local' ? `<div class="az">${'★ABCDEFGHJKLMNPQSTWXYZ#'.split('').map(l => `<span data-l="${l}">${l}</span>`).join('')}</div><div class="azb" style="display:none"></div>` : ''}`; } };
ACT.libSegCN = d => { const order = ['like', 'recent', 'playlists', 'local'], nv = { 我喜欢:'like', 最近:'recent', 歌单:'playlists', 本地:'local' }[d.v]; S._segDir = Math.sign(order.indexOf(nv) - order.indexOf(S.libSeg)); S.libSeg = nv; S._stagger = true; render(); };

/* ================= Tab：我的 ================= */
PAGES.me = { tabPage:true, render:() => `
  ${largeHead('我的', `<button class="ib" data-act="openScan" data-v="scan">${ic('scan')}</button>`)}
  <div class="m card" style="padding:18px;display:flex;gap:14px;align-items:center" data-act="push" data-v="account">
    <div class="avatar lg">栗</div>
    <div style="flex:1;min-width:0"><b style="font-size:19px">阿栗</b>
      <div style="font-size:12.5px;color:var(--t2);margin-top:3px">UID 10086427 · ali@example.com</div>
      <div style="display:flex;gap:6px;margin-top:8px"><span class="badge acc">${ic('crown')}已激活</span><span class="badge">${ic('phone')}3 台设备</span></div></div>${ic('right')}</div>
  <div class="m" style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:12px">
    ${[['6.2', '小时', '本周聆听'], ['12', '天', '连续聆听'], [String(S.liked.size), '首', '我喜欢']].map(([v, u, l]) => `<div class="card" style="padding:14px 12px" data-act="push" data-v="stats"><div style="font:750 24px var(--font-num)"><span data-count="${v}">${v}</span><small style="font-size:12px;color:var(--t3);font-weight:600;margin-left:2px">${u}</small></div><div style="font-size:12px;color:var(--t2);margin-top:2px">${l}</div></div>`).join('')}</div>
  <div class="qk" style="padding-bottom:6px">
    <button data-act="openScan" data-v="scan"><span class="ic">${ic('scan')}</span>扫一扫</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="push" data-v="download"><span class="ic">${ic('download')}</span>下载管理</button>
    <button data-act="push" data-v="stats"><span class="ic">${ic('chart')}</span>听歌统计</button></div>
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
    item({ icon:'download', color:'blue', label:'下载', val:`同时 ${S.set.dlConc} 首`, act:'push', args:{ v:'download' } }),
  ])}
  ${group('账号与数据', [
    item({ icon:'link', color:'green', label:'平台账号', val:'已登录 1 个', act:'push', args:{ v:'accounts3p' } }),
    item({ icon:'cloud', color:'blue', label:'备份与同步', val:'WebDAV', act:'push', args:{ v:'backup' } }),
    item({ icon:'bell', color:'orange', label:'公告', val:'1 条未读', act:'push', args:{ v:'announcements' } }),
    item({ icon:'info', color:'gray', label:'关于与更新', val:'v2.4.0', act:'push', args:{ v:'about' } }),
  ])}` };

/* ================= 二级页 ================= */
PAGES.playlist = { render:p => {
  const pl = p.id >= 100 ? MY_PLAYLISTS.find(x => x.id === p.id) : (PLAYLISTS[p.id] || PLAYLISTS[0]);
  const ids = p.id === 100 ? [...S.liked] : SONGS.map(s => s.id).filter((x, i) => (i * 7 + pl.h) % 3 !== 0).slice(0, 14);
  return `${appBar(pl.t, { glass:true, fade:true, right:`<button class="ib" data-act="sheet" data-v="shareCode">${ic('share')}</button>` })}
  <div class="hero-bg"><div style="${coverStyle(pl.h, pl.v)}"></div></div>
  <div class="hero">
    <div class="cv hero-cv" style="${coverStyle(pl.h, pl.v)}"></div>
    <h1>${pl.t}</h1>
    <div style="display:flex;gap:8px;align-items:center;margin-top:8px;font-size:13px;color:var(--t2)"><span class="avatar" style="width:22px;height:22px;font-size:10px">${(pl.by || '我')[0]}</span>${pl.by || '我'} · ${pl.n} 首${pl.pc ? ` · ${pl.pc} 次播放` : ''}</div>
    <p style="font-size:12.5px;color:var(--t3);margin-top:8px;line-height:1.55;max-width:300px">适合在夜里一个人走路时听。霓虹、雨声、合成器和一点点想念。</p>
    <div style="display:flex;gap:10px;margin-top:18px;width:100%">
      <button class="btn pri" style="flex:1" data-act="playAll" data-list="all">${ic('play')}播放全部</button>
      <button class="ib" style="width:48px;height:48px;background:var(--s2)" data-act="playAll" data-list="all" data-shuffle="1">${ic('shuffle')}</button>
      <button class="ib" style="width:48px;height:48px;background:var(--s2)" data-act="toast" data-msg="已加入下载队列 · ${pl.n} 首" data-icon="download">${ic('download')}</button>
      <button class="ib" style="width:48px;height:48px;background:var(--s2)" data-act="toast" data-msg="已收藏歌单" data-icon="heartf">${ic('heart')}</button></div></div>
  <div style="display:flex;align-items:center;padding:20px var(--pad) 6px;gap:8px"><b style="flex:1;font-size:15px">${ids.length} 首歌曲</b><button class="chip" style="height:30px">${ic('sort')}默认</button><button class="chip" style="height:30px">${ic('check')}多选</button></div>
  ${ids.map(id => songRow(SONGS[id], { list:'all' })).join('')}`; } };

PAGES.artist = { render:p => {
  const s = SONGS[p.id || 0]; const mine = SONGS.filter(x => x.a === s.a);
  return `${appBar(s.a, { glass:true, fade:true, right:`<button class="ib" data-act="toast" data-msg="已关注 ${s.a}" data-icon="heartf">${ic('heart')}</button>` })}
  <div class="art-bg"><div style="${coverStyle(s.h, 1)}"></div></div>
  <div style="position:relative;padding:150px var(--pad) 0"><h1 style="font-size:34px;font-weight:800;color:#fff;text-shadow:0 2px 20px rgba(0,0,0,.4)">${s.a}</h1>
    <div style="font-size:13px;color:var(--t2);margin-top:6px">12.4 万关注 · 本月 38 万次聆听</div>
    <div style="display:flex;gap:10px;margin-top:16px"><button class="btn pri" data-act="playAll" data-list="all">${ic('play')}播放热门</button><button class="btn sec">${ic('wave')}歌手电台</button></div></div>
  <div class="sec"><h2>热门歌曲</h2></div>${mine.concat(SONGS.slice(0, 3)).slice(0, 6).map((x, i) => songRow(x, { num:i, list:'all' })).join('')}
  <div class="sec"><h2>专辑</h2></div><div class="hs">${[s.al, '现场 · 2025', '单曲合集'].map((a, i) => `<div class="pl"><div class="cv" style="${coverStyle(s.h + i * 30, i)}"></div><div class="t">${a}</div><div style="font-size:12px;color:var(--t3)">${2026 - i}</div></div>`).join('')}</div>`; } };

PAGES.stats = { render:() => `${appBar('听歌统计')}
  <div style="margin-bottom:16px">${seg(['近 7 天', '近 30 天', '近 90 天'], '近 7 天', 'toast')}</div>
  <div class="m" style="display:grid;grid-template-columns:1fr 1fr;gap:10px">${[['6.2', '小时', '聆听时长', '+18%'], ['214', '次', '播放次数', '+9%'], ['63', '首', '不同歌曲', ''], ['21', '位', '不同歌手', '']].map(([v, u, l, d]) => `<div class="card" style="padding:16px"><div style="font-size:12px;color:var(--t2)">${l}</div><div style="font:750 28px var(--font-num);margin-top:6px"><span data-count="${v}">${v}</span><small style="font-size:13px;color:var(--t3);margin-left:3px">${u}</small></div>${d ? `<div style="font-size:11.5px;color:var(--ok);margin-top:2px">较上周 ${d}</div>` : ''}</div>`).join('')}</div>
  <div class="sec"><h2 style="font-size:16px">每日时长</h2><span class="more">分钟</span></div>
  <div class="card m" style="padding:18px 14px 12px"><div class="bars grow">${[42, 65, 38, 80, 54, 96, 71].map((v, i) => `<div><b style="height:${v}%;--d:${i * 60}ms;${i === 5 ? '' : 'opacity:.55'}"></b>${'一二三四五六日'[i]}</div>`).join('')}</div></div>
  <div class="sec"><h2 style="font-size:16px">风格分布</h2></div>
  <div class="card m" style="padding:14px 16px">${[['城市流行', 34], ['电子', 22], ['后摇', 16], ['华语独立', 14], ['其他', 14]].map(([n, p], i) => `<div style="display:flex;align-items:center;gap:10px;margin:8px 0;font-size:13px"><span style="width:64px;color:var(--t2)">${n}</span><div style="flex:1;height:8px;border-radius:4px;background:var(--s3);overflow:hidden"><div class="gbar" style="width:${p * 2.4}%;--d:${i * 70}ms"></div></div><b style="width:36px;text-align:right;font-family:var(--font-num)">${p}%</b></div>`).join('')}</div>
  <div class="sec"><h2 style="font-size:16px">90 天聆听足迹</h2></div>
  <div class="card m" style="padding:14px"><div class="heat">${Array.from({ length:90 }, (_, i) => { const v = (Math.sin(i * 1.7) + Math.sin(i * .37) + 2) / 4; return `<i style="background:color-mix(in srgb,var(--accent) ${Math.round(v * v * 100)}%,var(--s3));--d:${i * 6}ms"></i>`; }).join('')}</div></div>
  <div class="sec"><h2 style="font-size:16px">最常听的歌手</h2></div>
  <div class="hs">${['雾港', '回声实验室', 'Nova Lane', '苏米', '夜行列车'].map((a, i) => `<div style="width:84px;text-align:center"><div class="cv" style="${coverStyle(i * 70 + 20, 1)};width:76px;height:76px;border-radius:38px;margin:0 auto"></div><div style="font-size:12.5px;margin-top:8px;font-weight:600">${a}</div><div style="font-size:11px;color:var(--t3)">${48 - i * 7} 次</div></div>`).join('')}</div>` };

/* ================= 扫一扫（多合一：设备登录 / 歌单码 / 分享码 / 听歌识曲） ================= */
ACT.openScan = d => { S.scanMode = d.v === 'match' ? 'match' : 'scan'; S.scanResult = null; S.qrState = 'scan'; ACT.push({ v:'scan' }); if (S.scanMode === 'match') ACT.match(); };
PAGES.scan = { full:true, lightBar:true, render:() => {
  const mode = S.scanMode, r = S.scanResult;
  const switcher = `<div class="scan-sw">${seg(['扫一扫', '听歌识曲'], mode === 'match' ? '听歌识曲' : '扫一扫', 'scanMode', 'dark')}</div>`;
  let body = '';
  if (mode === 'match') {
    const found = S.matchState === 'found', s = SONGS[7];
    body = found ? `<div class="scan-res">${cover(s, 'hero-cv', 200)}<div class="badge acc" style="margin-top:20px">${ic('check')}已识别 · 匹配度 96%</div>
        <h1 style="font-size:26px;font-weight:750;margin-top:12px">${s.t}</h1><p style="color:rgba(255,255,255,.65);margin-top:4px">${s.a} · ${s.al}</p>
        <div style="display:flex;gap:10px;margin-top:24px;width:100%"><button class="btn pri" style="flex:1" data-act="play" data-id="7">${ic('play')}立即播放</button><button class="btn sec" data-act="like" data-id="7">${ic('heart')}收藏</button></div>
        <button class="btn ghost block" style="margin-top:10px;color:#fff;border-color:rgba(255,255,255,.2)" data-act="match">再识别一首</button></div>`
      : `<div class="match"><i></i><i></i><i></i><div class="core">${ic('mic')}</div></div>
        <div style="text-align:center"><h2 style="font-size:20px;font-weight:700">正在聆听…</h2><p style="color:rgba(255,255,255,.62);font-size:13.5px;margin-top:8px">把手机靠近声源，保持 5–10 秒</p></div>
        <div class="wavebar">${'<i></i>'.repeat(32)}</div>
        <p class="hint" style="text-align:center;margin-top:30px;color:rgba(255,255,255,.45)">音频指纹在本地生成，只上传指纹，不上传录音</p>`;
  } else if (!r) {
    body = `<div class="vf">${['tl', 'tr', 'bl', 'br'].map(p => `<i class="c ${p}"></i>`).join('')}<div class="scanline"></div></div>
      <p style="text-align:center;color:rgba(255,255,255,.82);margin-top:26px;font-size:14px">对准二维码，自动识别</p>
      <div class="scan-types">${[['tv', '设备登录', '电视 · 车机 · 桌面端'], ['grid', '歌单码', '导入或打开歌单'], ['link', '分享码', '播放好友分享的歌']].map(([i, n, d]) => `<div>${ic(i)}<b>${n}</b><small>${d}</small></div>`).join('')}</div>
      <div class="scan-demo"><span>原型演示：</span>${[['tv', '电视登录'], ['playlist', '歌单码'], ['song', '分享码']].map(([k, n]) => `<button data-act="scanSim" data-v="${k}">${n}</button>`).join('')}</div>`;
  } else if (r === 'tv' || r === 'tvdone') {
    const done = r === 'tvdone';
    body = `<div class="scan-res"><div class="res-ic">${ic(done ? 'check' : 'tv')}</div>
      <h1 style="font-size:22px;font-weight:750;margin-top:22px">${done ? '客厅电视已登录' : '在「客厅电视」上登录？'}</h1>
      <p style="color:rgba(255,255,255,.65);font-size:14px;line-height:1.6;margin-top:8px">${done ? '歌单与收藏会自动同步，可以在电视上继续播放。' : 'Lyra TV · Android 12 · 192.168.1.23<br>确认后电视将使用你的账号'}</p>
      ${done ? `<button class="btn pri block" style="margin-top:28px" data-act="back">完成</button>` : `<button class="btn pri block" style="margin-top:28px" data-act="scanDone" data-v="tv">确认登录</button><button class="btn ghost block" style="margin-top:10px;color:#fff;border-color:rgba(255,255,255,.2)" data-act="scanSim" data-v="">取消</button>`}</div>`;
  } else {
    const isPl = r === 'playlist', s = SONGS[7], pl = PLAYLISTS[3];
    body = `<div class="scan-res"><div class="badge acc">${ic('check')}识别到${isPl ? '歌单码' : '歌曲分享码'}</div>
      <div class="res-card">${isPl ? `<div class="cv" style="${coverStyle(pl.h, pl.v)};width:72px;height:72px;border-radius:16px"></div><div style="flex:1;text-align:left"><b style="font-size:16px">${pl.t}</b><div style="font-size:12.5px;color:rgba(255,255,255,.6);margin-top:3px">${pl.n} 首 · 来自 ${plat().n}</div></div>`
        : `${cover(s, '', 72)}<div style="flex:1;text-align:left"><b style="font-size:16px">${s.t}</b><div style="font-size:12.5px;color:rgba(255,255,255,.6);margin-top:3px">${s.a} · 小满分享给你</div><div style="font-size:12.5px;margin-top:6px">“这首适合夜里开车”</div></div>`}</div>
      <button class="btn pri block" style="margin-top:22px" data-act="scanDone" data-v="${isPl ? 'playlist' : 'song'}">${isPl ? '打开歌单' : '立即播放'}</button>
      <button class="btn ghost block" style="margin-top:10px;color:#fff;border-color:rgba(255,255,255,.2)" data-act="scanSim" data-v="">继续扫描</button></div>`;
  }
  return `<div class="scan-bg"></div>
    <div class="ab" style="background:none"><button class="ib" data-act="back" style="color:#fff">${ic('close')}</button><div class="ttl" style="color:#fff">${mode === 'match' ? '听歌识曲' : '扫一扫'}</div><button class="ib" style="color:#fff" data-act="toast" data-msg="已打开相册" data-icon="album">${mode === 'match' ? '' : ic('album')}</button></div>
    <div class="scan-body">${body}</div>${switcher}`; } };

PAGES.announcements = { render:() => `${appBar('公告')}
  ${[['重要', '11 月 2 日', '服务端维护通知', '11 月 5 日 02:00–04:00 进行数据库升级，期间同步与登录不可用，离线播放不受影响。', true], ['新功能', '10 月 28 日', '律动 / 灵动皮肤上线', 'Apple Music 风格的两套播放器皮肤：弹簧逐字歌词、波浪浮动歌词。', false], ['更新', '10 月 12 日', 'v2.4.0 发布', '新增液态玻璃底栏、平台与解析脚本两级选择。', false]].map(([k, d, t, b, imp]) => `
    <div class="card m" style="margin-bottom:12px;padding:16px">
      <div style="display:flex;gap:8px;align-items:center"><span class="badge ${imp ? 'acc' : ''}">${k}</span><span style="font-size:12px;color:var(--t3)">${d}</span>${imp ? '<span class="pulse-dot"></span>' : ''}</div>
      <b style="display:block;font-size:16px;margin-top:10px">${t}</b><p style="font-size:13.5px;color:var(--t2);line-height:1.6;margin-top:6px">${b}</p>
      ${imp ? `<button class="btn sec sm" style="margin-top:12px" data-act="dialog" data-v="announce">查看并确认</button>` : ''}</div>`).join('')}` };

/* ================= 剪贴板口令：从刘海处展开的横幅 ================= */
function clipBanner() {
  const s = SONGS[S.clip];
  return `<div class="clipbn"><div class="cb-in">${cover(s, '', 44)}
    <div style="flex:1;min-width:0"><small>检测到好友分享的歌曲</small><b>${s.t} · ${s.a}</b></div>
    <button class="cb-x" data-act="clipClose">${ic('close')}</button><button class="cb-go" data-act="clipPlay">${ic('play')}</button></div></div>`;
}
