// Big P als lagen: lichaam, mond, wenkbrauwen en zelf getekende oogleden.
// Coordinaten zijn die van de volle bron (1122 x 1402, bigp-layers.json); de PNG's in assets/ zijn
// op de helft verkleind en worden in die coordinaten op volle maat geplaatst.
const L = {
  w: 1122, h: 1402,
  feet: [545, 1184],
  mouth: { x: 386, y: 387, w: 257, h: 272 },
  browL: { x: 405, y: 225, w: 119, h: 62 },
  browR: { x: 696, y: 226, w: 102, h: 58 },
  eyes: [
    { cx: 460, cy: 382, rx: 62, ry: 63, lid: '#fc2013' },
    { cx: 768, cy: 378, rx: 47, ry: 63, lid: '#fc5b2e' },
  ],
};
const LASH = '#2a0604';
const MOUTHS = ['rest', 'small', 'laugh', 'o'];

// Standen uit het Motion-hoofdstuk van tvos-redesign-38-big-p-proposed.md.
// brows: [lift px, rotatie graden] per wenkbrauw; negatieve lift = omhoog.
const STATES = {
  idle:      { browL: [0, 0],    browR: [0, 0],   mouth: 'rest',  lean: 0,   sway: 0, breathe: 4,   blink: [3, 6], drift: true },
  listening: { browL: [-18, 0],  browR: [-18, 0], mouth: 'small', lean: 0,   sway: 0, breathe: 5.5, blink: [5, 8] },
  working:   { browL: [-11, -3], browR: [-2, 2],  mouth: 'rest',  lean: 3,   sway: 1, breathe: 4,   blink: [3, 6] },
  success:   { browL: [-18, 0],  browR: [-18, 0], mouth: 'laugh', lean: 0,   sway: 0, breathe: 4,   blink: [3, 6] },
  worried:   { browL: [-8, -9],  browR: [-8, 9],  mouth: 'small', lean: 0,   sway: 0, breathe: 4,   blink: [4, 7], sag: 7 },
};

const reducedQuery = matchMedia('(prefers-reduced-motion: reduce)');
const motion = { reduced: reducedQuery.matches, paused: false };
reducedQuery.addEventListener?.('change', (e) => { motion.reduced = e.matches; });

const all = [];
const rand = (a, b) => a + Math.random() * (b - a);
const ease = (x) => 0.5 - Math.cos(Math.PI * x) / 2;

class BigP {
  constructor(host) {
    const [fx, fy] = L.feet;
    const img = (href, b, extra = '') => `<image href="${href}" x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" ${extra}/>`;
    host.innerHTML = `<svg viewBox="0 0 ${L.w} ${L.h}" style="position:relative;width:100%;height:100%;overflow:visible;display:block">
      <defs><radialGradient id="floor${all.length}"><stop offset="0" stop-color="#e5140f" stop-opacity=".42"/><stop offset=".55" stop-color="#e5140f" stop-opacity=".14"/><stop offset="1" stop-color="#e5140f" stop-opacity="0"/></radialGradient></defs>
      <ellipse cx="${fx}" cy="${fy + 6}" rx="470" ry="80" fill="url(#floor${all.length})"/>
      <ellipse class="shadow" cx="${fx}" cy="${fy + 4}" rx="300" ry="20" fill="#000" opacity=".55"/>
      <g class="rig">
        <image href="assets/body.png" x="0" y="0" width="${L.w}" height="${L.h}"/>
        ${MOUTHS.map((m) => img(`assets/mouth-${m}.png`, L.mouth, `class="mouth" data-m="${m}" style="transition:opacity 120ms linear;opacity:${m === 'rest' ? 1 : 0}"`)).join('')}
        ${L.eyes.map((e, i) => `<clipPath id="eye${all.length}-${i}"><ellipse cx="${e.cx}" cy="${e.cy}" rx="${e.rx + 3}" ry="${e.ry + 3}"/></clipPath>
        <linearGradient id="lidg${all.length}-${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${e.lid}"/><stop offset=".7" stop-color="${e.lid}"/><stop offset="1" stop-color="#7a0905"/></linearGradient>
        <g clip-path="url(#eye${all.length}-${i})"><path class="lid" fill="url(#lidg${all.length}-${i})"/><path class="lash" fill="none" stroke="${LASH}" stroke-width="7"/></g>`).join('')}
        <g class="brow">${img('assets/brow-l.png', L.browL)}</g>
        <g class="brow">${img('assets/brow-r.png', L.browR)}</g>
      </g></svg>`;
    const q = (s) => host.querySelectorAll(s);
    this.rig = q('.rig')[0];
    this.shadow = q('.shadow')[0];
    this.mouths = [...q('.mouth')];
    this.lids = [...q('.lid')];
    this.lashes = [...q('.lash')];
    this.brows = [...q('.brow')];
    this.t = 0;
    this.cur = { lean: 0, sway: 0, sag: 0, bl: [0, 0], br: [0, 0], period: 4 };
    this.drift = 0;
    this.nextDrift = rand(5, 9);
    this.nextBlink = rand(2, 4);
    this.blinkT = -1;
    this.pulses = [];
    this.set('idle');
    all.push(this);
  }

  set(name) {
    this.state = name;
    this.s = STATES[name];
    this.mouths.forEach((m) => { m.style.opacity = m.dataset.m === this.s.mouth ? 1 : 0; });
    if (!this.s.drift) this.drift = 0;
  }

