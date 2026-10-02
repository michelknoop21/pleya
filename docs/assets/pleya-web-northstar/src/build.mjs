// Bouwt pages/*.html (fragmenten met {{tokens}}) naar out/*.html en schiet elke
// pagina op de breedtes uit zijn eigen kopregel. Zelfde werkwijze als
// docs/assets/tvos-unified/src/build.mjs op main en ~/Downloads/mockups/_src
// (iOS): één HTML-bron per scherm, tokens in web.css, artwork buiten git.
//
// Gebruik: node build.mjs [paginanaam ...]
//   PLEYA_ART=/pad/naar/art   overrulet de artworkmap (standaard: de iOS-set,
//                              met de TV-set als terugval)
//   PLEYA_OUT=/pad             overrulet de map waar de jpg's landen
import { chromium } from '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('.', import.meta.url).pathname;
const OUT = join(ROOT, 'out');
const DEST = process.env.PLEYA_OUT ?? join(ROOT, '..');
const ART_DIRS = [
  process.env.PLEYA_ART,
  join(homedir(), 'Downloads', 'mockups', '_src', 'art'),
  join(homedir(), 'Downloads', 'mockups-tvos', '_src', 'art'),
].filter(Boolean);
mkdirSync(OUT, { recursive: true });
mkdirSync(DEST, { recursive: true });

// Breedtes: ScreenBreakpoints uit lib/utils/layout_constants.dart (600/900/1200/1600)
// en de vijf e2e-breedtes van pleya_web. 1600 = brede desktop, 1280 = compacte
// desktop, 1024 = tablet-breedte browser, 393 = iPhone 15 Pro (zoals de iOS-set).
const VIEWPORTS = {
  1600: { width: 1600, height: 1000, scale: 1 },
  1280: { width: 1280, height: 800, scale: 1 },
  1024: { width: 1024, height: 768, scale: 1 },
  834: { width: 834, height: 1112, scale: 1 },
  393: { width: 393, height: 852, scale: 2 },
};

