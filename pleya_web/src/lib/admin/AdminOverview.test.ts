/**
 * Het overzicht tegen een nepserver: een kaart per kijker (direct play
 * tegenover omzetting), de lege staat, Stoppen bij een omzetsessie, de
 * taakacties, Scan alle bibliotheken en de tegels als links.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { StreamSessionSummary, TranscodeSession } from '../api/types';
import { setLocale } from '../i18n';
import { apiError, clientFor, json, library, root, scan } from './libraryFake';
import { job } from './opsFake';
import type { OverviewData } from './overview';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    info: null
  }
}));

import AdminOverview from './AdminOverview.svelte';

const films = library('l1', 'Films', { item_count: 461 });
const series = library('l2', 'Series', { kind: 'shows', item_count: 97 });

const STREAM: StreamSessionSummary = {
  id: 'ss-1',
  user_id: 'u1',
  username: 'Michel',
  device_name: 'MacBook van Michel',
  item_id: 'i1',
  item_title: 'Severance',
  item_kind: 'episode',
  position_ms: 21 * 60_000,
  duration_ms: 50 * 60_000,
  started_at: new Date(Date.now() - 21 * 60_000).toISOString(),
  expires_at: new Date(Date.now() + 3_600_000).toISOString()
};

const SESSION: TranscodeSession = {
  id: 't-1',
  user_id: 'u2',
  version_id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77',
  mode: 'transcode',
  hw_accel: 'vaapi',
  started_at: new Date(Date.now() - 8 * 60_000).toISOString(),
  last_heartbeat_at: new Date(Date.now() - 4_000).toISOString()
};

function overview(extra: Partial<OverviewData> = {}): OverviewData {
  return {
    server: { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: '2026-10-25T10:00:00Z' },
    libraries: [films, series],
    users: [
      { id: 'u1', username: 'Michel', role: 'owner' },
      { id: 'u2', username: 'Sanne', role: 'member' }
    ],
    scans: [],
    jobs: [],
    roots: [root('/m/Films', films), root('/m/Series', series)],
    streams: [],
    transcode: { max_sessions: 0, hardware: { accel: 'none', reason: null }, items: [] },
    ...extra
  } as OverviewData;
}

/** Elke schrijfaanvraag slaagt, tenzij `fail` er een antwoord voor geeft. */
function setup(fail: Record<string, Response> = {}) {
  const writes: string[] = [];
  h.client = clientFor(async (input, init) => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const key = `${request.method} ${new URL(request.url).pathname.slice('/pleya/v1'.length)}`;
    writes.push(key);
    if (fail[key]) return fail[key].clone();
    if (request.method === 'DELETE') return new Response(null, { status: 204 });
    return json(key.includes('/jobs/') ? job('j') : { id: 'new', state: 'queued' }, 202);
  });
  return writes;
}

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('overzicht, nu aan het kijken', () => {
  it('toont een kaart per kijker, met direct play tegenover omzetting', () => {
    setup();
    render(AdminOverview, {
      data: overview({
        streams: [STREAM],
        transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [SESSION] }
      })
    });

    const direct = screen.getByRole('heading', { level: 4, name: 'Severance' }).closest('article')!;
    expect(direct).toHaveTextContent('Michel · MacBook van Michel');
    expect(direct).toHaveTextContent('Direct afspelen');
    expect(direct).toHaveTextContent('42% · 21 min van 50 min');
    expect(within(direct).getByRole('progressbar', { name: 'Voortgang 42 procent' })).toHaveValue(42);
    // Een browserstream heeft geen stoproute, dus ook geen knop.
    expect(within(direct).queryByRole('button')).toBeNull();

    const converting = screen.getByRole('heading', { level: 4, name: 'Omzetsessie' }).closest('article')!;
    expect(converting).toHaveTextContent('Sanne · versie 0191f2a4');
    expect(converting).toHaveTextContent('Omzetting · VAAPI');
    expect(converting).not.toHaveTextContent('Direct afspelen');
    // De omzetsessie draagt geen positie: geen balk en geen verzonnen percentage.
    expect(within(converting).queryByRole('progressbar')).toBeNull();
    expect(
      within(converting).getByRole('button', { name: 'Transcodesessie van Sanne stoppen' })
    ).toBeEnabled();

    expect(screen.getByText('2 kijkers · 1 omzetting')).toBeInTheDocument();
  });

  it('laat de voortgang weg als de server geen positie meldt', () => {
    setup();
    const { position_ms: _p, duration_ms: _d, ...fresh } = STREAM;
    render(AdminOverview, { data: overview({ streams: [fresh] }) });
    const card = screen.getByRole('heading', { level: 4, name: 'Severance' }).closest('article')!;
    expect(within(card).queryByRole('progressbar')).toBeNull();
    expect(card).not.toHaveTextContent('%');
    expect(screen.getByText('1 kijker')).toBeInTheDocument();
  });

  it('zegt dat er niemand kijkt als beide lijsten leeg zijn', () => {
    setup();
    render(AdminOverview, { data: overview() });
    expect(screen.getByText('Er kijkt nu niemand in de browser.')).toBeInTheDocument();
    expect(screen.queryByRole('article')).toBeNull();
    expect(screen.queryByText(/kijker/)).toBeNull();
  });

  it('stopt een omzetsessie pas na de bevestiging en leest daarna opnieuw', async () => {
    const writes = setup();
    const onreload = vi.fn();
    render(AdminOverview, {
      data: overview({
        transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [SESSION] }
      }),
      onreload
    });

    await userEvent.click(screen.getByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('De speler van Sanne stopt');
    expect(writes).toEqual([]);

    await userEvent.click(within(dialog).getByRole('button', { name: 'Stoppen' }));
    await waitFor(() => expect(writes).toEqual(['DELETE /transcode-sessions/t-1']));
    await waitFor(() => expect(onreload).toHaveBeenCalledTimes(1));
  });

  it('meldt een geweigerde stop en leest opnieuw als de sessie al weg is', async () => {
    setup({ 'DELETE /transcode-sessions/t-1': apiError('library.not_found', 404) });
    const onreload = vi.fn();
    render(AdminOverview, {
      data: overview({
        transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [SESSION] }
      }),
      onreload
    });
    await userEvent.click(screen.getByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(onreload).toHaveBeenCalledTimes(1);
  });

  it('probeert na een mislukte stop dezelfde sessie opnieuw, ook als daarna een andere is aangeklikt', async () => {
    const writes = setup({ 'DELETE /transcode-sessions/t-1': new Response('{}', { status: 500 }) });
    const OTHER = { ...SESSION, id: 't-2', user_id: 'u1' };
    render(AdminOverview, {
      data: overview({
        transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [SESSION, OTHER] }
      }),
      onreload: vi.fn()
    });
    await userEvent.click(screen.getByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    const retry = await screen.findByRole('button', { name: /Opnieuw proberen/ });
    await userEvent.click(screen.getByRole('button', { name: 'Transcodesessie van Michel stoppen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Annuleren' }));
    await userEvent.click(retry);
    await waitFor(() => expect(writes.filter((w: string) => w.startsWith('DELETE'))).toHaveLength(2));
    expect(writes).not.toContain('DELETE /transcode-sessions/t-2');
  });
});

