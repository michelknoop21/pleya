/* Mockup 45: Kinderen in huis. Eén bron voor alle beelden: ?t=dark|light&s=ph|pad|tv&x=2 (zoom 2 voor scherpe PNG's). */
const Q = new URLSearchParams(location.search);
const THEME = Q.get('t') || 'dark';
const WORDMARK = '../../../../assets/branding/pleya_wordmark.png';
const MARK = '../../../../assets/branding/pleya_mark.png';
const BIGP = '../../tvos-unified/src/assets/bigp/';
const S = (d, fill) => `<svg class="ic" viewBox="0 0 24 24" fill="${fill || 'none'}" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const I = {
  back: S('<path d="M20 12H4M10 6l-6 6 6 6"/>'),
  chev: S('<path d="m9 6 6 6-6 6"/>').replace('class="ic"', '').replace('<svg ', '<svg class="ic chev" '),
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  baby: S('<circle cx="12" cy="9" r="5"/><path d="M5 21c1-4 4-6 7-6s6 2 7 6"/>'),
  mic: S('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'),
  home: S('<path d="M3 11 12 3l9 8v10h-6v-6H9v6H3z"/>', 'currentColor'),
  tv: S('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  film: S('<path d="M3 9h18v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1zM3 5l3-1 1 4H3zM8 3.5l3.5-.8 1.2 5.3H8.8zM14 2.3l3.5-.8 1.6 6.5h-3.8z"/>', 'currentColor'),
  search: S('<circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/>'),
  down: S('<path d="m6 9 6 6 6-6"/>'),
};

// Oudste eerst. Peildatum van de mockup: 16 oktober 2026.
const KIDS = [
  { n: 'Noor', m: 'maart 2020', a: '6 jaar' },
  { n: 'Sam', m: 'mei 2023', a: '3 jaar' },
  { n: 'Luuk', m: 'juli 2026', a: '3 maanden' },
];
const EXPLAIN = '<b>Alleen op dit toestel.</b> Big P gebruikt dit om voorstellen voor je kinderen te filteren, op elk profiel. De namen gaan nooit naar het AI-model, alleen de leeftijd van het jongste kind.';

const status = () => `<div class="status"><span>9:41</span><div class="island"></div><span style="font-size:14px">100%</span></div>`;
const bar = (t, who) => `<div class="bar"><span class="back">${I.back}</span><h1>${t}</h1>${who || ''}</div>`;
const whoAdult = '<span class="who">Profiel Michel<span class="mono">M</span></span>';
const whoKid = '<span class="who kid">Profiel Sam<span class="mono">S</span></span>';
const tabbar = () => `<div class="tabbar"><div>${I.home}Home</div><div>${I.tv}Series</div><div>${I.film}Films</div><div class="on"><span class="mono tava">M</span>Mijn Pleya</div></div><div class="homeind"></div>`;
const navRow = (t, s, val) => `<div class="srow"><div class="body"><div class="t">${t}</div>${s ? `<div class="s">${s}</div>` : ''}</div>${val ? `<span class="val">${val}</span>` : ''}${I.chev}</div>`;
const sw = (t, s, on) => `<div class="srow"><div class="body"><div class="t">${t}</div>${s ? `<div class="s">${s}</div>` : ''}</div><span class="switch ${on ? 'on' : ''}"></span></div>`;
const kidRow = (k, sel) => `<div class="srow ${sel ? 'sel' : ''}"><span class="lead">${k.n[0]}</span><div class="body"><div class="t">${k.n}</div><div class="s">${k.m}</div></div><span class="val">${k.a}</span>${I.chev}</div>`;
const addRow = () => `<div class="srow add"><span class="lead">${I.plus}</span><div class="body"><div class="t">Kind toevoegen</div></div></div>`;

// ---------- schermen ----------
const S_ = {};
S_['45-a-ingang'] = () => status() + bar('Big P', whoAdult) + `<div class="scroll">
  <div class="glabel">Gebruik</div>
  <div class="card">${navRow('Geheugen', '', 'Aan')}${sw('Stem van Big P', 'Korte gesproken reacties. Nooit tijdens dicteren of kijken.', true)}</div>
  <div class="glabel">Huishouden</div>
  <div class="card">${navRow('Kinderen in huis', 'Voor voorstellen voor je kinderen, op elk profiel', '3 kinderen')}</div>
  <div class="glabel">Kinderprofiel</div>
  <div class="card">${sw('Kinderprofiel', 'Big P toont op dit profiel alleen titels die bij de leeftijd van de kinderen passen. Alleen voor dit profiel, alleen op dit toestel.', false)}</div>
  <div class="mockup-note">Toelichting bij de mockup: op een volwassen profiel vervangt "Kinderen in huis" de rij "Leeftijden kinderen (dit profiel)". Die rij blijft alleen bestaan op een kinderprofiel (45 H).</div>
