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
  users: false
};

describe('capabilities bepalen de navigatie', () => {
  it('toont home, zoeken, bibliotheken en server wanneer alles kan', () => {
    expect(navItems(all, 3).map((i) => i.id)).toEqual(['home', 'search', 'libraries', 'server']);
  });

  it('laat zoeken weg wanneer de server het niet aanbiedt', () => {
    expect(navItems({ ...all, search: false }, 3).map((i) => i.id)).not.toContain('search');
  });

  it('laat bibliotheken weg wanneer er geen zijn, in plaats van een leeg scherm', () => {
    expect(navItems(all, 0).map((i) => i.id)).not.toContain('libraries');
  });

  it('laat home en bibliotheken weg wanneer bladeren niet kan', () => {
    const ids = navItems({ ...all, browse: false }, 3).map((i) => i.id);
    expect(ids).not.toContain('home');
    expect(ids).not.toContain('libraries');
  });

  it('toont niets van kijkstatus, afspelen of beheer, want daar is geen endpoint voor', () => {
    const ids = navItems(all, 3).map((i) => i.id);
    for (const forbidden of ['continue', 'watchlist', 'downloads', 'livetv', 'scans', 'jobs', 'users']) {
      expect(ids).not.toContain(forbidden);
    }
  });

  it('kent geen navigatie zonder info', () => {
    expect(navItems(null, 0).map((i) => i.id)).toEqual(['server']);
  });
});

describe('welk item actief is', () => {
  const items = navItems(all, 2);

  it('kiest home alleen op de wortel', () => {
    expect(activeItemId(items, '/')).toBe('home');
  });

  it('kiest de langste treffer', () => {
    expect(activeItemId(items, '/libraries/abc')).toBe('libraries');
    expect(activeItemId(items, '/search?q=x')).toBe('search');
    expect(activeItemId(items, '/server')).toBe('server');
  });

  it('kiest niets op een pad dat bij geen item hoort', () => {
    expect(activeItemId(items, '/items/abc')).toBeNull();
  });
});
