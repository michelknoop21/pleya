/**
 * Scherm 31 tegen een nepserver: tokenduren, ingelogde toestellen van alle
 * gebruikers met Intrekken, en de ondertekensleutel achter het woord `rotate`.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { apiError, device, settingsFake, user } from './settingsFake';

const h = vi.hoisted(() => ({ client: null as unknown, signOut: vi.fn(), goto: vi.fn(async () => {}) }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    signOut: h.signOut
  }
}));

import SecurityPage from './SecurityPage.svelte';

function setup(options: Parameters<typeof settingsFake>[0] = {}) {
  const server = settingsFake({
    users: [user('u1', 'Michel', 'owner'), user('u2', 'Sanne')],
    sessions: {
      u1: [
        device('s1', 'Deze browser', { current: true }),
        device('s2', 'Apple TV woonkamer', { last_seen_at: '2026-10-25T08:00:00Z' }),
        device('s9', 'Mijn agent', { kind: 'api' })
      ],
      u2: [device('s3', 'iPhone van Sanne', { last_seen_at: '2026-10-26T09:00:00Z' })]
    },
    ...options
  });
  h.client = server.client;
  return server;
}

beforeEach(() => {
  setLocale('nl');
  h.signOut.mockClear();
  h.goto.mockClear();
});
afterEach(() => setLocale('en'));

describe('scherm 31, beveiliging', () => {
  it('toont de tokenduren en elk toestel van elke gebruiker, nieuwste eerst, zonder API-tokens', async () => {
    setup();
    render(SecurityPage);
    expect(await screen.findByLabelText('Toegangstoken geldig')).toHaveValue('900');
    expect(screen.getByLabelText('Ingelogd blijven (vernieuwingstoken)')).toHaveValue('2592000');
    expect(screen.getByText('alle gebruikers, 3 toestellen')).toBeInTheDocument();
    const names = screen.getAllByRole('row').slice(1).map((r) => within(r).getAllByRole('cell')[0]!.textContent?.trim());
    expect(names[0]).toContain('iPhone van Sanne');
    expect(screen.queryByText('Mijn agent')).not.toBeInTheDocument();
  });

  it('geeft het eigen toestel geen Intrekken-knop (negatieve controle)', async () => {
    setup();
    render(SecurityPage);
    const row = (await screen.findByText('Deze browser')).closest('tr') as HTMLElement;
    expect(within(row).queryByRole('button')).not.toBeInTheDocument();
    expect(within(row).getByText('dit toestel')).toBeInTheDocument();
  });

  it('trekt een toestel pas in na bevestiging', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(SecurityPage);
    await ui.click(await screen.findByRole('button', { name: 'iPhone van Sanne van Sanne intrekken' }));
    expect(server.writes()).toEqual([]);
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Intrekken' }));
    await waitFor(() => expect(server.writes()).toEqual(['DELETE /sessions/s3']));
    await waitFor(() => expect(screen.queryByText('iPhone van Sanne')).not.toBeInTheDocument());
  });

  it('zegt dat het toestel al weg is als de sessie niet meer bestaat', async () => {
    setup({ fail: { 'DELETE /sessions/s3': () => apiError('auth.session_not_found', 404) } });
    const ui = userEvent.setup();
    render(SecurityPage);
    await ui.click(await screen.findByRole('button', { name: 'iPhone van Sanne van Sanne intrekken' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Intrekken' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('is al uitgelogd');
  });

  it('meldt gebruikers van wie de sessies niet te lezen waren', async () => {
    setup({ fail: { 'GET /sessions': () => apiError('server.internal', 500) } });
    render(SecurityPage);
    expect(await screen.findByText(/waren niet te lezen en ontbreken dus/)).toHaveTextContent('Michel, Sanne');
  });

  it('slaat een nieuwe tokenduur pas op na bevestiging en stuurt alleen die sleutel', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(SecurityPage);
    await ui.selectOptions(await screen.findByLabelText('Toegangstoken geldig'), '1800');
    await ui.click(screen.getByRole('button', { name: 'Opslaan' }));
    expect(server.writes()).toEqual([]);
    expect(within(screen.getByRole('dialog')).getByText('Toegangstoken geldig: 30 minuten')).toBeInTheDocument();
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Opslaan' }));
    await screen.findByText(/Opgeslagen/);
    expect(server.seen.find((s) => s.method === 'PATCH')?.body).toEqual({ access_token_ttl: '30m' });
  });

  it('roteert de sleutel alleen na het woord rotate (negatieve controle)', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(SecurityPage);
    await ui.click(await screen.findByRole('button', { name: 'Sleutel roteren' }));
    const dialog = screen.getByRole('dialog');
    const confirm = within(dialog).getByRole('button', { name: 'Sleutel roteren' });
    expect(confirm).toBeDisabled();
    await ui.type(within(dialog).getByRole('textbox'), 'rotat');
    expect(confirm).toBeDisabled();
    await ui.click(confirm);
    expect(server.writes()).toEqual([]);

    await ui.type(within(dialog).getByRole('textbox'), 'e');
    expect(confirm).toBeEnabled();
    await ui.click(confirm);
    await waitFor(() => expect(server.writes()).toEqual(['POST /server/rotate-signing-key']));
    expect(server.seen.find((s) => s.method === 'POST')?.body).toEqual({ confirm: 'rotate' });
    // Elke sessie is ingetrokken: lokaal uitloggen en naar inloggen.
    await waitFor(() => expect(h.goto).toHaveBeenCalledWith('/login'));
    expect(h.signOut).toHaveBeenCalled();
  });

  it('logt niet uit en toont de zin als de rotatie mislukt', async () => {
    setup({ fail: { 'POST /server/rotate-signing-key': () => apiError('server.internal', 500, { request_id: 'req-7' }) } });
    const ui = userEvent.setup();
    render(SecurityPage);
    await ui.click(await screen.findByRole('button', { name: 'Sleutel roteren' }));
    const dialog = screen.getByRole('dialog');
    await ui.type(within(dialog).getByRole('textbox'), 'rotate');
    await ui.click(within(dialog).getByRole('button', { name: 'Sleutel roteren' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('req-7');
    expect(h.signOut).not.toHaveBeenCalled();
    expect(h.goto).not.toHaveBeenCalled();
  });

  it('toont de sleutel nergens', async () => {
    setup();
    render(SecurityPage);
    await screen.findByText('Ondertekensleutel');
    expect(document.body.textContent).not.toMatch(/-----BEGIN|signing_key|secret/i);
  });
});
