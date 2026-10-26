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

async function movieId(page: Page): Promise<string | null> {
  const token = await page.evaluate(() => {
    const raw = sessionStorage.getItem('pleya.access_token');
    return raw ? (JSON.parse(raw) as { token: string }).token : '';
  });
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
    await signIn(page);
  });

  test('speelt een film, ruimt op bij sluiten en zet geen token in een URL', async ({ page }) => {
    // Een omzetting mag tot 30 s op zijn eerste segment wachten (StartTimeout
    // in transcode/manager.go); daar komen inloggen en afspelen nog bij.
    test.setTimeout(90_000);
    const urls: string[] = [];
    page.on('request', (r) => urls.push(r.url()));

    const id = await movieId(page);
    test.skip(!id, 'deze server heeft geen film');

    await page.goto(`/items/${id}`);
    await page.getByRole('link', { name: label('en', 'player.play') }).click();
    await page.waitForURL(/\/play$/);

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

    const token = await page.evaluate(() => {
      const raw = sessionStorage.getItem('pleya.access_token');
      return raw ? (JSON.parse(raw) as { token: string }).token : '';
    });
    expect(token).not.toBe('');
    expect(urls.filter((u) => u.includes(token))).toEqual([]);

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
