import { describe, expect, it } from 'vitest';

import { activeItemId, navItems } from './navItems';
import type { Capabilities } from '../api/types';

const all: Capabilities = {
  external_id_lookup: false,
  applied_external_identity: false,
  metadata_match_status: false,
  metadata_search: false,
  assistant_memory: false,
  browse: true,
  search: true,
  artwork: true,
  artwork_sizes: false,
  filters: false,
  watch_state: false,
  playback_plan: false,
  playback_quality: false,
  playback_audio_selection: false,
  embedded_subtitles: false,
  playback_subtitles: false,
  history: false,
  favorites: false,
  ratings: false,
  track_preferences: false,
  personal_data: false,
  collections: false,
  playlists: false,
  item_activity: false,
  transcode: false,
  downloads: false,
  backups: false,
  live_tv: false,
  realtime: false,
  users: false,
  watch_state_ownership: false,
  watch_state_copy: false,
  stream_sessions: false,
  sessions: false,
  api_tokens: false,
  cookie_auth: false,
  cookie_upgrade: false,
  administration: false,
  mcp: false
};

const films = { id: 'lib-films', kind: 'movies' };
const kids = { id: 'lib-kids', kind: 'movies' };
const series = { id: 'lib-series', kind: 'shows' };
const books = { id: 'lib-books', kind: 'books' };

const ids = (libraries: { id: string; kind: string }[], caps: Capabilities | null = all) =>
  navItems(caps, libraries).map((i) => i.id);

describe('de vijf slots volgen capabilities en bibliotheken', () => {
  it('toont home, films, series en mijn pleya met films en series, zonder boeken', () => {
    expect(ids([films, series])).toEqual(['home', 'series', 'films', 'my']);
  });

  it('toont boeken alleen met een boekenbibliotheek', () => {
    expect(ids([films, series])).not.toContain('books');
    expect(ids([films, series, books])).toEqual(['home', 'series', 'films', 'books', 'my']);
  });

  it('laat films en series weg wanneer de soort er niet is, in plaats van een leeg scherm', () => {
    expect(ids([series])).toEqual(['home', 'series', 'my']);
    expect(ids([])).toEqual(['home', 'my']);
  });

  it('laat alles behalve mijn pleya weg wanneer bladeren niet kan', () => {
    expect(ids([films, series, books], { ...all, browse: false })).toEqual(['my']);
  });

  it('kent geen navigatie zonder info, behalve mijn pleya', () => {
    expect(ids([], null)).toEqual(['my']);
  });

  it('zet zoeken niet in de slots: dat is een actie in de kop', () => {
    expect(ids([films, series])).not.toContain('search');
  });

  it('toont niets van kijkstatus, afspelen of beheer, want daar is geen route voor', () => {
    const all5 = ids([films, series, books]) as string[];
    for (const forbidden of ['continue', 'watchlist', 'downloads', 'livetv', 'admin', 'libraries']) {
      expect(all5).not.toContain(forbidden);
    }
  });
});

describe('waar een slot heen wijst', () => {
  it('wijst naar de eigen landing voor elke videosoort', () => {
    const items = navItems(all, [films, series]);
    expect(items.find((i) => i.id === 'films')?.href).toBe('/films');
    expect(items.find((i) => i.id === 'series')?.href).toBe('/series');
  });

  it('houdt de films-landing bij meerdere bibliotheken', () => {
    const items = navItems(all, [films, kids, series]);
    expect(items.find((i) => i.id === 'films')?.href).toBe('/films');
  });

  it('wijst mijn pleya naar het serveroverzicht, tot S8 een eigen landing geeft', () => {
    expect(navItems(all, []).find((i) => i.id === 'my')?.href).toBe('/server');
  });
});

describe('welk slot actief is', () => {
  const libs = [films, kids, series];
  const items = navItems(all, libs);

  it('kiest home alleen op de wortel', () => {
    expect(activeItemId(items, '/', libs)).toBe('home');
  });

  it('kiest het slot van de soort van de bibliotheek, ook als het slot naar het overzicht wijst', () => {
    expect(activeItemId(items, '/libraries/lib-kids', libs)).toBe('films');
    expect(activeItemId(items, '/libraries/lib-series', libs)).toBe('series');
  });

  it('kiest de landing en houdt het algemene overzicht neutraal', () => {
    expect(activeItemId(items, '/films', libs)).toBe('films');
    expect(activeItemId(items, '/series', libs)).toBe('series');
    expect(activeItemId(items, '/libraries', libs)).toBeNull();
  });

  it('kiest mijn pleya op het serveroverzicht', () => {
    expect(activeItemId(items, '/server', libs)).toBe('my');
  });

  it('kiest niets op een pad dat bij geen slot hoort', () => {
    expect(activeItemId(items, '/items/abc', libs)).toBeNull();
    expect(activeItemId(items, '/search', libs)).toBeNull();
  });
});
