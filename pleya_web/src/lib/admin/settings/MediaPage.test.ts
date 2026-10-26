/**
 * Scherm 28 tegen een nepserver: de drie instelbare waarden, de alleen-lezen
 * analyse en transcoderstatus, Opslaan met bevestiging, Stoppen met
 * bevestiging, en wat er gebeurt als de server weigert.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { apiError, baseInfo, settingsFake, user } from './settingsFake';

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

import MediaPage from './MediaPage.svelte';

const ENV = [
  { key: 'PLEYA_SERVER_FFPROBE_TIMEOUT', value: '60s', redacted: false },
  { key: 'PLEYA_SERVER_JOB_WORKERS', value: '2', redacted: false }
];

function setup(options: Parameters<typeof settingsFake>[0] = {}, capabilities = {}) {
  const server = settingsFake({
    users: [user('u1', 'Sanne')],
    environment: ENV,
    transcode: {
      max_sessions: 2,
      hardware: { accel: 'vaapi', reason: null },
      items: [
        {
          id: 't1',
          user_id: 'u1',
          version_id: 'v1',
          mode: 'transcode',
          hw_accel: 'vaapi',
          started_at: new Date().toISOString(),
          last_heartbeat_at: new Date().toISOString()
        }
      ]
    },
    ...options
  });
  h.client = server.client;
  const info = baseInfo();
  Object.assign(info.capabilities, capabilities);
  h.info = info;
  return server;
}

const user$ = () => userEvent.setup();

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('scherm 28, media en streaming', () => {
  it('toont de geldende waarden, de omgeving en de transcodersessie', async () => {
    setup();
    render(MediaPage);
    const ttl = await screen.findByLabelText('Levensduur van een streamsessie');
    expect(ttl).toHaveValue('1800');
    expect(screen.getByLabelText('Streamsessies per gebruiker')).toHaveValue('8');
    expect(screen.getByLabelText(/Streamtoken geldig/)).toHaveValue('300');

    expect(screen.getByText('gevonden, ffmpeg 5.1.9')).toBeInTheDocument();
    expect(screen.getByText('60s')).toBeInTheDocument();
    expect(screen.getByText('VAAPI actief')).toBeInTheDocument();
    expect(screen.getByText('aan, 1 sessie')).toBeInTheDocument();
    const row = screen.getByText('Sanne').closest('li') as HTMLElement;
    expect(within(row).getByText(/omzetten · VAAPI/)).toBeInTheDocument();
    // Het maximum is een omgevingsvariabele: er is geen veld, alleen de naam.
    expect(screen.getByText('PLEYA_SERVER_TRANSCODE_MAX_SESSIONS')).toBeInTheDocument();
    expect(screen.queryByLabelText('Gelijktijdige transcodes')).not.toBeInTheDocument();
  });

  it('zegt dat een variabele niet gezet is in plaats van een waarde te verzinnen', async () => {
    setup({ environment: [] });
    render(MediaPage);
    await screen.findByText('Analyse');
    expect(screen.getAllByText(/niet ingesteld, standaard van de server/)).toHaveLength(2);
  });

  it('houdt Opslaan uit zolang niets veranderd is, en stuurt na bevestiging alleen de wijziging', async () => {
    const server = setup();
    const ui = user$();
    render(MediaPage);
    const save = await screen.findByRole('button', { name: 'Opslaan' });
    expect(save).toBeDisabled();

    await ui.selectOptions(screen.getByLabelText('Streamsessies per gebruiker'), '4');
    expect(save).toBeEnabled();
    await ui.click(save);
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Streamsessies per gebruiker: 4')).toBeInTheDocument();
    // Nog geen schrijfactie voor de bevestiging.
    expect(server.writes()).toEqual([]);

    await ui.click(within(dialog).getByRole('button', { name: 'Opslaan' }));
    await screen.findByText(/Opgeslagen/);
    expect(server.writes()).toEqual(['PATCH /settings']);
    expect(server.seen.find((s) => s.method === 'PATCH')?.body).toEqual({ max_stream_sessions: 4 });
  });

  it('stuurt niets als je de bevestiging annuleert (negatieve controle)', async () => {
    const server = setup();
    const ui = user$();
    render(MediaPage);
    await ui.selectOptions(await screen.findByLabelText('Levensduur van een streamsessie'), '900');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Annuleren' }));
    expect(server.writes()).toEqual([]);
  });

  it('zet het concept terug met Annuleren onder de pagina', async () => {
    setup();
    const ui = user$();
    render(MediaPage);
    const select = await screen.findByLabelText('Streamsessies per gebruiker');
    await ui.selectOptions(select, '2');
    await ui.click(screen.getByRole('button', { name: 'Annuleren' }));
    expect(select).toHaveValue('8');
  });

  it('laat het formulier staan en noemt veld en grens als de server weigert', async () => {
    const server = setup({
      fail: {
        'PATCH /settings': () =>
          apiError('settings.invalid_value', 400, {
            field: 'stream_token_ttl',
            minimum: '1m',
            maximum: '15m'
          })
      }
    });
    const ui = user$();
    render(MediaPage);
    const select = await screen.findByLabelText(/Streamtoken geldig/);
    await ui.selectOptions(select, '600');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Opslaan' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Streamtoken geldig');
    expect(alert).toHaveTextContent('1m tot 15m');
    expect(screen.queryByText(/Opgeslagen/)).not.toBeInTheDocument();
    // Niets is verloren: het gekozen concept staat er nog en Opslaan kan opnieuw.
    expect(select).toHaveValue('600');
    expect(screen.getByRole('button', { name: 'Opslaan' })).toBeEnabled();
    expect(server.writes()).toEqual(['PATCH /settings']);
  });

  it('stopt een transcodesessie pas na bevestiging', async () => {
    const server = setup();
    const ui = user$();
    render(MediaPage);
    await ui.click(await screen.findByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));
    expect(server.writes()).toEqual([]);
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    await waitFor(() => expect(server.writes()).toEqual(['DELETE /transcode-sessions/t1']));
    await waitFor(() => expect(screen.queryByText('Sanne')).not.toBeInTheDocument());
  });

  it('legt uit dat de sessie al weg is als de server hem niet meer kent', async () => {
    setup({ fail: { 'DELETE /transcode-sessions/t1': () => apiError('library.not_found', 404) } });
    const ui = user$();
    render(MediaPage);
    await ui.click(await screen.findByRole('button', { name: 'Transcodesessie van Sanne stoppen' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Stoppen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('De sessie van Sanne is al afgelopen');
  });

  it('toont transcoderen als uit zonder omzetter en laat geen sessielijst zien', async () => {
    setup({}, { transcode: false });
    render(MediaPage);
    await screen.findByText('Transcoderen');
    expect(screen.queryByText('Nu bezig')).not.toBeInTheDocument();
    expect(screen.getAllByText('uit').length).toBeGreaterThan(0);
  });

  it('meldt een onleesbare pagina met een uitweg als de instellingen niet laden', async () => {
    setup({ fail: { 'GET /settings': () => apiError('server.internal', 500) } });
    render(MediaPage);
    expect(await screen.findByRole('button', { name: /opnieuw/i })).toBeInTheDocument();
  });
});
