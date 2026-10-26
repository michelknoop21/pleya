/**
 * Scherm 36 tegen een nepserver: de lijst en de kandidaten, kiezen en afwijzen
 * alleen na een bevestiging, een weigering van de server die de lijst intact
 * laat, en dat er geen knoppen staan voor wat de server nog niet draagt.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { apiError, attention, matchFake } from './matchFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import MatchPage from './MatchPage.svelte';

const dune = attention('i1', 'Dune', 'ambiguous', {
  alternatives: [
    { external_id: '438631', title: 'Dune', year: 2021 },
    { external_id: '693134', title: 'Dune: Part Two', year: 2024 }
  ]
});
const anora = attention('i2', 'Anora', 'unmatched', { year: 2024 });
const conclave = attention('i3', 'Conclave', 'failed', { year: 2024 });
const oppen = attention('i4', 'Oppenheimer', 'rejected', { year: 2023 });

function setup(options: Parameters<typeof matchFake>[0] = {}, props: { initialItem?: string } = {}) {
  const server = matchFake({ items: [anora, dune, oppen, conclave], ...options });
  h.client = server.client;
  const view = render(MatchPage, { props });
  return { server, view };
}

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const rowOf = (title: string) =>
  screen.getByRole('button', { name: new RegExp(`^${title}`) }).closest('tr') as HTMLElement;

describe('scherm 36, de lijst en de kandidaten', () => {
  it('zet wat een keuze vraagt bovenaan en toont de uitkomst per titel', async () => {
    setup();
    await screen.findByRole('heading', { level: 3, name: 'Wacht op een keuze' });
    const rows = screen.getAllByRole('row').slice(1);
    expect(rows.map((r) => r.getAttribute('data-item'))).toEqual(['i1', 'i2', 'i3', 'i4']);
    expect(rowOf('Dune')).toHaveTextContent('2 kandidaten');
    expect(rowOf('Anora')).toHaveTextContent('niets gevonden');
    expect(rowOf('Conclave')).toHaveTextContent('ophalen mislukt');
    expect(rowOf('Oppenheimer')).toHaveTextContent('afgewezen');
  });

  it('toont de kandidaten van de eerste titel met nummer en jaar, zonder score of poster', async () => {
    setup();
    const group = await screen.findByRole('radiogroup', { name: 'Kandidaten van de provider' });
    expect(within(group).getAllByRole('radio')).toHaveLength(2);
    expect(group).toHaveTextContent('2021 · nummer 438631');
    expect(group).toHaveTextContent('Dune: Part Two (2024)');
    expect(group.querySelector('img')).toBeNull();
    expect(screen.queryByText(/%/)).toBeNull();
  });

  it('opent de titel uit de link van scherm 29', async () => {
    setup({}, { initialItem: 'i2' });
    expect(await screen.findByText(/geen kandidaten/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Anora (2024) beoordelen' })).toHaveAttribute(
      'aria-pressed',
      'true'
    );
  });

  it('zegt het als de titel uit de link niet meer op de lijst staat', async () => {
    setup({}, { initialItem: 'weg' });
    expect(await screen.findByText(/vraagt geen aandacht meer/)).toBeInTheDocument();
    expect(screen.queryByRole('radiogroup')).toBeNull();
  });
});

describe('een kandidaat kiezen', () => {
  async function choose(user: ReturnType<typeof userEvent.setup>) {
    await user.click(await screen.findByRole('radio', { name: /Dune: Part Two/ }));
    await user.click(screen.getByRole('button', { name: 'Deze kiezen' }));
  }

  it('stuurt niets zolang de bevestiging openstaat of geannuleerd wordt', async () => {
    const { server } = setup();
    const user = userEvent.setup();
    await choose(user);
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('vervangt wat de provider eerder');
    expect(dialog).toHaveTextContent('Dune: Part Two (2024)');
    expect(server.writes()).toEqual([]);
    await user.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(server.writes()).toEqual([]);
  });

  it('stuurt na bevestigen één PUT met het nummer en leest de lijst opnieuw', async () => {
    const { server } = setup();
    const user = userEvent.setup();
    await choose(user);
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Koppelen' }));
    await waitFor(() => expect(server.writes()).toEqual(['PUT /items/i1/metadata-match']));
    expect(server.seen.find((s) => s.method === 'PUT')?.body).toEqual({ external_id: '693134' });
    expect(await screen.findByText(/is gekoppeld aan Dune: Part Two \(2024\)/)).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole('button', { name: /^Dune \(2021\)/ })).toBeNull());
    expect(server.seen.filter((s) => s.path.startsWith('/metadata/attention')).length).toBeGreaterThan(1);
  });

  it('laat de lijst staan en zegt wat er mis is als de server het nummer weigert', async () => {
    const { server } = setup({ fail: { 'PUT /items/i1/metadata-match': apiError('library.invalid_match', 400) } });
    const user = userEvent.setup();
    await choose(user);
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Koppelen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('geen geldig titelnummer');
    expect(rowOf('Dune')).toBeInTheDocument();
    expect(rowOf('Anora')).toBeInTheDocument();
    expect(server.state.items).toHaveLength(4);
  });

  it('leest de lijst opnieuw als de titel niet meer bestaat', async () => {
    const { server } = setup({ fail: { 'PUT /items/i1/metadata-match': apiError('library.not_found', 404) } });
    const user = userEvent.setup();
    await choose(user);
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Koppelen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('staat niet meer op de server');
    await waitFor(() =>
      expect(server.seen.filter((s) => s.path.startsWith('/metadata/attention')).length).toBe(2)
    );
  });

  it('houdt Deze kiezen dicht zolang er niets gekozen is', async () => {
    const { server } = setup();
    await screen.findByRole('radiogroup');
    expect(screen.getByRole('button', { name: 'Deze kiezen' })).toBeDisabled();
    expect(server.writes()).toEqual([]);
  });
});

describe('zelf een nummer invullen', () => {
  it('stuurt een ongeldig nummer niet en zegt waarom', async () => {
    const { server } = setup({}, { initialItem: 'i2' });
    const user = userEvent.setup();
    await user.type(await screen.findByLabelText('Nummer bij de provider'), '0123');
    await user.click(screen.getByRole('button', { name: 'Dit nummer gebruiken' }));
    expect(await screen.findByText(/positief geheel getal van hoogstens tien cijfers/)).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(server.writes()).toEqual([]);
  });

  it('stuurt een geldig nummer pas na bevestigen', async () => {
    const { server } = setup({}, { initialItem: 'i2' });
    const user = userEvent.setup();
    await user.type(await screen.findByLabelText('Nummer bij de provider'), '438631');
    await user.click(screen.getByRole('button', { name: 'Dit nummer gebruiken' }));
    const dialog = await screen.findByRole('dialog');
    expect(server.writes()).toEqual([]);
    await user.click(within(dialog).getByRole('button', { name: 'Koppelen' }));
    await waitFor(() => expect(server.writes()).toEqual(['PUT /items/i2/metadata-match']));
    expect(server.seen.find((s) => s.method === 'PUT')?.body).toEqual({ external_id: '438631' });
  });
});

describe('de match afwijzen', () => {
  it('legt uit wat er gebeurt en stuurt niets zonder bevestiging', async () => {
    const { server } = setup();
    const user = userEvent.setup();
    await user.click(await screen.findByRole('button', { name: 'Match afwijzen' }));
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('samenvatting, genres, kijkwijzer, cast en gecachte afbeeldingen');
    expect(dialog).toHaveTextContent('Wat een sidecar zette blijft staan');
    expect(server.writes()).toEqual([]);
    await user.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(server.writes()).toEqual([]);
  });

  it('stuurt na bevestigen één DELETE en zet de titel op afgewezen', async () => {
    const { server } = setup();
    const user = userEvent.setup();
    await user.click(await screen.findByRole('button', { name: 'Match afwijzen' }));
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Afwijzen' }));
    await waitFor(() => expect(server.writes()).toEqual(['DELETE /items/i1/metadata-match']));
    expect(await screen.findByText('Dune (2021) is afgewezen.')).toBeInTheDocument();
    await waitFor(() => expect(rowOf('Dune')).toHaveTextContent('afgewezen'));
  });

  it('laat de lijst staan en zegt wat er mis is als de server het weigert', async () => {
    const { server } = setup({
      fail: { 'DELETE /items/i1/metadata-match': apiError('server.database_unavailable', 500) }
    });
    const user = userEvent.setup();
    await user.click(await screen.findByRole('button', { name: 'Match afwijzen' }));
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Afwijzen' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(rowOf('Dune')).toHaveTextContent('2 kandidaten');
    expect(server.state.items.find((i) => i.item_id === 'i1')?.state).toBe('ambiguous');
  });

  it('biedt bij een al afgewezen titel geen tweede afwijzing aan, wel een nummer', async () => {
    setup({}, { initialItem: 'i4' });
    expect(await screen.findByText(/al afgewezen/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Match afwijzen' })).toBeNull();
    expect(screen.getByLabelText('Nummer bij de provider')).toBeInTheDocument();
  });
});

describe('wat de server nog niet draagt', () => {
  it('toont geen knoppen of panelen voor overrides, artwork kiezen of een providerronde', async () => {
    setup();
    await screen.findByRole('radiogroup');
    const names = screen.getAllByRole('button').map((b) => b.textContent ?? '');
    for (const name of names) expect(name).not.toMatch(/override|artwork|pin|providerronde|veld|bevestig/i);
    expect(screen.queryByText(/Artwork kiezen|Velden van|Providerronde/)).toBeNull();
    expect(screen.getByText(/staan hier niet/)).toBeInTheDocument();
  });
});
