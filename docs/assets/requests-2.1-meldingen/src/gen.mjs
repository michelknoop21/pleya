// Requests 2.1, meldingen en notificaties (voorstel onder A-20/A-21). Vult de goedgekeurde set
// ../../requests-2.0 aan met de families 9 tot en met 12 en raakt die set niet aan: hij leest
// alleen haar rq.css. Schrijft out/*.html, de beelden in ../tv ../phone ../tablet ../desktop,
// ../manifest.json, ../index.html en de dekkingsmatrix in ../README.md.
// Gebruik: node gen.mjs [filter ...] [--no-render]
// Playwright: PLEYA_MOCKUP_PLAYWRIGHT, anders /opt/node-tools of de Homebrew-installatie.
import { writeFileSync, readFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('.', import.meta.url).pathname;
const SET = join(ROOT, '..');
const OUT = join(ROOT, 'out');
const TVSRC = '../../../tvos-unified/src';
const RQCSS = '../../../requests-2.0/src/rq.css';
const ARTDIR = '../../../ios-unified/detail-2026';
const problems = [];
const STATUS = { short: 'VOORSTEL', long: 'Voorstel, nog niet goedgekeurd. Aanvulling op de goedgekeurde set Requests 2.0 (A-20, 8 oktober 2026); Probleem melden is nieuwe scope en wacht op een besluit van Michel' };

// ---------- iconen (zelfde tekening als requests-2.0, plus wat meldingen nodig hebben) ----------
const sv = (d, x = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${x}>${d}</svg>`;
const I = {
  search: sv('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', 'stroke-width="2.4"'),
  back: sv('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'),
  chev: sv('<path d="m9 6 6 6-6 6"/>'),
  chevd: sv('<path d="m6 9 6 6 6-6"/>'),
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
  pause: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>',
  plus: sv('<path d="M12 5v14M5 12h14"/>'),
  info: sv('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
  warn: sv('<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>'),
  check: sv('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.8"'),
  close: sv('<path d="m6 6 12 12M18 6 6 18"/>'),
  person: sv('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  clock: sv('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  lock: sv('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  refresh: sv('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>'),
  requests: sv('<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>'),
  film: sv('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>'),
  show: sv('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  home: sv('<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4z"/>'),
  live: sv('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m7 3 5 3 5-3"/>'),
  cloudoff: sv('<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z"/><path d="m4 4 16 16"/>'),
  flag: sv('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'),
  bell: sv('<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>'),
  belloff: sv('<path d="M6 16V11a6 6 0 0 1 9.3-5M18 11v5l2 2H8"/><path d="M10 21h4M3 3l18 18"/>'),
  chat: sv('<path d="M4 5h16v11H9l-5 4z"/>'),
  send: sv('<path d="m4 12 16-8-6 16-2-6z"/>'),
  gear: sv('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>'),
  image: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m21 16-5-5-8 8"/>'),
  audio: sv('<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>'),
  cc: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10.5 10.2a2.3 2.3 0 1 0 0 3.6M17 10.2a2.3 2.3 0 1 0 0 3.6"/>'),
  other: sv('<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.4M12 17v.5"/>'),
  list: sv('<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>'),
  eye: sv('<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  dl: sv('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>'),
  speed: sv('<path d="M12 14l4-4"/><path d="M4 18a9 9 0 1 1 16 0"/>'),
  rew: sv('<path d="M11 18 4 12l7-6zM20 18l-7-6 7-6z"/>'),
  fwd: sv('<path d="m13 6 7 6-7 6zM4 6l7 6-7 6z"/>'),
  airplay: sv('<path d="M5 17H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1h-1"/><path d="m12 15 5 6H7z"/>'),
  inbox: sv('<path d="M3 13h5l1 3h6l1-3h5"/><path d="M5 5h14l2 8v6H3v-6z"/>'),
};
const TYPE = { video: ['Beeld', I.image], audio: ['Geluid', I.audio], sub: ['Ondertiteling', I.cc], other: ['Overig', I.other] };

// ---------- fixture ----------
// Blender-openfilms uit detail-2026; de rest zijn getekende covers met FIXTURE erop. Geen titel,
// naam of server komt van een echt toestel.
const IT = {
  charge: { t: 'Charge', y: 2022, g: 'Actie', k: 'Film', len: '1u 32m', img: 'charge-poster' },
  sintel: { t: 'Sintel', y: 2010, g: 'Fantasy', k: 'Film', len: '1u 28m', img: 'sintel-poster', wide: 'sintel-wide' },
  tears: { t: 'Tears of Steel', y: 2012, g: 'Sciencefiction', k: 'Film', len: '1u 41m', img: 'tears-poster' },
  spring: { t: 'Spring', y: 2019, g: 'Animatie', k: 'Film', len: '1u 18m', img: 'spring-poster' },
  camin: { t: 'Caminandes', y: 2013, g: 'Animatie', k: 'Serie', n: 3, len: '3 seizoenen', img: 'caminandes-poster', wide: 'bbb-wide' },
  dweebs: { t: 'Dweebs', y: 2021, g: 'Komedie', k: 'Serie', n: 2, len: '2 seizoenen', img: 'dweebs-poster' },
  eleph: { t: 'Elephants Dream', y: 2006, g: 'Sciencefiction', k: 'Film', len: '1u 24m', img: 'elephants-poster' },
  wad: { t: 'Wadlopers', y: 2023, g: 'Drama', k: 'Serie', n: 5, len: '5 seizoenen', h: 196 },
  glas: { t: 'Glasstad', y: 2024, g: 'Thriller', k: 'Film', len: '1u 49m', h: 286 },
  nacht: { t: 'Nachttrein', y: 2024, g: 'Thriller', k: 'Serie', n: 2, len: '2 seizoenen', h: 250 },
  kust: { t: 'Kustlijn', y: 2022, g: 'Drama', k: 'Serie', n: 3, len: '3 seizoenen', h: 172 },
  onder: { t: 'Onderstroom', y: 2021, g: 'Misdaad', k: 'Serie', n: 4, len: '4 seizoenen', h: 340 },
};
const USER = 'Sanne', MGR = 'Michel', SRV = 'Thuis';
const hasFocus = p => p === 'tv' || p === 'dk';
const art = (it, wide) => (wide && it.wide) ? `<img src="${ARTDIR}/${it.wide}.jpg" alt="">` : it.img ? `<img src="${ARTDIR}/${it.img}.jpg" alt="">` : `<div class="fx" style="--h:${it.h}"><b>${it.t}</b><i>FIXTURE</i></div>`;
const cap = (k, l, inl) => `<span class="cap ${k}${inl ? ' inl' : ''}"><i class="d"></i>${l}</span>`;
const btn = (l, o = {}) => `<span class="b ${o.k ?? ''}${o.focus ? ' focus' : ''}${o.dis ? ' dis' : ''}">${o.busy ? '<i class="spin"></i>' : ''}${o.ic ?? ''}${l}</span>`;
const msg = (k, b, t, bt) => `<div class="msg ${k}">${{ info: I.info, warn: I.warn, err: I.warn, ok: I.check }[k]}<div><b>${b}</b><span>${t}</span></div>${bt ?? ''}</div>`;
const empty = (ic, h, t, btns) => `<div class="empty">${ic}<h2>${h}</h2><p>${t}</p>${btns ? `<div class="brow">${btns}</div>` : ''}</div>`;
const tag = (t, k = '') => `<span class="tagx ${k}">${t}</span>`;
const ty = (k, extra = '') => `<span class="ty${extra}">${TYPE[k][1]}${TYPE[k][0]}</span>`;
const tyi = k => `<span class="tyi">${TYPE[k][1]}</span>`;
const badge = (n, q) => `<span class="badge${q ? ' quiet' : ''}">${n}</span>`;
const hbtn = (ic, n) => `<span class="hbtn">${ic}${n ? badge(n) : ''}</span>`;

// ---------- frames (zelfde shell als requests-2.0) ----------
function topnav(active) {
  return `<nav class="topnav"><div class="chip">M</div><div class="cluster">${I.search.replace('class="ic"', 'class="ic search"')}${['Home', 'Series', 'Films', 'Live TV', 'Mijn Pleya'].map(n => `<div class="item${n === active ? ' on' : ''}">${n}</div>`).join('')}</div><div class="wordmark"><img src="${TVSRC}/assets/pleya_wordmark.png" alt="Pleya"></div></nav>`;
}
const tabbar = `<div class="tabbar"><div>${I.home}Home</div><div>${I.show}Series</div><div>${I.film}Films</div><div>${I.live}Live TV</div><div class="on">${I.person}Mijn Pleya</div></div><div class="homeind"></div>`;
const status = '<div class="status"><span>9:41</span><div class="island"></div><span></span></div>';
const ctxOf = role => role === 'mgr' ? `${MGR} · beheerder · ${SRV}` : `${USER} · ${SRV}`;
function shell(p, o) {
  const tags = [...(o.tags ?? []), `${I.person} ${ctxOf(o.role)}`];
  if (p === 'tv') return `${topnav(o.nav ?? 'Mijn Pleya')}<div class="pg"><div class="head">${o.tvhead ?? `<div class="page-title">${o.title}</div>`}<div class="tags">${tags.map(t => typeof t === 'string' ? tag(t) : tag(t[0], t[1])).join('')}</div></div>${o.body ?? ''}${o.center ?? ''}</div>${o.over ?? ''}`;
  const plain = tags.map(t => typeof t === 'string' ? t : t[0]);
  if (p === 'ph') return `${status}<div class="hdr">${o.hdr ?? `${I.back}<h1>${o.title}</h1>${o.right ?? ''}`}</div>${o.raw ?? `<div class="pg">${o.noctx ? '' : `<div class="ctx">${plain.slice().reverse().join(' · ')}</div>`}${o.top ?? ''}${o.body ?? ''}${o.center ?? ''}</div>`}${o.after ?? ''}${tabbar}${o.over ?? ''}`;
  return `<div class="bar">${I.back}<h1>${o.title}</h1><span class="sub">${plain.slice().reverse().join(' · ')}</span><div class="rt">${o.right ?? ''}</div></div><div class="pg">${o.top ?? ''}${o.body ?? ''}${o.center ?? ''}</div>${o.over ?? ''}`;
}
const sheet = (o) => `<div class="sheet${o.pop ? ' pop' : ''}"><div class="sh-head">${o.it ? `<div class="thumb">${art(o.it)}</div>` : ''}<div><div class="k">${o.k}</div><div class="t">${o.it ? o.it.t : o.title}</div>${o.it || o.sub ? `<div class="s">${o.sub ?? `${o.it.y} · ${o.it.k} · ${o.it.g}`}</div>` : ''}</div></div><div class="sh-body${o.scroll ? ' scroll' : ''}">${o.body}</div>${o.foot ? `<div class="sh-foot">${o.fc ? `<span class="fc">${o.fc}</span>` : ''}<span class="fb">${o.foot}</span></div>` : ''}</div>`;
const sr = (t, o = {}) => `<div class="sr${o.focus ? ' focus' : ''}${o.dis ? ' dis' : ''}${o.danger ? ' danger' : ''}">${o.pre ?? ''}<div class="bb"><div class="t">${t}</div>${o.s ? `<div class="s">${o.s}</div>` : ''}</div>${o.v ? `<span class="v">${o.v}</span>` : ''}${o.ctl ?? ''}</div>`;
const sw = (on, dis) => `<span class="sw${on ? ' on' : ''}${dis ? ' dis' : ''}"></span>`;
const rd = on => `<span class="rd${on ? ' on' : ''}"></span>`;

// ---------- 9. Meldingen afhandelen ----------
// [item, type, waar, door, reacties, datum, open]
const ISS = [
  ['nacht', 'audio', 'Seizoen 1, aflevering 3', 'Ravi', 2, '8 nov', true],
  ['sintel', 'sub', 'Film', USER, 1, '7 nov', true],
  ['camin', 'video', 'Seizoen 2, aflevering 1', 'Ravi', 0, '6 nov', true],
  ['kust', 'sub', 'Seizoen 3, aflevering 2', 'Noor', 3, '4 nov', true],
  ['tears', 'other', 'Film', USER, 0, '3 nov', true],
  ['onder', 'audio', 'Seizoen 4, hele seizoen', 'Ravi', 1, '1 nov', true],
];
const DONE = [
  ['glas', 'video', 'Film', 'Noor', 2, '30 okt', false], ['wad', 'sub', 'Seizoen 2, aflevering 6', USER, 4, '28 okt', false],
  ['eleph', 'audio', 'Film', 'Ravi', 1, '25 okt', false], ['dweebs', 'other', 'Seizoen 1, aflevering 2', 'Noor', 2, '22 okt', false],
  ['spring', 'sub', 'Film', 'Ravi', 1, '20 okt', false], ['charge', 'audio', 'Film', USER, 3, '18 okt', false],
];
const reac = n => n === 0 ? 'geen reactie' : n === 1 ? '1 reactie' : `${n} reacties`;
const irow = (r, p, o = {}) => { const it = IT[r[0]]; const st = r[6] ? cap('wait', 'Open', true) : cap('ok', 'Opgelost', true);
  return `<div class="lrow${o.focus && p === 'dk' ? ' hover' : ''}"><div class="thumb">${art(it)}</div><div class="bb"><div class="t">${it.t}</div><div class="s">${TYPE[r[1]][0]} · ${r[2]}</div><div class="s2">${o.mine ? '' : `door ${r[3]} · `}${reac(r[4])} · ${r[5]}</div></div>${p === 'ph' ? '' : st}${p === 'ph' ? `<div class="acts icon-only">${st}</div>` : `<div class="acts">${btn('', { k: 'icon', ic: I.more })}</div>`}</div>`; };
const icard = (r, p, o = {}) => { const it = IT[r[0]]; return `<div class="card${o.focus ? ' focus' : ''}"><div class="art">${art(it)}${r[6] ? cap('wait', 'Open') : cap('ok', 'Opgelost')}${ty(r[1], ' on-art')}</div><div class="t">${it.t}</div><div class="s">${r[2]}</div><div class="by">${o.mine ? reac(r[4]) : `door ${r[3]} · ${reac(r[4])}`}</div></div>`; };
function ilist(p, o) {
  const mgr = o.role === 'mgr', mine = o.scope === 'mine';
  const sel = o.sel ?? 'Open';
  const cnts = o.counts ?? { Open: 6, Opgelost: 41 };
  const rows = o.rows ?? [];
  const tags = [...(o.count ? [o.count] : []), ...(mgr ? [mine ? 'Bereik: mijn' : 'Bereik: alle'] : [])];
  if (p === 'tv') {
    const filt = `<div class="chipsx" style="margin:26px 0 30px">${mgr ? `<span class="cx${mine ? '' : ' on'}">Alle meldingen</span><span class="cx${mine ? ' on' : ''}">Mijn meldingen</span><span style="width:18px"></span>` : ''}${['Open', 'Opgelost'].map(l => `<span class="cx${l === sel ? ' on' : ''}">${l} <span class="n">${cnts[l]}</span></span>`).join('')}</div>`;
    const grid = rows.length ? `<div class="grid">${rows.map((r, i) => icard(r, p, { focus: i === (o.fi ?? 0), mine })).join('')}</div>` : '';
    return shell(p, { role: o.role, title: 'Meldingen', tags, body: filt + grid, center: o.center });
  }
  const top = `${mgr ? `<div class="seg"><span class="${mine ? '' : 'on'}">Alle meldingen</span><span class="${mine ? 'on' : ''}">Mijn meldingen</span></div>` : ''}<div class="chipsx">${['Open', 'Opgelost'].map(l => `<span class="cx${l === sel ? ' on' : ''}">${l} <span class="n">${cnts[l]}</span></span>`).join('')}${p === 'ph' ? '' : `<span class="cx txt">Nieuwste eerst</span>`}</div>`;
  const n = { ph: 6, tb: 7, dk: 9 }[p];
  const body = rows.length ? `<div class="lrows">${rows.slice(0, n).map((r, i) => irow(r, p, { focus: i === 0, mine })).join('')}</div>` : '';
  return shell(p, { role: o.role, title: 'Meldingen', tags: tags.filter(t => !t.startsWith('Bereik')), top: o.center ? (o.notop ? '' : top) : top, body, center: o.center, right: p === 'ph' ? '' : btn('Probleem melden', { ic: I.flag }) });
}

// detail van een melding
const THREAD = [
  { i: 'R', n: 'Ravi', t: '8 nov · 21:14', x: 'Vanaf ongeveer 12 minuten loopt het geluid een halve seconde achter op het beeld. Op de Apple TV en op mijn telefoon hetzelfde.' },
  { i: 'M', n: MGR, role: 'beheerder', t: '8 nov · 22:02', x: 'Zie het ook. Ik heb een andere release aangevraagd, die komt waarschijnlijk morgen binnen.', me: true },
  { i: 'R', n: 'Ravi', t: '9 nov · 09:30', x: 'Top, dank je. Ik wacht er even mee.' },
];
const convHtml = (extra = []) => `<div class="conv">${[...THREAD, ...extra].map(m => m.evt ? `<div class="evt ${m.k ?? ''}">${m.ic ?? I.check}${m.evt}</div>` : `<div class="cm${m.me ? ' me' : ''}"><div class="av">${m.i}</div><div class="cb2"><div class="who"><b>${m.n}</b>${m.role ? `<span class="rl2">${m.role}</span>` : ''}<span class="tm">${m.t}</span></div><div class="tx">${m.x}</div></div></div>`).join('')}</div>`;
const ISSUE = { it: IT.nacht, ty: 'audio', where: 'Seizoen 1, aflevering 3 · Station Zuid', by: 'Ravi', nr: 128 };
function idetail(p, o) {
  const it = ISSUE.it, open = !o.resolved, f = p === 'tv';
  const st = open ? cap('wait', 'Open', true) : cap('ok', 'Opgelost', true);
  const extra = o.extra ?? [];
  const resolveBtn = open ? btn('Markeren als opgelost', { ic: I.check, focus: f && o.focus === 'resolve' }) : btn('Melding heropenen', { ic: I.refresh, focus: f && o.focus === 'reopen' });
  const composer = `<div class="composer"><div class="fld${o.typed ? ' typed' : ''}">${o.typed ?? 'Schrijf een reactie'}</div>${btn(p === 'ph' ? '' : 'Reactie plaatsen', { k: o.typed ? 'pri' : '', ic: I.send, dis: !o.typed, busy: o.busy })}</div>`;
  if (p === 'ph') {
    const head = `<div class="ihead"><div class="thumb">${art(it)}</div><div class="bb"><div class="t">${it.t}</div><div class="s">${ISSUE.where}</div><div class="tyrow">${ty(ISSUE.ty)}${st}</div></div></div>`;
    return shell(p, { title: `Melding #${ISSUE.nr}`, right: I.more, raw: `<div class="ipg">${head}${o.msg ?? ''}<div class="acts2">${btn('Afspelen', { ic: I.play })}${open ? btn('Opgelost', { ic: I.check }) : btn('Heropenen', { ic: I.refresh })}</div>${convHtml(extra)}</div>`, after: open || o.allowReply ? composer : '' , over: o.over });
  }
  const left = `<div class="lc">${f ? '' : `<div class="poster">${art(it)}</div>`}<div class="kv"><span>Titel</span><b>${it.t}</b><span>Waar</span><b>${ISSUE.where}</b><span>Type</span><b>${TYPE[ISSUE.ty][0]}</b><span>Gemeld door</span><b>${ISSUE.by} · 8 nov</b><span>Server</span><b>${SRV}</b></div><div class="vstack">${btn('Aflevering afspelen', { ic: I.play, focus: f && o.focus === 'play' })}${resolveBtn}${btn('Titel openen', { ic: I.info })}</div></div>`;
  const right = `<div class="rc">${o.msg ?? ''}${convHtml(extra)}${f ? btn('Reageren', { k: 'pri', ic: I.chat, focus: o.focus === 'reply' }) : composer}</div>`;
  if (f) return shell(p, { role: 'mgr', tvhead: `<div><div class="page-title">${it.t}</div><div class="page-sub">Melding #${ISSUE.nr} · ${TYPE[ISSUE.ty][0]} · ${ISSUE.where}</div></div>`, tags: [[open ? 'Open' : 'Opgelost', open ? 'warn' : '']], body: `<div class="cols">${left}${right}</div>`, over: o.over });
  return shell(p, { role: 'mgr', title: `Melding #${ISSUE.nr}`, tags: [], right: `${ty(ISSUE.ty)}${st}${btn('', { k: 'icon', ic: I.more })}`, body: `<div class="cols">${left}${right}</div>`, over: o.over });
}
const issueS = {
  open: p => ilist(p, { role: 'mgr', scope: 'all', count: '6 open', rows: ISS }),
  resolved: p => ilist(p, { role: 'mgr', scope: 'all', sel: 'Opgelost', count: '41 opgelost', rows: DONE }),
  mineEmpty: p => ilist(p, { role: 'user', scope: 'mine', counts: { Open: 0, Opgelost: 0 }, center: empty(I.flag, 'Je hebt nog niets gemeld', 'Hapert het beeld, loopt het geluid niet gelijk of ontbreekt de ondertiteling? Meld het vanaf de titelpagina of in de speler. De beheerder ziet je melding meteen.', btn('Zo meld je een probleem', { k: 'pri', focus: p === 'tv' })) }),
  unavailable: p => ilist(p, { role: 'user', scope: 'mine', notop: true, counts: { Open: '–', Opgelost: '–' }, center: empty(I.lock, 'Meldingen werken niet op deze server', `De aanvraagserver ${SRV} draait een versie zonder meldingen, of dit account mag ze niet zien. Vraag de beheerder om Overseerr of Jellyseerr bij te werken en het recht Meldingen bekijken aan te zetten.`, btn('Terug naar Mijn Pleya', { focus: p === 'tv' })) }),
  error: p => ilist(p, { role: 'mgr', scope: 'all', counts: { Open: '–', Opgelost: '–' }, center: empty(I.cloudoff, 'Meldingen ophalen is mislukt', `De aanvraagserver ${SRV} reageert niet. Je filter blijft staan.`, btn('Opnieuw proberen', { k: 'pri', focus: p === 'tv', ic: I.refresh })) }),
  detail: p => idetail(p, { focus: 'reply' }),
  typing: p => idetail(p, { typed: 'Nieuwe versie staat erop, wil je het nog eens proberen?', focus: 'reply' }),
  unconfirmed: p => idetail(p, { msg: msg('warn', 'Niet bevestigd door de server', 'Je reactie is verstuurd, maar Seerr gaf geen antwoord. Pleya laadt het gesprek opnieuw voordat je hem nog een keer plaatst.', btn('Gesprek verversen', { ic: I.refresh, focus: p === 'tv' })), typed: 'Nieuwe versie staat erop, wil je het nog eens proberen?' }),
  resolved1: p => idetail(p, { resolved: true, focus: 'reopen', extra: [{ i: 'M', n: MGR, role: 'beheerder', t: '9 nov · 18:40', x: 'Nieuwe versie staat erop, geluid loopt nu gelijk.', me: true }, { evt: `${MGR} markeerde dit als opgelost · 9 nov`, k: 'ok' }] }),
  confirm: p => sheet({ k: 'Melding #128 · Geluid', it: IT.nacht, sub: 'Seizoen 1, aflevering 3 · gemeld door Ravi', body: `<div class="sr"><div class="bb"><div class="t">Markeren als opgelost?</div><div class="s">Ravi krijgt een notificatie als die aanstaat. De melding blijft leesbaar onder Opgelost en kan later weer open.</div></div></div>`, foot: btn('Annuleren', { k: 'ghost', focus: p === 'tv' }) + btn('Markeren als opgelost', { k: 'pri' }) }),
  actions: p => sheet({ pop: 1, k: 'Open · gemeld door Ravi', it: IT.nacht, sub: 'Geluid · seizoen 1, aflevering 3', body: sr('Aflevering afspelen', { pre: I.play, focus: p === 'tv' }) + sr('Titel openen', { pre: I.info }) + sr('Reageren', { pre: I.chat }) + sr('Markeren als opgelost', { pre: I.check }), foot: btn('Sluiten') }),
};