</div>` + tabbar();

S_['45-b-lijst'] = () => status() + bar('Kinderen in huis', whoAdult) + `<div class="scroll">
  <div class="glabel">Kinderen<i>3 kinderen</i></div>
  <div class="card">${KIDS.map((k) => kidRow(k)).join('')}${addRow()}</div>
  <div class="explain">${EXPLAIN}</div>
</div>` + tabbar();

S_['45-c-leeg'] = () => status() + bar('Kinderen in huis', whoAdult) + `<div class="scroll">
  <div class="card empty"><div class="ring">${I.baby}</div><b>Nog geen kinderen.</b>
    <p>Voeg je kinderen één keer toe. Dan kan Big P op elk profiel voorstellen voor "mijn kinderen" op hun leeftijd afstemmen.</p>
    <div class="btn pri">${I.plus}Kind toevoegen</div></div>
  <div class="explain">${EXPLAIN}</div>
</div>` + tabbar();

const wheel = (mo, yr) => `<div class="wheel"><div class="col">${mo.map((x, i) => `<div class="${i === 1 ? 'on' : ''}">${x}</div>`).join('')}</div><div class="col">${yr.map((x, i) => `<div class="${i === 1 ? 'on' : ''}">${x}</div>`).join('')}</div></div>`;
const editSheet = ({ title, name, mo, yr, now, del }) => `<div class="dim"></div><div class="sheet"><div class="grab"></div><h2>${title}</h2>
  <div class="flabel"><span>Naam</span></div><div class="field">${name}</div>
  <div class="flabel"><span>Geboortemaand</span></div>${wheel(mo, yr)}
  <div class="preview">${I.baby.replace('class="ic"', 'class="ic" style="font-size:18px"')}<span>${now}</span></div>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn pri">Bewaar</div></div>
  ${del ? '<div class="tbtn danger" style="margin-top:6px">Verwijderen</div>' : ''}
</div><div class="homeind"></div>`;
const listBehind = (sel) => status() + bar('Kinderen in huis', whoAdult) + `<div class="scroll"><div class="glabel">Kinderen<i>3 kinderen</i></div><div class="card">${KIDS.map((k, i) => kidRow(k, i === sel)).join('')}${addRow()}</div></div>` + tabbar();

S_['45-d-toevoegen'] = () => listBehind(-1) + editSheet({ title: 'Kind toevoegen', name: 'Sam', mo: ['april', 'mei', 'juni'], yr: ['2022', '2023', '2024'], now: 'Wordt nu <b>3 jaar</b>', del: false });
S_['45-e-bewerken'] = () => listBehind(0) + editSheet({ title: 'Kind bewerken', name: 'Noor', mo: ['februari', 'maart', 'april'], yr: ['2019', '2020', '2021'], now: 'Is nu <b>6 jaar</b>', del: true });
S_['45-f-wissen'] = () => listBehind(1) + `<div class="dim"></div><div class="dialog"><h2>Sam verwijderen?</h2>
  <p>Big P houdt bij voorstellen voor je kinderen dan geen rekening meer met Sam. Andere kinderen blijven staan.</p>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn del">Verwijderen</div></div></div><div class="homeind"></div>`;

S_['45-g-kaart'] = () => status() + `<div class="ball">
  <div class="asked"><span>Je vroeg: </span>Wat kunnen mijn kinderen vanavond kijken?</div>
  <div class="pcard"><div class="head"><img src="${MARK}"><span>Pleya vraagt</span></div>
    <h3>Voor welke kinderen?</h3>
    <p>Voeg ze één keer toe. Dan filtert Big P hiermee op elk profiel. Namen en maanden blijven op dit toestel. Het AI-model krijgt alleen de leeftijd van het jongste kind.</p>
    <div class="donechip"><b>Noor</b>maart 2020<span>6 jaar</span></div>
    <div class="kidrow"><div class="flabel"><span>Naam</span></div><div class="field active">Sam<span class="dd"></span></div></div>
    <div class="kidrow"><div class="flabel"><span>Geboortemaand</span></div><div class="pair2"><div class="field">mei<span class="dd">${I.down}</span></div><div class="field">2023<span class="dd">${I.down}</span></div></div></div>
    <div class="more">${I.plus}Nog een kind toevoegen</div>
    <div class="btn pri">Bewaar en zoek verder</div>
  </div></div>
  <div class="bp" style="left:236px;top:690px;width:150px"><img src="${BIGP}bigp-bezorgd.png"></div>`;

S_['45-h-kinderprofiel'] = () => status() + bar('Big P', whoKid) + `<div class="scroll">
  <div class="glabel">Gebruik</div>
  <div class="card">${sw('Stem van Big P', 'Korte gesproken reacties. Nooit tijdens dicteren of kijken.', true)}</div>
  <div class="glabel">Kinderprofiel</div>
  <div class="card">${sw('Kinderprofiel', 'Big P toont alleen titels die bij de leeftijd van de kinderen passen. Alleen voor dit profiel, alleen op dit toestel.', true)}${navRow('Leeftijden kinderen (dit profiel)', '', '3 jaar')}</div>
  <div class="mockup-note">Toelichting bij de mockup: op een kinderprofiel is "Kinderen in huis" verborgen, niet alleen vergrendeld. De namen en geboortemaanden van het huishouden zijn alleen voor een ouder. Het geheugen heeft hier ook geen ingang (bestaand gedrag).</div>
</div>` + tabbar();

