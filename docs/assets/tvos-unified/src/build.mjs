// Bouwt pages/*.html (fragmenten met {{tokens}}) naar out/*.html en schiet ze op
// exact 1920×1080 (@1x, zoals de northstar-set) naar ~/Downloads/mockups-tvos.
// Gebruik: node build.mjs [paginanaam ...]
import { chromium } from '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('.', import.meta.url).pathname;
const OUT = join(ROOT, 'out');
const DEST = join(homedir(), 'Downloads', 'mockups-tvos');
mkdirSync(OUT, { recursive: true });
mkdirSync(DEST, { recursive: true });

const S = (d, extra = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
const ICONS = {
  search: S('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', 'stroke-width="2.4"'),
  back: S('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'),
  chev: S('<path d="m9 6 6 6-6 6"/>'),
  chevd: S('<path d="m6 9 6 6 6-6"/>'),
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
  pause: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  minus: S('<path d="M5 12h14"/>'),
  info: S('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
  check: S('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.8"'),
  close: S('<path d="m6 6 12 12M18 6 6 18"/>'),
  download: S('<path d="M12 4v11m0 0 4-4m-4 4-4-4M5 19h14"/>'),
  bell: S('<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 21h4"/>'),
  gear: S('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  person: S('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  people: S('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-5-6.3"/>'),
  swap: S('<path d="M4 7h13l-3-3M20 17H7l3 3"/>'),
  star: S('<path d="m12 3 2.8 5.8 6.2.9-4.5 4.4 1.1 6.3L12 17.5l-5.6 2.9 1.1-6.3L3 9.7l6.2-.9z"/>'),
  thumb: S('<path d="M7 10v11H3V10zM7 10l4-7c1.5 0 2.5 1 2.5 2.5V9H20a2 2 0 0 1 2 2l-1.5 8a2 2 0 0 1-2 2H7"/>'),
  eye: S('<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  eyeoff: S('<path d="M3 3l18 18M10.5 10.6a2.5 2.5 0 0 0 3.4 3.4M7 7.2C4.5 8.7 2 12 2 12s3.5 6 10 6c1.6 0 3-.3 4.2-.9M12 6c6.5 0 10 6 10 6s-1 1.8-2.9 3.5"/>'),
  trash: S('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>'),
  edit: S('<path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4"/>'),
  tv: S('<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8"/>'),
  server: S('<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>'),
  folder: S('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
  activity: S('<path d="M3 12h4l3-8 4 16 3-8h4"/>'),
  logout: S('<path d="M10 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h5M15 8l4 4-4 4M19 12H9"/>'),
  more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  clock: S('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  lock: S('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  rew: S('<path d="M12 4a8 8 0 1 1-7 4"/><path d="M5 3v5h5"/><text x="8.3" y="15.5" font-size="7" font-weight="700" fill="currentColor" stroke="none">10</text>', 'stroke-width="1.8"'),
  fwd: S('<path d="M12 4a8 8 0 1 0 7 4"/><path d="M19 3v5h-5"/><text x="8.3" y="15.5" font-size="7" font-weight="700" fill="currentColor" stroke="none">10</text>', 'stroke-width="1.8"'),
  cc: S('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10 10.5a2 2 0 1 0 0 3M17 10.5a2 2 0 1 0 0 3"/>'),
  speed: S('<path d="M4 14a8 8 0 1 1 16 0"/><path d="m12 14 4-5"/>'),
  list: S('<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>'),
  next: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5v14l9-7zM17 5h2v14h-2z"/></svg>',
  audio: S('<path d="M4 10v4h4l5 4V6L8 10zM16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/>'),
  wifi: S('<path d="M2 8.5a16 16 0 0 1 20 0M5.5 12a11 11 0 0 1 13 0M9 15.5a6 6 0 0 1 6 0M12 19h.01"/>'),
  cloudoff: S('<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z"/><path d="m4 4 16 16"/>'),
  refresh: S('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>'),
  live: S('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m7 3 5 3 5-3"/>'),
  rec: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="6"/></svg>',
  bookmark: S('<path d="M6 3h12v18l-6-4-6 4z"/>'),
  requests: S('<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>'),
  film: S('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>'),
  show: S('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  keyboard: S('<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8"/>'),
  mic: S('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'),
  phone: S('<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>'),
  qr: S('<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3M21 14v3M14 21h3M21 21h-1"/>'),
  plex: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 3h5l7 9-7 9H6l7-9z"/></svg>',
  jellyfin: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3c-2 0-7 9-7 12s3 4 7 4 7-1 7-4-5-12-7-12zm0 6c1 0 3.5 4.5 3.5 6S13 16 12 16s-3.5 0-3.5-1 2.5-6 3.5-6z"/></svg>',
  pleya: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 3h8a5 5 0 0 1 0 10h-4v8H6zm4 3v4h4a2 2 0 0 0 0-4z"/></svg>',
  sort: S('<path d="M7 4v16m0 0-3-3m3 3 3-3M17 20V4m0 0-3 3m3-3 3 3"/>'),
  filter: S('<path d="M4 6h16M7 12h10M10 18h4"/>'),
  grid: S('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'),
  collection: S('<rect x="3" y="7" width="14" height="14" rx="2"/><path d="M7 3h14v14"/>'),
  playlist: S('<path d="M3 6h12M3 12h12M3 18h8M17 14v6M15 17h4"/>'),
  music: S('<circle cx="7" cy="17" r="3"/><circle cx="17" cy="15" r="3"/><path d="M10 17V5l10-2v12"/>'),
  photo: S('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="m21 16-5-5-8 8"/>'),
  moon: S('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>'),
  sun: S('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  sleep: S('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/><path d="M15 3h4l-4 4h4"/>'),
  captions: S('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 15h5M14 15h3M7 11h3M12 11h5"/>'),
  camera: S('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3"/>'),
  monitor: S('<rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>'),
  ring: S('<circle cx="12" cy="12" r="9"/>'),
};

const NAV = ['Home', 'Series', 'Films', 'Live TV', 'Mijn Pleya'];
function topnav(active, opts = {}) {
  const items = NAV.filter(n => !(n === 'Live TV' && !opts.live));
  const chip = opts.avatar ? `<img src="../assets/avatar.jpg" alt="">` : 'M';
  return `<nav class="topnav${opts.dim ? ' dim' : ''}"><div class="chip">${chip}</div><div class="cluster">
${ICONS.search.replace('class="ic"', 'class="ic search"')}
${items.map(n => `<div class="item${n === active ? ' on' : ''}${opts.focusNav === n ? ' focus' : ''}">${n}</div>`).join('')}
</div><div class="wordmark"><img src="../assets/pleya_wordmark.png" alt="Pleya"></div></nav>`;
}

function render(src) {
  return src
    .replace(/\{\{icon:(\w+)\}\}/g, (_, n) => { if (!ICONS[n]) throw new Error('icon ' + n); return ICONS[n]; })
    .replace(/\{\{nav:([^}|]+)(?:\|([^}]*))?\}\}/g, (_, a, f) => {
      const flags = (f ?? '').split(',').filter(Boolean);
      const focusNav = flags.find(x => x.startsWith('focus='))?.slice(6);
      return topnav(a.trim(), { live: flags.includes('live'), dim: flags.includes('dim'), avatar: flags.includes('avatar'), focusNav });
    })
    .replace(/\{\{art:([\w-]+)\}\}/g, (_, n) => `../art/${n}.jpg`);
}

const wanted = process.argv.slice(2);
const pages = readdirSync(join(ROOT, 'pages')).filter(f => f.endsWith('.html') && (wanted.length === 0 || wanted.some(w => f.includes(w)))).sort();
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, colorScheme: 'dark' });
const page = await ctx.newPage();
for (const f of pages) {
  const name = basename(f, '.html');
  const html = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>${name}</title><link rel="stylesheet" href="../tv.css"></head><body>${render(readFileSync(join(ROOT, 'pages', f), 'utf8'))}</body></html>`;
  const out = join(OUT, f);
  writeFileSync(out, html);
  await page.goto('file://' + out, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  const png = join(DEST, name + '.png');
  await page.screenshot({ path: png });
  console.log('shot', png);
}
await browser.close();
