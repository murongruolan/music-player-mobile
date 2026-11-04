/* v4.2：把原型里「点了只弹 Toast」或「点了没反应」的入口补成完整的页面 / 抽屉 / 弹窗。
   在 cloud.js 之后加载。只覆盖或包装已有渲染函数，不改其它文件里的结构。清单见 ../DESIGN.md「v4.2 补全」。 */
ICONS.paste = '<rect x="6" y="4" width="12" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h4"/>';
Object.assign(S, { plSort:'默认', plMulti:false, plSel:new Set(), statsRange:'近 7 天', rSort:'综合', rLossless:false, likeChip:'全部', likeSort:'最近添加', localView:'歌曲',
  sqCat:'全部', sqSort:'推荐', albReg:'全部', chartTab:'官方', mvReg:'内地', vidCat:'推荐', dlPaused:new Set(), mvLiked:false, pwdStep:0, flColor:0, btOrder:1, dlName:0 });
Object.assign(S.set, { flFs:18, flOp:60, genreAuto:true });
// main.js 的 reset() 会调用这里（本文件先于 main.js 加载）
function fixReset() { Object.assign(S, { plSort:'默认', plMulti:false, plSel:new Set(), statsRange:'近 7 天', rSort:'综合', rLossless:false, likeChip:'全部', likeSort:'最近添加', localView:'歌曲', sqCat:'全部', sqSort:'推荐', albReg:'全部', chartTab:'官方', mvReg:'内地', vidCat:'推荐', dlPaused:new Set(), mvLiked:false, pwdStep:0, flColor:0, btOrder:1, dlName:0 }); }
const tagChips = (opts, cur, act, cls = '') => `<div class="chips tight ${cls}">${opts.map(o => `<button class="chip ${o === cur ? 'on' : ''}" data-act="${act}" data-v="${o}">${o}</button>`).join('')}</div>`;
const secA = (t, more, attrs) => `<div class="sec"><h2>${t}</h2>${more ? `<button class="more" ${attrs}>${more}${ic('right')}</button>` : ''}</div>`;

/* ================= 1. 发现 · 平台推荐区：「更多 / 全部 / 播放 / 换一批 / 调整」都接上 ================= */
const REC_MORE = {
  albums:'data-act="push" data-v="newAlbums"', newsongs:'data-act="playAll" data-list="all"', official:'data-act="push" data-v="charts"',
  plcats:'data-act="push" data-v="plSquare"', mvrank:'data-act="push" data-v="mvRank"', videos:'data-act="push" data-v="videos"',
  nowlisten:'data-act="nowShuffle"', mood:'data-act="plCat" data-v="治愈"', fresh:'data-act="playAll" data-list="all"',
};
Object.keys(REC).forEach(k => {
  const f = REC[k];
  REC[k] = () => {
    let h = f();
    if (k === 'genres') h = h.replace('<button class="more">', isIn(S.plat) ? '<button class="more" data-act="sheet" data-v="genrePref">' : '<button class="more" data-act="push" data-v="plSquare">')
      .replace(/<div class="cv gtile" style="([^"]*)"><b>([^<]+)<\/b>/g, '<div class="cv gtile" style="$1" data-act="plCat" data-v="$2"><b>$2</b>');
    else if (REC_MORE[k]) h = h.replace('<button class="more">', `<button class="more" ${REC_MORE[k]}>`);
    if (k === 'plcats') h = h.replace(/<button style="(--d:\d+ms)">([^<]+)<\/button>/g, '<button style="$1" data-act="plCat" data-v="$2">$2</button>');
    if (k === 'nowlisten') h = h.replace(/<button class="chip">([^<]+)<\/button>/g, '<button class="chip" data-act="plCat" data-v="$1">$1</button>');
    return h;
  };
});
ACT.nowShuffle = () => { S._stagger = true; render(); toast('已换一批 · 按现在的时间和你最近常听的', 'refresh'); };
ACT.plCat = d => { S.sqCat = d.v; ACT.push({ v:'plSquare' }); };

/* ---------- 歌单广场 ---------- */
const SQ_CATS = { 常用:['全部', '华语', '流行', '摇滚', '民谣', '电子', '轻音乐', '深夜', '治愈'], 语种:['华语', '欧美', '日语', '韩语', '粤语'], 风格:['流行', '摇滚', '民谣', '电子', '说唱', '爵士', '古典', '后摇', 'Lo-fi', 'R&B'], 场景:['通勤', '学习', '运动', '开车', '睡前', '做饭', '咖啡馆', '旅行'], 情感:['治愈', '伤感', '放松', '开心', '思念', '深夜'], 主题:['ACG', '影视原声', '游戏', '网络歌曲', 'KTV', '经典老歌'] };
const plCard = (x, i) => `<div class="pl" style="width:auto;--d:${i * 30}ms" data-act="push" data-v="playlist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, x.v)};width:100%;height:auto;aspect-ratio:1"><span class="pc">${ic('play')}${x.pc}</span></div><div class="t">${x.t}</div><div class="sub42">${x.by} · ${x.n} 首</div></div>`;
PAGES.plSquare = { render:() => {
  const cats = SQ_CATS.常用.includes(S.sqCat) ? SQ_CATS.常用 : [S.sqCat, ...SQ_CATS.常用.slice(1)];
  const list = [...PLAYLISTS, ...PLAYLISTS.map(p => ({ ...p, id:p.id, t:`${S.sqCat === '全部' ? '' : S.sqCat + ' · '}${p.t}`, h:(p.h + 60) % 360 }))].slice(0, 12);
  return `${appBar('歌单广场', { right:`<button class="ib" data-act="sheet" data-v="plCats">${ic('grid')}</button>` })}
    <div class="sq-cats">${cats.map(c => `<button class="${c === S.sqCat ? 'on' : ''}" data-act="sqCat" data-v="${c}">${c}</button>`).join('')}<button class="sq-all" data-act="sheet" data-v="plCats">${ic('grid')}全部</button></div>
    <div class="sq-bar"><small>${S.sqCat === '全部' ? '全部歌单' : `「${S.sqCat}」歌单`} · ${plat().n}</small>${seg(['推荐', '最新', '最热'], S.sqSort, 'sqSort', 'mini42')}</div>
    ${S.sqCat !== '全部' ? `<div class="m card sq-hero" style="${coverStyle(PLAYLISTS[3].h, 2)}"><b>${S.sqCat}</b><small>${plat().n}上「${S.sqCat}」分类 · 每日更新</small><button class="hc-play" data-act="playAll" data-list="hot" data-shuffle="1">${ic('play')}</button></div>` : ''}
    <div class="sq-grid" key="${S.sqCat}${S.sqSort}">${list.map(plCard).join('')}</div>
    <div class="load42"><i class="spinner sm"></i>正在加载更多</div>`;
} };
SHEETS.plCats = () => ({ t:'全部分类', sub:plat().n, right:`<button class="chip" style="height:30px;margin-right:6px" data-act="toast" data-msg="长按分类拖到「常用」里" data-icon="drag">${ic('edit')}编辑常用</button>`, body:Object.entries(SQ_CATS).map(([g, l]) => `<div class="grp-t" style="padding-left:var(--pad)">${g}</div><div class="cats42">${l.map(c => `<button class="${c === S.sqCat ? 'on' : ''}" data-act="sqCatSheet" data-v="${c}">${c}</button>`).join('')}</div>`).join('') });
ACT.sqCat = d => { S.sqCat = d.v; S._stagger = true; render(); };
ACT.sqCatSheet = d => { S.sqCat = d.v; S.sheet = null; S._stagger = true; if (S.stack.at(-1)?.id !== 'plSquare') return ACT.push({ v:'plSquare' }); render(); };
ACT.sqSort = d => { S.sqSort = d.v; S._stagger = true; render(); };

