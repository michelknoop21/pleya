// Drie ontwerprichtingen voor Aanvragen, meldingen en notificaties (keuzeronde, A-20).
// A Affiche: posters voorop, zoals Home. B Tijdlijn: elke aanvraag als zending met stappen.
// C Regiekamer: compact en beheer eerst. Per richting vier telefoonschermen en een TV-scherm.
// Gebruik: node gen.mjs   (Playwright via PLEYA_MOCKUP_PLAYWRIGHT of /opt/node-tools)
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('.', import.meta.url).pathname, SET = join(ROOT, '..'), OUT = join(ROOT, 'out');
const TVSRC = '../../../tvos-unified/src', RQCSS = '../../../requests-2.0/src/rq.css', ART = '../../../ios-unified/detail-2026';
const sv = (d, x = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${x}>${d}</svg>`;
const I = {
  back: sv('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'), search: sv('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'),
  check: sv('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.6"'), close: sv('<path d="m6 6 12 12M18 6 6 18"/>', 'stroke-width="2.4"'),
  chevd: sv('<path d="m6 9 6 6 6-6"/>'), chev: sv('<path d="m9 6 6 6-6 6"/>'), more: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  play: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>', edit: sv('<path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4"/>'),
  info: sv('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'), bell: sv('<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>'),
  flag: sv('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'), filter: sv('<path d="M4 6h16M7 12h10M10 18h4"/>'), dl: sv('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>'),
  clock: sv('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'), plus: sv('<path d="M12 5v14M5 12h14"/>'), send: sv('<path d="m4 12 16-8-6 16-2-6z"/>'),
  audio: sv('<path d="M4 10v4h4l5 4V6L8 10z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>'), cc: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M10.5 10.2a2.3 2.3 0 1 0 0 3.6M17 10.2a2.3 2.3 0 1 0 0 3.6"/>'),
  image: sv('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m21 16-5-5-8 8"/>'), chat: sv('<path d="M4 5h16v11H9l-5 4z"/>'),
  gear: sv('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>'),
  swipe: sv('<path d="M5 12h14M15 8l4 4-4 4"/>'), home: sv('<path d="M4 11 12 4l8 7v9h-5v-6H9v6H4z"/>'), show: sv('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>'),
  film: sv('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16"/>'), live: sv('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m7 3 5 3 5-3"/>'), person: sv('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  sparkle: sv('<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>'),
};
const IT = {
  charge: { t: 'Charge', y: 2022, img: 'charge-poster' }, sintel: { t: 'Sintel', y: 2010, img: 'sintel-poster', wide: 'sintel-wide' },
  tears: { t: 'Tears of Steel', y: 2012, img: 'tears-poster' }, spring: { t: 'Spring', y: 2019, img: 'spring-poster' },
  camin: { t: 'Caminandes', y: 2013, img: 'caminandes-poster', wide: 'bbb-wide' }, dweebs: { t: 'Dweebs', y: 2021, img: 'dweebs-poster' },
  eleph: { t: 'Elephants Dream', y: 2006, img: 'elephants-poster' }, coffee: { t: 'Coffee Run', y: 2020, img: 'coffeerun-poster' },
  wad: { t: 'Wadlopers', y: 2023, h: 196 }, glas: { t: 'Glasstad', y: 2024, h: 286 }, nacht: { t: 'Nachttrein', y: 2024, h: 250 }, kust: { t: 'Kustlijn', y: 2022, h: 172 },
};
const art = (k, wide) => { const it = IT[k]; return wide && it.wide ? `<img src="${ART}/${it.wide}.jpg" alt="">` : it.img ? `<img src="${ART}/${it.img}.jpg" alt="">` : `<div class="fx" style="--h:${it.h}"><b>${it.t}</b><i>FIXTURE</i></div>`; };
const btn = (l, k = '', ic = '') => `<span class="b ${k}">${ic}${l}</span>`;
const status = '<div class="status"><span>9:41</span><div class="island"></div><span></span></div>';
const tabbar = `<div class="tabbar"><div>${I.home}Home</div><div>${I.show}Series</div><div>${I.film}Films</div><div>${I.live}Live TV</div><div class="on">${I.person}Mijn Pleya</div></div><div class="homeind"></div>`;
const phone = (body, tb = true) => `${status}${body}${tb ? tabbar : '<div class="homeind"></div>'}`;
const topnav = a => `<nav class="topnav"><div class="chip">M</div><div class="cluster">${I.search.replace('class="ic"', 'class="ic search"')}${['Home', 'Series', 'Films', 'Live TV', 'Mijn Pleya'].map(n => `<div class="item${n === a ? ' on' : ''}">${n}</div>`).join('')}</div><div class="wordmark"><img src="${TVSRC}/assets/pleya_wordmark.png" alt="Pleya"></div></nav>`;

// ======================= A. AFFICHE =======================
const pc = (k, o = {}) => `<div class="pc${o.focus ? ' focus' : ''}">${art(k)}<div class="scr"></div>${o.who ? `<div class="who"><span class="av">${o.who}</span></div>` : ''}<div class="lb"><b>${IT[k].t}</b><span>${o.st ?? ''}</span></div>${o.p != null ? `<div class="pb"><i style="width:${o.p}%"></i></div>` : ''}</div>`;
const A = {
  list: () => phone(`<div class="top"><h1>Aanvragen<span class="sp">${I.search}${I.filter}</span></h1><div class="tabs"><span class="on">Alle</span><span>Van mij</span><span>Meldingen</span></div></div>
<div class="scroll"><div class="sh">Wacht op jou <small>27</small><span class="all">Alles</span></div>
<div class="pair"><div>${pc('wad', { who: 'R', st: '<i class="dot wait"></i>Seizoen 3 tot 5' })}<div class="dec">${btn('Goedkeuren', 'pri')}${btn('', 'icon', I.close)}</div></div><div>${pc('tears', { who: 'R', st: '<i class="dot wait"></i>Film · 4K' })}<div class="dec">${btn('Goedkeuren', 'pri')}${btn('', 'icon', I.close)}</div></div></div>
<div class="sh">Onderweg <small>3</small></div><div class="rail">${pc('charge', { st: '62% · ±20 min', p: 62 })}${pc('glas', { st: 'In de wachtrij', p: 4 })}${pc('kust', { st: 'Seizoen 3 · 18%', p: 18 })}${pc('coffee', { st: '91%', p: 91 })}</div>
<div class="sh">Klaar om te kijken <small>35</small></div><div class="rail">${pc('sintel', { st: '<i class="dot ok"></i>Films' })}${pc('spring', { st: '<i class="dot ok"></i>Films' })}${pc('nacht', { st: '<i class="dot ok"></i>Deels' })}${pc('camin', { st: '<i class="dot ok"></i>Series' })}</div></div>`),
  detail: () => phone(`<div class="hero">${art('camin', true)}</div><div class="glass" style="left:16px">${I.back}</div><div class="glass" style="right:16px">${I.more}</div>
<div class="dbody"><div class="meta"><i class="dot wait"></i>Wacht op jou · aangevraagd door Ravi, 6 okt</div><h1>Caminandes</h1><div class="meta">Serie · 2013 · Animatie · HD</div>
<div class="seas"><span><i class="dot ok"></i>S1 in Pleya</span><span><i class="dot wait"></i>S2 gevraagd</span><span><i class="dot wait"></i>S3 gevraagd</span></div>
${btn('Goedkeuren', 'pri bigb', I.check)}<div class="row2">${btn('Afwijzen', '', I.close)}${btn('Aanpassen', '', I.edit)}</div>
<div class="rnd"><div><span>${I.info}</span>Titel</div><div><span>${I.play}</span>Trailer</div><div><span>${I.chat}</span>Reageer</div><div><span>${I.person}</span>Ravi</div></div></div>`),
  issue: () => phone(`<div class="top"><h1>Aanvragen<span class="sp">${I.search}${I.filter}</span></h1><div class="tabs"><span>Alle</span><span>Van mij</span><span class="on">Meldingen</span></div></div>
<div class="list"><div class="still"><div class="img">${art('sintel', true)}<span class="tc">${I.play}12:04</span><span class="ty">${I.audio}Geluid</span></div><div class="tx"><b>Sintel · geluid loopt achter</b><span>Ravi · 8 nov · 2 reacties</span><q>Zie het ook. Ik heb een andere release aangevraagd.</q></div></div>
<div class="still"><div class="img">${art('camin', true)}<span class="tc">${I.play}S2 A1 · 03:40</span><span class="ty">${I.cc}Ondertiteling</span></div><div class="tx"><b>Caminandes · geen Nederlandse ondertitels</b><span>Sanne · 7 nov · nog geen reactie</span></div></div></div>`),
  noti: () => phone(`<div class="top"><h1>Voor jou<span class="sp">${I.gear}</span></h1><div class="tabs"><span class="on">Nieuw 3</span><span>Eerder</span></div></div>
<div class="list"><div class="ncard">${art('sintel', true)}<div class="in"><small>Je aanvraag staat klaar</small><b>Sintel</b><span style="font-size:13px;color:var(--ink-2)">Film · 2010 · 4K HDR</span>${btn('Afspelen', 'pri', I.play)}</div></div>
<div class="nrow"><div class="pp">${art('nacht')}</div><div class="bb"><b>Michel reageerde op je melding</b><span>Nachttrein S1 A3 · “Nieuwe versie staat erop.”</span></div><i class="ud"></i></div>
<div class="nrow"><div class="pp">${art('kust')}</div><div class="bb"><b>Nieuwe aflevering van Kustlijn</b><span>Seizoen 3, aflevering 4 · 08:15</span></div><i class="ud"></i></div>
<div class="nrow"><div class="pp">${art('wad')}</div><div class="bb"><b>Wadlopers seizoen 3 goedgekeurd</b><span>Downloaden begint zo · ma</span></div></div></div>`),
  tv: () => `${topnav('Mijn Pleya')}<div class="pg"><div class="head"><div class="page-title">Aanvragen</div></div><div style="height:30px"></div>
<div class="rl2">Wacht op jou <small>27</small></div><div class="rail">${pc('wad', { who: 'R', st: '<i class="dot wait"></i>S3 tot 5' })}${pc('tears', { who: 'R', st: '<i class="dot wait"></i>Film · 4K' })}${pc('dweebs', { who: 'N', st: '<i class="dot wait"></i>Seizoen 2' })}${pc('eleph', { who: 'S', st: '<i class="dot wait"></i>Film' })}${pc('glas', { who: 'R', st: '<i class="dot wait"></i>Film' })}${pc('kust', { who: 'N', st: '<i class="dot wait"></i>S4' })}${pc('spring', { who: 'S', st: '<i class="dot wait"></i>Film' })}</div>
<div class="tvdec">${btn('Goedkeuren', 'pri focus', I.check)}${btn('Afwijzen', '', I.close)}${btn('Openen', '', I.info)}</div>
<div class="rl2">Onderweg <small>3</small></div><div class="rail">${pc('charge', { st: '62% · ±20 min', p: 62 })}${pc('coffee', { st: '91%', p: 91 })}${pc('nacht', { st: 'S2 · 18%', p: 18 })}</div></div>`,
};

// ======================= B. TIJDLIJN =======================
const steps = (n, p, wait) => `<div class="steps">${[0, 1, 2, 3].map(i => `<i class="${i < n ? 'd' : i === n ? (wait ? 'w' : 'c') : ''}"${i === n && !wait ? ` style="--p:${p}%"` : ''}></i>`).join('')}</div>`;
const tr = (k, s, n, p, lab, right, o = {}) => `<div class="tr${o.focus ? ' focus' : ''}"><div class="pp">${art(k)}</div><div class="bb"><div class="t">${IT[k].t}<small>${o.when ?? ''}</small></div><div class="s">${s}</div>${steps(n, p, o.wait)}<div class="sl"><b>${lab}</b><span>${right}</span></div>${o.qa ? `<div class="qa">${btn('Goedkeuren', 'pri', I.check)}${btn('Afwijzen')}</div>` : ''}</div></div>`;
const stp = (cls, ic, t, s, extra = '') => `<div class="st ${cls}"><span class="k">${ic}</span><div><b>${t}</b><span>${s}</span>${extra}</div></div>`;
const B = {
  list: () => phone(`<div class="top"><div class="r1"><h1>Aanvragen</h1>${I.search}</div><div style="display:flex;gap:8px"><span class="dd">Alle aanvragen ${I.chevd}</span></div><div class="chips"><span class="on">Actief <span class="n">31</span></span><span>Klaar <span class="n">35</span></span><span>Afgewezen <span class="n">14</span></span></div></div>
<div class="scroll" style="top:200px"><div class="gh"><i class="dot wait"></i>Vraagt om jou</div>${tr('wad', 'Ravi · seizoen 3 tot 5', 0, 0, 'Wacht op goedkeuring', '6 okt', { wait: 1, qa: 1 })}
<div class="gh" style="margin-top:14px"><i class="dot run"></i>Onderweg</div>${tr('charge', 'Sanne · film · 4K', 2, 62, 'Downloaden 62%', 'nog ±20 min')}${tr('glas', 'Sanne · film', 1, 0, 'Goedgekeurd', 'in de wachtrij')}${tr('kust', 'Ravi · seizoen 3', 2, 18, 'Downloaden 18%', 'nog ±1 u')}</div>`),
  detail: () => phone(`<div class="dh">${I.back}<span style="flex:1"></span>${I.more}</div><div class="dcard"><div class="pp">${art('charge')}</div><div><h1>Charge</h1><div class="s">Film · 2022 · 4K · aangevraagd door Sanne</div><div class="eta">${I.clock}Waarschijnlijk klaar om 14:40</div></div></div>
<div class="tl">${stp('d', I.check, 'Aangevraagd', 'Sanne · 6 okt, 14:02')}${stp('d', I.check, 'Goedgekeurd', 'Michel · 6 okt, 14:10 · Radarr 4K')}${stp('c', I.dl, 'Downloaden · 62%', '8,4 van 13,6 GB · nog ongeveer 20 minuten', '<div class="pbar"><i></i></div>')}${stp('', I.play, 'Beschikbaar in Films', 'Je krijgt een notificatie als hij klaarstaat')}</div>
<div class="facts"><div>Kwaliteit<b>4K</b></div><div>Server<b>Radarr 4K</b></div><div>Limiet<b>3 van 5</b></div></div><div class="foot">${btn('Annuleren', 'ghost')}${btn('Status verversen', '', '')}</div>`),
  issue: () => phone(`<div class="dh">${I.back}<b style="font-size:18px;flex:1">Melding #128</b>${I.more}</div><div class="dcard" style="top:104px"><div class="pp" style="width:60px">${art('nacht')}</div><div><h1 style="font-size:21px">Nachttrein</h1><div class="s">S1 A3 · Geluid · vanaf 12:04</div></div></div>
<div class="tl" style="top:210px">${stp('d', I.flag, 'Gemeld door Ravi', '8 nov, 21:14', '<div class="bub">Vanaf ongeveer 12 minuten loopt het geluid een halve seconde achter.</div>')}${stp('d', I.chat, 'Michel reageerde', '8 nov, 22:02', '<div class="bub me">Ik heb een andere release aangevraagd.</div>')}${stp('d', I.dl, 'Nieuwe versie binnen', '9 nov, 11:30 · automatisch gezien door Pleya')}${stp('c', I.clock, 'Wacht op Ravi', 'Klopt het nu? Dan kan de melding dicht.')}</div>
<div class="compose"><div class="f">Schrijf een reactie</div>${btn('', 'pri', I.send)}</div>`),
  noti: () => phone(`<div class="top"><div class="r1"><h1>Activiteit</h1>${I.gear}</div><div class="chips"><span class="on">Alles</span><span>Aanvragen</span><span>Meldingen</span><span>Bibliotheek</span></div></div>
<div class="scroll" style="top:156px"><div class="gh">Vandaag</div>
<div class="act"><span class="ik ok">${I.check}</span><div class="bb"><b>Charge staat klaar in Films</b><span>Aanvraag · 14:40</span><div class="mini"><i class="d"></i><i class="d"></i><i class="d"></i><i class="d"></i></div></div><i class="ud"></i></div>
<div class="act"><span class="ik">${I.chat}</span><div class="bb"><b>Michel reageerde op je melding over Nachttrein</b><span>Melding · 11:40</span></div><i class="ud"></i></div>
<div class="act"><span class="ik am">${I.dl}</span><div class="bb"><b>Kustlijn seizoen 3 wordt gedownload</b><span>Aanvraag · 18% · 09:02</span><div class="mini"><i class="d"></i><i class="d"></i><i></i><i></i></div></div><i class="ud"></i></div>
<div class="gh" style="margin-top:12px">Deze week</div>
<div class="act"><span class="ik">${I.plus}</span><div class="bb"><b>Nieuwe aflevering van Dweebs</b><span>Bibliotheek · ma</span></div></div>
<div class="act"><span class="ik red">${I.close}</span><div class="bb"><b>Zoutland is afgewezen</b><span>Aanvraag · zo · “Staat al op Netflix”</span></div></div></div>`),
  tv: () => `${topnav('Mijn Pleya')}<div class="pg"><div class="head"><div class="page-title">Aanvragen</div></div></div><div class="two"><div class="lst">${tr('charge', 'Sanne · film · 4K', 2, 62, 'Downloaden 62%', 'nog ±20 min', { focus: 1 })}${tr('wad', 'Ravi · seizoen 3 tot 5', 0, 0, 'Wacht op goedkeuring', '6 okt', { wait: 1 })}${tr('glas', 'Sanne · film', 1, 0, 'Goedgekeurd', 'in de wachtrij')}${tr('kust', 'Ravi · seizoen 3', 2, 18, 'Downloaden 18%', 'nog ±1 u')}</div>
<div class="tlw"><h2>Charge</h2><div class="s0">Film · 2022 · 4K · aangevraagd door Sanne</div><div class="tl" style="position:static">${stp('d', I.check, 'Aangevraagd', 'Sanne · 6 okt, 14:02')}${stp('d', I.check, 'Goedgekeurd', 'Michel · 6 okt, 14:10')}${stp('c', I.dl, 'Downloaden · 62%', 'nog ongeveer 20 minuten', '<div class="pbar"><i></i></div>')}${stp('', I.play, 'Beschikbaar in Films', 'verwacht om 14:40')}</div><div class="tvb">${btn('Titel openen', '', I.info)}${btn('Annuleren', 'ghost')}</div></div></div>`,
};

// ======================= C. REGIEKAMER =======================
const pp = k => `<div class="pp">${art(k)}</div>`;
const qr = (k, t, s, age, o = {}) => `<div class="qr${o.swipe ? ' swipe' : ''}${o.focus ? ' focus' : ''}">${o.sel != null ? `<span class="sel${o.sel ? ' on' : ''}">${o.sel ? I.check : ''}</span>` : ''}${o.ik ?? pp(k)}<div class="bb"><div class="t">${t}</div><div class="s">${s}</div></div><span class="age">${age}</span>${o.noBtns ? '' : `<span class="rb">${I.close}</span><span class="rb y${o.fy ? ' focus' : ''}">${I.check}</span>`}</div>${o.after ?? ''}`;
const tiles = sel => `<div class="ctiles"><div class="ctile am${sel === 0 ? ' on' : ''}"><b>27</b><span>wachten op jou</span></div><div class="ctile${sel === 1 ? ' on' : ''}"><b>6</b><span>meldingen open</span></div><div class="ctile red${sel === 2 ? ' on' : ''}"><b>2</b><span>mislukt</span></div></div>`;
const CQ = () => `<div class="q">${qr('wad', 'Wadlopers', 'Ravi · S3 tot 5 · HD', '3 d', { sel: 1, swipe: 1 })}${qr('tears', 'Tears of Steel', 'Ravi · film · 4K', '2 d', { sel: 1 })}${qr('dweebs', 'Dweebs', 'Noor · seizoen 2', '1 d', { sel: 1 })}${qr('eleph', 'Elephants Dream', 'Sanne · film', '5 u', { sel: 0 })}${qr('glas', 'Glasstad', 'Ravi · film', '2 u', { sel: 0 })}</div>`;
const C = {
  list: () => phone(`<div class="top"><h1>Aanvragen</h1>${I.search}${I.filter}</div>${tiles(0)}
<div class="scroll"><div class="qbar"><b>Wacht op jou</b><span>oudste eerst</span><span class="rt">${btn('3 goedkeuren', 'pri', I.check)}</span></div>${CQ()}<div class="hint">${I.swipe}Veeg naar rechts om goed te keuren, naar links om af te wijzen</div><div class="fold">Onderweg <span style="color:var(--ink-3)">3 ${I.chevd}</span></div><div class="fold">Afgehandeld deze week <span style="color:var(--ink-3)">41 ${I.chevd}</span></div></div>`),
  detail: () => phone(`<div class="top"><h1>Aanvragen</h1>${I.search}${I.filter}</div>${tiles(0)}<div class="scroll"><div class="qbar"><b>Wacht op jou</b></div>${CQ()}</div><div class="scrim"></div>
<div class="csheet"><div class="hd">${pp('wad')}<div><b>Wadlopers</b><span>Ravi · aangevraagd 3 dagen geleden</span></div></div>
<div class="kv"><div>Seizoenen<b>3, 4 en 5</b></div><div>Grootte<b>±42 GB</b></div><div>Kwaliteit<b>HD · WEB-1080p</b></div><div>Server<b>Sonarr · /media/series</b></div><div class="am">Limiet Ravi<b>9 van 10 gebruikt</b></div><div>Al in Pleya<b>Seizoen 1</b></div></div>
<div class="two">${btn('Afwijzen', '', I.close)}${btn('Goedkeuren', 'pri', I.check)}</div><div class="lnk">Seizoenen of kwaliteit aanpassen</div></div>`, false),
  issue: () => phone(`<div class="top"><h1>Meldingen</h1>${I.search}${I.filter}</div>${tiles(1)}
<div class="scroll"><div class="qbar"><b>Open</b><span>oudste eerst</span></div><div class="q">${qr('nacht', 'Nachttrein · Geluid', 'Ravi · S1 A3 · vanaf 12:04', '2 d', { noBtns: 1, ik: `<span class="rb">${I.audio}</span>`, after: `<div class="qreply"><span>Ik kijk ernaar</span><span>Nieuwe versie aangevraagd</span><span>Opgelost, probeer opnieuw</span><span>Reageren…</span></div>` })}${qr('camin', 'Caminandes · Ondertiteling', 'Sanne · S2 A1 · geen NL', '1 d', { noBtns: 1, ik: `<span class="rb">${I.cc}</span>` })}${qr('kust', 'Kustlijn · Ondertiteling', 'Noor · S3 A2 · loopt niet gelijk', '5 d', { noBtns: 1, ik: `<span class="rb">${I.cc}</span>` })}${qr('tears', 'Tears of Steel · Beeld', 'Sanne · haperen na 40 min', '6 d', { noBtns: 1, ik: `<span class="rb">${I.image}</span>` })}</div><div class="fold">Opgelost <span style="color:var(--ink-3)">41 ${I.chevd}</span></div></div>`),
  noti: () => phone(`<div class="top"><h1>Notificaties</h1>${I.gear}</div><div class="scroll" style="top:110px">
<div class="dig"><div class="h"><b>Samenvatting van vandaag</b><span>elke dag om 20:00</span></div><div class="nums"><div><b>4</b>nieuwe aanvragen</div><div><b>2</b>meldingen</div><div><b>3</b>klaar</div></div></div>
<div class="qbar" style="margin-top:6px"><b>Per onderwerp</b></div><div class="q">${[['Mijn aanvragen', 'goedgekeurd, klaar, afgewezen', 1], ['Mijn meldingen', 'reacties en opgelost', 0], ['Nieuwe aanvragen', 'alleen beheerder', 1], ['Nieuwe meldingen', 'alleen beheerder', 1], ['Nieuwe afleveringen', 'van series die je kijkt', 2]].map(([l, s, v]) => `<div class="pr"><div class="l">${l}<small>${s}</small></div><div class="seg3">${['Direct', 'Samenvatting', 'Uit'].map((o, i) => `<span class="${i === v ? 'on' : ''}">${o}</span>`).join('')}</div></div>`).join('')}</div></div>`),
  tv: () => `${topnav('Mijn Pleya')}<div class="pg"><div class="head"><div class="page-title">Beheer</div></div><div class="ctiles"><div class="ctile am focus"><b>27</b><span>aanvragen wachten</span></div><div class="ctile"><b>6</b><span>meldingen open</span></div><div class="ctile"><b>3</b><span>onderweg</span></div><div class="ctile red"><b>2</b><span>mislukt</span></div></div>
<div class="qh">Wacht op jou, oudste eerst</div><div class="q">${qr('wad', 'Wadlopers', 'Ravi · seizoen 3 tot 5 · HD · limiet 9 van 10', '3 d', { focus: 1, fy: 1 })}${qr('tears', 'Tears of Steel', 'Ravi · film · 4K', '2 d')}${qr('dweebs', 'Dweebs', 'Noor · seizoen 2', '1 d')}${qr('eleph', 'Elephants Dream', 'Sanne · film', '5 u')}</div></div>`,
};

// ======================= render =======================
const DIR = [
  { k: 'A', name: 'Affiche', d: A, why: 'Posters voorop, zoals Home: de status zit op de poster, download als rode voortgangslijn' },
  { k: 'B', name: 'Tijdlijn', d: B, why: 'Elke aanvraag als zending met vier stappen; meldingen en notificaties in één Activiteit' },
  { k: 'C', name: 'Regiekamer', d: C, why: 'Compact en beheer eerst: tellers, een wachtrij, vegen, snelle antwoorden en een dagelijkse samenvatting' },
];
const SCR = [['list', 'Aanvragenlijst'], ['detail', 'Aanvraag openen'], ['issue', 'Melding'], ['noti', 'Notificaties']];
const pages = [];
const lab = (code, name, w) => `<div class="lab" style="height:40px;width:${w}px"><b>${code}</b><span>${name}</span></div>`;
const panel = (dir, s) => `<div class="pn">${lab(`${dir.k}${SCR.findIndex(x => x[0] === s) + 1}`, `${dir.name} · ${SCR.find(x => x[0] === s)[1]}`, 402)}<div class="vp ph ${dir.k}" style="width:402px;height:874px">${dir.d[s]()}</div></div>`;
for (const dir of DIR) {
  pages.push({ name: `richting-${dir.k}-${dir.name.toLowerCase()}-telefoon`, w: 4 * 402 + 3 * 24 + 48, h: 874 + 40 + 48, dsf: 2, html: `<div style="display:flex;gap:24px;padding:24px">${SCR.map(([s]) => panel(dir, s)).join('')}</div>` });
  pages.push({ name: `richting-${dir.k}-${dir.name.toLowerCase()}-tv`, w: 1920, h: 1080 + 56, dsf: 1, html: `<div class="pn"><div class="lab" style="height:56px;width:1920px"><b>${dir.k}5</b><span>${dir.name} · Apple TV</span></div><div class="vp tv ${dir.k} tvw">${dir.d.tv()}</div></div>` });
}
pages.push({ name: 'vergelijking-aanvragenlijst', w: 3 * 402 + 2 * 24 + 48, h: 874 + 40 + 48, dsf: 2, html: `<div style="display:flex;gap:24px;padding:24px">${DIR.map(d => panel(d, 'list')).join('')}</div>` });

const txt = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, ' ');
const problems = [];
for (const p of pages) if (/—/.test(txt(p.html))) problems.push(`${p.name}: emdash`);
mkdirSync(OUT, { recursive: true });
const pw = process.env.PLEYA_MOCKUP_PLAYWRIGHT ?? ['/opt/node-tools/node_modules/playwright/index.mjs', '/opt/homebrew/lib/node_modules/@playwright/test/node_modules/playwright/index.mjs'].find(existsSync);
const { chromium } = await import(pw);
const browser = await chromium.launch();
for (const dsf of [1, 2]) {
  const ctx = await browser.newContext({ deviceScaleFactor: dsf, colorScheme: 'dark' }); const page = await ctx.newPage();
  for (const pg of pages.filter(p => p.dsf === dsf)) {
    const f = join(OUT, pg.name + '.html');
    writeFileSync(f, `<!doctype html><html lang="nl"><head><meta charset="utf-8"><link rel="stylesheet" href="${TVSRC}/tv.css"><link rel="stylesheet" href="${RQCSS}"><link rel="stylesheet" href="../rr.css"></head><body>${pg.html}</body></html>`);
    await page.setViewportSize({ width: pg.w, height: pg.h });
    await page.goto('file://' + f, { waitUntil: 'networkidle' }); await page.evaluate(() => document.fonts.ready);
    const bad = await page.evaluate(() => [...document.images].filter(i => !i.naturalWidth).map(i => i.src));
    if (bad.length) problems.push(`${pg.name}: kapotte afbeelding`);
    for (const m of await page.evaluate(() => { const o = []; for (const e of document.querySelectorAll('.vp .t, .vp b, .vp .s, .vp span')) if (e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflow === 'hidden' && getComputedStyle(e).textOverflow !== 'ellipsis') o.push(e.textContent.trim().slice(0, 40)); return o; })) problems.push(`${pg.name}: afgekapt "${m}"`);
    await page.screenshot({ path: join(SET, pg.name + '.jpg'), type: 'jpeg', quality: 88 });
    console.log('shot', pg.name);
  }
  await ctx.close();
}
await browser.close();
console.log(problems.length ? 'PROBLEMEN:\n' + problems.join('\n') : `${pages.length} beelden, zelfcontrole schoon`);
writeFileSync(join(SET, 'richtingen.json'), JSON.stringify(DIR.map(d => ({ k: d.k, name: d.name, why: d.why })), null, 1));
