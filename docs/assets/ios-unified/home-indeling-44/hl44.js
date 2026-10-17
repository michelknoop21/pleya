/* Mockup 44: Home-indeling op iPhone, iPad en Mac (HOME-R1).
   Eén bron voor alle beelden. De pagina leest ?t=dark|light en ?s=s|l|pad|mac uit de URL;
   ?x=2 rendert op 2x via CSS-zoom zodat `pw screenshot` scherpe PNG's maakt. */
const Q = new URLSearchParams(location.search);
const THEME = Q.get('t') || 'dark';
const SIZE = Q.get('s') || 'l';
const L = SIZE === 'l';
const ST = L ? 54 : 20;          // statusbalk
const TAB = L ? 86 : 52;         // tabbalk
const SHEET_TOP = L ? 58 : 26;

const PO = n => `../detail-2026/${n}-poster.jpg`;
const P = ['sintel', 'tears', 'elephants', 'spring', 'caminandes', 'charge', 'coffeerun', 'dweebs'];
const pp = (...i) => i.map(k => P[k % P.length]);
const AVATAR = '../../tvos-unified/src/assets/avatar.jpg';
const WORDMARK = '../../tvos-unified/src/assets/pleya_wordmark.png';

const I = {
  drag: '<circle cx="9" cy="6" r="1.7"/><circle cx="15" cy="6" r="1.7"/><circle cx="9" cy="12" r="1.7"/><circle cx="15" cy="12" r="1.7"/><circle cx="9" cy="18" r="1.7"/><circle cx="15" cy="18" r="1.7"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M10.6 5.1A10.4 10.4 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.2 4.1M6.6 6.6A17 17 0 0 0 2 12s3.6 7 10 7a9.6 9.6 0 0 0 5.4-1.6"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="M3 3l18 18"/>',
  more: '<circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chev: '<path d="M9 6l6 6-6 6"/>',
  up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  down: '<path d="M12 5v14M6 13l6 6 6-6"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16v4z"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  fwd: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
  home: '<path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" fill="currentColor"/>',
  tv: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 3l4 4 4-4"/>',
  clap: '<path d="M3 9h18v11H3z"/><path d="M3 9l2.5-5h13L21 9M9 4l-2 5M15 4l-2 5"/>',
  live: '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8"/>',
  tune: '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
  swap: '<path d="M8 20V4M4 8l4-4 4 4M16 4v16M12 16l4 4 4-4"/>',
  genre: '<path d="M4 6h16M4 12h11M4 18h7"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  dns: '<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>',
  vis: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  cloudoff: '<path d="M3 3l18 18"/><path d="M7.5 8.2A5 5 0 0 0 7 18h10.5M11.2 6.1A6 6 0 0 1 18.3 11 3.8 3.8 0 0 1 20.6 16.8"/>',
  layers: '<path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 13l9 5 9-5"/>',
  movie: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
  empty: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M4 15l4-4 4 4 3-3 5 5"/>',
};
const ic = (n, extra = '') => {
  const filled = n === 'drag' || n === 'more';
  return `<svg class="ic" viewBox="0 0 24 24" ${filled ? 'fill="currentColor" stroke="none"' : 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'} ${extra}>${I[n]}</svg>`;
};

