/* ======================================================================
   v4.4 与 App #28–#30 同步：原型里还没有、App 已经实现的界面
   1. 外观：减少模糊效果
   2. 我的 → 音乐 → 关注的歌手（新页面）；歌手页 / 搜索艺术家 / 平台歌手页的「关注」改为真实状态
   3. 歌手电台、私人电台的真实说明；电台队列里的「不感兴趣」
   4. 搜索歌曲排序：综合 / 歌名 / 歌手 / 时长（平台不提供最新 / 最热排序）
   5. 关于 → 诊断：崩溃报告页、清除缓存确认
   6. 发现页 Banner：飙升榜 / 新歌榜（副标题是榜首歌曲）+ 推荐歌单第 7–10 个
   ====================================================================== */

/* ---------- 1. 减少模糊效果 ---------- */
S.set.reduceBlur = false;
{
  const _ap = PAGES.appearance.render;
  PAGES.appearance.render = p => _ap(p).replace(/(<div class="it[^"]*" data-act="tg" data-k="reduceMotion">[\s\S]*?<\/div><\/div>)/,
    `$1${item({ icon:'layers', color:'gray', label:'减少模糊效果', sub:'玻璃、毛玻璃导航栏改为不透明底色，老机型更流畅', sw:'reduceBlur' })}`);
}

/* ---------- 2. 关注的歌手 ---------- */
S.follow = S.follow || [{ a:'雾港', h:38, at:'10-28' }, { a:'Lumen', h:250, at:'10-21' }];
const isFollow = a => S.follow.some(f => f.a === a);
ACT.follow = d => {
  const a = d.v;
  if (isFollow(a)) { S.follow = S.follow.filter(f => f.a !== a); render(); return toast(`已取消关注 ${a}`, 'heart'); }
  const s = SONGS.find(x => x.a === a);
  S.follow = [{ a, h:s ? s.h : 200, at:'今天' }, ...S.follow]; render(); toast(`已关注 ${a}，可在「我的 → 关注的歌手」找到`, 'heartf');
};
ACT.unfollowRow = d => { S.follow = S.follow.filter(f => f.a !== d.v); render(); toast(`已取消关注 ${d.v}`, 'heart'); };
ACT.followRadio = d => { ACT.playAll({ list:'hot', shuffle:'1' }); S.queueName = `${d.v} 电台`; render(); toast(`正在生成「${d.v}」电台…`, 'wave'); };
ACT.openFollowed = d => { const s = SONGS.find(x => x.a === d.v); ACT.push({ v:'artist', id:s ? s.id : 0 }); };
PAGES.followed = { render:() => `${appBar('关注的歌手')}
  ${S.follow.length ? `<div class="grp">${S.follow.map(f => `<div class="it" data-act="openFollowed" data-v="${f.a}">
      <div class="cv fw44" style="${coverStyle(f.h, 1)}"></div><div class="lb"><b>${f.a}</b><small>关注于 ${f.at}</small></div>
      <button class="ib" data-act="followRadio" data-v="${f.a}">${ic('wave')}</button><button class="ib" style="color:var(--accent-text)" data-act="unfollowRow" data-v="${f.a}">${ic('heartf')}</button></div>`).join('')}</div>`
    : `<div class="empty44">${ic('user')}<b>还没有关注的歌手</b><small>在歌手页右上角点爱心关注，之后在这里找到他们</small></div>`}
  <p class="hint" style="padding:0 var(--pad)">关注记录只保存在这台设备上。右侧电台按钮会在歌手所在平台搜索他的歌，打乱后连续播放。</p>` };
{
  const _me = PAGES.me.render;
  PAGES.me.render = p => _me(p).replace('<div class="grp-t">个性化</div>', `${group('音乐', [item({ icon:'user', color:'pink', label:'关注的歌手', val:S.follow.length ? `${S.follow.length} 位` : '', act:'push', args:{ v:'followed' } })])}<div class="grp-t">个性化</div>`);
}

