import { describe, expect, it, vi } from 'vitest';
import type { Item } from '../api/types';
import { videoContext } from './videoContext';

const episode: Item = { id: 'episode', kind: 'episode', title: 'Testing 1-2-3', parent_id: 'season', added_at: '' };
const season: Item = { id: 'season', kind: 'season', title: 'Season 38', parent_id: 'show', index: 38, added_at: '' };
const show: Item = { id: 'show', kind: 'show', title: 'The Simpsons', artwork: { poster_id: 'poster', backdrop_id: 'backdrop' }, summary: 'Series synopsis', added_at: '' };
const signal = () => new AbortController().signal;

describe('video context through authoritative parent IDs', () => {
  it('supplies the show and its artwork without replacing the playable episode', async () => {
    const read = vi.fn(async (id: string) => id === 'season' ? season : show);
    const result = await videoContext(episode, read, signal());
    expect(result).toEqual({ season, show });
    expect(episode.id).toBe('episode');
    expect(read.mock.calls.map(call => call[0])).toEqual(['season', 'show']);
  });
  it('resolves a season directly to its show', async () => {
    expect(await videoContext(season, async () => show, signal())).toEqual({ season, show });
  });
  it.each(['wrong-id', 'wrong-kind', 'unavailable'])('rejects a %s parent without hiding the episode', async failure => {
    const read = vi.fn(async () => {
      if (failure === 'unavailable') throw new Error('404');
      return { ...season, ...(failure === 'wrong-id' ? { id: 'someone-else' } : { kind: 'show' as const }) };
    });
    expect(await videoContext(episode, read, signal())).toEqual({});
    expect(read).toHaveBeenCalledTimes(1);
  });
  it('keeps the validated season when the show cannot be read', async () => {
    expect(await videoContext(episode, async id => {
      if (id === 'season') return season;
      throw new Error('403');
    }, signal())).toEqual({ season });
  });
  it('does not request ancestors for movies or after cancellation', async () => {
    const read = vi.fn();
    const controller = new AbortController(); controller.abort();
    expect(await videoContext(episode, read, controller.signal)).toEqual({});
    expect(await videoContext({ ...episode, kind: 'movie' }, read, signal())).toEqual({});
    expect(read).not.toHaveBeenCalled();
  });
});
