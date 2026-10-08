// Requests 2.0 (roadmap A-20): tekent elke staat uit docs/requests-2.0-spec.md één keer
// en rendert hem voor TV, telefoon, tablet en desktop. Schrijft out/*.html, de beelden in
// ../tv ../phone ../tablet ../desktop, ../manifest.json, ../index.html en de dekkingsmatrix
// in ../README.md. Gebruik: node gen.mjs [filter ...]   (filter = deel van een bestandsnaam)
// Zelfde Playwright-override als ../../tvos-unified/src/build.mjs: PLEYA_MOCKUP_PLAYWRIGHT.
import { writeFileSync, readFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('.', import.meta.url).pathname;
const SET = join(ROOT, '..');
const OUT = join(ROOT, 'out');
const TVSRC = '../../../tvos-unified/src';
const ARTDIR = '../../../ios-unified/detail-2026';
const problems = [];
// Status van de set. Staat alleen in manifest, index en README, niet in de beelden, zodat een
// statuswissel geen nieuwe render vraagt.
const STATUS = { short: 'ONTWERP GOEDGEKEURD', long: 'Ontwerp goedgekeurd door Michel Knoop op 8 oktober 2026; Impeccable polish en onafhankelijke review afgerond' };

// ---------- iconen (subset van build.mjs, zelfde tekening) ----------
const sv = (d, x = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${x}>${d}</svg>`;
const I = {
  search: sv('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', 'stroke-width="2.4"'),
  back: sv('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'),
  chev: sv('<path d="m9 6 6 6-6 6"/>'),
  chevd: sv('<path d="m6 9 6 6 6-6"/>'),
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
  plus: sv('<path d="M12 5v14M5 12h14"/>'),
  info: sv('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
  warn: sv('<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>'),
  check: sv('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.8"'),
  close: sv('<path d="m6 6 12 12M18 6 6 18"/>'),
  person: sv('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  trash: sv('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>'),
  edit: sv('<path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4"/>'),
  server: sv('<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>'),
  folder: sv('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
  more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  clock: sv('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  lock: sv('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  refresh: sv('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>'),
  requests: sv('<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>'),
  film: sv('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>'),
  show: sv('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  home: sv('<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4z"/>'),
  live: sv('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m7 3 5 3 5-3"/>'),
  filter: sv('<path d="M4 6h16M7 12h10M10 18h4"/>'),
  cloudoff: sv('<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z"/><path d="m4 4 16 16"/>'),
  sliders: sv('<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>'),
};

// ---------- fixture ----------
// Blender-openfilms uit de bestaande detail-2026-map; de rest zijn getekende covers met
// het woord FIXTURE erop. Geen titel, aanvrager of server hier komt van een echt toestel.
const IT = {
  charge: { t: 'Charge', y: 2022, g: 'Actie', k: 'Film', len: '1u 32m', img: 'charge-poster' },
  sintel: { t: 'Sintel', y: 2010, g: 'Fantasy', k: 'Film', len: '1u 28m', img: 'sintel-poster', wide: 'sintel-wide' },
  tears: { t: 'Tears of Steel', y: 2012, g: 'Sciencefiction', k: 'Film', len: '1u 41m', img: 'tears-poster' },
  spring: { t: 'Spring', y: 2019, g: 'Animatie', k: 'Film', len: '1u 18m', img: 'spring-poster' },
  coffee: { t: 'Coffee Run', y: 2020, g: 'Animatie', k: 'Film', len: '1u 12m', img: 'coffeerun-poster' },
  camin: { t: 'Caminandes', y: 2013, g: 'Animatie', k: 'Serie', n: 3, img: 'caminandes-poster' },
  eleph: { t: 'Elephants Dream', y: 2006, g: 'Sciencefiction', k: 'Film', len: '1u 24m', img: 'elephants-poster' },
  dweebs: { t: 'Dweebs', y: 2021, g: 'Komedie', k: 'Serie', n: 2, img: 'dweebs-poster' },
  wad: { t: 'Wadlopers', y: 2023, g: 'Drama', k: 'Serie', n: 5, len: '5 seizoenen', h: 196 },
  dijk: { t: 'Dijkwacht', y: 2011, g: 'Misdaad', k: 'Serie', n: 14, len: '14 seizoenen', h: 222 },
  zout: { t: 'Zoutland', y: 2025, g: 'Drama', k: 'Film', len: '2u 04m', h: 28 },
  glas: { t: 'Glasstad', y: 2024, g: 'Thriller', k: 'Film', len: '1u 49m', h: 286 },
  nacht: { t: 'Nachttrein', y: 2024, g: 'Thriller', k: 'Serie', n: 2, h: 250 },
  kust: { t: 'Kustlijn', y: 2022, g: 'Drama', k: 'Serie', n: 3, h: 172 },
  polder: { t: 'De Stille Polder', y: 2025, g: 'Documentaire', k: 'Film', len: '1u 36m', h: 96 },
  onder: { t: 'Onderstroom', y: 2021, g: 'Misdaad', k: 'Serie', n: 4, h: 340 },
  kwacht: { t: 'Kustwacht', y: 2024, g: 'Actie', k: 'Film', len: '1u 52m', h: 206 },
  klicht: { t: 'Kustlicht', y: 2020, g: 'Romantiek', k: 'Serie', n: 6, h: 44 },
  kzout: { t: 'De Kust van Zout', y: 2023, g: 'Drama', k: 'Film', len: '1u 58m', h: 8 },
};
const CAST = [['MD', 'Mira Doorn', 'Shade'], ['JV', 'Joost Valk', 'Poortwachter'], ['LB', 'Lena Bos', 'Scales'], ['TV', 'Tariq Veen', 'Sjamaan'], ['IK', 'Ilse Kramer', 'Verteller'], ['NH', 'Noor Hadi', 'Stadswacht']];
const USER = 'Sanne', MGR = 'Michel', SRV = 'Thuis';

const hasFocus = p => p === 'tv' || p === 'dk';
const art = (it, wide) => (wide && it.wide) ? `<img src="${ARTDIR}/${it.wide}.jpg" alt="">` : it.img ? `<img src="${ARTDIR}/${it.img}.jpg" alt="">` : `<div class="fx" style="--h:${it.h}"><b>${it.t}</b><i>FIXTURE</i></div>`;
const cap = (k, l, inl) => `<span class="cap ${k}${inl ? ' inl' : ''}"><i class="d"></i>${l}</span>`;
const sub = it => it.k === 'Serie' ? `${it.y} · ${it.n} seizoenen` : `${it.y} · ${it.g}`;
const card = (it, o = {}) => `<div class="card${o.focus ? ' focus' : ''}${o.busy ? ' busy' : ''}"><div class="art">${art(it)}${o.cap ? cap(...o.cap) : ''}</div><div class="t">${it.t}</div><div class="s">${o.s ?? sub(it)}</div>${o.by ? `<div class="by">${o.by}</div>` : ''}</div>`;
const btn = (l, o = {}) => `<span class="b ${o.k ?? ''}${o.focus ? ' focus' : ''}${o.dis ? ' dis' : ''}">${o.busy ? '<i class="spin"></i>' : ''}${o.ic ?? ''}${l}</span>`;
const msg = (k, b, t, bt) => `<div class="msg ${k}">${{ info: I.info, warn: I.warn, err: I.warn, ok: I.check }[k]}<div><b>${b}</b><span>${t}</span></div>${bt ?? ''}</div>`;
const empty = (ic, h, t, btns) => `<div class="empty">${ic}<h2>${h}</h2><p>${t}</p>${btns ? `<div class="brow">${btns}</div>` : ''}</div>`;
const tag = (t, k = '') => `<span class="tagx ${k}">${t}</span>`;
const skCard = '<div class="card"><div class="art sk"></div><div class="skl"></div><div class="skl" style="width:45%"></div></div>';
const errTile = (p, l = 'Meer laden mislukt') => `<div class="card${hasFocus(p) ? ' focus' : ''}"><div class="art errt">${I.warn}<b>${l}</b><span>Wat al geladen was blijft staan.</span>${btn('Opnieuw', { ic: I.refresh })}</div></div>`;

// ---------- frames ----------
function topnav(active) {
  return `<nav class="topnav"><div class="chip">M</div><div class="cluster">${I.search.replace('class="ic"', 'class="ic search"')}${['Home', 'Series', 'Films', 'Live TV', 'Mijn Pleya'].map(n => `<div class="item${n === active ? ' on' : ''}">${n}</div>`).join('')}</div><div class="wordmark"><img src="${TVSRC}/assets/pleya_wordmark.png" alt="Pleya"></div></nav>`;
}
const tabbar = `<div class="tabbar"><div>${I.home}Home</div><div>${I.show}Series</div><div>${I.film}Films</div><div>${I.live}Live TV</div><div class="on">${I.person}Mijn Pleya</div></div><div class="homeind"></div>`;
const status = '<div class="status"><span>9:41</span><div class="island"></div><span></span></div>';
const ctxOf = role => role === 'mgr' ? `${MGR} · beheerder · ${SRV}` : role === 'none' ? `${USER} · geen aanvraagserver` : `${USER} · ${SRV}`;

// o: title, role, tags[], right, body, panel (TV-rail), center, over, hdr (telefoonkop), nostrip
function shell(p, o) {
  const tags = [...(o.tags ?? []), `${I.person} ${ctxOf(o.role)}`];
  if (p === 'tv') return `${topnav(o.nav ?? 'Mijn Pleya')}<div class="pg"><div class="head">${o.tvhead ?? `<div class="page-title">${o.title}</div>`}<div class="tags">${tags.map(t => typeof t === 'string' ? tag(t) : tag(t[0], t[1])).join('')}</div></div>${o.body || o.panel ? `<div class="bd">${o.panel ?? (o.nostrip ? '' : '<div class="strip"></div>')}<div class="main${o.scrolled ? ' scrolled' : ''}">${o.body ?? ''}</div></div>` : ''}${o.center ?? ''}</div>${o.over ?? ''}`;
  const plain = tags.map(t => typeof t === 'string' ? t : t[0]);
  if (p === 'ph') return `${status}<div class="hdr">${o.hdr ?? `${I.back}<h1>${o.title}</h1>${o.right ?? ''}`}</div><div class="pg"><div class="ctx">${plain.slice().reverse().join(' · ')}</div>${o.top ?? ''}${o.body ?? ''}${o.center ?? ''}</div>${tabbar}${o.over ?? ''}`;
  return `<div class="bar">${I.back}<h1>${o.title}</h1><span class="sub">${plain.slice().reverse().join(' · ')}</span><div class="rt">${o.right ?? ''}</div></div><div class="pg">${o.top ?? ''}${o.body ?? ''}${o.center ?? ''}</div>${o.over ?? ''}`;
}

// ---------- 1. Ontdekken ----------
const D_FILMS = [['charge', ['wait', 'Aangevraagd']], ['zout'], ['sintel', ['ok', 'Beschikbaar']], ['glas'], ['tears'], ['polder'], ['spring'], ['coffee']];
const D_SERIES = [['wad', ['part', 'Deels beschikbaar']], ['dijk'], ['nacht'], ['kust', ['ok', 'Beschikbaar']], ['onder'], ['camin'], ['dweebs'], ['klicht']];
const rail = (p, label, arr, fi, next) => `<div class="rl${next ? ' next' : ''}">${label}${p === 'tv' ? '' : `<span class="all">Alles tonen ${I.chev}</span>`}</div><div class="rb">${arr.map(([k, c], i) => card(IT[k], { cap: c, focus: i === fi && hasFocus(p) })).join('')}</div>`;
const dTop = (p, sel = 'Alles', extra = '') => p === 'tv' ? '' : `<div class="sfield">${I.search}Zoek een film of serie om aan te vragen</div><div class="chipsx">${['Alles', 'Films', 'Series'].map(c => `<span class="cx${c === sel ? ' on' : ''}">${c}</span>`).join('')}<span class="cx${extra ? ' on' : ''}">${extra || 'Genres'} ${I.chevd}</span>${p === 'ph' ? '' : `<span class="cx">Streamingdienst ${I.chevd}</span>`}</div>`;
const optSheet = (p, title, opts) => `<div class="scrimx"></div><div class="sheet"><div class="sh-head"><div class="t">${title}</div></div><div class="sh-body">${opts.map(([l, on]) => `<div class="sr"><div class="bb"><div class="t">${l}</div></div>${on ? I.check : ''}</div>`).join('')}</div><div class="sh-foot">${btn('Wissen', { k: 'ghost' })}${btn('Toon titels', { k: 'pri' })}</div></div>`;
const GENRES = [['Alle genres', 0], ['Actie', 0], ['Animatie', 0], ['Documentaire', 0], ['Drama', 1], ['Komedie', 0], ['Misdaad', 0], ['Sciencefiction', 0], ['Thriller', 0]];

const discover = {
  loaded: p => shell(p, { title: 'Aanvragen', tags: ['Populair nu'], top: dTop(p), body: rail(p, 'Populaire films', D_FILMS, 0) + rail(p, 'Populaire series', D_SERIES, -1, true) }),
  filters: p => p === 'tv'
    ? shell(p, { title: 'Populaire films', tags: ['Drama'], panel: `<div class="panel"><div class="prow"><div class="bb"><div class="t">Soort</div><div class="v">Films</div></div>${I.chev}</div><div class="prow focus"><div class="bb"><div class="t">Genre</div><div class="v">Drama</div></div>${I.chev}</div><div class="prow"><div class="bb"><div class="t">Streamingdienst</div><div class="v">Alle</div></div>${I.chev}</div><div class="hr"></div><div class="back">${I.close} Filters wissen</div></div>`, body: `<div class="grid g5">${['zout', 'kzout', 'polder', 'glas', 'charge'].map(k => card(IT[k], { s: `${IT[k].y} · Drama` })).join('')}</div>` })
    : shell(p, { title: 'Aanvragen', tags: ['Populair nu'], top: dTop(p, 'Films', 'Drama'), body: `<div class="grid">${['zout', 'kzout', 'polder', 'glas', 'charge', 'sintel'].map(k => card(IT[k], { s: `${IT[k].y} · Drama` })).join('')}</div>`,
      over: p === 'ph' ? optSheet(p, 'Genre', GENRES) : `<div class="menu" style="left:calc(var(--in) + 15.5em);top:11.6em">${GENRES.map(([l, on]) => `<div class="o${on ? ' hover' : ''}">${l}${on ? I.check : ''}</div>`).join('')}</div>` }),
  notConfigured: p => shell(p, { title: 'Aanvragen', role: 'none', center: empty(I.requests, 'Aanvragen is niet ingesteld', `Koppel een Jellyseerr- of Overseerr-server aan het profiel ${USER} om films en series aan te vragen.${p === 'tv' ? ' Tip: dit is makkelijker in te stellen op je telefoon of computer.' : ''}`, btn('Aanvraagserver instellen', { k: 'pri', focus: p === 'tv' }) + btn('Terug naar Mijn Pleya')) }),
  loading: p => shell(p, { title: 'Aanvragen', tags: ['Populair nu'], top: dTop(p), body: `<div class="rl">Populaire films</div><div class="rb">${skCard.repeat(8)}</div><div class="rl next">Populaire series</div><div class="rb">${skCard.repeat(8)}</div>` }),
  empty: p => shell(p, { title: p === 'tv' ? 'Populaire series' : 'Aanvragen', tags: ['Series', 'Documentaire'], top: dTop(p, 'Series', 'Documentaire'), nostrip: true, center: empty(I.filter, 'Geen titels voor deze filters', 'Er zijn geen populaire series in het genre Documentaire. Dit is geen storing: de aanvraagserver antwoordde gewoon met een lege lijst.', btn('Filters wissen', { k: 'pri', focus: p === 'tv' }) + btn('Genre wijzigen')) }),
  error: p => shell(p, { title: 'Aanvragen', tags: ['Populair nu'], top: dTop(p), nostrip: true, center: empty(I.cloudoff, 'Kan de server niet bereiken', `De aanvraagserver ${SRV} reageert niet. Je filters en je plek in de lijst blijven staan.`, btn('Opnieuw proberen', { k: 'pri', focus: p === 'tv', ic: I.refresh }) + btn('Zoeken in bibliotheek')) }),
  moreError: p => { const n = { tv: 11, ph: 5, tb: 11, dk: 13 }[p]; const ks = ['charge', 'zout', 'sintel', 'glas', 'tears', 'polder', 'spring', 'coffee', 'kwacht', 'kzout', 'eleph', 'zout', 'glas'].slice(0, n); return shell(p, { title: 'Populaire films', tags: [`${n} geladen`, ['Volgende pagina mislukt', 'warn']], top: dTop(p, 'Films'), scrolled: true, body: `<div class="grid">${ks.map(k => card(IT[k])).join('')}${errTile(p)}</div>` }); },
  back: p => shell(p, { title: 'Aanvragen', tags: ['Populair nu'], top: dTop(p), body: rail(p, 'Populaire films', [['charge', ['wait', 'Aangevraagd']], ['zout'], ['sintel', ['ok', 'Beschikbaar']], ['glas', ['wait', 'Aangevraagd']], ['tears'], ['polder'], ['spring'], ['coffee']], 3) + rail(p, 'Populaire series', D_SERIES, -1, true), over: `<div class="toast ok">${I.check}Terug op Glasstad · status bijgewerkt naar Aangevraagd</div>` }),
};

// ---------- 2. Zoeken ----------
const phKb = `<div class="kb"><div class="r">${'qwertyuiop'.split('').map(c => `<span>${c}</span>`).join('')}</div><div class="r">${'asdfghjkl'.split('').map(c => `<span>${c}</span>`).join('')}</div><div class="r"><span class="m">⇧</span>${'zxcvbnm'.split('').map(c => `<span>${c}</span>`).join('')}<span class="m">⌫</span></div><div class="r"><span class="m">123</span><span class="w">spatie</span><span class="go">zoek</span></div><small>systeemtoetsenbord, niet door Pleya getekend</small></div>`;
const tvKb = `<div class="tvkb"><div class="line">${'abcdefghijklmnopqrstuvwxyz'.split('').map(c => `<span${c === 't' ? ' class="on"' : ''}>${c}</span>`).join('')}</div><div class="cap2">tvOS-systeemtoetsenbord · dicteren met de Siri Remote of typen op een iPhone in de buurt · Android TV toont zijn eigen Leanback-toetsenbord</div></div>`;
const sfield = (p, q, n, focus) => `<div class="sfield${focus && hasFocus(p) ? ' focus' : ''}">${I.search}<b>${q}</b>${focus ? '<i class="caret"></i>' : ''}${n ? `<span class="n">${n}</span>` : ''}</div>`;
function search(p, o) {
  const f = sfield(p, o.q, o.n, o.typing);
  const body = `${o.banner ?? ''}${o.body ?? ''}`;
  if (p === 'tv') return `${topnav('')}<div class="pg">${f}<div style="margin-top:26px;height:900px;overflow:hidden;margin-left:-20px;padding-left:20px"><div style="margin-top:${14 + (o.tvScroll ?? 0)}px">${body}</div></div>${o.center ?? ''}${o.typing ? tvKb : ''}</div>${hint('Menu', 'terug, de zoekopdracht blijft staan')}`;
  if (p === 'ph') return `${status}<div class="hdr">${f}<span class="cancel">Annuleer</span></div><div class="pg"><div class="ctx">${I.person} ${ctxOf()}</div>${body}${o.center ?? ''}</div>${o.typing ? phKb : tabbar}`;
  return `<div class="bar">${I.back}<h1>Zoeken</h1>${f}<span class="sub">${ctxOf()}</span></div><div class="pg">${body}${o.center ?? ''}</div>`;
}
const hint = (k, t) => `<div class="hint hintx"><kbd>${k}</kbd> ${t}</div>`;
const sect = (p, label, n, arr, fi, next) => `<div class="rl${next ? ' next' : ''}">${label}<span class="n">${n}</span></div><div class="rb">${arr.map(([k, c, s], i) => card(IT[k], { cap: c, s, focus: i === fi && hasFocus(p) })).join('')}</div>`;
const searchS = {
  input: p => search(p, { q: 'kus', typing: true, body: `<div class="recent"><div class="rl">Recent gezocht</div><div class="chipsx">${['kustlijn', 'sintel', 'wadlopers'].map(c => `<span class="cx">${I.clock}${c}</span>`).join('')}</div></div>` }),
  results: p => search(p, { q: 'kust', n: '5 resultaten', body: sect(p, 'In je bibliotheek', 1, [['kust', null, '2022 · 3 seizoenen · speelbaar']], -1) + sect(p, 'Via Aanvragen', 4, [['kwacht', null, '2024 · Film · aan te vragen'], ['kzout', ['wait', 'Aangevraagd']], ['klicht', ['part', 'Deels beschikbaar']], ['kust', ['ok', 'Beschikbaar']]], 0, true), tvScroll: -420 }),
  handoff: p => search(p, { q: 'kustwacht', center: empty(I.search, 'Niets in je bibliotheek voor ‘kustwacht’', 'Je bibliotheken zijn doorzocht en volledig beantwoord. Via Aanvragen kun je dezelfde zoekopdracht voortzetten zonder hem opnieuw te typen.', btn('Zoek ‘kustwacht’ via Aanvragen', { k: 'pri', focus: p === 'tv', ic: I.requests }) + btn('Zoekopdracht aanpassen')) }),
  noMatch: p => search(p, { q: 'kustwaxt', n: '0 resultaten', center: empty(I.search, 'Geen resultaten voor ‘kustwaxt’', 'Niets in je bibliotheek en niets via Aanvragen. Beide bronnen hebben geantwoord, dus dit is een lege uitkomst en geen storing.', btn('Zoekopdracht aanpassen', { k: 'pri', focus: p === 'tv' }) + btn('Ontdekken via Aanvragen')) }),
  incomplete: p => search(p, { q: 'kust', n: '1 resultaat · onvolledig', banner: `<div style="margin-bottom:1.2em;max-width:60em">${msg('warn', 'Aanvragen kon niet zoeken', `De aanvraagserver ${SRV} gaf geen antwoord. Wat je hieronder ziet komt alleen uit je bibliotheek.`, btn('Opnieuw proberen', { focus: p === 'tv', ic: I.refresh }))}</div>`, body: sect(p, 'In je bibliotheek', 1, [['kust', null, '2022 · 3 seizoenen · speelbaar']], -1) }),
};

// ---------- 3. Detail ----------
function detail(p, o) {
  const it = o.it, f = p === 'tv';
  const meta = `${it.k} · ${it.g} · ${it.y} · ${it.len}`;
  const stl = `<div class="stl">${o.cap ? cap(o.cap[0], o.cap[1], true) : ''}<span>${o.line}</span></div>`;
  const syn = `<div class="syn">${it.k === 'Serie' ? 'Drie generaties gidsen houden een familiebedrijf op het wad overeind terwijl het getij, de regels en de buren steeds minder meewerken.' : 'Een eenling trekt door een verlaten land op zoek naar wat ze kwijtraakte, en ontdekt onderweg dat de tocht langer heeft geduurd dan ze dacht.'} <span style="color:var(--ink-4)">(fixturetekst)</span></div>`;
  const facts = `<div class="facts"><div>Regie<b>Fixture Regisseur</b></div><div>Gesproken taal<b>Engels</b></div><div>TMDB<b>7,4</b></div><div>Status op ${SRV}<b>${o.raw}</b></div></div>`;
  const cast = `<div class="rl">Cast</div><div class="cast">${CAST.slice(0, p === 'ph' ? 4 : 6).map(c => `<div><i>${c[0]}</i>${c[1]}<small>${c[2]}</small></div>`).join('')}</div>`;
  const btns = o.btns.map((b, i) => btn(b[0], { k: i === 0 ? 'pri' : (b[2] ?? ''), focus: i === 0 && f, ic: b[1] })).join('') + (p === 'ph' ? '' : btn('', { k: 'icon', ic: I.more }));
  if (p === 'ph') return `<div class="dhero">${art(it, true)}</div><div class="dback">${I.back}</div>${status}<div class="dbody"><h1>${it.t}</h1><div class="meta">${meta}</div>${stl}<div class="brow">${btns}</div>${o.msg ?? ''}${syn}${o.msg ? '' : facts}<div class="rl">Cast</div><div class="cast">${CAST.slice(0, 4).map(c => `<div><i>${c[0]}</i>${c[1]}<small>${c[2]}</small></div>`).join('')}</div></div>${tabbar}`;
  return `<div class="bleed">${art(it, true)}<div class="sc"></div></div>${f ? topnav('Mijn Pleya') : `<div class="bar clear">${I.back}<span class="sub">${o.backTo ?? 'Aanvragen'}</span><span class="sub" style="margin-left:auto">${ctxOf()}</span></div>`}<div class="htext"><h1>${it.t}</h1><div class="meta">${meta}</div>${stl}${syn}<div class="brow">${btns}</div>${o.msg ?? ''}${facts}</div><div class="castr">${cast}</div>${f ? hint('Menu', `terug naar ${o.backTo ?? 'Aanvragen'}`) : ''}`;
}
const detailS = {
  unknown: p => detail(p, { it: IT.charge, line: 'Nog niet aangevraagd', raw: 'Onbekend', btns: [['Aanvragen', I.plus], ['Trailer', I.play]], backTo: 'zoekresultaten ‘kust’' }),
  pending: p => detail(p, { it: IT.charge, cap: ['wait', 'In afwachting'], line: 'Door jou aangevraagd op 6 oktober', raw: 'In afwachting', btns: [['Mijn aanvraag', I.requests], ['Trailer', I.play]] }),
  processing: p => detail(p, { it: IT.charge, cap: ['wait', 'Bezig'], line: 'Goedgekeurd; de server haalt de film op', raw: 'Bezig', btns: [['Status verversen', I.refresh], ['Trailer', I.play]] }),
  partial: p => detail(p, { it: IT.wad, cap: ['part', 'Deels beschikbaar'], line: 'Seizoen 1 beschikbaar · seizoen 2 aangevraagd · 3 nog aan te vragen', raw: 'Deels beschikbaar', btns: [['Meer seizoenen aanvragen', I.plus], ['Zoeken in bibliotheek', I.search]] }),
  availProven: p => detail(p, { it: IT.sintel, cap: ['ok', 'Beschikbaar'], line: 'Gevonden in je bibliotheek', raw: 'Beschikbaar', btns: [['Openen in bibliotheek', I.play], ['Trailer', null]], msg: msg('info', 'Pleya herkent deze titel in je bibliotheek', 'Open de titel in je bibliotheek om een bron te kiezen en af te spelen.') }),
  availUnknown: p => detail(p, { it: IT.sintel, cap: ['ok', `Beschikbaar volgens ${SRV}`], line: 'Niet gekoppeld aan een bron van dit profiel', raw: 'Beschikbaar', btns: [['Zoeken in bibliotheek: ‘Sintel’', I.search], ['Trailer', I.play]], msg: msg('warn', 'Waar hij staat is niet bekend', 'De aanvraagserver meldt beschikbaar, maar Pleya vindt de titel niet op een bron van dit profiel. Zoek in je bibliotheek om hem te openen.') }),
  declined: p => detail(p, { it: IT.charge, cap: ['no', 'Afgewezen'], line: 'Je aanvraag van 6 oktober is afgewezen · reden niet bekend', raw: 'Onbekend', btns: [['Opnieuw aanvragen', I.plus], ['Mijn aanvragen', I.requests]] }),
  refreshError: p => detail(p, { it: IT.charge, cap: ['unk', 'Status onbekend'], line: 'Laatst bekend om 10:42: In afwachting', raw: 'niet ververst', btns: [['Opnieuw laden', I.refresh], ['Trailer', I.play]], msg: msg('err', 'Status niet ververst', 'Kan de server niet bereiken. Zolang de status onbekend is biedt Pleya geen nieuwe aanvraag aan.') }),
};

// ---------- 4 t/m 6 en 8: overlays ----------
const sheet = (o) => `<div class="sheet${o.pop ? ' pop' : ''}"><div class="sh-head">${o.it ? `<div class="thumb">${art(o.it)}</div>` : ''}<div><div class="k">${o.k}</div><div class="t">${o.it ? o.it.t : o.title}</div>${o.it || o.sub ? `<div class="s">${o.sub ?? `${o.it.y} · ${o.it.k} · ${o.it.g}`}</div>` : ''}</div></div><div class="sh-body${o.scroll ? ' scroll' : ''}">${o.body}</div>${o.foot ? `<div class="sh-foot">${o.fc ? `<span class="fc">${o.fc}</span>` : ''}<span class="fb">${o.foot}</span></div>` : ''}</div>`;
const sr = (t, o = {}) => `<div class="sr${o.focus ? ' focus' : ''}${o.dis ? ' dis' : ''}${o.danger ? ' danger' : ''}">${o.pre ?? ''}<div class="bb"><div class="t">${t}</div>${o.s ? `<div class="s">${o.s}</div>` : ''}</div>${o.v ? `<span class="v">${o.v}</span>` : ''}${o.ctl ?? ''}</div>`;
const sw = on => `<span class="sw${on ? ' on' : ''}"></span>`;
const cb = s => `<span class="cb${s === 'on' ? ' on' : s === 'mix' ? ' mix' : ''}">${s === 'on' ? I.check : ''}</span>`;
const quota = (t, k = '') => `<div class="quota ${k}">${I.clock}${t}</div>`;
const FC = `Op naam van ${USER} · ${SRV}`;
const FCM = `Op naam van ${MGR} · ${SRV}`;
const season = (n, st, f) => st === 'avail' ? sr(`Seizoen ${n}`, { pre: cb(), dis: true, ctl: cap('ok', 'Beschikbaar', true) }) : st === 'req' ? sr(`Seizoen ${n}`, { pre: cb(), dis: true, ctl: cap('wait', 'Aangevraagd', true) }) : sr(`Seizoen ${n}`, { pre: cb(st), focus: f, v: `${8 + (n % 3) * 2} afleveringen` });

const film = (p, o) => { const f = p === 'tv'; return sheet({ k: o.k ?? 'Film aanvragen', it: IT.charge, body: o.body(f), foot: o.foot(f), fc: o.fc === undefined ? FC : o.fc }); };
const q4k = (on, f) => sr('In 4K aanvragen', { s: on ? 'Kwaliteit: 4K' : 'Kwaliteit: standaard (HD)', ctl: sw(on), focus: f });
const filmS = {
  def: p => film(p, { body: f => q4k(false) + quota('Nog 3 van 5 aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen', { k: 'pri', focus: f }) }),
  no4k: p => film(p, { body: f => sr('Kwaliteit', { s: 'Dit profiel mag films niet in 4K aanvragen. Voor series geldt een eigen recht.', v: 'Standaard (HD)', ctl: I.lock }) + quota('Onbeperkt aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen', { k: 'pri', focus: f }) }),
  quotaUnknown: p => film(p, { body: f => q4k(false) + quota('Limiet onbekend · de server beslist bij het indienen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen', { k: 'pri', focus: f }) }),
  quotaOut: p => film(p, { body: f => q4k(false) + quota('Nog 0 van 5 aanvragen', 'err') + msg('warn', 'Je limiet is bereikt', 'Je kunt nu geen film aanvragen. De aanvraagserver bepaalt wanneer er weer ruimte is.'), foot: f => btn('Aanvragen', { k: 'pri', dis: true }) + btn('Sluiten', { focus: f }) }),
  duplicate: p => film(p, { body: f => msg('info', 'Al aangevraagd', 'Deze film is op 6 oktober door jou aangevraagd en staat op In afwachting. Een tweede aanvraag wordt niet verstuurd.'), foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Aanvraag bekijken', { k: 'pri', focus: f }), fc: null }),
  noRight: p => film(p, { body: f => msg('err', 'Je hebt hier geen rechten voor', `Het profiel ${USER} mag op ${SRV} geen aanvragen doen. De beheerder van de aanvraagserver kan dat aanpassen.`), foot: f => btn('Sluiten', { focus: f }), fc: null }),
  submitting: p => film(p, { body: f => `<div style="opacity:.5">${q4k(true)}${quota('Nog 3 van 5 aanvragen')}</div>`, foot: f => btn('Annuleren', { k: 'ghost', dis: true }) + btn('Aanvragen…', { k: 'pri', busy: true, dis: true }) }),
  error: p => film(p, { body: f => msg('err', 'Aanvragen mislukt. Probeer opnieuw.', 'Kan de server niet bereiken. Er is niets verstuurd; je keuzes hieronder staan er nog.') + q4k(true) + quota('Nog 3 van 5 aanvragen'), foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Opnieuw proberen', { k: 'pri', focus: f, ic: I.refresh }) }),
  uncertain: p => film(p, { body: f => msg('warn', 'Niet zeker of de aanvraag is aangekomen', 'De verbinding viel weg nadat de aanvraag was verstuurd. Pleya leest eerst de status opnieuw; pas als er geen aanvraag blijkt te staan kun je opnieuw indienen.'), foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Status controleren', { k: 'pri', focus: f, ic: I.refresh }) }),
  rejected: p => film(p, { body: f => msg('err', 'De server heeft de aanvraag geweigerd', 'Antwoord 403: niet toegestaan voor dit profiel. De aanvraag is niet opnieuw verstuurd. De beheerder van de aanvraagserver kan het recht aanpassen.') + `<div style="opacity:.5">${q4k(true)}</div>`, foot: f => btn('Sluiten', { focus: f }) }),
  success: p => film(p, { k: 'Film aangevraagd', body: f => `<div class="big">${I.check}<h3>Aangevraagd</h3><p>Charge staat op In afwachting. Detail, Mijn aanvragen en de aantallen zijn opnieuw geladen.</p></div>`, foot: f => btn('Mijn aanvragen', { k: 'ghost' }) + btn('Klaar', { k: 'pri', focus: f }) }),
};

const serie = (p, o) => { const f = p === 'tv'; const it = o.it ?? IT.wad; return sheet({ k: o.k ?? 'Seizoenen kiezen', it, sub: `${it.y} · Serie · ${it.n} seizoenen`, scroll: o.scroll, body: o.body(f), foot: o.foot(f), fc: o.fc === undefined ? FC : o.fc }); };
const allRow = (st, s, f) => sr('Alle seizoenen', { pre: cb(st), s, focus: f });
const serieS = {
  all: p => serie(p, { body: f => allRow('on', '3 van 3 aanvraagbare seizoenen gekozen') + season(1, 'avail') + season(2, 'req') + season(3, 'on') + season(4, 'on') + season(5, 'on') + q4k(false) + quota('Nog 6 van 10 aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('3 seizoenen aanvragen', { k: 'pri', focus: f }) }),
  one: p => serie(p, { body: f => allRow('mix', '1 van 3 aanvraagbare seizoenen gekozen') + season(1, 'avail') + season(2, 'req') + season(3, '') + season(4, '') + season(5, 'on', f) + q4k(false) + quota('Nog 6 van 10 aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Seizoen 5 aanvragen', { k: 'pri' }) }),
  multi: p => serie(p, { body: f => allRow('mix', '2 van 3 aanvraagbare seizoenen gekozen', f) + season(1, 'avail') + season(2, 'req') + season(3, 'on') + season(4, '') + season(5, 'on') + q4k(false) + quota('Nog 6 van 10 aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Seizoenen 3 en 5 aanvragen', { k: 'pri' }) }),
  long: p => serie(p, { it: IT.dijk, scroll: true, body: f => `<div class="fade-t"></div>${season(5, 'avail')}${season(6, 'req')}${season(7, 'on')}${season(8, 'on')}${season(9, 'on', f)}${season(10, '')}${season(11, 'on')}${season(12, 'on')}<div class="fade-b"></div><div class="sbar"><i></i></div>`, foot: f => btn('Annuleren', { k: 'ghost' }) + btn('7 seizoenen aanvragen', { k: 'pri' }), fc: 'Seizoen 9 van 14' }),
  none: p => serie(p, { body: f => msg('info', 'Er valt niets meer aan te vragen', 'Elk seizoen is al beschikbaar of aangevraagd.') + season(1, 'avail') + season(2, 'avail') + season(3, 'req') + season(4, 'req') + season(5, 'req'), foot: f => btn('Aanvragen', { k: 'pri', dis: true }) + btn('Sluiten', { focus: f }), fc: null }),
  fourK: p => serie(p, { body: f => allRow('on', '3 van 3 aanvraagbare seizoenen gekozen') + season(3, 'on') + season(4, 'on') + season(5, 'on') + q4k(true, f) + quota('Nog 2 van 10 aanvragen · de server beslist of 3 seizoenen passen', 'warn'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('3 seizoenen in 4K aanvragen', { k: 'pri' }) }),
  submitting: p => serie(p, { body: f => `<div style="opacity:.5">${allRow('mix', '2 van 3 aanvraagbare seizoenen gekozen')}${season(3, 'on')}${season(4, '')}${season(5, 'on')}${q4k(false)}</div>`, foot: f => btn('Annuleren', { k: 'ghost', dis: true }) + btn('Aanvragen…', { k: 'pri', busy: true, dis: true }) }),
  error: p => serie(p, { body: f => msg('err', 'Aanvragen mislukt. Probeer opnieuw.', 'Er ging iets mis op de server. Je keuze voor seizoen 3 en 5 staat er nog.') + allRow('mix', '2 van 3 aanvraagbare seizoenen gekozen') + season(3, 'on') + season(4, '') + season(5, 'on') + q4k(false), foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Opnieuw proberen', { k: 'pri', focus: f, ic: I.refresh }) }),
  success: p => serie(p, { k: 'Seizoenen aangevraagd', body: f => `<div class="big">${I.check}<h3>2 seizoenen aangevraagd</h3><p>Wadlopers seizoen 3 en 5 staan op In afwachting. De detailstatus is nu Deels beschikbaar met 1 seizoen nog aan te vragen.</p></div>`, foot: f => btn('Mijn aanvragen', { k: 'ghost' }) + btn('Klaar', { k: 'pri', focus: f }) }),
};

const advSec = `<div class="sec">${I.sliders}Geavanceerde opties<span class="r">alleen beheerder</span></div>`;
const adv = (p, o) => { const f = p === 'tv'; return sheet({ k: o.k ?? 'Film aanvragen', it: o.it ?? IT.charge, sub: o.sub, body: o.body(f), foot: o.foot(f), fc: o.fc === undefined ? FCM : o.fc }); };
const sp = `<i class="spin"></i>`;
const advS = {
  admin: p => adv(p, { body: f => q4k(false) + advSec + sr('Server', { v: 'Radarr · HD', ctl: I.chev, pre: I.server, focus: f }) + sr('Kwaliteitsprofiel', { v: 'HD-1080p', ctl: I.chev }) + sr('Hoofdmap', { v: '/media/films', s: '1,2 TB vrij', ctl: I.chev, pre: I.folder }) + quota('Onbeperkt aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen', { k: 'pri' }) }),
  nonAdmin: p => adv(p, { fc: FC, body: f => q4k(false) + quota('Nog 3 van 5 aanvragen'), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen', { k: 'pri', focus: f }) }),
  serieAdmin: p => adv(p, { k: 'Seizoenen kiezen', it: IT.wad, sub: '2023 · Serie · 5 seizoenen', body: f => allRow('on', '3 van 3 aanvraagbare seizoenen gekozen') + q4k(false) + advSec + sr('Server', { v: 'Sonarr · HD', ctl: I.chev, pre: I.server, focus: f }) + sr('Kwaliteitsprofiel', { v: 'WEB-1080p', ctl: I.chev }) + sr('Hoofdmap', { v: '/media/series', s: '860 GB vrij', ctl: I.chev, pre: I.folder }), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('3 seizoenen aanvragen', { k: 'pri' }) }),
  pick4k: p => adv(p, { k: 'Server kiezen', sub: '4K staat aan: alleen 4K-servers', body: f => sr('Radarr 4K', { s: 'Standaard voor 4K', pre: I.server, ctl: I.check, focus: f }) + sr('Radarr 4K Remux', { pre: I.server }) + `<div class="sec" style="color:var(--ink-4)">${I.info}Radarr · HD en Radarr · Anime staan hier niet: een HD-server past niet bij een 4K-aanvraag.</div>`, foot: f => btn('Terug', { k: 'ghost' }), fc: null }),
  reload: p => adv(p, { body: f => q4k(true) + advSec + sr('Server', { v: 'Radarr 4K', ctl: I.chev, pre: I.server }) + sr('Kwaliteitsprofiel', { v: `${sp} Laden…` }) + sr('Hoofdmap', { v: `${sp} Laden…`, pre: I.folder }) + msg('info', 'Server gewijzigd', 'HD-1080p en /media/films horen bij de vorige server en zijn gewist. De opties van Radarr 4K worden opgehaald.'), foot: f => btn('Annuleren', { k: 'ghost', focus: f }) + btn('Aanvragen', { k: 'pri', dis: true }) }),
  reloaded: p => adv(p, { body: f => q4k(true) + advSec + sr('Server', { v: 'Radarr 4K', ctl: I.chev, pre: I.server }) + sr('Kwaliteitsprofiel', { v: 'Ultra-HD', s: 'Standaard van deze server', ctl: I.chev, focus: f }) + sr('Hoofdmap', { v: '/media/films-4k', s: 'Standaard van deze server · 3,4 TB vrij', ctl: I.chev, pre: I.folder }), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('In 4K aanvragen', { k: 'pri' }) }),
  error: p => adv(p, { body: f => q4k(false) + advSec + msg('err', 'Opties van de server niet geladen', 'Servers, profielen en hoofdmappen zijn onbekend. Indienen kan nog steeds: dan kiest de aanvraagserver zijn eigen standaard.', btn('Opnieuw', { focus: f, ic: I.refresh })) + sr('Server', { v: 'Onbekend', dis: true, pre: I.server }) + sr('Kwaliteitsprofiel', { v: 'Onbekend', dis: true }) + sr('Hoofdmap', { v: 'Onbekend', dis: true, pre: I.folder }), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Aanvragen met serverstandaard', { k: 'pri' }) }),
  noConfig: p => adv(p, { body: f => q4k(true, f) + advSec + msg('warn', 'Geen 4K-server ingesteld', `Op ${SRV} is voor films geen Radarr-server met 4K gekoppeld. Zet 4K uit om in HD aan te vragen; Pleya stuurt geen 4K-aanvraag naar een HD-server.`) + sr('Server', { v: 'Geen', dis: true, pre: I.server }) + sr('Kwaliteitsprofiel', { v: 'Geen', dis: true }) + sr('Hoofdmap', { v: 'Geen', dis: true, pre: I.folder }), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('In 4K aanvragen', { k: 'pri', dis: true }) }),
};

const mrow = (ic, l, o = {}) => sr(l, { pre: ic, ...o });
const mgmtSheets = {
  menuMgr: p => sheet({ pop: 1, k: `In afwachting · aangevraagd door Ravi`, it: IT.wad, sub: 'Serie · seizoen 3 tot en met 5', body: mrow(I.info, 'Titel openen') + mrow(I.check, 'Goedkeuren', { focus: p === 'tv' }) + mrow(I.close, 'Afwijzen') + mrow(I.edit, 'Bewerken'), foot: btn('Sluiten') }),
  menuOwn: p => sheet({ pop: 1, k: 'In afwachting · jouw aanvraag', it: IT.charge, sub: 'Film · aangevraagd op 6 oktober', body: mrow(I.info, 'Titel openen', { focus: p === 'tv' }) + mrow(I.edit, 'Bewerken') + mrow(I.trash, 'Aanvraag annuleren', { danger: 1 }), foot: btn('Sluiten') }),
  menuRead: p => sheet({ pop: 1, k: 'Goedgekeurd · jouw aanvraag', it: IT.glas, sub: 'Film · aangevraagd op 2 oktober', body: mrow(I.info, 'Titel openen', { focus: p === 'tv' }) + `<div class="sec" style="color:var(--ink-4)">${I.lock}Annuleren en bewerken kan alleen zolang een aanvraag op In afwachting staat. Goedkeuren en afwijzen vragen het beheerrecht.</div>`, foot: btn('Sluiten') }),
  cancel: p => sheet({ k: 'Aanvraag annuleren', it: IT.charge, sub: 'Film · In afwachting · aangevraagd op 6 oktober', body: `<div class="sr"><div class="bb"><div class="t">Deze aanvraag annuleren?</div><div class="s">De aanvraag verdwijnt van de aanvraagserver. Je kunt de film daarna opnieuw aanvragen.</div></div></div>`, foot: btn('Aanvraag annuleren', { k: 'danger' }) + btn('Niet annuleren', { k: 'pri', focus: p === 'tv' }) }),
  editSerie: p => serie(p, { k: 'Aanvraag bewerken', body: f => allRow('mix', 'Aangevraagd: seizoen 3, 4 en 5') + season(1, 'avail') + season(2, 'req') + season(3, 'on') + season(4, '', f) + season(5, 'on') + q4k(false), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Wijziging opslaan', { k: 'pri' }), fc: 'Seizoen 4 gaat uit de aanvraag' }),
  editFilm: p => adv(p, { k: 'Aanvraag bewerken · Ravi', it: IT.tears, body: f => q4k(true, f) + advSec + sr('Server', { v: 'Radarr 4K', ctl: I.chev, pre: I.server }) + sr('Kwaliteitsprofiel', { v: 'Ultra-HD', s: 'Opnieuw gekozen na de 4K-wissel', ctl: I.chev }) + sr('Hoofdmap', { v: '/media/films-4k', ctl: I.chev, pre: I.folder }), foot: f => btn('Annuleren', { k: 'ghost' }) + btn('Wijziging opslaan', { k: 'pri' }), fc: `Bewerkt door ${MGR} · ${SRV}` }),
  editForbidden: p => sheet({ k: 'Aanvraag bewerken', it: IT.wad, sub: 'Serie · aangevraagd door Ravi', body: msg('err', 'Je hebt hier geen rechten voor', 'De server weigerde de wijziging (403). De aanvraag is niet aangepast en staat nog zoals hij stond.'), foot: btn('Sluiten', { focus: p === 'tv' }) }),
  editUnsupported: p => sheet({ k: 'Aanvraag bewerken', it: IT.glas, sub: 'Film · Goedgekeurd', body: msg('info', 'Bewerken kan niet meer', 'Deze aanvraag is al goedgekeurd. Alleen een aanvraag op In afwachting is aan te passen; daarna beslist de server.'), foot: btn('Sluiten', { focus: p === 'tv' }) }),
  editBusy: p => serie(p, { k: 'Aanvraag bewerken', body: f => `<div style="opacity:.5">${allRow('mix', 'Aangevraagd: seizoen 3 en 5')}${season(3, 'on')}${season(4, '')}${season(5, 'on')}</div>`, foot: f => btn('Annuleren', { k: 'ghost', dis: true }) + btn('Opslaan…', { k: 'pri', busy: true, dis: true }) }),
  // Uitkomst onbekend, zelfde patroon als 4I: de wijziging is verstuurd, het antwoord kwam niet
  // terug. Geen bewering over de server en geen tweede PUT voordat de aanvraag herlezen is.
  // Een bekende weigering is 8G.
  editError: p => serie(p, { k: 'Aanvraag bewerken', body: f => msg('warn', 'Niet zeker of de wijziging is opgeslagen', 'De verbinding viel weg nadat de wijziging was verstuurd. Pleya leest eerst de aanvraag opnieuw. Je keuze hieronder blijft staan; opnieuw opslaan kan pas als de aanvraag nog de oude seizoenen blijkt te hebben.') + allRow('mix', 'Jouw keuze: seizoen 3 en 5') + season(3, 'on') + season(4, '') + season(5, 'on'), foot: f => btn('Sluiten', { k: 'ghost' }) + btn('Status controleren', { k: 'pri', focus: f, ic: I.refresh }), fc: 'Op de server: nog niet opnieuw gelezen' }),
};

// ---------- 7. Aanvragenlijst ----------
const NOART = { t: 'Titel niet geladen', y: '', g: '', k: 'Film', noart: 1 };
const REQ = [
  ['charge', 'wait', 'In afwachting', USER, 'Film', '6 okt'], ['wad', 'wait', 'In afwachting', 'Ravi', 'Serie · seizoen 3–5', '6 okt'], ['zout', 'no', 'Afgewezen', 'Ravi', 'Film', '5 okt'],
  ['sintel', 'ok', 'Beschikbaar', MGR, 'Film', '4 okt'], ['glas', 'wait', 'Goedgekeurd', USER, 'Film', '2 okt'], ['kust', 'ok', 'Beschikbaar', 'Ravi', 'Serie · seizoen 1–3', '1 okt'],
  ['tears', 'wait', 'In afwachting', 'Ravi', 'Film · 4K', '30 sep'], [null, 'wait', 'In afwachting', 'Ravi', 'Film · TMDB 550988', '29 sep'], ['nacht', 'part', 'Deels beschikbaar', USER, 'Serie · seizoen 1–2', '28 sep'],
  ['onder', 'wait', 'Goedgekeurd', MGR, 'Serie · seizoen 4', '27 sep'], ['polder', 'no', 'Mislukt', 'Ravi', 'Film', '25 sep'], ['spring', 'ok', 'Beschikbaar', USER, 'Film', '24 sep'],
];
const rcard = (r, p, o = {}) => { const it = r[0] ? IT[r[0]] : NOART; const c = o.cap ?? [r[1], r[2]]; return `<div class="card${o.focus ? ' focus' : ''}${o.busy ? ' busy' : ''}"><div class="art${it.noart ? ' ph0' : ''}">${it.noart ? I.film : art(it)}${cap(...c)}</div><div class="t">${it.t}</div><div class="s">${it.noart ? r[4] : `${it.y} · ${r[4]}`}</div><div class="by">${o.mine ? `Aangevraagd op ${r[5]}` : `Aangevraagd door ${r[3]}`}</div></div>`; };
const rrow = (r, p, o = {}) => { const it = r[0] ? IT[r[0]] : NOART; const c = o.cap ?? [r[1], r[2]]; const pend = c[1] === 'In afwachting';
  const acts = o.busy ? '' : (o.role === 'mgr' && pend ? btn('Goedkeuren', { k: 'pri' }) + btn('Afwijzen') : '') + (o.role !== 'mgr' && pend ? btn('Annuleren') : '') + (p === 'ph' ? '' : btn('', { k: 'icon', ic: I.more }));
  return `<div class="lrow${o.focus && p === 'dk' ? ' hover' : ''}${o.busy ? ' busy' : ''}"><div class="thumb">${it.noart ? I.film : art(it)}</div><div class="bb"><div class="t">${it.t}</div><div class="s">${it.noart || p === 'ph' ? r[4] : `${it.y} · ${r[4]}`} · ${o.mine ? r[5] : `door ${r[3]} · ${r[5]}`}</div></div>${cap(c[0], c[1], true)}${acts ? `<div class="acts">${acts}</div>` : ''}</div>`; };
const COUNTS = [['Alles', 389], ['In afwachting', 27], ['Goedgekeurd', 108], ['Beschikbaar', 35], ['Afgewezen', 14]];
// o: role, scope ('mine'|'all'), count, sel (statusfilter), counts ('known'|'unknown'|'failed'), countOver (afwijkende telling van /request/count in deze staat), open (TV-rail), rows[], per-rij opties, center, tail, toast, skeleton
function list(p, o) {
  const mine = o.scope !== 'all', mgr = o.role === 'mgr';
  const title = mine ? 'Mijn aanvragen' : 'Alle aanvragen';
  const sel = o.sel ?? 'Alles';
  const cnt = l => o.counts === 'known' ? (o.countOver?.[l] ?? COUNTS.find(c => c[0] === l)[1]) : o.counts === 'failed' ? '–' : '';
  // Een aantal komt uit de telling van hetzelfde bereik, nooit uit de geladen pagina. Een lege
  // lijst naast een bekend aantal boven nul op het gekozen filter is een tegenspraak.
  if (o.counts === 'known' && o.center && !(o.rows ?? []).length && cnt(sel) !== 0) problems.push(`lijst ${p}: leeg op ${sel} maar de telling zegt ${cnt(sel)}`);
  const tags = [...(o.count ? [o.count] : []), ...(o.countWarn ? [[o.countWarn, 'warn']] : []), ...(sel !== 'Alles' ? [sel] : []), 'Nieuwste eerst', ...(mgr ? [mine ? 'Bereik: mijn' : 'Bereik: alle'] : [])];
  const rows = o.rows ?? [];
  const per = (r, i) => ({ focus: i === o.fi && hasFocus(p), busy: i === o.bi, cap: i === o.ci ? o.cc : i === o.bi ? ['busy', 'Bezig…'] : undefined, mine, role: o.role });
  if (p === 'tv') {
    const panel = o.open ? `<div class="panel"><div class="back">${I.back} Status</div><div class="hr"></div>${COUNTS.map(([l]) => `<div class="opt${l === sel ? ' on focus' : ''}">${l === sel ? I.check : ''}${l}<span class="n">${cnt(l)}</span></div>`).join('')}${o.counts === 'known' ? '' : `<div class="hr"></div><div class="pf">${o.counts === 'failed' ? 'Aantallen niet geladen. Een streepje is geen nul.' : 'Aantallen zijn er alleen voor Alle aanvragen.'}</div>`}${mgr ? `<div class="hr"></div><div class="prow"><div class="bb"><div class="t">Bereik</div><div class="v">${mine ? 'Mijn aanvragen' : 'Alle aanvragen'}</div></div>${I.chev}</div>` : ''}</div>` : null;
    const grid = o.skeleton ? `<div class="grid">${skCard.repeat(12)}</div>` : rows.length ? `<div class="grid${o.open ? ' g5' : ''}">${rows.map((r, i) => rcard(r, p, per(r, i))).join('')}${o.tail ? errTile(p) : ''}</div>` : '';
    return shell(p, { role: o.role, title, tags, panel, body: grid || undefined, scrolled: !!o.tail, nostrip: !!o.center, center: o.center, over: o.toast });
  }
  const top = `${mgr ? `<div class="seg"><span class="${mine ? '' : 'on'}">Alle aanvragen</span><span class="${mine ? 'on' : ''}">Mijn aanvragen</span></div>` : ''}<div class="chipsx">${(p !== 'ph' ? COUNTS : COUNTS.slice(0, 3).some(c => c[0] === sel) ? COUNTS.slice(0, 3) : [COUNTS[0], COUNTS.find(c => c[0] === sel), COUNTS[1]]).map(([l]) => `<span class="cx${l === sel ? ' on' : ''}">${l}${cnt(l) !== '' ? ` <span class="n">${cnt(l)}</span>` : ''}</span>`).join('')}${p === 'ph' ? `<span class="cx">${I.chevd}</span>` : `<span class="cx txt">Nieuwste eerst</span>`}</div>${o.counts === 'known' || o.center || o.skeleton ? '' : `<div class="foot-note">${I.info}${o.counts === 'failed' ? 'Aantallen niet geladen. Een streepje is geen nul.' : 'Aantallen zijn er alleen voor Alle aanvragen.'}</div>`}`;
  const n = { ph: 6, tb: 8, dk: 10 }[p];
  const body = o.skeleton ? `<div class="lrows">${'<div class="lrow sk"><div class="thumb"></div><div class="bb"><div class="skl" style="width:40%"></div><div class="skl" style="width:25%"></div></div></div>'.repeat(n)}</div>`
    : rows.length ? `<div class="lrows">${rows.slice(0, o.tail ? { ph: 3, tb: 5, dk: 7 }[p] : n).map((r, i) => rrow(r, p, per(r, i))).join('')}${o.tail ? `<div class="lrow">${msg('warn', 'Meer laden mislukt', 'Wat al geladen was blijft staan.', btn('Opnieuw', { ic: I.refresh })).replace('class="msg', 'style="flex:1;background:none;padding:0" class="msg')}</div>` : ''}</div>` : '';
  return shell(p, { role: o.role, title: p === 'ph' ? 'Aanvragen' : title, tags: tags.filter(t => typeof t !== 'string' || !t.startsWith('Bereik') && t !== 'Nieuwste eerst'), top, body, center: o.center, over: o.toast });
}
const MINE = REQ.filter(r => r[3] === USER);
const PEND = REQ.filter(r => r[2] === 'In afwachting');
const listS = {
  mine: p => list(p, { role: 'user', scope: 'mine', rows: MINE, fi: 0 }),
  all: p => list(p, { role: 'mgr', scope: 'all', count: '389 aanvragen', counts: 'known', rows: REQ, fi: 1 }),
  status: p => list(p, { role: 'mgr', scope: 'all', count: '27 van 389', counts: 'known', sel: 'In afwachting', open: true, rows: PEND }),
  countsUnknown: p => list(p, { role: 'mgr', scope: 'mine', counts: 'unknown', open: true, rows: REQ.filter(r => r[3] === MGR) }),
  countsFailed: p => list(p, { role: 'mgr', scope: 'all', countWarn: 'Aantal onbekend', counts: 'failed', open: true, rows: REQ }),
  loading: p => list(p, { role: 'user', scope: 'mine', skeleton: true }),
  empty: p => list(p, { role: 'user', scope: 'mine', center: empty(I.requests, 'Er is nog niets aangevraagd.', 'Dit is een lege lijst, geen storing. Zoek een titel of blader door wat er populair is.', btn('Ontdekken', { k: 'pri', focus: p === 'tv' }) + btn('Zoeken', { ic: I.search })) }),
  filteredEmpty: p => list(p, { role: 'mgr', scope: 'all', counts: 'known', countOver: { Alles: 375, Afgewezen: 0 }, sel: 'Afgewezen', count: '0 van 375', center: empty(I.filter, 'Er staat op dit moment niets op Afgewezen.', 'De aanvraagserver telt 0 afgewezen aanvragen. De andere statussen hebben er wel.', btn('Filters wissen', { k: 'pri', focus: p === 'tv' })) }),
  error: p => list(p, { role: 'user', scope: 'mine', center: empty(I.cloudoff, 'Kan de server niet bereiken', `De aanvraagserver ${SRV} reageert niet. Je filter blijft staan.`, btn('Opnieuw proberen', { k: 'pri', focus: p === 'tv', ic: I.refresh })) }),
  moreError: p => list(p, { role: 'mgr', scope: 'all', count: '389 aanvragen', counts: 'known', rows: REQ.slice(0, 11), tail: true }),
  changed: p => list(p, { role: 'mgr', scope: 'all', count: '389 aanvragen', counts: 'known', rows: REQ, fi: 1, ci: 1, cc: ['wait', 'Goedgekeurd'], toast: `<div class="toast ok">${I.check}Wadlopers goedgekeurd · lijst en aantallen opnieuw geladen</div>` }),
  busy: p => list(p, { role: 'mgr', scope: 'all', count: '389 aanvragen', counts: 'known', rows: REQ, bi: 1 }),
  actError: p => list(p, { role: 'mgr', scope: 'all', count: '389 aanvragen', counts: 'known', rows: REQ, fi: 1, toast: `<div class="toast err">${I.warn}Goedkeuren mislukt. De aanvraag staat nog op In afwachting; de lijst is opnieuw geladen.</div>` }),
};

// ---------- staten: familie, naam, rol, status t.o.v. de huidige bron, bedoeling ----------
// built: B = bestaand gedrag, hier in northstartaal getekend · W = gedrag wijzigt t.o.v. de
// bron van 8 oktober · N = nieuw oppervlak, niet gebouwd.
const FAM = { 1: 'Ontdekken', 2: 'Zoeken', 3: 'Detail film/serie', 4: 'Aanvraag film', 5: 'Aanvraag serie', 6: 'Advanced target', 7: 'Aanvragenlijst', 8: 'Aanvraagbeheer' };
const S = [];
const add = (fam, name, role, built, intent, kind, r, u) => S.push({ fam, name, role, built, intent, kind, r, u });
const scr = (fam, name, role, built, intent, r) => add(fam, name, role, built, intent, 'scherm', r);
const ovl = (fam, name, role, built, intent, r, u) => add(fam, name, role, built, intent, 'overlay', r, u);

scr(1, 'Geladen', 'aanvrager', 'B', 'Mockup 35 A met de profiel- en servercontext als tag erbij', discover.loaded);
scr(1, 'Filters open', 'aanvrager', 'B', 'De bestaande ontdekfilters: soort, genre, streamingdienst (35 B)', discover.filters);
scr(1, 'Niet ingesteld', 'geen koppeling', 'B', 'Geen Opnieuw-knop: er is niets te herhalen, alleen iets in te stellen', discover.notConfigured);
scr(1, 'Laden', 'aanvrager', 'B', 'Skelet in de kaartmaat, kop en filters staan er al', discover.loading);
scr(1, 'Leeg na filter', 'aanvrager', 'W', 'Leeg is geen fout: Filters wissen in plaats van Opnieuw', discover.empty);
scr(1, 'Fout met opnieuw proberen', 'aanvrager', 'B', 'Echte fout houdt Opnieuw, filters blijven staan', discover.error);
scr(1, 'Meer laden mislukt', 'aanvrager', 'W', 'Paginafout als tegel aan het eind; geladen kaarten blijven', discover.moreError);
scr(1, 'Terugkeer naar gekozen kaart', 'aanvrager', 'W', 'Terug uit detail landt op dezelfde kaart, met de nieuwe status', discover.back);

scr(2, 'Invoer met systeemtoetsenbord', 'aanvrager', 'B', 'Native invoer per platform; Pleya tekent geen eigen toetsenbord', searchS.input);
scr(2, 'Resultaten gemengd', 'aanvrager', 'W', 'Bibliotheek en Aanvragen als aparte koppen; capsule zegt beschikbaar, aangevraagd of deels', searchS.results);
scr(2, 'Geen match in bibliotheek, door naar Aanvragen', 'aanvrager', 'B', 'Mockup 36 C: de query gaat mee', searchS.handoff);
scr(2, 'Nergens een match', 'aanvrager', 'B', 'Beide bronnen antwoordden; leeg, geen storing', searchS.noMatch);
scr(2, 'Onvolledig: Aanvragen antwoordde niet', 'aanvrager', 'W', 'Alleen getoond als de fout bekend is; bibliotheekresultaten blijven', searchS.incomplete);

scr(3, 'Nog niet aangevraagd (unknown)', 'aanvrager', 'B', 'Aanvragen is de primaire actie', detailS.unknown);
scr(3, 'In afwachting (pending)', 'aanvrager, eigen aanvraag', 'W', 'Primaire actie opent de eigen aanvraag in plaats van een dode knop', detailS.pending);
scr(3, 'Bezig (processing)', 'aanvrager', 'W', 'Geen aanvraagknop; verversen is de zinvolle actie', detailS.processing);
scr(3, 'Deels beschikbaar (partial), serie', 'aanvrager', 'B', 'Meer seizoenen aanvragen naast zoeken in de bibliotheek', detailS.partial);
scr(3, 'Beschikbaar, identiteit bewezen', 'aanvrager', 'N', 'Opent het bestaande Pleya-detail; noemt geen bron en speelt niet zelf af', detailS.availProven);
scr(3, 'Beschikbaar, bron onbekend', 'aanvrager', 'N', 'Zoekroute met de titel als query; geen afspeelbelofte', detailS.availUnknown);
scr(3, 'Afgewezen', 'aanvrager', 'W', 'Afwijzing zichtbaar waar bekend; opnieuw aanvragen als het recht er is', detailS.declined);
scr(3, 'Status niet ververst', 'aanvrager', 'W', 'Onbekend is niet beschikbaar en niet aanvraagbaar', detailS.refreshError);

const U = { c: IT.charge, w: IT.wad, d: IT.dijk };
ovl(4, 'Standaard: 4K toegestaan, limiet bekend', 'aanvrager met 4K-film', 'B', 'Titel, kwaliteit en limiet in één blik', filmS.def, U.c);
ovl(4, '4K niet toegestaan voor films, onbeperkt', 'aanvrager zonder 4K-film', 'W', '4K-recht is per soort; de regel legt uit waarom er geen schakelaar is', filmS.no4k, U.c);
ovl(4, 'Limiet onbekend', 'aanvrager', 'W', 'Onbekend is geen nul en geen onbeperkt', filmS.quotaUnknown, U.c);
ovl(4, 'Limiet bereikt', 'aanvrager', 'B', 'Indienen uit, focus op Sluiten', filmS.quotaOut, U.c);
ovl(4, 'Al aangevraagd (duplicaat)', 'aanvrager', 'B', 'Geen tweede aanvraag; wel de weg naar de bestaande', filmS.duplicate, U.c);
ovl(4, 'Geen aanvraagrecht', 'profiel zonder recht', 'B', 'Bestaande foutcopy, geen formulier', filmS.noRight, U.c);
ovl(4, 'Bezig met indienen', 'aanvrager', 'B', 'Eén keer verstuurd; beide knoppen uit', filmS.submitting, U.c);
ovl(4, 'Fout, keuzes behouden', 'aanvrager', 'B', '4K-keuze blijft staan, herstel is één knop', filmS.error, U.c);
ovl(4, 'Onzeker of het aankwam', 'aanvrager', 'W', 'Eerst status herlezen, dan pas eventueel opnieuw', filmS.uncertain, U.c);
ovl(4, 'Door de server geweigerd (403/409)', 'aanvrager', 'W', 'Geen blind opnieuw indienen, geen verruimde rechten', filmS.rejected, U.c);
ovl(4, 'Bevestigd resultaat', 'aanvrager', 'B', 'Zegt wat er herladen is en waar je naartoe kunt', filmS.success, U.c);

ovl(5, 'Alle aanvraagbare seizoenen vooraf gekozen', 'aanvrager', 'B', 'Beschikbaar en aangevraagd zijn zichtbaar maar niet te kiezen', serieS.all, U.w);
ovl(5, 'Eén seizoen', 'aanvrager', 'B', 'De knop noemt wat er verstuurd wordt', serieS.one, U.w);
ovl(5, 'Meerdere seizoenen, selecteer alles gemengd', 'aanvrager', 'B', 'Alle seizoenen toont de tussenstand', serieS.multi, U.w);
ovl(5, 'Lange scrolllijst (14 seizoenen)', 'aanvrager', 'W', 'Kop en knoppen blijven staan; alleen de lijst schuift', serieS.long, U.d);
ovl(5, 'Geen aanvraagbaar seizoen', 'aanvrager', 'B', 'Uitleg in plaats van een leeg formulier', serieS.none, U.w);
ovl(5, '4K voor series, limiet krap', 'aanvrager met 4K-serie', 'W', 'Pleya rekent de limiet niet zelf uit; de server beslist', serieS.fourK, U.w);
ovl(5, 'Bezig met indienen', 'aanvrager', 'B', 'Zelfde guard als bij film', serieS.submitting, U.w);
ovl(5, 'Fout, selectie behouden', 'aanvrager', 'B', 'De gekozen seizoenen staan er nog', serieS.error, U.w);
ovl(5, 'Bevestigd resultaat', 'aanvrager', 'B', 'Noemt de seizoenen en de nieuwe detailstatus', serieS.success, U.w);

ovl(6, 'Beheerder: server, profiel, hoofdmap (film)', 'beheerder', 'B', 'De drie bestaande keuzes, onder de 4K-schakelaar', advS.admin, U.c);
ovl(6, 'Geen beheerder: sectie afwezig', 'aanvrager', 'B', 'Niet uitgegrijsd maar weg: het formulier is dat van 4A, de aanvraagserver kiest het doel', advS.nonAdmin, U.c);
ovl(6, 'Beheerder: Sonarr-doel bij een serie', 'beheerder', 'B', 'Zelfde sectie onder de seizoenkeuze', advS.serieAdmin, U.w);
ovl(6, 'Serverkeuze bij 4K: alleen 4K-servers', 'beheerder', 'B', 'Geen SD/4K-mix mogelijk', advS.pick4k, U.c);
ovl(6, 'Na serverwissel: afhankelijke keuzes gewist en aan het laden', 'beheerder', 'B', 'Indienen uit tot profiel en hoofdmap er zijn', advS.reload, U.c);
ovl(6, 'Herladen: standaard van de nieuwe server', 'beheerder', 'B', 'Geen stil behoud van het oude doel', advS.reloaded, U.c);
ovl(6, 'Opties niet geladen', 'beheerder', 'W', 'Productkeuze: indienen met serverstandaard blijft mogelijk (zie README)', advS.error, U.c);
ovl(6, 'Geen 4K-server ingesteld', 'beheerder', 'W', 'Indienen in 4K uit; HD blijft de uitweg', advS.noConfig, U.c);

scr(7, 'Mijn aanvragen', 'aanvrager', 'B', '35 C1 voor de eigen lijst; zonder totaal, want dat is niet bewezen', listS.mine);
scr(7, 'Alle aanvragen', 'beheerder', 'B', '35 C1 met het bereik als tag', listS.all);
scr(7, 'Statusfilter met aantallen', 'beheerder, bereik alle', 'B', '35 D; aantallen horen bij hetzelfde bereik als de lijst', listS.status);
scr(7, 'Aantallen onbekend bij eigen bereik', 'beheerder, bereik mijn', 'W', 'Geen globale aantallen naast een eigen lijst', listS.countsUnknown);
scr(7, 'Aantallen niet geladen', 'beheerder, bereik alle', 'W', 'Streepje in plaats van nul', listS.countsFailed);
scr(7, 'Laden', 'aanvrager', 'B', 'Skelet in kaart- of rijmaat', listS.loading);
scr(7, 'Leeg', 'aanvrager', 'W', 'TVUX-36: Ontdekken en Zoeken in plaats van Opnieuw', listS.empty);
scr(7, 'Gefilterd leeg', 'beheerder', 'B', 'Filters wissen blijft de actie; het aantal op het gekozen filter is de bekende 0 uit hetzelfde bereik', listS.filteredEmpty);
scr(7, 'Fout', 'aanvrager', 'B', 'Alleen een echte fout krijgt Opnieuw proberen', listS.error);
scr(7, 'Meer laden mislukt', 'beheerder', 'W', 'Fouttegel aan het eind; de geladen pagina blijft', listS.moreError);
scr(7, 'Statusverandering en terugkeer naar kaart', 'beheerder', 'W', 'Zelfde kaart houdt de focus, capsule en aantallen zijn nieuw', listS.changed);

const UL = IT.wad;
ovl(8, 'Acties voor beheerder op een aanvraag in afwachting', 'beheerder', 'N', 'TV: via het contextmenu, niet gebouwd. Touch en desktop: bestaande rijknoppen, hier als menu', mgmtSheets.menuMgr, UL);
ovl(8, 'Acties op een eigen aanvraag in afwachting', 'aanvrager', 'N', 'Annuleren bestaat op touch; Bewerken is nieuw', mgmtSheets.menuOwn, U.c);
ovl(8, 'Geen acties: niet meer in afwachting of geen recht', 'aanvrager', 'N', 'Het menu legt uit waarom er niets te doen is', mgmtSheets.menuRead, IT.glas);
ovl(8, 'Annuleren bevestigen', 'aanvrager, eigen aanvraag', 'B', 'Bestaande bevestiging; focus op de veilige knop', mgmtSheets.cancel, U.c);
ovl(8, 'Bewerken: seizoenen', 'aanvrager, eigen aanvraag', 'N', 'updateRequest heeft nog geen scherm; dit is het voorstel', mgmtSheets.editSerie, U.w);
ovl(8, 'Bewerken: 4K en doel', 'beheerder', 'N', 'Zelfde afhankelijkheden als bij aanvragen', mgmtSheets.editFilm, IT.tears);
ovl(8, 'Bewerken geweigerd (403)', 'aanvrager', 'N', 'Bekende weigering: de server antwoordde, de aanvraag blijft zoals hij stond', mgmtSheets.editForbidden, U.w);
ovl(8, 'Bewerken niet mogelijk', 'aanvrager', 'N', 'Alleen een aanvraag in afwachting is aan te passen', mgmtSheets.editUnsupported, IT.glas);
ovl(8, 'Bewerken: bezig met opslaan', 'aanvrager', 'N', 'Eén keer verstuurd', mgmtSheets.editBusy, U.w);
ovl(8, 'Bewerken: onzeker of het is opgeslagen', 'aanvrager', 'N', 'Uitkomst onbekend na verzenden: keuze blijft staan, eerst de aanvraag herlezen, dan pas eventueel opnieuw', mgmtSheets.editError, U.w);
scr(8, 'Actie bezig op de kaart', 'beheerder', 'W', 'De kaart toont Bezig; geen tweede actie mogelijk', listS.busy);
scr(8, 'Actie mislukt, focus terug op de kaart', 'beheerder', 'W', 'Melding plus herlaadde lijst; status ongewijzigd', listS.actError);

// codes 1A, 1B ... per familie
const seen = {};
for (const s of S) { seen[s.fam] = (seen[s.fam] ?? 0) + 1; s.code = `${s.fam}${String.fromCharCode(64 + seen[s.fam])}`; s.slug = s.name.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 44); }

// ---------- pagina's ----------
const PL = { tv: { dir: 'tv', label: 'TV', w: 1920, h: 1080, dsf: 1 }, ph: { dir: 'phone', label: 'Telefoon', w: 402, h: 874, dsf: 2 }, tb: { dir: 'tablet', label: 'Tablet', w: 1180, h: 820, dsf: 1 }, dk: { dir: 'desktop', label: 'Desktop', w: 1440, h: 900, dsf: 1 } };
// paneelmaat per platform voor borden: [breedte, hoogte, aantal, tussenruimte, rand, labelhoogte]
const BOARD = { tv: [944, 1024, 2, 32, 0, 56], dk: [464, 844, 3, 24, 0, 56], tb: [560, 764, 3, 20, 0, 56], ph: [402, 874, 4, 24, 24, 40] };
const BLT = { B: 'bestaand gedrag', W: 'gewijzigd gedrag', N: 'nieuw, niet gebouwd' };
const inner = (p, s) => s.kind === 'scherm' ? s.r(p) : `<div class="bleed dim">${art(s.u ?? IT.charge, true)}<div class="sc"></div></div><div class="scrimx"></div>${s.r(p)}`;
const pages = [];
const LH = 56;
const lab = (s, w, h) => `<div class="lab" style="height:${h}px;width:${w}px"><b>${s.code}</b><span>${s.name}</span><em>${s.built === 'B' ? '' : s.built === 'N' ? '· nieuw' : '· gewijzigd'}</em></div>`;
const chunk = (a, n) => a.reduce((o, x, i) => (i % n ? o[o.length - 1].push(x) : o.push([x]), o), []);
for (const p of Object.keys(PL)) {
  for (const fam of Object.keys(FAM)) {
    const fs = S.filter(s => s.fam == fam);
    const single = p === 'ph' ? [] : fs.filter(s => s.kind === 'scherm');
    const boarded = p === 'ph' ? fs : fs.filter(s => s.kind === 'overlay');
    for (const s of single) pages.push({ p, fam, name: `rq-${p}-${s.code}-${s.slug}`, w: PL[p].w, h: PL[p].h + LH, states: [s],
      html: `<div class="pn">${lab(s, PL[p].w, LH)}<div class="vp ${p}">${inner(p, s)}</div></div>` });
    const [bw, bh, n, gap, pad, lh] = BOARD[p];
    for (const g of chunk(boarded, n)) {
      const w = n * bw + (n - 1) * gap + 2 * pad, h = bh + lh + 2 * pad;
      const slug = FAM[fam].toLowerCase().replace(/[^a-z0-9]+/g, '-');
      pages.push({ p, fam, name: `rq-${p}-${g[0].code}-${g[g.length - 1].code}-${slug}`, w, h, states: g, board: true,
        html: `<div style="display:flex;gap:${gap}px;padding:${pad}px;width:${w}px;height:${h}px">${g.map(s => `<div class="pn">${lab(s, bw, lh)}<div class="vp ${p}" style="width:${bw}px;height:${bh}px">${inner(p, s)}</div></div>`).join('')}</div>` });
    }
  }
}

// ---------- inhoudscontrole (draait ook met --no-render) ----------
// Drie contracten uit de spec die een beeld niet mag tegenspreken. Elke regel hieronder is
// rood geweest op de set van 8 oktober voor de herstelronde.
const stateOf = code => S.find(s => s.code === code);
const txt = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
for (const p of Object.keys(PL)) {
  // Na een verzonden wijziging is de uitkomst onbekend: geen "niets veranderd", geen blind
  // opnieuw versturen, wel de keuze behouden en eerst de status herlezen.
  const e = stateOf('8J').r(p), et = txt(e);
  if (/niets veranderd|niet aangepast/i.test(et)) problems.push(`8J ${p}: beweert dat de server onveranderd is`);
  if (/Opnieuw proberen|Opnieuw opslaan/.test(et)) problems.push(`8J ${p}: biedt blind opnieuw versturen aan`);
  if (!/Status controleren/.test(et)) problems.push(`8J ${p}: geen statuscontrole als herstel`);
  if (!/class="cb on"/.test(e) || !/Seizoen 3/.test(et)) problems.push(`8J ${p}: gekozen waarden niet behouden`);
  if (!/class="b pri[^"]*"[^>]*>(<svg[\s\S]*?<\/svg>)?Status controleren/.test(e)) problems.push(`8J ${p}: Status controleren is niet de hoofdknop`);
  // Bekende weigering blijft iets anders dan een onbekende uitkomst.
  if (!/403/.test(txt(stateOf('8G').r(p)))) problems.push(`8G ${p}: bekende weigering noemt het serverantwoord niet`);
  // Een leeg filter en het aantal bij datzelfde filter komen uit hetzelfde bereik.
  const h = stateOf('7H').r(p), ht = txt(h);
  const chip = h.match(/class="(?:cx on|opt on focus)">(?:<svg[\s\S]*?<\/svg>)?Afgewezen ?<span class="n">([^<]*)</);
  const head = ht.match(/(\d+) van (\d+)/);
  if (p !== 'tv' && !chip) problems.push(`7H ${p}: gekozen filter Afgewezen staat niet in beeld`);
  if (chip && chip[1] !== '0') problems.push(`7H ${p}: lege lijst naast aantal ${chip[1]} op het gekozen filter`);
  if (!head || head[1] !== '0') problems.push(`7H ${p}: kop noemt geen 0 voor het gekozen filter`);
  if (!/In afwachting ?<span class="n">27</.test(h) && p !== 'tv') problems.push(`7H ${p}: aantal van een ander filter is niet meer het bekende aantal`);
  // Onbekend blijft onbekend: geen getal bij eigen bereik, een streepje bij een mislukte telling.
  if (/class="n">\d/.test(stateOf('7D').r(p))) problems.push(`7D ${p}: getal bij eigen bereik`);
  const f = stateOf('7E').r(p);
  if (/class="n">\d/.test(f) || !/class="n">–</.test(f)) problems.push(`7E ${p}: mislukte telling toont geen streepje`);
}

// ---------- renderen ----------
const only = process.argv.slice(2);
const noRender = only.includes('--no-render');
mkdirSync(OUT, { recursive: true });
for (const p of Object.values(PL)) mkdirSync(join(SET, p.dir), { recursive: true });
if (!noRender) {
  const { chromium } = await import(process.env.PLEYA_MOCKUP_PLAYWRIGHT ?? '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs');
  const browser = await chromium.launch();
  for (const dsf of [1, 2]) {
    const ctx = await browser.newContext({ deviceScaleFactor: dsf, colorScheme: 'dark' });
    const page = await ctx.newPage();
    for (const pg of pages.filter(x => PL[x.p].dsf === dsf && (only.length === 0 || only.some(o => x.name.includes(o))))) {
      const file = join(OUT, pg.name + '.html');
      writeFileSync(file, `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>${pg.name}</title><link rel="stylesheet" href="${TVSRC}/tv.css"><link rel="stylesheet" href="../rq.css"></head><body>${pg.html}</body></html>`);
      await page.setViewportSize({ width: pg.w, height: pg.h });
      await page.goto('file://' + file, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      const bad = await page.evaluate(() => [...document.images].filter(i => !i.complete || !i.naturalWidth).map(i => i.getAttribute('src')));
      if (bad.length) problems.push(`${pg.name}: kapotte afbeelding ${bad.join(', ')}`);
      // Meetcontrole: profiel- en servercontext en het gekozen filter staan volledig binnen de
      // schermrand van het platform (TV: de 56 px van het catalogusraster), niet afgekapt en
      // niet bedekt.
      for (const m of await page.evaluate(() => {
        const out = [], r = e => e.getBoundingClientRect();
        for (const vp of document.querySelectorAll('.vp')) {
          const v = r(vp), inset = parseFloat(getComputedStyle(vp).getPropertyValue('--in')) || 0, tv = vp.classList.contains('tv');
          const tags = [...vp.querySelectorAll('.head .tagx')], title = vp.querySelector('.head .page-title');
          const ctx = [...(tags.length ? [tags.at(-1)] : []), ...vp.querySelectorAll('.bar .sub, .ctx')];
          for (const e of [...new Set([...tags, ...ctx])]) {
            const b = r(e), name = e.textContent.trim().slice(0, 40);
            if (b.left < v.left + inset - 1 || b.right > v.right - inset + 1) out.push(`"${name}" buiten de rand: ${Math.round(b.left - v.left)}..${Math.round(b.right - v.left)} van ${Math.round(v.width)}`);
            if (e.scrollWidth > e.clientWidth + 1) out.push(`"${name}" afgekapt`);
            if (title && e !== title && b.left < r(title).right + 8 && b.top < r(title).bottom && b.bottom > r(title).top && tv) out.push(`"${name}" over de paginatitel`);
          }
          for (const e of ctx) { const b = r(e), hit = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2); if (hit && !e.contains(hit) && !hit.closest('.scrimx, .sheet, .menu, .kb, .toast, .bleed')) out.push(`context bedekt door .${hit.className}`); }
          for (const row of vp.querySelectorAll('.chipsx')) { if (row.closest('.recent')) continue; const on = row.querySelector('.cx.on'); if (!on) { out.push('filterrij zonder zichtbaar gekozen filter'); continue; } const b = r(on); if (b.right > v.right - 1 || b.left < v.left) out.push(`gekozen filter "${on.textContent.trim()}" valt buiten beeld`); }
        }
        return out;
      })) problems.push(`${pg.name}: ${m}`);
      // Polishcontrole: wat een beeld belooft moet ook in beeld staan. Elke regel hieronder is
      // rood geweest op de set van voor de polishronde (zie README, Zelfcontrole).
      for (const m of await page.evaluate(() => {
        const out = [], r = e => e.getBoundingClientRect(), R = Math.round;
        for (const vp of document.querySelectorAll('.vp')) {
          const v = r(vp), code = vp.parentElement.querySelector('.lab b')?.textContent ?? '', P = m => out.push(`${code} ${m}`);
          const bar = vp.querySelector('.tabbar'), floor = bar ? r(bar).top : v.bottom;
          if (vp.querySelector('.rqnote')) P('voorstelnotitie staat in het scherm');
          // Voetregel van een overlay: één regel, binnen de voet, niet weggedrukt door een lange knop.
          for (const fc of vp.querySelectorAll('.sh-foot .fc')) { const b = r(fc), f = r(fc.parentElement), one = parseFloat(getComputedStyle(fc).fontSize) * 1.6; if (b.left < f.left - 1 || b.right > f.right + 1) P('voetregel valt buiten de overlay'); if (b.height > one && !vp.classList.contains('ph')) P(`voetregel breekt over ${R(b.height / (one / 1.6) / 1.3)} regels`); }
          // Herstelknoppen (Opnieuw, Opnieuw proberen) staan volledig in beeld, boven de tabbalk.
          for (const b of vp.querySelectorAll('.msg .b, .errt .b')) { const x = r(b); if (x.bottom > floor + .5 || x.top < v.top) P(`herstelknop "${b.textContent.trim()}" valt onder de rand (${R(x.bottom - v.top)} van ${R(floor - v.top)})`); }
          // Focus staat met zijn ring volledig in beeld.
          for (const e of vp.querySelectorAll('.focus')) { const t = e.classList.contains('card') ? e.querySelector('.art') : e, b = r(t), m = Math.max(0, ...(getComputedStyle(t).boxShadow.match(/(\d+)px(?= *(?:,|$))/g) ?? []).map(parseFloat)); if (b.bottom + m > v.bottom + .5 || b.top - m < v.top - .5) P(`focus valt met zijn ring buiten beeld (onderkant ${R(b.bottom + m - v.top)} van ${R(v.height)})`); const sib = [...(e.classList.contains('card') ? e.children : [])].at(-1); if (sib && r(sib).bottom > v.bottom + .5) P('ondertitel van de kaart in focus valt onder de rand'); }
          // Aanvrager, datum en speelbaarheid worden niet afgekapt.
          for (const s of vp.querySelectorAll('.lrow .s, .card .s')) if (s.scrollWidth > s.clientWidth + 1) P(`regel afgekapt: "${s.textContent.trim()}"`);
          // Telefoon: een filterchip die de rand raakt vervaagt, zodat een half getal geen getal lijkt.
          if (vp.classList.contains('ph')) for (const row of vp.querySelectorAll('.chipsx')) { const cut = [...row.children].some(c => r(c).left < v.right && r(c).right > v.right); if (cut && !/gradient/.test(getComputedStyle(row).maskImage + getComputedStyle(row).webkitMaskImage)) P('filterchip hard afgesneden op de schermrand'); }
        }
        return out;
      })) problems.push(`${pg.name}: ${m.trim()}`);
      await page.waitForTimeout(80);
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
  set: 'Requests 2.0 (A-20)', status: STATUS.long, generated: new Date().toISOString().slice(0, 10),
  images: pages.map(pg => ({ file: `${PL[pg.p].dir}/${pg.name}.jpg`, platform: PL[pg.p].label, pixels: `${pg.w * PL[pg.p].dsf}x${pg.h * PL[pg.p].dsf}`, family: FAM[pg.fam], panels: pg.states.map(s => s.code) })),
  states: S.map(s => ({ code: s.code, family: FAM[s.fam], state: s.name, role: s.role, kind: s.kind, versusSource: BLT[s.built], intent: s.intent, ...Object.fromEntries(Object.keys(PL).map(p => [PL[p].label, where(s, p)])) })),
};
writeFileSync(join(SET, 'manifest.json'), JSON.stringify(manifest, null, 1));

const cell = (s, p) => { const w = where(s, p); return `[${w.panel ? 'paneel ' + w.panel : 'beeld'}](${w.file})`; };
const matrix = Object.keys(FAM).map(f => `### ${f}. ${FAM[f]}\n\n| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |\n|---|---|---|---|---|---|---|---|\n${S.filter(s => s.fam == f).map(s => `| ${s.code} | ${s.name} | ${s.role} | ${BLT[s.built]} | ${Object.keys(PL).map(p => cell(s, p)).join(' | ')} |`).join('\n')}`).join('\n\n');
const readme = join(SET, 'README.md');
if (existsSync(readme)) {
  const src = readFileSync(readme, 'utf8');
  const a = '<!-- MATRIX:BEGIN -->', b = '<!-- MATRIX:END -->';
  if (src.includes(a)) writeFileSync(readme, src.slice(0, src.indexOf(a) + a.length) + '\n' + matrix + '\n' + src.slice(src.indexOf(b)));
}

const esc = t => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
writeFileSync(join(SET, 'index.html'), `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>Requests 2.0 · voorstelset A-20</title><style>
body{background:#141414;color:#fff;font:15px/1.45 -apple-system,Inter,sans-serif;margin:0;padding:28px 36px 80px}
h1{font-size:28px;margin:0 0 6px}h2{font-size:22px;margin:44px 0 6px;padding-top:14px;border-top:1px solid #fff2}h3{font-size:15px;color:#fff9;margin:22px 0 10px;font-weight:600}
p{color:#fffb;max-width:980px;margin:6px 0}a{color:#fff}.st{display:inline-block;background:#FFB020;color:#000;font-weight:700;border-radius:5px;padding:1px 8px}
nav a{margin-right:14px;color:#fffb}.g{display:flex;flex-wrap:wrap;gap:14px}.c{width:300px}.c.wide{width:620px}.c img{width:100%;display:block;border-radius:6px;border:1px solid #fff2;background:#000}
.c div{font-size:12.5px;color:#fff9;margin-top:5px}.c b{color:#fff}table{border-collapse:collapse;font-size:13px;margin-top:8px}td,th{border-bottom:1px solid #fff2;padding:4px 10px 4px 0;text-align:left;vertical-align:top}th{color:#fff9;font-weight:600}
</style></head><body>
<h1>Requests 2.0 · voorstelset A-20</h1>
<p><span class="st">${STATUS.short}</span> ${STATUS.long}. Niets hiervan is gebouwd of op een toestel gezien. De dekkingsmatrix en de goedgekeurde keuzes staan in <a href="README.md">README.md</a>, de machineleesbare lijst in <a href="manifest.json">manifest.json</a>.</p>
<p>${S.length} staten in ${Object.keys(FAM).length} families, ${pages.length} beelden. Een bord toont meerdere staten op ware grootte; de code boven elk scherm of paneel is die uit de tabel. De strook met code en naam (56 px, op de telefoon 40) hoort bij het beeld, niet bij het scherm.</p>
<nav>${Object.keys(FAM).map(f => `<a href="#f${f}">${f}. ${FAM[f]}</a>`).join('')}</nav>
${Object.keys(FAM).map(f => `<h2 id="f${f}">${f}. ${FAM[f]}</h2>
<table><tr><th>Code</th><th>Staat</th><th>Rol</th><th>Tegenover de bron</th><th>Bedoeling</th></tr>${S.filter(s => s.fam == f).map(s => `<tr><td><b>${s.code}</b></td><td>${esc(s.name)}</td><td>${esc(s.role)}</td><td>${BLT[s.built]}</td><td>${esc(s.intent)}</td></tr>`).join('')}</table>
${Object.keys(PL).map(p => `<h3>${PL[p].label}</h3><div class="g">${pages.filter(x => x.p === p && x.fam == f).map(pg => `<a class="c${pg.board ? ' wide' : ''}" href="${PL[p].dir}/${pg.name}.jpg"><img loading="lazy" src="${PL[p].dir}/${pg.name}.jpg" alt=""><div><b>${pg.states.map(s => s.code).join(' · ')}</b> ${esc(pg.states.map(s => s.name).join(' | '))} · ${pg.w * PL[p].dsf}×${pg.h * PL[p].dsf}</div></a>`).join('')}</div>`).join('')}`).join('')}
</body></html>`);

// ---------- zelfcontrole ----------
for (const im of manifest.images) { const f = join(SET, im.file); if (!existsSync(f)) problems.push('ontbreekt: ' + im.file); else if (statSync(f).size < 8000) problems.push('verdacht klein: ' + im.file); }
for (const s of manifest.states) for (const p of Object.values(PL)) if (!existsSync(join(SET, s[p.label].file))) problems.push(`${s.code} ${p.label}: geen bestand`);
console.log(`\n${S.length} staten · ${pages.length} beelden · ${Object.values(PL).map(p => `${p.label} ${pages.filter(x => PL[x.p] === p).length}`).join(' · ')}`);
console.log(problems.length ? 'PROBLEMEN:\n' + problems.join('\n') : 'zelfcontrole: elk beeld bestaat, elke staat heeft op elk platform een bestand, geen kapotte afbeeldingen');
process.exit(problems.length ? 1 : 0);