/* ---------- dataset ---------- */
// Wat de iPhone-Home tekent (unified rijen, DEC-145).
const PHONE_ROWS = [
  { t: 'Nieuwe sci-fi', s: 'Eigen rij · Films · Sciencefiction · Niet bekeken · 42 titels', own: true, th: pp(1, 0, 4) },
  { t: 'Recent uitgebracht', s: 'Pleya-rij', th: pp(3, 5, 6) },
  { t: 'Kijklijst', s: 'Pleya-rij · 9 titels', th: pp(2, 7, 1) },
  { t: 'Recent toegevoegde series', s: 'Plex Familie · Jellyfin NAS', th: pp(4, 3, 0) },
  { t: 'Recent toegevoegde films', s: 'Plex Familie', th: pp(5, 2, 6) },
  { t: 'Omdat je Severance gekeken hebt', s: 'Plex Familie', th: pp(6, 1, 7) },
  { t: 'Aanbevolen voor jou', s: 'Jellyfin NAS · verborgen', off: true, th: pp(7, 4, 2) },
  { t: 'Nu op tv', s: 'Pleya-rij · standaard uit', off: true, th: [] },
];
// Wat de iPad- en Mac-Home vandaag tekenen: één rij per server-hub, geen Recent uitgebracht of Nu op tv.
const DESK_ROWS = [
  { t: 'Nieuwe sci-fi', s: 'Eigen rij · Films · Sciencefiction · Niet bekeken · 42 titels', own: true, th: pp(1, 0, 4, 3) },
  { t: 'Kijklijst', s: 'Pleya-rij · 9 titels', th: pp(2, 7, 1, 5) },
  { t: 'Recent toegevoegde films', s: 'Plex Familie', th: pp(5, 2, 6, 0) },
  { t: 'Recent toegevoegde series', s: 'Plex Familie', th: pp(4, 3, 0, 7) },
  { t: 'Recent toegevoegde series', s: 'Jellyfin NAS', th: pp(3, 6, 1, 2) },
  { t: 'Omdat je Severance gekeken hebt', s: 'Plex Familie', th: pp(6, 1, 7, 4) },
  { t: 'Aanbevolen voor jou', s: 'Jellyfin NAS · verborgen', off: true, th: pp(7, 4, 2, 5) },
];
const FIXED = [
  { t: 'Uitgelicht', s: 'Altijd bovenaan', th: pp(0, 5, 2) },
  { t: 'Verder kijken', s: 'Altijd tweede', th: pp(3, 6, 1) },
];

/* ---------- bouwstenen ---------- */
const status = () => `<div class="status"><span>9:41</span>${L ? '<div class="island"></div>' : ''}<span class="bat"></span></div>`;
const homeind = () => '<div class="homeind"></div>';
const tabbar = () => `<div class="tabbar">
  <div class="on">${ic('home')}Home</div><div>${ic('tv')}Series</div><div>${ic('clap')}Films</div><div>${ic('live')}Live TV</div><div><span class="tava">M</span>Mijn Pleya</div></div>`;
const thumbs = (list, n = 3) => {
  const imgs = list.slice(0, n).map(src => `<img src="${PO(src)}">`).join('');
  return `<div class="thumbs">${imgs || '<i></i><i></i><i></i>'}</div>`;
};
const trail = (r, mac) => {
  if (r.fixed) return `<span class="vast">${ic('lock')}vast</span>`;
  if (r.own) return mac
    ? `<div class="chip2">${ic('edit')}Bewerken</div><span class="ibtn">${ic('more')}</span>`
    : `<span class="ibtn">${ic('more')}</span>`;
  return `<span class="ibtn">${ic(r.off ? 'eyeoff' : 'eye')}</span>`;
};
const lrow = (r, cls = '', mac = false) => `<div class="lrow ${r.fixed ? 'fixed' : ''} ${r.off ? 'off' : ''} ${cls}">
  <span class="handle">${r.fixed ? ic('lock') : ic('drag')}</span>${r.thumbHtml || thumbs(r.th, mac ? 4 : 3)}
  <div class="body"><div class="t">${r.t}</div><div class="s">${r.s}</div></div>${trail(r, mac)}</div>`;
const fixedCard = (mac) => `<div class="glabel">Vast</div><div class="card">${FIXED.map(r => lrow({ ...r, fixed: true }, '', mac)).join('')}</div>`;
const newRow = () => `<div class="newrow"><span class="lead">${ic('plus')}</span><div><div class="t">Nieuwe rij</div><div class="s">Van een filter op films of series</div></div></div>`;