/* ---------- 新碟上架 ---------- */
PAGES.newAlbums = { render:() => `${appBar('新碟上架')}
  ${tagChips(['全部', '华语', '欧美', '日韩', 'Hi-Res'], S.albReg, 'albReg', 'pad42')}
  ${[['本周', [2, 7, 12, 16]], ['上周', [21, 1, 5, 9]], ['更早', [14, 18]]].map(([g, ids]) => `<div class="grp-t" style="padding-left:var(--pad)">${g}</div>
    <div class="na-grid" key="${S.albReg}">${ids.map((id, i) => { const s = SONGS[(id + (S.albReg === '欧美' ? 16 : S.albReg === '日韩' ? 8 : 0)) % SONGS.length]; return `<div class="na" data-act="push" data-v="playlist" data-id="${id % 8}" style="--d:${i * 40}ms"><div class="na-cv"><div class="cv" style="${coverStyle(s.h, s.v)}"></div><i></i></div><b>${s.al}</b><small>${s.a}</small><small class="na-meta">${['11-02', '11-01', '10-30', '10-28'][i % 4]} · ${8 + i * 2} 首${s.q === 'Hi-Res' ? ' · <em>Hi-Res</em>' : ''}</small></div>`; }).join('')}</div>`).join('')}` };
ACT.albReg = d => { S.albReg = d.v; S._stagger = true; render(); };

/* ---------- 排行榜 ---------- */
const CHARTS = { 官方:[['飙升榜', 340, [11, 17, 5], '刚刚更新'], ['新歌榜', 30, [8, 13, 19], '每天更新'], ['热歌榜', 210, [0, 2, 4], '每天更新'], ['原创榜', 150, [7, 21, 12], '每周四更新']],
  特色:[['Hi-Res 榜', 45, [7, 0, 17]], ['电音榜', 260, [8, 2, 19]], ['说唱榜', 0, [11, 5, 16]], ['ACG 榜', 300, [12, 4, 22]], ['国风榜', 20, [9, 1, 13]], ['民谣榜', 120, [3, 10, 14]]],
  全球:[['美国 Billboard', 220, [16, 17, 19]], ['英国 UK', 200, [18, 16, 17]], ['日本 Oricon', 330, [20, 21, 22]], ['韩国 Melon', 280, [19, 22, 16]]] };
const rkCard = ([n, h, ids, up]) => `<div class="rk" style="--h:${h}" data-act="push" data-v="playlist" data-id="${h % 8}"><div class="rk-h"><b>${n}</b><small>${up || '每周更新'}</small></div>${ids.map((id, i) => `<div class="rk-r">${cover(SONGS[id], '', 40)}<b>${i + 1}</b><div><span>${SONGS[id].t}</span><small>${SONGS[id].a}</small></div><em class="${i === 0 ? 'up' : ''}">${['▲3', '—', '▼1'][i]}</em></div>`).join('')}</div>`;
PAGES.charts = { render:() => `${appBar('排行榜')}
  <div style="margin-bottom:10px">${seg(['官方', '特色', '全球'], S.chartTab, 'chartTab')}</div>
  ${S.chartTab === '官方' ? `<div class="ch-list" key="o">${CHARTS.官方.map(rkCard).join('')}</div>`
    : `<div class="ch-grid" key="${S.chartTab}">${CHARTS[S.chartTab].map(([n, h, ids], i) => `<div class="ch-tile" data-act="push" data-v="playlist" data-id="${h % 8}" style="--d:${i * 35}ms"><div class="cv" style="${coverStyle(h, 2)}"><b>${n}</b><span>${ic('play')}</span></div><small>1 ${SONGS[ids[0]].t}</small><small>2 ${SONGS[ids[1]].t}</small></div>`).join('')}</div>`}
  <p class="hint" style="padding:12px var(--pad) 0">榜单由${plat().n}提供，未登录也能看；点进去和歌单详情一样可以播放、收藏。</p>` };
ACT.chartTab = d => { S.chartTab = d.v; S._stagger = true; render(); };

/* ---------- MV 排行 / 推荐视频 / 视频播放 ---------- */
const mvRow = (i, k) => { const s = SONGS[(i * 5 + 3 + k) % SONGS.length]; return `<div class="mvr" data-act="push" data-v="mvPlay" data-id="${s.id}"><b class="${i === 0 ? 'top' : ''}">${i + 1}</b><div class="cv mv-th" style="${coverStyle(s.h + 20, s.v)}"><span class="mv-d">${fmt(180 + i * 31)}</span></div><div><span>${s.t}</span><small>${s.a} · ${98 - i * 9}万次播放</small><em class="${i < 2 ? 'up' : ''}">${['▲2', '▲5', '—', '▼1', '—', '▲1', '—', '▼2'][i]}</em></div></div>`; };
PAGES.mvRank = { render:() => `${appBar('MV 排行')}${tagChips(['内地', '港台', '欧美', '韩国', '日本'], S.mvReg, 'mvReg', 'pad42')}
  <div class="m" key="${S.mvReg}">${Array.from({ length:8 }, (_, i) => mvRow(i, ['内地', '港台', '欧美', '韩国', '日本'].indexOf(S.mvReg) * 3)).join('')}</div>
  <p class="hint" style="padding:12px var(--pad) 0">按近 7 天播放量排名，每周一更新。</p>` };
ACT.mvReg = d => { S.mvReg = d.v; S._stagger = true; render(); };
PAGES.videos = { render:() => `${appBar('推荐视频')}${tagChips(['推荐', '现场', '翻唱', '舞蹈', 'MV', '幕后'], S.vidCat, 'vidCat', 'pad42')}
  <div class="mvgrid" key="${S.vidCat}">${[0, 1, 2, 3, 4, 5, 6, 7].map(i => { const s = SONGS[(i * 3 + 1 + S.vidCat.length) % SONGS.length]; return `<div class="mv" data-act="push" data-v="mvPlay" data-id="${s.id}" style="--d:${i * 30}ms"><div class="cv mv-th" style="${coverStyle(s.h + 30, i)}"><span class="mv-d">${fmt(140 + i * 29)}</span><span class="mv-p">${ic('play')}</span></div><b>${s.t}（${S.vidCat === '推荐' ? '现场' : S.vidCat}）</b><small>${s.a} · ${(i * 37 + 12) % 90 + 3}万次播放</small></div>`; }).join('')}</div>` };
