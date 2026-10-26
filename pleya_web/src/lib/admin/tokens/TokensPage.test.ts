/**
 * Scherm 34 tegen een nepserver: de tokens van alle gebruikers, aanmaken met
 * een geheim dat één keer in beeld staat, intrekken met bevestiging, de MCP-
 * status, het auditlog van agents en de weigeringen van de server. Elke
 * beveiligingsregel heeft een negatieve controle: het geheim staat na sluiten
 * nergens meer, intrekken zonder bevestiging gebeurt niet, een serverweigering
 * laat de lijst heel.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../../i18n';
import { SessionState } from '../../stores/session.svelte';
import { fakeServer } from '../fakeServer';
import { adminGate } from '../gate';
import { apiError, FAKE_SECRET, token, tokenFake, user, type TokenFakeOptions } from './tokenFake';

const h = vi.hoisted(() => ({ client: null as unknown, tokens: true }));
vi.mock('../../stores/session.svelte', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../../stores/session.svelte')>();
  return {
    ...mod,
    session: {
      get client() {
        return h.client;
      },
      get me() {
        return { id: 'u1', username: 'Michel', role: 'owner' };
      },
      get capabilities() {
        return { api_tokens: h.tokens };
      }
    }
  };
});

import TokensPage from './TokensPage.svelte';

const SOON = new Date(Date.now() + 89 * 86_400_000 + 3_600_000).toISOString();

function setup(options: Partial<TokenFakeOptions> = {}) {
  const server = tokenFake({
    users: [user('u1', 'Michel', 'owner'), user('u2', 'Sanne', 'member')],
    tokens: {
      u1: [
        token('t1', 'u1', 'Claude Code op de Mac', { scope: 'admin', expires_at: SOON }),
        token('t2', 'u1', 'Nachtelijke scanrobot', { scope: 'maintenance', last_seen_at: '2026-10-25T03:00:00Z' })
      ],
      u2: [token('t3', 'u2', 'Sannes leesassistent', { last_seen_at: '2026-10-24T21:12:00Z' })]
    },
    ...options
  });
  h.client = server.client;
  return server;
}

/** Een opslag in het geheugen: de testomgeving heeft geen betrouwbare localStorage. */
function memoryStore(): Storage {
  const map = new Map<string, string>();
  return {
    get length() {
      return map.size;
    },
    key: (i) => [...map.keys()][i] ?? null,
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => void map.set(k, String(v)),
    removeItem: (k) => void map.delete(k),
    clear: () => map.clear()
  };
}

/** Alles waar een geheim in terecht kan komen buiten de pagina zelf. */
function leaks(): string {
  const parts: string[] = [location.href, document.body.textContent ?? ''];
  for (const store of [localStorage, sessionStorage]) {
    for (let i = 0; i < store.length; i += 1) {
      const key = store.key(i)!;
      parts.push(key, store.getItem(key) ?? '');
    }
  }
  return parts.join('\n');
}

beforeEach(() => {
  setLocale('nl');
  h.tokens = true;
  vi.stubGlobal('localStorage', memoryStore());
  vi.stubGlobal('sessionStorage', memoryStore());
});
afterEach(() => {
  setLocale('en');
  vi.unstubAllGlobals();
});

async function create(ui: ReturnType<typeof userEvent.setup>, name: string, scope?: string) {
  await ui.type(await screen.findByLabelText(/^Naam/), name);
  if (scope) await ui.click(screen.getByRole('radio', { name: new RegExp(`^${scope}`, 'i') }));
  await ui.click(screen.getByRole('button', { name: 'Token aanmaken', hidden: false }));
}

