/**
 * Scherm 29 tegen een nepserver: de dekking per bibliotheek met de poort van
 * de server, de lijst die aandacht vraagt, en dat het scherm nooit schrijft.
 */
import { render, screen, within } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { library, settingsFake } from './settingsFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import MetadataPage from './MetadataPage.svelte';

const coverage = (items: number, sidecar: number, genres: number, gate: boolean) => ({
  items,
  with_sidecar: sidecar,
  with_summary: sidecar,
  with_genres: genres,
  ratio: genres / items,
  threshold: 0.8,
  gate_met: gate
});

function setup(attention: unknown = { items: [], total: 0 }, withKids = true) {
  const server = settingsFake({
    libraries: [library('l1', 'Films'), library('l2', 'Series', { kind: 'shows' }), library('l3', 'Kids')],
    coverage: {
      l1: coverage(461, 420, 411, true),
      l2: coverage(97, 82, 79, true),
      ...(withKids ? { l3: coverage(5, 2, 2, false) } : {})
    },
    attention
  });
  h.client = server.client;
  return server;
}

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('scherm 29, metadata en artwork', () => {
  it('toont per bibliotheek de dekking en de poort met de drempel van de server', async () => {
    setup();
    render(MetadataPage);
    const films = (await screen.findByText('Films')).closest('tr') as HTMLElement;
    expect(within(films).getByText('89,2% · 411 van 461')).toBeInTheDocument();
    expect(within(films).getByText('boven de 80%')).toBeInTheDocument();
    const kids = screen.getByText('Kids').closest('tr') as HTMLElement;
    expect(within(kids).getByText('onder de 80%')).toBeInTheDocument();
    expect(within(kids).getByRole('meter')).toHaveAttribute('aria-valuenow', '40');
  });

  it('laat een bibliotheek zonder leesbare dekking staan als "niet te lezen"', async () => {
    setup(undefined, false);
    render(MetadataPage);
    const kids = (await screen.findByText('Kids')).closest('tr') as HTMLElement;
    expect(within(kids).getByText('niet te lezen')).toBeInTheDocument();
    expect(within(kids).queryByText(/boven de|onder de/)).not.toBeInTheDocument();
  });

  it('toont titels die aandacht vragen met hun toestand', async () => {
    setup({
      total: 7,
      items: [
        { item_id: 'i1', library_id: 'l1', kind: 'movie', title: 'Nosferatu', year: 2024, state: 'ambiguous', alternatives: [], updated_at: '2026-10-26T08:00:00Z' },
        { item_id: 'i2', library_id: 'l1', kind: 'movie', title: 'Heat', year: null, state: 'failed', alternatives: [], updated_at: '2026-10-26T08:00:00Z' }
      ]
    });
    render(MetadataPage);
    const row = (await screen.findByText('Nosferatu (2024)')).closest('li') as HTMLElement;
    expect(within(row).getByText('dubbelzinnig')).toBeInTheDocument();
    expect(screen.getByText('7 titels')).toBeInTheDocument();
    expect(screen.getByText('En nog 5.')).toBeInTheDocument();
  });

  it('schrijft nooit en verzint geen providerstatus (negatieve controle)', async () => {
    const server = setup();
    render(MetadataPage);
    await screen.findByText('Films');
    expect(server.writes()).toEqual([]);
    expect(screen.queryByText(/TMDB/)).not.toBeInTheDocument();
    expect(screen.queryByText(/niet geconfigureerd/)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Opslaan' })).not.toBeInTheDocument();
  });
});
