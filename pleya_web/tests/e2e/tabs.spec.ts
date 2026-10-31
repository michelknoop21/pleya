import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { expectShell, label, PASSWORD, signIn, USERNAME } from './helpers';

/**
 * Twee tabbladen in één browserprofiel, tegen de echte server. De cookie en localStorage
 * zijn gedeeld, het accesstoken staat per tabblad. Op 127.0.0.1 is de pagina een secure
 * context, dus `navigator.locks` is hier echt.
 */

const STILL_SIGNED_IN = label('en', 'unreachable.signedIn');
/** Lang genoeg om twee verversingen zonder slot zeker te laten overlappen. */
const REFRESH_DELAY_MS = 700;

async function logOut(page: Page): Promise<void> {
  await page.goto('/server');
  await page.getByRole('button', { name: label('en', 'common.logout') }).click();
  await page.waitForURL('**/login');
}

async function logIn(page: Page): Promise<void> {
  await page.getByLabel(label('en', 'login.username')).fill(USERNAME);
  await page.getByLabel(label('en', 'login.password'), { exact: true }).fill(PASSWORD);
  await page.getByRole('button', { name: label('en', 'login.submit') }).click();
  await expectShell(page);
}

async function secondTab(context: BrowserContext): Promise<Page> {
  const tab = await context.newPage();
  await tab.goto('/');
  await expectShell(tab);
  return tab;
}

interface Refresh { start: number; end: number; status: number }

/** Vertraagt elke verversing van dit tabblad en houdt bij wanneer hij echt liep. */
async function watchRefreshes(page: Page): Promise<Refresh[]> {
  const seen: Refresh[] = [];
  await page.route('**/pleya/v1/auth/refresh', async (route) => {
    const entry = { start: Date.now(), end: 0, status: 0 };
    seen.push(entry);
    await new Promise((resolve) => setTimeout(resolve, REFRESH_DELAY_MS));
    const response = route.request().response().then((answer) => {
      entry.end = Date.now();
      entry.status = answer?.status() ?? 0;
    });
    await route.continue();
    await response;
  });
  return seen;
}

async function reloadBoth(a: Page, b: Page): Promise<void> {
  await Promise.all([a.reload(), b.reload()]);
  await Promise.all([expectShell(a), expectShell(b)]);
}

const overlaps = (x: Refresh, y: Refresh) => x.start < y.end && y.start < x.end;

test.describe('twee tabbladen', () => {
  test.use({ locale: 'en-US' });

  test('na uitloggen in een ander tabblad belooft een storing geen sessie meer', async ({ page, context }) => {
    await signIn(page);
    const stuck = await context.newPage();
    // /info en de verversing lukken nog, dus dit tabblad heeft een accesstoken in het geheugen.
    await stuck.route(/\/pleya\/v1\/(server|libraries|users\/me)$/, (route) => route.abort('connectionrefused'));
    await stuck.goto('/');
    await expect(stuck.getByRole('main')).toContainText(STILL_SIGNED_IN, { timeout: 20_000 });
    // Daarna valt de hele server weg voor dit tabblad, en antwoordt niets hem meer met een 401.
    await stuck.route('**/pleya/v1/**', (route) => route.abort('connectionrefused'));

    await logOut(page);

    await expect(stuck.getByRole('main')).not.toContainText(STILL_SIGNED_IN);
  });

  test('een verlaten tabblad wist de aantekening van een nieuwe login niet', async ({ page, context }) => {
    await signIn(page);
    const fresh = await secondTab(context);
    await logOut(fresh);
    await logIn(fresh);

    // De sessie van dit tabblad is weg: zijn eerste aanvraag krijgt een 401 en het geeft op.
    const nav = page.getByRole('navigation', { name: label('en', 'nav.primary') });
    await nav.getByRole('link', { name: label('en', 'nav.my') }).click();
    await page.waitForURL('**/server');
    await nav.getByRole('link', { name: label('en', 'nav.home') }).click();
    await page.waitForURL('**/login');

    expect(await fresh.evaluate(() => localStorage.getItem('pleya.cookie_session'))).toBe('1');

    await fresh.route('**/pleya/v1/info', (route) => route.abort('connectionrefused'));
    await fresh.reload();
    await expect(fresh.getByRole('main')).toContainText(STILL_SIGNED_IN);
  });

  test('het slot houdt twee verversingen uit elkaar en niemand raakt zijn sessie kwijt', async ({ page, context }) => {
    await signIn(page);
    const other = await secondTab(context);
    expect(await page.evaluate(() => isSecureContext && 'locks' in navigator)).toBe(true);
    const first = await watchRefreshes(page);
    const second = await watchRefreshes(other);

    await reloadBoth(page, other);

    expect(first).toHaveLength(1);
    expect(second).toHaveLength(1);
    expect(first[0]).toMatchObject({ status: 200 });
    expect(second[0]).toMatchObject({ status: 200 });
    // Elk tabblad heeft een eigen accesstoken nodig, dus het zijn er twee, na elkaar.
    expect(overlaps(first[0]!, second[0]!)).toBe(false);

    await reloadBoth(page, other);
  });

  test('zonder navigator.locks overlappen ze, en vangt het respijt dat op', async ({ page, context }) => {
    await context.addInitScript(() => {
      Object.defineProperty(Navigator.prototype, 'locks', { value: undefined, configurable: true });
    });
    await signIn(page);
    const other = await secondTab(context);
    expect(await page.evaluate(() => navigator.locks)).toBeUndefined();
    const first = await watchRefreshes(page);
    const second = await watchRefreshes(other);

    await reloadBoth(page, other);

    expect(first[0]).toMatchObject({ status: 200 });
    expect(second[0]).toMatchObject({ status: 200 });
    expect(overlaps(first[0]!, second[0]!)).toBe(true);

    await reloadBoth(page, other);
  });
});
