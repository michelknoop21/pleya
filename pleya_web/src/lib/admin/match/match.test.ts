/** De rekenregels van scherm 36 en de rolgate op het nieuwe pad. */
import { describe, expect, it } from 'vitest';

import { SessionState } from '../../stores/session.svelte';
import { adminGate } from '../gate';
import { fakeServer } from '../fakeServer';
import { setLocale } from '../../i18n';
import { isValidExternalId, outcomeLabel, sortedAttention } from './match';
import { attention } from './matchFake';

describe('titelnummer', () => {
  it('volgt het patroon van het contract', () => {
    for (const ok of ['1', '438631', '9999999999']) expect(isValidExternalId(ok)).toBe(true);
    for (const bad of ['', '0', '012', '-5', '1.5', '12345678901', ' 12', 'abc', '12 ']) {
      expect(isValidExternalId(bad)).toBe(false);
    }
  });
});

describe('volgorde en uitkomst', () => {
  it('zet ambigu voor niet gevonden, mislukt en afgewezen, daarbinnen op titel', () => {
    const sorted = sortedAttention([
      attention('a', 'Zed', 'rejected'),
      attention('b', 'Beta', 'ambiguous'),
      attention('c', 'Alfa', 'ambiguous'),
      attention('d', 'Gamma', 'failed'),
      attention('e', 'Delta', 'unmatched')
    ]);
    expect(sorted.map((i) => i.item_id)).toEqual(['c', 'b', 'e', 'd', 'a']);
  });

  it('telt de kandidaten en zegt niets gevonden bij een lege lijst', () => {
    setLocale('nl');
    const alt = { external_id: '1', title: 'x', year: null };
    expect(outcomeLabel(attention('a', 'X', 'ambiguous', { alternatives: [alt] }))).toBe('1 kandidaat');
    expect(outcomeLabel(attention('a', 'X', 'unmatched'))).toBe('niets gevonden');
    setLocale('en');
  });
});

describe('rolgate op Match en overrides', () => {
  it('geeft een lid een 404 en raakt de aandachtslijst en de matchroutes niet', async () => {
    const server = fakeServer({ role: 'member' });
    await expect(adminGate(new SessionState(server.client))).rejects.toMatchObject({ status: 404 });
    expect(server.seen.filter((p) => p.startsWith('/metadata') || p.includes('metadata-match'))).toEqual([]);
    expect(server.adminCalls()).toEqual([]);
  });

  it('laat een beheerder door', async () => {
    const server = fakeServer({ role: 'admin' });
    await expect(adminGate(new SessionState(server.client))).resolves.toBeUndefined();
  });
});
