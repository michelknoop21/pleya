/**
 * Scherm 35 tegen een nepserver: de lijst, de meldingen, de instellingen, de
 * drie schrijfacties en vooral de restore, met per kritieke regel een
 * negatieve controle (geen restore zonder de exacte zin, de sleutel nergens in
 * de pagina, een weigering laat de lijst staan, het verversen stopt).
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { TransportError } from '../../api/errors';
import { apiError, backup, backupsFake, list, restoreTest, sentence } from './backupsFake';

const h = vi.hoisted(() => ({ client: null as unknown, capabilities: undefined as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    get capabilities() {
      return h.capabilities;
    }
  }
}));

import BackupsPage from './BackupsPage.svelte';

const NOW = Date.now();
const iso = (hoursAgo: number) => new Date(NOW - hoursAgo * 3_600_000).toISOString();

const NEWEST = backup('b3', {
  started_at: iso(10),
  finished_at: iso(10),
  size_bytes: 412_000_000,
  last_restore_test: restoreTest({ finished_at: iso(9) })
});
const OLDER = backup('b2', { started_at: iso(34), finished_at: iso(34), size_bytes: 411_000_000 });
const MANUAL = backup('b1', {
  started_at: iso(24 * 50),
  trigger: 'upgrade',
  schema_version: 7,
  secrets_included: false,
  size_bytes: 380_000_000
});

function setup(options: Partial<Parameters<typeof backupsFake>[0]> = {}) {
  const server = backupsFake({ list: list([NEWEST, OLDER, MANUAL]), ...options });
  h.client = server.client;
  return server;
}

const gets = (server: ReturnType<typeof setup>) => server.seen.filter((s) => s.method === 'GET').length;

beforeEach(() => {
  setLocale('nl');
  h.capabilities = undefined;
});
afterEach(() => {
  setLocale('en');
  vi.useRealTimers();
});

describe('scherm 35, de lijst', () => {
  it('toont per back-up tijdstip, trigger, inhoud, grootte, status en hersteltest', async () => {
    setup();
    render(BackupsPage);

    const rows = await screen.findAllByRole('row');
    const newest = rows.find((r) => r.getAttribute('data-backup') === 'b3') as HTMLElement;
    expect(newest).toHaveTextContent('dagelijks');
    expect(newest).toHaveTextContent('database (schema 22) en /config');
    expect(newest).toHaveTextContent('576 titels');
    expect(newest).toHaveTextContent('412 MB');
    expect(newest).toHaveTextContent('geheimen erin, versleuteld');
    expect(newest).toHaveTextContent('hersteltest geslaagd');
    expect(newest).toHaveTextContent('576 van 576 titels');

    const upgrade = rows.find((r) => r.getAttribute('data-backup') === 'b1') as HTMLElement;
    expect(upgrade).toHaveTextContent('vóór een upgrade');
    expect(upgrade).toHaveTextContent('zonder geheimen');
    expect(upgrade).toHaveTextContent('niet getest');
  });

  it('toont de instellingen alleen lezen, met de naam van de variabele', async () => {
    setup();
    render(BackupsPage);
    const panel = (await screen.findByRole('heading', { name: 'Instellingen' })).closest('section') as HTMLElement;
    expect(panel).toHaveTextContent('/backups');
    expect(panel).toHaveTextContent('PLEYA_SERVER_BACKUP_DIR');
    expect(panel).toHaveTextContent('elke dag om 03:30');
    expect(panel).toHaveTextContent('PLEYA_SERVER_BACKUP_TIME');
    expect(panel).toHaveTextContent('14 dagen');
    expect(panel).toHaveTextContent('PLEYA_SERVER_BACKUP_RETENTION_DAYS');
    expect(panel).toHaveTextContent('ingesteld');
    expect(within(panel).queryByRole('textbox')).toBeNull();
    expect(within(panel).queryByRole('button')).toBeNull();
  });

  it('zet de sleutel nergens in de pagina, ook niet als de server er een meestuurt', async () => {
    const leaky = { ...list([NEWEST]), secrets_key: 'PASSWOORD-VAN-DE-SLEUTEL-1234' } as ReturnType<typeof list>;
    setup({ list: leaky });
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    expect(document.body.innerHTML).not.toContain('PASSWOORD-VAN-DE-SLEUTEL-1234');
    expect(screen.getByText('PLEYA_SERVER_BACKUP_KEY')).toBeInTheDocument();
  });

  it('meldt dezelfde schijf, een ontbrekende sleutel en een te oude hersteltest', async () => {
    const old = backup('b9', { last_restore_test: restoreTest({ finished_at: iso(24 * 10) }), started_at: iso(24 * 10) });
    setup({ list: list([old], { same_failure_domain: true, secrets_key_configured: false }) });
    render(BackupsPage);
    expect(await screen.findByText('De back-upmap staat op dezelfde schijf als de configuratie')).toBeInTheDocument();
    expect(screen.getByText('Geen sleutel ingesteld voor de geheimen')).toBeInTheDocument();
    expect(screen.getByText('De laatste hersteltest is te oud')).toBeInTheDocument();
    expect(screen.getByText('niet ingesteld')).toBeInTheDocument();
  });

  it('meldt geen waarschuwingen als alles in orde is', async () => {
    setup();
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    expect(screen.queryByText(/dezelfde schijf/)).toBeNull();
    expect(screen.queryByText(/Geen sleutel/)).toBeNull();
    expect(screen.queryByText(/te oud/)).toBeNull();
  });

  it('meldt een mislukte laatste back-up met de reden', async () => {
    const failed = backup('bf', { status: 'failed', failure_code: 'storage.full', started_at: iso(1) });
    setup({ list: list([failed, NEWEST]) });
    render(BackupsPage);
    expect(await screen.findByText('De laatste back-up is mislukt')).toBeInTheDocument();
    expect(screen.getAllByText(/de schijf was vol/).length).toBeGreaterThan(0);
    // Een mislukte rij heeft geen acties.
    const row = screen.getAllByRole('row').find((r) => r.getAttribute('data-backup') === 'bf') as HTMLElement;
    expect(within(row).queryByRole('button')).toBeNull();
  });

  it('toont een leeg scherm met het tijdstip als er geen back-ups zijn', async () => {
    setup({ list: list([]) });
    render(BackupsPage);
    expect(await screen.findByText(/Er zijn nog geen back-ups\. De eerste komt om 03:30/)).toBeInTheDocument();
  });

  it('toont niets en vraagt niets als de server geen back-ups kent', async () => {
    h.capabilities = { backups: false };
    const server = setup();
    render(BackupsPage);
    expect(await screen.findByText('Deze server maakt geen back-ups')).toBeInTheDocument();
    expect(gets(server)).toBe(0);
    expect(screen.queryByRole('button', { name: 'Nu een back-up maken' })).toBeNull();
  });

  it('laat een lid zonder tabel en met een uitweg (de server geeft hem 404)', async () => {
    setup({ fail: { 'GET /backups': () => apiError('auth.user_not_found', 404) } });
    render(BackupsPage);
    expect(await screen.findByText(/geen beheerrechten/)).toBeInTheDocument();
    expect(screen.queryByRole('table')).toBeNull();
  });
});

describe('scherm 35, back-up maken en hersteltest', () => {
  it('maakt een back-up met één aanvraag en volgt hem', async () => {
    const server = setup();
    render(BackupsPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Nu een back-up maken' }));
    expect(await screen.findByText(/De back-up staat in de wachtrij/)).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /backups']);
    await waitFor(() => expect(screen.getAllByRole('row').some((r) => r.getAttribute('data-status') === 'running')).toBe(true));
  });

  it('zegt bij 409 server.backup_busy dat er al een loopt, en laat de lijst staan', async () => {
    const server = setup({ fail: { 'POST /backups': () => apiError('server.backup_busy', 409) } });
    render(BackupsPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Nu een back-up maken' }));
    expect(await screen.findByText(/al een back-up of hersteltest/)).toBeInTheDocument();
    expect(screen.getAllByRole('row').filter((r) => r.hasAttribute('data-backup'))).toHaveLength(3);
    expect(server.writes()).toEqual(['POST /backups']);
  });

  it('zegt bij een volle schijf wat te doen', async () => {
    setup({ fail: { 'POST /backups': () => apiError('storage.full', 507) } });
    render(BackupsPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Nu een back-up maken' }));
    expect(await screen.findByText(/Maak ruimte vrij op de schijf van de back-upmap/)).toBeInTheDocument();
  });

  it('start een hersteltest op de gekozen back-up en niet op een andere', async () => {
    const server = setup();
    render(BackupsPage);
    const row = (await screen.findAllByRole('row')).find((r) => r.getAttribute('data-backup') === 'b2') as HTMLElement;
    await userEvent.click(within(row).getByRole('button', { name: /Hersteltest/ }));
    expect(await screen.findByText(/De hersteltest staat in de wachtrij/)).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /backups/b2/verify']);
  });

  it('laat de lijst intact als de server een hersteltest weigert', async () => {
    const server = setup({
      fail: { 'POST /backups/b2/verify': () => apiError('server.backup_not_restorable', 409, { reason: 'status' }) }
    });
    render(BackupsPage);
    const row = (await screen.findAllByRole('row')).find((r) => r.getAttribute('data-backup') === 'b2') as HTMLElement;
    await userEvent.click(within(row).getByRole('button', { name: /Hersteltest/ }));
    expect(await screen.findByText(/niet geslaagd en dus niet terug te zetten/)).toBeInTheDocument();
    expect(screen.getAllByRole('row').filter((r) => r.hasAttribute('data-backup'))).toHaveLength(3);
    expect(server.writes()).toEqual(['POST /backups/b2/verify']);
  });

  it('zet elke schrijfknop uit zolang er iets loopt', async () => {
    const running = backup('br', { status: 'running', started_at: iso(0.01), schema_version: null, titles: null });
    setup({ list: list([running, NEWEST]) });
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    expect(screen.getByRole('button', { name: 'Nu een back-up maken' })).toBeDisabled();
    for (const b of screen.getAllByRole('button', { name: /Hersteltest|terugzetten/i })) expect(b).toBeDisabled();
  });
});

describe('scherm 35, verversen', () => {
  it('ververst zolang een back-up loopt en houdt op zodra niets meer loopt', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const running = backup('br', { status: 'running', started_at: iso(0.01), schema_version: null, titles: null });
    const server = setup({ list: list([running, NEWEST]) });
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    const first = gets(server);

    await vi.advanceTimersByTimeAsync(4100);
    expect(gets(server)).toBeGreaterThan(first);

    // De back-up is klaar; de eerstvolgende verversing ziet dat en daarna blijft het stil.
    Object.assign(server.state.items[0]!, backup('br', { started_at: iso(0.01) }));
    await vi.advanceTimersByTimeAsync(4100);
    const settled = gets(server);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(gets(server)).toBe(settled);
  });

  it('ververst niet als niets loopt', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup();
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    const first = gets(server);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(gets(server)).toBe(first);
  });
});

describe('scherm 35, terugzetten', () => {
  async function openDialog(server: ReturnType<typeof setup>) {
    render(BackupsPage);
    const row = (await screen.findAllByRole('row')).find((r) => r.getAttribute('data-backup') === 'b2') as HTMLElement;
    await userEvent.click(within(row).getByRole('button', { name: /terugzetten/i }));
    const dialog = await screen.findByRole('dialog');
    expect(server.writes()).toEqual([]);
    return dialog;
  }

  it('toont wat er gebeurt en de zin van de server, en stuurt nog niets', async () => {
    const server = setup();
    const dialog = await openDialog(server);
    expect(dialog).toHaveTextContent('De database en /config worden vervangen');
    expect(dialog).toHaveTextContent('start zelf opnieuw');
    expect(dialog).toHaveTextContent(OLDER.restore_confirmation!);
    expect(within(dialog).getByRole('button', { name: 'Deze back-up terugzetten' })).toBeDisabled();
  });

  it('stuurt niets zonder de exacte zin: leeg, bijna goed, andere hoofdletters', async () => {
    const server = setup();
    const dialog = await openDialog(server);
    const field = within(dialog).getByRole('textbox');
    const go = within(dialog).getByRole('button', { name: 'Deze back-up terugzetten' });
    const exact = OLDER.restore_confirmation!;

    for (const attempt of [exact.slice(0, -1), exact + ' ', exact.toUpperCase(), exact.replace('herstel', 'Herstel')]) {
      await userEvent.clear(field);
      await userEvent.type(field, attempt);
      expect(go).toBeDisabled();
      await userEvent.click(go);
      await userEvent.type(field, '{Enter}');
    }
    expect(server.writes()).toEqual([]);
    expect(server.restores()).toEqual([]);
  });

  it('stuurt met de exacte zin één restore en wacht dan tot de server terug is', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup({ maintenanceCalls: 2 });
    const dialog = await openDialog(server);
    const field = within(dialog).getByRole('textbox');
    await userEvent.click(field);
    await userEvent.paste(OLDER.restore_confirmation!);
    const go = within(dialog).getByRole('button', { name: 'Deze back-up terugzetten' });
    expect(go).toBeEnabled();
    await userEvent.click(go);

    expect(await screen.findByText('De server zet de back-up terug')).toBeInTheDocument();
    expect(server.restores()).toHaveLength(1);
    expect(server.restores()[0]!.body).toEqual({ confirm: sentence(OLDER.started_at) });
    // De lijst van vóór de restore is weg en er is geen knop om nog eens te restoren.
    expect(screen.queryByRole('table')).toBeNull();
    expect(screen.queryByRole('button', { name: /terugzetten/i })).toBeNull();

    await vi.advanceTimersByTimeAsync(3100 * 3);
    expect(await screen.findByText('De server antwoordt weer')).toBeInTheDocument();
    expect(server.restores()).toHaveLength(1);

    await userEvent.click(screen.getByRole('button', { name: 'Naar de lijst' }));
    expect(await screen.findByRole('heading', { name: 'Instellingen' })).toBeInTheDocument();
  });

  it('stuurt nooit een tweede restore als de verbinding wegvalt voor het antwoord', async () => {
    // Een fetch die bij de restore een netwerkfout geeft; de rest gaat naar de nepserver.
    const server = backupsFake({
      list: list([NEWEST, OLDER, MANUAL]),
      fail: {
        'POST /backups/b2/restore': () => {
          throw new TransportError(new Error('weg'));
        }
      }
    });
    h.client = server.client;
    const dialog = await openDialog(server as unknown as ReturnType<typeof setup>);
    await userEvent.click(within(dialog).getByRole('textbox'));
    await userEvent.paste(OLDER.restore_confirmation!);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Deze back-up terugzetten' }));

    expect(await screen.findByText(/Het terugzetten kan toch begonnen zijn/)).toBeInTheDocument();
    expect(screen.queryByText('De server zet de back-up terug')).toBeNull();
    await waitFor(() => expect(screen.getByRole('table')).toBeInTheDocument());
    expect(server.restores()).toHaveLength(1);
  });

  it('zegt bij een weigering waarom en laat de lijst staan', async () => {
    const server = setup({
      fail: { 'POST /backups/b2/restore': () => apiError('server.backup_not_restorable', 409, { reason: 'schema_newer' }) }
    });
    const dialog = await openDialog(server);
    await userEvent.click(within(dialog).getByRole('textbox'));
    await userEvent.paste(OLDER.restore_confirmation!);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Deze back-up terugzetten' }));

    expect(await screen.findByText(/komt van een nieuwere versie van de server/)).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(screen.getAllByRole('row').filter((r) => r.hasAttribute('data-backup'))).toHaveLength(3);
    expect(screen.queryByText('De server zet de back-up terug')).toBeNull();
  });

  it('sluit de dialoog met Annuleren zonder iets te sturen', async () => {
    const server = setup();
    const dialog = await openDialog(server);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(server.writes()).toEqual([]);
  });

  it('biedt Terugzetten niet aan bij een back-up die niet geslaagd is', async () => {
    const failed = backup('bf', { status: 'failed', started_at: iso(1) });
    const missing = backup('bm', { status: 'missing', started_at: iso(2) });
    setup({ list: list([failed, missing, NEWEST]) });
    render(BackupsPage);
    await screen.findByRole('heading', { name: 'Instellingen' });
    expect(screen.getAllByRole('button', { name: /terugzetten/i })).toHaveLength(1);
  });
});