describe('overzicht, taken en acties', () => {
  const RUNNING = scan('l2', 'running', { id: 's-run' });
  const RUN_JOB = job('j-run', { state: 'running', scan_id: 's-run', library_id: 'l2', last_error: null, finished_at: null });
  const FAILED_JOB = job('j-fail', { kind: 'backup_verify', state: 'failed' });

  it('breekt een lopende scan af via zijn job', async () => {
    const writes = setup();
    const onreload = vi.fn();
    render(AdminOverview, { data: overview({ scans: [RUNNING], jobs: [RUN_JOB] }), onreload });
    await userEvent.click(screen.getByRole('button', { name: 'Scan Series afbreken' }));
    await waitFor(() => expect(writes).toEqual(['POST /jobs/j-run/cancel']));
    expect(await screen.findByText(/Scan Series wordt gestopt/)).toBeInTheDocument();
    expect(onreload).toHaveBeenCalledTimes(1);
  });

  it('probeert een mislukte taak opnieuw', async () => {
    const writes = setup();
    render(AdminOverview, { data: overview({ jobs: [FAILED_JOB] }) });
    await userEvent.click(
      screen.getByRole('button', { name: 'Controle van een back-up mislukt opnieuw proberen' })
    );
    await waitFor(() => expect(writes).toEqual(['POST /jobs/j-fail/retry']));
    expect(await screen.findByText(/staat weer in de wachtrij/)).toBeInTheDocument();
  });

  it('scant alle bibliotheken en slaat een niet-gemounte root over', async () => {
    const writes = setup();
    render(AdminOverview, {
      data: overview({ roots: [root('/m/Films', films), root('/m/Series', series, { mounted: false })] })
    });
    await userEvent.click(screen.getByRole('button', { name: 'Scan alle bibliotheken' }));
    await waitFor(() => expect(writes).toEqual(['POST /libraries/l1/scan']));
    const notice = await screen.findByText(/1 in de wachtrij gezet/);
    expect(notice).toHaveTextContent('1 overgeslagen omdat een root niet gemount is');
  });
});

describe('overzicht, indeling', () => {
  it('zet de kijkers voor de taken en de tegels onderaan, als links naar hun sectie', () => {
    setup();
    const { container } = render(AdminOverview, {
      data: overview({
        transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [] }
      })
    });
    const order = [...container.querySelectorAll('h3, a.tile')].map(
      (el) => el.getAttribute('href') ?? el.textContent?.trim()
    );
    expect(order).toEqual([
      'Nu aan het kijken',
      'Taken en activiteit',
      'Server',
      '/admin/libraries',
      '/admin/storage',
      '/admin/users',
      '/admin/activity'
    ]);
    expect(screen.getByRole('link', { name: /Gebruikers\s*2/ })).toHaveAttribute('href', '/admin/users');
    // De omzetter verhuisde van het kijkpaneel naar het serverblok.
    expect(screen.getByText('Omzetter').nextElementSibling).toHaveTextContent('0 van 2 sessies · vaapi');
  });
});
