/* 全屏播放器（9 套皮肤）+ Bottom Sheet + 对话框。 */
const flowBlobs = s => [0, 50, 300].map((d, i) => `<i style="background:radial-gradient(circle,hsl(${(s.h + d) % 360} 75% ${[58, 45, 52][i]}%),transparent 65%)"></i>`).join('');
function playerBg(s, forcePhoto) {
  const shade = S.tone === 'dark' ? S.bright / 100 : S.bright / 300;
  if (forcePhoto) return '';
  const inner = S.bg === 'blur' ? `<div class="blur" style="${coverStyle(s.h, s.v)}"></div>` : `<div class="flow">${flowBlobs(s)}</div>`;
  return `<div class="pbg ${S.bg === 'static' ? 'static' : ''} ${S.tone === 'light' ? 'lightTone' : ''}" style="--shade:${shade}">${inner}<div class="shade"></div></div>`;
}
const MODE_IC = { loop:'repeat', one:'repeat1', shuffle:'shuffle', order:'order' };
function topBar() {
  return `<div class="ptop"><button class="ib" data-act="closePlayer">${ic('down')}</button>
    <div class="mid"><small>${S.castDev ? '正在投放 · ' + S.castDev : '正在播放'}</small><b>${S.queueName}</b></div>
    <button class="ib" data-act="sheet" data-v="more" data-id="${S.cur}" data-ctx="player">${ic('more')}</button></div>`;
}
function info(s) {
  return `<div class="pinfo"><div class="tx"><div class="t">${marquee(s.t, 12)}</div><div class="a"><span>${s.a}</span><b class="qb" data-act="sheet" data-v="quality">${S.quality}</b></div></div>
    <button class="ib heart ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}</button></div>`;
}
function progress(s) {
  const p = S.pos / s.dur * 100;
  return `<div class="prog"><div class="tr"><div class="buf"></div><div class="fill" data-b="fill" style="width:${p}%"></div><div class="th" data-b="thumb" style="left:${p}%"></div></div>
    <div class="tm"><span data-b="pos">${fmt(S.pos)}</span><span>-${fmt(s.dur - S.pos)}</span></div></div>`;
}
function controls() {
  return `<div class="ctl"><button class="ib md ${S.mode !== 'order' ? 'on' : ''}" data-act="mode">${ic(MODE_IC[S.mode])}</button>
    <button class="ib sk" data-act="prev">${ic('prev')}</button>
    <button class="big" data-act="toggle">${ic(S.playing ? 'pause' : 'play')}</button>
    <button class="ib sk" data-act="next">${ic('next')}</button>
    <button class="ib md" data-act="sheet" data-v="queue">${ic('queue')}</button></div>`;
}
function aux() {
  return `<div class="aux">
    <button class="ib ${S.lyricMode ? 'on' : ''}" data-act="lyricMode" title="歌词">${ic('quote')}</button>
    <button class="ib ${S.castDev ? 'on' : ''}" data-act="sheet" data-v="cast">${ic('cast')}</button>
    <button class="ib ${S.timer ? 'on' : ''}" data-act="sheet" data-v="timer">${ic('moon')}</button>
    <button class="ib ${S.eqOn ? 'on' : ''}" data-act="sheet" data-v="eq">${ic('sliders')}</button>
    <button class="ib" data-act="sheet" data-v="skin">${ic('palette')}</button></div>`;
}
/* 把一行切成"字/词"片段，按字符数分配时间占比（有逐字时间轴时直接用时间轴） */
function wordSpans(text) {
  const toks = text.match(/[A-Za-z0-9'’]+|\s+|./g) || [];
  const total = toks.reduce((n, t) => n + (t.trim() ? t.length : 0), 0) || 1; let acc = 0;
  return toks.map(t => { if (!t.trim()) return t; const a = acc / total; acc += t.length; return `<span class="wd" data-a="${a.toFixed(3)}" data-b="${(acc / total).toFixed(3)}">${t}</span>`; }).join('');
}
function lyricList(o = {}) {
  const k = lyrIdx();
  return `<div class="lyr ${S.set.blur && !o.stagger ? 'blurOn' : ''} ${S.set.glow ? 'glowOn' : ''} ${o.cls || ''}" data-anchor="${o.anchor || .36}" style="--lfs:${o.fs || S.set.lfs}px;--ltfs:${S.set.ltfs}px">
    <div class="lyr-in">${LYRICS.map((l, i) => `<div class="ll ${i === k ? 'on' : ''}" data-act="seekLine" data-i="${i}" style="padding:${S.set.lgap}px 0;--wi:${i}">${S.set.roma ? `<span class="ro">${['cheng shi', 'wo ba er ji', 'yun ceng hen di', 'feng cong bei fang'][i % 4]} …</span>` : ''}${o.words ? `<span class="wds">${wordSpans(l.o)}</span>` : `<span class="w">${l.o}</span>`}${S.set.trans && !o.noTr ? `<span class="tr">${l.tr}</span>` : ''}</div>`).join('')}</div>
    <button class="back" data-act="lyrBack">${ic('up')}回到当前</button></div>`;
}
const lines3 = () => { const k = lyrIdx(), g = i => LYRICS[i] ? LYRICS[i].o : ''; return `<div class="lines3"><div>${g(k - 1)}</div><div class="c">${g(k) || '♪'}</div><div>${g(k + 1)}</div></div>`; };

function renderPlayer() {
  const s = song(), sk = S.skin;
  let mid = '', bg = playerBg(s), bottom = progress(s) + controls() + aux();
  if (typeof SKIN_RENDER !== 'undefined' && SKIN_RENDER[sk]) return SKIN_RENDER[sk](s);
  if (sk === 'spring') return renderAM(s, S.amWave === 'wave' ? 'flow' : 'spring');
  if (sk === 'cover') {
    mid = S.lyricMode
      ? `<div class="mini-head" style="display:flex">${cover(s)}<div style="flex:1;min-width:0"><div class="t">${s.t}</div><div class="a">${s.a}</div></div><button class="ib heart ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}</button></div>${lyricList()}`
      : `<div class="art" data-act="lyricMode">${cover(s, '', 0, 'data-hero')}</div>${info(s)}`;
  } else if (sk === 'vinyl') {
    mid = `<div class="vinyl-wrap" data-act="lyricMode"><div class="arm"><i></i></div><div class="vinyl" data-hero style="${S.set.vinylSpin ? '' : 'animation:none'}">${cover(s)}<div class="hole"></div></div></div>${info(s)}${lines3()}`;
  } else if (sk === 'karaoke') {
    mid = `<div class="mini-head" style="display:flex">${cover(s)}<div style="flex:1;min-width:0"><div class="t">${s.t}</div><div class="a">${s.a} · <b class="qb" style="color:var(--accent)">${S.quality}</b></div></div><button class="ib heart ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}</button></div>${lyricList({ fs:30, anchor:.3 })}`;
    bottom = progress(s) + controls();
  } else if (sk === 'immersive') {
    bg = `<div class="pbg"><div class="blur" style="${coverStyle(s.h, s.v)};filter:blur(40px) saturate(1.6) brightness(.8)"></div><div class="shade" style="--shade:.3"></div></div>`;
    mid = `<div class="art" data-act="lyricMode">${cover(s, '', 0, 'data-hero')}</div>${info(s)}${lines3()}`;
  } else if (sk === 'minimal') {
    bg = '';
    mid = `<div class="mini-head">${cover(s)}<div style="flex:1;min-width:0"><div class="t" style="font-size:17px">${s.t}</div><div class="a">${s.a}</div><div class="a" style="font-size:12px;color:var(--pt3)">${s.al} · ${S.quality}</div></div></div>${lyricList({ fs:17, anchor:.3, noTr:true })}`;
    bottom = progress(s) + controls();
  } else if (sk === 'pulse') {
    mid = `<div class="pulse"><i class="ring"></i><i class="ring"></i><i class="ring"></i>${cover(s, '', 0, 'data-hero')}</div><div class="spec">${'<i></i>'.repeat(24)}</div>${info(s)}${lines3()}`;
  } else if (sk === 'poster') {
    bg = `<div class="photo" style="${coverStyle(s.h, s.v)};position:absolute;inset:0"></div><div style="position:absolute;inset:0;background:linear-gradient(rgba(0,0,0,.25) 0,rgba(0,0,0,.18) 25%,rgba(0,0,0,.45) 45%,rgba(0,0,0,.86) 78%)"></div>`;
    mid = `<div style="flex:1;min-height:0;display:flex;flex-direction:column;justify-content:flex-end">${lyricList({ fs:34, anchor:.62, noTr:true })}</div>
      <div style="padding:0 28px;font-size:13px;color:var(--pt2)">${s.t} — ${s.a}</div>`;
    bottom = progress(s) + controls();
  } else if (sk === 'stage') {
    bg = `<div class="pbg"><div class="flow">${flowBlobs(s)}</div><div class="shade" style="--shade:.72"></div></div>`;
    mid = `<div class="stage-l">${stageHTML(lyrIdx())}</div>`;
    bottom = `<div class="hidebar">${progress(s)}${controls()}</div>`;
  } else if (sk === 'particles') {
    bg = `<div class="pbg" style="background:#05060a"></div><canvas class="fxc" data-fx="${S.particle}"></canvas>`;
    mid = `<div style="flex:1"></div>${lines3()}<div class="chips">${[['galaxy', '星系'], ['disk', '事件视界'], ['globe', '全息地球'], ['gyro', '陀螺核心']].map(([k, n]) => `<button class="chip ${S.particle === k ? 'on' : ''}" data-act="particle" data-v="${k}">${n}</button>`).join('')}</div>${info(s)}`;
  }
  return `<div class="player ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'}">${bg}
    <div class="pw sk-${sk} ${S.lyricMode && sk === 'cover' ? 'lyr-mode' : ''}" ${sk === 'stage' ? 'onclick="this.classList.toggle(\'reveal\')"' : ''}>${topBar()}<div class="pmid">${mid}</div>${bottom}</div></div>`;
}

/* ================= Bottom Sheets ================= */
const SHEETS = {
  queue: () => ({ t:'播放队列', sub:`${S.queue.length} 首`, dark:true, body:`
    <div style="display:flex;gap:8px;padding:0 var(--pad) 10px"><button class="chip on" data-act="mode">${ic(MODE_IC[S.mode])}${{ loop:'列表循环', one:'单曲循环', shuffle:'随机', order:'顺序' }[S.mode]}</button><button class="chip" data-act="toast" data-msg="已保存为歌单" data-icon="plus">${ic('plus')}存为歌单</button><button class="chip" data-act="sheetToast" data-msg="已清空队列" data-icon="trash">${ic('trash')}清空</button></div>
    ${S.queue.map(id => songRow(SONGS[id], { tail:`<span class="ib" style="color:var(--t3);cursor:grab">${ic('drag')}</span>` })).join('')}` }),
  more: () => { const s = SONGS[S.sheet.id], ctx = S.sheet.ctx; return { t:'', dark:S.playerOpen, head:`<div style="display:flex;gap:12px;align-items:center;padding:4px var(--pad) 14px">${cover(s, '', 56)}<div style="flex:1;min-width:0"><b style="font-size:16px">${s.t}</b><div style="font-size:12.5px;color:var(--t2);margin-top:3px">${s.a} · ${s.al} · ${s.q}</div></div><button class="ib heart ${S.liked.has(s.id) ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(S.liked.has(s.id) ? 'heartf' : 'heart')}</button></div>`, body:`
    <div class="qk" style="padding-top:0;grid-template-columns:repeat(4,1fr);row-gap:16px">
      ${[['next', '下一首播放', '已添加到下一首'], ['plus', '加入歌单', ''], ['download', '下载', '已加入下载队列'], ['share', '分享口令', '']].map(([i, n, m]) => `<button ${m ? `data-act="sheetToast" data-msg="${m}" data-icon="${i}"` : i === 'plus' ? 'data-act="sheet" data-v="addTo"' : 'data-act="sheet" data-v="shareCode"'}><span class="ic">${ic(i)}</span>${n}</button>`).join('')}
      ${[['quote', '歌词分享', 'shareCard'], ['hd', '音质', 'quality'], ['speed', '倍速', 'speed'], ['cast', '投放', 'cast']].map(([i, n, v]) => `<button data-act="sheet" data-v="${v}"><span class="ic">${ic(i)}</span>${n}</button>`).join('')}</div>
    <div style="height:12px"></div>
    ${group('', [item({ icon:'album', color:'violet', label:'查看专辑', val:s.al, act:'push', args:{ v:'playlist', id:s.h % 8 } }), item({ icon:'user', color:'blue', label:'查看歌手', val:s.a, act:'push', args:{ v:'artist', id:s.id } }), item({ icon:'code', color:'gray', label:'播放链路', act:'sheet', args:{ v:'trace' } }),
      ...(ctx === 'daily' ? [item({ icon:'close', color:'red', label:'不感兴趣', sub:'减少推荐相似歌曲', act:'sheetToast', args:{ msg:'已减少此类推荐', icon:'check' } })] : []),
      ...(ctx === 'local' ? [item({ icon:'trash', color:'red', label:'从设备删除', danger:true, act:'sheetToast', args:{ msg:'已删除文件', icon:'trash' } })] : [])])}` }; },
  quality: () => ({ t:'音质', sub:'当前歌曲最高支持 ' + song().q, dark:S.playerOpen, body:`${group('', QUALITIES.map(q => { const ok = ['128k', 'HQ', 'SQ', 'Hi-Res'].includes(q.k) ? QUALITIES.findIndex(x => x.k === q.k) <= QUALITIES.findIndex(x => x.k === (song().q === 'Atmos' ? 'Hi-Res' : song().q)) || song().q === 'Atmos' : song().q === 'Atmos';
      return `<div class="it noic" data-act="${ok ? 'quality' : 'toast'}" data-v="${q.k}" data-msg="当前歌曲不支持 ${q.k}" data-icon="info" style="${ok ? '' : 'opacity:.4'}"><div class="lb"><b>${q.n} <span class="qb" style="margin-left:6px">${q.k}</span></b><small>${q.d}</small></div>${S.quality === q.k ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`; }))}
    ${group('', [item({ label:'不可用时自动降级', sw:'allowDown' })])}` }),
  timer: () => ({ t:'睡眠定时', sub:S.timer ? `${S.timer} 分钟后停止` : '', dark:S.playerOpen, body:`
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;padding:0 var(--pad) 16px">${[0, 15, 30, 45, 60, 90].map(m => `<button class="chip ${S.timer === m ? 'on' : ''}" style="height:52px;justify-content:center;font-size:15px" data-act="timer" data-v="${m}">${m ? m + ' 分钟' : '关闭'}</button>`).join('')}</div>
    ${group('', [item({ label:'播完当前歌曲再停止', sw:'finishSong' }), item({ label:'停止时淡出音量', sub:'最后 30 秒逐渐变小', sw:'fade' })])}` }),
  speed: () => ({ t:'播放速度', dark:S.playerOpen, body:`
    <div style="text-align:center;font:750 44px var(--font-num);padding:6px 0 4px"><output data-out="speed">${S.speed.toFixed(2)}×</output></div>
    <div class="sl" style="padding:0 var(--pad) 10px"><input type="range" min=".5" max="2" step=".05" value="${S.speed}" data-st="speed" style="--v:${(S.speed - .5) / 1.5 * 100}%"></div>
    <div class="chips" style="justify-content:center;padding-bottom:16px">${[.75, 1, 1.25, 1.5, 2].map(v => `<button class="chip ${S.speed === v ? 'on' : ''}" data-act="speed" data-v="${v}">${v}×</button>`).join('')}</div>
    ${group('', [item({ label:'保持音调', sub:'变速不变调', sw:'pitch' })])}` }),
  cast: () => ({ t:'投放到设备', dark:S.playerOpen, body:`
    <div class="scanl" style="margin-bottom:12px"></div>
    ${group('附近的设备', [['tv', '客厅电视', 'DLNA · Lyra TV'], ['volume', '书房音箱', 'DLNA · 上次使用 3 天前'], ['car', '我的车', '蓝牙 · 已配对']].map(([i, n, d]) => `<div class="it" data-act="cast" data-v="${n}"><div class="tile" style="background:${S.castDev === n ? 'var(--accent)' : TILE.gray};color:${S.castDev === n ? 'var(--accent-ink)' : '#fff'}">${ic(i)}</div><div class="lb"><b>${n}</b><small>${d}</small></div>${S.castDev === n ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`))}
    ${S.castDev ? `<div style="padding:0 var(--pad)"><button class="btn danger block" data-act="cast" data-v="">断开 ${S.castDev}</button></div>` : '<p class="hint">没找到设备？确认手机和设备在同一 Wi-Fi 下</p>'}` }),
  skin: () => ({ t:'播放器皮肤', dark:true, body:`
    <div class="opt-grid">${SKINS.map(k => `<button class="${S.skin === k.id ? 'on' : ''}" data-act="skin" data-v="${k.id}"><div class="pv" style="background:#0B0C12">${skinThumb(k.id)}</div>${k.n}</button>`).join('')}</div>
    <p class="hint" style="padding:0 var(--pad) 10px">${SKINS.find(k => k.id === S.skin).d}</p>
    <div class="grp-t">背景</div><div style="padding:0 0 12px">${seg(['模糊封面', '静态流光', '动态流光'], { blur:'模糊封面', static:'静态流光', flow:'动态流光' }[S.bg], 'bgCN')}</div>
    <div style="padding:0 0 4px">${seg(['暗色', '亮色'], S.tone === 'dark' ? '暗色' : '亮色', 'toneCN')}</div>
    <div class="sl" style="padding:12px var(--pad)"><label>压暗程度</label><input type="range" min="0" max="80" step="1" value="${S.bright}" data-st="bright" data-unit="%" style="--v:${S.bright / .8}%"><output data-out="bright">${S.bright}%</output></div>` }),
  lyricq: () => ({ t:'歌词快调', dark:true, body:`
    ${group('', [slider('字号', 'lfs', 16, 40, 1, 'px'), `<div class="it noic"><div class="lb"><b>时间偏移</b><small>正值 = 提前</small></div><button class="chip" data-act="loff" data-v="-0.5">−0.5s</button><b style="font-family:var(--font-num);width:52px;text-align:center">${S.set.loff > 0 ? '+' : ''}${S.set.loff.toFixed(1)}s</b><button class="chip" data-act="loff" data-v="0.5">+0.5s</button></div>`, item({ label:'显示翻译', sw:'trans' }), item({ label:'非当前行模糊', sw:'blur' })])}
    <div style="padding:0 var(--pad)"><button class="btn sec block" data-act="push" data-v="lyrics">全部歌词设置</button></div>` }),
  eq: () => ({ t:'均衡器', dark:S.playerOpen, right:`<div class="sw ${S.eqOn ? 'on' : ''}" data-act="eqOn" style="margin-right:10px"></div>`, body:`
    <div class="chips" style="padding-bottom:16px">${[...Object.keys(EQ_PRESETS), ...(S.eqPreset === '自定义' ? ['自定义'] : [])].map(n => `<button class="chip ${S.eqPreset === n ? 'on' : ''}" ${n === '自定义' ? '' : `data-act="eqPreset" data-v="${n}"`}>${n}</button>`).join('')}</div>
    <div style="${S.eqOn ? '' : 'opacity:.4;pointer-events:none'}">${eqHTML()}</div>
    <p class="hint" style="padding:14px var(--pad) 0;text-align:center">拖动圆点调整各频段（±12 dB）</p>` }),
  shareCard: () => { const s = song(), k = Math.max(0, lyrIdx()); return { t:'歌词分享', dark:true, body:`
    <div class="m" style="border-radius:24px;overflow:hidden;position:relative;height:360px;color:#fff">
      <div style="position:absolute;inset:0;${coverStyle(s.h, s.v)}"></div><div style="position:absolute;inset:0;background:linear-gradient(rgba(0,0,0,.1),rgba(0,0,0,.75))"></div>
      <div style="position:absolute;left:22px;right:22px;bottom:22px"><div style="font-size:40px;line-height:1;opacity:.6">“</div>
        ${[k, k + 1].map(i => `<div style="font-size:22px;font-weight:800;line-height:1.4">${LYRICS[i % LYRICS.length].o}</div>`).join('')}
        <div style="display:flex;align-items:center;gap:10px;margin-top:18px">${cover(s, '', 36)}<div style="flex:1;font-size:12px;opacity:.85">${s.t}<br>${s.a}</div>${appIcon(30)}</div></div></div>
    <div style="display:flex;gap:10px;padding:16px var(--pad) 0"><button class="btn sec" style="flex:1" data-act="sheetToast" data-msg="已保存到相册" data-icon="download">${ic('download')}保存图片</button><button class="btn pri" style="flex:1" data-act="sheetToast" data-msg="已打开系统分享" data-icon="share">${ic('share')}分享</button></div>` }; },
  shareCode: () => ({ t:'分享口令', dark:S.playerOpen, body:`
    <div class="m card" style="padding:18px;text-align:center"><div style="font-size:13px;color:var(--t2)">好友复制后打开 Lyra 即可播放</div>
      <div style="margin-top:12px;padding:14px;border-radius:14px;background:var(--s2);font:600 15px var(--font-num);color:var(--accent-text);word-break:break-all">【Lyra歌曲·1·Gx7Lq2…k2Q】${song().t}</div></div>
    <div style="display:flex;gap:10px;padding:16px var(--pad) 0"><button class="btn pri" style="flex:1" data-act="sheetToast" data-msg="口令已复制" data-icon="copy">${ic('copy')}复制口令</button><button class="btn sec" style="flex:1" data-act="sheet" data-v="shareCard">${ic('quote')}生成歌词卡</button></div>` }),
  trace: () => ({ t:'播放链路', sub:song().t, dark:S.playerOpen, body:`<div style="padding:0 var(--pad)">${[['ok', '00:00.000', '脚本源 · A', '请求 Hi-Res', '失败：资源不存在'], ['warn', '00:00.312', '脚本源 · A', '降级到 SQ', '成功 · 28.4 MB · 302 重定向'], ['ok', '00:00.540', '缓存', '边播边存', '已缓存 38%']].map(([t, ts, src, a, r], i) => `
    <div style="display:flex;gap:12px;padding-bottom:16px"><div style="display:flex;flex-direction:column;align-items:center"><i style="width:12px;height:12px;border-radius:6px;background:${i === 0 ? 'var(--danger)' : 'var(--ok)'};margin-top:4px"></i>${i < 2 ? '<b style="flex:1;width:2px;background:var(--line-strong);margin-top:4px"></b>' : ''}</div>
      <div style="flex:1"><div style="font:600 11.5px var(--font-num);color:var(--t3)">${ts}</div><b style="font-size:14.5px">${src} · ${a}</b><div style="font-size:12.5px;color:var(--t2);margin-top:2px">${r}</div></div></div>`).join('')}</div>` }),
  addTo: () => ({ t:'加入歌单', dark:S.playerOpen, body:`${group('', [item({ icon:'plus', color:'gray', label:'新建歌单', act:'sheet', args:{ v:'newPlaylist' } }), ...MY_PLAYLISTS.map(p => `<div class="it" data-act="sheetToast" data-msg="已加入「${p.t}」" data-icon="check"><div class="cv" style="${coverStyle(p.h, p.v)};width:44px;height:44px;border-radius:10px"></div><div class="lb"><b>${p.t}</b><small>${p.n} 首</small></div></div>`)])}` }),
  newPlaylist: () => ({ t:'新建歌单', body:`<div style="padding:0 var(--pad)"><div class="fld">${ic('edit')}<input placeholder="歌单名称" value="周末下午"></div>${group('', [item({ label:'设为私密', sw:'pitch' })])}<button class="btn pri block" data-act="sheetToast" data-msg="已创建「周末下午」" data-icon="check">创建</button></div>` }),
  import: () => ({ t:'导入', body:`${group('', [item({ icon:'link', color:'blue', label:'歌单链接 / 口令', sub:'自动识别并解析平台歌单', act:'sheetToast', args:{ msg:'已识别：深夜城市漫游（42 首）', icon:'link' } }), item({ icon:'folder', color:'orange', label:'从文件导入', sub:'支持桌面端导出的歌单文件、.json', act:'sheetToast', args:{ msg:'已导入 213 首', icon:'download' } }), item({ icon:'code', color:'violet', label:'导入音源脚本', sub:'.js 文件或链接', act:'sheetToast', args:{ msg:'已导入脚本源 · D', icon:'code' } })])}` }),
  activate: () => ({ t:'激活账号', body:`<div style="padding:0 var(--pad)"><div class="fld">${ic('key')}<input placeholder="XXXX-XXXX-XXXX-XXXX"></div><p class="hint" style="padding:10px 2px 16px">激活码区分大小写，一个激活码只能使用一次</p><button class="btn pri block" data-act="sheetToast" data-msg="激活成功" data-icon="crown">激活</button></div>` }),
};
ACT.bgCN = d => { S.bg = { 模糊封面:'blur', 静态流光:'static', 动态流光:'flow' }[d.v]; render(); };
ACT.toneCN = d => { S.tone = d.v === '暗色' ? 'dark' : 'light'; render(); };

function skinThumb(id) {
  const c = `<div class="c" style="${coverStyle(38, 0)}"></div>`, l = (a, w = 60) => `<div class="l ${a ? 'a' : ''}" style="width:${w}%"></div>`;
  return `<div class="skin-pv">${{
    spring:`<div style="position:absolute;inset:0;background:radial-gradient(circle at 30% 30%,hsl(268 70% 45%),transparent 60%),radial-gradient(circle at 70% 80%,hsl(320 70% 40%),transparent 60%)"></div><div style="position:absolute;left:8px;top:8px;width:16px;height:16px;border-radius:4px;${coverStyle(38, 0)}"></div><div style="position:absolute;left:10px;right:10px;top:32px;display:flex;flex-direction:column;gap:5px">${l(1, 90)}${l(0, 70)}${l(0, 60)}</div>`,
    flow:`<div style="position:absolute;inset:0;background:radial-gradient(circle at 70% 30%,hsl(200 70% 45%),transparent 60%)"></div><div style="position:absolute;left:10px;right:10px;top:16px;display:flex;flex-direction:column;gap:6px">${l(0, 60)}<div class="l" style="width:70%;margin-left:12%"></div>${l(1, 90)}<div class="l" style="width:56%;margin-left:20%"></div></div>`,
    cover: c + l(1, 50) + l(0, 34), vinyl:`<div class="c" style="border-radius:50%;background:repeating-radial-gradient(circle,#111 0 1px,#222 1px 2px);box-shadow:inset 0 0 0 13px #151619"></div>` + l(1, 40),
    karaoke: l(0, 70) + `<div class="l" style="width:76%;height:6px;background:linear-gradient(90deg,var(--accent) 55%,rgba(255,255,255,.3) 55%)"></div>` + l(0, 64) + l(0, 50),
    immersive:`<div style="position:absolute;inset:0;${coverStyle(38, 0)};filter:blur(8px);opacity:.6"></div><div class="c" style="${coverStyle(38, 0)};position:relative"></div>`,
    minimal:`<div style="display:flex;gap:4px;width:70%"><div style="width:16px;height:16px;border-radius:4px;${coverStyle(38, 0)}"></div><div class="l a" style="width:50%;margin-top:6px"></div></div>` + l(0, 70) + l(1, 66) + l(0, 60),
    pulse:`<div class="c" style="border-radius:50%;${coverStyle(38, 0)};box-shadow:0 0 0 5px rgba(244,210,138,.25),0 0 0 10px rgba(244,210,138,.1)"></div>`,
    poster:`<div style="position:absolute;inset:0;${coverStyle(38, 0)}"></div><div style="position:absolute;inset:0;background:linear-gradient(transparent,rgba(0,0,0,.8))"></div><div style="position:absolute;left:8px;bottom:10px;right:8px">${l(1, 90)}<div style="height:3px"></div>${l(0, 70)}</div>`,
    stage:`<div class="l a" style="width:80%;height:7px"></div>` + l(0, 50),
    particles:`<canvas class="fxc" data-fx="galaxy" data-static="1" style="position:absolute;inset:0"></canvas>`,
  }[id]}</div>`;
}
function eqHTML() {
  const W = 300, Hh = 170, pts = S.eq.map((v, i) => [(i + .5) / 10 * W, Hh / 2 - v / 12 * (Hh / 2 - 10)]);
  const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  return `<div class="eq"><svg class="curve" viewBox="0 0 ${W} ${Hh}" preserveAspectRatio="none"><path d="${d}" fill="none" stroke="var(--accent)" stroke-width="2" opacity=".55" vector-effect="non-scaling-stroke"/></svg>
    ${S.eq.map((v, i) => { const y = 50 - v / 12 * 46; return `<div class="band"><small>${v > 0 ? '+' : ''}${v}</small><div class="track" data-b="${i}"><b style="top:${Math.min(50, y)}%;bottom:${100 - Math.max(50, y)}%"></b><i style="top:${y}%"></i></div><small>${EQ_BANDS[i]}</small></div>`; }).join('')}</div>`;
}
function drawEq() { const el = document.querySelector('.eq'); if (el) el.outerHTML = eqHTML(); }

function renderSheet() {
  const f = SHEETS[S.sheet.v]; if (!f) return '';
  const c = f();
  return `<div class="scrim" data-act="closeSheet"></div><div class="sheet ${c.dark ? 'dark player-sheet' : ''}" ${c.dark ? 'data-theme="dark"' : ''}>
    <div class="grab"></div>${c.t ? `<div class="sh"><h3>${c.t}${c.sub ? `<small>${c.sub}</small>` : ''}</h3>${c.right || ''}<button class="ib" data-act="closeSheet" style="color:var(--t2)">${ic('close')}</button></div>` : ''}${c.head || ''}
    <div class="sbody">${c.body}</div></div>`;
}
const DIALOGS = {
  session: { i:'lock', t:'登录已过期', p:'为了账号安全，请重新登录。你的收藏和歌单已保存在云端。', a:[['稍后', 'closeDialog', 'sec'], ['重新登录', 'logout', 'pri']] },
  announce: { i:'bell', t:'服务端维护通知', p:'11 月 5 日 02:00–04:00 进行数据库升级，期间同步与登录不可用，离线播放不受影响。', a:[['我已知晓', 'closeDialog', 'pri']] },
  update: { i:'download', t:'发现新版本 v2.5.0', p:'· 歌词舞台按段落分段<br>· 车机歌词推送更稳定<br>· 修复若干问题<br><small style="color:var(--t3)">增量更新 · 12.4 MB</small>', a:[['稍后', 'closeDialog', 'sec'], ['立即更新', 'closeDialog', 'pri']] },
  logout: { i:'logout', t:'退出登录？', p:'退出后本机的下载和缓存会保留，收藏与歌单需要登录后同步。', a:[['取消', 'closeDialog', 'sec'], ['退出', 'logout', 'danger']] },
};
function renderDialog() {
  if (typeof FORM_DIALOGS !== 'undefined' && FORM_DIALOGS[S.dialog]) return `<div class="scrim" style="z-index:94"></div><div class="dlg form">${FORM_DIALOGS[S.dialog]()}</div>`;
  const d = DIALOGS[S.dialog]; if (!d) return '';
  return `<div class="scrim" data-act="closeDialog" style="z-index:94"></div><div class="dlg"><div class="di">${ic(d.i)}</div><h3>${d.t}</h3><p>${d.p}</p>
    <div class="acts">${d.a.map(([n, act, k]) => `<button class="btn ${k}" data-act="${act}">${n}</button>`).join('')}</div></div>`;
}

/* ================= Apple Music 风格：律动（弹簧逐字）/ 灵动（波浪歌词） =================
   三个视图共用一个封面元素（data-flip="amcover"），切换时封面在大图与左上角小图之间形变。 */
function amBg(s) {
  if (S.bg !== 'flow') return playerBg(s);
  return `<div class="pbg am-bg"><div class="flow">${flowBlobs(s)}<i style="background:radial-gradient(circle,hsl(${(s.h + 180) % 360} 70% 50%),transparent 65%)"></i></div><div class="shade" style="--shade:${S.bright / 100 * .8}"></div></div>`;
}
function amVol() {
  return `<div class="prog vol" data-kind="vol"><div class="vrow"><span>${ic('volume')}</span><div class="tr"><div class="fill" style="width:${S.vol * 100}%"></div></div><span>${ic('volume')}</span></div></div>`;
}
function renderAM(s, sk) {
  const v = S.amView, liked = S.liked.has(s.id);
  const head = `<div class="am-head ${v === 'cover' ? 'big' : 'small'}">
      <div class="am-cv-wrap"><div class="cv am-cv" data-flip="amcover" data-hero data-act="amView" data-v="cover" style="${coverStyle(s.h, s.v)}"></div></div>
      <div class="am-ti" data-flip="amtitle"><div class="t">${marquee(s.t, v === 'cover' ? 12 : 9)}</div><div class="a">${s.a}</div></div>
      <button class="ib heart am-like ${liked ? 'on' : ''}" data-act="like" data-id="${s.id}">${ic(liked ? 'heartf' : 'heart')}</button>
      <button class="ib am-more" data-act="sheet" data-v="more" data-id="${s.id}" data-ctx="player">${ic('more')}</button></div>`;
  let panel = '';
  if (v === 'lyrics') panel = sk === 'spring' ? lyricList({ fs:30, anchor:.26, words:true, stagger:true, cls:'stagger am-lyr' }) : lyricList({ fs:28, anchor:.3, cls:'wavy am-lyr' });
  if (v === 'queue') panel = `<div class="am-q">
      <div class="am-q-h"><b>接下来播放</b><span>${S.queueName}</span>
        <div class="am-q-btns"><button class="${S.mode === 'shuffle' ? 'on' : ''}" data-act="mode">${ic('shuffle')}</button><button class="${S.mode === 'loop' || S.mode === 'one' ? 'on' : ''}" data-act="mode">${ic(S.mode === 'one' ? 'repeat1' : 'repeat')}</button><button data-act="sheet" data-v="queue">${ic('more')}</button></div></div>
      <div class="am-q-l">${S.queue.slice(S.queue.indexOf(S.cur) + 1).concat(S.queue.slice(0, S.queue.indexOf(S.cur))).slice(0, 10).map((id, i) => { const x = SONGS[id]; return `<div class="am-q-r" data-act="play" data-id="${id}" style="--d:${i * 35}ms">${cover(x, '', 44)}<div style="flex:1;min-width:0"><b>${x.t}</b><small>${x.a}</small></div><span>${ic('drag')}</span></div>`; }).join('')}</div></div>`;
  const ctl = `<div class="am-ctl">${progress(s)}
      <div class="ctl am-main"><button class="ib sk" data-act="prev">${ic('prev')}</button><button class="am-play" data-act="toggle">${ic(S.playing ? 'pause' : 'play')}</button><button class="ib sk" data-act="next">${ic('next')}</button></div>
      ${amVol()}
      <div class="am-tabs"><button class="${v === 'lyrics' ? 'on' : ''}" data-act="amView" data-v="lyrics">${ic('quote')}</button><button class="${S.castDev ? 'on' : ''}" data-act="sheet" data-v="cast">${ic('cast')}</button><button class="${v === 'queue' ? 'on' : ''}" data-act="amView" data-v="queue">${ic('queue')}</button></div></div>`;
  return `<div class="player am ${S._playerAnim ? 'enter' : ''} ${S.playing ? '' : 'paused'} view-${v} sk-${sk}">${amBg(s)}
    <div class="pw"><div class="am-grab" data-act="closePlayer"><i></i></div>${head}<div class="am-panel">${panel}</div>${ctl}</div></div>`;
}
