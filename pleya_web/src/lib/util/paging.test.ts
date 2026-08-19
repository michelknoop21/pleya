import { describe, expect, it, vi } from 'vitest';

import { emptyPager, loadNext } from './paging';
import { ApiError } from '../api/errors';
import type { Item, ItemPage } from '../api/types';

function item(id: string): Item {
  return { id, kind: 'movie', title: id, added_at: '2026-01-01T00:00:00Z' };
}

function page(ids: string[], next: string | null, total?: number): ItemPage {
  return {
    items: ids.map(item),
    next_cursor: next,
    ...(total === undefined ? {} : { total_estimate: total })
  };
}

describe('cursorpaginering', () => {
  it('voegt de volgende pagina achteraan toe en onthoudt de cursor', async () => {
    const controller = new AbortController();
    let state = emptyPager();

    const load = vi
      .fn()
      .mockResolvedValueOnce(page(['a', 'b'], 'c1', 120))
      .mockResolvedValueOnce(page(['c'], null));

    ({ next: state } = await loadNext(state, load, controller.signal));
    expect(state.items.map((i) => i.id)).toEqual(['a', 'b']);
    expect(state.cursor).toBe('c1');
    expect(state.totalEstimate).toBe(120);
    expect(state.done).toBe(false);

    ({ next: state } = await loadNext(state, load, controller.signal));
    expect(state.items.map((i) => i.id)).toEqual(['a', 'b', 'c']);
    expect(state.cursor).toBeNull();
    expect(state.done).toBe(true);
    // total_estimate ontbreekt op de tweede pagina en blijft dan staan.
    expect(state.totalEstimate).toBe(120);
  });

  it('stuurt de bewaarde cursor mee bij de volgende aanvraag', async () => {
    const controller = new AbortController();
    const load = vi
      .fn()
      .mockResolvedValueOnce(page(['a'], 'c1'))
      .mockResolvedValueOnce(page(['b'], null));

    let state = emptyPager();
    ({ next: state } = await loadNext(state, load, controller.signal));
    ({ next: state } = await loadNext(state, load, controller.signal));

    expect(load.mock.calls[0]?.[0]).toBeUndefined();
    expect(load.mock.calls[1]?.[0]).toBe('c1');
  });

  it('vraagt niets meer op de laatste pagina', async () => {
    const controller = new AbortController();
    const load = vi.fn().mockResolvedValue(page([], null));

    let state = emptyPager();
    ({ next: state } = await loadNext(state, load, controller.signal));
    expect(state.done).toBe(true);

    ({ next: state } = await loadNext(state, load, controller.signal));
    expect(load).toHaveBeenCalledTimes(1);
  });

  it('begint opnieuw wanneer de cursor bij een andere sortering hoort', async () => {
    const controller = new AbortController();
    const load = vi
      .fn()
      .mockResolvedValueOnce(page(['a'], 'c1'))
      .mockRejectedValueOnce(
        new ApiError({
          code: 'library.cursor_invalid',
          message: 'wrong sort',
          status: 400,
          retryable: false
        })
      );

    let state = emptyPager();
    ({ next: state } = await loadNext(state, load, controller.signal));

    const result = await loadNext(state, load, controller.signal);
    expect(result.restarted).toBe(true);
    expect(result.next.items).toEqual([]);
    expect(result.next.cursor).toBeNull();
    expect(result.next.error).toBeNull();
  });

  it('houdt een andere fout vast in plaats van de lijst weg te gooien', async () => {
    const controller = new AbortController();
    const load = vi
      .fn()
      .mockResolvedValueOnce(page(['a'], 'c1'))
      .mockRejectedValueOnce(
        new ApiError({
          code: 'storage.unavailable',
          message: 'down',
          status: 503,
          retryable: true
        })
      );

    let state = emptyPager();
    ({ next: state } = await loadNext(state, load, controller.signal));
    ({ next: state } = await loadNext(state, load, controller.signal));

    expect(state.items.map((i) => i.id)).toEqual(['a']);
    expect(state.error).toBeInstanceOf(ApiError);
    expect(state.loading).toBe(false);
  });
});
