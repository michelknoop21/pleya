import { expect, test, type Page } from '@playwright/test';

import { expectNoHorizontalOverflow, heightFor, label, signIn } from './helpers';

/**
 * De browserspeler (S13.2, S18.3) tegen de echte API: een film openen vanaf
 * zijn detailpagina, zien dat de `<video>` loopt, sluiten, en dan geen
 * omzetsessie meer op de server. Plus de grens die de speler belooft: geen
 * accesstoken in welke URL dan ook.
 *
 * De testdata van `scripts/e2e-stack.sh` zijn H.264 in MKV. Een browser die MKV
 * speelt krijgt direct play; een die dat niet doet krijgt een remux over
 * hls.js. Beide wegen moeten hier slagen.
 */

const apiBearers = new WeakMap<Page, string>();
function apiToken(page: Page): string {
  const token = apiBearers.get(page);
  expect(Boolean(token), 'an authenticated browser API request supplied the test credential').toBe(true);
  return token!;
}

async function movieId(page: Page): Promise<string | null> {
  const token = apiToken(page);
  const headers = { Authorization: `Bearer ${token}` };
  const libs = (await (await page.request.get('/pleya/v1/libraries', { headers })).json()) as {
    items: { id: string; kind: string }[];
  };
  const films = libs.items.find((l) => l.kind === 'movies');
  if (!films) return null;
  const page1 = (await (
    await page.request.get(`/pleya/v1/libraries/${films.id}/items?limit=50`, { headers })
  ).json()) as { items: { id: string; title: string }[] };
  // PLEYA_E2E_PLAY_TITLE kiest een titel op een stack met meer dan de testdata.
  const wanted = process.env['PLEYA_E2E_PLAY_TITLE'];
  return (wanted ? page1.items.find((i) => i.title === wanted) : page1.items[0])?.id ?? null;
}

test.describe('de speler', () => {
  test.beforeEach(async ({ page }) => {
    page.on('request', request => {
      const url = new URL(request.url());
      const bearer = request.headers()['authorization'];
      if (url.origin === new URL(page.url()).origin && url.pathname.startsWith('/pleya/v1/') && bearer?.startsWith('Bearer ')) apiBearers.set(page, bearer.slice(7));
    });
    // Deze spec draait ook tegen een echte server: afspelen mag geen kijkstatus van dat account schrijven.
    await page.route('**/pleya/v1/watch-state', (route) => route.abort());
    await signIn(page);
  });

  test.afterEach(async ({ page }) => {
    const token = apiBearers.get(page);
    if (token) {
      const response = await page.request.post('/pleya/v1/auth/logout', { headers: { Authorization: `Bearer ${token}` } }).catch(() => { throw new Error('Fixture logout could not reach the server'); });
      expect(response.status(), 'fixture session revoked after playback').toBe(204);
    }
    apiBearers.delete(page);
  });

  test('weigert een onbekende expliciete versie zonder afspeelverzoek', async ({ page }) => {
    const id = await movieId(page);
    test.skip(!id, 'deze server heeft geen film');
    let plans = 0;
    page.on('request', request => { if (new URL(request.url()).pathname.endsWith('/playback/plan')) plans++; });
    await page.goto(`/items/${id}/play?version=00000000-0000-0000-0000-000000000000`);
    await expect(page.getByText('That version is no longer available.')).toBeVisible();
    await expect(page.locator('video')).toHaveCount(0);
    expect(plans).toBe(0);
  });

  test('speelt een film, ruimt op bij sluiten en zet geen token in een URL', async ({ page }) => {
    // Een omzetting mag tot 30 s op zijn eerste segment wachten (StartTimeout
    // in transcode/manager.go); daar komen inloggen en afspelen nog bij.
    test.setTimeout(90_000);
    const urls: string[] = [];
    page.on('request', (r) => urls.push(r.url()));

    const id = await movieId(page);
    test.skip(!id, 'deze server heeft geen film');

    await page.addInitScript(() => {
      const proof = { requested: '', applied: '' };
      Object.assign(window, { pleyaVersionProof: proof });
      const fetchOriginal = window.fetch.bind(window);
      window.fetch = Object.assign(async (input: Parameters<typeof window.fetch>[0], init?: Parameters<typeof window.fetch>[1]) => {
        const url = new URL(input instanceof Request ? input.url : String(input), location.href);
        if (!url.pathname.endsWith('/playback/plan')) return fetchOriginal(input, init);
        // DevTools may omit a streamed Request body; observe its clone without consuming the sent request.
        const request = new Request(input, init);
        const body = await request.clone().json().catch(() => null);
        proof.requested = body?.version_id ?? '';
        const response = await fetchOriginal(request);
        const plan = await response.clone().json().catch(() => null);
        proof.applied = plan?.version_id ?? '';
        return response;
      }, window.fetch);
    });
    await page.goto(`/items/${id}`);
    const play = page.getByRole('link', { name: label('en', 'player.playFromStart'), exact: true })
      .or(page.getByRole('link', { name: label('en', 'player.play'), exact: true })).first();
    const href = await play.getAttribute('href');
    const selectedVersion = new URL(href!, page.url()).searchParams.get('version');
    expect(Boolean(selectedVersion)).toBe(true);
    await play.click();
    await page.waitForURL(/\/play(?:\?.*)?$/);
    await expect.poll(() => page.evaluate(() => (window as unknown as {pleyaVersionProof:{requested:string}}).pleyaVersionProof.requested)).toBe(selectedVersion);
    await expect.poll(() => page.evaluate(() => (window as unknown as {pleyaVersionProof:{applied:string}}).pleyaVersionProof.applied)).toBe(selectedVersion);

    await expect
      .poll(() => page.evaluate(() => document.querySelector('video')?.currentTime ?? 0), {
        timeout: 45_000
      })
      .toBeGreaterThan(0.3);
    await expect(page.getByRole('alert')).toHaveCount(0);

    for (const width of [320, 1280]) {
      await page.setViewportSize({ width, height: heightFor(width) });
      await expectNoHorizontalOverflow(page);
    }

    await page.mouse.move(100, 100);
    await page.getByRole('button', { name: label('en', 'player.back'), exact: true }).click();
    await page.waitForURL(/\/items\/[^/]+$/);

    const token = apiToken(page);
    expect(urls.some((url) => url.includes(token)), 'no access credential in URLs').toBe(false);

    await expect
      .poll(async () => {
        const res = await page.request.get('/pleya/v1/transcode-sessions', {
          headers: { Authorization: `Bearer ${token}` }
        });
        return ((await res.json()) as { items: unknown[] }).items.length;
      })
      .toBe(0);
  });
});
