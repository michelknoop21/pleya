import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import NavRail from './NavRail.svelte';
import BottomBar from './BottomBar.svelte';
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
  sessions: false
};
const items = navItems(caps, 2);

describe('de zijbalk', () => {
  it('draagt een naam en één link per item', () => {
    render(NavRail, { props: { items, activeId: 'home' } });
    const nav = screen.getByRole('navigation', { name: 'Primary' });
    expect(nav).toBeInTheDocument();
    // De merklink staat er ook in, vandaar één meer dan het aantal items.
    expect(screen.getAllByRole('link')).toHaveLength(items.length + 1);
  });

  it('markeert het actieve item met aria-current', () => {
    render(NavRail, { props: { items, activeId: 'libraries' } });
    const current = screen.getByRole('link', { current: 'page' });
    expect(current).toHaveAttribute('href', '/libraries');
  });

  it('is volledig met het toetsenbord te doorlopen', async () => {
    render(NavRail, { props: { items, activeId: 'home' } });
    const user = userEvent.setup();

    const links = screen.getAllByRole('link');
    for (const link of links) {
      await user.tab();
      expect(link).toHaveFocus();
    }
  });

  it('klapt uit zodra de focus erin valt, zodat labels leesbaar worden', async () => {
    const { container } = render(NavRail, { props: { items, activeId: 'home' } });
    const nav = container.querySelector('.rail');
    expect(nav?.classList.contains('rail--open')).toBe(false);

    await userEvent.setup().tab();
    expect(nav?.classList.contains('rail--open')).toBe(true);
  });
});

describe('de bottom bar', () => {
  it('draagt dezelfde items als de zijbalk', () => {
    render(BottomBar, { props: { items, activeId: 'search' } });
    expect(screen.getAllByRole('link')).toHaveLength(items.length);
    expect(screen.getByRole('link', { current: 'page' })).toHaveAttribute('href', '/search');
  });

  it('toont een leesbaar label naast het icoon', () => {
    render(BottomBar, { props: { items, activeId: 'home' } });
    for (const item of items) {
      expect(screen.getByText(item.label)).toBeInTheDocument();
    }
  });
});
