// Big P als lagen, tweede ronde: hij leeft. Eén <svg> per Big P met één rig-groep; alle beweging is een
// transform op die groep (plus arm, wenkbrauwen, oogleden), zodat het een-op-een naar een Flutter-widget met
// AnimationControllers kan. Coordinaten zijn die van de volle bron (1122 x 1402, bigp-layers.json uit
// ~/.claude/skills/big-p/avatar/lagen); de PNG's in assets/ zijn op de helft verkleind.
// Gedrag overgenomen uit de Remotion-template van de big-p-skill (BigP.tsx, poses.ts, mouth.ts).
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
  wave: { x: 28, y: 267, w: 240, h: 393, pivot: [289, 566] },
  aim: { x: 690, y: 628, w: 388, h: 188, pivot: [722, 658], tip: [1068, 722] },
};
const LASH = '#2a0604';
const LIMB = '#1b0b09';
const MOUTHS = ['rest', 'small', 'mid', 'big', 'o', 'e', 'laugh'];
// Volle houdingen (pose-*.png): affien op de P van de rustpose gelegd, zodat mond en wenkbrauwen erover passen.
// Elke houding heeft eigen beenlengte; de figuur schuift per houding naar de vloer (feet uit bigp-layers.json).
const POSES = ['zwaaien', 'juichen', 'duim_presenteren', 'vinger_presenteren', 'wijzen_links'];
const POSE_FEET = { zwaaien: 1157, juichen: 1238, duim_presenteren: 1147, vinger_presenteren: 1149, wijzen_links: 1228 };
const OWN_FACE = { wijzen_links: true }; // driekwartaanzicht: eigen gezicht, geen mond-, wenkbrauw- of lidlaag
const AIM_BASE = Math.atan2(L.aim.tip[1] - L.aim.pivot[1], L.aim.tip[0] - L.aim.pivot[0]) * 180 / Math.PI; // ~10,5 graden
const AIM_MIN = -12, AIM_MAX = 60; // SKILL.md: hoger schuift de hand achter de P, lager raakt hij het been
const SWITCH = 0.27; // s; houdingwissel zonder overvloeien: beeld springt halverwege, lichaam veert in

// Standen. brows: [lift, rotatie] per wenkbrauw (negatieve lift = omhoog; negatieve rotatie links = binnenkant op).
// lean in graden rond de voeten, positief = naar de inhoud (wordt met facing vermenigvuldigd); dy zakt de figuur.
const STATES = {
  idle:      { bl: [0, 0],     br: [0, 0],    mouth: 'rest',  lean: 0,    dy: 0,  float: 1,   breathe: 3.4, pose: 'rest' },
  listening: { bl: [-20, -3],  br: [-20, 3],  mouth: 'o',     lean: 4,    dy: 10, float: .7,  breathe: 4.2, pose: 'rest', ear: true },
  working:   { bl: [-16, 3],   br: [4, 5],    mouth: 'rest',  lean: 3.5,  dy: 4,  float: .6,  breathe: 3.4, pose: 'point', think: true },
  success:   { bl: [-24, 0],   br: [-24, 0],  mouth: 'laugh', lean: 0,    dy: 0,  float: 1.2, breathe: 3.0, pose: 'duim_presenteren' },
  worried:   { bl: [-14, -16], br: [-14, 16], mouth: 'o', lean: -1.5, dy: 18, float: .35, breathe: 5.0, pose: 'rest' },
  attentive: { bl: [-10, 0],   br: [-10, 0],  mouth: 'rest',  lean: 3,    dy: 6,  float: .5,  breathe: 4.4, pose: 'rest' },
};
const LEVEL = { rest: 0, small: 1, e: 1, o: 1, mid: 2, big: 3, laugh: 3 };

const reducedQuery = matchMedia('(prefers-reduced-motion: reduce)');
const motion = { reduced: reducedQuery.matches, paused: false };
reducedQuery.addEventListener?.('change', (e) => { motion.reduced = e.matches; });

const all = [];
const rand = (a, b) => a + Math.random() * (b - a);
const ease = (x) => 0.5 - Math.cos(Math.PI * x) / 2;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
// licht onderdempte veer: overgangen schieten een fractie door en komen dan tot rust, zonder trillen
function spring(s, target, dt, k = 150, z = 0.72) {
  s.v += ((target - s.x) * k - s.v * 2 * Math.sqrt(k) * z) * dt;
  s.x += s.v * dt;
}

