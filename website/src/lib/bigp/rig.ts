// Big P as layers, alive: one <svg> per figure with a single rig group. All motion is a
// transform on that group plus the legs, the aiming arm, the brows and the eyelids, driven by
// springs. Ported from the motion prototype (docs/assets/tvos-unified/src/prototype/38-big-p-motion)
// with the rigged legs and walk cycle of the video template added.
import { L, LATER, OWN_FACE, POSE_FEET, type ImagePose, type Mouth, type Pose } from './layers';
import { wake, type Ticker } from './loop';
import { drawLegs, STEP, type LegEls } from './legs';
import { buildSvg, preload } from './markup';
import { clamp, ease, hopAt, lidPath, rand, spring, type Spring } from './math';
import { LEVEL, STATES, type State, type StateName } from './states';
import { planWord, type MouthKey } from './talk';

const AIM_BASE = (Math.atan2(L.aim.tip[1] - L.aim.pivot[1], L.aim.tip[0] - L.aim.pivot[0]) * 180) / Math.PI;
// Higher and the hand slides behind the bowl of the P, lower and it reaches the leg.
const AIM_MIN = -12;
const AIM_MAX = 60;
// Seconds a pose change takes. No crossfade (that gives ghost arms): the image swaps halfway
// while the body squashes.
const SWITCH = 0.27;
const WALK_FULL = L.h * 0.18; // units per second at which the stride is fully shown

type Pulse = { t0: number; dur: number; dy?: number; rot?: number; brow?: number; fn?: (x: number) => number };
type Walk = { from: number; dur: number; t: number; done: () => void };
export type Options = { /** which side the content is on: 1 = right of Big P, -1 = left */ facing?: 1 | -1 };

let count = 0;

export class BigP implements Ticker {
  visible = true;
  state: StateName = 'idle';
  readonly facing: 1 | -1;
  private s: State = STATES.idle;
  private t = 0;
  private svg: SVGSVGElement;
  private stage: SVGGElement;
  private rig: SVGGElement;
  private shadow: SVGElement;
  private face: SVGElement;
  private legsEl: SVGElement;
  private legEls: LegEls[];
  private aimArm: SVGElement;
  private waveArm: SVGElement;
  private poseEls: Record<Pose, SVGElement>;
  private mouths: Record<string, SVGElement>;
  private lids: SVGElement[];
  private lashes: SVGElement[];
  private brows: SVGElement[];
  private ready = new Set<Pose>(['rest']);
  private pending = new Map<Pose, Promise<void>>();
  private sp: Record<'lean' | 'dy' | 'aim' | 'foot' | 'bl0' | 'bl1' | 'br0' | 'br1' | 'open', Spring>;
  private pulses: Pulse[] = [];
  private hops: { t0: number; dur: number; h: number }[] = [];
  private talkQ: MouthKey[] = [];
  private talking = false;
  private talkMouth: Mouth = 'rest';
  private talkEnd = 0;
  private ear = 1;
  private nextEar = 0;
  private tiltTarget = 0;
  private nextTilt = rand(1, 3);
  private nextBlink = rand(1, 3);
  private blinkT = -1;
  private double = false;
  private phase = 0;
  private gesturePose: Pose | null = null;
  private gestureUntil = 0;
  private poseFrom: Pose = 'rest';
  private poseTo: Pose = 'rest';
  private poseT = SWITCH;
  private shownPose: Pose | null = null;
  private shownMouth: Mouth = 'rest';
  private aimEl: Element | null = null;
  private walk: Walk | null = null;
  private walkX = 0;
  private walkPhase = 0;
  private walkAmt = 0;
  private walkDir: 1 | -1 = 1;
  private back: ReturnType<typeof setTimeout> | undefined;

