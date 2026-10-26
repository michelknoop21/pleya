/**
 * Opnamen van bibliotheekbeheer (S10.2, schermen 21 tot 23) tegen een
 * draaiende server, op de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en
 * 320. Zelfde opzet als admin-shots.ts: inloggen, per breedte herladen, de
 * horizontale paginaoverloop meten en een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 PLEYA_E2E_USER=… PLEYA_E2E_PASS=… \
 *     bun run scripts/admin-libraries-shots.ts [uitvoermap]
 *
 * Alleen lezen. Elke aanvraag die iets zou veranderen (alles behalve GET en de
 * inlogroutes) wordt in de browser afgebroken, dus een verkeerde klik raakt de
 * server nooit. Op de testinstance komt elke bibliotheek uit
 * PLEYA_SERVER_LIBRARIES en is elke root al in gebruik; scherm 22 in de
 * bewerkbare vorm en de dialoog van 23 bestaan daar dus niet. Die twee worden
 * vastgelegd met Films als `managed: db` in het antwoord van `GET /libraries`,
 * alleen in deze browser, en dragen `-nagebootst` in de bestandsnaam.
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const USER = process.env['PLEYA_E2E_USER'] ?? '';
const PASS = process.env['PLEYA_E2E_PASS'] ?? '';
const OUT = process.argv[2] ?? '../docs/qa/s10-libraries';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({
  ...localeContextOptions('nl'),
  viewport: { width: 1440, height: 900 }
});
const page = await context.newPage();
const errors: string[] = [];
const blocked: string[] = [];
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

// Vangnet: niets dat schrijft komt bij de server.
await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const path = new URL(request.url()).pathname;
  if (request.method() === 'GET' || path.includes('/pleya/v1/auth/')) return route.fallback();
  blocked.push(`${request.method()} ${path}`);
  return route.abort();
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill(USER);
await page.getByLabel(t('login.password'), { exact: true }).fill(PASS);
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function measure(name: string, width: number, fullPage = false): Promise<void> {
  const over = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage, type: 'jpeg', quality: 70 });
  console.log(`${name}@${width}: overloop ${over}px`);
}

async function shoot(
  path: string,
  name: string,
  widths = WIDTHS,
  prepare?: (p: Page) => Promise<void>
): Promise<void> {
  await page.goto(`${BASE}${path}`);
  for (const width of widths) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    if (prepare) await prepare(page);
    await measure(name, width, width >= 1280 && !prepare);
  }
}

await shoot('/admin/libraries', 'bibliotheken');

const filmsId = await page
  .locator('tr[data-library]', { has: page.getByRole('link', { name: 'Films', exact: true }) })
  .first()
  .getAttribute('data-library');
if (!filmsId) throw new Error('Films staat niet in de lijst');

await shoot(`/admin/libraries/${filmsId}`, 'bibliotheek-env');
await shoot('/admin/libraries/new', 'bibliotheek-toevoegen');

// Vanaf hier is Films in deze browser een db-bibliotheek (zie de kop).
await context.route('**/pleya/v1/libraries', async (route) => {
  if (route.request().method() !== 'GET') return route.fallback();
  const response = await route.fetch();
  const body = (await response.json()) as { items: { id: string; managed?: string }[] };
  for (const item of body.items) if (item.id === filmsId) item.managed = 'db';
  return route.fulfill({ response, json: body });
});

await shoot(`/admin/libraries/${filmsId}`, 'bibliotheek-bewerken-nagebootst');
await shoot(`/admin/libraries/${filmsId}`, 'bibliotheek-verwijderen-nagebootst', WIDTHS, async (p) => {
  await p.getByRole('button', { name: t('admin.lib.delete.open') }).click();
  await p.getByRole('dialog').getByRole('textbox').fill('Fil');
  await p.waitForTimeout(300);
});

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