S_['45-i-ipad'] = () => `<div class="status"><span>9:41  vr 16 okt</span><span style="font-size:14px">100%</span></div>` + bar('Kinderen in huis', whoAdult) + `<div class="cols">
  <div><div class="glabel" style="margin-top:6px">Kinderen<i>3 kinderen</i></div>
    <div class="card">${KIDS.map((k, i) => kidRow(k, i === 1)).join('')}${addRow()}</div><div class="explain">${EXPLAIN}</div></div>
  <div class="pane"><h2>Kind bewerken</h2>
    <div class="flabel"><span>Naam</span></div><div class="field active">Sam</div>
    <div class="flabel"><span>Geboortemaand</span></div><div class="pair2"><div class="field">mei<span class="dd">${I.down}</span></div><div class="field">2023<span class="dd">${I.down}</span></div></div>
    <div class="preview">${I.baby.replace('class="ic"', 'class="ic" style="font-size:18px"')}<span>Is nu <b>3 jaar</b></span></div>
    <div class="acts"><div class="btn">Annuleren</div><div class="btn pri">Bewaar</div></div>
    <div class="tbtn danger" style="margin-top:6px">Verwijderen</div></div>
</div>` + `<div class="tabbar"><div>${I.home}Home</div><div>${I.tv}Series</div><div>${I.film}Films</div><div class="on"><span class="mono tava">M</span>Mijn Pleya</div></div>`;

// ---------- tvOS ----------
const tvNav = () => `<nav class="topnav"><div class="pchip">M</div><div class="cluster"><span class="nsearch">${I.search}</span><span class="item">Home</span><span class="item">Series</span><span class="item">Films</span><span class="item">Live TV</span><span class="item on">Mijn Pleya</span></div><div class="wordmark"><img src="../../tvos-unified/src/assets/pleya_wordmark.png" style="height:52px"></div></nav>`;
const tvRow = (k, focus) => `<div class="row ${focus ? 'focus' : ''}"><span class="lead">${k.n[0]}</span><div class="body"><div class="t">${k.n}</div><div class="s">${k.m}</div></div><span class="val">${k.a}</span>${I.chev}</div>`;
const tvList = (focusAdd) => tvNav() + `<div class="page"><div class="page-title">Kinderen in huis</div><div class="crumb">Mijn Pleya ▸ Instellingen ▸ Big P ▸ Kinderen in huis</div>
  <div class="wide"><div class="rows">${KIDS.map((k, i) => tvRow(k, i === 1 && !focusAdd)).join('')}
    <div class="row ${focusAdd ? 'focus' : ''}"><span class="lead" style="background:#fff;color:#141414">${I.plus}</span><div class="body"><div class="t">Kind toevoegen</div></div></div></div>
    <div class="foot">${EXPLAIN.replace(/<\/?b>/g, '')}</div></div></div>`;
S_['45-j-tv-lijst'] = () => tvList(false);
S_['45-k-tv-naam'] = () => tvList(true) + `<div class="dim"></div><div class="panel"><h2>Kind toevoegen</h2><div class="sub">Naam en geboortemaand. De naam blijft op dit toestel.</div>
  <div class="flab">Naam</div><div class="fld focus"><span class="ph">Naam</span>${I.mic}</div>
  <div class="hint">OK opent het toetsenbord. Dicteren kan met de microfoonknop op de remote.</div>
  <div class="flab">Geboortemaand</div><div class="duo"><div class="fld"><span class="ph">Maand</span></div><div class="fld"><span class="ph">Jaar</span></div></div>
  <div class="acts"><div class="pbtn">Annuleren</div><div class="pbtn pri" style="opacity:.4">Bewaar</div></div></div>`;
S_['45-l-tv-maand'] = () => tvList(true) + `<div class="dim"></div><div class="panel"><h2>Kind toevoegen</h2><div class="sub">Naam en geboortemaand. De naam blijft op dit toestel.</div>
  <div class="flab">Naam</div><div class="fld">Sam</div>
  <div class="flab">Geboortemaand</div><div class="duo"><div class="step"><span class="arr" style="top:-36px">▲</span><div class="fld step focus">mei</div><span class="arr" style="bottom:-40px">▼</span></div><div class="fld step">2023</div></div>
  <div class="hint" style="margin-top:46px">Omhoog en omlaag kiest. Rechts gaat naar het jaar, OK naar Bewaar. Wordt nu 3 jaar.</div>
  <div class="acts"><div class="pbtn">Annuleren</div><div class="pbtn pri">Bewaar</div></div></div>`;

function render(name) {
  const size = Q.get('s') || 'ph';
  document.body.className = `${size} ${THEME}`;
  if (Q.get('x') === '2') document.documentElement.style.zoom = '2';
  document.body.innerHTML = S_[name]();
}