ACT.vidCat = d => { S.vidCat = d.v; S._stagger = true; render(); };
PAGES.mvPlay = { full:true, lightBar:true, render:p => {
  const s = SONGS[p.id ?? 3];
  return `<div class="mvp">
    <div class="mvp-v" style="${coverStyle(s.h + 20, s.v)}"><button class="ib mvp-back" data-act="back">${ic('left')}</button><button class="ib mvp-more" data-act="sheet" data-v="mvQuality">${ic('more')}</button>
      <button class="mvp-play" data-act="toast" data-msg="已暂停" data-icon="pause">${ic('pause')}</button>
      <div class="mvp-bar"><span>1:12</span><div><i style="width:34%"></i><b style="left:34%"></b></div><span>${fmt(s.dur)}</span><button data-act="sheet" data-v="mvQuality">1080P</button><button data-act="toast" data-msg="横屏全屏播放" data-icon="phone">${ic('ext')}</button></div></div>
    <div class="mvp-body">
      <h2>${s.t}（Official MV）</h2><small>${s.a} · 2026-10-28 · ${(s.id * 37 + 12) % 90 + 3}万次播放</small>
      <div class="mvp-art" data-act="push" data-v="artist" data-id="${s.id}"><div class="cv" style="${coverStyle(s.h, 1)}"></div><div><b>${s.a}</b><small>12.4 万关注 · 18 支 MV</small></div><button class="btn sec sm" data-act="toast" data-msg="已关注 ${s.a}" data-icon="heartf">关注</button></div>
      <div class="mvp-acts">${[['heart' + (S.mvLiked ? 'f' : ''), S.mvLiked ? '1.3万' : '1.2万', 'mvLike'], ['plus', '收藏', 'mvFav'], ['share', '分享', 'mvShare'], ['download', '下载', 'mvDl'], ['music', '听歌曲', 'mvSong']].map(([i, n, a]) => `<button data-act="${a}" data-id="${s.id}" class="${a === 'mvLike' && S.mvLiked ? 'on' : ''}">${ic(i)}<span>${n}</span></button>`).join('')}</div>
      <div class="grp-t">相关推荐</div>
      ${[1, 2, 3, 4].map(k => { const x = SONGS[(s.id + k * 3) % SONGS.length]; return `<div class="mvp-rel" data-act="push" data-v="mvPlay" data-id="${x.id}"><div class="cv mv-th" style="${coverStyle(x.h + 20, x.v)}"><span class="mv-d">${fmt(160 + k * 21)}</span></div><div><b>${x.t}（${['现场', 'MV', '舞蹈版', '幕后'][k - 1]}）</b><small>${x.a} · ${k * 13 + 4}万次播放</small></div></div>`; }).join('')}
    </div></div>`;
} };
SHEETS.mvQuality = () => ({ t:'视频设置', dark:true, body:`${group('画质', ['1080P · 蓝光', '720P · 超清', '480P · 高清', '自动'].map((q, i) => `<div class="it noic" data-act="sheetToast" data-msg="已切换到 ${q.split(' ')[0]}" data-icon="hd"><div class="lb"><b>${q}</b>${i === 3 ? '<small>按网络自动选择</small>' : ''}</div>${i === 0 ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`))}
  ${group('', [item({ icon:'speed', color:'violet', label:'倍速', val:'1.0×', act:'sheet', args:{ v:'speed' } }), item({ icon:'moon', color:'blue', label:'只听声音', sub:'关闭画面，节省流量', sw:'pitch' }), item({ icon:'wifi', color:'teal', label:'移动网络下自动降为 480P', sw:'wifiOnly' })])}` });
Object.assign(ACT, {
  mvLike: () => { S.mvLiked = !S.mvLiked; render(); toast(S.mvLiked ? '已点赞' : '已取消点赞', 'heartf'); },
  mvFav: () => toast('已收藏到「我的视频」', 'plus'), mvShare: () => { S.sheet = { v:'shareCode', id:S.cur }; render(); },
  mvDl: () => toast('已加入下载 · 1080P · 186 MB', 'download'), mvSong: d => { playSong(+d.id, 'all'); S.stack.pop(); render(); ACT.openPlayer(); },
});

/* ---------- 曲风偏好 ---------- */
SHEETS.genrePref = () => ({ t:'曲风偏好', sub:'影响「为你定制」和每日推荐', body:`<div class="gp-list">${[['城市流行', 34, 300], ['电子', 22, 200], ['后摇', 16, 225], ['华语独立', 14, 30], ['Lo-fi', 9, 280], ['R&B', 5, 340]].map(([n, p, h]) => `<div class="gp"><i style="background:hsl(${h} 60% 55%)"></i><b>${n}</b><div class="gp-st">${['少听', '默认', '多听'].map((x, k) => `<button class="${(p > 20 ? 2 : p > 8 ? 1 : 0) === k ? 'on' : ''}" data-act="toast" data-msg="${n}：${x}" data-icon="sliders">${x}</button>`).join('')}</div><small>${p}%</small></div>`).join('')}</div>
  <div class="grp-t" style="padding-left:var(--pad)">再加几个</div><div class="cats42">${['爵士', '古典', '民谣', '说唱', 'ACG', '摇滚', '轻音乐'].map(c => `<button data-act="toast" data-msg="已添加「${c}」" data-icon="plus">${ic('plus')}${c}</button>`).join('')}</div>
  ${group('', [item({ icon:'sparkle', color:'gold', label:'根据听歌记录自动调整', sub:'每周按你最近 30 天的聆听更新一次', sw:'genreAuto' })])}` });

/* ================= 2. 歌单详情：排序 + 多选 ================= */
const _plR = PAGES.playlist.render;
PAGES.playlist.render = p => {
  let h = _plR(p);
  h = h.replace(/<button class="chip" style="height:30px">(<svg[\s\S]*?<\/svg>)默认<\/button><button class="chip" style="height:30px">(<svg[\s\S]*?<\/svg>)多选<\/button>/,
    (m, a, b) => `<button class="chip" style="height:30px" data-act="sheet" data-v="plSortS">${a}${S.plSort}</button><button class="chip ${S.plMulti ? 'on' : ''}" style="height:30px" data-act="plMulti">${b}${S.plMulti ? '完成' : '多选'}</button>`);
  if (S.plMulti) {
    h = h.replace(/class="row ([^"]*)" data-act="play" data-id="(\d+)"/g, (m, c, id) => `class="row sel42 ${S.plSel.has(+id) ? 'picked' : ''} ${c}" data-act="plPick" data-id="${id}"`);
    h += `<div class="multibar"><span>已选 ${S.plSel.size}</span>${[['next', '下一首', '已添加到下一首播放'], ['plus', '加歌单', ''], ['download', '下载', '已加入下载'], ['trash', '移除', '已从歌单移除']].map(([i, n, m]) => `<button class="${S.plSel.size ? '' : 'dis'}" ${i === 'plus' ? 'data-act="sheet" data-v="addTo"' : `data-act="plMultiAct" data-msg="${m}" data-icon="${i}"`}>${ic(i)}<span>${n}</span></button>`).join('')}</div>`;
  }
  return h;
};
SHEETS.plSortS = () => ({ t:'排序', body:`<div class="grp">${['默认', '歌名', '歌手', '专辑', '时长', '最近添加'].map(o => `<div class="it noic" data-act="plSortPick" data-v="${o}"><div class="lb"><b>${o}</b></div>${S.plSort === o ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>` });
Object.assign(ACT, {
  plSortPick: d => { S.plSort = d.v; S.sheet = null; S._stagger = true; render(); },
  plMulti: () => { S.plMulti = !S.plMulti; S.plSel = new Set(); render(); },
  plPick: d => { const id = +d.id; S.plSel.has(id) ? S.plSel.delete(id) : S.plSel.add(id); render(); },
  plMultiAct: d => { if (!S.plSel.size) return; const n = S.plSel.size; S.plMulti = false; S.plSel = new Set(); render(); toast(`${d.msg} · ${n} 首`, d.icon); },
});

/* ================= 3. 歌手电台 / 下载暂停 / 播放队列存为歌单 ================= */
const _arR = PAGES.artist.render;
PAGES.artist.render = p => _arR(p).replace(/<button class="btn sec">(<svg[\s\S]*?<\/svg>)歌手电台<\/button>/, '<button class="btn sec" data-act="artistRadio">$1歌手电台</button>');
ACT.artistRadio = () => { ACT.playAll({ list:'hot', shuffle:'1' }); toast('歌手电台：从这位歌手出发，连续播放相似的歌', 'wave'); };
const _dlR = PAGES.download.render;
let _dlI = 0;
PAGES.download.render = () => { _dlI = 0; return _dlR().replace(/<button class="ib" style="color:var\(--t3\)">(<svg[\s\S]*?<\/svg>)<\/button>/g, () => { const i = _dlI++; const on = S.dlPaused.has(i); return `<button class="ib" style="color:var(--t3)" data-act="dlPause" data-v="${i}">${ic(on ? 'play' : 'pause')}</button>`; }); };
ACT.dlPause = d => { const i = +d.v; S.dlPaused.has(i) ? S.dlPaused.delete(i) : S.dlPaused.add(i); render(); toast(S.dlPaused.has(i) ? '已暂停' : '继续下载', S.dlPaused.has(i) ? 'pause' : 'download'); };

/* ================= 4. 听歌统计：时间范围真的切换 ================= */
const _stR = PAGES.stats.render;
PAGES.stats.render = () => {
  const k = { '近 7 天':1, '近 30 天':4.1, '近 90 天':11.6 }[S.statsRange];
  let h = _stR().replace(/<div class="seg [^"]*" style="--n:3;--i:0">[\s\S]*?<\/div>/, seg(['近 7 天', '近 30 天', '近 90 天'], S.statsRange, 'statsRange'));
  if (k !== 1) h = h.replace(/data-count="([\d.]+)">([\d.]+)/g, (m, v) => { const n = (+v * (v.includes('.') ? k : Math.sqrt(k) * 1.6)).toFixed(v.includes('.') ? 1 : 0); return `data-count="${n}">${n}`; }).replace(/较上周/g, '较上期').replace('每日时长', S.statsRange === '近 30 天' ? '每周时长' : '每月时长');
  return h;
};
ACT.statsRange = d => { S.statsRange = d.v; S._stagger = true; render(); };

/* ================= 5. 搜索结果：排序 / 只看无损 ================= */
const _srch = searchResults;
searchResults = () => _srch().replace(/<span class="chip">(<svg[\s\S]*?<\/svg>)综合排序<\/span><span class="chip">(<svg[\s\S]*?<\/svg>)只看无损<\/span>/, (m, a, b) => `<span class="chip" data-act="sheet" data-v="rSort">${a}${S.rSort}排序</span><span class="chip ${S.rLossless ? 'on' : ''}" data-act="rLossless">${b}只看无损</span>`);
SHEETS.rSort = () => ({ t:'排序', body:`<div class="grp">${[['综合', '平台默认的相关度'], ['最新', '发行时间从新到旧'], ['最热', '播放量从高到低'], ['时长', '从短到长']].map(([o, d]) => `<div class="it noic" data-act="rSortPick" data-v="${o}"><div class="lb"><b>${o}</b><small>${d}</small></div>${S.rSort === o ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>` });
ACT.rSortPick = d => { S.rSort = d.v; S.sheet = null; S._stagger = true; render(); };
ACT.rLossless = () => { S.rLossless = !S.rLossless; S._stagger = true; render(); toast(S.rLossless ? '只显示 SQ 及以上' : '显示全部音质', 'hd'); };

/* ================= 6. 音乐库：我喜欢的筛选 / 排序；本地的歌手 / 专辑 / 文件夹 ================= */
const _lib42 = PAGES.library.render;
PAGES.library.render = () => {
  let h = _lib42();
  if (S.libSeg === 'like') {
    h = h.replace(/<span class="chip on">全部<\/span><span class="chip">已下载<\/span><span class="chip">Hi-Res<\/span><span class="chip">(<svg[\s\S]*?<\/svg>)最近添加<\/span>/, (m, a) => `${['全部', '已下载', 'Hi-Res'].map(c => `<span class="chip ${S.likeChip === c ? 'on' : ''}" data-act="likeChip" data-v="${c}">${c}</span>`).join('')}<span class="chip" data-act="sheet" data-v="likeSortS">${a}${S.likeSort}</span>`);
    if (S.likeChip !== '全部') {
      // 按筛选重建列表：筛选胶囊行之后到分段内容结束之间整体替换
      const keep = S.likeChip === 'Hi-Res' ? id => SONGS[id].q === 'Hi-Res' || SONGS[id].q === 'Atmos' : id => id % 2 === 0;
      const mark = 'data-v="likeSortS">', a = h.indexOf(mark), start = h.indexOf('</div>', a) + 6, close = h.lastIndexOf('</div>');
      const ids = [...S.liked].filter(keep);
      if (a > 0) h = h.slice(0, start) + (ids.length ? ids.map(id => songRow(SONGS[id], { list:'like', heart:true })).join('') : `<div class="dv-emptydir">没有${S.likeChip}的歌</div>`) + h.slice(close);
    }
  }
  if (S.libSeg === 'local') {
    const chips = /<span class="chip on">歌曲<\/span><span class="chip">歌手<\/span><span class="chip">专辑<\/span><span class="chip">文件夹<\/span><\/div>/;
    const m = chips.exec(h);
    if (m) {
      const start = m.index, end = m.index + m[0].length, az = h.indexOf('<div class="az">'), close = h.lastIndexOf('</div>', az > 0 ? az : h.length);
      const nc = `${['歌曲', '歌手', '专辑', '文件夹'].map(c => `<span class="chip ${S.localView === c ? 'on' : ''}" data-act="localView" data-v="${c}">${c}</span>`).join('')}</div>`;
      let body = h.slice(end, close);
      if (S.localView === '歌手') body = [...new Set(SONGS.map(s => s.a))].slice(0, 10).map(a => { const x = SONGS.find(s => s.a === a); return `<div class="row" data-act="push" data-v="artist" data-id="${x.id}"><div class="cv" style="${coverStyle(x.h, 1)};border-radius:24px"></div><div class="tx"><div class="t">${a}</div><div class="s"><span>本地 ${SONGS.filter(s => s.a === a).length} 首</span></div></div><span style="color:var(--t3);padding-right:14px">${ic('right')}</span></div>`; }).join('');
      if (S.localView === '专辑') body = `<div class="dv-albums">${[...new Set(SONGS.map(s => s.al))].slice(0, 8).map((al, i) => { const x = SONGS.find(s => s.al === al); return `<div class="dv-alb" data-act="push" data-v="playlist" data-id="${i % 8}" style="--d:${i * 30}ms"><div class="cv" style="${coverStyle(x.h, x.v)}"></div><b>${al}</b><small>${x.a} · ${SONGS.filter(s => s.al === al).length} 首</small></div>`; }).join('')}</div>`;
      if (S.localView === '文件夹') body = `<div class="m card dv-list" style="margin-top:6px">${[['/Music', 86, '3.1 GB'], ['/Download', 24, '620 MB'], ['/Music/录音', 6, '48 MB'], ['/微信/音乐', 12, '92 MB']].map(([p, n, sz]) => `<div class="dv-row" data-act="toast" data-msg="打开 ${p}" data-icon="folder"><span class="dv-fi">${ic('folder')}</span><div class="dv-tx"><b>${p}</b><small><span>${n} 首 · ${sz}</span></small></div><span class="dv-go">${ic('right')}</span></div>`).join('')}</div>
        <div style="padding:12px var(--pad) 0"><button class="btn sec block" data-act="sheet" data-v="scanDirs">${ic('folder')}管理扫描目录</button></div>`;
      h = h.slice(0, start) + nc + body + h.slice(close);
    }
  }
  return h;
};
SHEETS.likeSortS = () => ({ t:'排序', body:`<div class="grp">${['最近添加', '歌名', '歌手', '专辑', '播放次数'].map(o => `<div class="it noic" data-act="likeSortPick" data-v="${o}"><div class="lb"><b>${o}</b></div>${S.likeSort === o ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>` });
SHEETS.scanDirs = () => ({ t:'扫描目录', body:`<div class="grp">${[['/Music', true], ['/Download', true], ['/Music/录音', false], ['/微信/音乐', true]].map(([p, on]) => `<div class="it"><div class="tile" style="background:${TILE.blue}">${ic('folder')}</div><div class="lb"><b>${p}</b></div><div class="sw ${on ? 'on' : ''}"></div></div>`).join('')}</div>
  ${group('', [item({ icon:'filter', color:'gray', label:'忽略 60 秒以下的文件', sub:'过滤通话录音和提示音', sw:'pitch' }), item({ icon:'plus', color:'green', label:'添加目录', act:'sheetToast', args:{ msg:'已打开系统文件夹选择', icon:'folder' } })])}` });
Object.assign(ACT, {
  likeChip: d => { S.likeChip = d.v; S._stagger = true; render(); }, likeSortPick: d => { S.likeSort = d.v; S.sheet = null; render(); },
  localView: d => { S.localView = d.v; S._stagger = true; render(); },
});

/* ================= 7. 设置里的「只弹 Toast」项 → 抽屉 / 弹窗 / 页面 ================= */
const FL_COLORS = ['#FFFFFF', '#F4D28A', '#7DF9FF', '#FF8FE0', '#5EE6A8'];
SHEETS.floatStyle = () => ({ t:'悬浮歌词样式', body:`<div class="fl-prev"><div class="fl-bar" style="--fs:${S.set.flFs}px;--op:${S.set.flOp / 100};--fc:${FL_COLORS[S.flColor]}"><span>${LYRICS[6].o}</span><small>${LYRICS[6].tr}</small></div></div>
  <div style="padding:0 var(--pad)">${slider('字号', 'flFs', 12, 28, 1, 'px')}${slider('背景不透明度', 'flOp', 0, 100, 5, '%')}</div>
  <div class="grp-t" style="padding-left:var(--pad)">文字颜色</div><div class="fl-colors">${FL_COLORS.map((c, i) => `<button class="${S.flColor === i ? 'on' : ''}" style="--c:${c}" data-act="flColor" data-v="${i}"></button>`).join('')}<button class="fl-acc ${S.flColor === -1 ? 'on' : ''}" data-act="flColor" data-v="-1">跟随主题色</button></div>
  ${group('', [item({ label:'显示翻译', sw:'trans' }), item({ label:'锁定后点击穿透', sub:'锁定时不能拖动，点击会传给下面的 App', sw:'floatLock' })])}` });
SHEETS.btOrder = () => ({ t:'推送给车机 / 蓝牙的内容', body:`<div class="grp">${[['仅歌词', '歌名栏显示当前歌词'], ['歌词 · 歌名', '第一行歌词，第二行歌名（推荐）'], ['歌名 · 歌词', '第一行歌名，第二行歌词']].map(([n, d], i) => `<div class="it noic" data-act="btOrder" data-v="${i}"><div class="lb"><b>${n}</b><small>${d}</small></div>${S.btOrder === i ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>
  <div class="m card bt-prev">${ic('car')}<div><b>${S.btOrder === 2 ? song().t : LYRICS[6].o}</b><small>${S.btOrder === 0 ? '' : S.btOrder === 2 ? LYRICS[6].o : song().t + ' · ' + song().a}</small></div></div>` });
SHEETS.lyrSrc = () => ({ t:'歌词来源优先级', sub:'按住右侧拖动', body:`<div class="ho-list">${[['内置', '歌曲所在平台的官方歌词'], ['平台', '其它平台同名歌曲的歌词'], ['本地', '同目录 .lrc 与文件内嵌歌词'], ['音源脚本', '脚本提供的歌词接口']].map(([n, d], i) => `<div class="ho-it"><div class="ho-tx"><b>${i + 1}. ${n}</b><small>${d}</small></div><span class="ho-h">${ic('drag')}</span></div>`).join('')}</div>
  <p class="hint" style="padding:8px var(--pad) 0">从上往下找，找到逐字歌词优先于普通歌词。</p>` });
SHEETS.dlNaming = () => { const pats = [['歌名 - 歌手', s => `${s.t} - ${s.a}`], ['歌手 - 歌名', s => `${s.a} - ${s.t}`], ['歌名', s => s.t], ['专辑/序号. 歌名', s => `${s.al}/01. ${s.t}`]];
  return { t:'文件命名', body:`<div class="grp">${pats.map(([n, f], i) => `<div class="it noic" data-act="dlName" data-v="${i}"><div class="lb"><b>${n}</b><small>${f(song())}.flac</small></div>${S.dlName === i ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>
  ${group('', [item({ label:'按歌手建子文件夹', sw:'dlCover' }), item({ label:'写入标签与封面', sub:'下载后把歌名、歌手、专辑、封面写进文件', sw:'dlLyric' })], '文件名里的 / \\ : * ? " < > | 会自动替换成全角字符。')}` }; };
SHEETS.profileEdit = () => ({ t:'编辑资料', body:`<div class="pe-av"><div class="avatar lg">栗</div><button class="chip" data-act="toast" data-msg="从相册选择 · 裁剪成正方形" data-icon="image">${ic('image')}更换头像</button></div>
  <div style="padding:0 var(--pad)"><div class="fld">${ic('user')}<input value="阿栗" maxlength="20"></div><p class="hint" style="padding:6px 2px 0">昵称 2–20 个字，30 天内可改 3 次</p>
  <div class="fld" style="margin-top:12px">${ic('edit')}<input placeholder="一句话介绍（选填）" value="夜里听歌的人"></div>
  <button class="btn pri block" style="margin-top:16px" data-act="sheetToast" data-msg="资料已保存" data-icon="check">保存</button></div>` });
SHEETS.accBackups = () => ({ t:'账号历史备份', sub:'保留最近 12 份', body:`<div class="grp">${[['今天 03:00', '自动 · iPhone 15', '1.2 MB'], ['昨天 03:00', '自动 · iPhone 15', '1.2 MB'], ['10-30 21:14', '手动 · 桌面端', '1.1 MB'], ['10-24 03:00', '自动 · iPhone 15', '1.1 MB']].map(([t, by, sz], i) => `<div class="it" data-act="accRestore" data-v="${i}"><div class="tile" style="background:${i ? TILE.gray : TILE.green}">${ic('cloud')}</div><div class="lb"><b>${t}</b><small>${by} · ${sz}</small></div><div class="val">恢复${ic('right')}</div></div>`).join('')}</div>
  <p class="hint" style="padding:0 var(--pad)">包含收藏、歌单、设置和音源脚本，不含音频文件。</p>` });
ACT.accRestore = d => { S.sheet = null; S.dlg = { i:+d.v, mode:'merge', acc:true }; S.dialog = 'davRestore'; render(); };
const _davRestore = FORM_DIALOGS.davRestore;
FORM_DIALOGS.davRestore = () => S.dlg.acc ? _davRestore().replace(/<p class="fd-s">[^<]*<\/p>/, `<p class="fd-s">${['今天 03:00', '昨天 03:00', '10-30 21:14', '10-24 03:00'][S.dlg.i || 0]} · 账号备份</p>`) : _davRestore();
FORM_DIALOGS.changePwd = () => { const st = S.pwdStep;
  if (st === 2) return `<div class="fd-load">${ic('check')}<b>密码已修改</b><small>其它设备会在下次刷新时要求重新登录</small></div><div class="fd-acts"><button class="btn pri" data-act="closeDialog">完成</button></div>`;
  return `<h3 class="fd-t">修改密码</h3><p class="fd-s">${st === 0 ? '先验证邮箱 ali@example.com' : '设置新密码'}</p>
  ${st === 0 ? `<div class="fld" style="margin-top:14px">${ic('key')}<input placeholder="6 位验证码"><button class="act" data-act="toast" data-msg="验证码已发送至邮箱" data-icon="mail">发送</button></div>`
    : `<div class="fld" style="margin-top:14px">${ic('lock')}<input type="password" placeholder="新密码（至少 8 位，含字母和数字）" value="Night2026"></div><div class="pw-meter"><i class="on"></i><i class="on"></i><i></i><span>中等</span></div><div class="fld" style="margin-top:10px">${ic('lock')}<input type="password" placeholder="再输一次"></div>
      ${group('', [item({ label:'退出其它所有设备', sub:'推荐：防止别人用旧密码继续登录', sw:'crash' })])}`}
  <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn pri" data-act="pwdNext">${st === 0 ? '下一步' : '确认修改'}</button></div>`; };
FORM_DIALOGS.changeEmail = () => `<h3 class="fd-t">更换邮箱</h3><p class="fd-s">当前 ali@example.com。新邮箱用于登录和找回密码。</p>
  <div class="fld" style="margin-top:14px">${ic('mail')}<input placeholder="新邮箱"></div>
  <div class="fld" style="margin-top:10px">${ic('key')}<input placeholder="新邮箱收到的验证码"><button class="act" data-act="toast" data-msg="验证码已发送到新邮箱" data-icon="mail">发送</button></div>
  <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn pri" data-act="closeDialogToast" data-msg="邮箱已更换">确认</button></div>`;
FORM_DIALOGS.platPhone = () => `<h3 class="fd-t">手机号登录</h3><p class="fd-s">${plat().n}会给这个号码发短信验证码</p>
  <div class="fld" style="margin-top:14px"><span class="cc42">+86</span><input placeholder="手机号" inputmode="tel"></div>
  <div class="fld" style="margin-top:10px">${ic('key')}<input placeholder="短信验证码"><button class="act" data-act="toast" data-msg="验证码已发送" data-icon="phone">获取</button></div>
  <p class="fd-s" style="margin-top:10px">${ic('shield')} 登录凭据只保存在本机，用于获取每日推荐和你的歌单。</p>
  <div class="fd-acts"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn pri" data-act="closeDialogToast" data-msg="已登录${plat().n}">登录</button></div>`;
FORM_DIALOGS.platCookie = () => `<h3 class="fd-t">Cookie 登录</h3><p class="fd-s">在电脑浏览器登录${plat().n}网页版后，从开发者工具复制 Cookie 粘贴到这里</p>
  <textarea class="ta42" placeholder="MUSIC_U=…; __csrf=…"></textarea>
  <div class="fd-det mute">${ic('info')}只需要包含登录态的那几项；粘贴后会立刻校验是否有效</div>
  <div class="fd-acts three"><button class="btn sec" data-act="closeDialog">取消</button><button class="btn sec" data-act="toast" data-msg="已粘贴" data-icon="paste">粘贴</button><button class="btn pri" data-act="closeDialogToast" data-msg="Cookie 有效 · 已登录">校验并登录</button></div>`;
Object.assign(ACT, {
  flColor: d => { S.flColor = +d.v; render(); }, btOrder: d => { S.btOrder = +d.v; render(); }, dlName: d => { S.dlName = +d.v; render(); },
  pwdNext: () => { S.pwdStep++; render(); }, closeDialogToast: d => { S.dialog = null; render(); toast(d.msg, 'check'); },
  openPwd: () => { S.pwdStep = 0; S.dialog = 'changePwd'; render(); },
});
// 会员权益
PAGES.perks = { render:() => `${appBar('会员权益')}
  <div class="m card pk-hero"><div class="pk-c">${ic('crown')}</div><b>已激活 · Sponsor</b><small>感谢支持。下面的功能你都可以用。</small></div>
  <div class="m card pk-tbl"><div class="pk-h"><span></span><b>免费</b><b class="acc">赞助</b></div>${[['在线播放与收藏', 1, 1], ['平台登录与每日推荐', 1, 1], ['15 套播放器皮肤', '11 套', 1], ['多端实时同步', 0, 1], ['账号云备份', 0, 1], ['云端听歌统计', 0, 1], ['Hi-Res 下载', 0, 1], ['优先体验新功能', 0, 1]].map(([n, a, b]) => `<div class="pk-r"><span>${n}</span>${[a, b].map(v => `<i class="${v === 1 ? 'y' : v === 0 ? 'n' : 't'}">${v === 1 ? ic('check') : v === 0 ? '—' : v}</i>`).join('')}</div>`).join('')}</div>
  <div style="padding:16px var(--pad) 0"><button class="btn sec block" data-act="sheet" data-v="activate">${ic('key')}输入激活码 / 升级码</button></div>
  <p class="hint" style="padding:10px var(--pad) 0">激活码通过官方渠道获得；升级码可以把赞助等级提升一级。</p>` };
// 使用须知（已登录后从「关于」打开的只读版本）
PAGES.terms = { render:() => `${appBar('使用须知')}<div class="m card terms42">${[['shield', '隐私', '聆听记录只用于生成每日混音和统计，可以随时在设置里清除。'], ['layers', '音源', '解析脚本由你自行添加并对其合法性负责，Lyra 不提供、不存储任何音频内容。'], ['cloud', '同步', '收藏与歌单可以同步到你的账号或自建 WebDAV，同步内容不含音频文件。'], ['info', '版本', '如果当前版本停止服务，App 会提示你更新到可用的版本。']].map(([i, t, d]) => `<div><span>${ic(i)}</span><b>${t}</b><p>${d}</p></div>`).join('')}</div>
  <p class="hint" style="padding:12px var(--pad) 0">你在 2026-10-02 同意了本须知（v3）。须知更新时会在启动时再次提示。</p>` };

/* ---------- 把占位 Toast 换成真正的去处 ---------- */
const ITEM_REMAP = [
  ['可调整字号、颜色和背景透明度', 'data-act="sheet" data-v="floatStyle"'], ['可选：仅歌词 / 歌词·歌名 / 歌名·歌词', 'data-act="sheet" data-v="btOrder"'],
  ['长按拖动调整顺序', 'data-act="sheet" data-v="lyrSrc"'], ['可选顺序与分隔符，非法字符自动替换', 'data-act="sheet" data-v="dlNaming"'],
  ['编辑资料', 'data-act="sheet" data-v="profileEdit"'], ['验证码已发送至邮箱', 'data-act="openPwd"'],
  ['Hi-Res 下载 · 粒子皮肤 · 云同步 …', 'data-act="push" data-v="perks"'], ['选择一份备份进行恢复', 'data-act="sheet" data-v="accBackups"'],
  ['发送验证码', 'data-act="openDlg" data-v="platPhone"'], ['粘贴 Cookie 字符串', 'data-act="openDlg" data-v="platCookie"'], ['已打开使用须知', 'data-act="push" data-v="terms"'],
];
const esc42 = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const _bs42 = buildScreen;
buildScreen = function () {
  let h = _bs42();
  for (const [msg, to] of ITEM_REMAP) h = h.replace(new RegExp(`(<div class="it[^"]*" )data-act="toast" data-msg="${esc42(msg)}" data-icon="[^"]*"`, 'g'), `$1${to}`);
  h = h.replace(/(<div class="it[^"]*")\s*>(\s*<div class="tile"[^>]*>(?:(?!<\/div>)[\s\S])*<\/div>\s*<div class="lb"><b>邮箱<\/b>)/, '$1 data-act="openDlg" data-v="changeEmail">$2');
  h = h.replace(/data-act="toast" data-msg="播放 MV：([^"]*)" data-icon="video"/g, (m, t) => { const s = SONGS.find(x => t.startsWith(x.t)); return `data-act="push" data-v="mvPlay" data-id="${s ? s.id : 3}"`; });
  h = h.replace(/data-act="toast" data-msg="已保存为歌单" data-icon="plus"/g, 'data-act="openDlg" data-v="newPlaylist"');
  return h;
};

/* ---------------- 目录（main.js 读取） ---------------- */
const at = (id, params, fn) => () => { S.stack = [{ id, params:params || {} }]; fn && fn(); };
const FIX_JUMPS = [
  ['歌单广场', at('plSquare')], ['歌单广场 · 分类（深夜）', at('plSquare', {}, () => { S.sqCat = '深夜'; })], ['歌单 · 全部分类', at('plSquare', {}, () => { S.sheet = { v:'plCats' }; })],
  ['新碟上架', at('newAlbums')], ['排行榜 · 官方', at('charts')], ['排行榜 · 特色', at('charts', {}, () => { S.chartTab = '特色'; })], ['排行榜 · 全球', at('charts', {}, () => { S.chartTab = '全球'; })],
  ['MV 排行', at('mvRank')], ['推荐视频', at('videos')], ['MV 播放', at('mvPlay', { id:3 })], ['MV 播放 · 画质与设置', at('mvPlay', { id:3 }, () => { S.sheet = { v:'mvQuality' }; })],
  ['曲风偏好', () => { S.sheet = { v:'genrePref' }; }],
  ['歌单详情 · 排序', at('playlist', { id:0 }, () => { S.sheet = { v:'plSortS' }; })], ['歌单详情 · 多选', at('playlist', { id:0 }, () => { S.plMulti = true; S.plSel = new Set([2, 5]); })],
  ['听歌统计 · 近 30 天', at('stats', {}, () => { S.statsRange = '近 30 天'; })],
  ['搜索结果 · 排序', () => { S.tab = 'search'; S.searchQ = '雾港'; S.searchDone = true; S.rType = '歌曲'; S.sheet = { v:'rSort' }; }],
  ['音乐库 · 我喜欢 · Hi-Res', () => { S.tab = 'library'; S.libSeg = 'like'; S.likeChip = 'Hi-Res'; }], ['音乐库 · 我喜欢 · 排序', () => { S.tab = 'library'; S.libSeg = 'like'; S.sheet = { v:'likeSortS' }; }],
  ['音乐库 · 本地 · 专辑', () => { S.tab = 'library'; S.libSeg = 'local'; S.localView = '专辑'; }], ['音乐库 · 本地 · 文件夹', () => { S.tab = 'library'; S.libSeg = 'local'; S.localView = '文件夹'; }], ['本地 · 扫描目录', () => { S.tab = 'library'; S.libSeg = 'local'; S.localView = '文件夹'; S.sheet = { v:'scanDirs' }; }],
  ['系统歌词 · 悬浮样式', at('syslyrics', {}, () => { S.sheet = { v:'floatStyle' }; })], ['系统歌词 · 车机推送内容', at('syslyrics', {}, () => { S.sheet = { v:'btOrder' }; })], ['歌词 · 来源优先级', at('lyrics', {}, () => { S.sheet = { v:'lyrSrc' }; })],
  ['下载 · 文件命名', at('download', {}, () => { S.sheet = { v:'dlNaming' }; })],
  ['账号中心 · 编辑资料', at('account', {}, () => { S.sheet = { v:'profileEdit' }; })], ['账号中心 · 修改密码', at('account', {}, () => { S.pwdStep = 0; S.dialog = 'changePwd'; })], ['账号中心 · 设置新密码', at('account', {}, () => { S.pwdStep = 1; S.dialog = 'changePwd'; })], ['账号中心 · 更换邮箱', at('account', {}, () => { S.dlg = {}; S.dialog = 'changeEmail'; })], ['会员权益', at('perks')],
  ['账号备份 · 历史', at('backup', {}, () => { S.sheet = { v:'accBackups' }; })], ['账号备份 · 恢复', at('backup', {}, () => { S.dlg = { i:0, mode:'merge', acc:true }; S.dialog = 'davRestore'; })],
  ['平台账号 · 手机号登录', at('accounts3p', {}, () => { S.dlg = {}; S.dialog = 'platPhone'; })], ['平台账号 · Cookie 登录', at('accounts3p', {}, () => { S.dlg = {}; S.dialog = 'platCookie'; })],
  ['使用须知（只读）', at('terms')],
  ['播放队列 · 存为歌单', () => { S.playerOpen = true; S.skin = 'vinyl'; S.dlg = { val:'' }; S.dialog = 'newPlaylist'; }],
];

/* ================= 8. 登录设备：多选批量移除（对应 App #24） ================= */
const DEVICES = [['phone', '阿栗的 iPhone', '本机 · iOS 19.1 · 上海', true], ['grid', 'Lyra 桌面端', 'Windows 11 · 2 小时前', false], ['tv', '客厅电视', 'Android TV · 昨天', false], ['car', '车机', 'Android Automotive · 3 天前', false], ['phone', '旧手机', 'Android 14 · 10-12 在线', false]];
PAGES.devices = { render:() => {
  const sel = S.devSel, on = !!sel;
  return `${appBar('登录设备', { right:`<button class="ib" data-act="devMulti">${ic(on ? 'close' : 'check')}</button>` })}
  <p class="hint" style="padding:0 var(--pad) 12px">${on ? '勾选要移除的设备（本机不可移除），点底部按钮批量移除。' : `最多同时登录 10 台设备，当前 ${DEVICES.length} 台。移除后该设备需要重新登录。右上角可进入多选。`}</p>
  <div class="grp">${DEVICES.map(([i, n, d, me], k) => `<div class="it ${on && !me ? 'pick42' : ''}" ${on && !me ? `data-act="devPick" data-v="${k}"` : ''}><div class="tile" style="background:${me ? TILE.green : TILE.gray}">${ic(i)}</div><div class="lb"><b>${n}</b><small>${d}</small></div>
    ${me ? '<span class="badge acc">本机</span>' : on ? `<span class="ck42 ${sel.has(k) ? 'on' : ''}">${sel.has(k) ? ic('check') : ''}</span>` : `<button class="btn danger sm" data-act="devOne" data-v="${k}">移除</button>`}</div>`).join('')}</div>
  ${on && sel.size ? `<div class="devbar"><button class="btn danger block" data-act="dialog" data-v="devBatch">${ic('logout')}移除所选（${sel.size}）</button></div>` : ''}`;
} };
DIALOGS.devBatch = { i:'logout', t:'移除所选设备？', p:'被移除的设备需要重新登录。本机不会被移除。', a:[['取消', 'closeDialog', 'sec'], ['移除', 'devBatchGo', 'danger']] };
Object.assign(ACT, {
  devMulti: () => { S.devSel = S.devSel ? null : new Set(); render(); },
  devPick: d => { const k = +d.v; S.devSel.has(k) ? S.devSel.delete(k) : S.devSel.add(k); render(); },
  devOne: d => { S.dialog = 'devOne'; DIALOGS.devOne = { i:'logout', t:`移除「${DEVICES[+d.v][1]}」？`, p:'该设备需要重新登录。', a:[['取消', 'closeDialog', 'sec'], ['移除', 'devBatchGo', 'danger']] }; render(); },
  devBatchGo: () => { const n = S.devSel ? S.devSel.size : 1; S.dialog = null; S.devSel = null; render(); toast(`已移除 ${n} 台设备`, 'logout'); },
});
const _fixReset2 = fixReset;
fixReset = function () { _fixReset2(); S.devSel = null; };

/* ================= 9. 发现 · 快捷入口：每日混音 → 歌单广场、排行榜 → 完整榜单页（对应 App #21） ================= */
MODS.quick = () => `<div class="qk">
    <button data-act="push" data-v="plSquare"><span class="ic">${ic('grid')}</span>歌单广场</button>
    <button data-act="playAll" data-list="hot" data-shuffle="1"><span class="ic">${ic('wave')}</span>私人电台</button>
    <button data-act="openScan" data-v="match"><span class="ic">${ic('mic')}</span>听歌识曲</button>
    <button data-act="push" data-v="charts"><span class="ic">${ic('chart')}</span>排行榜</button></div>`;
HOME_MOD_N.quick = ['快捷入口', '歌单广场、私人电台、识曲、排行榜'];
FIX_JUMPS.push(['登录设备 · 多选', at('devices', {}, () => { S.devSel = new Set([2, 4]); })], ['登录设备 · 批量移除确认', at('devices', {}, () => { S.devSel = new Set([2, 4]); S.dialog = 'devBatch'; })]);