describe('scherm 34, de lijst', () => {
  it('toont de tokens van alle gebruikers met eigenaar, bereik en verloop, nieuwste gebruik eerst', async () => {
    setup();
    render(TokensPage);
    const first = await screen.findByRole('row', { name: /Claude Code op de Mac/ });
    expect(within(first).getByText('Michel · Eigenaar')).toBeInTheDocument();
    expect(within(first).getByText('beheer')).toBeInTheDocument();
    expect(within(first).getByText('over 90 dagen')).toBeInTheDocument();
    expect(screen.getByRole('row', { name: /Sannes leesassistent/ })).toHaveTextContent('Sanne · Lid');
    expect(screen.getByText('3 actief')).toBeInTheDocument();
    const names = screen.getAllByRole('row').slice(1).map((r) => within(r).getAllByRole('cell')[0]!.textContent);
    expect(names[0]).toContain('Claude Code');
    expect(names[2]).toContain('Sannes leesassistent');
  });

  it('toont geen geheim en vraagt alleen leesroutes (negatieve controle)', async () => {
    const server = setup();
    render(TokensPage);
    await screen.findByText('Nachtelijke scanrobot');
    expect(document.body.textContent).not.toContain('plyat1_');
    expect(server.writes()).toEqual([]);
  });

  it('meldt van wie de tokens niet te lezen waren en laat de rest staan', async () => {
    setup({ fail: { 'GET /auth/api-tokens': () => apiError('server.internal', 500) } });
    render(TokensPage);
    expect(await screen.findByText(/De tokens van Michel, Sanne waren niet te lezen/)).toBeInTheDocument();
  });

  it('zegt dat MCP uit staat en toont het auditlog leeg', async () => {
    setup();
    render(TokensPage);
    expect(await screen.findByText(/MCP staat uit/)).toBeInTheDocument();
    expect(screen.getByText(/Nog niets vastgelegd/)).toBeInTheDocument();
  });

  it('toont MCP-adres en toolaantal als de laag aanstaat, en de agentregels met de tokennaam', async () => {
    const server = setup({
      mcp: { enabled: true, url: 'https://web.pleya.app/mcp', tool_count: 31 },
      audit: [
        { id: 'a1', at: new Date().toISOString(), source: 'mcp', operation: 'startLibraryScan', target: 'l1', outcome: 'ok', user_id: 'u1', session_id: 't1' },
        { id: 'a2', at: new Date().toISOString(), source: 'mcp', operation: 'deleteLibrary', target: 'l3', outcome: 'denied', user_id: 'u1', session_id: 't-weg' },
        { id: 'a3', at: new Date().toISOString(), source: 'http', operation: 'login', outcome: 'ok' }
      ]
    });
    render(TokensPage);
    expect(await screen.findByText('https://web.pleya.app/mcp')).toBeInTheDocument();
    expect(screen.getByText('31 tools')).toBeInTheDocument();
    const ok = screen.getByText('startLibraryScan').closest('li')!;
    expect(ok).toHaveTextContent('door Claude Code op de Mac');
    expect(within(ok).getByText('ok')).toBeInTheDocument();
    // Een ingetrokken token valt terug op de gebruiker; de weigering is zichtbaar.
    const denied = screen.getByText('deleteLibrary').closest('li')!;
    expect(denied).toHaveTextContent('door Michel');
    expect(within(denied).getByText('geweigerd')).toBeInTheDocument();
    // Alleen de bron mcp staat in het paneel.
    expect(screen.queryByText('login')).not.toBeInTheDocument();
    expect(server.seen.some((s) => s.path.startsWith('/audit?') && s.path.includes('source=mcp'))).toBe(true);
  });

  it('laat de lijst staan als het auditlog niet te lezen is', async () => {
    setup({ fail: { 'GET /audit': () => apiError('server.internal', 500) } });
    render(TokensPage);
    expect(await screen.findByText('Nachtelijke scanrobot')).toBeInTheDocument();
    expect(screen.getByText(/Het auditlog was niet te lezen/)).toBeInTheDocument();
  });
});