  constructor(private host: HTMLElement, { facing = 1 }: Options = {}) {
    host.insertAdjacentHTML('beforeend', buildSvg(count++));
    const q = <T extends SVGElement>(sel: string) => host.querySelector<T>(sel)!;
    const qa = (sel: string) => [...host.querySelectorAll<SVGElement>(sel)];
    this.svg = q<SVGSVGElement>('svg');
    this.stage = q<SVGGElement>('.bigp-stage');
    this.rig = q<SVGGElement>('.rig');
    this.shadow = q('.shadow');
    this.face = q('.face');
    this.legsEl = q('.legs');
    this.legEls = qa('.leg').map((g) => ({ side: g.dataset.side as 'l' | 'r', g, shin: g.querySelector<SVGElement>('.shin')! }));
    this.aimArm = q('.aimarm');
    this.waveArm = q('.wavearm');
    this.poseEls = { rest: q('.p-rest'), wijzen: q('.p-wijzen') } as Record<Pose, SVGElement>;
    for (const p of Object.keys(POSE_FEET) as ImagePose[]) this.poseEls[p] = q(`.p-${p}`);
    this.mouths = Object.fromEntries(qa('.mouth').map((m) => [m.dataset.m!, m]));
    this.lids = qa('.lid');
    this.lashes = qa('.lash');
    this.brows = qa('.brow');
    this.facing = facing;
    const s0 = (): Spring => ({ x: 0, v: 0 });
    this.sp = { lean: s0(), dy: s0(), aim: { x: 20, v: 0 }, foot: s0(), bl0: s0(), bl1: s0(), br0: s0(), br1: s0(), open: s0() };
  }

  /** Remove the figure from the page. */
  destroy() {
    clearTimeout(this.back);
    this.svg.remove();
  }

  /** Fetch a pose that is not part of the first paint. It is shown only after this resolves. */
  ensure(pose: Pose): Promise<void> {
    if (pose === 'rest' || this.ready.has(pose)) return Promise.resolve();
    let p = this.pending.get(pose);
    if (!p) {
      const srcs = LATER[pose];
      p = Promise.all(srcs.map(preload)).then(() => {
        for (const src of srcs) this.host.querySelectorAll(`image[data-later="${src}"]`).forEach((el) => el.setAttribute('href', src));
        this.ready.add(pose);
        wake();
      });
      // A layer that fails to load leaves him in the pose he had.
      p.catch(() => {});
      this.pending.set(pose, p);
    }
    return p;
  }

  // ---------- stances and gestures ----------
  set(name: StateName) {
    clearTimeout(this.back); // a pending settle() belongs to the stance that is being replaced
    this.state = name;
    this.s = STATES[name];
    wake();
  }
  gesture(pose: Pose, ms: number) {
    this.gesturePose = pose;
    this.gestureUntil = this.t + ms / 1000;
  }
  /** Nod: dips and bends toward the content. */
  nod(amp = 1, dur = 520) {
    this.pulses.push({ t0: this.t, dur: dur / 1000, dy: 16 * amp, rot: 2.2 * amp * this.facing });
  }
  /** Shake the head: two to three times left and right, fading out. */
  shake() {
    this.pulses.push({ t0: this.t, dur: 1.3, fn: (x) => 5.5 * Math.sin(2 * Math.PI * 2.5 * x) * (1 - x) });
  }
  hop(h = 110, dur = 0.72) {
    this.hops.push({ t0: this.t, dur, h });
  }
  /** Point at an element; the arm follows it through a spring. `null` lowers the arm. */
  aimAt(el: Element | null) {
    this.aimEl = el;
    if (el) void this.ensure(this.facing > 0 ? 'wijzen' : 'wijzen_links').catch(() => {});
  }
  /** A new thing to look at: the head turns with it and the brows go up for a moment. */
  follow(el: Element) {
    this.aimAt(el);
    this.pulses.push({ t0: this.t, dur: 0.45, dy: 6, rot: 2.5 * this.facing, brow: -10 });
  }
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
  /** Return to idle after a success or an attentive moment. */
  settle(ms = 900) {
    clearTimeout(this.back);
    this.back = setTimeout(() => {
      if (this.state === 'success' || this.state === 'attentive') this.set('idle');
    }, ms);
  }
  /**
   * Walk in from `from` render units to the side (positive = from the right) and stop on the
   * mark. Resolves on arrival; with reduced motion he simply stands there.
   */
  walkIn(from: number, dur = 1.9): Promise<void> {
    this.walkX = from;
    this.stage.setAttribute('transform', `translate(${from} 0)`);
    return new Promise((done) => {
      this.walk = { from, dur, t: 0, done };
    });
  }

