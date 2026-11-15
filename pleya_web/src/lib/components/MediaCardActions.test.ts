import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

const h = vi.hoisted(() => ({
  session: {} as Record<string, unknown>,
  setWatched: vi.fn(),
  setFavorite: vi.fn()
}));
vi.mock('../stores/session.svelte', () => ({ session: h.session }));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('../stores/addToList.svelte', () => ({ addToList: { open: vi.fn() } }));
vi.mock('../api/personal', () => ({ personalApi: () => ({ setWatched: h.setWatched, setFavorite: h.setFavorite }) }));

import MediaCard from './MediaCard.svelte';
import type { Item } from '../api/types';

const state = (watched: boolean, position_ms = 0): NonNullable<Item['user_state']> => ({
  watched, position_ms, play_count: 0, updated_at: '2026-01-01T00:00:00Z'
});
const movie = (patch: Partial<Item> = {}): Item => ({
  id: 'm 1', kind: 'movie', title: 'Grease', added_at: '2026-01-01T00:00:00Z', duration_ms: 6_000_000,
  versions: [{ id: 'v', container: 'mkv', duration_ms: 6_000_000, file_count: 1 }],
  ...patch
});
const everything = { playback_plan: true, watch_state: true, favorites: true };

function setup(item: Item = movie(), caps: Record<string, boolean> = everything, quickActions = true) {
  Object.assign(h.session, { capabilities: caps, canAdminister: false, client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } });
  return render(MediaCard, { props: { item, quickActions } });
}

beforeEach(() => {
  vi.clearAllMocks();
  h.setWatched.mockImplementation(async (_id: string, watched: boolean) => state(watched));
  h.setFavorite.mockResolvedValue(undefined);
});

