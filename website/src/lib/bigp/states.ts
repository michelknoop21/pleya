import type { Mouth, Pose } from './layers';

/**
 * A stance of Big P. `bl`/`br` are [lift, rotation] per brow (negative lift = up; negative
 * rotation on the left brow raises its inner end). `lean` is degrees around the feet,
 * positive = toward the content. `dy` sinks the figure, `float` scales the idle sway.
 */
export type State = {
  bl: [number, number];
  br: [number, number];
  mouth: Mouth;
  lean: number;
  dy: number;
  float: number;
  /** seconds per breath */
  breathe: number;
  pose: Pose;
  /** tilts the head from side to side, as if listening */
  ear?: boolean;
  /** the brows swap every 1.4 s, as if weighing something */
  think?: boolean;
};

export const STATES = {
  idle: { bl: [0, 0], br: [0, 0], mouth: 'rest', lean: 0, dy: 0, float: 1, breathe: 3.4, pose: 'rest' },
  listening: { bl: [-20, -3], br: [-20, 3], mouth: 'o', lean: 4, dy: 10, float: 0.7, breathe: 4.2, pose: 'rest', ear: true },
  working: { bl: [-16, 3], br: [4, 5], mouth: 'rest', lean: 3.5, dy: 4, float: 0.6, breathe: 3.4, pose: 'rest', think: true },
  success: { bl: [-24, 0], br: [-24, 0], mouth: 'laugh', lean: 0, dy: 0, float: 1.2, breathe: 3.0, pose: 'duim_presenteren' },
  worried: { bl: [-14, -16], br: [-14, 16], mouth: 'o', lean: -1.5, dy: 18, float: 0.35, breathe: 5.0, pose: 'rest' },
  attentive: { bl: [-10, 0], br: [-10, 0], mouth: 'rest', lean: 3, dy: 6, float: 0.5, breathe: 4.4, pose: 'rest' },
} satisfies Record<string, State>;

export type StateName = keyof typeof STATES;

/** How far each mouth sprite is open, 0..3. Talking opens at most one level per step. */
export const LEVEL: Record<Mouth, number> = { rest: 0, small: 1, e: 1, o: 1, mid: 2, big: 3, laugh: 3 };
