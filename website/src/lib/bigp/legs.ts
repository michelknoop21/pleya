import { L } from './layers';

export type LegEls = { side: 'l' | 'r'; g: SVGElement; shin: SVGElement };

/** Distance covered per step, so the feet do not slide while he walks. */
export const STEP = L.h * 0.2;

type Gait = {
  /** how far the body floats above its standing height; the planted legs make this up */
  rise: number;
  /** 0 = standing, 1 = full stride */
  w: number;
  /** walk cycle in radians, one step per PI */
  phase: number;
  dir: 1 | -1;
  /** seconds, for the idle weight shift; null holds the legs still */
  t: number | null;
};

/**
 * Thigh turns at the hip, shin with shoe at the knee. Standing, the legs stretch so the feet
 * stay on the floor while the body floats; walking, each leg in turn lifts with a bent knee
 * while the other carries. Idle, the weight shifts slowly from one leg to the other.
 */
export function drawLegs(legs: LegEls[], { rise, w, phase, dir, t }: Gait) {
  for (const { side, g, shin } of legs) {
    const { hip, knee } = L.legs[side];
    const own = phase + (side === 'r' ? Math.PI : 0);
    const len = L.feet[1] - hip[1];
    const stepUp = w * Math.max(0, Math.sin(own));
    const idle = t === null ? 0 : (1 - w) * Math.max(0, Math.sin(t * 0.65 + (side === 'l' ? 0 : Math.PI))) * 0.08;
    const lifted = Math.max(stepUp, idle);
    const thigh = w * dir * 11 * Math.cos(own);
    const stretch = Math.max(0.7, (len + rise - lifted * 46) / len);
    g.setAttribute('transform', `translate(${hip[0]} ${hip[1]}) rotate(${thigh.toFixed(2)}) scale(1 ${stretch.toFixed(4)}) translate(${-hip[0]} ${-hip[1]})`);
    shin.setAttribute('transform', `rotate(${(-dir * 38 * lifted).toFixed(2)} ${knee[0]} ${knee[1]})`);
  }
}
