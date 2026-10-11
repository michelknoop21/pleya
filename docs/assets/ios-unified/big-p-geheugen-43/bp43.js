// Mockup 43: gedeelde stukken voor het geheugenscherm van Big P.
const P = '../detail-2026/';
const STILL = '../../tvos-unified/src/assets/bigp/';
const WORDMARK = '../../../../assets/branding/pleya_wordmark.png';
const S = (d, extra = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
const I = {
  back: S('<path d="M20 12H4M10 6l-6 6 6 6"/>'),
  search: S('<circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/>'),
  chev: S('<path d="m9 6 6 6-6 6"/>', 'class="ic chev"').replace('class="ic" ', ''),
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  cloud: S('<path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z"/>'),
  trash: S('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>'),
  chat: S('<path d="M4 5h16v11H10l-5 4v-4H4z"/>'),
  note: S('<path d="M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5"/>'),
  dots: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  up: S('<path d="M12 19V5M6 11l6-6 6 6"/>'),
  follow: S('<path d="M5 5v6a3 3 0 0 0 3 3h11M15 10l4 4-4 4"/>'),
  toggle: S('<rect x="2" y="6.5" width="20" height="11" rx="5.5"/><circle cx="16.5" cy="12" r="2.2" fill="currentColor"/>'),
  globe: S('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>'),
  home: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M3 11 12 3l9 8v10h-6v-6H9v6H3z"/></svg>',
  tv: S('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  film: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9h18v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1zM3 5l3-1 1 4H3zM8 3.5l3.5-.8 1.2 5.3H8.8zM14 2.3l3.5-.8 1.6 6.5h-3.8z"/></svg>',
};

const CATS = ['Voorkeuren', 'Niet voor mij', 'Huishouden', 'Kijkgewoonten', 'Overig'];
const SRC = { told: 'Door jou verteld', ok: 'Voorgesteld door Big P, door jou bevestigd', hand: 'Handmatig toegevoegd' };
const MEM = [
  ['Houdt niet van horror', 'Niet voor mij', SRC.ok],
  ['Kijkt op vrijdagavond met het gezin', 'Huishouden', SRC.told],
  ['Fan van Scandinavische misdaadseries', 'Voorkeuren', SRC.told],
  ['Geen films langer dan twee uur op doordeweekse avonden', 'Kijkgewoonten', SRC.hand],
  ['Heeft een hekel aan musicals', 'Niet voor mij', SRC.ok],
  ['Kijkt documentaires graag in het weekend', 'Kijkgewoonten', SRC.told],
];
const countOf = (c) => MEM.filter((m) => m[1] === c).length;

const status = (time = '9:41') => `<div class="status"><span>${time}</span><div class="island"></div><span style="font-size:14px">100%</span></div>`;
const bar = (title = 'Geheugen', { sub = '', menu = false, who = false } = {}) => `<div class="bar ${sub ? 'tall' : ''}"><span class="back">${I.back}</span><div class="ttl"><h1>${title}</h1>${sub ? `<span class="sub">${sub}</span>` : ''}</div>${who ? '<span class="who">Profiel Michel<span class="mono">M</span></span>' : ''}${menu ? `<span class="menu">${I.dots}</span>` : ''}</div>`;
const tabbar = (on = 'me') => `<div class="tabbar"><div class="${on === 'home' ? 'on' : ''}">${I.home}Home</div><div>${I.tv}Series</div><div>${I.film}Films</div><div class="${on === 'me' ? 'on' : ''}"><span class="mono tava">M</span>Mijn Pleya</div></div><div class="homeind"></div>`;

const switchRow = (on = true) => `<div class="srow"><div class="body"><div class="t">Geheugen gebruiken</div></div><span class="switch ${on ? 'on' : ''}"></span></div>
  <div class="explain">Alleen voor dit profiel, alleen op dit apparaat. Gebruik je een cloudmodel, dan gaan relevante herinneringen mee met je vraag.</div>`;
const navRow = (t, val = '') => `<div class="srow"><div class="body"><div class="t">${t}</div></div>${val !== '' ? `<span class="val">${val}</span>` : ''}${I.chev}</div>`;
const searchField = () => `<div class="search">${I.search}Zoek in herinneringen</div>`;
const chips = (sel = 'Alles', all = true) => (all ? ['Alles'] : []).concat(CATS).map((c) => `<span class="chip ${c === sel ? 'on' : ''}">${c}</span>`).join('');
const memRow = (m, { sel = false, chev = true } = {}) => `<div class="srow ${sel ? 'sel' : ''}"><div class="body"><div class="t">${m[0]}</div><div class="s">${m[1]} · ${m[2]}</div></div>${chev ? I.chev : ''}</div>`;
const memList = (opts = {}) => `<div class="card">${MEM.filter((m) => !opts.cat || m[1] === opts.cat).map((m, i) => memRow(m, { ...opts, sel: opts.sel === i })).join('')}</div>`;
const agesRow = () => `<div class="card"><div class="srow"><div class="body"><div class="t">Leeftijden kinderen</div><div class="s">Beheerd bij Kinderprofiel</div></div><span class="val">8 en 11</span>${I.chev}</div></div>`;
const addBtn = () => `<div class="btn pri">${I.plus}Herinnering toevoegen</div>`;
const wipe = (off = false) => `<div class="tbtn danger" style="${off ? 'opacity:.35' : ''}">Alle herinneringen wissen</div>`;

// Het overzicht: lopende tekst die Big P schrijft uit de opgeslagen herinneringen.
const OV = [
  ['Overzicht', "Je kijkt vooral 's avonds. Het liefst kies je dan een serie. De vrijdagavond is voor het gezin."],
  ['Voorkeuren', 'Je bent fan van Scandinavische misdaadseries. Documentaires kijk je graag in het weekend.'],
  ['Niet voor jou', 'Je houdt niet van horror. Aan musicals heb je een hekel.'],
  ['Huishouden', 'Je kijkt op vrijdagavond met het gezin. Je hebt twee kinderen. Hun leeftijden staan bij Kinderprofiel.'],
  ['Kijkgewoonten', 'Doordeweeks houd je het kort. Films die langer duren dan twee uur kijk je niet op doordeweekse avonden.'],
];
const QS = ['Wat past bij een vrijdagavond met het gezin?', 'Welke misdaadseries heb ik nog niet gezien?', 'Vat samen wat je over mijn smaak weet.'];
const OVFOOT = 'Dit overzicht is geschreven door Big P op basis van 6 herinneringen. De herinneringen zelf beheer je via het menu.';
const ovSections = () => OV.map((o) => `<h2>${o[0]}</h2><p>${o[1]}</p>`).join('');
const deeper = () => `<div class="deeper"><h2>Duik dieper</h2>${QS.map((q) => `<div class="q">${I.follow}<span>${q}</span></div>`).join('')}</div>`;
const ovFoot = () => `<div class="ovfoot">${OVFOOT}</div>`;
// state: idle (leeg veld), active (cursor), sent (tekst net verstuurd), off (uitgeschakeld)
const composer = ({ state = 'idle', text = '' } = {}) => `<div class="composer ${state}"><div class="cfield"><span class="ctext">${state === 'active' ? '<span class="caret"></span>' : ''}${text || '<span class="ph">Vraag of werk bij</span>'}</span><span class="send">${I.up}</span></div></div>`;
function overviewScreen({ sub = 'Zojuist bijgewerkt', comp = {} } = {}) {
  return status() + bar('Geheugen', { sub, menu: true }) + `<div class="scroll ov" id="sc">${ovSections()}${deeper()}${ovFoot()}</div>` + composer(comp) + tabbar();
}

// Het lijstscherm achter "Herinneringen beheren". Het filter staat op een categorie zodat het hele scherm in beeld past.
function manageScreen(cat = 'Niet voor mij') {
  return status() + bar('Herinneringen', { who: true }) + `<div class="scroll" id="sc">
    ${searchField()}
    <div class="fchips">${chips(cat)}</div>
    <div class="glabel">Herinneringen<i>${countOf(cat)} van ${MEM.length} herinneringen</i></div>${memList({ cat })}
    <div class="glabel">Uit je kinderprofiel</div>${agesRow()}
    <div style="margin-top:20px">${addBtn()}</div>
  </div>` + tabbar();
}
const toEnd = () => document.fonts.ready.then(() => { const s = document.getElementById('sc'); s.scrollTop = s.scrollHeight; });

// Puntjesraster voor de laadstaat: lichte stippen op donker, groter in het midden.
function dots(w, h, step = 20) {
  let out = '';
  for (let y = step / 2; y < h; y += step) for (let x = step / 2; x < w; x += step) {
    const d = Math.hypot((x - w / 2) / (w * 0.5), (y - h / 2) / (h * 0.46));
    const t = Math.max(0, 1 - d);
    if (t <= 0.02) continue;
    out += `<circle cx="${x}" cy="${y}" r="${(0.6 + 3.4 * t ** 1.6).toFixed(2)}" fill="#fff" opacity="${(0.08 + 0.3 * t).toFixed(2)}"/>`;
  }
  return `<svg class="dots" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${out}</svg>`;
}

function keyboard() {
  const row = (s) => `<div class="row">${[...s].map((c) => `<span class="k">${c}</span>`).join('')}</div>`;
  return `<div class="kb">${row('qwertyuiop')}${row('asdfghjkl')}
    <div class="row"><span class="k w">${S('<path d="M12 4 4 13h5v6h6v-6h5z"/>')}</span>${[...'zxcvbnm'].map((c) => `<span class="k">${c}</span>`).join('')}<span class="k w">${S('<path d="M9 6h11v12H9l-6-6zM13 10l4 4M17 10l-4 4"/>')}</span></div>
    <div class="row"><span class="k w">123</span><span class="k w">${I.globe}</span><span class="k sp">spatie</span><span class="k ret">return</span></div>
  </div>`;
}

// Home-achtergrond en Big P uit set 39, voor het gespreksbeeld.
function homeBg() {
  return status() + `<div class="hdr"><img class="logo" src="${WORDMARK}"><span class="hsearch">${I.search}</span><span class="face"></span><span class="mono ava">M</span></div>
  <div class="hchips"><span>Series</span><span>Films</span></div>
  <div class="sec" style="top:186px">Verder kijken</div>
  <div class="land" style="top:228px"><div><img src="${P}sintel-wide.jpg"><b>Sintel</b></div><div><img src="${P}bbb-wide.jpg"><b>Big Buck Bunny</b></div></div>
  <div class="sec" style="top:432px">Recent toegevoegde films</div>
  <div class="rail" style="top:474px"><div><img src="${P}tears-poster.jpg"><b>Tears of Steel</b></div><div><img src="${P}spring-poster.jpg"><b>Spring</b></div><div><img src="${P}elephants-poster.jpg"><b>Elephants Dream</b></div></div>`;
}
const bp = (pose, { left, top, width }) => `<div class="bp" style="left:${left}px;top:${top}px;width:${width}px"><span class="shadow"></span><img src="${STILL}${pose}.png"></div>`;
const tail = (x, y) => `<span class="tail" style="left:${x - 11}px;top:${y - 26}px"></span>`;
