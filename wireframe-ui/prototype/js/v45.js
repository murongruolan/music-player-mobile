/* ======================================================================
   v4.5 平台登录：按各平台实际支持的方式
   - 网易云：扫码 / 导入 Cookie（没有手机号密码登录）
   - QQ音乐：只能导入 Cookie
   - 酷狗：手机验证码（App 端接入中）
   - 酷我 / 咪咕：没有账号体系，公开内容直接可用，不显示登录入口
   登录信息只存本机钥匙串；登录后用你的会员身份获取播放地址。
   ====================================================================== */
const LOGIN_MODES = { netease:['扫码', 'Cookie'], qq:['Cookie'], kugou:['验证码'], kuwo:[], migu:[] };
const COOKIE_HOW = {
  netease:'在电脑浏览器登录 music.163.com，打开开发者工具 → 网络，任选一个 music.163.com 的请求，复制请求头里的整段 Cookie（至少包含 MUSIC_U）。',
  qq:'在电脑浏览器登录 y.qq.com，打开开发者工具 → 网络，任选一个 y.qq.com 的请求，复制请求头里的整段 Cookie（需要包含 uin，会员取链还需要 qm_keyst）。',
};
const noLogin = pid => !LOGIN_MODES[pid]?.length;
S.platExpired = S.platExpired || {};

