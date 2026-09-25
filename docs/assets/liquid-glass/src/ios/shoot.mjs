// Schiet de iPhone-mockups (LG-01 tot en met LG-03) op 402x874 CSS-px @3x = 1206x2622.
// Echt glas in twee passes, omdat CSS geen breking kent:
//   pass 1: de pagina zonder glasvlakken, als beeld van wat er onder het glas ligt;
//   pass 2: per .glass-vlak vier lagen uit dat beeld: blur, brekingsrand, tint, lichtrand.
// Gebruik: node shoot.mjs [paginanaam ...]   (Playwright uit de globale installatie)
import { readdirSync, mkdirSync } from 'node:fs';
import { join, basename } from 'node:path';

const { chromium } = await import(
  process.env.PLEYA_MOCKUP_PLAYWRIGHT ?? '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs'
);
const ROOT = new URL('.', import.meta.url).pathname;
const DEST = process.env.PLEYA_MOCKUP_DEST ?? join(ROOT, '../../mockups-2026-09-24');
mkdirSync(DEST, { recursive: true });

// Draait in de pagina. url = pass-1-beeld, W/H = paginamaat in CSS-px.
// Lagen van onder naar boven: brekingslaag (hele vlak, licht vergroot rond het midden),
// daarboven de blurlaag met een zacht afgeronde uitsparing van `band` px langs de rand, zodat
// alleen die rand de breking laat zien; dan tint met een lichte verloop bovenin, dan de lichtrand.
function buildGlass({ url, W, H }) {
  const css = getComputedStyle(document.documentElement);
  const v = (el, name) => parseFloat(el.dataset[name] ?? css.getPropertyValue('--lg-' + name));
  for (const el of document.querySelectorAll('.glass')) {
    const r = el.getBoundingClientRect();
    const blur = v(el, 'blur'), tint = v(el, 'tint'), sat = v(el, 'sat'), band = v(el, 'band'), zoom = v(el, 'zoom'), dim = v(el, 'dim');
    const rad = Math.min(parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0, r.width / 2, r.height / 2);
    const P = Math.ceil(blur * 3);
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const add = (style, parent = el) => { const d = document.createElement('div'); d.className = 'lg'; d.setAttribute('style', style); parent.append(d); return d; };
    const layers = document.createElement('div');
    layers.className = 'lg'; layers.style.cssText = 'inset:0;border-radius:inherit';
    // 1. breking
    add(`inset:0;background:url(${url}) no-repeat;background-size:${W * zoom}px ${H * zoom}px;` +
      `background-position:${-(zoom - 1) * cx - r.left}px ${-(zoom - 1) * cy - r.top}px;` +
      `filter:blur(${blur / 3}px) saturate(${sat}) brightness(${dim})`, layers);
    // 2. blur, gemaskeerd tot binnen de rand (zachte overgang van 3 px)
    const w = r.width, h = r.height, ir = Math.max(rad - band, 0);
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><filter id="f"><feGaussianBlur stdDeviation="3"/></filter>` +
      `<rect x="${band}" y="${band}" width="${w - 2 * band}" height="${h - 2 * band}" rx="${ir}" fill="#fff" filter="url(#f)"/></svg>`;
    const m = `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`;
    const wrap = add(`inset:0;-webkit-mask:${m} no-repeat 0 0 / ${w}px ${h}px;mask:${m} no-repeat 0 0 / ${w}px ${h}px`, layers);
    add(`inset:${-P}px;background:url(${url}) no-repeat;background-size:${W}px ${H}px;` +
      `background-position:${-(r.left - P)}px ${-(r.top - P)}px;filter:blur(${blur}px) saturate(${sat}) brightness(${dim})`, wrap);
    // 3. tint, 4. lichtrand
    add(`inset:0;background:linear-gradient(180deg, rgba(255,255,255,.10), rgba(255,255,255,0) 45%), rgba(255,255,255,${tint})`, layers);
    add(`inset:0;border-radius:inherit;box-shadow:inset 0 1px 0 rgba(255,255,255,.55), inset 0 0 0 .5px rgba(255,255,255,.30), inset 0 -1px 0 rgba(255,255,255,.10)`, layers);
    el.prepend(layers);
  }
}

const wanted = process.argv.slice(2);
const pages = readdirSync(ROOT).filter(f => /^LG-\d\d.*\.html$/.test(f) && (wanted.length === 0 || wanted.some(w => f.includes(w)))).sort();
const browser = await chromium.launch();
for (const f of pages) {
  const land = f.includes('speler');
  const W = land ? 874 : 402, H = land ? 402 : 874;
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 3, colorScheme: 'dark' });
  const page = await ctx.newPage();
  await page.goto('file://' + join(ROOT, f), { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => document.documentElement.classList.add('bgpass'));
  const bg = await page.screenshot({ type: 'png' });
  const url = 'data:image/png;base64,' + bg.toString('base64');
  await page.evaluate(() => document.documentElement.classList.remove('bgpass'));
  await page.evaluate(buildGlass, { url, W, H });
  await page.evaluate(u => new Promise(res => { const i = new Image(); i.onload = res; i.src = u; }), url);
  await page.waitForTimeout(200);
  const png = join(DEST, basename(f, '.html') + '.png');
  await page.screenshot({ path: png });
  console.log('shot', png);
  await ctx.close();
}
await browser.close();
