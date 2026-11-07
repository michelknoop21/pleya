import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/svelte';

const h = vi.hoisted(() => ({
  session: {} as Record<string, unknown>,
  setWatched: vi.fn(),
  setFavorite: vi.fn(),
  clearMetadataMatch: vi.fn(),
  goto: vi.fn(),
  open: vi.fn(),
  loadItem: vi.fn()
}));
vi.mock('../stores/session.svelte', () => ({ session: h.session }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/addToList.svelte', () => ({ addToList: { open: h.open } }));
vi.mock('../api/personal', () => ({ personalApi: () => ({ setWatched: h.setWatched, setFavorite: h.setFavorite }) }));
vi.mock('../api/adminSettings', () => ({ adminSettingsApi: () => ({ clearMetadataMatch: h.clearMetadataMatch }) }));

import CardMenu from './CardMenu.svelte';
import type { Item } from '../api/types';

const movie = { id: 'm 1', kind: 'movie', title: 'Grease', duration_ms: 5000, added_at: '2026-01-01T00:00:00Z' } as Item;
const everything = { collections: true, watch_state: true, favorites: true, metadata_overrides: true };

function setup(admin: boolean, caps: Record<string, boolean> = everything, item: Item = movie) {
  Object.assign(h.session, { capabilities: caps, canAdminister: admin, client: { item: h.loadItem } });
  render(CardMenu, { item });
  return fireEvent.click(screen.getByRole('button', { name: 'Actions for ' + item.title }));
}
const labels = () => screen.getAllByRole('menuitem').map((el) => el.textContent?.trim());

beforeEach(() => {
  vi.clearAllMocks();
  h.setWatched.mockResolvedValue({});
  h.setFavorite.mockResolvedValue(undefined);
  h.clearMetadataMatch.mockResolvedValue({});
});

describe('CardMenu', () => {
  it('gives a member the personal items and no admin items', async () => {
    await setup(false);
    expect(labels()).toEqual(['Add to', 'Mark watched', 'Add to favorites', 'Information']);
  });

  it('gives an administrator the admin items too', async () => {
    await setup(true);
    expect(labels()).toEqual([
      'Add to', 'Mark watched', 'Add to favorites', 'Information', 'Watched by',
      'Correct match', 'Unlink', 'Edit metadata'
    ]);
  });

  it('leaves out what the server does not offer', async () => {
    await setup(true, { watch_state: false }, { ...movie, kind: 'show' } as Item);
    expect(labels()).toEqual(['Correct match', 'Unlink']);
  });

  it('reports the watched state through the watch-state call and flips the label', async () => {
    await setup(false);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Mark watched' }));
    expect(h.setWatched).toHaveBeenCalledWith('m 1', true, 5000);
    await fireEvent.click(screen.getByRole('button', { name: 'Actions for Grease' }));
    expect(await screen.findByRole('menuitem', { name: 'Mark unwatched' })).toBeInTheDocument();
  });

  it('removes a favorite with the favorites call', async () => {
    await setup(false, everything, { ...movie, favorite: true } as Item);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Remove from favorites' }));
    expect(h.setFavorite).toHaveBeenCalledWith('m 1', false);
  });

  it('shows the version panel of the loaded item under Information', async () => {
    h.loadItem.mockResolvedValue({ ...movie, versions: [{ id: 'v', container: 'mkv', duration_ms: 60000 }] });
    await setup(false);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Information' }));
    expect(await screen.findByText(/mkv/)).toBeInTheDocument();
    expect(h.loadItem).toHaveBeenCalledWith('m 1');
  });

  it('opens the existing screens for the admin links', async () => {
    await setup(true);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Correct match' }));
    expect(h.goto).toHaveBeenLastCalledWith('/admin/metadata/match?item=m%201');
    await fireEvent.click(screen.getByRole('button', { name: 'Actions for Grease' }));
    await fireEvent.click(await screen.findByRole('menuitem', { name: 'Edit metadata' }));
    expect(h.goto).toHaveBeenLastCalledWith('/admin/metadata/edit?item=m%201');
    await fireEvent.click(screen.getByRole('button', { name: 'Actions for Grease' }));
    await fireEvent.click(await screen.findByRole('menuitem', { name: 'Watched by' }));
    expect(h.goto).toHaveBeenLastCalledWith('/items/m%201#watched-by');
  });

  it('unlinks only after confirmation', async () => {
    await setup(true);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Unlink' }));
    expect(h.clearMetadataMatch).not.toHaveBeenCalled();
    const dialog = await screen.findByRole('dialog', { name: 'Unlink the metadata?' });
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Unlink' }));
    expect(h.clearMetadataMatch).toHaveBeenCalledWith('m 1');
  });
});
