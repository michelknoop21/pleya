import { describe, expect, it } from 'vitest';

import { TokenStore, type TokenStorage } from './tokens';

function store(initial: Record<string, string> = {}): TokenStorage {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => void map.set(k, v),
    removeItem: (k) => void map.delete(k)
  };
}

describe('tokenopslag', () => {
  it('bewaart het refreshtoken duurzaam en het accesstoken per tab', () => {
    const persistent = store();
    const session = store();
    const tokens = new TokenStore(persistent, session);

    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    expect(persistent.getItem('pleya.refresh_token')).toBe('R1');
    expect(session.getItem('pleya.access_token')).toContain('A1');
    expect(persistent.getItem('pleya.access_token')).toBeNull();
  });

  it('overleeft een herlaadbeurt zonder te verversen', () => {
    const persistent = store();
    const session = store();
    new TokenStore(persistent, session).set({
      access_token: 'A1',
      refresh_token: 'R1',
      expires_in_ms: 900_000
    });

    // Een nieuwe instantie is wat er na een herlaadbeurt gebeurt.
    const afterReload = new TokenStore(persistent, session);
    expect(afterReload.accessToken).toBe('A1');
  });

  it('geeft een verlopen accesstoken niet terug', () => {
    let now = 1_000_000;
    const tokens = new TokenStore(store(), store(), () => now);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 60_000 });

    expect(tokens.accessToken).toBe('A1');
    now += 60_000;
    expect(tokens.accessToken).toBeNull();
  });

  it('houdt marge, zodat een token niet onderweg verloopt', () => {
    let now = 1_000_000;
    const tokens = new TokenStore(store(), store(), () => now);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 40_000 });

    now += 15_000; // nog 25 s te gaan, minder dan de marge van 30 s
    expect(tokens.accessToken).toBeNull();
  });

  it('gooit bij afmelden allebei de tokens weg', () => {
    const persistent = store();
    const session = store();
    const tokens = new TokenStore(persistent, session);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    tokens.clear();

    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
  });

  it('werkt door wanneer de browser opslag weigert', () => {
    const tokens = new TokenStore(null, null);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    expect(tokens.accessToken).toBe('A1');
    expect(tokens.refreshToken).toBeNull();
  });
});
