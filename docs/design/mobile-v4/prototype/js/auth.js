/* 登录 / 注册 / 忘记密码（v4 重做）
   - 登录：邮箱或 ID + 密码
   - 注册：邮箱 + 密码 + 人机验证 + 邮箱验证码
   - 忘记密码：邮箱 + 人机验证 + 邮箱验证码 → 重设密码 → 完成
   人机验证做成通用组件，服务端下发类型：图形字符 / 滑块拼图 / 文字点选（原型里可手动切换演示）。 */
S.auth = { email:'', id:'', pwd:'', pwd2:'', code:'', cap:'', capMode:'text', capOk:false, clicks:[], cd:0, busy:false, done:false, err:{}, show:false, remember:true };
const CAP_TEXT = 'K7F3';
const CLICK_CHARS = [['夜', 62, 48], ['航', 210, 112], ['星', 128, 132], ['光', 262, 40], ['海', 30, 120], ['风', 180, 30]];
const CLICK_TARGET = ['夜', '航', '星'];
const SLIDE_X = 196;                                   // 拼图缺口位置（px，相对图片左侧）
const authVal = k => S.auth[k] || '';
function fieldA(k, icon, ph, o = {}) {
  const err = S.auth.err[k], ok = o.ok;
  return `<label class="af ${err ? 'bad' : ''} ${ok ? 'good' : ''} ${authVal(k) ? 'has' : ''}" data-fk="${k}">
    ${ic(icon)}<span class="af-l">${ph}</span>
    <input data-f="${k}" type="${o.type === 'password' && !S.auth.show ? 'password' : o.type === 'password' ? 'text' : o.type || 'text'}" value="${authVal(k)}" autocomplete="off" ${o.max ? `maxlength="${o.max}"` : ''}>
    ${o.type === 'password' ? `<button type="button" class="af-eye" data-act="authEye">${ic(S.auth.show ? 'eye' : 'lock')}</button>` : ''}
    ${o.right || ''}${ok ? `<i class="af-ok">${ic('check')}</i>` : ''}
    ${err ? `<em class="af-err">${err}</em>` : ''}</label>`;
}
const pwScore = p => { let s = 0; if (p.length >= 8) s++; if (/[A-Z]/.test(p) && /[a-z]/.test(p)) s++; if (/\d/.test(p)) s++; if (/[^\w]/.test(p)) s++; return p ? Math.max(1, s) : 0; };
function pwMeter(k) { const s = pwScore(authVal(k)); return `<div class="pwm" data-pwm="${k}"><div>${[1, 2, 3, 4].map(i => `<i class="${i <= s ? 'on s' + s : ''}"></i>`).join('')}</div><span>${['至少 8 位，建议混合字母、数字和符号', '弱', '一般', '较强', '强'][s]}</span></div>`; }