const S = (d, extra = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
const ICONS = {
  search: S('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', 'stroke-width="2.4"'),
  back: S('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'),
  chev: S('<path d="m9 6 6 6-6 6"/>'),
  chevd: S('<path d="m6 9 6 6 6-6"/>'),
  chevl: S('<path d="m15 6-6 6 6 6"/>'),
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
  pause: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  stop: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  minus: S('<path d="M5 12h14"/>'),
  info: S('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
  check: S('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.8"'),
  close: S('<path d="m6 6 12 12M18 6 6 18"/>'),
  download: S('<path d="M12 4v11m0 0 4-4m-4 4-4-4M5 19h14"/>'),
  upload: S('<path d="M12 19V8m0 0-4 4m4-4 4 4M5 5h14"/>'),
  bell: S('<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 21h4"/>'),
  gear: S('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  person: S('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  people: S('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-5-6.3"/>'),
  eye: S('<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  eyeoff: S('<path d="M3 3l18 18M10.5 10.6a2.5 2.5 0 0 0 3.4 3.4M7 7.2C4.5 8.7 2 12 2 12s3.5 6 10 6c1.6 0 3-.3 4.2-.9M12 6c6.5 0 10 6 10 6s-1 1.8-2.9 3.5"/>'),
  trash: S('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>'),
  edit: S('<path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4"/>'),
  tv: S('<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8"/>'),
  server: S('<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>'),
  folder: S('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
  drive: S('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 12h.01M11 12h6"/>'),
  activity: S('<path d="M3 12h4l3-8 4 16 3-8h4"/>'),
  logout: S('<path d="M10 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h5M15 8l4 4-4 4M19 12H9"/>'),
  more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  clock: S('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  lock: S('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  key: S('<circle cx="8" cy="15" r="4"/><path d="m10.8 12.2 8.2-8.2M15 7l3 3M18 4l2 2"/>'),
  shield: S('<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>'),
  cc: S('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10 10.5a2 2 0 1 0 0 3M17 10.5a2 2 0 1 0 0 3"/>'),
  list: S('<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>'),
  audio: S('<path d="M4 10v4h4l5 4V6L8 10zM16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/>'),
  wifi: S('<path d="M2 8.5a16 16 0 0 1 20 0M5.5 12a11 11 0 0 1 13 0M9 15.5a6 6 0 0 1 6 0M12 19h.01"/>'),
  cloudoff: S('<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z"/><path d="m4 4 16 16"/>'),
  refresh: S('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>'),
  bookmark: S('<path d="M6 3h12v18l-6-4-6 4z"/>'),
  film: S('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>'),
  show: S('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  book: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M3 5.5C5.5 4.5 8.5 4.5 11 6v13.5c-2.5-1.5-5.5-1.5-8-.5zM13 6c2.5-1.5 5.5-1.5 8-.5V19c-2.5-1-5.5-1-8 .5z"/></svg>',
  bookline: S('<path d="M3 5.5C5.5 4.5 8.5 4.5 11 6v13.5c-2.5-1.5-5.5-1.5-8-.5zM13 6c2.5-1.5 5.5-1.5 8-.5V19c-2.5-1-5.5-1-8 .5z"/>'),
  home: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3 3 11h2.5v9h5v-6h3v6h5v-9H21z"/></svg>',
  homeline: S('<path d="M3 11 12 3l9 8M5 10v10h5v-6h4v6h5V10"/>'),
  sort: S('<path d="M7 4v16m0 0-3-3m3 3 3-3M17 20V4m0 0-3 3m3-3 3 3"/>'),
  filter: S('<path d="M4 6h16M7 12h10M10 18h4"/>'),
  grid: S('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'),
  collection: S('<rect x="3" y="7" width="14" height="14" rx="2"/><path d="M7 3h14v14"/>'),
  alert: S('<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>'),
  globe: S('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'),
  cpu: S('<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>'),
  chart: S('<path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/>'),
  image: S('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="m21 16-5-5-8 8"/>'),
  tag: S('<path d="M3 12V4h8l10 10-8 8z"/><path d="M7.5 8h.01"/>'),
  link: S('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'),
  moon: S('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>'),
  sun: S('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  playlist: S('<path d="M3 6h12M3 12h12M3 18h8M17 14v6M15 17h4"/>'),
  music: S('<circle cx="7" cy="17" r="3"/><circle cx="17" cy="15" r="3"/><path d="M10 17V5l10-2v12"/>'),
  copy: S('<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>'),
  ext: S('<path d="M14 4h6v6M20 4l-9 9M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>'),
  scan: S('<path d="M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3M3 12h18"/>'),
  x: S('<path d="m6 6 12 12M18 6 6 18"/>'),
  reader: S('<path d="M4 5h6a3 3 0 0 1 3 3v12a2 2 0 0 0-2-2H4zM20 5h-6a3 3 0 0 0-3 3v12a2 2 0 0 1 2-2h7z"/>'),
  share: S('<path d="M21 3 10 14M21 3l-7 18-4-7-7-4z"/>'),
  thumb: S('<path d="M7 10v11H3V10zM7 10l4-7c1.5 0 2.5 1 2.5 2.5V9H20a2 2 0 0 1 2 2l-1.5 8a2 2 0 0 1-2 2H7"/>'),
};

// CSS-getekende boekcovers, dezelfde zes-plus-vijf als de e-booksgoldens (feat/ebooks,
// lib/books/books_source.dart). Commerciële covers horen niet in de repository.
const COVERS = {
  dune: { base: '#3A1A0B', accent: '#E08A3C', ink: '#F7E2C6', shape: 'orb', title: 'Dune', author: 'Frank Herbert' },
  hailmary: { base: '#101010', accent: '#F6C62D', ink: '#111111', shape: 'diag', title: 'Project Hail Mary', author: 'Andy Weir', sans: true },
  sapiens: { base: '#EFE7D8', accent: '#3A2F22', ink: '#B3261E', shape: 'rings', title: 'Sapiens', author: 'Yuval Noah Harari' },
  nineteen: { base: '#0C0C0C', accent: '#CFD6DE', ink: '#E5140F', shape: 'eye', title: '1984', author: 'George Orwell', sans: true },
  alchemist: { base: '#C8401A', accent: '#F7B545', ink: '#FFF3DF', shape: 'orb', title: 'De Alchemist', author: 'Paulo Coelho' },
  atomic: { base: '#F4F2EC', accent: '#E5140F', ink: '#111111', shape: 'plain', title: 'Atomic Habits', author: 'James Clear', sans: true },
  messiah: { base: '#0D3742', accent: '#EF9A3A', ink: '#F1E6D0', shape: 'orb', title: 'Dune Messiah', author: 'Frank Herbert' },
  children: { base: '#5C1A12', accent: '#A33A1F', ink: '#F6D9C4', shape: 'orb', title: 'Children of Dune', author: 'Frank Herbert' },
  sisters: { base: '#163B4A', accent: '#E8E4EA', ink: '#EAF2F6', shape: 'orb', title: 'De Zeven Zussen', author: 'Lucinda Riley' },
  hobbit: { base: '#15522F', accent: '#CFE7C6', ink: '#EAF5D8', shape: 'orb', title: 'De Hobbit', author: 'J.R.R. Tolkien' },
  brave: { base: '#4A140E', accent: '#CFD6DE', ink: '#F6D9C4', shape: 'plain', title: 'Brave New World', author: 'Aldous Huxley' },
  zoutpad: { base: '#2B3A2E', accent: '#D8C9A2', ink: '#F1EEDB', shape: 'diag', title: 'Het Zoutpad', author: 'Raynor Winn' },
};
function cover(id, progress) {
  const c = COVERS[id];
  if (!c) throw new Error(`onbekende cover: ${id}`);
  let motif = '';
  if (c.shape === 'orb') motif = `<div class="orb" style="background:radial-gradient(circle at 35% 30%, #fff8 0, ${c.accent} 35%, ${c.base} 100%);box-shadow:0 0 40px ${c.accent}66"></div>`;
  if (c.shape === 'rings') motif = `<div class="rings" style="color:${c.accent}"></div>`;
  if (c.shape === 'eye') motif = `<div class="eye" style="color:${c.accent}"></div>`;
  if (c.shape === 'diag') motif = `<div class="diag" style="background:${c.accent}"></div>`;
  const prog = progress != null ? `<div class="prog-cov"><i style="width:${progress}%"></i></div>` : '';
  return `<div class="cover" style="background:${c.base};color:${c.ink}">${motif}<div class="au" style="position:relative">${c.author}</div><div class="ti${c.sans ? ' sans' : ''}" style="position:relative">${c.title}</div>${prog}</div>`;
}
function ambience(id) {
  const c = COVERS[id];
  return `background:radial-gradient(120% 90% at 80% 40%, ${c.accent}55 0, ${c.base} 55%, #141414 100%)`;
}

function art(name) {
  for (const d of ART_DIRS) {
    const p = join(d, name + '.jpg');
    if (existsSync(p)) return 'file://' + p;
  }
  console.warn(`  ! artwork ontbreekt: ${name}`);
  return '';
}

const NAV = [
  ['home', 'Home', '/'], ['series', 'Series', '/series'], ['films', 'Films', '/films'], ['books', 'Boeken', '/books'], ['my', 'Mijn Pleya', '/my'],
];
const TAB_ICON = { home: 'home', series: 'show', films: 'film', books: 'book', my: null };

// {{shell:active|opties}}  opties: nav=Titel (mobiele terugkop), admin (toont Beheer in de topnav),
// noadmin (gebruiker zonder beheerrecht), q=zoekterm, nobooks (geen Boeken-slot, dan Live TV of Downloads valt weg: hier gewoon vier)
function shell(active, opts = {}) {
  const items = NAV.filter(([id]) => !(opts.nobooks && id === 'books'));
  const cluster = items.map(([id, label]) => `<a class="item${id === active ? ' on' : ''}" href="#">${label}</a>`).join('');
  const adminLink = opts.noadmin ? '' : `<a class="item admin${active === 'admin' ? ' on' : ''}" href="#" title="Serverbeheer">${ICONS.gear}Beheer</a>`;
  const search = opts.q
    ? `<div class="search-inline">${ICONS.search}<b>${opts.q}</b></div>`
    : `<div class="search-inline">${ICONS.search}Zoeken</div>`;
  const top = `<nav class="topnav"><div class="brand"><img src="../assets/pleya_wordmark.png" alt="Pleya"></div><div class="cluster">${cluster}</div><div class="actions">${search}${adminLink}<img class="avatar" src="../assets/avatar.jpg" alt=""></div></nav>`;
  const navAction = opts.navAction === undefined
    ? ICONS.more.replace('class="ic"', 'class="ic more"')
    : (opts.navAction && ICONS[opts.navAction] ? ICONS[opts.navAction].replace('class="ic"', 'class="ic more"') : '');
  const mhead = opts.nav !== undefined
    ? `<header class="mhead nav">${ICONS.back.replace('class="ic"', 'class="ic back"')}<div class="title">${opts.nav === true ? '' : opts.nav}</div>${navAction}</header>`
    : `<header class="mhead"><img class="wordmark" src="../assets/pleya_wordmark.png" alt="Pleya"><div class="actions">${ICONS.search}<img class="avatar" src="../assets/avatar.jpg" alt=""></div></header>`;
  const tabs = items.map(([id, label]) => {
    const icon = id === 'my' ? `<img src="../assets/avatar.jpg" alt="">` : ICONS[TAB_ICON[id]];
    return `<a class="tab${id === active ? ' on' : ''}" href="#">${icon}<span>${label}</span></a>`;
  }).join('');
  return `${top}${mhead}<nav class="tabbar">${tabs}</nav>`;
}

const ADMIN_NAV = [
  ['overview', 'Overzicht', 'chart'], ['libraries', 'Bibliotheken', 'folder'], ['storage', 'Opslag', 'drive'], ['activity', 'Scans en taken', 'activity'],
  ['users', 'Gebruikers', 'people'], ['media', 'Media en streaming', 'play'], ['metadata', 'Metadata en artwork', 'image'],
  ['network', 'Netwerk', 'globe'], ['security', 'Beveiliging', 'shield'], ['diagnostics', 'Diagnostiek', 'cpu'],
];
// {{admin:section|badges=activity:1,storage:!}}
function adminNav(active, badges = {}) {
  const links = ADMIN_NAV.map(([id, label, icon]) => {
    const b = badges[id];
    const badge = b ? `<span class="bd${b === '!' ? ' red' : ''}">${b === '!' ? '!' : b}</span>` : '';
    return `<a class="nl${id === active ? ' on' : ''}" href="#">${ICONS[icon]}${label}${badge}</a>`;
  }).join('');
  return `<aside class="admin-nav"><div class="head">Serverbeheer</div>${links}<div class="sep"></div><a class="nl" href="#">${ICONS.chevl}Terug naar Pleya</a></aside>`;
}

// {{card:slug|Titel|Onderregel|opties}}  opties: prog=40, seen, new, src=2 bronnen, wide, hover, focus, over, badge=NIEUW
function card(slug, title, sub, o = {}) {
  const cls = ['card', o.wide ? 'wide' : '', o.hover ? 'hover' : '', o.focus ? 'focus' : ''].filter(Boolean).join(' ');
  const bits = [];
  if (o.src) bits.push(`<span class="badge-src">${o.src}</span>`);
  if (o.seen) bits.push(`<span class="seen">${ICONS.check}</span>`);
  if (o.new) bits.push(`<span class="dot-new"></span>`);
  if (o.badge) bits.push(`<span class="badge-new">${o.badge}</span>`);
  if (o.over) bits.push(`<div class="over"><span class="pl">${ICONS.play}</span><span class="sm">${ICONS.plus}</span><span class="sm">${ICONS.more}</span></div>`);
  if (o.prog) bits.push(`<div class="prog"><i style="width:${o.prog}%"></i></div>`);
  const cap = title ? `<div class="cap"><div class="t">${title}</div>${sub ? `<div class="s">${sub}</div>` : ''}</div>` : '';
  const file = slug.endsWith('-backdrop') ? slug : slug + '-poster';
  return `<div class="${cls}"><div class="art"><img src="${art(file)}" alt="">${bits.join('')}</div>${cap}</div>`;
}
// {{bookcard:id|prog|opties}}
function bookcard(id, prog, o = {}) {
  const c = COVERS[id];
  const cls = ['card', o.hover ? 'hover' : '', o.focus ? 'focus' : ''].filter(Boolean).join(' ');
  return `<div class="${cls}"><div class="art">${cover(id, prog)}${o.new ? '<span class="dot-new"></span>' : ''}</div><div class="cap"><div class="t">${c.title}</div><div class="s">${o.sub ?? c.author}</div></div></div>`;
}
// {{readcard:id|48|Hoofdstuk 12}}
function readcard(id, pct, label) {
  const c = COVERS[id];
  return `<div class="read-card"><div class="amb" style="${ambience(id)}"></div><div class="body"><div class="t">${c.title}</div><div class="s">${c.author}</div><div class="p">${pct}% · ${label}</div><div class="bar"><i style="width:${pct}%"></i></div></div><div class="cov" style="font-size:12px">${cover(id)}</div></div>`;
}
// {{ep:slug|S1 · A3|Titel|duur|synopsis|opties}} opties: prog=40, seen
function ep(slug, num, title, dur, syn, o = {}) {
  const bits = [];
  if (o.prog) bits.push(`<div class="prog"><i style="width:${o.prog}%"></i></div>`);
  if (o.seen) bits.push(`<span class="seen">${ICONS.check}</span>`);
  return `<div class="ep"><div class="th"><img src="${art(slug.endsWith('-backdrop') ? slug : slug + '-backdrop')}" alt=""><span class="num">${num}</span>${bits.join('')}</div><div class="body"><div class="t"><span>${title}</span>${ICONS.download}</div><div class="d">${dur}</div><div class="syn">${syn}</div></div></div>`;
}

// Kaartopties staan in één segment, gescheiden door komma's: prog=40,seen,src=2 bronnen
function parseCardOpts(s) {
  const o = {};
  for (const part of (s ?? '').replace(/^\|/, '').split(',').map((x) => x.trim()).filter(Boolean)) {
    const [k, v] = part.split('=');
    o[k] = v ?? true;
  }
  return o;
}

function parseOpts(s) {
  const o = {};
  for (const part of (s ?? '').split('|').filter(Boolean)) {
    const [k, v] = part.split('=');
    o[k] = v ?? true;
  }
  return o;
}

function expand(src) {
  return src
    .replace(/\{\{shell:([a-z]+)(\|[^}]*)?\}\}/g, (_, a, o) => shell(a, parseOpts(o)))
    .replace(/\{\{admin:([a-z]+)(\|[^}]*)?\}\}/g, (_, a, o) => {
      const opts = parseOpts(o);
      const badges = {};
      for (const kv of (opts.badges ? String(opts.badges).split(',') : [])) { const [k, v] = kv.split(':'); badges[k] = v; }
      return adminNav(a, badges);
    })
    .replace(/\{\{card:([a-z0-9-]+)\|([^|}]*)\|([^|}]*)(\|[^}]*)?\}\}/g, (_, s, t, sub, o) => card(s, t, sub, parseCardOpts(o)))
    .replace(/\{\{bookcard:([a-z]+)(?:\|(\d*))?(\|[^}]*)?\}\}/g, (_, id, p, o) => bookcard(id, p ? Number(p) : null, parseCardOpts(o)))
    .replace(/\{\{readcard:([a-z]+)\|(\d+)\|([^}]*)\}\}/g, (_, id, p, l) => readcard(id, Number(p), l))
    .replace(/\{\{ep:([a-z0-9]+)\|([^|}]*)\|([^|}]*)\|([^|}]*)\|([^|}]*)(\|[^}]*)?\}\}/g, (_, s, n, t, d, syn, o) => ep(s, n, t, d, syn, parseCardOpts(o)))
    .replace(/\{\{icon:([a-z]+)\}\}/g, (_, n) => { if (!ICONS[n]) throw new Error(`onbekend icoon: ${n}`); return ICONS[n]; })
    .replace(/\{\{art:([a-z0-9-]+)\}\}/g, (_, n) => art(n))
    .replace(/\{\{cover:([a-z]+)(?::(\d+))?\}\}/g, (_, id, p) => cover(id, p == null ? null : Number(p)))
    .replace(/\{\{amb:([a-z]+)\}\}/g, (_, id) => ambience(id));
}