// ---------- 10. Probleem melden ----------
function titlePage(p) {
  const it = IT.sintel, meta = `${it.k} · ${it.g} · ${it.y} · ${it.len}`;
  const syn = '<div class="syn">Een eenling trekt door een verlaten land op zoek naar wat ze kwijtraakte, en ontdekt onderweg dat de tocht langer heeft geduurd dan ze dacht. <span style="color:var(--ink-4)">(fixturetekst)</span></div>';
  if (p === 'ph') {
    const ics = [[I.plus, 'Kijklijst'], [I.eye, 'Gezien'], [I.dl, 'Download'], [I.flag, 'Melden', 1]];
    return `<div class="dhero">${art(it, true)}</div><div class="dback">${I.back}</div>${status}<div class="dbody"><h1>${it.t}</h1><div class="meta">${meta}</div><div class="brow" style="flex-direction:column;align-items:stretch;margin-top:14px">${btn('Afspelen', { k: 'pri', ic: I.play })}</div><div style="display:flex;justify-content:space-between;margin:16px 6px 4px">${ics.map(([ic, l, on]) => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px;font-size:12px;color:${on ? 'var(--ink)' : 'var(--ink-3)'}"><span style="width:46px;height:46px;border-radius:50%;display:grid;place-items:center;background:${on ? 'var(--ink)' : 'var(--fill-2)'};color:${on ? 'var(--bg)' : 'var(--ink)'}">${ic.replace('class="ic"', 'class="ic" style="width:20px;height:20px"')}</span>${l}</div>`).join('')}</div>${syn}<div class="facts" style="margin-top:14px"><div>Bron<b>${SRV} · 4K HDR</b></div><div>Audio<b>Engels 5.1</b></div><div>Ondertiteling<b>NL, EN</b></div></div></div>${tabbar}`;
  }
  const f = p === 'tv';
  const btns = btn('Afspelen', { k: 'pri', ic: I.play }) + btn('Kijklijst', { ic: I.plus }) + btn('Probleem melden', { ic: I.flag, focus: f });
  return `<div class="bleed">${art(it, true)}<div class="sc"></div></div>${f ? topnav('Films') : `<div class="bar clear">${I.back}<span class="sub">Films</span><span class="sub" style="margin-left:auto">${ctxOf()}</span></div>`}<div class="htext"><h1>${it.t}</h1><div class="meta">${meta}</div>${syn}<div class="brow">${btns}</div><div class="facts"><div>Bron<b>${SRV} · 4K HDR</b></div><div>Audio<b>Engels 5.1</b></div><div>Ondertiteling<b>Nederlands, Engels</b></div></div></div>`;
}
function playerMenu(p) {
  const it = IT.sintel, f = p === 'tv';
  const menu = `<div class="pmenu"><div class="pmh">Tijdens het kijken</div>${sr('Audio en ondertiteling', { pre: I.cc, v: 'Engels · NL' })}${sr('Afspeelsnelheid', { pre: I.speed, v: '1×' })}${sr('Probleem melden', { pre: I.flag, s: 'Tijdstip 12:04 gaat mee', focus: f })}</div>`;
  return `<div class="player"><div class="vid">${art(it, true)}</div><div class="shade"></div>${p === 'ph' ? status : ''}<div class="ptop">${I.back}<div class="tt">${it.t}<small>${it.y} · ${it.len}</small></div><div class="rt">${I.airplay}${I.cc}</div></div><div class="ctl">${I.rew}<span class="pp">${I.pause}</span>${I.fwd}</div><div class="pbot"><div class="scrub"><i></i><b></b></div><div class="times"><span>12:04</span><span>-1:15:56</span></div></div></div><div class="scrimx" style="background:rgba(0,0,0,.35)"></div>${menu}`;
}
const FCU = `Gemeld als ${USER} bij ${SRV}`;
const rep = (p, o) => { const f = p === 'tv'; return sheet({ k: o.k ?? 'Probleem melden', it: o.it ?? IT.sintel, sub: o.sub, body: o.body(f), foot: o.foot(f), fc: o.fc === undefined ? FCU : o.fc }); };
const typeRows = (sel, f) => Object.entries({ video: 'Haperen, blokjes, zwart beeld of verkeerde verhouding', audio: 'Loopt niet gelijk, valt weg of verkeerde taal', sub: 'Ontbreekt, loopt niet gelijk of verkeerde taal', other: 'Iets anders, beschrijf het in de volgende stap' }).map(([k, s]) => sr(TYPE[k][0], { pre: tyi(k), s, ctl: rd(k === sel), focus: f && k === sel })).join('');
const reportS = {
  title: p => titlePage(p),
  player: p => playerMenu(p),
  type: p => rep(p, { body: f => `<div class="sec">Wat is er mis?</div>${typeRows('audio', f)}`, foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Volgende', { k: 'pri' }) }),
  episode: p => rep(p, { it: IT.camin, sub: '2013 · Serie · 3 seizoenen', body: f => `<div class="pref">${I.info}Ingevuld vanuit de speler</div>${sr('Seizoen', { v: 'Seizoen 2', ctl: I.chevd })}${sr('Aflevering', { v: '1 · Llamigos', ctl: I.chevd, focus: f })}${sr('Geldt voor de hele serie', { s: 'Bijvoorbeeld als elke aflevering zonder ondertiteling is', ctl: sw(false) })}<div class="sec">Type</div>${sr('Beeld', { pre: tyi('video'), s: 'Gekozen in de vorige stap', ctl: I.check })}`, foot: f => btn('Terug', { k: 'ghost' }) + btn('Volgende', { k: 'pri' }) }),
  text: p => rep(p, { sub: 'Geluid · film · tijdstip 12:04', body: f => `<div class="sec">Wat zie of hoor je? <span class="r">optioneel</span></div><div class="ta">Vanaf ongeveer 12 minuten loopt het geluid achter op het beeld. Op de Apple TV en op mijn telefoon<i class="caret"></i><span class="cnt">118 / 500</span></div><div class="pref">${I.clock}Tijdstip 12:04 en de gekozen audiotrack Engels 5.1 gaan mee</div>`, foot: f => btn('Terug', { k: 'ghost' }) + btn('Melding versturen', { k: 'pri', ic: I.send, focus: f }) }),
  sent: p => rep(p, { k: 'Melding verstuurd', sub: 'Geluid · film', body: f => `<div class="big">${I.check}<h3>Gemeld bij ${SRV}</h3><p>De beheerder ziet je melding nu. Reageert iemand of is het opgelost, dan zie je dat onder Meldingen in Mijn Pleya${p === 'tv' ? '' : ' en, als je dat aanzet, als notificatie'}.</p></div>`, foot: f => btn('Bekijk melding', { k: 'ghost' }) + btn('Verder kijken', { k: 'pri', ic: I.play, focus: f }), fc: null }),
  duplicate: p => rep(p, { sub: 'Geluid · film', body: f => msg('info', 'Ravi meldde dit al', 'Op 8 november is er een geluidsmelding voor Sintel gemaakt, en die staat nog open. Reageer daar, dan blijft alles bij elkaar en krijg je dezelfde updates.') + `<div class="lrows" style="margin:.3em;width:auto"><div class="lrow"><div class="tyi">${I.audio}</div><div class="bb"><div class="t">Geluid loopt achter</div><div class="s">door Ravi · 2 reacties · 8 nov</div></div>${cap('wait', 'Open', true)}</div></div>`, foot: f => btn('Toch apart melden', { k: 'ghost' }) + btn('Naar die melding', { k: 'pri', focus: f }) }),
  noRight: p => rep(p, { body: f => msg('err', 'Je mag geen meldingen maken', `Het profiel ${USER} heeft op ${SRV} het recht Problemen melden niet. De beheerder van de aanvraagserver kan dat aanzetten.`), foot: f => btn('Sluiten', { focus: f }), fc: null }),
  error: p => rep(p, { sub: 'Geluid · film · tijdstip 12:04', body: f => msg('err', 'Versturen mislukt', 'Kan de server niet bereiken. Er is niets gemeld; je tekst staat er nog.') + `<div class="ta">Vanaf ongeveer 12 minuten loopt het geluid achter op het beeld. Op de Apple TV en op mijn telefoon hetzelfde.<span class="cnt">131 / 500</span></div>`, foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Opnieuw proberen', { k: 'pri', ic: I.refresh, focus: f }) }),
};

// ---------- 11. Notificaties ----------
const nrow = (o, p) => `<div class="nrow${o.read ? ' read' : ''}${o.focus && hasFocus(p) ? ' focus' : ''}">${o.it ? `<div class="thumb">${art(o.it)}</div>` : `<span class="tyi">${o.ic}</span>`}<div class="bb"><div class="t">${o.t}</div><div class="x">${o.x}</div><div class="k">${o.k}</div></div>${o.read ? '' : '<i class="dot"></i>'}</div>`;
const NOTI = {
  today: [
    { it: IT.charge, t: 'Charge is beschikbaar', x: 'Je aanvraag van 6 oktober staat klaar in Films.', k: 'Aanvragen · 14:02' },
    { ic: I.chat, t: `${MGR} reageerde op je melding`, x: 'Nachttrein, seizoen 1 aflevering 3: “Nieuwe versie staat erop, geluid loopt nu gelijk.”', k: 'Meldingen · 11:40' },
    { it: IT.kust, t: 'Nieuwe aflevering van Kustlijn', x: 'Seizoen 3, aflevering 4 staat in Series.', k: 'Bibliotheek · 08:15' },
  ],
  week: [
    { it: IT.wad, t: 'Wadlopers seizoen 3 goedgekeurd', x: `${MGR} keurde je aanvraag goed. De server haalt het seizoen nu op.`, k: 'Aanvragen · ma', read: 1 },
    { ic: I.check, t: 'Je melding over Sintel is opgelost', x: 'Ondertiteling · de Nederlandse ondertitels lopen weer gelijk.', k: 'Meldingen · zo', read: 1 },
    { ic: `<img src="${TVSRC}/assets/pleya_wordmark.png" alt="" style="width:80%">`, t: 'Pleya 2.9 is er', x: 'Met meldingen en notificaties. Bijwerken via de App Store.', k: 'Pleya · za', read: 1 },
  ],
};
function inbox(p, o = {}) {
  const groups = o.empty ? '' : `<div class="nwrap"><div class="ngrp">Vandaag</div><div class="nlist">${NOTI.today.map((n, i) => nrow({ ...n, focus: i === 0 }, p)).join('')}</div><div class="ngrp">Deze week</div><div class="nlist">${NOTI.week.slice(0, p === 'ph' ? 2 : 3).map(n => nrow(n, p)).join('')}</div></div>`;
  const right = p === 'ph' ? hbtn(I.gear) : `${btn('Alles gelezen', { k: 'ghost' })}${btn('Voorkeuren', { ic: I.gear })}`;
  return shell(p, { title: 'Notificaties', tags: o.empty ? [] : ['3 nieuw'], right, body: groups, center: o.center });
}
const prefRows = (p, o = {}) => {
  const f = p === 'tv', mgr = o.role === 'mgr';
  const push = o.push ?? 'on';
  const pushRow = sr('Push op dit toestel', { s: push === 'denied' ? 'Uit in iOS-instellingen. Pleya kan het niet zelf aanzetten.' : push === 'none' ? `${SRV} ondersteunt nog geen push. Notificaties staan alleen hier in Pleya.` : p === 'tv' ? 'Apple TV toont geen systeemmeldingen. Notificaties staan in Mijn Pleya.' : 'Ook als Pleya dicht is. Loopt via je eigen Pleya Server.', ctl: sw(push === 'on' && p !== 'tv', push !== 'on' || p === 'tv'), focus: false });
  const g = (h, rows, r) => `<div class="sgrp">${h}${r ? `<span class="r">${r}</span>` : ''}</div><div class="setp">${rows}</div>`;
  return `<div class="swrap">${o.msg ?? ''}${g('Waar', pushRow)}${g('Aanvragen en meldingen', sr('Updates over mijn aanvragen', { s: 'Goedgekeurd, afgewezen, beschikbaar', ctl: sw(true), focus: f }) + sr('Updates over mijn meldingen', { s: 'Reacties en opgelost', ctl: sw(true) }))}${g('Bibliotheek', sr('Nieuwe films', { ctl: sw(false) }) + sr('Nieuwe afleveringen', { s: 'Van series die je kijkt', ctl: sw(true) }) + (p === 'ph' && mgr ? '' : sr('Releasedatums van wat je volgt', { ctl: sw(false) })))}${mgr ? g('Beheer', sr('Nieuwe aanvragen om te beoordelen', { ctl: sw(true) }) + sr('Nieuwe meldingen van gebruikers', { ctl: sw(true) }), 'alleen beheerder') : g('Pleya', sr('Nieuwe Pleya-versies', { ctl: sw(true) }))}</div>`;
};
const notiS = {
  inbox: p => inbox(p),
  empty: p => inbox(p, { empty: true, center: empty(I.bell, 'Nog geen notificaties', 'Alles staat standaard uit. Kies welke updates je wilt zien, bijvoorbeeld als een aanvraag beschikbaar is of iemand op je melding reageert.', btn('Voorkeuren kiezen', { k: 'pri', focus: p === 'tv', ic: I.gear })) }),
  prefs: p => shell(p, { role: 'mgr', title: 'Notificatievoorkeuren', tags: ['standaard alles uit'], body: prefRows(p, { role: 'mgr' }) }),
  prime: p => p === 'tv'
    ? sheet({ k: 'Notificaties', title: 'Op Apple TV alleen in Pleya', body: `<div class="prime"><div class="bell">${I.bell}</div><h3>Geen systeemmeldingen op de TV</h3><p>tvOS toont geen meldingen van apps. Wat je aanzet zie je in Mijn Pleya, met een teller op de tegel. Push op je iPhone stel je op de iPhone zelf in.</p></div>`, foot: btn('Begrepen', { k: 'pri', focus: true }) })
    : sheet({ k: 'Notificaties', title: p === 'dk' ? 'Meldingen op deze Mac' : 'Push op deze iPhone', body: `<div class="prime"><div class="bell">${I.bell}</div><h3>Push aanzetten</h3><p>${p === 'dk' ? 'macOS' : 'iOS'} vraagt zo om toestemming. Pleya stuurt daarna alleen wat je aanzet:</p><ul><li>${I.check}Updates over mijn aanvragen</li><li>${I.check}Nieuwe afleveringen</li></ul><p style="font-size:.86em">De berichten lopen via je eigen Pleya Server ${SRV}, niet via een externe dienst.</p></div>`, foot: btn('Niet nu', { k: 'ghost' }) + btn('Doorgaan', { k: 'pri' }) }),
  denied: p => shell(p, { role: 'user', title: 'Notificatievoorkeuren', tags: [['push uit', 'warn']], body: prefRows(p, { push: p === 'tv' ? 'on' : 'denied', msg: p === 'tv' ? '' : `<div style="margin-bottom:.4em">${msg('warn', 'Push staat uit voor Pleya', `Je hebt toestemming geweigerd. Je voorkeuren blijven bewaard en verschijnen in Pleya; voor meldingen op het ${p === 'dk' ? 'bureaublad' : 'vergrendelscherm'} zet je push aan in de instellingen.`, btn(p === 'dk' ? 'Systeeminstellingen' : 'Open iOS-instellingen'))}</div>` }) }),
  pushes: p => {
    const lst = [
      { it: IT.charge, t: 'Charge is beschikbaar', x: 'Je aanvraag staat klaar in Films. Tik om af te spelen.', tm: 'nu' },
      { ic: 1, t: `${MGR} reageerde op je melding`, x: 'Nachttrein S1 A3: “Nieuwe versie staat erop.”', tm: '12 min' },
      { ic: 1, t: 'Nieuwe aanvraag om te beoordelen', x: 'Ravi vraagt Wadlopers seizoen 3 tot en met 5 aan.', tm: '1 u', mgr: 1 },
    ];
    const card = n => `<div class="push"><div class="app"><img src="${TVSRC}/assets/pleya_wordmark.png" alt=""></div><div class="bb"><div class="top"><span>PLEYA${n.mgr ? ' · BEHEER' : ''}</span><span>${n.tm}</span></div><div class="t">${n.t}</div><div class="x">${n.x}</div></div>${n.it ? `<div class="thumb">${art(n.it)}</div>` : ''}</div>`;
    const bg = `<div class="lockbg"><img src="${ARTDIR}/sintel-wide.jpg" alt=""></div>`;
    if (p === 'ph' || p === 'tb') return `${bg}${p === 'ph' ? status : ''}<div class="lockclock"><div class="d">maandag 9 november</div><div class="h">9:41</div></div><div class="pushes">${lst.map(card).join('')}</div><div class="cap2x">Voorbeeld op het vergrendelscherm. De derde komt alleen bij een beheerder.</div>`;
    if (p === 'dk') return `${bg}<div class="pushes">${lst.slice(0, 2).map(card).join('')}</div><div class="cap2x">macOS-melding rechtsboven. Klikken opent Pleya op de juiste plek.</div>`;
    return `<div class="bleed">${art(IT.sintel, true)}<div class="sc"></div></div>${topnav('Home')}<div class="pushes">${card({ ...lst[0], tm: 'nu' })}</div><div class="cap2x">Op Apple TV alleen binnen Pleya: een kaart rechtsboven die na vijf seconden verdwijnt, zonder de focus te pakken.</div>`;
  },
  noPush: p => shell(p, { role: 'user', title: 'Notificatievoorkeuren', tags: ['alleen in Pleya'], body: prefRows(p, { push: 'none', msg: `<div style="margin-bottom:.4em">${msg('info', `${SRV} ondersteunt nog geen push`, 'Werk Pleya Server bij om meldingen ook buiten de app te krijgen. Tot die tijd verschijnt alles in Mijn Pleya.')}</div>` }) }),
};

// ---------- 12. Ingangen ----------
const MP = [
  [I.requests, 'Aanvragen', '2 in afwachting', null],
  [I.flag, 'Meldingen', '1 open melding van jou', '1', 'newx'],
  [I.bell, 'Notificaties', '3 nieuw', '3', 'newx'],
  [I.list, 'Kijklijst', '14 titels', null],
  [I.dl, 'Downloads', '2 films op dit toestel', null],
  [I.gear, 'Instellingen', '', null],
];
function myPleya(p) {
  if (p === 'tv') return `${topnav('Mijn Pleya')}<div class="pg"><div class="head"><div class="page-title">Mijn Pleya</div><div class="tags">${tag(`${I.person} ${ctxOf()}`)}</div></div><div class="mgrid">${MP.map(([ic, t, s, n], i) => `<div class="mtile${i === 1 ? ' focus' : ''}">${ic}${n ? badge(n) : ''}<div class="t">${t}</div><div class="s">${s || 'Profiel, servers, weergave'}</div></div>`).join('')}</div></div>`;
  const rows = `<div class="lrows">${MP.map(([ic, t, s, n, x], i) => `<div class="mprow ${x ?? ''}${i === 1 && p === 'dk' ? ' focus' : ''}">${ic}<div class="bb"><div class="t">${t}</div>${s ? `<div class="s">${s}</div>` : ''}</div>${n ? badge(n) : ''}${I.chev.replace('class="ic"', 'class="ic chev"')}</div>`).join('')}</div>`;
  const head = `<div class="mph"><div class="av"><img src="${ARTDIR}/avatar.jpg" alt=""></div><div><div class="t">${USER}</div><div class="s">Profiel op ${SRV}</div></div></div>`;
  if (p === 'ph') return shell(p, { hdr: `<h1>Mijn Pleya</h1>${hbtn(I.bell, 3)}`, noctx: true, body: head + rows });
  return shell(p, { title: 'Mijn Pleya', right: hbtn(I.bell, 3), body: `<div style="max-width:40em">${head}${rows}</div>` });
}
const REQ = [['charge', 'wait', 'In afwachting', USER, 'Film', '6 okt'], ['wad', 'wait', 'In afwachting', 'Ravi', 'Serie · seizoen 3–5', '6 okt'], ['sintel', 'ok', 'Beschikbaar', MGR, 'Film', '4 okt'], ['glas', 'wait', 'Goedgekeurd', USER, 'Film', '2 okt'], ['kust', 'ok', 'Beschikbaar', 'Ravi', 'Serie · seizoen 1–3', '1 okt'], ['nacht', 'part', 'Deels beschikbaar', USER, 'Serie · seizoen 1–2', '28 sep'], ['tears', 'wait', 'In afwachting', 'Ravi', 'Film · 4K', '30 sep'], ['onder', 'wait', 'Goedgekeurd', MGR, 'Serie · seizoen 4', '27 sep']];
const rrow = (r, p) => { const it = IT[r[0]]; const pend = r[2] === 'In afwachting'; const acts = (pend ? btn('Goedkeuren', { k: 'pri' }) + btn('Afwijzen') : '') + (p === 'ph' ? '' : btn('', { k: 'icon', ic: I.more })); return `<div class="lrow"><div class="thumb">${art(it)}</div><div class="bb"><div class="t">${it.t}</div><div class="s">${p === 'ph' ? r[4] : `${it.y} · ${r[4]}`} · door ${r[3]} · ${r[5]}</div></div>${cap(r[1], r[2], true)}${acts ? `<div class="acts">${acts}</div>` : ''}</div>`; };
function reqWithEntry(p) {
  const shortcut = `<div class="lrows" style="margin-bottom:1em"><div class="mprow">${I.flag}<div class="bb"><div class="t">Meldingen</div><div class="s">6 open · nieuwste: Nachttrein, geluid</div></div>${badge(6)}${I.chev.replace('class="ic"', 'class="ic chev"')}</div></div>`;
  if (p === 'tv') return `${topnav('Mijn Pleya')}<div class="pg"><div class="head"><div class="page-title">Alle aanvragen</div><div class="tags">${tag('389 aanvragen')}${tag(`${I.person} ${ctxOf('mgr')}`)}</div></div><div class="chipsx" style="margin:26px 0 30px"><span class="cx on">Alles <span class="n">389</span></span><span class="cx">In afwachting <span class="n">27</span></span><span class="cx">Goedgekeurd <span class="n">108</span></span><span style="width:18px"></span><span class="cx focus" style="box-shadow:0 0 0 6px var(--bg),0 0 0 10px var(--ink)">${I.flag}Meldingen <span class="n">6</span></span></div><div class="grid">${REQ.slice(0, 6).map(r => `<div class="card"><div class="art">${art(IT[r[0]])}${cap(r[1], r[2])}</div><div class="t">${IT[r[0]].t}</div><div class="s">${r[4]}</div><div class="by">Aangevraagd door ${r[3]}</div></div>`).join('')}</div></div>`;
  const top = `<div class="seg"><span class="on">Alle aanvragen</span><span>Mijn aanvragen</span></div><div class="chipsx"><span class="cx on">Alles <span class="n">389</span></span><span class="cx">In afwachting <span class="n">27</span></span><span class="cx">Goedgekeurd <span class="n">108</span></span>${p === 'ph' ? `<span class="cx">${I.chevd}</span>` : '<span class="cx">Beschikbaar <span class="n">35</span></span><span class="cx">Afgewezen <span class="n">14</span></span>'}</div>${shortcut}`;
  const n = { ph: 3, tb: 5, dk: 7 }[p];
  return shell(p, { role: 'mgr', title: 'Aanvragen', right: p === 'ph' ? hbtn(I.flag, 6) : '', top, body: `<div class="lrows">${REQ.slice(0, n).map(r => rrow(r, p)).join('')}</div>` });
}

// ---------- staten ----------
// built: N = nieuw, niet op main · P = gebouwd op een open branch, nog niet gemerged
const FAM = { 9: 'Meldingen afhandelen', 10: 'Probleem melden', 11: 'Notificaties', 12: 'Ingangen' };
const S = [];
const add = (fam, name, role, built, intent, kind, r, u) => S.push({ fam, name, role, built, intent, kind, r, u });
const scr = (fam, name, role, built, intent, r) => add(fam, name, role, built, intent, 'scherm', r);
const ovl = (fam, name, role, built, intent, r, u) => add(fam, name, role, built, intent, 'overlay', r, u);

scr(9, 'Open meldingen', 'beheerder', 'P', 'Zelfde lijsttaal als 7B: rij in een kaart, statusstip, type en plek in één regel. PR #654 heeft de lijst, deze vorm is nieuw', issueS.open);
scr(9, 'Filter Opgelost', 'beheerder', 'P', 'Opgelost blijft leesbaar; aantallen uit hetzelfde bereik', issueS.resolved);
scr(9, 'Mijn meldingen leeg', 'aanvrager', 'N', 'Leeg is geen fout: legt uit waar je een probleem meldt', issueS.mineEmpty);
scr(9, 'Niet beschikbaar op deze server', 'aanvrager', 'P', 'Server te oud of geen recht: geen Opnieuw-knop, wel wat de beheerder moet doen', issueS.unavailable);
scr(9, 'Fout bij ophalen', 'beheerder', 'P', 'Alleen een echte fout krijgt Opnieuw proberen; een streepje is geen nul', issueS.error);
scr(9, 'Detail met gesprek', 'beheerder', 'P', 'Titel, plek en type bovenaan; afspelen vanaf de gemelde aflevering; gesprek als berichten', issueS.detail);
scr(9, 'Reactie typen', 'beheerder', 'P', 'Plaatsen wordt pas actief met tekst; op TV via het systeemtoetsenbord', issueS.typing);
scr(9, 'Reactie niet bevestigd', 'beheerder', 'P', 'Uitkomst onbekend: eerst het gesprek verversen, niet blind opnieuw plaatsen. Zelfde patroon als 4I en 8J', issueS.unconfirmed);
scr(9, 'Opgelost, heropenen mogelijk', 'beheerder', 'P', 'Gebeurtenis in het gesprek; Heropenen vervangt Markeren als opgelost', issueS.resolved1);
ovl(9, 'Oplossen bevestigen', 'beheerder', 'N', 'Veilige knop in focus op TV; zegt wie een notificatie krijgt', issueS.confirm, IT.nacht);
ovl(9, 'Acties via de drie puntjes', 'beheerder', 'N', 'Zelfde menu als 8A: titel, afspelen, reageren, oplossen', issueS.actions, IT.nacht);

scr(10, 'Ingang op de titelpagina', 'aanvrager', 'N', 'Telefoon: ronde actieknop Melden naast Kijklijst. TV en desktop: knop in de knoppenrij', reportS.title);
scr(10, 'Ingang in de speler', 'aanvrager', 'N', 'Menu tijdens het kijken; tijdstip en audiotrack gaan automatisch mee', reportS.player);
ovl(10, 'Type kiezen', 'aanvrager', 'N', 'Vier Seerr-typen met een voorbeeld per type, zodat niemand hoeft te raden', reportS.type, IT.sintel);
ovl(10, 'Serie: seizoen en aflevering', 'aanvrager', 'N', 'Vooraf ingevuld uit de speler; hele serie kan ook', reportS.episode, IT.camin);
ovl(10, 'Toelichting', 'aanvrager', 'N', 'Optioneel tekstvak; zegt wat er automatisch meegaat', reportS.text, IT.sintel);
ovl(10, 'Verstuurd', 'aanvrager', 'N', 'Verder kijken is de hoofdknop; de melding blijft vindbaar', reportS.sent, IT.sintel);
ovl(10, 'Al gemeld door iemand anders', 'aanvrager', 'N', 'Eerst naar de bestaande melding, apart melden kan nog', reportS.duplicate, IT.sintel);
ovl(10, 'Geen recht om te melden', 'profiel zonder recht', 'N', 'Noemt het Seerr-recht en wie het kan aanzetten', reportS.noRight, IT.sintel);
ovl(10, 'Versturen mislukt, tekst blijft', 'aanvrager', 'N', 'Er is niets gemeld; herstel is één knop', reportS.error, IT.sintel);

scr(11, 'Notificatiecentrum', 'aanvrager', 'P', 'Per dag gegroepeerd; rode stip is ongelezen; tikken opent de plek van de update', notiS.inbox);
scr(11, 'Leeg, alles staat uit', 'aanvrager', 'P', 'Opt-in: leeg betekent hier meestal dat er niets aanstaat', notiS.empty);
scr(11, 'Voorkeuren per categorie', 'beheerder', 'P', 'Categorieën uit de WIP-branch; Beheer alleen voor de beheerder; alles standaard uit', notiS.prefs);
ovl(11, 'Uitleg voor de systeemvraag', 'aanvrager', 'N', 'Pleya legt uit voordat iOS vraagt; op TV eerlijk dat er geen systeemmeldingen zijn', notiS.prime, IT.sintel);
scr(11, 'Push geweigerd', 'aanvrager', 'N', 'Voorkeuren blijven werken in de app; de weg naar de instellingen staat erbij', notiS.denied);
scr(11, 'Voorbeelden van push', 'aanvrager en beheerder', 'P', 'Vier soorten berichten; TV alleen in de app, zonder focus te pakken', notiS.pushes);
scr(11, 'Server zonder push', 'aanvrager', 'N', 'Capability ontbreekt: schakelaar uit, de rest werkt in de app', notiS.noPush);

scr(12, 'Mijn Pleya met Meldingen en Notificaties', 'aanvrager', 'N', 'De twee nieuwe ingangen naast Aanvragen, met teller en een nieuw-label uit de merkgradiënt', myPleya);
scr(12, 'Aanvragen met snelkoppeling naar Meldingen', 'beheerder', 'N', 'Beheerder ziet open meldingen boven de aanvraaglijst; TV als filterchip', reqWithEntry);

const seen = {};
for (const s of S) { seen[s.fam] = (seen[s.fam] ?? 0) + 1; s.code = `${s.fam}${String.fromCharCode(64 + seen[s.fam])}`; s.slug = s.name.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 44); }

// ---------- pagina's ----------
const PL = { tv: { dir: 'tv', label: 'TV', w: 1920, h: 1080, dsf: 1 }, ph: { dir: 'phone', label: 'Telefoon', w: 402, h: 874, dsf: 2 }, tb: { dir: 'tablet', label: 'Tablet', w: 1180, h: 820, dsf: 1 }, dk: { dir: 'desktop', label: 'Desktop', w: 1440, h: 900, dsf: 1 } };
const BOARD = { tv: [944, 1024, 2, 32, 0, 56], dk: [464, 844, 3, 24, 0, 56], tb: [560, 764, 3, 20, 0, 56], ph: [402, 874, 4, 24, 24, 40] };
const BLT = { N: 'nieuw, niet gebouwd', P: 'deels op een open branch, niet op main' };
const inner = (p, s) => s.kind === 'scherm' ? s.r(p) : `<div class="bleed dim">${art(s.u ?? IT.sintel, true)}<div class="sc"></div></div><div class="scrimx"></div>${s.r(p)}`;
const pages = [];
const LH = 56;
const lab = (s, w, h) => `<div class="lab" style="height:${h}px;width:${w}px"><b>${s.code}</b><span>${s.name}</span><em>${s.built === 'N' ? '· nieuw' : '· open branch'}</em></div>`;
const chunk = (a, n) => a.reduce((o, x, i) => (i % n ? o[o.length - 1].push(x) : o.push([x]), o), []);
for (const p of Object.keys(PL)) {
  for (const fam of Object.keys(FAM)) {
    const fs = S.filter(s => s.fam == fam);
    const single = p === 'ph' ? [] : fs.filter(s => s.kind === 'scherm');
    const boarded = p === 'ph' ? fs : fs.filter(s => s.kind === 'overlay');
    for (const s of single) pages.push({ p, fam, name: `mk-${p}-${s.code}-${s.slug}`, w: PL[p].w, h: PL[p].h + LH, states: [s], html: `<div class="pn">${lab(s, PL[p].w, LH)}<div class="vp ${p}">${inner(p, s)}</div></div>` });
    const [bw, bh, n, gap, pad, lh] = BOARD[p];
    for (const g of chunk(boarded, n)) {
      const w = n * bw + (n - 1) * gap + 2 * pad, h = bh + lh + 2 * pad;
      const slug = FAM[fam].toLowerCase().replace(/[^a-z0-9]+/g, '-');
      pages.push({ p, fam, name: `mk-${p}-${g[0].code}-${g[g.length - 1].code}-${slug}`, w, h, states: g, board: true,
        html: `<div style="display:flex;gap:${gap}px;padding:${pad}px;width:${w}px;height:${h}px">${g.map(s => `<div class="pn">${lab(s, bw, lh)}<div class="vp ${p}" style="width:${bw}px;height:${bh}px">${inner(p, s)}</div></div>`).join('')}</div>` });
    }
  }
}

// ---------- inhoudscontrole ----------
const txt = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
for (const p of Object.keys(PL)) for (const s of S) {
  const t = txt(inner(p, s));
  if (/\u2014/.test(t)) problems.push(`${s.code} ${p}: emdash in de copy`);
  if (/Plezy|Seerr-server/.test(t)) problems.push(`${s.code} ${p}: verkeerde productnaam`);
}
// Een onbevestigde reactie biedt geen blind opnieuw plaatsen aan.
for (const p of Object.keys(PL)) { const t = txt(S.find(s => s.code === '9H').r(p)); if (/Opnieuw plaatsen|Opnieuw proberen/.test(t) || !/verversen/.test(t)) problems.push(`9H ${p}: herstel is niet eerst verversen`); }

// ---------- renderen ----------
const only = process.argv.slice(2).filter(a => !a.startsWith('--'));
const noRender = process.argv.includes('--no-render');
mkdirSync(OUT, { recursive: true });
for (const p of Object.values(PL)) mkdirSync(join(SET, p.dir), { recursive: true });
if (!noRender) {
  const pw = process.env.PLEYA_MOCKUP_PLAYWRIGHT ?? ['/opt/node-tools/node_modules/playwright/index.mjs', '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs'].find(existsSync);
  const { chromium } = await import(pw);
  const browser = await chromium.launch();
  for (const dsf of [1, 2]) {
    const ctx = await browser.newContext({ deviceScaleFactor: dsf, colorScheme: 'dark' });
    const page = await ctx.newPage();
    for (const pg of pages.filter(x => PL[x.p].dsf === dsf && (only.length === 0 || only.some(o => x.name.includes(o))))) {
      const file = join(OUT, pg.name + '.html');
      writeFileSync(file, `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>${pg.name}</title><link rel="stylesheet" href="${TVSRC}/tv.css"><link rel="stylesheet" href="${RQCSS}"><link rel="stylesheet" href="../mk.css"></head><body>${pg.html}</body></html>`);
      await page.setViewportSize({ width: pg.w, height: pg.h });
      await page.goto('file://' + file, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      const bad = await page.evaluate(() => [...document.images].filter(i => !i.complete || !i.naturalWidth).map(i => i.getAttribute('src')));
      if (bad.length) problems.push(`${pg.name}: kapotte afbeelding ${bad.join(', ')}`);
      for (const m of await page.evaluate(() => {
        const out = [], r = e => e.getBoundingClientRect(), R = Math.round;
        for (const vp of document.querySelectorAll('.vp')) {
          const v = r(vp), code = vp.parentElement.querySelector('.lab b')?.textContent ?? '', P = m => out.push(`${code} ${m}`);
          const bar = vp.querySelector('.tabbar'), floor = bar ? r(bar).top : v.bottom;
          // Knoppen in meldingen, formulieren en lege staten staan volledig in beeld, boven de tabbalk.
          for (const b of vp.querySelectorAll('.msg .b, .empty .b, .sh-foot .b, .composer .b, .vstack .b')) { const x = r(b); if (x.bottom > floor + .5 || x.top < v.top - .5 || x.right > v.right + .5) P(`knop "${b.textContent.trim()}" valt buiten beeld`); }
          // Focus met ring in beeld.
          for (const e of vp.querySelectorAll('.focus')) { const t = e.classList.contains('card') ? e.querySelector('.art') : e, b = r(t); if (b.bottom > v.bottom + .5 || b.top < v.top - .5 || b.right > v.right + .5) P(`focus valt buiten beeld (${R(b.bottom - v.top)} van ${R(v.height)})`); }
          // Geen afgekapte regels in rijen.
          for (const s of vp.querySelectorAll('.lrow .t, .lrow .s, .lrow .s2, .nrow .t, .mprow .t, .sr .t')) if (s.scrollWidth > s.clientWidth + 1) P(`regel afgekapt: "${s.textContent.trim().slice(0, 50)}"`);
          // Een sheet past in het paneel.
          for (const sh of vp.querySelectorAll('.sheet')) { const b = r(sh); if (b.top < v.top - .5) P('sheet hoger dan het scherm'); }
          // Rijen onder de tabbalk tellen niet als zichtbaar: de laatste zichtbare rij mag niet half onder de balk staan als hij een knop heeft.
          for (const e of vp.querySelectorAll('.lrows .lrow .acts .b')) { const x = r(e); if (x.top < floor && x.bottom > floor) P(`rijknop "${e.textContent.trim()}" half onder de tabbalk`); }
        }
        return out;
      })) problems.push(`${pg.name}: ${m.trim()}`);
      await page.waitForTimeout(60);
      await page.screenshot({ path: join(SET, PL[pg.p].dir, pg.name + '.jpg'), type: 'jpeg', quality: 88 });
      console.log('shot', PL[pg.p].dir + '/' + pg.name + '.jpg', `${pg.w * dsf}x${pg.h * dsf}`);
    }
    await ctx.close();
  }
  await browser.close();
}

// ---------- manifest, index, dekkingsmatrix ----------
const where = (s, p) => { const pg = pages.find(x => x.p === p && x.states.includes(s)); return { file: `${PL[p].dir}/${pg.name}.jpg`, panel: pg.board ? s.code : null, px: `${pg.w * PL[p].dsf}x${pg.h * PL[p].dsf}` }; };
const manifest = {
  set: 'Requests 2.1 meldingen en notificaties (voorstel onder A-20/A-21)', status: STATUS.long, generated: new Date().toISOString().slice(0, 10),
  images: pages.map(pg => ({ file: `${PL[pg.p].dir}/${pg.name}.jpg`, platform: PL[pg.p].label, pixels: `${pg.w * PL[pg.p].dsf}x${pg.h * PL[pg.p].dsf}`, family: FAM[pg.fam], panels: pg.states.map(s => s.code) })),
  states: S.map(s => ({ code: s.code, family: FAM[s.fam], state: s.name, role: s.role, kind: s.kind, versusSource: BLT[s.built], intent: s.intent, ...Object.fromEntries(Object.keys(PL).map(p => [PL[p].label, where(s, p)])) })),
};
writeFileSync(join(SET, 'manifest.json'), JSON.stringify(manifest, null, 1));
const cell = (s, p) => { const w = where(s, p); return `[${w.panel ? 'paneel ' + w.panel : 'beeld'}](${w.file})`; };
const matrix = Object.keys(FAM).map(f => `### ${f}. ${FAM[f]}\n\n| Code | Staat | Rol | Tegenover main | TV | Telefoon | Tablet | Desktop |\n|---|---|---|---|---|---|---|---|\n${S.filter(s => s.fam == f).map(s => `| ${s.code} | ${s.name} | ${s.role} | ${BLT[s.built]} | ${Object.keys(PL).map(p => cell(s, p)).join(' | ')} |`).join('\n')}`).join('\n\n');
const readme = join(SET, 'README.md');
if (existsSync(readme)) { const src = readFileSync(readme, 'utf8'); const a = '<!-- MATRIX:BEGIN -->', b = '<!-- MATRIX:END -->'; if (src.includes(a)) writeFileSync(readme, src.slice(0, src.indexOf(a) + a.length) + '\n' + matrix + '\n' + src.slice(src.indexOf(b))); }

