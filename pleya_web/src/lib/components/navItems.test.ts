import { describe, expect, it } from 'vitest';

import { activeItemId, navItems } from './navItems';
import type { Capabilities } from '../api/types';

const all: Capabilities = {
  browse: true,
  search: true,
  artwork: true,
  watch_state: false,
  playback_plan: false,
  transcode: false,
  downloads: false,
  live_tv: false,
  realtime: false,
  users: false,
  watch_state_ownership: false,
  stream_sessions: false,
  sessions: false,
  api_tokens: false,
  cookie_auth: false,
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
  it('wijst naar de enige bibliotheek van de soort', () => {
    const items = navItems(all, [films, series]);
    expect(items.find((i) => i.id === 'films')?.href).toBe('/libraries/lib-films');
    expect(items.find((i) => i.id === 'series')?.href).toBe('/libraries/lib-series');
  });

  it('wijst naar het overzicht bij meer dan één bibliotheek van de soort', () => {
    const items = navItems(all, [films, kids, series]);
    expect(items.find((i) => i.id === 'films')?.href).toBe('/libraries');
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

  it('kiest films op het overzicht wanneer films daar naartoe wijst', () => {
    expect(activeItemId(items, '/libraries', libs)).toBe('films');
  });

  it('kiest mijn pleya op het serveroverzicht', () => {
    expect(activeItemId(items, '/server', libs)).toBe('my');
  });

  it('kiest niets op een pad dat bij geen slot hoort', () => {
    expect(activeItemId(items, '/items/abc', libs)).toBeNull();
    expect(activeItemId(items, '/search', libs)).toBeNull();
  });
});
