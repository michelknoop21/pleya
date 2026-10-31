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

  it('wist een oud refreshtoken wanneer de nieuwe tokenpair er geen bevat', () => {
    const persistent = store({ 'pleya.refresh_token': 'R-oud' });
    const tokens = new TokenStore(persistent, store());

    tokens.set({ access_token: 'A-cookie', expires_in_ms: 900_000 });

    expect(tokens.refreshToken).toBeNull();
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
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

describe('cookie credential storage', () => {
  it('keeps access in memory and removes persistent credentials in cookie mode', () => {
    const persistent = store({ 'pleya.refresh_token': 'legacy-R' });
    const session = store({ 'pleya.access_token': 'legacy-A' });
    const tokens = new TokenStore(persistent, session);
    tokens.setMemoryOnly(true);
    tokens.set({ access_token: 'cookie-A', expires_in_ms: 900000 });
    expect(tokens.accessToken).toBe('cookie-A');
    expect(tokens.refreshToken).toBeNull();
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
    expect(new TokenStore(persistent, session).hasSomething).toBe(false);
  });
  it('onthoudt een cookiesessie over een herlaadbeurt, zonder credential', () => {
    const persistent = store();
    const tokens = new TokenStore(persistent, store());
    tokens.setMemoryOnly(true);
    tokens.set({ access_token: 'cookie-A', expires_in_ms: 900000 });

    const reloaded = new TokenStore(persistent, store());
    expect(reloaded.signedIn).toBe(true);
    expect(reloaded.accessToken).toBeNull();
    expect(reloaded.refreshToken).toBeNull();

    // `GET /info` slaagt: de overstap naar geheugen wist de tokens, niet de aantekening.
    reloaded.setMemoryOnly(true);
    expect(reloaded.signedIn).toBe(true);
    expect(new TokenStore(persistent, store()).signedIn).toBe(true);

    reloaded.clear();
    expect(new TokenStore(persistent, store()).signedIn).toBe(false);
  });
  it('zegt niet dat een lege browser of een server zonder cookies een cookiesessie heeft', () => {
    expect(new TokenStore(store(), store()).signedIn).toBe(false);

    const persistent = store();
    const tokens = new TokenStore(persistent, store());
    tokens.setMemoryOnly(true);
    tokens.set({ access_token: 'cookie-A', expires_in_ms: 900000 });
    tokens.setMemoryOnly(false);
    tokens.set({ access_token: 'legacy-A', refresh_token: 'legacy-R', expires_in_ms: 900000 });
    expect(persistent.getItem('pleya.cookie_session')).toBeNull();
    expect(new TokenStore(persistent, store()).signedIn).toBe(true);
  });
  it('can use the existing legacy storage again for a server without cookies', () => {
    const persistent = store(); const session = store();
    const tokens = new TokenStore(persistent, session);
    tokens.setMemoryOnly(true);
    tokens.set({ access_token: 'cookie-A', expires_in_ms: 900000 });
    tokens.setMemoryOnly(false);
    tokens.set({ access_token: 'legacy-A', refresh_token: 'legacy-R', expires_in_ms: 900000 });
    expect(persistent.getItem('pleya.refresh_token')).toBe('legacy-R');
    expect(session.getItem('pleya.access_token')).toContain('legacy-A');
  });
});

it('removes the legacy refresh credential even when session storage rejects removal', () => {
  const persistent = store({ 'pleya.refresh_token': 'legacy-R' });
  const blocked: TokenStorage = { getItem: () => null, setItem: () => { throw new Error('blocked'); }, removeItem: () => { throw new Error('blocked'); } };
  const tokens = new TokenStore(persistent, blocked);
  tokens.setMemoryOnly(true);
  expect(persistent.getItem('pleya.refresh_token')).toBeNull();
});