/* iPhone-sheet "Home aanpassen" */
function customizeSheet({ rows = PHONE_ROWS, lift = -1, slot = -1, label = 'Jouw rijen', count = true, extra = '' } = {}) {
  let body = '';
  rows.forEach((r, i) => {
    if (i === slot) body += '<div class="slot"></div>';
    if (i !== lift) body += lrow(r);
  });
  if (slot === rows.length) body += '<div class="slot"></div>';
  const visible = rows.filter(r => !r.off).length;
  return `<div class="sheet page"><div class="grab"></div>
    <div class="shead"><h2>Home aanpassen</h2><div class="done">${ic('check')}Klaar</div></div>
    <div class="intro">Sleep aan ${ic('drag', 'style="display:inline;vertical-align:-2px;font-size:13px"')} om te verplaatsen. Uitgelicht en Verder kijken blijven staan waar ze staan.</div>
    <div class="list fade" style="top:${L ? 104 : 100}px;bottom:0">
      ${fixedCard()}
      <div class="glabel">${label}${count ? `<i>${visible} van ${rows.length} op Home</i>` : ''}</div>
      <div class="card" id="mov">${body}</div>${newRow()}${extra}
    </div></div>`;
}

/* Home-feed op de iPhone */
const homeHead = () => `<div class="hhead"><img class="wm" src="${WORDMARK}"><span class="sr">${ic('search')}</span><img class="ava" src="${AVATAR}"></div>`;
const section = (title, imgs, { count, pressed } = {}) => `<div class="section ${pressed ? 'pressed' : ''}">
  <div class="rowhead"><h3>${title}${count ? ` <span>· ${count}</span>` : ''}</h3><a>Alles bekijken ${ic('chev')}</a></div>
  <div class="rail">${imgs.map(s => `<img src="${PO(s)}">`).join('')}</div></div>`;

/* ---------- schermen ---------- */
const S = {};

S['44-a-home-ingang'] = () => {
  const top = L ? 112 : 70;
  return status() + homeHead() + `<div class="feed" style="top:${top}px;bottom:${TAB}px">
    <div style="margin-top:-6px">${section('Omdat je Severance gekeken hebt', pp(6, 1, 7, 4))}
    ${section('Aanbevolen voor jou', pp(2, 5, 0, 3))}</div>
    <div class="foot"><span class="lead">${ic('tune')}</span><div><div class="t">Home aanpassen</div><div class="s">Verplaats of verberg rijen, of maak er een van een filter</div></div><span class="chev">${ic('chev')}</span></div>
  </div>` + tabbar() + homeind();
};

S['44-b-rijkop-lang-drukken'] = () => {
  const top = L ? 112 : 70;
  return status() + homeHead() + `<div class="feed" style="top:${top}px;bottom:${TAB}px">
    <div style="margin-top:${L ? -8 : -150}px">${section('Kijklijst', pp(2, 7, 1, 5), { count: 9 })}
    ${section('Recent toegevoegde series', pp(4, 3, 0, 6), { pressed: true })}
    ${section('Recent toegevoegde films', pp(5, 2, 6, 1))}</div></div>` + tabbar() +
    `<div class="dim"></div>
    <div class="sheet asheet"><div class="grab"></div>
      <div class="ahead"><div class="thumbs">${pp(4, 3, 0).map(s => `<img src="${PO(s)}">`).join('')}</div><div><div class="t">Recent toegevoegde series</div><div class="s">Plex Familie · Jellyfin NAS · rij 4 van 8</div></div></div>
      <div style="height:6px"></div>
      <div class="aitem">${ic('up')}Omhoog</div>
      <div class="aitem">${ic('down')}Omlaag</div>
      <div class="aitem">${ic('eyeoff')}Verbergen op Home</div>
      <div class="asep"></div>
      <div class="aitem">${ic('tune')}Home aanpassen<span class="k">${ic('chev', 'style="font-size:16px"')}</span></div>
    </div>` + homeind();
};

