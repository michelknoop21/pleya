/**
 * Toetsenbord en tijdweergave van de speler, los van de component zodat ze
 * zonder DOM te testen zijn.
 *
 * Spatie en `k` pauzeren, pijlen links en rechts springen tien seconden,
 * pijlen omhoog en omlaag zetten het volume, `f` wisselt volledig scherm, `m`
 * het geluid. Een toets die het gefocuste element zelf al afhandelt blijft
 * van dat element: spatie op een knop drukt die knop in, en de pijlen op de
 * schuifbalk verschuiven de schuifbalk.
 */

export type KeyAction =
  | { kind: 'toggle' }
  | { kind: 'seekBy'; seconds: number }
  | { kind: 'volumeBy'; delta: number }
  | { kind: 'fullscreen' }
  | { kind: 'mute' }
  | { kind: 'escape' };

export interface KeyInput {
  key: string;
  ctrlKey?: boolean;
  metaKey?: boolean;
  altKey?: boolean;
  /** Tag van het element met focus, in hoofdletters zoals `tagName`. */
  targetTag?: string;
  /** `type` van een gefocust `<input>`. */
  targetType?: string;
}

export const SEEK_STEP_S = 10;
export const VOLUME_STEP = 0.1;

export function keyAction(input: KeyInput): KeyAction | null {
  if (input.ctrlKey || input.metaKey || input.altKey) return null;
  const tag = input.targetTag ?? '';
  const onButton = tag === 'BUTTON' || tag === 'A' || tag === 'SELECT';
  const onRange = tag === 'INPUT' && input.targetType === 'range';
  const onText = (tag === 'INPUT' && !onRange) || tag === 'TEXTAREA';
  if (onText) return null;

  switch (input.key) {
    case ' ':
    case 'Spacebar':
      return onButton ? null : { kind: 'toggle' };
    case 'k':
    case 'K':
      return { kind: 'toggle' };
    case 'ArrowLeft':
      return onRange ? null : { kind: 'seekBy', seconds: -SEEK_STEP_S };
    case 'ArrowRight':
      return onRange ? null : { kind: 'seekBy', seconds: SEEK_STEP_S };
    case 'ArrowUp':
      return onRange ? null : { kind: 'volumeBy', delta: VOLUME_STEP };
    case 'ArrowDown':
      return onRange ? null : { kind: 'volumeBy', delta: -VOLUME_STEP };
    case 'f':
    case 'F':
      return { kind: 'fullscreen' };
    case 'm':
    case 'M':
      return { kind: 'mute' };
    case 'Escape':
      return { kind: 'escape' };
    default:
      return null;
  }
}

/** `1:06:41` of `4:05`; een onbekende tijd wordt `0:00`. */
export function formatPlayTime(seconds: number): string {
  const total = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** De afspeelsnelheden die de snelheidsknop doorloopt. */
export const SPEEDS = [1, 1.25, 1.5, 2, 0.5, 0.75] as const;

export function nextSpeed(current: number): number {
  const i = SPEEDS.findIndex((s) => Math.abs(s - current) < 0.001);
  return SPEEDS[(i + 1) % SPEEDS.length] ?? 1;
}