/* ---------- 通用人机验证 ---------- */
function captcha() {
  const a = S.auth, m = a.capMode;
  const modes = [['text', '图形字符'], ['slide', '滑块拼图'], ['click', '文字点选']];
  let body = '';
  if (a.capOk) body = `<div class="cap-ok">${ic('check')}<b>验证通过</b><small>${{ text:'字符正确', slide:'拼图已对齐 · 用时 0.8s', click:'点选顺序正确' }[m]}</small></div>`;
  else if (m === 'text') body = `<div class="cap-text">
      <div class="cap-img" data-act="capRefresh" title="点击换一张">${capSvg()}<i class="cap-rf">${ic('refresh')}</i></div>
      <input data-f="cap" maxlength="4" placeholder="输入图中字符" value="${authVal('cap')}" class="cap-in" autocomplete="off">
      <button type="button" class="cap-go" data-act="capCheck">${ic('check')}</button></div>`;
  else if (m === 'slide') body = `<div class="cap-slide">
      <div class="cs-img" style="${coverStyle(268, 2)}"><i class="cs-hole" style="left:${SLIDE_X}px"></i><i class="cs-piece" style="${coverStyle(268, 2)};background-position:-${SLIDE_X}px -40px"></i><button type="button" class="cs-rf" data-act="capRefresh">${ic('refresh')}</button></div>
      <div class="cs-track"><span>向右拖动滑块完成拼图</span><i class="cs-fill"></i><b class="cs-knob">${ic('right')}</b></div></div>`;
  else body = `<div class="cap-click">
      <div class="cc-tip">请依次点击 ${CLICK_TARGET.map((c, i) => `<b class="${a.clicks.length > i ? 'hit' : ''}">${c}</b>`).join('')}<button type="button" data-act="capRefresh">${ic('refresh')}</button></div>
      <div class="cc-img" data-act="capClick" style="${coverStyle(200, 1)}">${CLICK_CHARS.map(([c, x, y], i) => `<span style="left:${x}px;top:${y}px;transform:rotate(${(i * 37) % 50 - 25}deg)">${c}</span>`).join('')}
        ${a.clicks.map((p, i) => `<i class="cc-mark" style="left:${p[0]}px;top:${p[1]}px">${i + 1}</i>`).join('')}</div></div>`;
  return `<div class="cap ${a.capOk ? 'passed' : ''} ${a.capShake ? 'shake' : ''}">
    <div class="cap-h"><span>${ic('shield')}人机验证</span><div class="cap-m">${modes.map(([k, n]) => `<button type="button" class="${m === k ? 'on' : ''}" data-act="capMode" data-v="${k}">${n}</button>`).join('')}</div></div>
    ${body}<small class="cap-note">类型由服务端下发，此处可切换演示</small></div>`;
}
function capSvg() {
  const seed = S.auth.capSeed || 1;
  return `<svg viewBox="0 0 120 44"><rect width="120" height="44" rx="8" fill="#1d1e28"/>${Array.from({ length:5 }, (_, i) => `<path d="M0 ${8 + i * 8 + seed % 5} Q60 ${(i * 17 + seed * 7) % 44} 120 ${(i * 11 + seed * 3) % 44}" stroke="hsl(${i * 60 + seed * 20} 60% 60% / .35)" fill="none"/>`).join('')}
    ${[...CAP_TEXT].map((c, i) => `<text x="${16 + i * 25}" y="${30 + (i % 2 ? -3 : 4)}" transform="rotate(${(i * 23 + seed * 9) % 36 - 18} ${22 + i * 25} 24)" font-size="24" font-weight="800" font-style="italic" fill="hsl(${38 + i * 50} 80% 70%)" font-family="Georgia,serif">${c}</text>`).join('')}
    ${Array.from({ length:30 }, (_, i) => `<circle cx="${(i * 37 + seed * 13) % 120}" cy="${(i * 23 + seed * 5) % 44}" r=".9" fill="#fff" opacity=".35"/>`).join('')}</svg>`;
}
function capFail(msg) { S.auth.capShake = true; render(); toast(msg, 'info'); setTimeout(() => { S.auth.capShake = false; const c = document.querySelector('.cap'); c && c.classList.remove('shake'); }, 500); }
function capPass() { S.auth.capOk = true; render(); const c = document.querySelector('.cap-ok'); c && c.animate([{ transform:'scale(.85)', opacity:0 }, { transform:'none', opacity:1 }], { duration:420, easing:'cubic-bezier(.3,1.5,.5,1)' }); }
ACT.capMode = d => { Object.assign(S.auth, { capMode:d.v, capOk:false, clicks:[], cap:'' }); render(); };
ACT.capRefresh = (d, e) => { e && e.stopPropagation(); Object.assign(S.auth, { capOk:false, clicks:[], cap:'', capSeed:(S.auth.capSeed || 1) + 1 }); render(); const r = document.querySelector('.cap-rf,.cs-rf,.cc-tip button'); r && r.animate([{ transform:'rotate(0)' }, { transform:'rotate(360deg)' }], { duration:500 }); };
ACT.capCheck = () => { if (authVal('cap').toUpperCase() === CAP_TEXT) capPass(); else capFail('字符不正确，换一张试试'); };
ACT.capClick = (d, e) => {
  const img = e.target.closest('.cc-img'), r = img.getBoundingClientRect(), sc = r.width / img.offsetWidth;
  const x = (e.clientX - r.left) / sc, y = (e.clientY - r.top) / sc;
  S.auth.clicks.push([x - 11, y - 11]);
  if (S.auth.clicks.length < 3) return render();
  const ok = S.auth.clicks.every((p, i) => { const t = CLICK_CHARS.find(c => c[0] === CLICK_TARGET[i]); return Math.hypot(p[0] + 11 - (t[1] + 14), p[1] + 11 - (t[2] + 16)) < 30; });
  if (ok) capPass(); else { S.auth.clicks = []; capFail('顺序或位置不对，再试一次'); }
};
/* 滑块拖动（独立于全局手势，捕获阶段拦截） */
(function () {
  let g = null;
  document.addEventListener('pointerdown', e => {
    const k = e.target.closest('.cs-knob'); if (!k) return;
    e.stopPropagation(); e.preventDefault();
    const tr = k.parentElement; g = { k, tr, x0:e.clientX, max:tr.offsetWidth - k.offsetWidth - 4, sc:tr.getBoundingClientRect().width / tr.offsetWidth, piece:tr.parentElement.querySelector('.cs-piece'), t0:performance.now() };
    k.classList.add('drag');
  }, true);
  window.addEventListener('pointermove', e => {
    if (!g) return; const x = Math.max(0, Math.min(g.max, (e.clientX - g.x0) / g.sc));
    g.x = x; g.k.style.transform = `translateX(${x}px)`; g.tr.querySelector('.cs-fill').style.width = x + 24 + 'px'; g.piece.style.transform = `translateX(${x}px)`;
    g.tr.querySelector('span').style.opacity = 1 - x / 80;
  });
  window.addEventListener('pointerup', () => {
    if (!g) return; const { x = 0, k, tr, piece } = g; g = null; k.classList.remove('drag');
    if (Math.abs(x - (SLIDE_X - 8)) < 7) { capPass(); return; }
    [k, piece].forEach(el => { el.style.transition = 'transform 420ms cubic-bezier(.3,1.3,.5,1)'; el.style.transform = ''; });
    const f = tr.querySelector('.cs-fill'); f.style.transition = 'width 420ms'; f.style.width = '';
    tr.classList.add('fail'); setTimeout(() => tr.classList.remove('fail'), 600);
    toast('没对齐，再试一次', 'info');
  });
})();