describe('scherm 34, aanmaken en het geheim', () => {
  it('maakt een token met het gekozen bereik en toont het geheim één keer met uitleg', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, '  Home Assistant  ', 'Alleen lezen');
    const panel = await screen.findByTestId('token-secret');
    expect(within(panel).getByText(FAKE_SECRET)).toBeInTheDocument();
    expect(within(panel).getByText(/enige keer dat het geheim zichtbaar is/)).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /auth/api-tokens']);
    expect(server.seen.find((s) => s.method === 'POST')!.body).toEqual({
      name: 'Home Assistant',
      scope: 'read',
      expires_in_days: 90
    });
    // Het token staat nu in de lijst, zonder geheim.
    const row = screen.getByRole('row', { name: /Home Assistant/ });
    expect(row).not.toHaveTextContent('plyat1_');
  });

  it('wist het geheim bij sluiten uit de pagina, de opslag en de URL (negatieve controle)', async () => {
    setup();
    const ui = userEvent.setup();
    const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map((m) => vi.spyOn(console, m));
    render(TokensPage);
    await create(ui, 'Agent');
    await screen.findByTestId('token-secret');
    // Tijdens het tonen staat het alleen in het paneel, niet in opslag of URL.
    expect(document.querySelectorAll('[data-testid="token-secret"] code')).toHaveLength(1);
    expect(localStorage.length + sessionStorage.length).toBe(0);
    expect(location.href).not.toContain('plyat1_');

    await ui.click(screen.getByRole('button', { name: 'Ik heb het bewaard' }));
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
    expect(leaks()).not.toContain(FAKE_SECRET);
    expect(leaks()).not.toContain('plyat1_');
    for (const spy of spies) {
      expect(JSON.stringify(spy.mock.calls)).not.toContain('plyat1_');
      spy.mockRestore();
    }
  });

  it('wist het geheim ook als de pagina verlaten wordt zonder te sluiten', async () => {
    setup();
    const ui = userEvent.setup();
    const view = render(TokensPage);
    await create(ui, 'Agent');
    await screen.findByTestId('token-secret');
    view.unmount();
    expect(leaks()).not.toContain('plyat1_');
    // Opnieuw openen toont geen geheim: de lijst kent het niet.
    render(TokensPage);
    await screen.findByText('Nachtelijke scanrobot');
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
    expect(document.body.textContent).not.toContain('plyat1_');
  });

  it('maakt geen tweede token zolang het geheim open staat (negatieve controle)', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Eerste');
    await screen.findByTestId('token-secret');
    expect(screen.getByRole('button', { name: 'Token aanmaken' })).toBeDisabled();
    expect(screen.getByLabelText(/^Naam/)).toBeDisabled();
    expect(screen.getByText(/Sluit eerst het geheim hierboven/)).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /auth/api-tokens']);
  });

  it('kopieert het geheim naar het klembord en meldt het zonder het te herhalen', async () => {
    setup();
    const ui = userEvent.setup();
    const write = vi.fn(async () => {});
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: write }, configurable: true });
    render(TokensPage);
    await create(ui, 'Agent');
    await ui.click(await screen.findByRole('button', { name: 'Kopiëren' }));
    expect(write).toHaveBeenCalledWith(FAKE_SECRET);
    expect(await screen.findByRole('button', { name: 'Gekopieerd' })).toBeInTheDocument();
  });

  it('zegt wat te doen als de browser het kopiëren blokkeert', async () => {
    setup();
    const ui = userEvent.setup();
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText: vi.fn(async () => Promise.reject(new Error('geweigerd'))) },
      configurable: true
    });
    render(TokensPage);
    await create(ui, 'Agent');
    await ui.click(await screen.findByRole('button', { name: 'Kopiëren' }));
    expect(await screen.findByText(/De browser blokkeerde het kopiëren/)).toBeInTheDocument();
  });

  it('vraagt een naam voordat er iets verstuurd wordt', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await ui.click(await screen.findByRole('button', { name: 'Token aanmaken' }));
    expect(await screen.findByText('Geef het token een naam.')).toBeInTheDocument();
    expect(server.writes()).toEqual([]);
  });
});

describe('scherm 34, brede scope', () => {
  it('vraagt bevestiging met uitleg voor een beheertoken en maakt hem pas daarna aan', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Beheeragent', 'Beheer');
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/kan alles wat jij kunt/)).toBeInTheDocument();
    expect(server.writes()).toEqual([]);
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
    await ui.click(within(dialog).getByRole('button', { name: 'Beheertoken aanmaken' }));
    await screen.findByTestId('token-secret');
    expect(server.seen.find((s) => s.method === 'POST')!.body).toMatchObject({ scope: 'admin' });
  });

  it('maakt niets aan als de bevestiging geannuleerd wordt (negatieve controle)', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Beheeragent', 'Beheer');
    await ui.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Annuleren' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(server.writes()).toEqual([]);
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
    expect(screen.getByLabelText(/^Naam/)).toHaveValue('Beheeragent');
  });

  it('vraagt geen bevestiging voor alleen lezen', async () => {
    setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Lezer', 'Alleen lezen');
    await screen.findByTestId('token-secret');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('toont de weigering van een bereik boven de rol als zin met uitweg en laat de lijst heel', async () => {
    const server = setup({ requesterRole: 'member' });
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Te veel', 'Beheer');
    await ui.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Beheertoken aanmaken' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('rol lid');
    expect(alert).toHaveTextContent('bereik beheer');
    expect(alert).toHaveTextContent('Kies een lager bereik');
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
    expect(screen.queryByRole('row', { name: /Te veel/ })).not.toBeInTheDocument();
    expect(screen.getByText('3 actief')).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /auth/api-tokens']);
  });

  it('geeft een zin als de server de invoer afwijst', async () => {
    setup({ fail: { 'POST /auth/api-tokens': () => apiError('session.invalid', 400) } });
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Agent', 'Alleen lezen');
    expect(await screen.findByRole('alert')).toHaveTextContent('Er is geen token aangemaakt');
    expect(screen.queryByTestId('token-secret')).not.toBeInTheDocument();
  });

  it('wijst naar inloggen als de server zegt dat je geen beheerder meer bent', async () => {
    setup({ fail: { 'POST /auth/api-tokens': () => apiError('auth.user_not_found', 404) } });
    const ui = userEvent.setup();
    render(TokensPage);
    await create(ui, 'Agent', 'Alleen lezen');
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('geen eigenaar of beheerder meer');
    expect(within(alert).getByRole('link')).toHaveAttribute('href', '/');
  });
});