const esc = t => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;');
writeFileSync(join(SET, 'index.html'), `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Meldingen en notificaties</title><style>
:root{--bg:#141414;--ink:#fff;--muted:rgba(255,255,255,.62);--hair:rgba(255,255,255,.14);--amber:#FFB020}
body{background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,Inter,sans-serif;margin:0;padding:28px 36px 80px}
h1{font-size:28px;margin:0 0 6px}h2{font-size:22px;margin:44px 0 6px;padding-top:14px;border-top:1px solid var(--hair)}h3{font-size:15px;color:var(--muted);margin:22px 0 10px;font-weight:600}
p{color:rgba(255,255,255,.8);max-width:980px;margin:6px 0}a{color:#fff}.st{display:inline-block;background:var(--amber);color:#000;font-weight:700;border-radius:5px;padding:1px 8px}
nav a{margin-right:14px;color:var(--muted)}.g{display:flex;flex-wrap:wrap;gap:14px}.c{width:300px}.c.wide{width:620px}.c img{width:100%;display:block;border-radius:6px;border:1px solid var(--hair);background:#000}
.c div{font-size:12.5px;color:var(--muted);margin-top:5px}.c b{color:#fff}table{border-collapse:collapse;font-size:13px;margin-top:8px}td,th{border-bottom:1px solid var(--hair);padding:4px 10px 4px 0;text-align:left;vertical-align:top}th{color:var(--muted);font-weight:600}
.cmp{display:flex;gap:18px;flex-wrap:wrap;align-items:flex-start}.cmp figure{margin:0;width:300px}.cmp figure.w{width:640px}.cmp img{width:100%;border-radius:6px;border:1px solid var(--hair)}.cmp figcaption{font-size:12.5px;color:var(--muted);margin-top:6px}
@media (max-width:700px){body{padding:20px 16px 60px}.c,.c.wide,.cmp figure,.cmp figure.w{width:100%}table{display:block;overflow-x:auto}}
</style></head><body>
<h1>Meldingen en notificaties</h1>
<p><span class="st">${STATUS.short}</span> ${esc(STATUS.long)}. Niets hiervan is gebouwd of op een toestel gezien. De matrix en de keuzes staan in <a href="README.md">README.md</a>, de afwijkingen van de huidige app in <a href="AFWIJKINGEN.md">AFWIJKINGEN.md</a>.</p>
<p>${S.length} staten in ${Object.keys(FAM).length} families, ${pages.length} beelden. Vormtaal en tokens komen uit de goedgekeurde set <a href="../requests-2.0/index.html">Requests 2.0</a>; deze set vult alleen aan.</p>
<nav><a href="#nu">Nu in de app</a>${Object.keys(FAM).map(f => `<a href="#f${f}">${f}. ${FAM[f]}</a>`).join('')}</nav>
<h2 id="nu">Nu in de app tegenover goedgekeurd</h2>
<p>Links de app op 9 november, rechts de goedgekeurde staten 7A tot en met 7D uit Requests 2.0. Het verschil per scherm staat in AFWIJKINGEN.md.</p>
<div class="cmp"><figure><img src="bewijs/2026-11-09-alle-aanvragen.png" alt="Alle aanvragen in de app op 9 november"><figcaption>App, iPhone, 9 november 2026</figcaption></figure><figure class="w"><img src="../requests-2.0/phone/rq-ph-7A-7D-aanvragenlijst.jpg" alt="Goedgekeurde aanvragenlijst 7A tot en met 7D"><figcaption>Goedgekeurd, 7A tot en met 7D</figcaption></figure></div>
${Object.keys(FAM).map(f => `<h2 id="f${f}">${f}. ${FAM[f]}</h2>
<table><tr><th>Code</th><th>Staat</th><th>Rol</th><th>Tegenover main</th><th>Bedoeling</th></tr>${S.filter(s => s.fam == f).map(s => `<tr><td><b>${s.code}</b></td><td>${esc(s.name)}</td><td>${esc(s.role)}</td><td>${BLT[s.built]}</td><td>${esc(s.intent)}</td></tr>`).join('')}</table>
${Object.keys(PL).map(p => `<h3>${PL[p].label}</h3><div class="g">${pages.filter(x => x.p === p && x.fam == f).map(pg => `<a class="c${pg.board ? ' wide' : ''}" href="${PL[p].dir}/${pg.name}.jpg"><img loading="lazy" src="${PL[p].dir}/${pg.name}.jpg" alt=""><div><b>${pg.states.map(s => s.code).join(' · ')}</b> ${esc(pg.states.map(s => s.name).join(' | '))}</div></a>`).join('')}</div>`).join('')}`).join('')}
</body></html>`);

for (const im of manifest.images) { const f = join(SET, im.file); if (!existsSync(f)) problems.push('ontbreekt: ' + im.file); else if (statSync(f).size < 8000) problems.push('verdacht klein: ' + im.file); }
console.log(`\n${S.length} staten · ${pages.length} beelden · ${Object.values(PL).map(p => `${p.label} ${pages.filter(x => PL[x.p] === p).length}`).join(' · ')}`);
console.log(problems.length ? 'PROBLEMEN:\n' + problems.join('\n') : 'zelfcontrole: elk beeld bestaat, geen kapotte afbeeldingen, geen afgekapte regels');
process.exit(problems.length ? 1 : 0);
