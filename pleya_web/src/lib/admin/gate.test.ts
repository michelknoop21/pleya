/**
 * S10.7: een lid krijgt op `/admin` een 404 en de beheerlaag doet voor hem
 * geen enkele beheeraanvraag. Getest met een echte SessionState en een echte
 * PleyaClient tegen een nepfetch, zodat "nul beheeraanroepen" een telling is
 * en geen aanname.
 */
import { describe, expect, it } from 'vitest';

import { ADMIN_PATHS } from '../api/admin';
import { SessionState } from '../stores/session.svelte';
import { adminGate } from './gate';
import { fakeServer } from './fakeServer';

describe('rolgate van /admin', () => {
  it('geeft een lid een 404 zonder één beheeraanvraag', async () => {
    const server = fakeServer({ role: 'member' });
    const session = new SessionState(server.client);

    // Dezelfde tekst als de router geeft voor een pad dat niet bestaat.
    await expect(adminGate(session)).rejects.toMatchObject({
      status: 404,
      body: { message: 'Not Found' }
    });
    expect(session.phase).toBe('ready');
    expect(server.seen).toContain('/users/me');
    expect(server.adminCalls()).toEqual([]);
  });

  it('geeft een beperkte gebruiker dezelfde 404', async () => {
    const server = fakeServer({ role: 'restricted' });
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
    expect(server.adminCalls()).toEqual([]);
  });

  it('laat een eigenaar en een beheerder door', async () => {
    for (const role of ['owner', 'admin'] as const) {
      const server = fakeServer({ role });
      await expect(adminGate(new SessionState(server.client))).resolves.toBeUndefined();
    }
  });

  it('geeft ook een eigenaar een 404 op een server zonder beheeroppervlak', async () => {
    const server = fakeServer({ role: 'owner', administration: false });
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
  });

  it('stuurt een bezoeker zonder sessie niet naar een 404 maar laat de schil naar inloggen gaan', async () => {
    const server = fakeServer({ role: 'member', signedIn: false });
    const session = new SessionState(server.client);
    await expect(adminGate(session)).resolves.toBeUndefined();
    expect(session.phase).toBe('signed-out');
    expect(server.adminCalls()).toEqual([]);
  });

  it('start de sessie één keer, ook als de schil en de gate allebei vragen', async () => {
    const server = fakeServer({ role: 'owner' });
    const session = new SessionState(server.client);
    await Promise.all([session.ensureStarted(), adminGate(session), session.ensureStarted()]);
    expect(server.seen.filter((p) => p === '/info')).toHaveLength(1);
  });
});

describe('rolgate en de instellingenroutes (S10.5)', () => {
  it('laat een lid geen enkele instellings- of diagnoseroute raken', async () => {
    const server = fakeServer({ role: 'member' });
    // De gate beslist vóór de pagina rendert, dus nul aanroepen op deze paden.
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
    for (const path of ['/settings', '/server/environment', '/server/log', '/metadata/attention']) {
      expect(server.seen).not.toContain(path);
    }
    expect(server.adminCalls()).toEqual([]);
  });

  it('beschouwt die routes als beheerpaden, zodat de telling ze ziet', () => {
    for (const path of ['/settings', '/server/environment', '/server/log', '/metadata/attention']) {
      expect(ADMIN_PATHS as readonly string[]).toContain(path);
    }
  });
});
