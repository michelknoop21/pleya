export type Spring = { x: number; v: number };

export const rand = (a: number, b: number) => a + Math.random() * (b - a);
export const ease = (x: number) => 0.5 - Math.cos(Math.PI * x) / 2;
export const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));

/** Slightly underdamped spring: transitions overshoot a fraction and settle without ringing. */
export function spring(s: Spring, target: number, dt: number, k = 150, z = 0.72) {
  s.v += ((target - s.x) * k - s.v * 2 * Math.sqrt(k) * z) * dt;
  s.x += s.v * dt;
}

/**
 * Hop with squash and stretch: crouch, stretch at take-off, parabola, flatten on landing.
 * Returns the lift in render units and the vertical scale; the caller widens the figure
 * to keep the volume roughly constant.
 */
export function hopAt(x: number, h: number) {
  const a = 0.16;
  const b = 0.72;
  if (x < a) return { lift: 0, sy: 1 - 0.12 * Math.sin((Math.PI / 2) * (x / a)) };
  if (x < b) {
    const v = (x - a) / (b - a);
    return { lift: h * 4 * v * (1 - v), sy: 1 + 0.09 * Math.cos(Math.PI * v) ** 2 };
  }
  const w = (x - b) / (1 - b);
  return { lift: 0, sy: 1 - 0.13 * Math.sin(Math.PI * w) * (1 - 0.4 * w) };
}

type Eye = { cx: number; cy: number; rx: number; ry: number };

/**
 * Blink: an upper lid in the face colour with a curved edge that follows the eyeball, and a
 * small lower lid that comes up to meet it. Returns [lid shapes, lash line]; both are
 * clipped to the eye ellipse by the caller.
 */
export function lidPath(e: Eye, b: number): [string, string] {
  const x0 = e.cx - e.rx - 2;
  const x1 = e.cx + e.rx + 2;
  const top = e.cy - e.ry - 30;
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