// Sprong met squash en stretch: inveren, strekken bij het afzetten, parabool, platdrukken bij de landing.
// Geeft lift (render-px omhoog) en verticale schaal; de breedte compenseert zodat het volume ongeveer gelijk blijft.
function hopAt(x, h) {
  const a = 0.16, b = 0.72;
  if (x < a) return { lift: 0, sy: 1 - 0.12 * Math.sin((Math.PI / 2) * (x / a)) };
  if (x < b) { const v = (x - a) / (b - a); return { lift: h * 4 * v * (1 - v), sy: 1 + 0.09 * Math.cos(Math.PI * v) ** 2 }; }
  const w = (x - b) / (1 - b);
  return { lift: 0, sy: 1 - 0.13 * Math.sin(Math.PI * w) * (1 - 0.4 * w) };
}

class BigP {
  // facing: aan welke kant de inhoud staat. +1 = rechts (Big P-scherm), -1 = links (opgeroepen in de hoek).
  constructor(host, { facing = 1 } = {}) {
    const n = all.length;
    const [fx, fy] = L.feet;
    const img = (href, b, extra = '') => `<image href="${href}" x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" ${extra}/>`;
    const full = (href, extra = '') => `<image href="${href}" x="0" y="0" width="${L.w}" height="${L.h}" ${extra}/>`;
    host.innerHTML = `<svg viewBox="0 0 ${L.w} ${L.h}" style="position:relative;width:100%;height:100%;overflow:visible;display:block">
      <defs><radialGradient id="floor${n}"><stop offset="0" stop-color="#e5140f" stop-opacity=".42"/><stop offset=".55" stop-color="#e5140f" stop-opacity=".14"/><stop offset="1" stop-color="#e5140f" stop-opacity="0"/></radialGradient></defs>
      <ellipse cx="${fx}" cy="${fy + 6}" rx="470" ry="80" fill="url(#floor${n})"/>
      <ellipse class="shadow" cx="${fx}" cy="${fy + 4}" rx="300" ry="20" fill="#000" opacity=".55"/>
      <g class="rig">
        <g class="p-wijzen" opacity="0">
          <circle cx="${L.aim.pivot[0]}" cy="${L.aim.pivot[1]}" r="26" fill="${LIMB}"/>
          <g class="aimarm">${img('assets/aim-arm.png', L.aim)}</g>
          ${full('assets/body-wijzen.png')}
        </g>
        ${full('assets/body.png', 'class="p-rest"')}
        ${POSES.map((p) => full(`assets/pose-${p}.png`, `class="p-${p}" opacity="0"`)).join('')}
        <g class="wavearm" opacity="0">${img('assets/wave-arm.png', L.wave)}</g>
        <g class="face">
          ${MOUTHS.map((m) => img(`assets/mouth-${m}.png`, L.mouth, `class="mouth" data-m="${m}" opacity="${m === 'rest' ? 1 : 0}"`)).join('')}
          ${L.eyes.map((e, i) => `<clipPath id="eye${n}-${i}"><ellipse cx="${e.cx}" cy="${e.cy}" rx="${e.rx + 3}" ry="${e.ry + 3}"/></clipPath>
          <linearGradient id="lidg${n}-${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${e.lid}"/><stop offset=".7" stop-color="${e.lid}"/><stop offset="1" stop-color="#7a0905"/></linearGradient>
          <g clip-path="url(#eye${n}-${i})"><path class="lid" fill="url(#lidg${n}-${i})"/><path class="lash" fill="none" stroke="${LASH}" stroke-width="7"/></g>`).join('')}
          <g class="brow">${img('assets/brow-l.png', L.browL)}</g>
          <g class="brow">${img('assets/brow-r.png', L.browR)}</g>
        </g>
      </g></svg>`;
    const q = (s) => host.querySelector(s);
    this.svg = q('svg');
    this.rig = q('.rig');
    this.shadow = q('.shadow');
    this.face = q('.face');
    this.aimArm = q('.aimarm');
    this.waveArm = q('.wavearm');
    this.poseEls = { rest: q('.p-rest'), wijzen: q('.p-wijzen') };
    POSES.forEach((p) => { this.poseEls[p] = q(`.p-${p}`); });
    this.mouths = Object.fromEntries([...host.querySelectorAll('.mouth')].map((m) => [m.dataset.m, m]));
    this.lids = [...host.querySelectorAll('.lid')];
    this.lashes = [...host.querySelectorAll('.lash')];
    this.brows = [...host.querySelectorAll('.brow')];

    this.facing = facing;
    this.t = 0;
    const s0 = () => ({ x: 0, v: 0 });
    this.sp = { lean: s0(), dy: s0(), aim: { x: 20, v: 0 }, foot: s0(), bl0: s0(), bl1: s0(), br0: s0(), br1: s0(), open: s0() };
    this.pulses = []; // eenmalige bewegingen: knik, schud, nadruk op een woord
    this.hops = [];
    this.talkQ = [];
    this.talking = false;
    this.talkMouth = 'rest';
    this.ear = 1;
    this.tiltTarget = 0; this.nextTilt = rand(1, 3);
    this.glance = 0; this.glanceUntil = -1; this.nextGlance = rand(4, 7);
    this.nextWave = rand(15, 25);
    this.nextBlink = rand(1, 3); this.blinkT = -1; this.double = false;
    this.gesturePose = null; this.gestureUntil = 0;
    this.poseFrom = 'rest'; this.poseTo = 'rest'; this.poseT = SWITCH;
    this.shownMouth = 'rest';
    this.aimEl = null;
    this.forced = null;
    this.set('idle');
    all.push(this);
  }