S['44-c-aanpassen-lijst'] = () => `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() + customizeSheet() + homeind();

S['44-d-slepen'] = () => {
  // Kijklijst (index 2) wordt naar plek 1 gesleept: hij zweeft boven de lege plek.
  const rows = PHONE_ROWS;
  const base = (L ? 104 : 100) + 7 + 18 + 7 + 2 * 58 + 16 + 7 + 18 + 7; // vaste kaart plus labels
  const liftTop = base + 48;
  return `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() +
    customizeSheet({ lift: 2, slot: 1 }).replace('</div></div>' + '', '</div></div>') +
    `<div style="position:absolute;left:16px;right:16px;top:${SHEET_TOP + liftTop}px;z-index:45;background:var(--sheet);border-radius:14px">${lrow(rows[2], 'lifted')}</div>
    <div class="touch" style="left:${16 + 5}px;top:${SHEET_TOP + liftTop + 9}px"></div>` + homeind();
};

S['44-e-eigen-rij-menu'] = () => `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() + customizeSheet() +
  `<div class="dim" style="z-index:41"></div>
  <div class="sheet asheet" style="z-index:42"><div class="grab"></div>
    <div class="ahead"><div class="thumbs">${pp(1, 0, 4).map(s => `<img src="${PO(s)}">`).join('')}</div><div><div class="t">Nieuwe sci-fi</div><div class="s">Eigen rij · Films · 42 titels</div></div></div>
    <div style="height:6px"></div>
    <div class="aitem">${ic('edit')}Bewerken</div>
    <div class="aitem">${ic('eyeoff')}Verbergen op Home</div>
    <div class="aitem">${ic('movie')}Alle 42 in Films<span class="k">${ic('chev', 'style="font-size:16px"')}</span></div>
    <div class="asep"></div>
    <div class="aitem danger">${ic('trash')}Verwijderen</div>
  </div>` + homeind();

S['44-f-verwijderen'] = () => `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() + customizeSheet() +
  `<div class="dim" style="z-index:45"></div>
  <div class="dialog" style="top:${L ? 330 : 200}px"><h2>Nieuwe sci-fi verwijderen?</h2>
    <p>De rij verdwijnt van Home. De films zelf blijven gewoon in je bibliotheek.</p>
    <div class="acts"><div class="btn pri">Annuleren</div><div class="btn dng">Verwijderen</div></div></div>` + homeind();