{
  const _plR = SHEETS.platLogin;
  SHEETS.platLogin = () => {
    const pid = S.dlg.plat, p = PLATFORMS.find(x => x.id === pid), modes = LOGIN_MODES[pid] || [];
    if (!modes.length) return { t:p.n, body:`<div class="plsheet" style="--pc:${p.c};--pc2:${p.c2}"><div class="pls-h">${platBadge(p, 40)}<div><b>${p.n}不需要登录</b><small>公开的歌单、榜单、搜索直接可用；平台本身没有可接入的账号登录</small></div></div>
      <button class="btn sec block" style="margin-top:16px" data-act="closeSheet">知道了</button></div>` };
    if (!modes.includes(S.dlg.mode)) S.dlg.mode = modes[0];
    const mode = S.dlg.mode, st = S.dlg.st || 0;
    const head = `<div class="pls-h">${platBadge(p, 40)}<div><b>登录${p.n}</b><small>用你的会员身份获取播放地址 · 登录信息只存本机</small></div></div>${modes.length > 1 ? seg(modes, mode, 'loginMode') : ''}`;
    let body;
    if (mode === '扫码') {
      body = _plR().body.replace(/^[\s\S]*?(<div class="qrbox)/, '$1').replace(/<\/div>\s*$/, '');
      if (S.dlg.expired) body = `<div class="qrbox expired45" data-act="qrRefresh">${qrSvg(9)}<div class="qr-exp">${ic('refresh')}<b>二维码已过期</b><small>点击刷新</small></div></div><p class="pls-tip">二维码 2 分钟内有效</p>`;
    } else if (mode === 'Cookie') {
      body = `<div style="padding:${modes.length > 1 ? 16 : 6}px 0 0"><textarea class="ta" placeholder="${pid === 'qq' ? 'uin=…; qm_keyst=…' : 'MUSIC_U=…; __csrf=…'}"></textarea>
        <p class="hint" style="padding:8px 2px 0;line-height:1.6">${COOKIE_HOW[pid]}</p>
        ${S.dlg.err ? `<p class="err45">${ic('info')}${S.dlg.err}</p>` : ''}
        <div style="display:flex;gap:10px;margin-top:12px"><button class="btn sec" style="flex:1" data-act="toast" data-msg="已粘贴" data-icon="paste">${ic('paste')}粘贴</button><button class="btn pri" style="flex:2" data-act="qrScan">验证并登录</button></div>
        <button class="btn ghost block" style="margin-top:8px" data-act="cookieBad">原型演示：Cookie 无效</button></div>`;
    } else {
      body = `<div style="padding:6px 0 0"><div class="fld">${ic('phone')}<input placeholder="手机号" inputmode="tel" value="138 0000 0000"></div>
        <div class="fld" style="margin-top:10px">${ic('key')}<input placeholder="短信验证码" inputmode="numeric"><button class="act" data-act="kgCode">${S.dlg.cd ? `${S.dlg.cd}s` : '获取'}</button></div>
        ${S.dlg.captcha ? `<p class="err45">${ic('shield')}酷狗要求人机验证，完成后会自动发送验证码</p>` : ''}
        <button class="btn pri block" style="margin-top:16px" data-act="qrScan">登录</button>
        <button class="btn ghost block" style="margin-top:8px" data-act="kgCaptcha">原型演示：需要人机验证</button></div>`;
    }
    return { t:'', body:`<div class="plsheet" style="--pc:${p.c};--pc2:${p.c2}">${head}${body}</div>` };
  };
}
Object.assign(ACT, {
  qrRefresh: () => { S.dlg.expired = false; S.dlg.st = 0; render(); },
  cookieBad: () => { S.dlg.err = S.dlg.plat === 'qq' ? 'QQ Music Cookie 中未找到 UIN' : 'Cookie 里没有 MUSIC_U，请确认是登录后的网易云 Cookie'; render(); },
  kgCode: () => { S.dlg.cd = 60; render(); toast('验证码已发送', 'phone'); },
  kgCaptcha: () => { S.dlg.captcha = true; render(); },
  platRelogin: d => { delete S.platExpired[d.v]; ACT.platLogin(d); },
});
{
  const _pl = ACT.platLogin;
  ACT.platLogin = d => { if (noLogin(d.v || S.plat)) { S.dlg = { plat:d.v || S.plat }; S.sheet = { v:'platLogin' }; return render(); } _pl(d); };
}

/* ---------- 平台账号页 ---------- */
PAGES.accounts3p = { render:() => `${appBar('平台账号')}
  <div class="note">${ic('link')}<span>登录后可以用你的平台会员身份获取播放地址，并看到每日推荐和你在该平台的歌单。登录信息只保存在本机钥匙串，不会上传。</span></div>
  ${group('平台', PLATFORMS.map(p => {
    const modes = LOGIN_MODES[p.id], exp = S.platExpired[p.id];
    const sub = !modes.length ? '无需登录 · 公开内容直接可用' : exp ? `登录已失效，请重新登录（${exp}）` : isIn(p.id) ? `已登录 · ${S.platLogin[p.id]} · ${PLAT_FEAT[p.id].vip}` : `未登录 · ${modes.map(m => m === 'Cookie' ? '导入 Cookie' : m === '验证码' ? '手机验证码' : '扫码').join('或')}`;
    const btn = !modes.length ? '' : exp ? `<button class="btn pri sm" data-act="platRelogin" data-v="${p.id}">重新登录</button>` : `<button class="btn ${isIn(p.id) ? 'sec' : 'pri'} sm" data-act="${isIn(p.id) ? 'platLogout' : 'platLogin'}" data-v="${p.id}">${isIn(p.id) ? '退出' : '登录'}</button>`;
    return `<div class="it">${platBadge(p, 30)}<div class="lb"><b>${p.n}</b><small class="${exp ? 'warn45' : ''}">${sub}</small></div>${btn}</div>`;
  }))}` };

/* ---------- 发现页登录卡：没有登录的平台不显示，按钮图标跟登录方式走 ---------- */
{
  const _c4 = platLoginCard4;
  platLoginCard4 = () => {
    const p = plat(), modes = LOGIN_MODES[p.id] || [];
    if (!modes.length) return '';
    const sub = modes[0] === '扫码' ? '扫码或导入 Cookie · 用你的会员身份播放' : modes[0] === 'Cookie' ? '导入 Cookie · 用你的会员身份播放' : '手机验证码 · 用你的会员身份播放';
    return _c4().replace(/<small>[^<]*<\/small>/, `<small>${sub}</small>`).replace(/(data-act="platLogin" data-v="[^"]*">)<svg[\s\S]*?<\/svg>/, `$1${ic(modes[0] === '扫码' ? 'scan' : modes[0] === 'Cookie' ? 'code' : 'phone')}`);
  };
}

FIX_JUMPS.push(
  ['平台登录 · 网易云扫码', () => { ACT.platLogin({ v:'netease' }); }],
  ['平台登录 · 二维码过期', () => { ACT.platLogin({ v:'netease' }); S.dlg.expired = true; }],
  ['平台登录 · 网易云 Cookie', () => { ACT.platLogin({ v:'netease', mode:'Cookie' }); }],
  ['平台登录 · QQ Cookie', () => { ACT.platLogin({ v:'qq' }); }],
  ['平台登录 · Cookie 无效', () => { ACT.platLogin({ v:'qq' }); S.dlg.err = 'QQ Music Cookie 中未找到 UIN'; }],
  ['平台登录 · 酷狗验证码', () => { ACT.platLogin({ v:'kugou' }); }],
  ['平台登录 · 酷狗人机验证', () => { ACT.platLogin({ v:'kugou' }); S.dlg.captcha = true; }],
  ['平台登录 · 酷我无需登录', () => { ACT.platLogin({ v:'kuwo' }); }],
  ['平台账号 · 登录已失效', at('accounts3p', {}, () => { S.platLogin.qq = '阿栗'; S.platExpired.qq = 'Cookie 已过期'; })],
);