  // ---------- talking ----------
  /** Queue the mouth shapes for one word. Returns how long the word takes, in ms. */
  speak(word: string, calm = false): number {
    const from = Math.max(this.t, this.talkQ.length ? this.talkQ[this.talkQ.length - 1].at : 0);
    const { keys, dur, end } = planWord(word, from, calm);
    this.talkQ.push(...keys);
    this.talking = true;
    this.talkEnd = end + 0.3;
    return dur * 1000;
  }
  /** End of the sentence: mouth closed. */
  hush() {
    this.talkQ = [];
    this.talkMouth = 'rest';
    this.talkEnd = this.t + 0.12;
  }

  // ---------- per frame ----------
  private autos() {
    const t = this.t;
    if (t > this.nextTilt) {
      this.tiltTarget = rand(-2.6, 2.6);
      this.nextTilt = t + rand(2.2, 4.5);
    }
    if (this.s.ear && t > this.nextEar) {
      this.ear = -this.ear;
      this.nextEar = t + rand(2.5, 4);
    }
  }

  private wantedPose(): Pose {
    if (this.walk) return 'rest'; // only the rest body has legs that can step
    if (this.gesturePose && this.t > this.gestureUntil) this.gesturePose = null;
    const want = this.gesturePose ?? (this.aimEl?.isConnected ? (this.facing > 0 ? 'wijzen' : 'wijzen_links') : this.s.pose);
    if (this.ready.has(want)) return want;
    void this.ensure(want).catch(() => {});
    return this.poseTo;
  }

  private stepWalk(dt: number) {
    const k = this.walk;
    if (!k) return;
    k.t += dt;
    const p = clamp(k.t / k.dur, 0, 1);
    const x = k.from * (1 - p * p * (3 - 2 * p));
    const dx = x - this.walkX;
    this.walkX = x;
    this.walkPhase += (Math.abs(dx) / STEP) * Math.PI;
    this.walkAmt = dt > 0 ? clamp(Math.abs(dx) / dt / WALK_FULL, 0, 1) : 0;
    if (dx) this.walkDir = dx < 0 ? -1 : 1;
    if (p >= 1) {
      this.walk = null;
      this.walkAmt = 0;
      this.walkX = 0;
      k.done();
    }
  }

