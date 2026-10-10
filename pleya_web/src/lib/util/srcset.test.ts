import { describe, expect, it } from 'vitest';

import { ARTWORK_SIZES_AVAILABLE, ladderStep, requestWidth } from './srcset';

describe('ladderStep', () => {
  it('kiest de kleinste trede die breedte maal dpr dekt', () => {
    expect(ladderStep(110, 2, 'poster')).toBe(240);
    expect(ladderStep(190, 2, 'poster')).toBe(480);
  });

  it('gebruikt de backdroptreden voor een backdrop', () => {
    expect(ladderStep(3000, 1, 'backdrop')).toBe(3840);
    expect(ladderStep(100, 1, 'backdrop')).toBe(480);
  });

  it('neemt een trede die precies gelijk is aan de behoefte, niet de volgende', () => {
    expect(ladderStep(240, 1, 'poster')).toBe(240);
    expect(ladderStep(241, 1, 'poster')).toBe(480);
    expect(ladderStep(480, 1, 'backdrop')).toBe(480);
  });

  it('geeft boven de top de top', () => {
    expect(ladderStep(9000, 1, 'backdrop')).toBe(3840);
    expect(ladderStep(9000, 1, 'poster')).toBe(1920);
  });
});

describe('requestWidth', () => {
  it('vraagt niets zolang de server geen formaten levert', () => {
    expect(ARTWORK_SIZES_AVAILABLE).toBe(false);
    expect(requestWidth(190, 2, 'poster')).toBeUndefined();
    expect(requestWidth(190, 2, 'poster', false)).toBeUndefined();
  });

  it('vraagt een trede wanneer de server formaten levert', () => {
    expect(requestWidth(190, 2, 'poster', true)).toBe(480);
  });

  it('vraagt het origineel voor een vlak dat nog niet gemeten is', () => {
    expect(requestWidth(0, 2, 'poster', true)).toBeUndefined();
  });

  it('vraagt het origineel bij een dpr van 0, ook als de server formaten levert', () => {
    expect(requestWidth(190, 0, 'poster', true)).toBeUndefined();
    expect(requestWidth(190, Number.NaN, 'poster', true)).toBeUndefined();
  });
});
