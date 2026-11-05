// CI 截图：逐个打开 ?shot=<id>，等待 Flutter 首帧后截图到 tool/shots/
import { chromium } from 'playwright';
import fs from 'node:fs';

const list = JSON.parse(fs.readFileSync('./shots.json', 'utf8'));
fs.mkdirSync('./shots', { recursive: true });
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const landCtx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const logs = [];
const log = s => { logs.push(s); console.log(s); fs.writeFileSync('./shots/log.txt', logs.join('\n')); };

let i = 0;
for (const id of list) {
  i++;
  const t0 = Date.now();
  const land = id.endsWith('@land');
  const sid = id.replace('@land', '');
  log(`start ${id}`);
  const page = await (land ? landCtx : ctx).newPage();
  page.on('pageerror', e => log(`[${id}] PAGEERROR ${e.message}`));
  page.on('console', m => { const t = m.text(); if (m.type() === 'error' || /Exception|Error|overflow/i.test(t)) log(`[${id}] ${m.type()} ${t.slice(0, 400)}`); });
  // 每张最多 45 秒：页面卡死（死循环 / 渲染挂住）时 Playwright 自己的超时可能不生效，整步会被 15 分钟超时杀掉、一张图都没有
  const hard = new Promise((_, rej) => setTimeout(() => rej(new Error('hard timeout 45s')), 45000));
  try {
    await Promise.race([hard, (async () => {
    await page.goto(`http://localhost:8080/?shot=${encodeURIComponent(sid)}`, { waitUntil: 'commit', timeout: 20000 });
    await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 20000, state: 'attached' });
    await page.waitForTimeout(i === 1 ? 9000 : 4000); // 首次需下载 CanvasKit 与回退字体
    await page.screenshot({ path: `./shots/${String(i).padStart(2, '0')}-${id.replace(/[^\w-]+/g, '_')}.png`, timeout: 15000, animations: 'allow', caret: 'initial' });
    log(`ok ${id} ${Date.now() - t0}ms`);
    })()]);
  } catch (e) {
    log(`SHOT-FAIL ${id}: ${e.message.split('\n')[0]}`);
  }
  await Promise.race([page.close(), new Promise(r => setTimeout(r, 5000))]);
}
await browser.close();
