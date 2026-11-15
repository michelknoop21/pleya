/** Doorgaan naar de volgende aflevering: de speler blijft staan tot het nieuwe item er is, en volledig scherm hangt aan de schil van de route. */
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, expect, it, vi } from 'vitest';
import type { Item } from '../../lib/api/types';
import { deps, fakeApi } from '../../lib/player/playerFake';

const h = vi.hoisted(() => ({ go: (_id: string) => {}, release: (_item: unknown) => {}, search: {} as Record<string, string> }));
const episode = (id: string, index: number): Item => ({ id, kind: 'episode', title: `Aflevering ${index}`, index, parent_id: 's1', added_at: '2026-10-30T00:00:00Z', versions: [{ id: `v-${id}`, container: 'mp4', duration_ms: 60000, file_count: 1 }, { id: `v-${id}-b`, container: 'mkv', duration_ms: 60000, file_count: 1 }] });
vi.mock('$app/state', async () => {
  const { fromStore, writable } = await import('svelte/store');
  const id = writable('e1');
  h.go = id.set;
  const current = fromStore(id);
  return { page: { get params() { return { id: current.current }; }, get url() { return new URL(`http://client.test/items/${current.current}/play${h.search[current.current] ?? ''}`); } } };
});
vi.mock('$app/navigation', () => ({ goto: vi.fn(async (href: string) => h.go(href.split('/')[2]!)) }));
vi.mock('../../lib/stores/session.svelte.js', () => ({ session: { client: { item: (id: string) => (id === 'e1' ? Promise.resolve(episode('e1', 1)) : new Promise((r) => (h.release = r))) }, capabilities: { playback_plan: true } } }));
vi.mock('../../lib/player/browserDeps.js', () => ({ browserPlayerDeps: () => deps(fakeApi()) }));
vi.mock('../../lib/util/videoContext.js', () => ({ videoContext: async () => ({}) }));
vi.mock('../../lib/player/upNext.js', async (original) => ({ ...(await original<typeof import('../../lib/player/upNext')>()), nextEpisode: async (_c: unknown, current: Item) => (current.id === 'e1' ? episode('e2', 2) : null) }));
import PlayRoute from './[id]/play/+page.svelte';

beforeEach(() => {
  h.search = {};
  h.go('e1');
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => {});
});

it('houdt de speler en de schil van volledig scherm vast terwijl de volgende aflevering laadt', async () => {
  const asked: Element[] = [];
  HTMLElement.prototype.requestFullscreen = vi.fn(function (this: Element) { asked.push(this); return Promise.resolve(); });
  render(PlayRoute);
  await fireEvent.click(await screen.findByRole('button', { name: 'Full screen' }));
  const shell = asked[0]!;
  expect(shell.querySelector('.player')).not.toBeNull();
  expect(shell).not.toHaveClass('player');

  await fireEvent.click(await screen.findByRole('button', { name: 'Next episode' }));
  await waitFor(() => expect(h.release).not.toBe(undefined));
  await new Promise((r) => setTimeout(r));
  // Het nieuwe item is nog onderweg: het oude beeld staat er nog.
  expect(screen.getByRole('heading', { name: 'Aflevering 1' })).toBeInTheDocument();
  expect(document.querySelector('video')).not.toBeNull();

  h.release(episode('e2', 2));
  expect(await screen.findByRole('heading', { name: 'Aflevering 2' })).toBeInTheDocument();
  expect(shell.isConnected).toBe(true);
  expect(shell.querySelector('.player')).not.toBeNull();
});

it('bouwt de speler van het oude item niet opnieuw op als de URL al naar de volgende aflevering wijst', async () => {
  // Afspelen met een tweede versie; doorgaan geeft geen ?version= mee.
  h.search = { e1: '?version=v-e1-b&t=30' };
  render(PlayRoute);
  expect(await screen.findByRole('heading', { name: 'Aflevering 1' })).toBeInTheDocument();
  const video = document.querySelector('video');
  expect(video).not.toBeNull();

  await fireEvent.click(await screen.findByRole('button', { name: 'Next episode' }));
  await new Promise((r) => setTimeout(r));
  // Het nieuwe item laadt nog: dezelfde speler, niet een nieuwe voor het oude item met de eerste versie.
  expect(screen.getByRole('heading', { name: 'Aflevering 1' })).toBeInTheDocument();
  expect(document.querySelector('video')).toBe(video);
});