describe('scherm 34, intrekken', () => {
  it('trekt een token pas in na bevestiging en haalt het dan uit de lijst', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await ui.click(await screen.findByRole('button', { name: 'Sannes leesassistent intrekken' }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText(/Dit token hoort bij Sanne/)).toBeInTheDocument();
    expect(server.writes()).toEqual([]);
    await ui.click(within(dialog).getByRole('button', { name: 'Intrekken' }));
    await waitFor(() => expect(server.writes()).toEqual(['DELETE /sessions/t3']));
    await waitFor(() => expect(screen.queryByText('Sannes leesassistent')).not.toBeInTheDocument());
    expect(screen.getByText('2 actief')).toBeInTheDocument();
  });

  it('doet niets als het intrekken geannuleerd wordt (negatieve controle)', async () => {
    const server = setup();
    const ui = userEvent.setup();
    render(TokensPage);
    await ui.click(await screen.findByRole('button', { name: 'Sannes leesassistent intrekken' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Annuleren' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(server.writes()).toEqual([]);
    expect(screen.getByText('Sannes leesassistent')).toBeInTheDocument();
  });

  it('laat de lijst intact bij een serverweigering en biedt opnieuw laden', async () => {
    setup({ fail: { 'DELETE /sessions/t3': () => apiError('auth.session_not_found', 404) } });
    const ui = userEvent.setup();
    render(TokensPage);
    await ui.click(await screen.findByRole('button', { name: 'Sannes leesassistent intrekken' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Intrekken' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Sannes leesassistent is al weg');
    expect(within(alert).getByRole('button', { name: /opnieuw/i })).toBeInTheDocument();
    expect(screen.getByRole('row', { name: /Sannes leesassistent/ })).toBeInTheDocument();
    expect(screen.getByText('3 actief')).toBeInTheDocument();
  });

  it('laat de lijst intact bij een serverfout en laat opnieuw proberen toe', async () => {
    setup({ fail: { 'DELETE /sessions/t3': () => apiError('server.internal', 500, { request_id: 'r-1' }) } });
    const ui = userEvent.setup();
    render(TokensPage);
    await ui.click(await screen.findByRole('button', { name: 'Sannes leesassistent intrekken' }));
    await ui.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Intrekken' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('r-1');
    expect(within(alert).getByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
    expect(screen.getByText('3 actief')).toBeInTheDocument();
  });
});

describe('scherm 34, server zonder API-tokens', () => {
  it('legt uit waarom er niets is en vraagt geen tokenroute', async () => {
    h.tokens = false;
    const server = setup();
    render(TokensPage);
    expect(await screen.findByText('Deze server heeft geen API-tokens')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Terug naar beveiliging' })).toHaveAttribute('href', '/admin/security');
    expect(screen.queryByRole('button', { name: 'Token aanmaken' })).not.toBeInTheDocument();
    expect(server.seen).toEqual([]);
  });
});

describe('scherm 34, rolgate', () => {
  it('laat een lid geen token- of auditroute raken', async () => {
    const server = fakeServer({ role: 'member' });
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
    for (const path of ['/auth/api-tokens', '/audit']) expect(server.seen).not.toContain(path);
    expect(server.adminCalls()).toEqual([]);
  });
});
