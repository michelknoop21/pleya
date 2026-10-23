import { expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

import { setLocale, t, type Locale, type MessageKey } from '../../src/lib/i18n';

export const SETUP_CODE = process.env['PLEYA_E2E_SETUP_CODE'] ?? '';

/**
 * De inloggegevens komen uit de omgeving, zodat dezelfde suite tegen de
 * wegwerpstack én tegen een echte server kan draaien. De standaardwaarden zijn
 * die van `scripts/e2e-stack.sh`.
 */
export const USERNAME = process.env['PLEYA_E2E_USER'] ?? 'e2e';
export const PASSWORD = process.env['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';

/**
 * De breedtes waarop elke route gemeten wordt: de vaste vijf van de werkafspraak
 * (320, 390, 1280, 1440, 1920) en de breekpunten van de northstar ertussen (768
 * en 1024 aan weerszijden van 900, 1600 voor de breedste inzet). 390 staat voor
 * de 393 van de northstar; drie pixels verschuiven geen breekpunt.
 */
export const WIDTHS = [320, 390, 768, 1024, 1280, 1440, 1600, 1920] as const;

/** Hoogte bij een breedte: 1920 als volledig HD-scherm, de rest op 900. */
export function heightFor(width: number): number {
  return width >= 1920 ? 1080 : 900;
}

/**
 * De tags van de eerdere a11y-gates. `best-practice` hoort erbij omdat de gate
 * daar eerder ook op liep; zonder die tag zou de e2e-meting milder zijn dan de
 * handmatige ronde en een regressie pas bij de gate opvallen.
 */
export const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice'];

/**
 * Een label uit de catalogus in een bepaalde taal.
 *
 * `t()` leest een modulevariabele, dus de taal wordt bij elke vraag opnieuw
 * gezet. Anders hangt het antwoord af van welke helper toevallig het laatst
 * draaide.
 */
export function label(locale: Locale, key: MessageKey): string {
  setLocale(locale);
  return t(key);
}

/**
 * Zorgt dat er een sessie is.
 *
 * De eerste keer wisselt hij de setupcode in; daarna logt hij in. Welke van de
 * twee nodig is zegt de server zelf in `GET /info`, dus die vraag wordt hier
 * gesteld en niet geraden.
 */
export async function signIn(page: Page, locale: Locale = 'en'): Promise<void> {
  await page.goto('/');

  if (await setupRequired(page)) {
    await page.waitForURL('**/setup');
    await page.getByLabel(label(locale, 'setup.code')).fill(SETUP_CODE);
    await page.getByLabel(label(locale, 'setup.username')).fill(USERNAME);
    await page.getByLabel(label(locale, 'setup.password'), { exact: true }).fill(PASSWORD);
    await page.getByRole('button', { name: label(locale, 'setup.submit') }).click();
  } else {
    await page.waitForURL('**/login');
    await page.getByLabel(label(locale, 'login.username')).fill(USERNAME);
    await page.getByLabel(label(locale, 'login.password'), { exact: true }).fill(PASSWORD);
    await page.getByRole('button', { name: label(locale, 'login.submit') }).click();
  }

  await expectShell(page, locale);
}

/** Of de server nog een eigenaar zoekt; dat zegt `GET /info`, niet een gok. */
export async function setupRequired(page: Page): Promise<boolean> {
  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  return body.auth.setup_required;
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
export async function expectShell(page: Page, locale: Locale = 'en'): Promise<void> {
  await expect(page.getByRole('navigation', { name: label(locale, 'nav.primary') })).toBeVisible({
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

/**
 * Draait axe op de huidige pagina en eist nul overtredingen.
 *
 * De context staat in de foutmelding, met breedte en taal erbij: een rode regel
 * zonder die twee is in een matrix van vijftig metingen niet terug te vinden.
 */
export async function expectNoAxeViolations(page: Page, context?: string): Promise<void> {
  const results = await new AxeBuilder({ page }).withTags(AXE_TAGS).analyze();
  // Alleen de regel-ids vergelijken: de plekken staan al in de melding, en het
  // volledige resultaatobject maakt van één rode regel veertig regels uitvoer.
  const ids = results.violations.map((v) => v.id);
  expect(ids, axeMessage(page, results.violations, context)).toEqual([]);
}

type AxeViolation = Awaited<ReturnType<AxeBuilder['analyze']>>['violations'][number];

/** Route, breedte en taal, en per overtreding de regel en de plekken. */
export function axeMessage(page: Page, violations: AxeViolation[], context?: string): string {
  const width = page.viewportSize()?.width ?? '?';
  const where = `${context ?? new URL(page.url()).pathname} op ${width}px`;
  const summary = violations
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)
    .join('\n');
  return `axe op ${where}:\n${summary}`;
}

/**
 * Opent de eerste bibliotheek van een soort en geeft zijn pad terug, of `null`
 * als de server er geen van die soort heeft.
 *
 * De testbibliotheek van `e2e-stack.sh` en een echte bibliotheek op een NAS
 * hebben niets gemeen behalve hun vorm, dus een test die een titel uit de
 * testdata noemt draait maar op één van de twee. De soort staat op /server als
 * `data-library-kind` op de bibliotheekrij. Dat attribuut en niet de klassen
 * of de zichtbare tekst: de klassen verdwijnen bij de routemigratie (S7.6 taak
 * 7) en de tekst verschilt per taal.
 */
export async function openLibraryOfKind(
  page: Page,
  kind: 'movies' | 'shows'
): Promise<string | null> {
  await page.goto('/server');
  await page.getByRole('heading', { level: 1 }).first().waitFor();
  const ids = await page
    .locator(`[data-library-kind="${kind}"]`)
    .evaluateAll((els) => els.map((el) => el.getAttribute('data-library-id') ?? ''));
  const id = ids.find(Boolean);
  if (!id) return null;

  const path = `/libraries/${id}`;
  await page.goto(path);
  await page.waitForURL(/\/libraries\/.+/);
  return path;
}

/** Geen horizontale schuifbalk op de pagina zelf. */
export async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  expect(overflow, 'de pagina schuift horizontaal').toBeLessThanOrEqual(1);
}
