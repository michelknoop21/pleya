/**
 * De beheerschil zelf (S10.1, S10.7). Een lid dat de load voorbij kwam omdat
 * de rol toen nog niet vaststond, ziet niets van beheer en zet de load opnieuw
 * in gang; een eigenaar krijgt de zijbalk en het overzicht, en dan gaan de
 * beheeraanvragen wel de deur uit (positieve controle op dezelfde telling).
 */
import { createRawSnippet, tick } from 'svelte';
import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { SessionState } from '#lib/stores/session.svelte.js';
import { fakeServer } from '#lib/admin/fakeServer.js';
import { setLocale } from '#lib/i18n/index.js';

const h = vi.hoisted(() => ({
  current: null as unknown as object,
  invalidateAll: vi.fn(async () => {})
}));

vi.mock('$app/state', () => ({ page: { url: new URL('http://localhost/admin') } }));
vi.mock('$app/navigation', () => ({ invalidateAll: h.invalidateAll }));

// De singleton wijst per test naar een eigen sessie met een eigen nepserver.
vi.mock('#lib/stores/session.svelte.js', async (importOriginal) => {
  const mod = await importOriginal<typeof import('#lib/stores/session.svelte.js')>();
  const session = new Proxy(
    {},
    {
      get(_target, key) {
        const value = Reflect.get(h.current, key);
        return typeof value === 'function' ? value.bind(h.current) : value;
      }
    }
  );
  return { ...mod, session };
});

import Layout from './+layout.svelte';
import Page from './+page.svelte';

const sentinel = createRawSnippet(() => ({ render: () => '<p>beheerinhoud</p>' }));

async function readySession(role: 'owner' | 'admin' | 'member') {
  const server = fakeServer({ role });
  const session = new SessionState(server.client);
  await session.ensureStarted();
  h.current = session;
  return server;
}

beforeEach(() => {
  setLocale('nl');
  h.invalidateAll.mockClear();
});

describe('de beheerschil', () => {
  it('rendert voor een lid niets van beheer en laat de load de 404 geven', async () => {
    const server = await readySession('member');
    render(Layout, { props: { children: sentinel } });
    await tick();

    expect(screen.queryByText('beheerinhoud')).not.toBeInTheDocument();
    expect(screen.queryByRole('navigation', { name: 'Serverbeheer' })).not.toBeInTheDocument();
    expect(h.invalidateAll).toHaveBeenCalled();
    expect(server.adminCalls()).toEqual([]);
  });

  it('geeft een eigenaar de zijbalk met Overzicht actief en de inhoud', async () => {
    await readySession('owner');
    render(Layout, { props: { children: sentinel } });

    const nav = screen.getByRole('navigation', { name: 'Serverbeheer' });
    expect(nav).toBeInTheDocument();
    expect(screen.getByText('beheerinhoud')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Overzicht' })).toHaveAttribute('aria-current', 'page');
    expect(h.invalidateAll).not.toHaveBeenCalled();
  });

  it('laat het overzicht voor een eigenaar de beheerroutes vragen (positieve controle)', async () => {
    const server = await readySession('owner');
    render(Page);

    await waitFor(() => expect(screen.getByRole('heading', { name: 'Pleya-server' })).toBeInTheDocument());
    expect(server.adminCalls().sort()).toEqual(
      ['/jobs', '/scans', '/storage/roots', '/stream-sessions', '/transcode-sessions', '/users'].sort()
    );
  });
});