/* ---------- 3. 电台 / 不感兴趣 ---------- */
ACT.artistRadio = () => { const s = SONGS[S.stack.at(-1)?.params?.id ?? 0] || SONGS[0]; ACT.followRadio({ v:s.a }); };
const isRadio = () => S.queueName === '私人电台' || / 电台$/.test(S.queueName || '');
ACT.radioDislike = () => {
  const id = S.sheet.id; S.sheet = null; S.queue = S.queue.filter(x => x !== id);
  if (S.cur === id && S.queue.length) S.cur = S.queue[0];
  render(); toast('已从电台移除，以后的电台不再放这首', 'nodislike');
};
{
  const _more = SHEETS.more;
  SHEETS.more = () => {
    const o = _more();
    if (S.sheet.ctx !== 'daily' && isRadio() && S.queue.includes(S.sheet.id)) {
      o.body = o.body.replace(/(<div class="it[^"]*" data-act="sheet" data-v="trace">[\s\S]*?<\/div><\/div>)/, `$1${item({ icon:'nodislike', color:'gray', label:'不感兴趣', sub:'从电台移除，以后的电台不再放这首', act:'radioDislike' })}`);
    }
    return o;
  };
}

/* ---------- 4. 搜索排序：只保留能做到的 ---------- */
SHEETS.rSort = () => ({ t:'排序', sub:'只排已加载的结果', body:`<div class="grp">${[['综合', '平台默认的相关度'], ['歌名', '按歌名排序'], ['歌手', '按歌手排序'], ['时长', '从短到长']].map(([o, d]) => `<div class="it noic" data-act="rSortPick" data-v="${o}"><div class="lb"><b>${o}</b><small>${d}</small></div>${S.rSort === o ? `<span style="color:var(--accent-text)">${ic('check')}</span>` : ''}</div>`).join('')}</div>` });

/* ---------- 5. 关于 → 诊断 ---------- */
const CRASHES = [
  { at:'11-02 21:14:08', m:'RangeError (index): Invalid value: Not in inclusive range 0..28: 29', st:'#0 List.[] (dart:core-patch/growable_array.dart)\n#1 LyricView._layout (package:lyra/player/lyrics.dart:142)\n#2 _LyricViewState.build (package:lyra/player/lyrics.dart:201)' },
  { at:'10-30 08:02:51', m:'PlayerException: (0) Source error', st:'#0 AudioPlayer._load (package:just_audio/just_audio.dart:871)\n#1 AudioEngine._load (package:lyra/audio/audio_engine.dart:128)' },
];
S.crashes = S.crashes || CRASHES.slice();
PAGES.crashLog = { render:() => `${appBar('崩溃报告', { right:S.crashes.length ? `<button class="ib" data-act="dialog" data-v="crashClear">${ic('trash')}</button>` : '' })}
  ${S.crashes.length ? `<div class="grp">${S.crashes.map((c, i) => `<div class="it" data-act="sheet" data-v="crashDetail" data-id="${i}"><div class="tile" style="background:${TILE.red}">${ic('bug')}</div><div class="lb"><b class="cl44">${c.m}</b><small>${c.at}</small></div><div class="val">${ic('right')}</div></div>`).join('')}</div>
    <p class="hint" style="padding:0 var(--pad)">框架错误和未处理的异常记在本机，最多 20 条。开了「自动上报崩溃」时会同时上报错误信息和版本号。</p>`
    : `<div class="empty44">${ic('check')}<b>没有崩溃记录</b><small>出现崩溃或未处理的错误时会记在这里（最多 20 条）</small></div>`}` };
SHEETS.crashDetail = () => { const c = S.crashes[S.sheet.id] || S.crashes[0];
  return { t:'崩溃详情', sub:c.at, body:`<div style="padding:0 var(--pad)"><b style="display:block;font-size:13px;line-height:1.5">${c.m}</b><pre class="st44">${c.st}</pre>
    <button class="btn pri block" style="margin-top:14px" data-act="sheetToast" data-msg="已复制" data-icon="copy">${ic('copy')}复制</button></div>` }; };
DIALOGS.crashClear = { i:'trash', t:'清空崩溃记录？', p:'只清除本机记录。', a:[['取消', 'closeDialog', 'sec'], ['清空', 'crashClearGo', 'danger']] };
DIALOGS.cacheClear = { i:'trash', t:'清除缓存？', p:'会清掉已加载的封面图片、平台歌单 / 榜单 / 歌词缓存，之后打开时重新加载。收藏、歌单和设置不受影响。', a:[['取消', 'closeDialog', 'sec'], ['清除', 'cacheClearGo', 'danger']] };
Object.assign(ACT, {
  crashClearGo: () => { S.crashes = []; S.dialog = null; render(); toast('已清空', 'trash'); },
  cacheClearGo: () => { S.cacheMB = 0; S.dialog = null; render(); toast('已清除 86 MB 图片缓存和列表缓存', 'trash'); },
});
S.cacheMB = S.cacheMB ?? 86;
{
  const _ab = PAGES.about.render;
  PAGES.about.render = p => _ab(p)
    .replace(/data-act="toast" data-msg="没有崩溃记录" data-icon="check"([\s\S]*?)<div class="val">0 条/, (m, mid) => `data-act="push" data-v="crashLog"${mid}<div class="val">${S.crashes.length} 条`)
    .replace(/(<b>自动上报崩溃<\/b>)/, '$1<small>只上报错误信息和版本号，不含个人数据</small>')
    .replace(/(<b>应用日志<\/b>)/, '$1<small>复制最近的提示、播放错误和崩溃，发给开发者</small>')
    .replace(/data-act="toast" data-msg="已清除 1\.8 GB" data-icon="trash"([\s\S]*?<b>清除缓存<\/b>)([\s\S]*?)<div class="val">1\.8 GB/, (m, a, b) => `data-act="dialog" data-v="cacheClear"${a}<small>图片、平台列表与歌词的缓存，清除后重新加载</small>${b}<div class="val">${S.cacheMB} MB`);
}

/* ---------- 6. Banner：榜单（榜首歌）+ 推荐歌单 7–10 ---------- */
BANNERS.splice(0, BANNERS.length,
  { k:'排行榜', h:'飙升榜', d:'榜首 · 夜航星图 - 雾港', hue:20 },
  { k:'排行榜', h:'新歌榜', d:'榜首 · 玻璃海 - Lumen', hue:190 },
  { k:'推荐歌单', h:'雨天钢琴', d:'Mo · 5.3万次播放', hue:200 },
  { k:'推荐歌单', h:'后摇与星空', d:'Lyra 编辑部 · 21.4万次播放', hue:225 },
);

/* ---------- 目录 ---------- */
{
  const _bs44 = buildScreen;
  buildScreen = function () {
    let h = _bs44();
    const top = S.stack.at(-1);
    // 歌手页右上角爱心：真实关注状态
    if (top?.id === 'artist') {
      const a = (SONGS[top.params?.id ?? 0] || SONGS[0]).a;
      h = h.replace(/<button class="ib" data-act="toast" data-msg="已关注 [^"]*" data-icon="heartf">[\s\S]*?<\/button>/, `<button class="ib" ${isFollow(a) ? 'style="color:var(--accent-text)"' : ''} data-act="follow" data-v="${a}">${ic(isFollow(a) ? 'heartf' : 'heart')}</button>`);
    }
    // 搜索 · 艺术家：关注按钮
    h = h.replace(/<button class="btn sec sm" style="margin-right:14px" data-act="toast" data-msg="已关注 ([^"]*)" data-icon="heartf">关注<\/button>/g, (m, a) => `<button class="btn sec sm" style="margin-right:14px" data-act="follow" data-v="${a}">${isFollow(a) ? '已关注' : '关注'}</button>`);
    return h;
  };
}
FIX_JUMPS.push(
  ['外观 · 减少模糊效果', at('appearance', {}, () => { S.set.reduceBlur = true; })],
  ['关注的歌手', at('followed')], ['关注的歌手 · 空', at('followed', {}, () => { S.follow = []; })],
  ['歌手页 · 已关注', at('artist', { id:0 }, () => { S.follow = [{ a:SONGS[0].a, h:SONGS[0].h, at:'今天' }]; })],
  ['电台 · 不感兴趣', () => { S.queueName = '私人电台'; S.sheet = { v:'more', id:S.queue[1], ctx:'list' }; }],
  ['关于 · 崩溃报告', at('crashLog')], ['关于 · 崩溃详情', at('crashLog', {}, () => { S.sheet = { v:'crashDetail', id:0 }; })], ['关于 · 崩溃报告 · 空', at('crashLog', {}, () => { S.crashes = []; })],
  ['关于 · 清除缓存', at('about', {}, () => { S.dialog = 'cacheClear'; })],
);