describe('snelle acties op een kaart', () => {
  it('markeert als gezien vanaf de kaart, toont het vinkje en draait de knop om', async () => {
    const user = userEvent.setup();
    setup(movie({ user_state: state(false, 1_500_000) }));
    expect(screen.queryByRole('img', { name: 'Watched' })).toBeNull();
    await user.click(screen.getByRole('button', { name: 'Mark watched' }));
    expect(h.setWatched).toHaveBeenCalledWith('m 1', true, 6_000_000);
    expect(await screen.findByRole('img', { name: 'Watched' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Mark unwatched' }));
    expect(h.setWatched).toHaveBeenLastCalledWith('m 1', false, 6_000_000);
    expect(await screen.findByRole('button', { name: 'Mark watched' })).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'Watched' })).toBeNull();
  });

  it('wisselt favoriet via de favorietenroute en houdt het kaartmenu gelijk', async () => {
    const user = userEvent.setup();
    setup();
    await user.click(screen.getByRole('button', { name: 'Add to favorites' }));
    expect(h.setFavorite).toHaveBeenCalledWith('m 1', true);
    await user.click(await screen.findByRole('button', { name: 'Remove from favorites' }));
    expect(h.setFavorite).toHaveBeenLastCalledWith('m 1', false);
    await screen.findByRole('button', { name: 'Add to favorites' });
    // Het menu leest dezelfde stand als de knop, niet een eigen kopie.
    await user.click(screen.getByRole('button', { name: 'Add to favorites' }));
    await user.click(screen.getByRole('button', { name: 'Actions for Grease' }));
    expect(screen.getByRole('menuitem', { name: 'Remove from favorites' })).toBeInTheDocument();
  });

  it('laat een mislukte wijziging zien en de stand staan', async () => {
    const user = userEvent.setup();
    h.setFavorite.mockRejectedValue(new Error('offline'));
    setup();
    await user.click(screen.getByRole('button', { name: 'Add to favorites' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add to favorites' })).toBeInTheDocument();
  });

  it('toont alleen wat de server kan', () => {
    setup(movie(), { playback_plan: true, watch_state: false, favorites: false });
    expect(screen.getByRole('link', { name: 'Play Grease' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /watched/i })).toBeNull();
    expect(screen.queryByRole('button', { name: /favorites/i })).toBeNull();
  });

  it('houdt zonder capabilities alleen het menu over, en bij een serie niets', () => {
    const film = setup(movie(), {});
    // "Information" hangt aan geen capability, dus het menu blijft.
    expect(film.container.querySelectorAll('.acts a, .acts button')).toHaveLength(1);
    expect(screen.getByRole('button', { name: 'Actions for Grease' })).toBeInTheDocument();
    film.unmount();
    const show = setup(movie({ kind: 'show', versions: [] }), {});
    expect(show.container.querySelectorAll('.acts a, .acts button')).toHaveLength(0);
  });

  it('geeft een serie geen afspeel- en geen gezien-knop, wel favoriet', () => {
    setup(movie({ kind: 'show', versions: [] }));
    expect(screen.queryByRole('link', { name: 'Play Grease' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Mark watched' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Add to favorites' })).toBeInTheDocument();
  });

  it('hervat op de bewaarde positie en begint een geziene titel vooraan', () => {
    const first = setup(movie({ user_state: state(false, 90_000) }));
    expect(screen.getByRole('link', { name: 'Play Grease' })).toHaveAttribute('href', '/items/m%201/play?t=90');
    first.unmount();
    setup(movie({ user_state: state(true, 90_000) }));
    expect(screen.getByRole('link', { name: 'Play Grease' })).toHaveAttribute('href', '/items/m%201/play');
  });

  it('is met Tab bereikbaar in de volgorde kaart, afspelen, gezien, favoriet, menu, en met de toetsen te bedienen', async () => {
    const user = userEvent.setup();
    const { container } = setup();
    const card = container.querySelector('.card')!;
    const stops = [
      within(card as HTMLElement).getByRole('link', { name: /^Grease/ }),
      screen.getByRole('link', { name: 'Play Grease' }),
      screen.getByRole('button', { name: 'Mark watched' }),
      screen.getByRole('button', { name: 'Add to favorites' }),
      screen.getByRole('button', { name: 'Actions for Grease' })
    ];
    for (const stop of stops) {
      await user.tab();
      expect(stop).toHaveFocus();
      // Geen knop in de kaartlink: de acties zijn zusters van de link.
      if (stop !== stops[0]) expect(stop.closest('.card__link')).toBeNull();
    }
    stops[2]!.focus();
    await user.keyboard('{Enter}');
    expect(h.setWatched).toHaveBeenCalledWith('m 1', true, 6_000_000);
    // De focus blijft op de knop terwijl en nadat de aanvraag loopt.
    expect(await screen.findByRole('button', { name: 'Mark unwatched' })).toHaveFocus();
    await user.tab();
    await user.keyboard(' ');
    expect(h.setFavorite).toHaveBeenCalledWith('m 1', true);
  });

  it('zegt bij gezien en favoriet over welke titel de knop gaat', () => {
    setup();
    expect(screen.getByRole('button', { name: 'Mark watched' })).toHaveAccessibleDescription('Grease');
    expect(screen.getByRole('button', { name: 'Add to favorites' })).toHaveAccessibleDescription('Grease');
  });

  it('laat een kaart zonder quickActions bij alleen het menu', () => {
    const { container } = setup(movie(), everything, false);
    expect(screen.queryByRole('link', { name: 'Play Grease' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Mark watched' })).toBeNull();
    expect(container.querySelector('.acts--menu')).not.toBeNull();
    expect(screen.getByRole('button', { name: 'Actions for Grease' })).toBeInTheDocument();
  });

  it('werkt het vinkje ook bij als het kaartmenu de kijkstatus zet', async () => {
    const user = userEvent.setup();
    setup(movie(), everything, false);
    await user.click(screen.getByRole('button', { name: 'Actions for Grease' }));
    await user.click(screen.getByRole('menuitem', { name: 'Mark watched' }));
    expect(await screen.findByRole('img', { name: 'Watched' })).toBeInTheDocument();
  });
});