const wanted = process.argv.slice(2);
const pages = readdirSync(join(ROOT, 'pages')).filter((f) => f.endsWith('.html')).sort()
  .filter((f) => wanted.length === 0 || wanted.some((w) => f.startsWith(w)));

const browser = await chromium.launch();
for (const file of pages) {
  const name = basename(file, '.html');
  const src = readFileSync(join(ROOT, 'pages', file), 'utf8');
  const m = src.match(/<!--\s*widths:\s*([0-9, ]+)\s*-->/);
  const widths = m ? m[1].split(',').map((s) => Number(s.trim())) : [1600, 393];
  const html = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${name}</title><link rel="stylesheet" href="../web.css"></head><body>${expand(src)}</body></html>`;
  const outHtml = join(OUT, name + '.html');
  writeFileSync(outHtml, html);
  for (const w of widths) {
    const vp = VIEWPORTS[w];
    if (!vp) throw new Error(`geen viewport voor breedte ${w}`);
    const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: vp.scale, colorScheme: 'dark' });
    const page = await ctx.newPage();
    await page.goto('file://' + outHtml);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const dest = join(DEST, `${name}@${w}.jpg`);
    // Smal (telefoon) is één schermvulling met de tabbalk onderaan, zoals de iOS-set;
    // breed is de hele pagina, want daar scrolt de topnav mee als sticky.
    await page.screenshot({ path: dest, fullPage: vp.width > 600, type: 'jpeg', quality: 90 });
    await ctx.close();
    console.log(`${name}@${w} -> ${dest}`);
  }
}
await browser.close();
