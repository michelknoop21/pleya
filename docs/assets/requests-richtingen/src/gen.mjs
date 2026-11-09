// Drie ontwerprichtingen voor Aanvragen, meldingen en notificaties (keuzeronde, A-20).
// A Affiche: posters voorop, zoals Home. B Tijdlijn: elke aanvraag als zending met stappen.
// C Regiekamer: compact en beheer eerst. Per richting vier telefoonschermen en een TV-scherm.
// Elk telefoonscherm volgt hetzelfde skelet (statusbalk, kop, inhoud, voet, tabbalk); de
// meetcontrole onderaan faalt als koppen, tekstkolommen of randen niet kloppen.
// Gebruik: node gen.mjs [--grid]   (--grid tekent kantlijn en tekstkolom, alleen voor controle)
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('.', import.meta.url).pathname, SET = join(ROOT, '..'), OUT = join(ROOT, 'out');
const GRID = process.argv.includes('--grid');
const TVSRC = '../../../tvos-unified/src', RQCSS = '../../../requests-2.0/src/rq.css', ART = '../../../ios-unified/detail-2026';
const sv = (d, x = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${x}>${d}</svg>`;
const I = {
  back: sv('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'), search: sv('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'),
  check: sv('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.6"'), close: sv('<path d="m6 6 12 12M18 6 6 18"/>', 'stroke-width="2.4"'),
  chevd: sv('<path d="m6 9 6 6 6-6"/>'), more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>', edit: sv('<path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4"/>'),
  info: sv('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'), flag: sv('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'),
  filter: sv('<path d="M4 6h16M7 12h10M10 18h4"/>'), dl: sv('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>'),
  clock: sv('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'), plus: sv('<path d="M12 5v14M5 12h14"/>'), send: sv('<path d="m4 12 16-8-6 16-2-6z"/>'),
  audio: sv('<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>'), cc: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10.5 10.2a2.3 2.3 0 1 0 0 3.6M17 10.2a2.3 2.3 0 1 0 0 3.6"/>'),
  image: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m21 16-5-5-8 8"/>'), chat: sv('<path d="M4 5h16v11H9l-5 4z"/>'),
  gear: sv('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>'),
  swipe: sv('<path d="M5 12h14M15 8l4 4-4 4"/>'), home: sv('<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4z"/>'), show: sv('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  film: sv('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16"/>'), live: sv('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m7 3 5 3 5-3"/>'), person: sv('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
};
const IT = {
  charge: { t: 'Charge', img: 'charge-poster' }, sintel: { t: 'Sintel', img: 'sintel-poster', wide: 'sintel-wide' },
  tears: { t: 'Tears of Steel', img: 'tears-poster' }, spring: { t: 'Spring', img: 'spring-poster' },
  camin: { t: 'Caminandes', img: 'caminandes-poster', wide: 'bbb-wide' }, dweebs: { t: 'Dweebs', img: 'dweebs-poster' },
  eleph: { t: 'Elephants Dream', img: 'elephants-poster' }, coffee: { t: 'Coffee Run', img: 'coffeerun-poster' },
  wad: { t: 'Wadlopers', h: 196 }, glas: { t: 'Glasstad', h: 286 }, nacht: { t: 'Nachttrein', h: 250 }, kust: { t: 'Kustlijn', h: 172 }, onder: { t: 'Onderstroom', h: 340 },
};
const art = (k, wide) => { const it = IT[k]; return wide && it.wide ? `<img src="${ART}/${it.wide}.jpg" alt="">` : it.img ? `<img src="${ART}/${it.img}.jpg" alt="">` : `<div class="fx" style="--h:${it.h}"><b>${it.t}</b><i>FIXTURE</i></div>`; };
const pp = k => `<div class="pp">${art(k)}</div>`;
const btn = (l, k = '', ic = '') => `<span class="b ${k}">${ic}${l}</span>`;
const tx = (t, s, extra = '') => `<div class="tx"><div class="t">${t}</div>${s ? `<div class="s">${s}</div>` : ''}${extra}</div>`;
const status = '<div class="status"><span>9:41</span><div class="island"></div><span></span></div>';
const tabbar = `<div class="tabbar"><div>${I.home}Home</div><div>${I.show}Series</div><div>${I.film}Films</div><div>${I.live}Live TV</div><div class="on">${I.person}Mijn Pleya</div></div><div class="homeind"></div>`;
// Het skelet: statusbalk 54, kop (rij van 44 op y 62), inhoud, optionele voet, tabbalk 84.
const screen = ({ r1, r2 = '', body, bodyCls = '', ft = '', under = '', over = '' }) =>
  `${under}<div class="scr"><div class="sbs"></div><div class="hd"><div class="r1">${r1}</div>${r2}</div><div class="bd ${bodyCls}">${body}</div>${ft ? `<div class="ft">${ft}</div>` : ''}<div class="tbs"></div></div>${status}${tabbar}${over}`;
const icons = (...a) => `<span class="icons">${a.join('')}</span>`;
const topnav = a => `<nav class="topnav"><div class="chip">M</div><div class="cluster">${I.search.replace('class="ic"', 'class="ic search"')}${['Home', 'Series', 'Films', 'Live TV', 'Mijn Pleya'].map(n => `<div class="item${n === a ? ' on' : ''}">${n}</div>`).join('')}</div><div class="wordmark"><img src="${TVSRC}/assets/pleya_wordmark.png" alt="Pleya"></div></nav>`;

// ======================= A. AFFICHE (tekstkolom 80) =======================
const pc = (k, o = {}) => `<div class="pc${o.focus ? ' focus' : ''}">${art(k)}<div class="scr2"></div>${o.who ? `<div class="who"><span class="av">${o.who}</span></div>` : ''}<div class="lb"><b>${IT[k].t}</b><span>${o.st ?? ''}</span></div>${o.p != null ? `<div class="pb"><i style="width:${o.p}%"></i></div>` : ''}</div>`;
const aTabs = on => `<div class="tabs">${['Alle', 'Van mij', 'Meldingen'].map(t => `<span class="${t === on ? 'on' : ''}">${t}</span>`).join('')}</div>`;
const nrow = (k, t, s, unread) => `<div class="nrow">${pp(k)}${tx(t, s)}<i class="ud${unread ? '' : ' off'}"></i></div>`;
const A = {
  list: () => screen({ r1: `<h1>Aanvragen</h1>${icons(I.search, I.filter)}`, r2: aTabs('Alle'), bodyCls: 'fade', body: `
<div class="blk"><div class="sh">Wacht op jou <small>27</small><span class="all">Alles</span></div>
<div class="pair">${[['wad', 'Seizoen 3 tot 5'], ['tears', 'Film · 4K']].map(([k, s]) => `<div>${pc(k, { who: 'R', st: `<i class="dot wait"></i>${s}` })}<div class="brow2 dec">${btn('Goedkeuren', 'pri')}${btn('', 'icon', I.close)}</div></div>`).join('')}</div></div>
<div class="blk"><div class="sh">Onderweg <small>3</small></div><div class="rail">${pc('charge', { st: '62% · ±20 min', p: 62 })}${pc('glas', { st: 'In de wachtrij', p: 4 })}${pc('kust', { st: 'S3 · 18%', p: 18 })}${pc('coffee', { st: '91%', p: 91 })}</div></div>` }),
  detail: () => screen({ under: `<div class="hero">${art('camin', true)}</div>`, r1: `<span class="glass">${I.back}</span><span style="flex:1"></span><span class="glass">${I.more}</span>`, bodyCls: 'end', body: `
<div class="meta"><i class="dot wait"></i>Wacht op jou · aangevraagd door Ravi, 6 okt</div><div class="dt">Caminandes</div><div class="meta">Serie · 2013 · Animatie · HD</div>
<div class="seas"><span><i class="dot ok"></i>S1 in Pleya</span><span><i class="dot wait"></i>S2 gevraagd</span><span><i class="dot wait"></i>S3 gevraagd</span></div>
<div style="height:4px"></div>${btn('Goedkeuren', 'pri bigb', I.check)}<div class="brow2 row2">${btn('Afwijzen', '', I.close)}${btn('Aanpassen', '', I.edit)}</div>
<div class="rnd"><div><span>${I.info}</span>Titel</div><div><span>${I.play}</span>Trailer</div><div><span>${I.chat}</span>Reageer</div><div><span>${I.person}</span>Ravi</div></div>` }),
  issue: () => screen({ r1: `<h1>Aanvragen</h1>${icons(I.search, I.filter)}`, r2: aTabs('Meldingen'), bodyCls: 'fade', body: `
<div class="still"><div class="img">${art('sintel', true)}<span class="tag l">${I.play}12:04</span><span class="tag r">${I.audio}Geluid</span></div><div class="txt"><b>Sintel · geluid loopt achter</b><span>Ravi · 8 nov · 2 reacties</span><q>Zie het ook. Ik heb een andere release aangevraagd.</q></div></div>
<div class="still"><div class="img">${art('camin', true)}<span class="tag l">${I.play}S2 A1 · 03:40</span><span class="tag r">${I.cc}Ondertiteling</span></div><div class="txt"><b>Caminandes · geen Nederlandse ondertitels</b><span>Sanne · 7 nov · nog geen reactie</span></div></div>
<div class="blk"><div class="sh">Opgelost <small>41</small><span class="all">Alles</span></div><div class="lst">${nrow('glas', 'Glasstad · beeld hapert', 'Noor · opgelost 30 okt')}</div></div>` }),
  noti: () => screen({ r1: `<h1>Voor jou</h1>${icons(I.gear)}`, r2: `<div class="tabs"><span class="on">Nieuw 3</span><span>Eerder</span></div>`, body: `
<div class="ncard"><img src="${ART}/sintel-wide.jpg" alt=""><span class="bigic">${I.check}</span>${tx('Sintel', 'Film · 2010 · 4K HDR', btn('Afspelen', 'pri', I.play)).replace('<div class="tx">', '<div class="tx"><div class="k">Je aanvraag staat klaar</div>')}</div>
<div class="lst">${nrow('nacht', 'Michel reageerde op je melding', 'Nachttrein S1 A3 · “Nieuwe versie staat erop.”', 1)}${nrow('kust', 'Nieuwe aflevering van Kustlijn', 'Seizoen 3, aflevering 4 · 08:15', 1)}${nrow('wad', 'Wadlopers seizoen 3 goedgekeurd', 'Downloaden begint zo · maandag')}${nrow('charge', 'Charge staat in de wachtrij', 'Goedgekeurd door Michel · zondag')}</div>` }),
  tv: () => `${topnav('Mijn Pleya')}<div class="tpg"><div class="ttl">Aanvragen</div>
<div class="tsh">Wacht op jou <small>27</small></div><div class="trail">${[['wad', 'R', 'S3 tot 5', 1], ['tears', 'R', 'Film · 4K'], ['dweebs', 'N', 'Seizoen 2'], ['eleph', 'S', 'Film'], ['glas', 'R', 'Film'], ['kust', 'N', 'Seizoen 4'], ['spring', 'S', 'Film']].map(([k, w, s, f]) => pc(k, { who: w, st: `<i class="dot wait"></i>${s}`, focus: f })).join('')}</div>
<div class="tdec">${btn('Goedkeuren', 'pri focus', I.check)}${btn('Afwijzen', '', I.close)}${btn('Openen', '', I.info)}</div>
<div class="peek"><div class="tsh">Onderweg <small>3</small></div><div class="trail">${pc('charge', { st: '62% · ±20 min', p: 62 })}${pc('coffee', { st: '91%', p: 91 })}${pc('nacht', { st: 'S2 · 18%', p: 18 })}</div></div></div>`,
};

// ======================= B. TIJDLIJN (tekstkolom 74) =======================
const steps = (n, p, wait) => `<div class="steps">${[0, 1, 2, 3].map(i => `<i class="${i < n ? 'd' : i === n ? (wait ? 'w' : 'c') : ''}"${i === n && !wait ? ` style="--p:${p}%"` : ''}></i>`).join('')}</div>`;
const tr = (k, s, n, p, lab, right, o = {}) => `<div class="tr${o.focus ? ' focus' : ''}">${pp(k)}${tx(`${IT[k].t}${o.when ? `<small>${o.when}</small>` : ''}`, s, `${steps(n, p, o.wait)}<div class="sl"><b>${lab}</b><span>${right}</span></div>${o.qa ? `<div class="brow2 qa">${btn('Goedkeuren', 'pri', I.check)}${btn('Afwijzen')}</div>` : ''}`)}</div>`;
const stp = (cls, ic, t, s, extra = '') => `<div class="st ${cls}"><div class="lead"><span class="k">${ic}</span></div>${tx(t, s, extra)}</div>`;
const act = (cls, ic, t, s, o = {}) => `<div class="act"><div class="lead"><span class="ik ${cls}">${ic}</span></div>${tx(t, s, o.mini ?? '')}<i class="ud${o.unread ? '' : ' off'}"></i></div>`;
const mini = n => `<div class="mini">${[0, 1, 2, 3].map(i => `<i class="${i < n ? 'd' : ''}"></i>`).join('')}</div>`;
const bCard = (k, t, s) => `<div class="bcard">${pp(k)}${tx(t, s)}</div>`;
const B = {
  list: () => screen({ r1: `<h1>Aanvragen</h1><span class="scope">Alle ${I.chevd}</span>${I.search}`, r2: `<div class="chips"><span class="on">Actief <span class="n">31</span></span><span>Klaar <span class="n">35</span></span><span>Afgewezen <span class="n">14</span></span></div>`, bodyCls: 'fade', body: `
<div class="gh"><i class="dot wait"></i>Vraagt om jou</div>${tr('wad', 'Ravi · seizoen 3 tot 5', 0, 0, 'Wacht op goedkeuring', '6 okt', { wait: 1, qa: 1 })}
<div class="gh" style="margin-top:12px"><i class="dot run"></i>Onderweg</div>${tr('charge', 'Sanne · film · 4K', 2, 62, 'Downloaden 62%', 'nog ±20 min')}${tr('glas', 'Sanne · film', 1, 0, 'Goedgekeurd', 'in de wachtrij')}${tr('kust', 'Ravi · seizoen 3', 2, 18, 'Downloaden 18%', 'nog ±1 u')}` }),
  detail: () => screen({ r1: `${I.back}<h1>Charge</h1>${icons(I.more)}`, body: `
${bCard('charge', 'Film · 2022 · 4K', 'Aangevraagd door Sanne, 6 okt').replace('</div></div>', `<div class="eta">${I.clock}Waarschijnlijk klaar om 14:40</div></div></div>`)}
<div class="tl">${stp('d', I.check, 'Aangevraagd', 'Sanne · 6 okt, 14:02')}${stp('d', I.check, 'Goedgekeurd', 'Michel · 6 okt, 14:10 · Radarr 4K', '<div class="bub me">In 4K, dus het kan even duren.</div>')}${stp('c', I.dl, 'Downloaden · 62%', '8,4 van 13,6 GB · nog ongeveer 20 minuten', '<div class="pbar"><i></i></div>')}${stp('', I.play, 'Beschikbaar in Films', 'Je krijgt een notificatie als hij klaarstaat')}</div>
<div class="facts"><div>Kwaliteit<b>4K</b></div><div>Server<b>Radarr 4K</b></div><div>Grootte<b>13,6 GB</b></div><div>Limiet Sanne<b>3 van 5</b></div><div>Map<b>/films-4k</b></div><div>Via<b>Pleya iPhone</b></div></div>`, ft: btn('Annuleren', '', I.close) + btn('Titel openen', '', I.info) }),
  issue: () => screen({ r1: `${I.back}<h1>Melding #128</h1>${icons(I.more)}`, body: `
${bCard('nacht', 'Nachttrein', 'Seizoen 1, aflevering 3 · Geluid · vanaf 12:04')}
<div class="tl">${stp('d', I.flag, 'Gemeld door Ravi', '8 nov, 21:14', '<div class="bub">Vanaf ongeveer 12 minuten loopt het geluid een halve seconde achter.</div>')}${stp('d', I.chat, 'Michel reageerde', '8 nov, 22:02', '<div class="bub me">Ik heb een andere release aangevraagd.</div>')}${stp('d', I.chat, 'Ravi reageerde', '9 nov, 09:30', '<div class="bub">Top, dank je. Ik wacht er even mee.</div>')}${stp('d', I.dl, 'Nieuwe versie binnen', '9 nov, 11:30 · automatisch gezien door Pleya')}${stp('c', I.clock, 'Wacht op Ravi', 'Klopt het nu? Dan kan de melding dicht.')}</div>`, ft: `<div class="f">Schrijf een reactie</div>${btn('', 'pri icon', I.send)}` }),
  noti: () => screen({ r1: `<h1>Activiteit</h1>${icons(I.gear)}`, r2: `<div class="chips"><span class="on">Alles</span><span>Aanvragen</span><span>Meldingen</span><span>Bibliotheek</span></div>`, bodyCls: 'fade', body: `
<div class="gh">Vandaag</div>${act('ok', I.check, 'Charge staat klaar in Films', 'Aanvraag · 14:40', { unread: 1, mini: mini(4) })}${act('', I.chat, 'Michel reageerde op je melding over Nachttrein', 'Melding · 11:40', { unread: 1 })}${act('am', I.dl, 'Kustlijn seizoen 3 wordt gedownload', 'Aanvraag · 18% · 09:02', { unread: 1, mini: mini(2) })}
<div class="gh" style="margin-top:12px">Deze week</div>${act('', I.plus, 'Nieuwe aflevering van Dweebs', 'Bibliotheek · maandag')}${act('red', I.close, 'Zoutland is afgewezen', 'Aanvraag · zondag · “Staat al op Netflix”')}${act('ok', I.check, 'Je melding over Sintel is opgelost', 'Melding · zaterdag')}${act('', I.plus, 'Nieuwe film in je bibliotheek: Spring', 'Bibliotheek · vrijdag')}` }),
  tv: () => `${topnav('Mijn Pleya')}<div class="tpg"><div class="ttl">Aanvragen</div><div class="two"><div class="lst">${tr('charge', 'Sanne · film · 4K', 2, 62, 'Downloaden 62%', 'nog ±20 min', { focus: 1 })}${tr('wad', 'Ravi · seizoen 3 tot 5', 0, 0, 'Wacht op goedkeuring', '6 okt', { wait: 1 })}${tr('glas', 'Sanne · film', 1, 0, 'Goedgekeurd', 'in de wachtrij')}${tr('kust', 'Ravi · seizoen 3', 2, 18, 'Downloaden 18%', 'nog ±1 u')}</div>
<div class="panel2"><h2>Charge</h2><div class="s0">Film · 2022 · 4K · aangevraagd door Sanne</div><div class="tl">${stp('d', I.check, 'Aangevraagd', 'Sanne · 6 okt, 14:02')}${stp('d', I.check, 'Goedgekeurd', 'Michel · 6 okt, 14:10')}${stp('c', I.dl, 'Downloaden · 62%', 'nog ongeveer 20 minuten', '<div class="pbar"><i></i></div>')}${stp('', I.play, 'Beschikbaar in Films', 'verwacht om 14:40')}</div>
<div class="facts"><div>Kwaliteit<b>4K</b></div><div>Server<b>Radarr 4K</b></div><div>Limiet<b>3 van 5</b></div></div><div class="tvb">${btn('Titel openen', '', I.info)}${btn('Annuleren', '', I.close)}</div></div></div></div>`,
};

// ======================= C. REGIEKAMER (tekstkolom 100) =======================
const tiles3 = sel => `<div class="tiles3">${[['am', 27, 'wachten op jou'], ['', 6, 'meldingen open'], ['red', 2, 'mislukt']].map(([c, n, l], i) => `<div class="ctile ${c}${sel === i ? ' on' : ''}"><b>${n}</b><span>${l}</span></div>`).join('')}</div>`;
const sel = on => `<div class="lead20"><span class="sel${on ? ' on' : ''}">${on ? I.check : ''}</span></div>`;
const udot = on => `<div class="lead20">${on ? '<i class="udot"></i>' : ''}</div>`;
const qr = (lead, thumb, t, s, age, o = {}) => `<div class="qr${o.swipe ? ' swipe' : ''}${o.focus ? ' focus' : ''}${o.top ? ' top' : ''}">${lead}${thumb}${tx(t, s, o.extra ?? '')}<span class="age">${age}</span>${o.noBtns ? '' : `<span class="rb">${I.close}</span><span class="rb y${o.fy ? ' focus' : ''}">${I.check}</span>`}</div>`;
const CQ = (n = 5) => `<div class="q">${[['wad', 'Wadlopers', 'Ravi · S3 tot 5 · HD', '3 d', 1, 1], ['tears', 'Tears of Steel', 'Ravi · film · 4K', '2 d', 1], ['dweebs', 'Dweebs', 'Noor · seizoen 2', '1 d', 1], ['eleph', 'Elephants Dream', 'Sanne · film', '5 u', 0], ['glas', 'Glasstad', 'Ravi · film', '2 u', 0]].slice(0, n).map(([k, t, s, a, on, sw]) => qr(sel(on), pp(k), t, s, a, { swipe: sw })).join('')}</div>`;
const cHead = (t, ...ic) => `<h1>${t}</h1>${icons(...ic)}`;
const tyk = ic => `<span class="tyk">${ic}</span>`;
const C = {
  list: () => screen({ r1: cHead('Aanvragen', I.search, I.filter), body: `${tiles3(0)}<div class="qbar"><b>Wacht op jou</b><span>oudste eerst</span>${btn('3 goedkeuren', 'pri', I.check)}</div>${CQ()}<div class="hint">${I.swipe}Veeg rechts om goed te keuren, links om af te wijzen</div><div class="fold">Onderweg<span class="n">3 ${I.chevd}</span></div><div class="fold">Afgehandeld deze week<span class="n">41 ${I.chevd}</span></div>` }),
  detail: () => screen({ r1: cHead('Aanvragen', I.search, I.filter), body: `${tiles3(0)}<div class="qbar"><b>Wacht op jou</b><span>oudste eerst</span>${btn('3 goedkeuren', 'pri', I.check)}</div>${CQ()}`, over: `<div class="scrim"></div><div class="csheet"><span class="grab"></span><div class="hd2">${pp('wad')}${tx('Wadlopers', 'Ravi · aangevraagd 3 dagen geleden')}</div>
<div class="kv"><div>Seizoenen<b>3, 4 en 5</b></div><div>Grootte<b>±42 GB</b></div><div>Kwaliteit<b>HD · WEB-1080p</b></div><div>Server<b>Sonarr · /series</b></div><div class="am">Limiet Ravi<b>9 van 10 gebruikt</b></div><div>Al in Pleya<b>Seizoen 1</b></div></div>
<div class="brow2 two">${btn('Afwijzen', '', I.close)}${btn('Goedkeuren', 'pri', I.check)}</div><div class="lnk">Seizoenen of kwaliteit aanpassen</div></div>` }),
  issue: () => screen({ r1: cHead('Meldingen', I.search, I.filter), body: `${tiles3(1)}<div class="qbar"><b>Open</b><span>oudste eerst</span></div><div class="q">
${qr(udot(1), tyk(I.audio), 'Nachttrein · Geluid', 'Ravi · S1 A3 · vanaf 12:04', '2 d', { noBtns: 1, top: 1, extra: `<div class="qreply"><span>Ik kijk ernaar</span><span>Nieuwe versie gevraagd</span><span>Opgelost</span></div>` })}
${qr(udot(1), tyk(I.cc), 'Caminandes · Ondertiteling', 'Sanne · S2 A1 · geen NL', '1 d', { noBtns: 1, top: 1 })}${qr(udot(0), tyk(I.cc), 'Kustlijn · Ondertiteling', 'Noor · S3 A2 · loopt niet gelijk', '5 d', { noBtns: 1, top: 1 })}${qr(udot(0), tyk(I.image), 'Tears of Steel · Beeld', 'Sanne · haperen na 40 min', '6 d', { noBtns: 1, top: 1 })}${qr(udot(0), tyk(I.audio), 'Onderstroom · Geluid', 'Ravi · S4 · valt weg', '8 d', { noBtns: 1, top: 1 })}</div><div class="fold">Opgelost<span class="n">41 ${I.chevd}</span></div>` }),
  noti: () => screen({ r1: cHead('Notificaties', I.gear), body: `<div class="dig"><div class="h"><b>Samenvatting van vandaag</b><span>elke dag om 20:00</span></div><div class="nums"><div><b>4</b>nieuwe aanvragen</div><div><b>2</b>meldingen</div><div><b>3</b>klaar</div></div></div>
<div class="qbar"><b>Per onderwerp</b></div><div class="q">${[['Mijn aanvragen', 'goedgekeurd, klaar, afgewezen', 1], ['Mijn meldingen', 'reacties en opgelost', 0], ['Nieuwe aanvragen', 'alleen beheerder', 1], ['Nieuwe meldingen', 'alleen beheerder', 1], ['Nieuwe afleveringen', 'van series die je kijkt', 2]].map(([l, s, v]) => `<div class="pr"><div class="l">${l}<small>${s}</small></div><div class="seg3">${['Direct', 'Samenvatting', 'Uit'].map((o, i) => `<span class="${i === v ? 'on' : ''}">${o}</span>`).join('')}</div></div>`).join('')}</div>` }),
  tv: () => `${topnav('Mijn Pleya')}<div class="tpg"><div class="ttl">Beheer</div><div class="tiles4">${[['am on', 27, 'aanvragen wachten'], ['', 6, 'meldingen open'], ['', 3, 'onderweg'], ['red', 2, 'mislukt']].map(([c, n, l]) => `<div class="ctile ${c}"><b>${n}</b><span>${l}</span></div>`).join('')}</div>
<div class="qh">Wacht op jou, oudste eerst</div><div class="q">${[['wad', 'Wadlopers', 'Ravi · seizoen 3 tot 5 · HD · limiet 9 van 10', '3 d', 1], ['tears', 'Tears of Steel', 'Ravi · film · 4K', '2 d'], ['dweebs', 'Dweebs', 'Noor · seizoen 2', '1 d'], ['eleph', 'Elephants Dream', 'Sanne · film', '5 u']].map(([k, t, s, a, f]) => qr('', pp(k), t, s, a, { focus: f, fy: f })).join('')}</div></div>`,
};

// ======================= render =======================
const DIR = [
  { k: 'A', name: 'Affiche', d: A, col: 80 },
  { k: 'B', name: 'Tijdlijn', d: B, col: 74 },
  { k: 'C', name: 'Regiekamer', d: C, col: 100 },
];
const SCR = [['list', 'Aanvragenlijst'], ['detail', 'Aanvraag openen'], ['issue', 'Melding'], ['noti', 'Notificaties']];
const pages = [];
const lab = (code, name, w) => `<div class="lab" style="height:40px;width:${w}px"><b>${code}</b><span>${name}</span></div>`;
const panel = (dir, s) => `<div class="pn">${lab(`${dir.k}${SCR.findIndex(x => x[0] === s) + 1}`, `${dir.name} · ${SCR.find(x => x[0] === s)[1]}`, 402)}<div class="vp ph ${dir.k}" data-dir="${dir.k}" data-col="${dir.col}" data-screen="${s}" style="width:402px;height:874px;--colx:${dir.col}px">${dir.d[s]()}</div></div>`;
for (const dir of DIR) {
  pages.push({ name: `richting-${dir.k}-${dir.name.toLowerCase()}-telefoon`, w: 4 * 402 + 3 * 24 + 48, h: 874 + 40 + 48, dsf: 2, html: `<div style="display:flex;gap:24px;padding:24px">${SCR.map(([s]) => panel(dir, s)).join('')}</div>` });
  pages.push({ name: `richting-${dir.k}-${dir.name.toLowerCase()}-tv`, w: 1920, h: 1080 + 56, dsf: 1, tv: 1, html: `<div class="pn"><div class="lab" style="height:56px;width:1920px"><b>${dir.k}5</b><span>${dir.name} · Apple TV</span></div><div class="vp tv ${dir.k} tvw">${dir.d.tv()}</div></div>` });
}
pages.push({ name: 'vergelijking-aanvragenlijst', w: 3 * 402 + 2 * 24 + 48, h: 874 + 40 + 48, dsf: 2, html: `<div style="display:flex;gap:24px;padding:24px">${DIR.map(d => panel(d, 'list')).join('')}</div>` });

const problems = [];
const txt = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, ' ');
for (const p of pages) if (/—/.test(txt(p.html))) problems.push(`${p.name}: emdash`);
mkdirSync(OUT, { recursive: true });
const pw = process.env.PLEYA_MOCKUP_PLAYWRIGHT ?? ['/opt/node-tools/node_modules/playwright/index.mjs', '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs'].find(existsSync);
const { chromium } = await import(pw);
const browser = await chromium.launch();
const headY = {};
for (const dsf of [1, 2]) {
  const ctx = await browser.newContext({ deviceScaleFactor: dsf, colorScheme: 'dark' }); const page = await ctx.newPage();
  for (const pg of pages.filter(p => p.dsf === dsf)) {
    const f = join(OUT, pg.name + '.html');
    writeFileSync(f, `<!doctype html><html lang="nl"><head><meta charset="utf-8"><link rel="stylesheet" href="${TVSRC}/tv.css"><link rel="stylesheet" href="${RQCSS}"><link rel="stylesheet" href="../rr.css"></head><body class="${GRID ? 'gridon' : ''}">${pg.html}</body></html>`);
    await page.setViewportSize({ width: pg.w, height: pg.h });
    await page.goto('file://' + f, { waitUntil: 'networkidle' }); await page.evaluate(() => document.fonts.ready);
    if (await page.evaluate(() => [...document.images].some(i => !i.naturalWidth))) problems.push(`${pg.name}: kapotte afbeelding`);
    const res = await page.evaluate(() => {
      const out = [], heads = [], r = e => e.getBoundingClientRect(), R = Math.round;
      for (const vp of document.querySelectorAll('.vp')) {
        const v = r(vp), code = vp.parentElement.querySelector('.lab b').textContent, P = m => out.push(`${code} ${m}`);
        const isTv = vp.classList.contains('tv');
        // 3. Niets buiten het scherm, behalve wat in een schuivende inhoud of een kijkje (.peek) zit.
        for (const e of vp.querySelectorAll('.tx, .b, .sh, .gh, .qbar, .fold, .hint, .tiles3, .facts, .ft, .ncard, .still, .tsh, .ttl')) {
          if (e.closest('.peek')) continue;
          const b = r(e); if (b.right > v.right + .5 || b.left < v.left - .5) P(`"${e.textContent.trim().slice(0, 30)}" buiten de zijkant`);
          if (isTv && b.bottom > v.bottom + .5) P(`"${e.textContent.trim().slice(0, 30)}" onder de rand`);
        }
        if (isTv) continue;
        const hd = vp.querySelector('.hd .r1'); heads.push([vp.dataset.dir, code, R(r(hd).top - v.top)]);
        const tb = vp.querySelector('.tabbar'), floor = r(tb).top;
        // 3b. Een sectiekop staat helemaal boven de tabbalk.
        for (const e of vp.querySelectorAll('.sh, .gh, .qbar')) { const b = r(e); if (b.top < floor && b.bottom > floor - 8) P(`kop "${e.textContent.trim().slice(0, 24)}" half onder de tabbalk`); if (b.top >= floor) P(`kop "${e.textContent.trim().slice(0, 24)}" onder de tabbalk`); }
        // 2. Tekstkolom: elk tekstblok in een rij begint op de kolom van de richting.
        const col = +vp.dataset.col;
        for (const e of vp.querySelectorAll('.tr > .tx, .st > .tx, .act > .tx, .nrow > .tx, .ncard > .tx, .qr > .tx, .bcard > .tx')) { if (e.closest('.csheet')) continue; const x = R(r(e).left - v.left); if (r(e).top > floor) continue; if (Math.abs(x - col) > 1) P(`tekstkolom op ${x} in plaats van ${col}: "${e.textContent.trim().slice(0, 24)}"`); }
        // 4. Geen dode zone: het laatste blok van de inhoud staat niet meer dan 120 px boven de voet of tabbalk.
        const bd = vp.querySelector('.bd'); if (bd && !bd.classList.contains('end') && !vp.querySelector('.csheet')) { const kids = [...bd.children]; const last = Math.max(...kids.map(k => r(k).bottom)); const gap = r(bd).bottom - last; if (gap > 120) P(`dode zone van ${R(gap)} px onder de inhoud`); }
        // 6. Elk blok in de inhoud loopt over de volle breedte tussen de kantlijnen.
        if (bd) { const bb = r(bd), w = bb.width - 2 * 16; for (const k of bd.children) { const kw = r(k).width; if (k.classList.contains('rail') || k.closest('.A') && k.classList.contains('blk') && k.querySelector('.rail')) { if (kw < w - 1) P('blok smaller dan de inhoud'); continue; } if (Math.abs(kw - w) > 1 && !k.classList.contains('gh')) P(`blok ${k.className} is ${R(kw)} breed in plaats van ${R(w)}`); } }
        // 5. Knoppen in een rij zijn even hoog.
        for (const row of vp.querySelectorAll('.brow2, .ft')) { const hs = [...row.querySelectorAll(':scope > .b')].map(b => R(r(b).height)); if (new Set(hs).size > 1) P(`knoppen in een rij niet even hoog: ${hs.join('/')}`); }
      }
      return { out, heads };
    });
    problems.push(...res.out.map(m => `${pg.name}: ${m}`));
    for (const [d, code, y] of res.heads) (headY[d] ??= []).push([code, y]);
    await page.screenshot({ path: GRID ? join(OUT, pg.name + '-grid.jpg') : join(SET, pg.name + '.jpg'), type: 'jpeg', quality: 88 });
    console.log('shot', pg.name);
  }
  await ctx.close();
}
await browser.close();
// 1. De kop staat in alle schermen van een richting op dezelfde hoogte.
for (const [d, arr] of Object.entries(headY)) { const ys = new Set(arr.map(a => a[1])); if (ys.size > 1) problems.push(`richting ${d}: koppen op verschillende hoogte ${arr.map(a => a.join('=')).join(', ')}`); }
console.log(problems.length ? 'PROBLEMEN:\n' + [...new Set(problems)].join('\n') : `${pages.length} beelden, zelfcontrole schoon`);
process.exit(problems.length ? 1 : 0);
