/**
 * Scherm 26 tegen een nepserver: de tabel met rol, bibliotheken, laatst actief
 * en toestellen, het eerlijke antwoord waar het contract niets levert, en dat
 * de lijst nooit iets schrijft. Plus de rolgate: een lid raakt geen
 * gebruikersroute.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { SessionState } from '../stores/session.svelte';
import { setLocale } from '../i18n';
import { adminGate } from './gate';
import { fakeServer } from './fakeServer';
import { apiError, library, user, userFake, userSession } from './userFake';

const h = vi.hoisted(() => ({ client: null as unknown, meId: 'u1' }));
vi.mock('../stores/session.svelte', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../stores/session.svelte')>();
  return {
    ...mod,
    session: {
      get client() {
        return h.client;
      },
      get me() {
        return { id: h.meId };
      }
    }
  };
});

import UsersPage from './UsersPage.svelte';

function setup(fail: Parameters<typeof userFake>[0]['fail'] = {}) {
  const server = userFake({
    users: [user('u1', 'Michel', 'owner'), user('u2', 'Sanne', 'member'), user('u3', 'Kids', 'restricted')],
    libraries: [library('l1', 'Films')],
    sessions: {
      u1: [userSession('s1', 'Apple TV woonkamer', { last_seen_at: new Date().toISOString() }), userSession('s2', 'Mac'), userSession('s9', 'Token', { kind: 'api' })],
      u2: [userSession('s3', 'iPhone')],
      u3: []
    },
    fail
  });
  h.client = server.client;
  return server;
}

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('scherm 26, gebruikers', () => {
  it('toont elke gebruiker met rol, bibliotheken, laatst actief en toestellen', async () => {
    setup();
    render(UsersPage);
    const michel = await screen.findByRole('row', { name: /Michel/ });
    expect(within(michel).getByText('Eigenaar')).toBeInTheDocument();
    expect(within(michel).getByText('alle')).toBeInTheDocument();
    expect(within(michel).getByText('jij')).toBeInTheDocument();
    expect(within(michel).getByText(/Apple TV woonkamer/)).toBeInTheDocument();
    // Een API-token telt niet als toestel: twee van de drie sessies.
    expect(within(michel).getAllByRole('cell').some((c) => /2$/.test(c.textContent?.trim() ?? ""))).toBe(true);

    const sanne = screen.getByRole('row', { name: /Sanne/ });
    expect(within(sanne).getByText('Lid')).toBeInTheDocument();
    expect(within(sanne).getByText('per gebruiker ingesteld')).toBeInTheDocument();
    expect(within(sanne).getByRole('link', { name: 'Sanne bewerken' })).toHaveAttribute('href', '/admin/users/u2');

    const kids = screen.getByRole('row', { name: /Kids/ });
    expect(within(kids).getByText('Beperkt')).toBeInTheDocument();
    expect(within(kids).getByText('nog nooit')).toBeInTheDocument();
  });

  it('wijst naar Gebruiker toevoegen en toont de rollen en wat de server niet toont', async () => {
    setup();
    render(UsersPage);
    expect(await screen.findByRole('link', { name: /Gebruiker toevoegen/ })).toHaveAttribute('href', '/admin/users/new');
    expect(await screen.findByRole('heading', { name: 'Rollen' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Wat je hier niet ziet' })).toBeInTheDocument();
  });

  it('doet bij het laden geen enkele schrijfaanvraag', async () => {
    const server = setup();
    render(UsersPage);
    await screen.findByRole('row', { name: /Sanne/ });
    expect(server.writes()).toEqual([]);
  });

  it('laat de lijst staan als de sessies van één gebruiker niet te lezen zijn', async () => {
    setup({ 'GET /sessions': () => apiError('server.internal', 500) });
    render(UsersPage);
    const sanne = await screen.findByRole('row', { name: /Sanne/ });
    expect(within(sanne).getAllByText('onbekend').length).toBeGreaterThan(0);
  });

  it('toont een melding na toevoegen of verwijderen', async () => {
    setup();
    render(UsersPage, { props: { removed: 'Piet' } });
    expect(await screen.findByText(/Piet is verwijderd/)).toBeInTheDocument();
  });

  it('toont een fout met opnieuw proberen als de lijst niet laadt', async () => {
    setup({ 'GET /users': apiError('server.database_unavailable', 503) });
    render(UsersPage);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument());
  });
});

describe('rolgate voor gebruikersbeheer', () => {
  it('laat een lid nul gebruikers- of sessieaanvragen doen', async () => {
    const server = fakeServer({ role: 'member' });
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
    expect(server.seen).not.toContain('/users');
    expect(server.seen).not.toContain('/sessions');
  });
});