/* ---------- 输入同步（不重绘，避免打断输入） ---------- */
document.addEventListener('input', e => {
  const k = e.target.dataset && e.target.dataset.f; if (!k || !(k in S.auth)) return;
  S.auth[k] = e.target.value; const lb = e.target.closest('.af'); if (lb) { lb.classList.toggle('has', !!e.target.value); if (S.auth.err[k]) { delete S.auth.err[k]; lb.classList.remove('bad'); const em = lb.querySelector('.af-err'); em && em.remove(); } }
  const m = document.querySelector(`[data-pwm="${k}"]`); if (m) m.outerHTML = pwMeter(k);
});
ACT.authEye = (d, e) => { e && e.preventDefault(); S.auth.show = !S.auth.show; render(); };
ACT.authRemember = () => { S.auth.remember = !S.auth.remember; render(); };
const isEmail = v => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v);
function authErr(errs) { S.auth.err = errs; render(); document.querySelectorAll('.af.bad').forEach(el => el.animate([{ transform:'translateX(0)' }, { transform:'translateX(-8px)' }, { transform:'translateX(7px)' }, { transform:'translateX(-4px)' }, { transform:'none' }], { duration:380 })); }
ACT.sendCode = () => {
  const a = S.auth; if (a.cd > 0) return;
  if (!isEmail(a.email)) return authErr({ email:'先填写正确的邮箱' });
  if (!a.capOk) return capFail('请先完成人机验证');
  a.cd = 60; render(); toast(`验证码已发送至 ${a.email.replace(/^(.).*(@.*)$/, '$1***$2')}`, 'mail');
  clearInterval(a._t); a._t = setInterval(() => { a.cd--; const b = document.querySelector('.af-send'); if (b) { b.textContent = a.cd > 0 ? `${a.cd}s` : '重新发送'; b.classList.toggle('wait', a.cd > 0); } if (a.cd <= 0) clearInterval(a._t); }, 1000);
};
function busyThen(fn, ms = 900) { S.auth.busy = true; render(); setTimeout(() => { S.auth.busy = false; fn(); }, ms); }
const sendBtn = () => `<button type="button" class="af-send ${S.auth.cd > 0 ? 'wait' : ''}" data-act="sendCode">${S.auth.cd > 0 ? S.auth.cd + 's' : '获取验证码'}</button>`;
const submit = (label, act) => `<button class="btn pri block a-sub ${S.auth.busy ? 'busy' : ''}" data-act="${act}"><span>${label}</span><i class="spinner sm"></i></button>`;
const authShell = (inner, o = {}) => `<div class="ambient"><i></i><i></i><i></i></div>
  <div class="a-brand ${o.compact ? 'compact' : ''}">${appIcon(o.compact ? 48 : 64, 'float')}<div><h1>${APP_NAME}</h1><p>听见光的形状</p></div></div>
  <div class="a-card ${o.tall ? 'tall' : ''}" key="${o.key || ''}">${inner}</div>`;

