/**
 * Scherm 37 tegen een nepserver: de lijst met sessies, Stoppen achter een
 * bevestiging, wat er gebeurt als de server weigert, en het verversen dat
 * ophoudt bij een lege lijst.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { TranscodeSession } from '../../api/types';
import { setLocale } from '../../i18n';
import { apiError, baseInfo, settingsFake, user } from '../settings/settingsFake';

const h = vi.hoisted(() => ({ client: null as unknown, info: null as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    get info() {
      return h.info;
    }
  }
}));

import TranscodePage from './TranscodePage.svelte';

const mk = (id: string, userId: string, extra: Partial<TranscodeSession> = {}): TranscodeSession => ({
  id,
  user_id: userId,
  version_id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77',
  mode: 'transcode',
  hw_accel: 'vaapi',
  started_at: new Date(Date.now() - 8 * 60_000).toISOString(),
  last_heartbeat_at: new Date(Date.now() - 4_000).toISOString(),
  ...extra
});

function setup(
  options: Parameters<typeof settingsFake>[0] = {},
  capabilities: Record<string, boolean> = {}
) {
  const server = settingsFake({
    users: [user('u1', 'Sanne'), user('u2', 'Kids')],
    transcode: {
      max_sessions: 2,
      hardware: { accel: 'vaapi', reason: null },
      items: [mk('t1', 'u1'), mk('t2', 'u2', { hw_accel: null, mode: 'remux' })]
    },
    ...options
  });
  h.client = server.client;
  const info = baseInfo();
  Object.assign(info.capabilities, capabilities);
  h.info = info;
  return server;
}

const listCalls = (server: ReturnType<typeof setup>) =>
  server.seen.filter((s) => s.method === 'GET' && s.path === '/transcode-sessions').length;

beforeEach(() => setLocale('nl'));
afterEach(() => {
  setLocale('en');
  vi.useRealTimers();
});

describe('scherm 37, de lijst', () => {
  it('toont per sessie de gebruiker, de omzetting en de hardware, en de tegels', async () => {
    setup();
    render(TranscodePage);
    const row = (await screen.findByText('Sanne')).closest('tr') as HTMLElement;
    expect(row).toHaveTextContent('omzetten');
    expect(row).toHaveTextContent('VAAPI');
    expect(row).toHaveTextContent('versie 0191f2a4');
    const soft = screen.getByText('Kids').closest('tr') as HTMLElement;
    expect(soft).toHaveTextContent('remux');
    expect(soft).toHaveTextContent('software');
    expect(screen.getByText('2 sessies lopen')).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Transcode-sessies');
  });

  it('meldt het maximum bij een volle server en niet eronder', async () => {
    setup();
    const { unmount } = render(TranscodePage);
    expect(await screen.findByText('De server draait op zijn maximum.')).toBeInTheDocument();
    unmount();

    setup({
      transcode: {
        max_sessions: 3,
        hardware: { accel: 'vaapi', reason: null },
        items: [mk('t1', 'u1')]
      }
    });
    render(TranscodePage);
    await screen.findByText('Sanne');
    expect(screen.queryByText('De server draait op zijn maximum.')).not.toBeInTheDocument();
  });

  it('toont een nette lege toestand en noemt de reden dat er geen hardware is', async () => {
    setup({
      transcode: { max_sessions: 2, hardware: { accel: 'none', reason: 'geen render node' }, items: [] }
    });
    render(TranscodePage);
    expect(await screen.findByText('Er lopen geen transcode-sessies.')).toBeInTheDocument();
    expect(screen.getByText('geen render node')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /stoppen/i })).not.toBeInTheDocument();
  });

  it('toont zonder omzetter geen sessielijst en geen stopknop', async () => {
    setup({}, { transcode: false });
    render(TranscodePage);
    expect(await screen.findByText('Transcoderen staat uit.')).toBeInTheDocument();
    expect(screen.queryByText('Sanne')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /stoppen/i })).not.toBeInTheDocument();
  });

  it('zegt dat het maximum 0 transcoderen uitzet', async () => {
    setup({ transcode: { max_sessions: 0, hardware: { accel: 'none', reason: null }, items: [] } });
    render(TranscodePage);
    expect(await screen.findByText('een maximum van 0 zet transcoderen uit')).toBeInTheDocument();
    expect(screen.queryByText('De server draait op zijn maximum.')).not.toBeInTheDocument();
  });

  it('geeft een onleesbare pagina een opnieuw-proberen als de lijst niet laadt', async () => {
    setup({ fail: { 'GET /transcode-sessions': () => apiError('server.internal', 500) } });
    render(TranscodePage);
    expect(await screen.findByRole('button', { name: /opnieuw/i })).toBeInTheDocument();
  });
});

describe('scherm 37, Stoppen', () => {
  const open = async (ui: ReturnType<typeof userEvent.setup>) =>
    ui.click(await screen.findByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));

  it('stuurt niets zonder bevestiging en zegt dat de kijker onderbroken wordt', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TranscodePage);
    await open(ui);
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveTextContent('Sanne');
    expect(dialog).toHaveTextContent('moet opnieuw beginnen');
    expect(server.writes()).toEqual([]);

    await ui.click(within(dialog).getByRole('button', { name: /annuleren/i }));
    expect(server.writes()).toEqual([]);
    expect(screen.getByText('Sanne')).toBeInTheDocument();
  });

  it('stopt na bevestiging precies die sessie en leest de lijst opnieuw', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TranscodePage);
    await open(ui);
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    await waitFor(() => expect(server.writes()).toEqual(['DELETE /transcode-sessions/t1']));
    await waitFor(() => expect(screen.queryByText('Sanne')).not.toBeInTheDocument());
    expect(screen.getByText('Kids')).toBeInTheDocument();
  });

  it('laat de lijst intact als de server weigert, met een zin en een uitweg', async () => {
    const server = setup({
      fail: { 'DELETE /transcode-sessions/t1': () => apiError('server.database_unavailable', 503) }
    });
    const ui = userEvent.setup();
    render(TranscodePage);
    await open(ui);
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/database/i);
    expect(within(alert).getByRole('button', { name: /opnieuw/i })).toBeInTheDocument();
    // Niets is verdwenen en er is niet nog eens naar de lijst gevraagd om hem leeg te maken.
    expect(screen.getByText('Sanne')).toBeInTheDocument();
    expect(screen.getByText('Kids')).toBeInTheDocument();
    expect(server.writes()).toEqual(['DELETE /transcode-sessions/t1']);
  });

  it('legt uit dat de sessie al weg is en leest dan wel de lijst opnieuw', async () => {
    const server = setup({
      fail: { 'DELETE /transcode-sessions/t1': () => apiError('library.not_found', 404) }
    });
    const ui = userEvent.setup();
    render(TranscodePage);
    await open(ui);
    const before = listCalls(server);
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('De sessie van Sanne is al afgelopen');
    await waitFor(() => expect(listCalls(server)).toBe(before + 1));
  });
});

describe('scherm 37, verversen', () => {
  it('ververst elke vijf seconden zolang er sessies zijn, en daarna niet meer', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup();
    render(TranscodePage);
    await screen.findByText('Sanne');
    expect(listCalls(server)).toBe(1);
    await vi.advanceTimersByTimeAsync(5100);
    await waitFor(() => expect(listCalls(server)).toBe(2));

    // De sessies zijn weg: de volgende stand houdt het verversen op.
    server.state.transcode.items = [];
    await vi.advanceTimersByTimeAsync(5100);
    await waitFor(() => expect(listCalls(server)).toBe(3));
    await screen.findByText('Er lopen geen transcode-sessies.');
    await vi.advanceTimersByTimeAsync(30_000);
    expect(listCalls(server)).toBe(3);
  });

  it('ververst niet als er bij het openen al niets loopt', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup({
      transcode: { max_sessions: 2, hardware: { accel: 'vaapi', reason: null }, items: [] }
    });
    render(TranscodePage);
    await screen.findByText('Er lopen geen transcode-sessies.');
    await vi.advanceTimersByTimeAsync(30_000);
    expect(listCalls(server)).toBe(1);
  });

  it('houdt de staande lijst na een mislukte verversing en stopt tot de bezoeker kiest', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let calls = 0;
    const ok = () =>
      new Response(
        JSON.stringify({
          max_sessions: 2,
          hardware: { accel: 'vaapi', reason: null },
          items: [mk('t1', 'u1')]
        }),
        { status: 200, headers: { 'content-type': 'application/json' } }
      );
    // De eerste aanvraag slaagt, elke volgende faalt.
    const flaky = settingsFake({
      users: [user('u1', 'Sanne')],
      fail: {
        'GET /transcode-sessions': () => {
          calls += 1;
          return calls === 1 ? ok() : apiError('server.internal', 500);
        }
      }
    });
    h.client = flaky.client;
    render(TranscodePage);
    await screen.findByText('Sanne');
    await vi.advanceTimersByTimeAsync(5100);
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.getByText('Sanne')).toBeInTheDocument();
    const seen = calls;
    await vi.advanceTimersByTimeAsync(30_000);
    expect(calls).toBe(seen);
  });
});
