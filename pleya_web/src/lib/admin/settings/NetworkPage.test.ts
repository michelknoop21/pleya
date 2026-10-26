/**
 * Scherm 30 tegen een nepserver: identiteit en verbinding, de bevestiging met
 * waarschuwing voor wat je kan buitensluiten, vooraf geweigerde invoer, de
 * verbindingstest, en een weigering van de server.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { apiError, baseServer, settingsFake } from './settingsFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import NetworkPage from './NetworkPage.svelte';

function setup(options: Parameters<typeof settingsFake>[0] = {}) {
  const server = settingsFake(options);
  h.client = server.client;
  return server;
}

const dialogSave = () => within(screen.getByRole('dialog')).getByRole('button', { name: 'Opslaan' });

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('scherm 30, netwerk en identiteit', () => {
  it('toont naam, id, adres en de verbinding met de variabelen erachter', async () => {
    setup();
    render(NetworkPage);
    expect(await screen.findByLabelText('Servernaam')).toHaveValue('Pleya-server');
    expect(screen.getByLabelText('Server-id')).toHaveValue('0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77');
    expect(screen.getByLabelText('Server-id')).toHaveAttribute('readonly');
    expect(screen.getByLabelText('Publiek adres')).toHaveValue('https://web.pleya.app');
    expect(screen.getByText(':8080')).toBeInTheDocument();
    expect(screen.getByText('172.18.0.0/16')).toBeInTheDocument();
    expect(screen.getByText('achter een proxy')).toBeInTheDocument();
    expect(screen.getByText('PLEYA_SERVER_HTTP_ADDR')).toBeInTheDocument();
    expect(screen.getByText('PLEYA_SERVER_TRUSTED_PROXIES')).toBeInTheDocument();
    // Alleen-lezen: geen invoer voor bindadres of proxy's.
    expect(screen.queryByLabelText('Luistert op')).not.toBeInTheDocument();
    for (const route of ['GET /pleya/v1/info', 'POST /pleya/v1/auth/setup', 'POST /pleya/v1/auth/login', 'POST /pleya/v1/auth/refresh']) {
      expect(screen.getByText(route)).toBeInTheDocument();
    }
  });

  it('stuurt na bevestiging alleen de gewijzigde naam', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(NetworkPage);
    const name = await screen.findByLabelText('Servernaam');
    await ui.clear(name);
    await ui.type(name, 'Thuis');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    expect(within(screen.getByRole('dialog')).getByText('Servernaam: Thuis')).toBeInTheDocument();
    // Een naam kan je niet buitensluiten: geen buitensluitwaarschuwing.
    expect(screen.queryByText('Dit kan je buitensluiten.')).not.toBeInTheDocument();
    await ui.click(dialogSave());
    await screen.findByText(/Opgeslagen/);
    expect(server.seen.find((s) => s.method === 'PATCH')?.body).toEqual({ server_name: 'Thuis' });
  });

  it('waarschuwt expliciet bij een andere web-origin dan waar je nu kijkt', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(NetworkPage);
    await ui.type(await screen.findByLabelText('Adres van de webclient (origin)'), 'https://nieuw.example.org');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Dit kan je buitensluiten.')).toBeInTheDocument();
    expect(within(dialog).getByText(/Je kijkt naar deze pagina vanaf/)).toHaveTextContent('https://nieuw.example.org');
    expect(server.writes()).toEqual([]);
    await ui.click(within(dialog).getByRole('button', { name: 'Opslaan' }));
    await screen.findByText(/Opgeslagen/);
    expect(server.seen.find((s) => s.method === 'PATCH')?.body).toEqual({ web_origin: 'https://nieuw.example.org' });
  });

  it('waarschuwt ook bij CORS en stuurt de lijst als array', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(NetworkPage);
    await ui.type(await screen.findByLabelText('Toegestane origins (CORS)'), 'https://a.test{Enter}https://b.test');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    expect(within(screen.getByRole('dialog')).getByText('Dit kan je buitensluiten.')).toBeInTheDocument();
    await ui.click(dialogSave());
    await screen.findByText(/Opgeslagen/);
    expect(server.seen.find((s) => s.method === 'PATCH')?.body).toEqual({
      cors_origins: ['https://a.test', 'https://b.test']
    });
  });

  it('blokkeert Opslaan bij een ongeldige origin en een jokerteken, zonder aanvraag (negatieve controle)', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(NetworkPage);
    const origin = await screen.findByLabelText('Adres van de webclient (origin)');
    await ui.type(origin, 'https://a.test/pad');
    expect(await screen.findByText(/Gebruik de vorm https:\/\/host/)).toBeInTheDocument();
    const save = screen.getByRole('button', { name: 'Opslaan' });
    expect(save).toBeDisabled();
    await ui.clear(origin);
    await ui.type(screen.getByLabelText('Toegestane origins (CORS)'), '*');
    expect(screen.getByText(/Een jokerteken wordt niet geaccepteerd/)).toBeInTheDocument();
    expect(save).toBeDisabled();
    await ui.click(save);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(server.writes()).toEqual([]);
  });

  it('laat het formulier staan en geeft een uitweg als de server weigert', async () => {
    const server = setup({
      fail: {
        'PATCH /settings': () =>
          apiError('settings.invalid_value', 400, { field: 'public_url' })
      }
    });
    const ui = userEvent.setup();
    render(NetworkPage);
    const url = await screen.findByLabelText('Publiek adres');
    await ui.clear(url);
    await ui.type(url, 'http://192.168.1.5');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    await ui.click(dialogSave());
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Publiek adres');
    expect(alert).toHaveTextContent('Er is niets gewijzigd');
    expect(url).toHaveValue('http://192.168.1.5');
    expect(server.writes()).toEqual(['PATCH /settings']);
  });

  it('test de verbinding met een lege POST en toont beide metingen', async () => {
    const server = setup({
      connectivity: { public_url_reachable: true, range_intact: false, behind_proxy: true }
    });
    const ui = userEvent.setup();
    render(NetworkPage);
    await ui.click(await screen.findByRole('button', { name: 'Verbinding testen' }));
    expect(await screen.findByText('bereikbaar')).toBeInTheDocument();
    expect(screen.getByText('onderweg stukgemaakt')).toBeInTheDocument();
    expect(screen.getByText(/buffert ranges/)).toBeInTheDocument();
    expect(server.seen.find((s) => s.method === 'POST')).toMatchObject({
      path: '/server/connectivity-check',
      body: undefined
    });
  });

  it('zegt dat er niets te testen is zonder publiek adres', async () => {
    const settings = (await import('./settingsFake')).baseSettings();
    settings.public_url.value = '';
    setup({
      settings,
      server: { ...baseServer(), public_url: '' },
      connectivity: { public_url_reachable: false, range_intact: false, behind_proxy: false }
    });
    const ui = userEvent.setup();
    render(NetworkPage);
    await ui.click(await screen.findByRole('button', { name: 'Verbinding testen' }));
    expect(await screen.findByText(/Er is geen publiek adres ingesteld/)).toBeInTheDocument();
  });

  it('meldt een falende verbindingstest als zin met opnieuw proberen', async () => {
    setup({ fail: { 'POST /server/connectivity-check': () => apiError('server.internal', 500, { request_id: 'req-4' }) } });
    const ui = userEvent.setup();
    render(NetworkPage);
    await ui.click(await screen.findByRole('button', { name: 'Verbinding testen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('req-4');
    await waitFor(() => expect(screen.getByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument());
  });
});
