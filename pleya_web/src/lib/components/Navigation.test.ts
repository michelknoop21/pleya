import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import TopNav from './TopNav.svelte';
import MobileHeader from './MobileHeader.svelte';
import TabBar from './TabBar.svelte';
import { navItems } from './navItems';
import type { Capabilities } from '../api/types';

const caps: Capabilities = {
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
const items = navItems(caps, [
  { id: 'f', kind: 'movies' },
  { id: 's', kind: 'shows' }
]);

describe('de bovenbalk', () => {
  it('draagt een naam, het merk en één link per slot', () => {
    render(TopNav, { props: { items, activeId: 'home' } });
    expect(screen.getByRole('navigation', { name: 'Primary' })).toBeInTheDocument();
    // Het merk staat er ook in, vandaar één meer dan het aantal slots.
    expect(screen.getAllByRole('link')).toHaveLength(items.length + 1);
  });

  it('markeert het actieve slot met aria-current', () => {
    render(TopNav, { props: { items, activeId: 'films' } });
    expect(screen.getByRole('link', { current: 'page' })).toHaveAttribute('href', '/libraries/f');
  });

  it('toont zoeken als actie, alleen wanneer de server het aanbiedt', () => {
    const { unmount } = render(TopNav, { props: { items, activeId: 'home', showSearch: true } });
    expect(screen.getByRole('link', { name: 'Search' })).toHaveAttribute('href', '/search');
    unmount();

    render(TopNav, { props: { items, activeId: 'home', showSearch: false } });
    expect(screen.queryByRole('link', { name: 'Search' })).toBeNull();
  });

  it('is volledig met het toetsenbord te doorlopen', async () => {
    render(TopNav, { props: { items, activeId: 'home', showSearch: true } });
    const user = userEvent.setup();
    for (const link of screen.getAllByRole('link')) {
      await user.tab();
      expect(link).toHaveFocus();
    }
  });
});

describe('de mobiele kop', () => {
  it('draagt het merk en, met zoeken, een zoekactie', () => {
    render(MobileHeader, { props: { showSearch: true } });
    expect(screen.getByRole('link', { name: 'Search' })).toHaveAttribute('href', '/search');
  });

  it('laat de zoekactie weg zonder zoeken', () => {
    render(MobileHeader, { props: { showSearch: false } });
    expect(screen.queryByRole('link', { name: 'Search' })).toBeNull();
  });
});

describe('de tabbalk', () => {
  it('draagt dezelfde slots als de bovenbalk', () => {
    render(TabBar, { props: { items, activeId: 'series' } });
    expect(screen.getAllByRole('link')).toHaveLength(items.length);
    expect(screen.getByRole('link', { current: 'page' })).toHaveAttribute('href', '/libraries/s');
  });

  it('toont een leesbaar label naast het icoon', () => {
    render(TabBar, { props: { items, activeId: 'home' } });
    for (const item of items) {
      expect(screen.getByText(item.label)).toBeInTheDocument();
    }
  });

  it('toont Boeken alleen met een boekenbibliotheek', () => {
    const without = navItems(caps, [{ id: 'f', kind: 'movies' }]);
    const withBooks = navItems(caps, [
      { id: 'f', kind: 'movies' },
      { id: 'b', kind: 'books' }
    ]);

    const first = render(TabBar, { props: { items: without, activeId: 'home' } });
    expect(screen.queryByText('Books')).toBeNull();
    first.unmount();

    render(TabBar, { props: { items: withBooks, activeId: 'home' } });
    expect(screen.getByText('Books')).toBeInTheDocument();
  });
});