/* ---------- 登录 / 注册 ---------- */
PAGES.login = { full:true, lightBar:true, render:() => {
  const a = S.auth, reg = S.loginSeg === '注册';
  if (reg && a.done) return authShell(`<div class="a-done"><div class="ad-ic">${ic('check')}</div><h2>注册成功</h2><p>欢迎加入 ${APP_NAME}，已为你登录 <b>${a.email}</b></p>${submit('开始听歌', 'login')}</div>`, { compact:true, key:'done' });
  const head = `${seg(['登录', '注册'], reg ? '注册' : '登录', 'loginSeg', 'dark')}`;
  if (!reg) return authShell(`${head}<div class="a-form" key="login">
      ${fieldA('id', 'user', '邮箱或用户 ID')}
      ${fieldA('pwd', 'lock', '密码', { type:'password' })}
      <div class="a-row"><button type="button" class="a-ck" data-act="authRemember"><span class="ck ${a.remember ? 'on' : ''}">${ic('check')}</span>保持登录</button><button type="button" data-act="authPage" data-v="forgot">忘记密码？</button></div>
      ${submit('登录', 'doLogin')}
      <div class="a-or"><span>或</span></div>
      <button type="button" class="btn ghost block a-alt" data-act="toast" data-msg="用已登录的手机扫电视/桌面上的二维码即可" data-icon="scan">${ic('scan')}已登录的设备扫码</button></div>`);
  return authShell(`${head}<div class="a-form" key="reg">
      ${fieldA('email', 'mail', '邮箱', { ok:isEmail(a.email) })}
      ${fieldA('pwd', 'lock', '设置密码', { type:'password' })}${pwMeter('pwd')}
      ${captcha()}
      ${fieldA('code', 'key', '邮箱验证码', { max:6, right:sendBtn() })}
      <button type="button" class="a-ck agree" data-act="agree"><span class="ck ${S.agree ? 'on' : ''}">${ic('check')}</span>我已阅读并同意《用户协议》与《隐私政策》</button>
      ${submit('注册', 'doRegister')}</div>`, { compact:true, tall:true });
} };
ACT.loginSeg = d => { S.loginSeg = d.v; S.auth.err = {}; S.auth.done = false; render(); };
ACT.doLogin = () => {
  const a = S.auth, e = {};
  if (!a.id.trim()) e.id = '请输入邮箱或用户 ID';
  if (a.pwd.length < 6) e.pwd = '密码至少 6 位';
  if (Object.keys(e).length) return authErr(e);
  busyThen(() => { S.auth = { ...S.auth, pwd:'', err:{} }; ACT.login(); });
};
ACT.doRegister = () => {
  const a = S.auth, e = {};
  if (!isEmail(a.email)) e.email = '邮箱格式不正确';
  if (pwScore(a.pwd) < 2 || a.pwd.length < 8) e.pwd = '密码至少 8 位，并包含数字或字母大小写';
  if (!a.capOk) return Object.keys(e).length ? authErr(e) : capFail('请先完成人机验证');
  if (!/^\d{6}$/.test(a.code)) e.code = '请输入 6 位邮箱验证码';
  if (Object.keys(e).length) return authErr(e);
  if (!S.agree) return toast('请先勾选同意协议', 'info');
  busyThen(() => { S.auth.done = true; render(); });
};