/* wizard als sheet */
function wizard(step, body, foot) {
  const names = ['Naam en soort', 'Filters', 'Voorbeeld'];
  return `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() +
    `<div class="sheet page"><div class="grab"></div>
      <div class="shead"><h2>Nieuwe rij</h2><span class="close">${ic('close')}</span></div>
      <div class="steps">${[0, 1, 2].map(i => `<i class="${i <= step ? 'on' : ''}"></i>`).join('')}</div>
      <div class="stepl">Stap ${step + 1} van 3 · <b>${names[step]}</b></div>
      <div class="wbody">${body}</div>
      <div class="wfoot">${foot}</div></div>` + homeind();
}
const footBack = (label = 'Terug') => `<div class="tbtn">${label === 'Terug' ? ic('back') : ''}${label}</div>`;

S['44-g-nieuwe-rij-naam'] = () => wizard(0, `
  <div class="lede">Een rij toont de films of series die aan een filter voldoen.</div>
  <div class="flabel">Soort</div>
  <div class="kinds"><div class="btn pri">${ic('movie')}Films</div><div class="btn">${ic('tv')}Series</div></div>
  <div class="flabel">Naam</div>
  <div class="field active">Nieuwe sci-fi<span class="caret"></span></div>
  <div class="hint">Laat leeg en de naam volgt het filter, en blijft dat volgen.</div>`,
  footBack('Annuleren') + `<div class="btn pri">Volgende${ic('fwd')}</div>`);

const FILTER_LINES = [
  ['vis', 'Status', 'Niet bekeken', true],
  ['genre', 'Genre', 'Sciencefiction', true],
  ['clock', 'Jaar', 'Alle jaren', false],
  ['dns', 'Bronnen', 'Alle bronnen', false],
  ['swap', 'Sortering', 'Nieuwste release', true],
];
const filterCard = () => `<div class="card" style="margin:0">${FILTER_LINES.map(([i, l, v, set]) =>
  `<div class="fline">${ic(i)}<span class="lb">${l}</span><span class="v ${set ? 'set' : ''}">${v}</span><span class="chev">${ic('chev')}</span></div>`).join('')}</div>`;
const tagStrip = () => `<div class="tags"><span class="tag">Films</span><span class="tag">Sciencefiction</span><span class="tag">Niet bekeken</span><span class="tag mut">Nieuwste release</span></div>`;

S['44-h-nieuwe-rij-filters'] = () => wizard(1, `
  <div class="lede" style="margin-bottom:14px">Dezelfde keuzes als in Alle films. Elke regel opent zijn eigen lijst.</div>
  ${filterCard()}${tagStrip()}`,
  footBack() + `<div class="btn pri">Volgende${ic('fwd')}</div>`);

S['44-i-nieuwe-rij-voorbeeld'] = () => wizard(2, `
  <div class="lede">Zo komt de rij op Home te staan.</div>
  <div class="pvt"><b>Nieuwe sci-fi</b><span>42 titels · Films · Sciencefiction · Niet bekeken · Nieuwste release</span></div>
  <div class="pv">${pp(1, 0, 4).map(s => `<img src="${PO(s)}">`).join('')}<div class="more">+39</div></div>
  <div class="hint" style="margin-top:14px">Komt direct onder Verder kijken. Verplaatsen kan daarna in Home aanpassen.</div>`,
  footBack() + `<div class="btn pri">${ic('plus')}Rij toevoegen</div>`);

S['44-j-leeg-voorbeeld'] = () => wizard(2, `
  <div class="lede">Zo komt de rij op Home te staan.</div>
  <div class="pvt"><b>Korte sci-fi</b><span class="am">0 titels · Films · Sciencefiction · 1962 · Bekeken</span></div>
  <div class="emptybox"><div class="ring">${ic('empty')}</div><b>Niets voldoet aan dit filter</b><p>Maak het filter ruimer, of kies een andere sortering.</p></div>`,
  footBack() + `<div class="btn pri">${ic('tune')}Filters aanpassen</div>`);

S['44-k-randgevallen'] = () => {
  const offThumb = '<div class="thumbs"><i></i><i></i><i></i></div>';
  const emptyThumb = '<div class="thumbs"><i class="out"></i><i class="out"></i><i class="out"></i></div>';
  const rows = [
    { t: 'Recent toegevoegde series', s: `${'<em>2 bronnen</em>'} · Plex Familie · Jellyfin NAS`, th: pp(4, 3, 0) },
    { t: 'Anime', s: '<b>Plex Zolder offline</b> · plek blijft bewaard', thumbHtml: offThumb },
    { t: 'Kinderfilms', s: 'Eigen rij · Films · Animatie · <b>leeg</b>', own: true, thumbHtml: emptyThumb },
    { t: 'Nu op tv', s: 'Pleya-rij · standaard uit · alleen Plex', off: true, thumbHtml: offThumb },
    { t: 'Omdat je Severance gekeken hebt', s: 'Plex Familie', th: pp(6, 1, 7) },
  ];
  const extra = `<div class="glabel">Verder kijken</div><div class="card"><div class="lrow"><span class="handle">${ic('eyeoff')}</span>
    <div class="body"><div class="t">Verborgen items · 2</div><div class="s">Alleen op dit apparaat verborgen. Herstellen zet een titel terug.</div></div><span class="ibtn" style="font-size:16px">${ic('chev')}</span></div></div>`;
  return `<div class="dim" style="background:#000;opacity:${THEME === 'light' ? .2 : .7}"></div>` + status() +
    customizeSheet({ rows, extra, count: false }).replace(fixedCard(), '').replace('id="mov"', 'id="mov" style="--wrap:normal"') + homeind();
};

/* ---------- iPad ---------- */
S['44-l-ipad'] = () => {
  let left = '';
  DESK_ROWS.forEach((r, i) => {
    if (i === 3) left += '<div class="slot"></div>';
    if (i === 1) return; // Kijklijst zweeft
    left += lrow(r, i === 0 ? 'sel' : '');
  });
  return `<div class="backdrop"><div style="height:60px"></div>${section('Verder kijken', pp(0, 1, 2, 3, 4, 5, 6))}${section('Nieuwe sci-fi', pp(1, 0, 4, 3, 5, 6, 7))}</div>
  <div class="dim"></div>
  <div class="status" style="color:#fff;z-index:45"><span>9:41 vr 16 okt</span><span class="bat"></span></div>
  <div class="padsheet">
    <div class="shead"><h2>Home aanpassen</h2><div class="done">${ic('check')}Klaar</div></div>
    <div class="intro">Sleep aan ${ic('drag', 'style="display:inline;vertical-align:-2px;font-size:13px"')} om te verplaatsen. Tik op een eigen rij om hem te bewerken.</div>
    <div class="cols2">
      <div class="left"><div class="list fade" style="top:0;bottom:0">${fixedCard()}
        <div class="glabel">Jouw rijen<i>6 van 7 op Home</i></div><div class="card">${left}</div>${newRow()}</div>
        <div style="position:absolute;left:24px;right:16px;top:${200 + 58 * 2 + 4}px;z-index:9;background:var(--sheet);border-radius:14px">${lrow(DESK_ROWS[1], 'lifted')}</div>
        <div class="touch" style="left:30px;top:${200 + 58 * 2 + 13}px"></div>
      </div>
      <div class="right">
        <div class="rh"><h3>Nieuwe sci-fi bewerken</h3><div class="chip2" style="color:var(--accent)">${ic('trash')}Verwijderen</div></div>
        <div class="stepper"><div><i>${ic('check')}</i>Naam en soort</div><div class="on"><i>2</i>Filters</div><div><i>3</i>Voorbeeld</div></div>
        <div class="lede" style="font-size:14px;color:var(--ink-2);margin-top:14px">Dezelfde keuzes als in Alle films. Elke regel opent zijn eigen lijst.</div>
        ${filterCard()}${tagStrip()}
        <div class="wfoot"><div class="tbtn">Annuleren</div><div style="display:flex;gap:10px"><div class="btn" style="flex:none;padding:0 20px">${ic('back')}Terug</div><div class="btn pri" style="flex:none;padding:0 22px">Volgende${ic('fwd')}</div></div></div>
      </div>
    </div>
  </div>`;
};

/* ---------- Mac ---------- */
const lights = () => `<div class="tbar"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i><span>Pleya</span></div>`;
const dnav = () => `<div class="dnav"><img class="wm" src="${WORDMARK}"><a class="on">Home</a><a>Series</a><a>Films</a><a>Live TV</a><a>Mijn Pleya</a><div class="r">${ic('search')}<span class="tava">M</span></div></div>`;
const deskHome = (hover) => `<div class="dhero"><img src="../detail-2026/sintel-wide.jpg"><div class="tx"><h1>Sintel</h1><p>Een jonge vrouw zoekt de draak die ze ooit redde. 2010 · Fantasy · 15 min</p><div class="cta"><div>▶ Afspelen</div><div class="g">Meer info</div></div></div></div>
  <div class="dfeed">
    <div class="rowhead"><h3>Verder kijken</h3><a>Alles bekijken ${ic('chev')}</a></div>
    <div class="rail">${pp(0, 3, 6, 1, 4, 7, 2, 5).map(s => `<img src="${PO(s)}" style="height:110px;width:196px">`).join('')}</div>
    <div class="rowhead ${hover ? 'hover' : ''}"><h3>Recent toegevoegde series</h3><div style="display:flex;align-items:center"><a>Alles bekijken ${ic('chev')}</a>${hover ? `<span class="hmore">${ic('more')}</span>` : ''}</div></div>
    <div class="rail">${pp(4, 3, 0, 7, 2, 5, 1, 6, 4).map(s => `<img src="${PO(s)}">`).join('')}</div>
  </div>`;
const cursorSvg = `<svg viewBox="0 0 22 22"><path d="M4 2l13 11h-6l3.5 6.5-2.4 1.2L8.6 14 4 18z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
const grabSvg = `<svg viewBox="0 0 24 24"><path d="M8 11V6.5a1.5 1.5 0 0 1 3 0V11m0-1.5v-4a1.5 1.5 0 0 1 3 0V11m0-3.5a1.5 1.5 0 0 1 3 0V12m0-2a1.5 1.5 0 0 1 3 0v4.5c0 3.6-2.6 6.5-6.5 6.5S7 19 5.6 16.6L4 13.6a1.6 1.6 0 0 1 2.6-1.8L8 13.5" fill="#fff" stroke="#000" stroke-width="1.3" stroke-linejoin="round"/></svg>`;

S['44-m-mac-paneel'] = () => {
  let rows = '';
  DESK_ROWS.forEach((r, i) => {
    if (i === 2) rows += '<div class="slot"></div>';
    if (i === 4) return; // wordt gesleept
    rows += lrow(r, '', true);
  });
  const slotY = 367 + 61 * 2; // gemeten: eerste beweegbare regel op 367, regelhoogte 61
  return `<div class="win">${lights()}${dnav()}${deskHome(false)}<div class="dim" style="z-index:30"></div>
    <div class="macpanel">
      <div class="shead"><h2>Home aanpassen</h2><div class="done">${ic('check')}Klaar</div></div>
      <div class="intro">Sleep een rij met de muis naar zijn nieuwe plek. Uitgelicht en Verder kijken blijven staan waar ze staan.</div>
      <div class="list" style="top:104px">${fixedCard(true)}
        <div class="glabel">Jouw rijen<i>6 van 7 op Home</i></div><div class="card">${rows}</div>${newRow()}</div>
    </div>
    <div style="position:absolute;left:${200 + 34}px;width:${1440 - 400 - 56}px;top:${slotY + 4}px;z-index:47;background:var(--sheet);border-radius:14px">${lrow(DESK_ROWS[4], 'lifted', true)}</div>
    <div class="cursor" style="left:${200 + 50}px;top:${slotY + 22}px;width:26px;height:26px">${grabSvg}</div>
  </div>`;
};

S['44-n-mac-rechtsklik'] = () => `<div class="win">${lights()}${dnav()}${deskHome(true)}
  <div class="cmenu" style="left:250px;top:634px">
    <div class="mh">Recent toegevoegde series · Plex Familie</div>
    <div class="mi">${ic('up')}Omhoog verplaatsen</div>
    <div class="mi hl">${ic('down')}Omlaag verplaatsen</div>
    <div class="mi">${ic('eyeoff')}Verbergen op Home</div>
    <div class="sep"></div>
    <div class="mi">${ic('tune')}Home aanpassen…</div>
  </div>
  <div class="cursor" style="left:242px;top:618px">${cursorSvg}</div></div>`;

/* ---------- render ---------- */
function render(name) {
  document.body.className = `${SIZE} ${THEME}`;
  if (Q.get('x') === '2') document.documentElement.style.zoom = '2';
  document.body.innerHTML = S[name]();
}
