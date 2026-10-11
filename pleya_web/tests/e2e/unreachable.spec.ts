import { expect, test, type Page } from '@playwright/test';

import { expectShell, label, signIn } from './helpers';

/**
 * Beeld 14: `GET /info` mislukt bij het starten. De staat staat in de schil,
 * in de taal van de browser, en een geslaagde poging brengt de gebruiker op de
 * route waar hij intussen heen klikte.
 *
 * `route.abort` en niet een 500: een server die een fout teruggeeft is wél
 * bereikbaar. Wat hier nagebootst wordt is een verbinding die er niet is.
 */

async function cutInfo(page: Page): Promise<() => number> {
  let hits = 0;
  await page.route('**/pleya/v1/info', async (route) => {
    hits += 1;
    await route.abort('connectionrefused');
  });
  return () => hits;
}

test.describe('onbereikbare server (nl)', () => {
  test.use({ locale: 'nl-NL' });

  test('staat in de schil en komt terug op de route waar je heen klikte', async ({ page }) => {
    await page.addInitScript(() => {
      try {
        localStorage.removeItem('pleya.locale');
      } catch {
        // Opslag geweigerd: de browsertaal beslist al.
      }
    });
    await signIn(page, 'nl');

    const hits = await cutInfo(page);
    await page.goto('/');

    const main = page.getByRole('main');
    await expect(page.getByRole('heading', { level: 1 })).toContainText('is niet bereikbaar');
    await expect(main).toContainText('Je bent nog ingelogd');
    await expect(main).toContainText('Laatste contact');
    await expect(main).toContainText(/opnieuw proberen over \d+ s/);
    // De schil komt uit het record: de navigatie met Mijn Pleya erin.
    await expectShell(page, 'nl');
    const nav = page.getByRole('navigation', { name: label('nl', 'nav.primary') });
    await expect(nav.getByRole('link', { name: label('nl', 'nav.my') })).toBeVisible();
    expect(hits()).toBeGreaterThan(0);

    // Klikken verandert de URL, de staat blijft staan tot de server antwoordt.
    await nav.getByRole('link', { name: label('nl', 'nav.my') }).click();
    await page.waitForURL('**/server');
    await expect(page.getByRole('button', { name: label('nl', 'unreachable.retryNow') })).toBeVisible();

    await page.unroute('**/pleya/v1/info');
    await page.getByRole('button', { name: label('nl', 'unreachable.retryNow') }).click();

    // Terug in de app, op /server, met de bibliotheekrijen die de route tekent.
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(label('nl', 'server.title'), {
      timeout: 20_000
    });
    await expect(page.locator('[data-library-kind][data-library-id]').first()).toBeVisible();
    expect(new URL(page.url()).pathname).toBe('/server');
  });
});

test.describe('onbereikbare server zonder record (en)', () => {
  test.use({ locale: 'en-US' });

  test('noemt de host en toont alleen My Pleya', async ({ page }) => {
    await page.addInitScript(() => {
      try {
        localStorage.removeItem('pleya.locale');
        localStorage.removeItem('pleya.lastContact');
      } catch {
        // Opslag geweigerd: dan is er ook geen record.
      }
    });
    await cutInfo(page);
    await page.goto('/');

    const host = new URL(page.url()).host;
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(`${host} is not reachable`);
    await expect(page.getByRole('main')).not.toContainText('Last contact');
    const nav = page.getByRole('navigation', { name: label('en', 'nav.primary') });
    await expect(nav.getByRole('listitem')).toHaveText([label('en', 'nav.my')]);
  });
});