/* ---------- 忘记密码：验证身份 → 重设 → 完成 ---------- */
PAGES.forgot = { full:true, lightBar:true, render:() => {
  const a = S.auth, st = S.forgotStep;
  const steps = `<div class="a-steps">${['验证身份', '重设密码', '完成'].map((n, i) => `<div class="${i < st ? 'done' : i === st ? 'on' : ''}"><i>${i < st ? ic('check') : i + 1}</i><span>${n}</span></div>`).join('<b></b>')}</div>`;
  const back = `<button class="ib a-back" data-act="authPage" data-v="login">${ic('left')}</button>`;
  let body;
  if (st === 0) body = `<h2 class="a-t">找回密码</h2><p class="a-s">验证邮箱后即可重新设置密码</p>
    ${fieldA('email', 'mail', '注册邮箱', { ok:isEmail(a.email) })}${captcha()}${fieldA('code', 'key', '邮箱验证码', { max:6, right:sendBtn() })}${submit('下一步', 'forgotVerify')}`;
  else if (st === 1) body = `<h2 class="a-t">设置新密码</h2><p class="a-s">为 <b>${a.email || 'a***@example.com'}</b> 设置新密码</p>
    ${fieldA('pwd', 'lock', '新密码', { type:'password' })}${pwMeter('pwd')}${fieldA('pwd2', 'lock', '再次输入新密码', { type:'password', ok:a.pwd2 && a.pwd2 === a.pwd })}
    <p class="a-s small">重设后，其他已登录的设备需要重新登录</p>${submit('重设密码', 'forgotReset')}`;
  else body = `<div class="a-done"><div class="ad-ic">${ic('check')}</div><h2>密码已重设</h2><p>请使用新密码登录</p>${submit('返回登录', 'forgotDone')}</div>`;
  return `<div class="ambient"><i></i><i></i><i></i></div>${back}
    <div class="a-brand compact">${appIcon(48, 'float')}<div><h1>${APP_NAME}</h1><p>账号安全中心</p></div></div>
    <div class="a-card tall" key="f${st}">${steps}<div class="a-form">${body}</div></div>`;
} };
ACT.authPage = d => { S.authPage = d.v; S.forgotStep = 0; Object.assign(S.auth, { err:{}, capOk:false, clicks:[], cap:'', code:'', pwd:'', pwd2:'', done:false }); render(); };
ACT.forgotVerify = () => {
  const a = S.auth, e = {};
  if (!isEmail(a.email)) e.email = '邮箱格式不正确';
  if (!a.capOk) return Object.keys(e).length ? authErr(e) : capFail('请先完成人机验证');
  if (!/^\d{6}$/.test(a.code)) e.code = '请输入 6 位邮箱验证码';
  if (Object.keys(e).length) return authErr(e);
  busyThen(() => { S.forgotStep = 1; render(); });
};
ACT.forgotReset = () => {
  const a = S.auth, e = {};
  if (a.pwd.length < 8) e.pwd = '至少 8 位';
  if (a.pwd2 !== a.pwd) e.pwd2 = '两次输入不一致';
  if (Object.keys(e).length) return authErr(e);
  busyThen(() => { S.forgotStep = 2; render(); });
};
ACT.forgotDone = () => { ACT.authPage({ v:'login' }); S.loginSeg = '登录'; render(); toast('请使用新密码登录', 'lock'); };

/* 重绘时保留登录卡片 / Sheet / 弹窗内部的滚动位置，避免点验证码、切 Tab 后跳回顶部 */
const _renderKeep = render;
render = function () {
  const keep = ['.a-card', '.sheet .sbody', '.dlg.form'].map(s => { const el = document.querySelector('#screen ' + s); return [s, el ? el.scrollTop : 0]; });
  _renderKeep();
  keep.forEach(([s, y]) => { const el = document.querySelector('#screen ' + s); if (el && y) el.scrollTop = y; });
};
