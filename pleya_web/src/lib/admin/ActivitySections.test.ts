/**
 * Activiteit tegen een nepserver: de geplande taken per bibliotheek met Nu
 * uitvoeren, en het logpaneel met niveau en zoeken.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { job, library, opsFake, root, scan } from './opsFake';

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

/**
 * "Scan Films" staat ook bij Geplande taken; dit wijst de rij in de Geschiedenis aan.
 */
function historyRow(text: string): HTMLElement {
  return screen.getAllByText(text).map((el) => el.closest('tr')).find(Boolean) as HTMLElement;
}

beforeEach(() => setLocale('nl'));
afterEach(() => {
  setLocale('en');
  vi.useRealTimers();
});

describe('activiteit, geplande taken', () => {
  it('toont per bibliotheek het schema en de laatste keer, met een link naar het schema', async () => {
    setup({ libraries: [library('l1', 'Films', { scan_interval_seconds: 21600 }), series], scans: [DONE], jobs: [] });
    render(ActivityPage);
    const panel = await screen.findByRole('region', { name: 'Geplande taken' });
    const rows = within(panel).getAllByRole('listitem');
    expect(rows[0]).toHaveTextContent('Scan Films');
    expect(rows[0]).toHaveTextContent('Elke 6 uur, en bij het opstarten');
    expect(rows[1]).toHaveTextContent('Standaard van de server, en bij het opstarten');
    expect(rows[1]).toHaveTextContent('nog niet gescand');
    expect(within(panel).getByRole('link', { name: 'Schema van Films wijzigen' })).toHaveAttribute(
      'href',
      '/admin/libraries/l1'
    );
  });

  it('start met de ronde knop een scan van die ene bibliotheek', async () => {
    const server = setup({ scans: [DONE], jobs: [] });
    render(ActivityPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Scan Films nu uitvoeren' }));
    expect(await screen.findByText('De scan van Films staat in de wachtrij.')).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /libraries/l1/scan']);
  });

  it('biedt de knop niet aan zolang de scan loopt of een root niet gemount is', async () => {
    const server = setup({
      roots: [root('/m/Films', films), root('/m/Series', series), root('/m/Boeken', boeken, { mounted: false })],
      scans: [RUNNING, DONE]
    });
    render(ActivityPage);
    expect(await screen.findByRole('button', { name: 'Scan Series nu uitvoeren' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Scan Boeken nu uitvoeren' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Scan Films nu uitvoeren' })).toBeEnabled();
    expect(server.writes()).toEqual([]);
  });
});

describe('activiteit, log', () => {
  const LOG = [
    { at: '2026-10-26T14:31:07Z', level: 'error', component: 'scanner', message: 'ffprobe gaf na 60 s geen antwoord' },
    { at: '2026-10-26T08:00:03Z', level: 'warn', component: 'scanner', message: 'root /m/Boeken niet gemount' },
    { at: '2026-10-26T07:00:00Z', level: 'info', component: 'http', message: 'server luistert' }
  ];

  it('vraagt eerst waarschuwingen en hoger, en bij een ander niveau opnieuw', async () => {
    const server = setup({ scans: [], jobs: [], log: LOG });
    render(ActivityPage);
    const panel = await screen.findByRole('region', { name: 'Log' });
    expect(await within(panel).findByText(/ffprobe gaf na 60 s/)).toBeInTheDocument();
    expect(within(panel).queryByText(/server luistert/)).toBeNull();
    expect(server.seen.map((s) => s.path)).toContain('/server/log?level=warn&limit=200');

    await userEvent.selectOptions(within(panel).getByRole('combobox', { name: 'Niveau' }), 'error');
    await waitFor(() => expect(within(panel).queryByText(/niet gemount/)).toBeNull());
    expect(server.seen.map((s) => s.path)).toContain('/server/log?level=error&limit=200');
  });

  it('zoekt in de opgehaalde regels zonder nieuwe aanvraag', async () => {
    const server = setup({ scans: [], jobs: [], log: LOG });
    render(ActivityPage);
    const panel = await screen.findByRole('region', { name: 'Log' });
    await within(panel).findByText(/ffprobe/);
    const before = server.seen.length;
    await userEvent.type(within(panel).getByRole('searchbox', { name: 'Zoeken' }), 'boeken');
    expect(within(panel).queryByText(/ffprobe/)).toBeNull();
    expect(within(panel).getByText(/niet gemount/)).toBeInTheDocument();
    await userEvent.type(within(panel).getByRole('searchbox', { name: 'Zoeken' }), 'xyz');
    expect(within(panel).getByText('Geen regel met "boekenxyz" in de opgehaalde regels.')).toBeInTheDocument();
    expect(server.seen.length).toBe(before);
  });

  it('laat scans en taken staan als de log niet te lezen is', async () => {
    setup({ scans: [DONE], jobs: [] });
    render(ActivityPage);
    const panel = await screen.findByRole('region', { name: 'Log' });
    expect(await within(panel).findByText('De log is nu niet te lezen.')).toBeInTheDocument();
    expect(historyRow('Scan Films')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
