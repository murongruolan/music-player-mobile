/* 粒子舞台：电脑端 3D 点云预设的移动端精简版（Canvas 2D，2600 点）。
   正式实现应复用电脑端的 GLSL（sollin-fx-proposals/presets.three.vert.glsl），这里只用于原型演示。
   可拖动旋转；"朝向相机"的光环在屏幕空间绘制，任何角度都正对镜头。 */
const FX = { yaw:0.3, pitch:0.32, drag:null, list:[], N:2600, R:null };
(function initFx() {
  let a = 1234567; const r = () => ((a = (a * 16807) % 2147483647) / 2147483647);
  FX.R = Array.from({ length:FX.N }, () => [r(), r(), r(), r()]);
})();
function hexRgb(h) { const m = h.match(/\w\w/g).map(x => parseInt(x, 16)); return m; }
function hslRgb(h, s, l) { s /= 100; l /= 100; const k = n => (n + h / 30) % 12, a = s * Math.min(l, 1 - l); const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1))); return [f(0) * 255, f(8) * 255, f(4) * 255].map(Math.round); }

function mountFx(root) {
  FX.list = [];
  root.querySelectorAll('canvas.fxc').forEach(c => {
    const box = c.getBoundingClientRect(), dpr = Math.min(2, window.devicePixelRatio || 1);
    c.width = Math.max(10, box.width * dpr); c.height = Math.max(10, box.height * dpr);
    const item = { c, ctx:c.getContext('2d'), preset:c.dataset.fx, static:!!c.dataset.static, dpr };
    if (!item.static) {
      c.onpointerdown = e => { FX.drag = { x:e.clientX, y:e.clientY, yaw:FX.yaw, pitch:FX.pitch }; c.setPointerCapture(e.pointerId); };
      c.onpointermove = e => { if (!FX.drag) return; FX.yaw = FX.drag.yaw + (e.clientX - FX.drag.x) * .008; FX.pitch = Math.max(-1.4, Math.min(1.4, FX.drag.pitch + (e.clientY - FX.drag.y) * .008)); };
      c.onpointerup = () => { FX.drag = null; };
    }
    FX.list.push(item);
    drawFx(item, performance.now() / 1000);
  });
}
function drawFx(it, t) {
  const { ctx, c, preset } = it, w = c.width, h = c.height;
  const s = song(), beatPh = (S.pos * 112 / 60) % 1, beat = S.playing ? Math.exp(-beatPh * 6) : 0, bass = S.playing ? .35 + .4 * beat : .1;
  const yaw = it.static ? .4 : FX.yaw + (FX.drag ? 0 : t * .05), pitch = it.static ? .4 : FX.pitch;
  const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
  const f = Math.min(w, h) * 1.05, cx0 = w / 2, cy0 = h * (it.static ? .5 : .4);
  const cols = [hslRgb(s.h, 75, 66), hexRgb(ACCENTS[S.accent].c), [255, 244, 222]];
  ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1; ctx.fillStyle = '#05060a'; ctx.fillRect(0, 0, w, h);
  ctx.globalCompositeOperation = 'lighter';
  const proj = (x, y, z) => { const x1 = cy * x + sy * z, z1 = -sy * x + cy * z, y1 = cp * y - sp * z1, z2 = sp * y + cp * z1; const d = z2 + 8; const k = f / d; return [cx0 + x1 * k, cy0 - y1 * k, k, z2]; };
  const [ox, oy, ok] = proj(0, 0, 0);
  let lastC = -1;
  const dot = (x, y, z, ci, a, sz = 1) => {
    const p = proj(x, y, z); if (p[3] < -7) return;
    if (ci !== lastC) { ctx.fillStyle = `rgb(${cols[ci]})`; lastC = ci; }
    ctx.globalAlpha = Math.min(1, a * 1.5); const size = Math.max(1, sz * p[2] * .03 * it.dpr);
    ctx.fillRect(p[0], p[1], size, size); return p;
  };
  const tt = t * (S.playing ? 1 : .25), front = beatPh * 4;
  for (let i = 0; i < FX.N; i++) {
    const [r1, r2, r3, r4] = FX.R[i];
    if (preset === 'galaxy') {
      if (i < 320) { const yy = r1 * 2 - 1, an = r2 * 6.283, q = Math.sqrt(1 - yy * yy), rr = Math.pow(r3, 1.8) * .9 * (1 + bass * .15); dot(q * Math.cos(an) * rr, yy * rr * .6, q * Math.sin(an) * rr, 2, .5 + beat * .3); continue; }
      const r = .4 + Math.pow(r1, .85) * 3.8, arm = i % 2, spd = r2 + r3 - 1, inArm = r4 > .28;
      const th = (inArm ? arm * Math.PI + Math.log(r) * 2.3 + spd * (.6 + .1 * r) : r2 * 6.283) + tt * .3 / (.5 + .45 * r);
      const ring = Math.exp(-Math.abs(r - front) * 2) * beat;
      dot(Math.cos(th) * r, (r3 - .5) * .16 * Math.exp(-r * .2), Math.sin(th) * r, inArm && Math.abs(spd) < .25 ? 2 : inArm ? 0 : 1, (inArm ? .55 : .25) * (1 - r / 5) + ring * .6);
    } else if (preset === 'disk') {
      if (i < 2000) {
        const r = 1.15 + Math.pow(r1, .75) * 2.6, th = r2 * 6.283 + tt * .9 * Math.pow(r, -1.5);
        const x = Math.cos(th) * r, z = Math.sin(th) * r, y = (r3 - .5) * .05 * r;
        const p = proj(x, y, z); const dd = Math.hypot(p[0] - ox, p[1] - oy);
        if (p[3] > 0 && dd < 1.08 * ok) continue;                         // 被黑影挡住
        const heat = 1 - Math.min(1, (r - 1.15) / 2);
        dot(x, y, z, heat > .55 ? 2 : heat > .25 ? 1 : 0, (.25 + .55 * heat) * (1 + bass * heat) + Math.exp(-Math.abs(r - 1.15 - front * .6) * 3) * beat * .5);
      } else {
        // 透镜弧 + 光子环：屏幕空间绘制，永远正对相机（v2 修复点）
        const ph = r2 * 6.283, ring = i > 2420;
        const rr = (ring ? 1.08 + (r1 - .5) * .02 : 1.25 + Math.pow(r1, 2) * .6) * ok;
        const up = Math.sin(ph) * Math.sign(sp || 1) > 0 ? 1 : .35, flat = ring ? 1 : .92;
        if (lastC !== 2) { ctx.fillStyle = `rgb(${cols[2]})`; lastC = 2; }
        ctx.globalAlpha = ring ? .8 * (1 + beat) : .5 * up * (1 - r1 * .6);
        const size = Math.max(1.2, 1.8 * it.dpr); ctx.fillRect(ox + Math.cos(ph) * rr, oy - Math.sin(ph) * rr * flat, size, size);
      }
    } else if (preset === 'globe') {
      const yy = r1 * 2 - 1, an = r2 * 6.283 + tt * .1, q = Math.sqrt(1 - yy * yy), x = q * Math.cos(an), z = q * Math.sin(an);
      const R = 2 * (1 + bass * .04);
      const land = Math.sin(3 * x + 1) * Math.sin(4 * yy + .5) * Math.sin(3 * z + 2) + Math.sin(7 * x + z * 5) * .3;
      const back = (sp * yy + cp * (-sy * x + cy * z)) > 0;   // 背面
      const city = Math.pow(Math.abs(Math.sin(i * 12.9 + Math.floor(tt * 7))), 40) * 3;
      if (land > .08) dot(x * R, yy * R, z * R, city > .5 ? 2 : 0, (back ? .12 : .6) + city * .4);
      else if (Math.abs((yy * 6 + 6.5) % 1 - .5) < .03 || Math.abs((r2 * 24 + .5) % 1 - .5) < .03) dot(x * R, yy * R, z * R, 1, back ? .06 : .3);
      else dot(x * R * (1.04 + r3 * .12), yy * R * (1.04 + r3 * .12), z * R * (1.04 + r3 * .12), 0, .05);
      if (i < 260) { const u = i / 260 * 6.283, ys = Math.sin(tt * .4) * .9, rr = Math.sqrt(1 - ys * ys) * R * 1.02; dot(Math.cos(u) * rr, ys * R, Math.sin(u) * rr, 1, .55 + beat); }
    } else if (preset === 'gyro') {
      if (i < 360) { const yy = r1 * 2 - 1, an = r2 * 6.283, q = Math.sqrt(1 - yy * yy), rr = .5 * (1 + bass * .3) * (.7 + .3 * r3); dot(q * Math.cos(an) * rr, yy * rr, q * Math.sin(an) * rr, 2, .5 + beat * .4); continue; }
      const k = i % 4, rad = 1.2 + k * .5, u = r1 * 6.283 + tt * (.25 + .1 * k) * (k % 2 ? -1 : 1);
      const seg = ((r1 * 6 + k * .37) % 1) > .08; if (!seg) continue;
      let x = Math.cos(u) * rad, y = (r2 - .5) * .14, z = Math.sin(u) * rad;
      const ang = (tt * (.3 + .13 * k) + beat * .5) * (k % 2 ? -1 : 1) + k, ca = Math.cos(ang), sa = Math.sin(ang);
      const y2 = y * ca - z * sa, z2 = y * sa + z * ca; const b = k * .7, cb = Math.cos(b), sb = Math.sin(b);
      const chase = Math.pow(((r1 * 2 - tt * (.5 + .2 * k)) % 1 + 1) % 1, 20) * 2;
      dot(x * cb - y2 * sb, x * sb + y2 * cb, z2, chase > .4 ? 2 : k % 2 ? 1 : 0, .35 + chase);
    }
  }
  ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
}
(function fxLoop() {
  const t = performance.now() / 1000;
  FX.list.forEach(it => { if (!it.static && it.c.isConnected) drawFx(it, t); });
  requestAnimationFrame(fxLoop);
})();
