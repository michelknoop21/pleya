import { fireEvent, render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ admin: true, caps: {} as Record<string, boolean> }));
vi.mock('$app/state', () => ({ page: { url: new URL('http://web.test/items/show1') } }));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get canAdminister() { return h.admin; },
    get capabilities() { return h.caps; },
    client: {
      children: async () => ({ items: [], next_cursor: null }),
      hub: async () => ({ items: [], next_cursor: null })
    }
  }
}));
import SeriesDetail from './SeriesDetail.svelte';

const item = { id: 'show1', kind: 'show' as const, title: 'Dark', added_at: '2026-01-01T00:00:00Z' };

beforeEach(() => { h.admin = true; h.caps = { media_delete: true }; });

async function details(): Promise<void> {
  render(SeriesDetail, { props: { item, onchange: () => {} } });
  await fireEvent.click(screen.getByRole('tab', { name: 'Details and cast' }));
}

describe('verwijderen op het seriedetail', () => {
  it('opent de bevestiging die zegt dat alle afleveringen meegaan', async () => {
    await details();
    await fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
    expect(screen.getByRole('dialog').textContent).toContain('All episodes under it are deleted too.');
  });

  it('toont de knop niet zonder media_delete', async () => {
    h.caps = {};
    await details();
    expect(screen.queryByRole('button', { name: 'Delete' })).toBeNull();
  });

  it('toont de knop niet aan een lid', async () => {
    h.admin = false;
    await details();
    expect(screen.queryByRole('button', { name: 'Delete' })).toBeNull();
  });
});