  // Eenmalige bewegingen: knik (dip en voorover) en zak (bij een fout).
  nod(amp = 1, dur = 600) { this.pulses.push({ t0: this.t, dur: dur / 1000, dy: 14 * amp, rot: 1.4 * amp }); }
  sag() { this.pulses.push({ t0: this.t, dur: 0.9, dy: 22, rot: 0 }); }

  // success: lachen, wenkbrauwen omhoog, een knik van 600 ms, daarna terug naar rust.
  react() {
    this.set('success');
    this.nod(1.2, 600);
    clearTimeout(this.back);
    this.back = setTimeout(() => { if (this.state === 'success') this.set('idle'); }, 1800);
  }
  worry() { this.set('worried'); this.sag(); }

  tick(dt) {
    this.t += dt;
    const s = this.s, c = this.cur, rm = motion.reduced;
    // volgen met een tijdconstante van 120 ms: een overgang is na ongeveer 350 ms rond
    const k = rm ? 1 : 1 - Math.exp(-dt / 0.12);
    const to = (a, b) => a + (b - a) * k;

    if (s.drift && !rm && this.t > this.nextDrift) {
      this.drift = this.drift === 0 ? (Math.random() < 0.5 ? -1.5 : 1.5) : 0; // even scheef, blijft even staan
      this.nextDrift = this.t + rand(4, 8);
    }
    c.lean = to(c.lean, rm ? 0 : s.lean + this.drift);
    c.sway = to(c.sway, rm ? 0 : s.sway);
    c.sag = to(c.sag, rm ? 0 : s.sag || 0);
    c.period = to(c.period, s.breathe);
    c.bl = [to(c.bl[0], s.browL[0]), to(c.bl[1], s.browL[1])];
    c.br = [to(c.br[0], s.browR[0]), to(c.br[1], s.browR[1])];

    let dy = c.sag, rot = c.lean + c.sway * Math.sin(this.t * 2 * Math.PI / 5);
    let scale = 1;
    if (!rm) {
      this.phase = (this.phase || 0) + dt / c.period;
      scale = 1 + 0.006 * (1 - Math.cos(2 * Math.PI * this.phase)); // 1,000 tot 1,012
      this.pulses = this.pulses.filter((p) => {
        const x = (this.t - p.t0) / p.dur;
        if (x >= 1) return false;
        const f = Math.sin(Math.PI * ease(x));
        dy += p.dy * f; rot += p.rot * f;
        return true;
      });
    } else this.pulses = [];

    // knipperen: 180 ms, om de 3 tot 6 s (luisterend minder vaak)
    let b = 0;
    if (!rm) {
      if (this.blinkT < 0 && this.t > this.nextBlink) this.blinkT = 0;
      if (this.blinkT >= 0) {
        this.blinkT += dt;
        const x = this.blinkT / 0.18;
        if (x >= 1) { this.blinkT = -1; this.nextBlink = this.t + rand(...s.blink); } else b = Math.sin(Math.PI * x);
      }
    }

    const [fx, fy] = L.feet;
    this.rig.setAttribute('transform', `rotate(${rot.toFixed(3)} ${fx} ${fy}) translate(0 ${dy.toFixed(2)}) translate(${fx} ${fy}) scale(${scale.toFixed(4)}) translate(${-fx} ${-fy})`);
    this.shadow.setAttribute('rx', (300 - dy * 1.2).toFixed(1));
    const brow = (g, box, [lift, r]) => {
      const cx = box.x + box.w / 2, cy = box.y + box.h / 2;
      g.setAttribute('transform', `translate(0 ${lift.toFixed(2)}) rotate(${r.toFixed(2)} ${cx} ${cy})`);
    };
    brow(this.brows[0], L.browL, c.bl);
    brow(this.brows[1], L.browR, c.br);
    L.eyes.forEach((e, i) => {
      const [lid, lash] = b > 0.02 ? lidPath(e, b) : ['', ''];
      this.lids[i].setAttribute('d', lid);
      this.lashes[i].setAttribute('d', lash);
      this.lashes[i].setAttribute('opacity', Math.min(1, b * 1.6).toFixed(2));
    });
  }
}

// Bovenlid in de gezichtskleur, gebogen rand die de oogbol volgt; een klein onderlid komt het tegemoet.
// Geeft [lidvlakken, wimperlijn]; beide worden op de oogellips geknipt.
function lidPath(e, b) {
  const x0 = e.cx - e.rx - 2, x1 = e.cx + e.rx + 2;
  const top = e.cy - e.ry - 30; // lid begint ongeveer 30 px boven het oog
  const meet = e.cy + e.ry * 0.25;
  const edge = e.cy - e.ry + (meet - (e.cy - e.ry)) * b;
  const bulge = e.ry * 0.28 * Math.min(1, b * 1.4);
  const low = e.cy + e.ry - (e.cy + e.ry - meet) * b;
  return [
    `M${x0} ${top} L${x1} ${top} L${x1} ${edge} Q${e.cx} ${edge + 2 * bulge} ${x0} ${edge} Z ` +
    `M${x0} ${e.cy + e.ry + 6} L${x1} ${e.cy + e.ry + 6} L${x1} ${low} Q${e.cx} ${low - e.ry * 0.12} ${x0} ${low} Z`,
    `M${x0} ${edge} Q${e.cx} ${edge + 2 * bulge} ${x1} ${edge}`,
  ];
}

let last = performance.now();
function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (!motion.paused) all.forEach((p) => p.tick(dt));
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
