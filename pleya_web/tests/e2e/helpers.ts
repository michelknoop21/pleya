import { expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

export const SETUP_CODE = process.env['PLEYA_E2E_SETUP_CODE'] ?? '';

/**
 * De inloggegevens komen uit de omgeving, zodat dezelfde suite tegen de
 * wegwerpstack én tegen een echte server kan draaien. De standaardwaarden zijn
 * die van `scripts/e2e-stack.sh`.
 */
export const USERNAME = process.env['PLEYA_E2E_USER'] ?? 'e2e';
export const PASSWORD = process.env['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';

/** De vijf breedtes uit de responsive-strategie van PS-3W. */
export const WIDTHS = [390, 768, 1024, 1280, 1600] as const;

/**
 * Zorgt dat er een sessie is.
 *
 * De eerste keer wisselt hij de setupcode in; daarna logt hij in. Welke van de
 * twee nodig is zegt de server zelf in `GET /info`, dus die vraag wordt hier
 * gesteld en niet geraden.
 */
export async function signIn(page: Page): Promise<void> {
  await page.goto('/');

  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };

  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    await page.getByLabel('Setup code').fill(SETUP_CODE);
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password', { exact: false }).fill(PASSWORD);
    await page.getByRole('button', { name: 'Create owner' }).click();
  } else {
    await page.waitForURL('**/login');
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in' }).click();
  }

  await expectShell(page);
}

/**
 * Wacht tot de schil staat.
 *
 * Ruimer dan de standaard vijf seconden, en niet uit gemakzucht. Na een
 * inlogantwoord of een herlaadbeurt haalt de schil eerst /server en /libraries
 * op voordat er navigatie is, en tegen een server achter een tunnel is de
 * eerste verbinding van een run de traagste die er is. Vijf seconden haalt dat
 * op een koude start net niet, en dan faalt één test terwijl diezelfde test los
 * in twee seconden slaagt.
 *
 * Eén plek, omdat drie losse asserties met de standaardtermijn precies dat
 * probleem drie keer opnieuw opleveren.
 */
export async function expectShell(page: Page): Promise<void> {
  await expect(page.getByRole('navigation', { name: 'Primary' })).toBeVisible({
    timeout: 20_000
  });
}

/**
 * Het inhoudsraster op de huidige pagina.
 *
 * `getByRole('listitem')` op paginaniveau is misleidend: de navigatie is ook
 * een lijst en staat eerder in de DOM, dus "het eerste lijstonderdeel" is dan
 * de link naar Home. Het raster draagt een toegankelijke naam en is daarmee
 * eenduidig aan te wijzen.
 */
export function grid(page: Page) {
  return page.getByRole('main').getByRole('list').last();
}

/** Draait axe op de huidige pagina en eist nul overtredingen. */
export async function expectNoAxeViolations(page: Page, context?: string): Promise<void> {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();

  const summary = results.violations
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)
    .join('\n');

  expect(results.violations, `axe op ${context ?? page.url()}:\n${summary}`).toEqual([]);
}

/**
 * Opent de eerste bibliotheek van een soort en geeft zijn pad terug.
 *
 * De testbibliotheek van `e2e-stack.sh` en een echte bibliotheek op een NAS
 * hebben niets gemeen behalve hun vorm, dus een test die een titel uit de
 * testdata noemt draait maar op één van de twee. De soort staat wél in de UI,
 * en dat is genoeg om er een te kiezen.
 */
export async function openLibraryOfKind(page: Page, kind: 'movies' | 'shows'): Promise<boolean> {
  await page.goto('/server');
  await page.getByRole('heading', { name: 'Server', level: 1 }).waitFor();
  const titles = await page
    .locator('.rows__row')
    .filter({ hasText: kind })
    .evaluateAll((els) => els.map((el) => el.querySelector('.t-body')?.textContent?.trim() ?? ''));
  const title = titles.find(Boolean);
  if (!title) return false;

  await page.goto('/libraries');
  await page.getByRole('link', { name: new RegExp(title, 'i') }).first().click();
  await page.waitForURL(/\/libraries\/.+/);
  return true;
}

/** Geen horizontale schuifbalk op de pagina zelf. */
export async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  expect(overflow, 'de pagina schuift horizontaal').toBeLessThanOrEqual(1);
}
