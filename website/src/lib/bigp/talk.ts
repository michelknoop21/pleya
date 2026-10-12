import type { Mouth } from './layers';

export type MouthKey = { at: number; m: Mouth; stress?: boolean };

/**
 * Mouth shapes for one word, starting at `from` seconds: syllables from the vowel groups, per
 * syllable first 'small', then the vowel shape, then half closed, so the mouth opens at most
 * one level per step. Long words and words that start with a capital get a stressed first
 * syllable.
 */
export function planWord(word: string, from: number, calm = false): { keys: MouthKey[]; dur: number; end: number } {
  const groups = word.toLowerCase().match(/[aeiouyáéëïóöü]+/g) || ['a'];
  const dur = Math.max(0.22, groups.length * (calm ? 0.2 : 0.17));
  const stress = !calm && (word.replace(/\W/g, '').length >= 7 || /^[A-Z0-9]/.test(word));
  const step = dur / groups.length;
  const keys: MouthKey[] = [];
  let at = from;
  groups.forEach((g, i) => {
    let m: Mouth = /^(oe|oo|o|u|uu|ou|au|ui)$/.test(g) ? 'o' : /^(i|ie|ee|e|ij|ei|y|eu)$/.test(g) ? 'e' : stress && i === 0 ? 'big' : 'mid';
    if (calm && m === 'big') m = 'mid';
    keys.push({ at, m: 'small' }, { at: at + step * 0.25, m, stress: stress && i === 0 }, { at: at + step * 0.75, m: 'small' });
    at += step;
  });
  return { keys, dur, end: at };
}
