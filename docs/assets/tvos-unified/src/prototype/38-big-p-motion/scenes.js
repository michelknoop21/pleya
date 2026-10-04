// Scenario's van het motion-prototype. Alle serverdata is nagebootst; alleen Big P zelf (bigp.js) is echt laagwerk.
const $ = (s) => document.querySelector(s);
const SVG = (d, extra = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
const IC = {
  mic: SVG('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'),
  close: SVG('<path d="m6 6 12 12M18 6 6 18"/>', 'stroke-width="2.8"'),
  check: SVG('<path d="m5 12 5 5 9-10"/>', 'stroke-width="2.8"'),
  info: SVG('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
  lock: SVG('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  back: SVG('<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>'),
  eye: SVG('<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  pleya: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M6 3h8a5 5 0 0 1 0 10h-4v8H6zm4 3v4h4a2 2 0 0 0 0-4z"/></svg>',
};

// ---------- tijd: pauzeerbaar, afbreekbaar ----------
const CANCEL = Symbol('cancel');
let gen = 0, paused = false, sceneIx = 0;
const tickers = new Set(); // lopende tellers (voortgang, statusstrook); dt in seconden
let clockLast = performance.now();
(function clock(now) {
  const dt = Math.min(0.05, (now - clockLast) / 1000);
  clockLast = now;
  if (!paused) tickers.forEach((f) => f(dt));
  requestAnimationFrame(clock);
})(clockLast);

function sleep(ms) {
  const g = gen;
  return new Promise((res, rej) => {
    let left = ms;
    const f = (dt) => {
      if (g !== gen) { tickers.delete(f); rej(CANCEL); return; }
      left -= dt * 1000;
      if (left <= 0) { tickers.delete(f); res(); }
    };
    tickers.add(f);
  });
}
// Stilstaand moment voor de stills: ?still=N pauzeert hier.
const params = new URLSearchParams(location.search);
const stillMode = params.has('still');
async function key(name, hold) {
  if (!stillMode || params.get('still') !== name) return;
  hold?.(); // houdt een houding of mond vast voor de still
  setPaused(true);
  // Big P eerst laten bijkomen (veren, houdingwissel), dan bevriezen; de opname wacht op data-key
  // (nooit midden in een knipper bevriezen)
  setTimeout(function freeze() {
    if (all.some((b) => b.blinkT >= 0)) { setTimeout(freeze, 30); return; }
    motion.paused = true; document.body.dataset.key = name;
  }, 900);
  await new Promise(() => {});
}

// ---------- dom-hulp ----------
const avatar = new BigP($('#fig'));
const floater = new BigP($('#ffig'), { facing: -1 }); // opgeroepen: het paneel staat links van hem
let actor = avatar; // de Big P die op dit moment werkt
const tv = $('#tv');

function focus(el) {
  tv.querySelectorAll('.focus').forEach((e) => e.classList.remove('focus'));
  el?.classList.add('focus');
}
async function press(el) {
  focus(el);
  el.classList.add('press');
  await sleep(140);
  el.classList.remove('press');
  await sleep(120);
}
async function swap(el, html) {
  el.classList.add('out');
  await sleep(260);
  el.innerHTML = html;
  el.classList.remove('out');
}
function nav(active) {
  tv.querySelectorAll('.topnav .item').forEach((i) => i.classList.toggle('on', i.dataset.nav === active));
}
function screen(id) {
  // Big P is een laag: het Pleya-scherm blijft eronder zichtbaar, vervaagd en gedimd
  $('#bigp-screen').classList.toggle('hide', id !== '#bigp-screen');
  $('#films-screen').classList.toggle('backdrop', id === '#bigp-screen');
  nav(id === '#films-screen' ? 'Films' : 'Mijn Pleya');
}
const stag = (i) => `style="--d:${i * 90}ms"`;

// ---------- live statusstrook (Mijn Pleya ▸ Big P) ----------
const ctx = { zolder: 'ok', jobs: [{ name: 'Ondertitels zoeken', where: 'Woonkamer', pct: 41 }] };
function drawCtx() {
  const z = ctx.zolder === 'off';
  const job = ctx.jobs[0];
  $('#ctx').innerHTML =
    `<span><i class="dot ${z ? 'off' : ''}"></i>Zolder${z ? ' <span class="red">offline</span>' : ''}</span>` +
    `<span><i class="dot"></i>Woonkamer</span><span><i class="dot"></i>G-Plexflix</span><i class="sep"></i>` +
    `<span class="jobs">${ctx.jobs.length === 1 ? '1 taak' : ctx.jobs.length + ' taken'} bezig · ${job.name}, ${job.where} ${Math.floor(job.pct)}%</span>`;
}
tickers.add((dt) => {
  ctx.jobs.forEach((j) => { j.pct = j.pct >= 99 ? 12 : j.pct + dt * 0.9; });
  if (!$('#bigp-screen').classList.contains('hide')) drawCtx();
});

// ---------- Films-catalogus (mock, open films van Blender) ----------
const FILMS = [
  ['Sintel', '2010 · 15 min', '#3b2a1f,#a0522d'], ['Tears of Steel', '2012 · 12 min', '#1d2b3a,#4f7a96'],
  ['Spring', '2019 · 8 min', '#203a26,#7fb069'], ['Cosmos Laundromat', '2015 · 12 min', '#2b1d3a,#b07ad0'],
  ['Agent 327', '2017 · 4 min', '#3a1d1d,#d0503a'], ['Sprite Fright', '2021 · 10 min', '#1d3a36,#5fb8a8'],
  ['Big Buck Bunny', '2008 · 10 min', '#2d3a1d,#b0c060'], ['Elephants Dream', '2006 · 11 min', '#3a321d,#c0a050'],
  ['Caminandes', '2013 · 3 min', '#1d263a,#6080c0'], ['Charge', '2022 · 4 min', '#3a1d2b,#c05080'],
  ['Coffee Run', '2020 · 3 min', '#2a2018,#a07850'], ['Wing It!', '2023 · 4 min', '#18282a,#50a0a8'],
];
$('#grid').innerHTML = FILMS.map(([t, s, g]) =>
  `<div class="card"><div class="art" style="background:linear-gradient(160deg,${g.split(',')[1]},${g.split(',')[0]} 70%)"><span class="src">Zolder</span><b>${t}</b></div><div class="t">${t}</div><div class="s">${s}</div></div>`).join('');

// ---------- toetsenbord ----------
$('#keys').innerHTML = 'abcdefghijklmnopqrstuvwxyz'.split('').map((k) => `<span class="k">${k}</span>`).join('');
$('#kbctl').innerHTML = `<span class="c">abc</span><span class="c">123</span><span class="c">spatie</span><span class="c">${IC.back} wis</span><span class="c dict">${IC.mic} Dicteren</span><span class="c done">Gereed</span>`;
function kbFocus(sel) { $('#kbctl').querySelectorAll('.c').forEach((c) => c.classList.toggle('on', c.matches(sel))); }

async function dictate(text, who) {
  const typed = $('#typed');
  typed.innerHTML = '';
  $('#kblive').innerHTML = `${IC.mic} Dicteren`;
  kbFocus('.dict');
  for (const word of text.split(' ')) {
    const w = document.createElement('span');
    w.className = 'w';
    w.textContent = (typed.childNodes.length ? ' ' : '') + word;
    typed.appendChild(w);
    const end = /[,.?]$/.test(word);
    // knikje bij elk binnenkomend woord, een duidelijke knik aan het eind van een zinsdeel
    who.nod(end ? 0.9 : 0.3, end ? 560 : 300);
    await sleep(end ? 520 : 240 + Math.random() * 140);
  }
}
async function kbDone() {
  kbFocus('.done');
  await sleep(380);
  const d = $('#kbctl .done');
  d.style.transform = 'scale(.95)';
  await sleep(140);
  d.style.transform = '';
  $('#kb').classList.remove('up');
  $('#bigp-screen').classList.remove('kbup');
}

// Big P zegt een tekst: woord voor woord zichtbaar, mond en lijf in het ritme van de lettergrepen,
// mond dicht tussen zinnen. De tekst staat vooraf al in de layout (onzichtbaar), dus niets verspringt.
async function talk(el, who, calm = false) {
  if (!el) return;
  const words = el.textContent.trim().split(/\s+/);
  el.innerHTML = words.map((w) => `<span class="tw">${w}</span>`).join(' ');
  const spans = el.querySelectorAll('.tw');
  for (let i = 0; i < words.length; i++) {
    spans[i].classList.add('on');
    await sleep(who.speak(words[i], calm));
    if (/[.?!:]$/.test(words[i])) { who.hush(); await sleep(calm ? 460 : 360); } else if (/,$/.test(words[i])) await sleep(160);
  }
  who.hush();
}

// ---------- stappenlijst ----------
async function step(list, text, ms, result, kind = 'ok', metaClass = '') {
  const row = document.createElement('div');
  row.className = 'step in';
  row.innerHTML = `<span class="mark">${kind === 'fail' ? IC.close : IC.check}</span><span class="t">${text}</span><span class="m"></span>`;
  list.appendChild(row);
  actor.follow(row); // wijst de nieuwe stap aan, hoofd draait mee
  await sleep(ms);
  row.querySelector('.mark').classList.add(kind);
  if (kind === 'ok') actor.stepDone(); // vinger omhoog: deze is klaar
  const m = row.querySelector('.m');
  m.innerHTML = result;
  if (metaClass) m.classList.add(metaClass);
  await sleep(260);
}
async function status(text) {
  const h = $('#col .h');
  h.classList.add('swap', 'out');
  await sleep(220);
  h.textContent = text;
  h.classList.remove('out');
}

// ---------- pleya-kaart en bevestiging ----------
const line = (ok, t, s, bar) => `<div class="line"><span class="mark ${ok ? 'ok' : 'fail'}">${ok ? IC.check : IC.close}</span><div><div class="t">${t}</div><div class="s">${s}</div>${bar ? `<div class="bar"><i id="${bar}"></i></div>` : ''}</div></div>`;
const pcard = (hd, lines, i = 2) => `<div class="pcard in" ${stag(i)}><div class="hd">${IC.pleya} ${hd}</div>${lines.join('')}</div>`;
function progress(barId, labelSel, from, rate, fmt) {
  let p = from;
  tickers.add(function f(dt) {
    const bar = document.getElementById(barId);
    if (!bar) { tickers.delete(f); return; }
    p = Math.min(100, p + dt * rate);
    bar.style.width = p + '%';
    const lab = document.querySelector(labelSel);
    if (lab) lab.textContent = fmt(Math.floor(p));
  });
}
function modal(html) { $('#modal').innerHTML = html; }
const kv = (k, v) => `<div class="kv"><span class="k">${k}</span><span class="v">${v}</span></div>`;

// ---------- reset per scene ----------
function reset() {
  ['#kb', '#dim', '#scrim', '#modal', '#float'].forEach((s) => $(s).classList.remove('up', 'on', 'kbup', 'under'));
  $('#bigp-screen').classList.remove('behind');
  $('#fig').classList.remove('small');
  $('#col').innerHTML = '';
  $('#panel').innerHTML = '';
  $('#typed').innerHTML = '';
  kbFocus('.none');
  actor = avatar;
  [avatar, floater].forEach((b) => { b.set('idle'); b.hush(); b.hold(null); });
  $('#bigp-screen').classList.remove('kbup');
  $('#films-screen').classList.remove('backdrop');
  ctx.zolder = 'ok';
  ctx.jobs = [{ name: 'Ondertitels zoeken', where: 'Woonkamer', pct: 41 }];
  focus(null);
}

// ---------- oproepen op een gewoon scherm ----------
async function waitTrigger(ms) {
  const btn = $('#trigger');
  btn.classList.add('hot');
  let fired = false;
  btn.onclick = () => { fired = true; };
  for (let t = 0; t < ms && !fired; t += 100) await sleep(100);
  btn.classList.remove('hot');
  btn.onclick = null;
}
async function summon(request) {
  screen('#films-screen');
  focus($('#grid .card'));
  await sleep(900);
  await waitTrigger(2200);
  $('#dim').classList.add('on');
  $('#kb').classList.add('up');
  $('#float').classList.add('kbup', 'on');
  actor = floater;
  floater.set('listening');
  floater.hop(130); // binnenkomst: sprongetje met squash en stretch
  $('#panel').innerHTML = `<div class="st in"><i class="dot"></i> Ik luister…</div><div class="h in" ${stag(1)}>Spreek je vraag in.</div>
    <div class="ctxl in" ${stag(2)}>${IC.eye} Big P ziet: Films op Zolder, 342 titels</div>`;
  await sleep(700);
  await dictate(request, floater);
}
async function dismiss() {
  floater.leave();
  await sleep(380);
  $('#float').classList.remove('on');
  $('#dim').classList.remove('on');
  await sleep(700);
  floater.set('idle');
}

const SCENES = [
  { id: '0', name: 'Oproepen', run: async () => {
    await summon('Scan deze bibliotheek opnieuw.');
    await key('0');
    await sleep(500);
    await kbDone();
    $('#float').classList.remove('kbup');
    floater.set('working');
    await swap($('#panel'), `<div class="q">Je vroeg: <b>Scan deze bibliotheek opnieuw</b></div><div class="steps" id="fsteps"></div>`);
    const list = $('#fsteps');
    await step(list, 'Dit scherm: Films op Zolder', 900, 'herkend');
    await step(list, 'Zolder · scan van Films starten', 1100, 'gestart');
    await sleep(300);
    floater.react();
    await swap($('#panel'), `<div class="h in" style="margin-top:0">De scan van Films loopt.</div>` +
      pcard('Uitgevoerd door Pleya · 21:14', [line(true, 'Scan gestart · Films · Zolder', '<span id="fpct">Bezig · 3%</span>', 'fbar')], 1));
    progress('fbar', '#fpct', 3, 6, (p) => `Bezig · ${p}%`);
    await sleep(700);
    await talk($('#panel .h'), floater);
    await key('0b', () => floater.hold({ pose: 'duim_presenteren', mouth: 'mid' }));
    floater.settle(1200);
    await sleep(3000);
    await dismiss();
    await sleep(900);
  } },
  { id: '0c', name: 'Oproepen, bevestiging', run: async () => {
    await summon('Geef Sam ook toegang tot deze bibliotheek.');
    await sleep(400);
    await kbDone();
    $('#float').classList.remove('kbup');
    floater.set('working');
    await swap($('#panel'), `<div class="q">Je vroeg: <b>Geef Sam ook toegang tot deze bibliotheek</b></div><div class="steps" id="fsteps"></div>`);
    const list = $('#fsteps');
    await step(list, 'Dit scherm: Films op Zolder', 800, 'herkend');
    await step(list, 'Zolder · gebruiker Sam opzoeken', 1000, 'gevonden');
    await sleep(300);
    floater.set('attentive'); // kijkt naar de kaart, geduldig
    $('#float').classList.add('under');
    $('#scrim').classList.add('on');
    modal(`<div class="src">${IC.pleya} Pleya vraagt bevestiging</div><h2>Toegang geven</h2><div class="kvs">
      ${kv('Gebruiker', 'Sam')}${kv('Server', 'Zolder (Pleya Server)')}${kv('Bibliotheek', 'Films <span class="muted">· naast Kids</span>')}${kv('Beheerder', 'Nee')}</div>
      <div class="btn-row"><div class="btn" id="m-cancel">Annuleren</div><div class="btn" id="m-ok">Toegang geven</div></div>`);
    $('#modal').classList.add('on');
    focus($('#m-cancel'));
    await sleep(2400);
    focus($('#m-ok'));
    await sleep(900);
    await press($('#m-ok'));
    floater.nod(1);
    $('#modal').classList.remove('on');
    $('#scrim').classList.remove('on');
    $('#float').classList.remove('under');
    focus($('#grid .card'));
    await sleep(400);
    floater.react();
    await swap($('#panel'), `<div class="h in" style="margin-top:0">Sam kan nu Films zien.</div>` +
      pcard('Uitgevoerd door Pleya · 21:15', [line(true, 'Toegang gegeven · Films · Sam', 'Zolder · Kids bleef staan')], 1));
    await sleep(700);
    await talk($('#panel .h'), floater);
    floater.settle(1200);
    await sleep(3000);
    await dismiss();
    await sleep(900);
  } },
  { id: '1', name: 'Rust', run: async () => {
    screen('#bigp-screen');
    drawCtx();
    $('#col').innerHTML = `<div class="st in"><i class="dot"></i> Klaar voor je vraag · Zolder, Woonkamer en G-Plexflix</div>
      <div class="h in" ${stag(1)}>Hoi Michel, wat moet er gebeuren?</div>
      <div class="ctxchip in" ${stag(2)}><span class="chip-btn"><i class="dot warn"></i>2 mislukte taken op Zolder · bekijken</span></div>
      <div class="btn-row in" ${stag(3)}><div class="btn primary" id="ask">${IC.mic} Vraag Big P</div></div>
      <div class="ex-label in" ${stag(4)}>Bijvoorbeeld</div>
      <div class="ex">
        <div class="btn in" ${stag(5)}>Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw.</div>
        <div class="btn in" ${stag(6)}>Wie kan Kids zien op Woonkamer en op G-Plexflix? Zijn er verschillen?</div>
        <div class="btn in" ${stag(7)}>Scan alle filmbibliotheken op al mijn servers.</div>
      </div>`;
    focus($('#ask'));
    avatar.hop();
    await sleep(700);
    avatar.gesture('zwaaien', 2200); // begroeting
    await talk($('#col .h'), avatar);
    await key('1', () => avatar.hold({ pose: 'zwaaien', mouth: 'mid' }));
    await sleep(6000); // rust: hier zie je kijken naar de voorbeelden, knipperen, af en toe zwaaien
    await press($('#ask'));
  } },
  { id: '2', name: 'Luisteren', run: async () => {
    screen('#bigp-screen');
    drawCtx();
    $('#fig').classList.add('small');
    $('#bigp-screen').classList.add('kbup');
    avatar.set('listening');
    avatar.hop(80);
    $('#col').innerHTML = `<div class="st in"><i class="dot"></i> Ik luister…</div><div class="h in" ${stag(1)}>Spreek je vraag in.</div>`;
    $('#kb').classList.add('up');
    await sleep(700);
    await dictate('Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw.', avatar);
    await key('2');
    await sleep(600);
    await kbDone();
  } },
  { id: '3', name: 'Werken', run: async () => {
    screen('#bigp-screen');
    drawCtx();
    avatar.set('working');
    avatar.hop(80);
    $('#col').innerHTML = `<div class="q in">Je vroeg: <b>Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw.</b></div>
      <div class="h in" ${stag(1)}>Even kijken…</div><div class="steps" id="steps"></div>
      <div class="btn-row in" ${stag(2)}><div class="btn" id="cancel">${IC.close} Annuleren</div></div>`;
    focus($('#cancel'));
    const list = $('#steps');
    await sleep(900);
    await status('Zolder controleren…');
    await step(list, 'Zolder · taken van vandaag ophalen', 1100, '2 mislukt', 'ok', 'amber');
    await status('Woonkamer controleren…');
    await step(list, 'Woonkamer · geplande taken ophalen', 1000, '0 mislukt');
    await status('G-Plexflix controleren…');
    await step(list, 'G-Plexflix · activiteit ophalen', 1000, '0 mislukt');
    await status('Taken opnieuw starten…');
    await step(list, 'Zolder · ‘Scan Films’ opnieuw starten', 1000, 'gestart');
    const last = step(list, 'Zolder · ‘Miniaturen Series’ opnieuw starten', 1400, 'in de wachtrij');
    await sleep(700);
    await key('3', () => avatar.hold({ pose: 'wijzen' }));
    await last;
    await sleep(700);
  } },
  { id: '4', name: 'Resultaat', run: async () => {
    screen('#bigp-screen');
    ctx.jobs = [{ name: 'Scan Films', where: 'Zolder', pct: 4 }, ...ctx.jobs];
    drawCtx();
    avatar.react(); // juichen met een sprong, daarna duim en praten
    $('#col').innerHTML = `<div class="q in">Je vroeg: <b>Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw.</b></div>
      <div class="h in" ${stag(1)}>Twee taken op Zolder lopen weer.</div>
      <div class="p in" ${stag(1)}>Woonkamer en G-Plexflix hadden vandaag geen mislukte taken.</div>
      ${pcard('Uitgevoerd door Pleya · 21:14', [
        line(true, 'Opnieuw gestart · Scan Films · Zolder', '<span id="spct">Bezig · 4%</span>', 'sbar'),
        line(true, 'Opnieuw gestart · Miniaturen Series · Zolder', 'In de wachtrij, start na de scan'),
      ])}
      <div class="btn-row in" ${stag(3)}><div class="btn primary" id="ask">${IC.mic} Vraag Big P</div><div class="btn">Laat zien wat er misging</div><div class="btn">Melden als het klaar is</div><div class="btn">Klaar</div></div>`;
    focus($('#ask'));
    progress('sbar', '#spct', 4, 4, (p) => `Bezig · ${p}%`);
    await sleep(1200);
    await talk($('#col .h'), avatar);
    await talk($('#col .p'), avatar);
    await key('4', () => avatar.hold({ pose: 'duim_presenteren', mouth: 'mid' }));
    avatar.settle(1000);
    await sleep(3500);
  } },
  { id: '5', name: 'Gebruiker aanmaken', run: async () => {
    screen('#bigp-screen');
    drawCtx();
    $('#fig').classList.add('small');
    $('#bigp-screen').classList.add('kbup');
    avatar.set('listening');
    avatar.hop(80);
    $('#col').innerHTML = `<div class="st in"><i class="dot"></i> Ik luister…</div><div class="h in" ${stag(1)}>Spreek je vraag in.</div>`;
    $('#kb').classList.add('up');
    await sleep(600);
    await dictate('Maak Sam aan op Woonkamer, alleen Kids en Tekenfilms.', avatar);
    await sleep(300);
    await kbDone();
    $('#fig').classList.remove('small');
    avatar.set('working');
    await swap($('#col'), `<div class="q">Je vroeg: <b>Maak Sam aan op Woonkamer, alleen Kids en Tekenfilms.</b></div>
      <div class="h">Woonkamer controleren…</div><div class="steps" id="steps"></div>
      <div class="btn-row"><div class="btn" id="cancel">${IC.close} Annuleren</div></div>`);
    focus($('#cancel'));
    const list = $('#steps');
    await step(list, 'Woonkamer · bibliotheken ophalen', 1000, '6 bibliotheken');
    await step(list, 'Woonkamer · kijken of de naam Sam vrij is', 1000, 'vrij');
    await step(list, 'Kids en Tekenfilms gevonden', 900, '2 van 6');
    await status('Dit vraagt je bevestiging.');
    await sleep(500);
    avatar.set('attentive'); // kijkt naar de kaart, wacht rustig
    $('#bigp-screen').classList.add('behind');
    $('#scrim').classList.add('on');
    modal(`<div class="src">${IC.pleya} Pleya vraagt bevestiging</div><h2>Gebruiker aanmaken</h2><div class="kvs">
      ${kv('Gebruiker', 'Sam')}${kv('Server', 'Woonkamer (Jellyfin)')}${kv('Toegang', 'Kids, Tekenfilms <span class="muted">· alleen deze twee</span>')}${kv('Beheerder', 'Nee')}
      <div class="kv"><span class="k">Wachtwoord</span><span class="pw" id="pw">${IC.lock}<span class="muted">Optioneel</span></span></div></div>
      <div class="fine">${IC.info}<span>Het wachtwoord typ je hier in Pleya, in een afgeschermd veld. Het gaat niet naar Big P en niet naar de AI-provider.</span></div>
      <div class="btn-row"><div class="btn" id="m-cancel">Annuleren</div><div class="btn" id="m-ok">Aanmaken</div></div>`);
    $('#modal').classList.add('on');
    focus($('#m-cancel'));
    await sleep(1400);
    await key('5');
    await sleep(1600);
    focus($('#m-ok'));
    await sleep(900);
    await press($('#m-ok'));
    avatar.nod(1); // knikt als je bevestigt
    $('#modal').classList.remove('on');
    $('#scrim').classList.remove('on');
    $('#bigp-screen').classList.remove('behind');
    await sleep(400);
    avatar.react();
    await swap($('#col'), `<div class="q">Je vroeg: <b>Maak Sam aan op Woonkamer, alleen Kids en Tekenfilms.</b></div>
      <div class="h">Sam staat op Woonkamer.</div>
      <div class="p">Sam ziet alleen Kids en Tekenfilms. De andere vier bibliotheken staan voor Sam uit.</div>
      ${pcard('Uitgevoerd door Pleya · 21:18', [
        line(true, 'Gebruiker aangemaakt · Sam · Woonkamer', 'Geen beheerder, geen wachtwoord'),
        line(true, 'Toegang gezet · Kids en Tekenfilms', 'Woonkamer · 2 van 6 bibliotheken'),
      ], 0)}
      <div class="btn-row"><div class="btn primary" id="ask">${IC.mic} Vraag Big P</div><div class="btn">Wachtwoord instellen</div><div class="btn">Klaar</div></div>`);
    focus($('#ask'));
    await sleep(500);
    await talk($('#col .h'), avatar);
    await talk($('#col .p'), avatar);
    avatar.settle(1000);
    await sleep(3000);
  } },
  { id: '6', name: 'Fout', run: async () => {
    screen('#bigp-screen');
    ctx.zolder = 'off';
    drawCtx();
    avatar.set('working');
    avatar.hop(80);
    $('#col').innerHTML = `<div class="q in">Je vroeg: <b>Scan Films op Zolder</b></div>
      <div class="h in" ${stag(1)}>Zolder controleren…</div><div class="steps" id="steps"></div>
      <div class="btn-row in" ${stag(2)}><div class="btn" id="cancel">${IC.close} Annuleren</div></div>`;
    focus($('#cancel'));
    await step($('#steps'), 'Zolder · verbinden', 1800, 'niet bereikbaar', 'fail', 'red');
    await sleep(400);
    avatar.worry(); // bezorgd, schudt het hoofd, zakt door
    await swap($('#col'), `<div class="q">Je vroeg: <b>Scan Films op Zolder</b></div>
      <div class="h">Dat lukte niet: Zolder is niet bereikbaar.</div>
      <div class="p">Er is niets veranderd. Probeer het opnieuw zodra de server weer online is.</div>
      ${pcard('Niet uitgevoerd door Pleya · 21:16', [line(false, 'Scan niet gestart · Films · Zolder', 'Pleya Server · offline sinds 21:09')], 0)}
      <div class="btn-row"><div class="btn primary" id="ask">${IC.mic} Vraag Big P</div><div class="btn">Melden als Zolder terug is</div><div class="btn">Klaar</div></div>`);
    focus($('#ask'));
    await sleep(1100);
    await talk($('#col .h'), avatar, true); // rustig, zonder nadruk
    await talk($('#col .p'), avatar, true);
    await key('6');
    await sleep(3500);
  } },
  { id: '7', name: 'Aanvragen op beschrijving', run: async () => {
    screen('#bigp-screen');
    drawCtx();
    $('#fig').classList.add('small');
    $('#bigp-screen').classList.add('kbup');
    avatar.set('listening');
    avatar.hop(80);
    const ask = 'Die film waarin een astronaut alleen achterblijft op Mars en aardappels kweekt.';
    $('#col').innerHTML = `<div class="st in"><i class="dot"></i> Ik luister…</div><div class="h in" ${stag(1)}>Spreek je vraag in.</div>`;
    $('#kb').classList.add('up');
    await sleep(600);
    await dictate(ask, avatar);
    await sleep(300);
    await kbDone();
    $('#fig').classList.remove('small');
    avatar.set('working');
    await swap($('#col'), `<div class="q">Je vroeg: <b>${ask}</b></div>
      <div class="h">Even zoeken…</div><div class="steps" id="steps"></div>
      <div class="btn-row"><div class="btn" id="cancel">${IC.close} Annuleren</div></div>`);
    focus($('#cancel'));
    const list = $('#steps');
    await step(list, 'Titels bedenken bij je beschrijving', 1300, '4 titels');
    await step(list, 'Seerr doorzoeken', 1200, '4 kandidaten');
    await sleep(300);
    avatar.react();
    const opts = [
      ['The Martian', 2015, 'Astronaut Mark Watney blijft achter op Mars en moet overleven tot er hulp komt.', 'Aan te vragen', '', '#5a2a14,#d0703a'],
      ['Red Planet', 2000, 'Een bemanning strandt op Mars als de zuurstof voor de kolonisten opraakt.', 'Aan te vragen', '', '#3a1612,#a8402e'],
      ['Mission to Mars', 2000, 'Een reddingsmissie zoekt naar de eerste bemanning die op Mars verdween.', 'Beschikbaar', 'ok', '#1d2a3a,#5a7fa8'],
      ['Stranded', 2001, 'Een kleine Marsploeg moet het na een noodlanding zonder terugreis zien te redden.', 'Al aangevraagd', 'req', '#2a2a2a,#7a6a5a'],
    ];
    await swap($('#col'), `<div class="q">Je vroeg: <b>${ask}</b></div>
      <div class="h">Ik vond vier films die erop lijken.</div>
      <div class="opts">${opts.map(([t, y, d, chip, cls, g], i) => `<div class="opt in" ${stag(i)}>
        <div class="post" style="background:linear-gradient(160deg,${g.split(',')[1]},${g.split(',')[0]} 75%)"><b>${t}</b></div>
        <div class="txt"><div class="t">${t} <span class="y">(${y})</span></div><div class="d">${d}</div></div>
        <span class="schip ${cls}">${chip}</span></div>`).join('')}</div>`);
    const cards = [...$('#col').querySelectorAll('.opt')];
    focus(cards[0]);
    await sleep(400);
    avatar.set('idle');
    avatar.aimAt(cards[0]); // wijst de keuzes aan en volgt de focus
    avatar.gesture('wijzen', 4200);
    await talk($('#col .h'), avatar);
    await key('7', () => avatar.hold({ pose: 'wijzen' }));
    await sleep(800);
    focus(cards[1]); avatar.aimAt(cards[1]); await sleep(900);
    focus(cards[0]); avatar.aimAt(cards[0]); await sleep(800);
    await press(cards[0]);
    avatar.set('attentive');
    $('#bigp-screen').classList.add('behind');
    $('#scrim').classList.add('on');
    modal(`<div class="src">${IC.pleya} Pleya vraagt bevestiging</div><h2>The Martian (2015) aanvragen</h2><div class="kvs">
      ${kv('Film', 'The Martian <span class="muted">· 2015 · 2 u 24 min</span>')}${kv('Via', 'Films via Seerr')}${kv('Kwaliteit', '4K <span class="muted">· optioneel, standaard is 1080p</span>')}</div>
      <div class="btn-row"><div class="btn" id="m-cancel">Annuleren</div><div class="btn" id="m-ok">Aanvragen</div></div>`);
    $('#modal').classList.add('on');
    focus($('#m-cancel'));
    await sleep(2200);
    focus($('#m-ok'));
    await sleep(900);
    await press($('#m-ok'));
    avatar.nod(1);
    $('#modal').classList.remove('on');
    $('#scrim').classList.remove('on');
    $('#bigp-screen').classList.remove('behind');
    await sleep(400);
    avatar.react();
    await swap($('#col'), `<div class="q">Je vroeg: <b>${ask}</b></div>
      <div class="h">The Martian is aangevraagd.</div>
      <div class="p">Je krijgt een melding zodra hij in Films staat.</div>
      ${pcard('Uitgevoerd door Pleya · 21:22', [line(true, 'Aangevraagd · The Martian (2015)', 'Films via Seerr · 1080p · wacht op goedkeuring')], 0)}
      <div class="btn-row"><div class="btn primary" id="ask">${IC.mic} Vraag Big P</div><div class="btn">Klaar</div></div>`);
    focus($('#ask'));
    await sleep(500);
    await talk($('#col .h'), avatar);
    await talk($('#col .p'), avatar);
    avatar.settle(1000);
    await sleep(3000);
  } },
];

// ---------- bediening ----------
function setPaused(p) {
  paused = p;
  // Big P blijft leven tijdens pauze; alleen het script staat stil
  $('#play').textContent = p ? 'Afspelen' : 'Pauze';
  document.body.classList.toggle('paused', p);
}
async function play(i) {
  sceneIx = (i + SCENES.length) % SCENES.length;
  gen++;
  reset();
  $('#scenes').querySelectorAll('button').forEach((b, j) => b.classList.toggle('on', j === sceneIx));
  $('#note').textContent = sceneIx < 2 ? 'Op een gewoon Pleya-scherm roept lang drukken op Play/Pause Big P op.' : 'Mijn Pleya ▸ Big P';
  const mine = gen;
  try {
    await SCENES[sceneIx].run();
    if (mine === gen) play(sceneIx + 1);
  } catch (e) { if (e !== CANCEL) throw e; }
}
$('#scenes').innerHTML = SCENES.map((s) => `<button>${s.id} ${s.name}</button>`).join(' ');
$('#scenes').querySelectorAll('button').forEach((b, j) => { b.onclick = () => play(j); });
$('#play').onclick = () => setPaused(!paused);
$('#next').onclick = () => play(sceneIx + 1);
$('#rm').checked = motion.reduced;
$('#rm').onchange = (e) => { motion.reduced = e.target.checked; document.body.classList.toggle('rm', motion.reduced); };
document.body.classList.toggle('rm', motion.reduced);
document.body.classList.toggle('still', stillMode);

function fit() {
  const s = stillMode ? 1 : Math.min(innerWidth / 1920, (innerHeight - $('#controls').offsetHeight) / 1080);
  tv.style.transform = `scale(${s})`;
  $('#stage').style.height = 1080 * s + 'px';
  $('#stage').style.width = stillMode ? '1920px' : '';
  tv.style.left = stillMode ? '0' : Math.max(0, (innerWidth - 1920 * s) / 2) + 'px';
}
addEventListener('resize', fit);
fit();

const start = SCENES.findIndex((s) => s.id === (params.get('scene') ?? params.get('still')?.replace(/b$/, '')));
play(start < 0 ? 0 : start);
