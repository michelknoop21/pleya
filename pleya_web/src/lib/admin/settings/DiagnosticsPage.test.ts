/**
 * Scherm 32 tegen een nepserver: versies, capabilities, gezondheid, omgeving en
 * log. De nadruk ligt op wat er niet op mag staan: een geheim komt nergens in
 * de DOM, in het rapport of in een aanvraag-URL, ook niet als de server zelf
 * een keer iets laat lekken.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { baseInfo, baseServer, settingsFake } from './settingsFake';
import { buildReport, capabilityFlags, maskEntry, maskLine, type LogEntry } from './diagnostics';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import DiagnosticsPage from './DiagnosticsPage.svelte';

const SECRET = 'hunter2-geheim-wachtwoord';

const ENV = [
  { key: 'PLEYA_SERVER_HTTP_ADDR', value: ':8080', redacted: false },
  { key: 'DATABASE_URL', value: 'postgres://pleya:•••@db:5432/pleya', redacted: true },
  // Zo hoort de server dit nooit te sturen. Het scherm houdt een tweede slot.
  { key: 'PLEYA_SERVER_BACKUP_KEY', value: SECRET, redacted: false },
  { key: 'PLEYA_SERVER_TMDB_KEY', value: SECRET, redacted: false },
  { key: 'PLEYA_SERVER_PEER_URL', value: `https://beheer:${SECRET}@peer.test/x`, redacted: false }
];

const LOG: LogEntry[] = [
  { at: '2026-10-26T14:02:11Z', level: 'warn', component: 'scanner', message: 'scan root not mounted root=/volume1/media/Boeken' },
  { at: '2026-10-26T08:11:47Z', level: 'error', component: 'ffprobe', message: `dial https://u:${SECRET}@host.test timeout` }
];

function setup(options: Parameters<typeof settingsFake>[0] = {}) {
  const server = settingsFake({ environment: ENV, log: LOG, ...options });
  h.client = server.client;
  return server;
}

beforeEach(() => setLocale('nl'));
afterEach(() => {
  setLocale('en');
  vi.restoreAllMocks();
});

describe('scherm 32, diagnostiek', () => {
  it('toont versies, protocol, database en gezondheid', async () => {
    setup();
    render(DiagnosticsPage);
    expect(await screen.findByText('0.9.0')).toBeInTheDocument();
    expect(screen.getByText('go1.23 linux/amd64')).toBeInTheDocument();
    expect(screen.getByText(/v1, feature level 1/)).toBeInTheDocument();
    expect(screen.getByText('Postgres 18.6, schema 8')).toBeInTheDocument();
    expect(screen.getByText('ffmpeg 5.1.9')).toBeInTheDocument();
    expect(screen.getByText('1 bezig, 2 mislukt')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Zie Scans en taken' })).toHaveAttribute('href', '/admin/activity');
  });

  it('toont aan en uit voor elke capability, aan eerst', async () => {
    setup();
    render(DiagnosticsPage);
    const on = (await screen.findByText('browse')).closest('li') as HTMLElement;
    expect(on).toHaveAttribute('data-on', 'true');
    const off = screen.getByText('live_tv').closest('li') as HTMLElement;
    expect(off).toHaveAttribute('data-on', 'false');
    expect(capabilityFlags(baseInfo()).findIndex((f) => !f.on)).toBeGreaterThan(
      capabilityFlags(baseInfo()).filter((f) => f.on).length - 1
    );
  });

  it('toont een geheim nergens, ook niet als de server het stuurt (negatieve controle)', async () => {
    const server = setup();
    render(DiagnosticsPage);
    await screen.findByText('PLEYA_SERVER_HTTP_ADDR');
    expect(document.body.innerHTML).not.toContain(SECRET);
    // De naam blijft, de waarde is gemaskeerd en zegt dat.
    const key = screen.getByText('PLEYA_SERVER_BACKUP_KEY');
    expect(within(key.nextElementSibling as HTMLElement).getByText('gemaskeerd')).toBeInTheDocument();
    // Een wachtwoord in een URL, in de omgeving en in een logregel.
    expect(screen.getByText(/https:\/\/beheer:•••@peer\.test\/x/)).toBeInTheDocument();
    expect(screen.getByText(/dial https:\/\/u:•••@host\.test timeout/)).toBeInTheDocument();
    // Geen enkele aanvraag draagt iets uit de omgeving in zijn URL.
    expect(server.seen.every((s) => !s.path.includes(SECRET))).toBe(true);
    expect(server.writes()).toEqual([]);
  });

  it('vraagt de log met niveau en grens als query, en toont de regels', async () => {
    const server = setup();
    render(DiagnosticsPage);
    expect(await screen.findByText(/scan root not mounted/)).toBeInTheDocument();
    expect(server.seen.some((s) => s.path === '/server/log?level=warn&limit=50')).toBe(true);
    expect(screen.getByText('error')).toBeInTheDocument();
  });

  it('zegt dat omgeving of log niet te lezen is in plaats van leeg te blijven', async () => {
    setup({
      fail: {
        'GET /server/environment': new Response('{}', { status: 500 }),
        'GET /server/log': new Response('{}', { status: 500 })
      }
    });
    render(DiagnosticsPage);
    expect(await screen.findByText('De omgeving is nu niet te lezen.')).toBeInTheDocument();
    expect(screen.getByText('De log is nu niet te lezen.')).toBeInTheDocument();
    // De rest van de pagina werkt gewoon.
    expect(screen.getByText('Postgres 18.6, schema 8')).toBeInTheDocument();
  });

  it('bewaart het rapport als bestand zonder aanvraag en zonder geheimen', async () => {
    const server = setup();
    const saved: Blob[] = [];
    vi.spyOn(URL, 'createObjectURL').mockImplementation((blob) => {
      saved.push(blob as Blob);
      return 'blob:test';
    });
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    const ui = userEvent.setup();
    render(DiagnosticsPage);
    await screen.findByText('0.9.0');
    const before = server.seen.length;
    await ui.click(screen.getByRole('button', { name: 'Rapport voor support' }));
    expect(click).toHaveBeenCalledTimes(1);
    expect(server.seen).toHaveLength(before);
    const text = await saved[0]!.text();
    expect(text).toContain('PLEYA_SERVER_HTTP_ADDR=:8080');
    expect(text).toContain('postgres 18.6, schema 8');
    expect(text).not.toContain(SECRET);
  });

  it('is niet te laden zonder serverdetail en biedt opnieuw proberen', async () => {
    setup({ fail: { 'GET /server': new Response('{}', { status: 500 }) } });
    render(DiagnosticsPage);
    await waitFor(() => expect(screen.getByRole('button', { name: /opnieuw/i })).toBeInTheDocument());
  });
});

describe('maskering', () => {
  it('maskeert op naam en op een wachtwoord in een URL', () => {
    expect(maskEntry({ key: 'X_API_TOKEN', value: 'abc', redacted: false })).toMatchObject({ value: '•••', redacted: true });
    expect(maskEntry({ key: 'PLEYA_SERVER_ACCESS_TOKEN_TTL', value: '15m', redacted: false })).toMatchObject({
      value: '15m',
      redacted: false
    });
    expect(maskLine('x https://a:b@c.test y')).toBe('x https://a:•••@c.test y');
  });

  it('houdt het rapport vrij van geheimen', () => {
    const report = buildReport(
      {
        server: baseServer(),
        info: baseInfo(),
        environment: ENV,
        log: LOG
      },
      new Date('2026-10-26T10:00:00Z')
    );
    expect(report).not.toContain(SECRET);
    expect(report).toContain('PLEYA_SERVER_BACKUP_KEY=•••');
    expect(report).toContain('[capabilities]');
  });
});
