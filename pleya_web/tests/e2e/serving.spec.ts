import { expect, test } from '@playwright/test';

/**
 * Acceptatiecriterium 1, gemeten op de draaiende binary in plaats van in een
 * Go-test: de bundel wordt geserveerd en overschaduwt het protocol niet.
 */
test.describe('de binary serveert de bundel', () => {
  test('levert de app op de wortel', async ({ request }) => {
    const response = await request.get('/');
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toContain('text/html');
    expect(await response.text()).toContain('<title>Pleya</title>');
  });

  test('geeft een frontendroute dezelfde app terug', async ({ request }) => {
    for (const path of ['/libraries', '/search', '/items/onzin']) {
      const response = await request.get(path);
      expect(response.status(), path).toBe(200);
      expect(await response.text()).toContain('<title>Pleya</title>');
    }
  });

  test('laat /healthz en /readyz met rust', async ({ request }) => {
    for (const path of ['/healthz', '/readyz']) {
      const response = await request.get(path);
      expect(response.status(), path).toBe(200);
      expect(response.headers()['content-type']).toContain('application/json');
    }
  });

  test('stuurt een onbekende protocolroute niet naar de app', async ({ request }) => {
    const response = await request.get('/pleya/v1/nonexistent');
    expect(response.status()).toBe(404);
    expect(response.headers()['content-type']).toContain('application/json');
    expect(await response.json()).toMatchObject({ error: { code: 'library.not_found' } });
  });

  test('houdt een bestaand endpoint bij zijn eigen handler', async ({ request }) => {
    const info = await request.get('/pleya/v1/info');
    expect(info.status()).toBe(200);
    expect(await info.json()).toHaveProperty('capabilities');

    const guarded = await request.get('/pleya/v1/libraries');
    expect(guarded.status()).toBe(401);
    expect(await guarded.json()).toMatchObject({ error: { code: 'auth.token_invalid' } });
  });

  test('geeft gehashte bestanden een lange en HTML een korte levensduur', async ({ request }) => {
    const index = await request.get('/');
    expect(index.headers()['cache-control']).toBe('no-cache');

    const html = await index.text();
    const asset = /\/_app\/immutable\/[^"']+\.js/.exec(html)?.[0];
    expect(asset, 'geen gehashte bundel in index.html').toBeTruthy();

    const script = await request.get(asset!);
    expect(script.headers()['cache-control']).toContain('immutable');
  });

  test('zet de securityheaders en geen CORS', async ({ request }) => {
    const response = await request.get('/');
    const headers = response.headers();
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-frame-options']).toBe('DENY');
    expect(headers['content-security-policy']).toContain("frame-ancestors 'none'");
    expect(headers['referrer-policy']).toBe('no-referrer');
    expect(headers['access-control-allow-origin']).toBeUndefined();
  });
});