  tick(dt: number, rm: boolean) {
    this.t += dt;
    const t = this.t;
    const s = this.s;
    const F = this.facing;
    if (!rm) this.autos();
    if (rm && this.walk) this.walk.t = this.walk.dur;
    this.stepWalk(dt);
    const w = this.walkAmt;

    const want = this.wantedPose();
    if (want !== this.poseTo) {
      this.poseFrom = this.poseT < SWITCH / 2 ? this.poseFrom : this.poseTo;
      this.poseTo = want;
      this.poseT = rm ? SWITCH : 0;
    }
    this.poseT = Math.min(SWITCH, this.poseT + dt);
    const shown = this.poseT < SWITCH / 2 ? this.poseFrom : this.poseTo;
    const rigged = shown === 'rest' || shown === 'wijzen';
    const swapSquash = rm ? 0 : 0.06 * Math.sin((Math.PI * this.poseT) / SWITCH);

    while (this.talkQ.length && this.talkQ[0].at <= t) {
      const k = this.talkQ.shift()!;
      this.talkMouth = k.m;
      if (k.stress && !rm) this.pulses.push({ t0: t, dur: 0.34, dy: 10, rot: 1.6 * F, brow: -12 });
    }
    if (this.talking && !this.talkQ.length && t > this.talkEnd) {
      this.talking = false;
      this.talkMouth = 'rest';
    }

    const flip = s.think && Math.floor(t / 1.4) % 2 === 1;
    const bl = flip ? [s.br[0], -s.br[1]] : s.bl;
    const br = flip ? [s.bl[0], -s.bl[1]] : s.br;
    const target = {
      lean: s.lean * (s.ear ? this.ear : F) + (rm ? 0 : this.tiltTarget) + (shown === 'wijzen' ? 3.5 : 0),
      dy: s.dy,
      bl0: bl[0], bl1: bl[1], br0: br[0], br1: br[1],
      open: this.talking ? LEVEL[this.talkMouth] / 3 : 0,
      foot: rigged ? 0 : L.feet[1] - POSE_FEET[shown as ImagePose],
      aim: this.aimTarget(),
    };
    for (const key of Object.keys(this.sp) as (keyof typeof this.sp)[]) {
      if (rm) this.sp[key] = { x: target[key], v: 0 };
      else spring(this.sp[key], target[key], dt, key === 'foot' ? 400 : key === 'open' ? 260 : 150);
    }
    const sp = this.sp;

    // Continuous life: float, sway and breathing, replaced by the stride while he walks.
    let float = 0, air = 0, rot = sp.lean.x, dy = sp.dy.x, sx = 1, sy = 1, browPulse = 0;
    if (!rm) {
      float = s.float * 22 * (0.5 - 0.5 * Math.cos((t * 2 * Math.PI) / 3.1)) * (1 - w) + w * Math.abs(Math.sin(this.walkPhase)) * 22;
      rot += s.float * 1.6 * Math.sin((t * 2 * Math.PI) / 6.3) * (1 - w) + w * (this.walkDir * 4 + Math.sin(this.walkPhase) * 3);
      this.phase += dt / s.breathe;
      const breath = Math.sin(2 * Math.PI * this.phase);
      sy += 0.014 * breath;
      sx -= 0.006 * breath;
      dy += sp.open.x * 14; // talking: he dips a little as the mouth opens
      rot += sp.open.x * 1.2 * F;
      this.pulses = this.pulses.filter((p) => {
        const x = (t - p.t0) / p.dur;
        if (x >= 1) return false;
        if (p.fn) rot += p.fn(x);
        else {
          const f = Math.sin(Math.PI * ease(x));
          dy += (p.dy || 0) * f;
          rot += (p.rot || 0) * f;
          browPulse += (p.brow || 0) * f;
        }
        return true;
      });
      this.hops = this.hops.filter((h) => {
        const x = (t - h.t0) / h.dur;
        if (x >= 1) return false;
        const c = hopAt(x, h.h);
        air += c.lift;
        sy *= c.sy;
        sx *= 1 + (1 - c.sy) * 0.7;
        return true;
      });
      sy *= 1 - swapSquash;
      sx *= 1 + swapSquash * 0.5;
    } else {
      this.pulses = [];
      this.hops = [];
    }
    // The pose images carry their own legs, so they float as a whole; the rigged legs stay planted.
    if (!rigged) air += float * 0.3;
    const up = rigged ? float + air : air;

    const [fx, fy] = L.feet;
    this.stage.setAttribute('transform', `translate(${this.walkX.toFixed(1)} 0)`);
    this.rig.setAttribute(
      'transform',
      `rotate(${rot.toFixed(3)} ${fx} ${fy}) translate(0 ${(dy - up).toFixed(2)}) translate(${fx} ${fy}) scale(${sx.toFixed(4)} ${sy.toFixed(4)}) translate(${-fx} ${-fy}) translate(0 ${sp.foot.x.toFixed(2)})`,
    );
    this.shadow.setAttribute('rx', Math.max(150, 300 - air * 0.9 - dy * 0.4).toFixed(1));
    this.shadow.setAttribute('opacity', (0.55 * Math.max(0.35, 1 - air / 300)).toFixed(3));

    if (shown !== this.shownPose) {
      for (const k of Object.keys(this.poseEls) as Pose[]) this.poseEls[k].setAttribute('opacity', k === shown ? '1' : '0');
      this.waveArm.setAttribute('opacity', shown === 'zwaaien' ? '1' : '0');
      this.face.setAttribute('opacity', OWN_FACE[shown] ? '0' : '1');
      this.legsEl.setAttribute('opacity', rigged ? '1' : '0');
      this.shownPose = shown;
    }
    if (rigged) drawLegs(this.legEls, { rise: float - dy, w, phase: this.walkPhase, dir: this.walkDir, t: rm ? null : t });
    if (shown === 'zwaaien') {
      const [px, py] = L.wave.pivot;
      this.waveArm.setAttribute('transform', `rotate(${rm ? 0 : (Math.sin(t * 11) * 12).toFixed(2)} ${px} ${py})`);
    }
    if (shown === 'wijzen') {
      const [px, py] = L.aim.pivot;
      this.aimArm.setAttribute('transform', `rotate(${(sp.aim.x - AIM_BASE + (rm ? 0 : Math.sin(t * 1.4) * 1.5)).toFixed(2)} ${px} ${py})`);
    }

    // Mouth sprites swap hard: a crossfade shows two mouths.
    const mouth: Mouth = this.talking ? (rm ? 'small' : this.talkMouth) : s.mouth;
    if (mouth !== this.shownMouth) {
      this.mouths[this.shownMouth].setAttribute('opacity', '0');
      this.mouths[mouth].setAttribute('opacity', '1');
      this.shownMouth = mouth;
    }

    const talkBrow = rm ? 0 : -10 * sp.open.x + browPulse;
    this.drawBrow(this.brows[0], L.browL, sp.bl0.x + talkBrow, sp.bl1.x);
    this.drawBrow(this.brows[1], L.browR, sp.br0.x + talkBrow, sp.br1.x);
    this.drawLids(rm ? 0 : this.blink(dt));
  }