  // ---------- standen en gebaren ----------
  set(name) {
    this.state = name;
    this.s = STATES[name];
    if (name !== 'idle') this.glanceUntil = -1;
    if (name !== 'working') this.aimEl = null;
  }
  gesture(pose, ms) { this.gesturePose = pose; this.gestureUntil = this.t + ms / 1000; }
  // knik: zakt in en buigt naar de inhoud toe
  nod(amp = 1, dur = 520) { this.pulses.push({ t0: this.t, dur: dur / 1000, dy: 16 * amp, rot: 2.2 * amp * this.facing }); }
  // hoofdschudden: twee tot drie keer links-rechts, uitdovend
  shake() { this.pulses.push({ t0: this.t, dur: 1.3, fn: (x) => 5.5 * Math.sin(2 * Math.PI * 2.5 * x) * (1 - x) }); }
  hop(h = 110, dur = 0.72) { this.hops.push({ t0: this.t, dur, h }); }
  // afgang: sprongetje met de neus naar de uitgang (rechts), de container schuift hem daarna weg
  leave() { this.hop(90, 0.6); this.pulses.push({ t0: this.t, dur: 0.6, rot: 6, dy: 0 }); }
  // wijzen naar een element; de arm volgt het element via een veer
  aimAt(el) { this.aimEl = el; }
  // nieuwe stap: hoofd draait mee, wenkbrauwen even op
  follow(el) {
    this.aimAt(el);
    this.pulses.push({ t0: this.t, dur: 0.45, dy: 6, rot: 2.5 * this.facing, brow: -10 });
  }
  stepDone() { this.gesture('vinger_presenteren', 850); this.pulses.push({ t0: this.t, dur: 0.4, dy: -10, rot: 0, brow: -12 }); }
  react() {
    this.set('success');
    this.gesture('juichen', 1150);
    this.hop(150, 0.8);
  }
  worry() {
    this.set('worried');
    this.shake();
    this.pulses.push({ t0: this.t, dur: 1.1, dy: 22, rot: 0 });
  }
  settle(ms = 900) {
    clearTimeout(this.back);
    this.back = setTimeout(() => { if (this.state === 'success' || this.state === 'attentive') this.set('idle'); }, ms);
  }
  // still: houding en mond vastzetten (?still=N)
  hold(f) { this.forced = f; }

  // ---------- praten ----------
  // Plant de mondstanden voor één woord: lettergrepen uit de klinkergroepen, per lettergreep eerst 'small',
  // dan de klinkervorm, dan half dicht. Opent hooguit één niveau per stap (mouth.ts). Geeft de duur in ms.
  speak(word, calm = false) {
    const groups = word.toLowerCase().match(/[aeiouyáéëïóöü]+/g) || ['a'];
    const per = calm ? 0.2 : 0.17;
    const dur = Math.max(0.22, groups.length * per);
    const stress = !calm && (word.replace(/\W/g, '').length >= 7 || /^[A-Z0-9]/.test(word));
    const step = dur / groups.length;
    let at = Math.max(this.t, this.talkQ.length ? this.talkQ[this.talkQ.length - 1].at : 0);
    groups.forEach((g, i) => {
      let m = /^(oe|oo|o|u|uu|ou|au|ui)$/.test(g) ? 'o' : /^(i|ie|ee|e|ij|ei|y|eu)$/.test(g) ? 'e' : (stress && i === 0 ? 'big' : 'mid');
      if (calm && m === 'big') m = 'mid';
      this.talkQ.push({ at, m: 'small' }, { at: at + step * 0.25, m, stress: stress && i === 0 }, { at: at + step * 0.75, m: 'small' });
      at += step;
    });
    this.talking = true;
    this.talkEnd = at + 0.3;
    return dur * 1000;
  }
  // einde zin: mond dicht
  hush() { this.talkQ = []; this.talkMouth = 'rest'; this.talkEnd = this.t + 0.12; }

