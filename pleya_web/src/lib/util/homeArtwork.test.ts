import { describe, expect, it, vi } from 'vitest';
import type { Item } from '../api/types';
import { continueArtwork, dedupeReader, episodeCard, episodeCards, homeHero } from './homeArtwork';

const media = (id: string, kind: Item['kind'], extra: Partial<Item> = {}): Item => ({
  id, kind, title: id, added_at: '2026-11-02T12:00:00Z', ...extra
});
const signal = () => new AbortController().signal;
const episode = media('episode', 'episode', { parent_id: 'season', artwork: { poster_id: 'episode-still', backdrop_id: 'random-looking-still' } });
const season = media('season', 'season', { parent_id: 'show', artwork: { poster_id: 'season-cover' } });
const show = media('show', 'show', { title: 'Two and a Half Men', artwork: { poster_id: 'series-cover' } });

describe('Home artwork identity', () => {
  it('uses the series cover without replacing episode identity or watch state', async () => {
    const read = vi.fn(async (id: string) => id === 'season' ? season : show);
    const result = await continueArtwork([episode], read, signal());
    expect(result.get('episode')).toEqual({ posterId: 'series-cover', title: 'Two and a Half Men' });
    expect(episode.id).toBe('episode');
    expect(read.mock.calls.map(args => args[0])).toEqual(['season', 'show']);
  });
  it('shares ancestor requests within one load, never across profiles or loads', async () => {
    const read = vi.fn(async (id: string) => id === 'season' ? season : show);
    await continueArtwork([episode, { ...episode, id: 'second' }], read, signal());
    expect(read).toHaveBeenCalledTimes(2);
    await continueArtwork([episode], read, signal());
    expect(read).toHaveBeenCalledTimes(4);
  });
  it('keeps a season cover when the series is inaccessible', async () => {
    const result = await continueArtwork([episode], async id => {
      if (id === 'season') return season;
      throw new Error('404');
    }, signal());
    expect(result.get('episode')?.posterId).toBe('season-cover');
  });
  it('never substitutes a still or a response for another parent', async () => {
    const read = vi.fn(async () => media('wrong-id', 'season', { artwork: { poster_id: 'wrong-cover' } }));
    const result = await continueArtwork([episode], read, signal());
    expect(result.get('episode')?.posterId).toBeNull();
    expect(read).toHaveBeenCalledTimes(1);
  });
  it('does not resolve ancestors for movies or after cancellation', async () => {
    const read = vi.fn();
    const controller = new AbortController(); controller.abort();
    await continueArtwork([episode], read, controller.signal);
    const movie = media('movie', 'movie', { artwork: { poster_id: 'film-cover' } });
    expect((await continueArtwork([movie], read, signal())).get('movie')?.posterId).toBe('film-cover');
    expect(read).not.toHaveBeenCalled();
  });
  it('prefers a recent title with a real backdrop, keeping the whole item together', () => {
    const posterOnly = media('first', 'movie', { artwork: { poster_id: 'poster' } });
    const featured = media('second', 'movie', { artwork: { backdrop_id: 'background' } });
    expect(homeHero([posterOnly, featured])).toBe(featured);
    expect(homeHero([posterOnly])).toBe(posterOnly);
    expect(homeHero([])).toBeUndefined();
  });
});

describe('Episode cards in rails', () => {
  const bare = media('bare', 'episode', { parent_id: 'season', index: 5, title: 'TBA' });
  const numbered = { ...season, index: 1 };
  const wideShow = { ...show, artwork: { poster_id: 'series-cover', backdrop_id: 'series-backdrop' } };
  it('falls back from the episode image to the series backdrop, then the series poster', () => {
    expect(episodeCard(episode, 'wide', numbered, wideShow).artworkId).toBe('random-looking-still');
    expect(episodeCard(bare, 'wide', numbered, wideShow)).toEqual({ artworkId: 'series-backdrop', title: 'Two and a Half Men', subtitle: 'S1 · E5' });
    expect(episodeCard(bare, 'wide', numbered, show).artworkId).toBe('series-cover');
    expect(episodeCard(bare, 'wide').artworkId).toBeNull();
  });
  it('puts the series poster first on a poster card', () => {
    expect(episodeCard(episode, 'poster', numbered, wideShow).artworkId).toBe('series-cover');
  });
  it('shares one read per parent across episodes and rails of one load', async () => {
    const read = vi.fn(async (id: string) => id === 'season' ? numbered : wideShow);
    const shared = dedupeReader(read);
    await episodeCards([bare, { ...bare, id: 'other' }], 'wide', shared, signal());
    await episodeCards([bare], 'wide', shared, signal());
    expect(read).toHaveBeenCalledTimes(2);
  });
});
