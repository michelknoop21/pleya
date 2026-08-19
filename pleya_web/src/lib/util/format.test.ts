import { describe, expect, it } from 'vitest';

import { artworkAspect, formatDate, formatDuration, itemSubtitle } from './format';
import type { Item } from '../api/types';

function item(patch: Partial<Item>): Item {
  return {
    id: 'x',
    kind: 'movie',
    title: 'T',
    added_at: '2026-01-01T00:00:00Z',
    ...patch
  } as Item;
}

describe('duur', () => {
  it('rekent milliseconden om en nooit seconden', () => {
    expect(formatDuration(5_400_000)).toBe('1h 30m');
    expect(formatDuration(2_700_000)).toBe('45m');
  });

  it('toont seconden onder de minuut, want "0m" leest als onbekend', () => {
    expect(formatDuration(2_000)).toBe('2s');
    expect(formatDuration(59_000)).toBe('59s');
    expect(formatDuration(60_000)).toBe('1m');
  });

  it('geeft niets terug voor nul, negatief of ontbrekend', () => {
    expect(formatDuration(0)).toBeNull();
    expect(formatDuration(-1)).toBeNull();
    expect(formatDuration(null)).toBeNull();
    expect(formatDuration(undefined)).toBeNull();
  });
});

describe('datum', () => {
  it('leest RFC 3339 in UTC', () => {
    expect(formatDate('2026-08-19T12:00:00Z')).toContain('2026');
  });

  it('geeft niets terug voor onzin', () => {
    expect(formatDate('niet een datum')).toBeNull();
    expect(formatDate(null)).toBeNull();
  });
});

describe('de tweede regel onder een kaart', () => {
  it('toont het jaar bij een film', () => {
    expect(itemSubtitle(item({ kind: 'movie', year: 1978 }))).toBe('1978');
  });

  it('toont het aantal seizoenen bij een serie, met de juiste enkelvoudsvorm', () => {
    expect(itemSubtitle(item({ kind: 'show', child_count: 4 }))).toBe('4 seasons');
    expect(itemSubtitle(item({ kind: 'show', child_count: 1 }))).toBe('1 season');
  });

  it('doet hetzelfde voor afleveringen onder een seizoen', () => {
    expect(itemSubtitle(item({ kind: 'season', child_count: 1 }))).toBe('1 episode');
    expect(itemSubtitle(item({ kind: 'season', child_count: 12 }))).toBe('12 episodes');
  });

  it('toont het afleveringsnummer bij een aflevering', () => {
    expect(itemSubtitle(item({ kind: 'episode', index: 3 }))).toBe('Episode 3');
  });

  it('verzint niets wanneer het veld ontbreekt', () => {
    expect(itemSubtitle(item({ kind: 'movie' }))).toBeNull();
    expect(itemSubtitle(item({ kind: 'episode' }))).toBeNull();
  });
});

describe('verhouding van het beeld', () => {
  it('geeft een aflevering 16:9 en de rest een poster', () => {
    expect(artworkAspect('episode')).toBe('wide');
    expect(artworkAspect('movie')).toBe('poster');
    expect(artworkAspect('show')).toBe('poster');
    expect(artworkAspect('season')).toBe('poster');
  });
});