  /** Arm direction toward the near side of the target element, measured from the shoulder on screen. */
  private aimTarget(): number {
    const el = this.aimEl;
    if (!el?.isConnected) return 20;
    const m = this.svg.getScreenCTM();
    const r = el.getBoundingClientRect();
    if (!m || !r.width) return 20;
    const p = new DOMPoint(L.aim.pivot[0], L.aim.pivot[1]).matrixTransform(m);
    const tx = r.left + Math.min(40, r.width * 0.2);
    return clamp((Math.atan2(r.top + r.height / 2 - p.y, tx - p.x) * 180) / Math.PI, AIM_MIN, AIM_MAX);
  }

  private drawBrow(g: SVGElement, box: { x: number; y: number; w: number; h: number }, lift: number, r: number) {
    g.setAttribute('transform', `translate(0 ${lift.toFixed(2)}) rotate(${r.toFixed(2)} ${box.x + box.w / 2} ${box.y + box.h / 2})`);
  }

  /** Blink: 150 ms, every 1.8 to 4.5 s, sometimes twice. Returns how far the lids are shut, 0..1. */
  private blink(dt: number): number {
    if (this.blinkT < 0 && this.t > this.nextBlink) this.blinkT = 0;
    if (this.blinkT < 0) return 0;
    this.blinkT += dt;
    const x = this.blinkT / 0.15;
    if (x < 1) return Math.sin(Math.PI * x);
    this.blinkT = -1;
    this.double = !this.double && Math.random() < 0.2;
    this.nextBlink = this.t + (this.double ? 0.12 : rand(1.8, 4.5) * (this.s.ear ? 1.4 : 1));
    return 0;
  }

  private drawLids(b: number) {
    L.eyes.forEach((e, i) => {
      const [lid, lash] = b > 0.02 ? lidPath(e, b) : ['', ''];
      this.lids[i].setAttribute('d', lid);
      this.lashes[i].setAttribute('d', lash);
      this.lashes[i].setAttribute('opacity', Math.min(1, b * 1.6).toFixed(2));
    });
  }
}