  // ---------- per frame ----------
  autos() {
    const t = this.t, s = this.s;
    if (t > this.nextTilt) { this.tiltTarget = rand(-2.6, 2.6); this.nextTilt = t + rand(2.2, 4.5); }
    if (this.state === 'idle' && !this.talking && !this.gesturePose) {
      if (t > this.nextGlance && this.facing > 0) { this.glanceUntil = t + 1.7; this.nextGlance = t + rand(6, 11); }
      if (t > this.nextWave) { this.gesture('zwaaien', 1700); this.nextWave = t + rand(15, 25); }
    }
    this.glance = t < this.glanceUntil ? 1 : 0;
    if (s.ear && t > (this.nextEar || 0)) { this.ear = -this.ear; this.nextEar = t + rand(2.5, 4); }
  }

  tick(dt) {
    this.t += dt;
    const t = this.t, s = this.s, rm = motion.reduced, F = this.facing;
    if (!rm) this.autos();

    // houding: gebaar gaat voor de houding van de stand
    if (this.gesturePose && t > this.gestureUntil) this.gesturePose = null;
    let want = this.forced?.pose ?? this.gesturePose ?? s.pose;
    if (want === 'point') want = F > 0 ? 'wijzen' : 'wijzen_links';
    if (want !== this.poseTo) {
      this.poseFrom = this.poseT < SWITCH / 2 ? this.poseFrom : this.poseTo;
      this.poseTo = want;
      this.poseT = rm ? SWITCH : 0;
    }
    this.poseT = Math.min(SWITCH, this.poseT + dt);
    const shown = this.poseT < SWITCH / 2 ? this.poseFrom : this.poseTo;
    const swapSquash = rm ? 0 : 0.06 * Math.sin(Math.PI * this.poseT / SWITCH);

    // praten: wachtrij afspelen
    while (this.talkQ.length && this.talkQ[0].at <= t) {
      const k = this.talkQ.shift();
      this.talkMouth = k.m;
      if (k.stress && !rm) this.pulses.push({ t0: t, dur: 0.34, dy: 10, rot: 1.6 * F, brow: -12 });
    }
    if (this.talking && !this.talkQ.length && t > this.talkEnd) { this.talking = false; this.talkMouth = 'rest'; }

    // doelen
    const thinkFlip = s.think && Math.floor(t / 1.4) % 2 === 1;
    let bl = s.bl, br = s.br;
    if (thinkFlip) { bl = [s.br[0], -s.br[1]]; br = [s.bl[0], -s.bl[1]]; }
    const gl = this.glance;
    const target = {
      lean: s.lean * (s.ear ? this.ear : F) + (rm ? 0 : this.tiltTarget) + gl * 5 * F + (shown === 'wijzen' ? 3.5 : 0),
      dy: s.dy + gl * 8,
      bl0: bl[0] - gl * 8, bl1: bl[1], br0: br[0] - gl * 8, br1: br[1],
      open: this.talking ? LEVEL[this.talkMouth] / 3 : 0,
      foot: shown in POSE_FEET ? L.feet[1] - POSE_FEET[shown] : 0,
      aim: 20,
    };
    // wijzen: hoek naar het midden-links van het doelelement, gemeten vanaf de schouder op het scherm
    if (this.aimEl && this.aimEl.isConnected) {
      const m = this.svg.getScreenCTM();
      const r = this.aimEl.getBoundingClientRect();
      if (m && r.width) {
        const p = new DOMPoint(L.aim.pivot[0], L.aim.pivot[1]).matrixTransform(m);
        target.aim = clamp(Math.atan2(r.top + r.height / 2 - p.y, r.left + 40 - p.x) * 180 / Math.PI, AIM_MIN, AIM_MAX);
      }
    }
    for (const key in this.sp) {
      if (rm) { this.sp[key].x = target[key]; this.sp[key].v = 0; } else spring(this.sp[key], target[key], dt, key === 'foot' ? 400 : key === 'open' ? 260 : 150);
    }
    const sp = this.sp;

    // doorlopend leven: zweven, wiegen, ademen
    let lift = 0, rot = sp.lean.x, dy = sp.dy.x, sx = 1, sy = 1, browPulse = 0;
    if (!rm) {
      lift = s.float * 22 * (0.5 - 0.5 * Math.cos(t * 2 * Math.PI / 3.1));
      rot += s.float * 1.6 * Math.sin(t * 2 * Math.PI / 6.3);
      this.phase = (this.phase || 0) + dt / s.breathe;
      const breath = Math.sin(2 * Math.PI * this.phase);
      sy += 0.014 * breath; sx -= 0.006 * breath;
      dy += sp.open.x * 14; // praten: zakt iets door als de mond opengaat
      rot += sp.open.x * 1.2 * F;
      this.pulses = this.pulses.filter((p) => {
        const x = (t - p.t0) / p.dur;
        if (x >= 1) return false;
        if (p.fn) { rot += p.fn(x); return true; }
        const f = Math.sin(Math.PI * ease(x));
        dy += (p.dy || 0) * f; rot += (p.rot || 0) * f; browPulse += (p.brow || 0) * f;
        return true;
      });
      this.hops = this.hops.filter((h) => {
        const x = (t - h.t0) / h.dur;
        if (x >= 1) return false;
        const c = hopAt(x, h.h);
        lift += c.lift; sy *= c.sy; sx *= 1 + (1 - c.sy) * 0.7;
        return true;
      });
      sy *= 1 - swapSquash; sx *= 1 + swapSquash * 0.5;
    } else { this.pulses = []; this.hops = []; }

    const [fx, fy] = L.feet;
    this.rig.setAttribute('transform',
      `rotate(${rot.toFixed(3)} ${fx} ${fy}) translate(0 ${(dy - lift).toFixed(2)}) translate(${fx} ${fy}) scale(${sx.toFixed(4)} ${sy.toFixed(4)}) translate(${-fx} ${-fy}) translate(0 ${sp.foot.x.toFixed(2)})`);
    this.shadow.setAttribute('rx', Math.max(150, 300 - lift * 0.9 - dy * 0.4).toFixed(1));
    this.shadow.setAttribute('opacity', (0.55 * Math.max(0.35, 1 - lift / 300)).toFixed(3));

    if (shown !== this.shownPose) {
      for (const k in this.poseEls) this.poseEls[k].setAttribute('opacity', k === shown ? 1 : 0);
      this.waveArm.setAttribute('opacity', shown === 'zwaaien' ? 1 : 0);
      this.face.setAttribute('opacity', OWN_FACE[shown] ? 0 : 1);
      this.shownPose = shown;
    }
    if (shown === 'zwaaien') {
      const [px, py] = L.wave.pivot;
      this.waveArm.setAttribute('transform', `rotate(${rm ? 0 : (Math.sin(t * 11) * 12).toFixed(2)} ${px} ${py})`);
    }
    if (shown === 'wijzen') {
      const [px, py] = L.aim.pivot;
      this.aimArm.setAttribute('transform', `rotate(${(sp.aim.x - AIM_BASE + (rm ? 0 : Math.sin(t * 1.4) * 1.5)).toFixed(2)} ${px} ${py})`);
    }

    // mond: sprites wisselen hard (overvloeien geeft twee monden)
    let mouth = this.talking ? (rm ? 'small' : this.talkMouth) : s.mouth;
    if (this.forced?.mouth) mouth = this.forced.mouth;
    if (mouth !== this.shownMouth) {
      this.mouths[this.shownMouth].setAttribute('opacity', 0);
      this.mouths[mouth].setAttribute('opacity', 1);
      this.shownMouth = mouth;
    }

    // wenkbrauwen: gaan mee omhoog op de stem en bij nadruk
    const talkBrow = rm ? 0 : -10 * sp.open.x + browPulse;
    const brow = (g, box, lift, r) => {
      const cx = box.x + box.w / 2, cy = box.y + box.h / 2;
      g.setAttribute('transform', `translate(0 ${(lift + talkBrow).toFixed(2)}) rotate(${r.toFixed(2)} ${cx} ${cy})`);
    };
    brow(this.brows[0], L.browL, sp.bl0.x, sp.bl1.x);
    brow(this.brows[1], L.browR, sp.br0.x, sp.br1.x);

    // knipperen: 150 ms, om de 1,8 tot 4,5 s, soms dubbel
    let b = 0;
    if (!rm) {
      if (this.blinkT < 0 && t > this.nextBlink) this.blinkT = 0;
      if (this.blinkT >= 0) {
        this.blinkT += dt;
        const x = this.blinkT / 0.15;
        if (x >= 1) {
          this.blinkT = -1;
          this.double = !this.double && Math.random() < 0.2;
          this.nextBlink = t + (this.double ? 0.12 : rand(1.8, 4.5) * (s.ear ? 1.4 : 1));
        } else b = Math.sin(Math.PI * x);
      }
    }
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
