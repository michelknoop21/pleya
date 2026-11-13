/**
 * Onderhoud op scherm 22 (C-05) tegen een nepserver: metadata verversen en de
 * prullenbak legen, de capability-vlag, de verplichte bevestiging bij legen,
 * één aanvraag bij dubbel klikken, een zin per foutcode en een retry die bij
 * zijn eigen bibliotheek blijft.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, json, library, libraryFake, root } from './libraryFake';

const h = vi.hoisted(() => ({
  client: null as unknown,
  capabilities: null as Record<string, boolean> | null
}));
vi.mock('$app/navigation', () => ({ goto: vi.fn(async () => {}) }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    get capabilities() {
      return h.capabilities;
    }
  }
}));

import LibraryEditor from './LibraryEditor.svelte';

const films = library('l1', 'Films', { item_count: 461 });
const series = library('l2', 'Series', { kind: 'shows', item_count: 12 });

type Fail = Parameters<typeof libraryFake>[0]['fail'];

function setup(fail: Fail = {}, trash: Record<string, number> = { l1: 3 }) {
  const server = libraryFake({
    libraries: [films, series],
    roots: [root('/media/Films', films), root('/media/Series', series)],
    fail,
    trash
  });
  h.client = server.client;
  return server;
}

const posts = (server: ReturnType<typeof setup>, sub: string) =>
  server.writes().filter((w) => w.path.endsWith(sub));

async function open(id = 'l1') {
  render(LibraryEditor, { props: { id } });
  await screen.findByRole('textbox', { name: 'Naam' });
}

beforeEach(() => {
  setLocale('nl');
  h.capabilities = { library_maintenance: true };
});
afterEach(() => setLocale('en'));

describe('onderhoud, zichtbaarheid', () => {
  it('blijft weg zonder capabilities.library_maintenance', async () => {
    h.capabilities = { library_maintenance: false };
    setup();
    await open();
    expect(screen.queryByRole('button', { name: 'Metadata verversen' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Prullenbak legen' })).not.toBeInTheDocument();
  });
});

describe('metadata verversen', () => {
  it('stuurt één POST en noemt het aantal titels dat aan de beurt staat', async () => {
    const server = setup();
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Metadata verversen' }));
    expect(
      await screen.findByText(
        'Aan de beurt voor een nieuwe metadataronde in Films: 461 titels. Die ronde loopt op de achtergrond.'
      )
    ).toBeInTheDocument();
    expect(posts(server, '/refresh-metadata')).toEqual([
      { method: 'POST', path: '/libraries/l1/refresh-metadata', body: undefined }
    ]);
  });

  it('zegt het als er niets aan de beurt staat', async () => {
    h.client = libraryFake({
      libraries: [library('l2', 'Series', { item_count: 0 })],
      roots: []
    }).client;
    await open('l2');
    await userEvent.click(screen.getByRole('button', { name: 'Metadata verversen' }));
    expect(await screen.findByText(/In Series staat geen titel klaar/)).toBeInTheDocument();
  });

  it('stuurt bij dubbel klikken één aanvraag', async () => {
    let release: (r: Response) => void = () => {};
    const server = setup({
      'POST /libraries/l1/refresh-metadata': () => new Promise<Response>((r) => (release = r))
    });
    await open();
    const button = screen.getByRole('button', { name: 'Metadata verversen' });
    await userEvent.dblClick(button);
    await userEvent.click(button);
    expect(button).toBeDisabled();
    release(json({ items: 2 }, 202));
    await screen.findByText(/in Films: 2 titels/);
    expect(posts(server, '/refresh-metadata')).toHaveLength(1);
  });

  it('toont bij server.internal het verzoeknummer, en de retry raakt dezelfde bibliotheek', async () => {
    let calls = 0;
    const server = setup({
      'POST /libraries/l1/refresh-metadata': () =>
        ++calls === 1
          ? apiError('server.internal', 500, { request_id: 'req-9' })
          : json({ items: 5 }, 202)
    });
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Metadata verversen' }));
    expect(await screen.findByText(/verzoek req-9/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Opnieuw proberen' }));
    expect(await screen.findByText(/in Films: 5 titels/)).toBeInTheDocument();
    expect(posts(server, '/refresh-metadata').map((w) => w.path)).toEqual([
      '/libraries/l1/refresh-metadata',
      '/libraries/l1/refresh-metadata'
    ]);
  });
});

describe('prullenbak legen', () => {
  it('annuleren in de bevestiging stuurt niets', async () => {
    const server = setup();
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Prullenbak legen' }));
    const dialog = await screen.findByRole('dialog', { name: 'Prullenbak van Films legen?' });
    expect(within(dialog).getByText(/Dit is niet terug te draaien/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(posts(server, '/empty-trash')).toEqual([]);
  });

  it('legt na bevestigen, noemt de kandidaten en leest de stand niet direct opnieuw', async () => {
    const server = setup();
    await open();
    expect(screen.getByText('461 titels')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Prullenbak legen' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Prullenbak legen' }));
    expect(
      await screen.findByText(
        'De prullenbak van Films wordt geleegd: 3 titels gemarkeerd als verdwenen. De taak controleert de schijf eerst en kan er minder verwijderen. Volg hem bij Scans en taken.'
      )
    ).toBeInTheDocument();
    expect(posts(server, '/empty-trash')).toEqual([
      { method: 'POST', path: '/libraries/l1/empty-trash', body: undefined }
    ]);
    // 202 zet de taak alleen in de wachtrij: de stand wordt niet direct opnieuw gelezen.
    expect(screen.getByText('461 titels')).toBeInTheDocument();
  });

  it('stuurt bij dubbel klikken op bevestigen één aanvraag (de dialoog schakelt de knop uit zolang hij bezig is)', async () => {
    let release: (r: Response) => void = () => {};
    const server = setup({
      'POST /libraries/l1/empty-trash': () => new Promise<Response>((r) => (release = r))
    });
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Prullenbak legen' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.dblClick(within(dialog).getByRole('button', { name: 'Prullenbak legen' }));
    release(json({ items: 0, job_id: 'j' }, 202));
    expect(await screen.findByText(/stond geen titel met alleen verdwenen bestanden/)).toBeInTheDocument();
    expect(posts(server, '/empty-trash')).toHaveLength(1);
  });

  it.each([
    ['library.scan_in_progress', 409, /al een scan of een prullenbaktaak/, 'Naar scans en taken'],
    ['library.not_found', 404, /Films staat niet meer op de server/, null],
    ['auth.user_not_found', 404, /geen beheerrechten meer/, null],
    ['server.database_unavailable', 503, /database nu niet bereiken/, 'Opnieuw proberen']
  ])('geeft bij %s een eigen zin', async (code, status, text, action) => {
    setup({ 'POST /libraries/l1/empty-trash': apiError(code, status) });
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Prullenbak legen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Prullenbak legen' }));
    expect(await screen.findByText(text)).toBeInTheDocument();
    if (action) expect(screen.getByRole(action.startsWith('Naar') ? 'link' : 'button', { name: action })).toBeInTheDocument();
  });

  it('retry opent de bevestiging opnieuw voor dezelfde bibliotheek, zonder meteen te sturen', async () => {
    let calls = 0;
    const server = setup({
      'POST /libraries/l1/empty-trash': () =>
        ++calls === 1 ? apiError('server.internal', 500) : json({ items: 1, job_id: 'j' }, 202)
    });
    await open();
    await userEvent.click(screen.getByRole('button', { name: 'Prullenbak legen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Prullenbak legen' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Opnieuw proberen' }));
    const dialog = await screen.findByRole('dialog', { name: 'Prullenbak van Films legen?' });
    expect(posts(server, '/empty-trash')).toHaveLength(1);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Prullenbak legen' }));
    expect(await screen.findByText(/Films wordt geleegd: 1 titel /)).toBeInTheDocument();
    expect(posts(server, '/empty-trash').map((w) => w.path)).toEqual([
      '/libraries/l1/empty-trash',
      '/libraries/l1/empty-trash'
    ]);
  });
});
