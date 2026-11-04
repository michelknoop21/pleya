/**
 * Scherm 25 tegen een nepserver: wat er loopt, de fouten, de geschiedenis, en
 * de drie schrijfacties (Alles scannen, Afbreken, Nu opnieuw) met hun
 * foutpaden.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, job, library, opsFake, root, scan } from './opsFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import ActivityPage from './ActivityPage.svelte';

const films = library('l1', 'Films');
const series = library('l2', 'Series', { kind: 'shows' });
const boeken = library('l3', 'Boeken');

const RUNNING = scan('l2', 'running', {
  id: 's-run',
  files_seen: 3104,
  files_probed: 41,
  files_renamed: 2,
  bytes_hashed: 128_000_000,
  current_path: '…/Severance.S02E07.mkv'
});
const DONE = scan('l1', 'done', {
  id: 's-done',
  files_seen: 28412,
  files_new: 3,
  started_at: '2026-10-25T08:00:00Z',
  finished_at: '2026-10-25T08:11:00Z'
});
const FAILED_SCAN = scan('l3', 'failed', {
  id: 's-fail',
  last_error: 'root niet gemount',
  started_at: '2026-10-25T07:00:00Z',
  finished_at: '2026-10-25T07:00:05Z',
  files_seen: 0
});

function setup(overrides: Parameters<typeof opsFake>[0] = {}) {
  const server = opsFake({
    libraries: [films, series, boeken],
    roots: [root('/m/Films', films), root('/m/Series', series), root('/m/Boeken', boeken)],
    scans: [RUNNING, DONE, FAILED_SCAN],
    jobs: [job('j-run', { kind: 'scan_library', state: 'running', scan_id: 's-run', library_id: 'l2', last_error: null, attempts: 1, finished_at: null })],
    ...overrides
  });
  h.client = server.client;
  return server;
}

beforeEach(() => setLocale('nl'));
afterEach(() => {
  setLocale('en');
  vi.useRealTimers();
});

describe('scherm 25, wat er loopt', () => {
  it('toont de lopende scan met de tellers van de server en zijn huidige bestand', async () => {
    const server = setup();
    render(ActivityPage);

    const running = await screen.findByText('Scan Series');
    const body = running.closest('li') as HTMLElement;
    expect(body).toHaveTextContent('3.104 bestanden gezien');
    expect(body).toHaveTextContent('41 geanalyseerd');
    expect(body).toHaveTextContent('2 hernoemd');
    expect(body).toHaveTextContent('128 MB gehasht');
    expect(within(body).getByText('…/Severance.S02E07.mkv')).toBeInTheDocument();
    expect(screen.getByText('1 taak')).toBeInTheDocument();
    // Geen verzonnen percentage of voortgangsbalk.
    expect(screen.queryByRole('progressbar')).toBeNull();
    expect(screen.queryByText(/%/)).toBeNull();
    expect(server.writes()).toEqual([]);
  });

  it('zegt dat er niets loopt als er geen actieve scan is', async () => {
    setup({ scans: [DONE], jobs: [] });
    render(ActivityPage);
    expect(await screen.findByText('Er loopt nu niets.')).toBeInTheDocument();
  });

  it('breekt af via de job van de scan, zonder bevestiging, en meldt dat hij stopt', async () => {
    const server = setup();
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Scan Series afbreken' }));

    await waitFor(() => expect(server.writes()).toEqual(['POST /jobs/j-run/cancel']));
    expect(await screen.findByText(/Scan Series wordt gestopt/)).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Scan Series afbreken' })).toBeDisabled()
    );
  });

  it('biedt geen Afbreken aan voor een scan zonder vindbare job', async () => {
    setup({ jobs: [] });
    render(ActivityPage);
    await screen.findByText('Scan Series');
    expect(screen.queryByRole('button', { name: /afbreken/ })).toBeNull();
  });

  it('wijst een job die al klaar was af met een zin en ververst de stand', async () => {
    const server = setup({
      fail: { 'POST /jobs/j-run/cancel': apiError('job.not_cancellable', 409, { reason: 'finished' }) }
    });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Scan Series afbreken' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Scan Series is al klaar, dus er valt niets af te breken');
    expect(within(alert).getByRole('button', { name: 'Opnieuw laden' })).toBeInTheDocument();
    expect(screen.queryByText(/wordt gestopt/)).toBeNull();
    // De lijst werd opnieuw gelezen: GET /jobs staat er nu twee keer.
    await waitFor(() => expect(server.seen.filter((s) => s.path.startsWith('/jobs?')).length).toBe(2));
  });

  it('ververst elke vijf seconden zolang er iets loopt, en daarna niet meer', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup();
    render(ActivityPage);
    await screen.findByText('Scan Series');
    const count = () => server.seen.filter((s) => s.path.startsWith('/jobs?')).length;
    expect(count()).toBe(1);
    await vi.advanceTimersByTimeAsync(5100);
    await waitFor(() => expect(count()).toBe(2));

    // Nu loopt er niets meer: de volgende stand houdt het verversen op.
    server.state.scans = [DONE];
    server.state.jobs = [];
    await vi.advanceTimersByTimeAsync(5100);
    await waitFor(() => expect(count()).toBe(3));
    await vi.advanceTimersByTimeAsync(20_000);
    expect(count()).toBe(3);
  });

  it('ververst niet voor een taak die pas morgen aan de beurt is', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const later = job('j-later', {
      kind: 'backup_create',
      state: 'pending',
      run_at: '2099-01-01T00:00:00Z',
      finished_at: null,
      last_error: null
    });
    const server = setup({ scans: [DONE], jobs: [later] });
    render(ActivityPage);
    await screen.findByText('Er loopt nu niets.');
    await vi.advanceTimersByTimeAsync(20_000);
    expect(server.seen.filter((s) => s.path.startsWith('/jobs?')).length).toBe(1);
  });
});

describe('scherm 25, fouten', () => {
  const failed = job('j-fail', { library_id: 'l1', state: 'failed' });

  it('toont een mislukte job met melding en poging, en een root die niet gemount is', async () => {
    setup({
      scans: [DONE],
      jobs: [failed],
      roots: [root('/m/Films', films), root('/m/Boeken', boeken, { mounted: false })]
    });
    render(ActivityPage);

    const item = (await screen.findByText('Scan van Films mislukt')).closest('li') as HTMLElement;
    expect(item).toHaveTextContent('ffprobe gaf na 60 s geen antwoord');
    expect(item).toHaveTextContent('poging 3 van 3');
    const rootRow = screen.getByText('Root niet bereikbaar').closest('li') as HTMLElement;
    expect(within(rootRow).getByText('/m/Boeken')).toBeInTheDocument();
    expect(within(rootRow).getByRole('link', { name: 'Opslag' })).toHaveAttribute('href', '/admin/storage');
    expect(screen.getByText('2 open')).toBeInTheDocument();
    // De server kent geen Overslaan, dus de knop bestaat niet.
    expect(screen.queryByRole('button', { name: /overslaan/i })).toBeNull();
  });

  it('probeert een job opnieuw met één POST', async () => {
    const server = setup({ scans: [DONE], jobs: [failed] });
    render(ActivityPage);
    await userEvent.click(
      await screen.findByRole('button', { name: 'Scan van Films mislukt opnieuw proberen' })
    );
    await waitFor(() => expect(server.writes()).toEqual(['POST /jobs/j-fail/retry']));
    expect(await screen.findByText(/Scan van Films mislukt staat weer in de wachtrij/)).toBeInTheDocument();
  });

  it('zegt bij een dubbele taak dat er al een staat, en wijst naar opnieuw laden', async () => {
    setup({
      scans: [DONE],
      jobs: [failed],
      fail: {
        'POST /jobs/j-fail/retry': apiError('job.not_cancellable', 409, { reason: 'duplicate_in_flight' })
      }
    });
    render(ActivityPage);
    await userEvent.click(
      await screen.findByRole('button', { name: 'Scan van Films mislukt opnieuw proberen' })
    );
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('gelijke taak in de wachtrij of in uitvoering');
    expect(screen.queryByText(/staat weer in de wachtrij/)).toBeNull();
    expect(screen.getByText('Scan van Films mislukt')).toBeInTheDocument();
  });

  it('kent een soort taak die de client niet kent bij naam van de soort', async () => {
    setup({ scans: [DONE], jobs: [job('j-x', { kind: 'toekomstige_taak' })] });
    render(ActivityPage);
    const item = (await screen.findByText('Taak mislukt')).closest('li') as HTMLElement;
    expect(within(item).getByText('toekomstige_taak')).toBeInTheDocument();
  });

  it('zegt dat er niets mis is als er geen fouten zijn', async () => {
    setup({ scans: [DONE], jobs: [] });
    render(ActivityPage);
    expect(await screen.findByText(/Geen mislukte taken/)).toBeInTheDocument();
  });
});

describe('scherm 25, laatste scan mislukt', () => {
  it('noemt een bibliotheek waarvan de laatste scan mislukte, met de melding van de server', async () => {
    setup({ scans: [DONE, FAILED_SCAN], jobs: [] });
    render(ActivityPage);

    const item = (await screen.findByText('Laatste scan van Boeken mislukt')).closest('li') as HTMLElement;
    expect(item).toHaveTextContent('root niet gemount');
    expect(item).toHaveTextContent('Gestopt');
    expect(within(item).getByRole('button', { name: 'Scan van Boeken nu starten' })).toBeInTheDocument();
    expect(screen.queryByText(/Geen mislukte taken/)).toBeNull();
  });

  it('start een scan van die ene bibliotheek en zegt dat hij in de wachtrij staat', async () => {
    const server = setup({ scans: [DONE, FAILED_SCAN], jobs: [] });
    render(ActivityPage);

    await userEvent.click(await screen.findByRole('button', { name: 'Scan van Boeken nu starten' }));

    await waitFor(() => expect(server.writes()).toEqual(['POST /libraries/l3/scan']));
    expect(await screen.findByText('De scan van Boeken staat in de wachtrij.')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('telt een 409 als "wacht of loopt al" en niet als fout', async () => {
    setup({
      scans: [DONE, FAILED_SCAN],
      jobs: [],
      fail: { 'POST /libraries/l3/scan': apiError('library.scan_in_progress', 409) }
    });
    render(ActivityPage);

    await userEvent.click(await screen.findByRole('button', { name: 'Scan van Boeken nu starten' }));

    expect(await screen.findByText('Er wacht of loopt al een scan van Boeken.')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('toont een fout van de server met een nieuwe poging op dezelfde bibliotheek', async () => {
    const server = setup({
      scans: [DONE, FAILED_SCAN],
      jobs: [],
      fail: { 'POST /libraries/l3/scan': apiError('server.internal', 500) }
    });
    render(ActivityPage);

    await userEvent.click(await screen.findByRole('button', { name: 'Scan van Boeken nu starten' }));

    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /libraries/l3/scan']);
    expect(screen.getByText('Laatste scan van Boeken mislukt')).toBeInTheDocument();
  });

  it('meldt een bibliotheek met een niet-gemounte root alleen als root, zonder scanknop', async () => {
    const server = setup({
      scans: [DONE, FAILED_SCAN],
      jobs: [],
      roots: [root('/m/Films', films), root('/m/Series', series), root('/m/Boeken', boeken, { mounted: false })]
    });
    render(ActivityPage);

    expect(await screen.findByText('Root niet bereikbaar')).toBeInTheDocument();
    expect(screen.queryByText('Laatste scan van Boeken mislukt')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Scan van Boeken nu starten' })).toBeNull();
    expect(server.writes()).toEqual([]);
  });

  it('laat een bibliotheek met een nieuwere scan niet meer als mislukt staan', async () => {
    const newer = scan('l3', 'done', { id: 's-new', started_at: '2026-10-26T09:00:00Z', finished_at: '2026-10-26T09:01:00Z' });
    setup({ scans: [newer, FAILED_SCAN], jobs: [] });
    render(ActivityPage);

    expect(await screen.findByText(/Geen mislukte taken/)).toBeInTheDocument();
    expect(screen.queryByText('Laatste scan van Boeken mislukt')).toBeNull();
  });
});

describe('scherm 25, alles scannen', () => {
  it('start een scan per bibliotheek zonder lopende scan en slaat de rest over', async () => {
    const server = setup({
      scans: [RUNNING, DONE],
      roots: [
        root('/m/Films', films),
        root('/m/Series', series),
        root('/m/Boeken', boeken, { mounted: false })
      ]
    });
    render(ActivityPage);
    await screen.findByText('Scan Series');
    expect(server.writes()).toEqual([]);
    await userEvent.click(screen.getByRole('button', { name: 'Alles scannen' }));

    // Films start, Series loopt al, Boeken heeft een root die niet gemount is.
    await waitFor(() => expect(server.writes()).toEqual(['POST /libraries/l1/scan']));
    const notice = await screen.findByText(/1 in de wachtrij gezet/);
    expect(notice).toHaveTextContent('1 stond al in de wachtrij of liep al');
    expect(notice).toHaveTextContent('1 overgeslagen omdat een root niet gemount is');
  });

  it('telt een 409 van de server als "stond al in de wachtrij" en niet als fout', async () => {
    setup({
      scans: [DONE],
      jobs: [],
      fail: { 'POST /libraries/l2/scan': apiError('library.scan_in_progress', 409) }
    });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Alles scannen' }));
    const notice = await screen.findByText(/in de wachtrij gezet/);
    expect(notice).toHaveTextContent('2 in de wachtrij gezet');
    expect(notice).toHaveTextContent('1 stond al in de wachtrij');
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('toont een falende scanstart als fout en laat de lijsten intact', async () => {
    const server = setup({
      scans: [DONE],
      jobs: [],
      fail: { 'POST /libraries/l1/scan': apiError('server.database_unavailable', 503) }
    });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Alles scannen' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('database');
    expect(within(alert).getByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
    // De rest van het scherm blijft staan, en de scans die wel lukten zijn gemeld.
    expect(screen.getByText('Scan Films')).toBeInTheDocument();
    expect(screen.getByText(/2 in de wachtrij gezet/)).toBeInTheDocument();
    expect(server.writes()).toContain('POST /libraries/l1/scan');
  });
});

describe('scherm 25, geschiedenis', () => {
  it('toont tellers, duur en status per scan, en bij een mislukte scan zijn melding', async () => {
    setup({ scans: [DONE, FAILED_SCAN], jobs: [] });
    render(ActivityPage);
    const done = (await screen.findByText('Scan Films')).closest('tr') as HTMLElement;
    expect(done).toHaveTextContent('11 min');
    expect(done).toHaveTextContent('28.412 bestanden gezien · 3 nieuw · 0 ontbrekend');
    expect(within(done).getByText('klaar')).toBeInTheDocument();
    expect(within(done).getByText('handmatig')).toBeInTheDocument();

    const failed = screen.getByText('Scan Boeken').closest('tr') as HTMLElement;
    expect(failed).toHaveTextContent('root niet gemount');
    expect(within(failed).getByText('mislukt')).toBeInTheDocument();
  });

  it('laadt oudere scans met de cursor en toont geen knop meer op de laatste pagina', async () => {
    const older = scan('l1', 'done', { id: 's-old', started_at: '2026-10-01T08:00:00Z', finished_at: '2026-10-01T08:01:00Z' });
    const server = setup({ scans: [DONE], jobs: [], morePages: [[older]] });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Oudere tonen' }));

    await waitFor(() => expect(document.querySelectorAll('tr[data-scan]').length).toBe(2));
    expect(server.seen.some((s) => s.path.includes('cursor=page1'))).toBe(true);
    expect(screen.queryByRole('button', { name: 'Oudere tonen' })).toBeNull();
  });

  it('toont een verlopen cursor als fout met opnieuw laden en houdt de eerste pagina', async () => {
    setup({
      scans: [DONE],
      jobs: [],
      morePages: [[]],
      fail: { 'GET /scans?cursor=page1': apiError('library.cursor_invalid', 400) }
    });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Oudere tonen' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('De lijst veranderde terwijl je hem las');
    expect(within(alert).getByRole('button', { name: 'Opnieuw laden' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Oudere tonen' })).toBeInTheDocument();
    expect(document.querySelectorAll('tr[data-scan]').length).toBe(1);
  });

  it('zegt dat er nog geen scan is gelopen', async () => {
    setup({ scans: [], jobs: [] });
    render(ActivityPage);
    expect(await screen.findByText('Er is nog geen scan gelopen.')).toBeInTheDocument();
  });

  it('geeft een foutstaat met opnieuw proberen als de lijsten niet laden', async () => {
    setup({ fail: { 'GET /jobs': apiError('server.internal', 500) } });
    render(ActivityPage);
    expect(await screen.findByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
    expect(screen.queryByText('Scan Series')).toBeNull();
  });
});
