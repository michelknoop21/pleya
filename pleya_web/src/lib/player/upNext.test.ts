import { describe, expect, it, vi } from 'vitest';

import type { Item, ItemPage } from '../api/types';
import { nextCountdown, nextEpisode, type ChildrenReader } from './upNext';

const item = (id: string, kind: Item['kind'], index: number, parent_id?: string): Item =>
  ({ id, kind, index, title: id, added_at: '2026-01-01T00:00:00Z', ...(parent_id ? { parent_id } : {}) });

const season1 = item('s1', 'season', 1, 'show');
const season2 = item('s2', 'season', 2, 'show');
const tree: Record<string, Item[]> = {
  show: [season2, season1],
  s1: [item('e2', 'episode', 2, 's1'), item('e1', 'episode', 1, 's1')],
  s2: [item('f2', 'episode', 2, 's2'), item('f1', 'episode', 1, 's2')]
};
const reader = (): ChildrenReader => vi.fn(async (id) => ({ items: tree[id] ?? [] }) as ItemPage);

describe('volgende aflevering', () => {
  it('neemt de volgende in het seizoen, op nummer en niet op volgorde van het antwoord', async () => {
    const children = reader();
    expect((await nextEpisode(children, tree['s1']![1]!, season1))?.id).toBe('e2');
    expect(children).toHaveBeenCalledTimes(1);
  });

  it('gaat op de seizoensgrens naar de eerste aflevering van het volgende seizoen', async () => {
    expect((await nextEpisode(reader(), tree['s1']![0]!, season1))?.id).toBe('f1');
  });

  it('geeft niets na de laatste aflevering van de serie, en niets voor een film', async () => {
    expect(await nextEpisode(reader(), tree['s2']![0]!, season2)).toBeNull();
    const children = reader();
    expect(await nextEpisode(children, item('m', 'movie', 1), undefined)).toBeNull();
    expect(children).not.toHaveBeenCalled();
  });

  it('leest alle pagina\'s van een lang seizoen', async () => {
    const children: ChildrenReader = vi.fn(async (_id, query) =>
      (query.cursor ? { items: [item('e2', 'episode', 2, 's1')] } : { items: [item('e1', 'episode', 1, 's1')], next_cursor: 'c' }) as ItemPage);
    expect((await nextEpisode(children, item('e1', 'episode', 1, 's1'), undefined))?.id).toBe('e2');
  });
});

describe('aftellen in het eindvenster', () => {
  it('begint dertig seconden voor het einde op twintig en staat tien seconden voor het einde op nul', () => {
    expect(nextCountdown(100, 3000)).toBeNull();
    expect(nextCountdown(2969, 3000)).toBeNull();
    expect(nextCountdown(2970, 3000)).toBe(20);
    expect(nextCountdown(2983, 3000)).toBe(7);
    expect(nextCountdown(2990, 3000)).toBe(0);
    expect(nextCountdown(3000, 3000)).toBe(0);
  });

  it('telt niet af bij een onbekende duur of een fragment korter dan het venster', () => {
    expect(nextCountdown(5, 0)).toBeNull();
    expect(nextCountdown(5, 20)).toBeNull();
    expect(nextCountdown(5, Number.NaN)).toBeNull();
  });
});
