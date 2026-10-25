/**
 * Opnamen van de keten in de webclient tegen een draaiende server, op de vaste
 * breedtes van de werkafspraak (1920 bij 1080, 1440, 1280, 390 en 320).
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:18833 PLEYA_E2E_USER=… PLEYA_E2E_PASS=… \
 *     bun run scripts/chain-shots.ts [uitvoermap]
 *
 * Inloggen, de bibliotheeklijst, een bibliotheek, een itemdetail en een
 * zoekopdracht. Per beeld ook de horizontale paginaoverloop, want een scherm
 * dat zijwaarts scrolt is op 320 het eerste dat stuk gaat.
 */
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';
const USER = process.env['PLEYA_E2E_USER'] ?? '';
const PASS = process.env['PLEYA_E2E_PASS'] ?? '';
const OUT = process.argv[2] ?? '../docs/qa/chain-acceptance';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const page = await (
  await browser.newContext({ ...localeContextOptions('nl'), viewport: { width: 1440, height: 900 } })
).newPage();
const errors: string[] = [];
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill(USER);
await page.getByLabel(t('login.password'), { exact: true }).fill(PASS);
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function shoot(name: string) {
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    // Een toestel opent de pagina op zijn eigen breedte; opnieuw laden laat
    // layoutmetingen bij het mounten (virtueel raster) daar rekening mee houden.
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    await page.screenshot({
      path: `${OUT}/${name}@${width}.jpg`,
      fullPage: false,
      type: 'jpeg',
      quality: 70
    });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await page.waitForLoadState('networkidle');
await shoot('home');

await page.goto(`${BASE}/libraries`);
await page.waitForLoadState('networkidle');
await shoot('bibliotheken');

await page.locator('a[href^="/libraries/"]').first().click();
await page.waitForLoadState('networkidle');
await page.waitForTimeout(1500);
await shoot('bibliotheek');

await page.locator('a[href^="/items/"]').first().click();
await page.waitForLoadState('networkidle');
await page.waitForTimeout(1500);
await shoot('detail');

await page.goto(`${BASE}/search?q=the`);
await page.waitForLoadState('networkidle');
await page.waitForTimeout(1000);
await shoot('zoeken');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
await browser.close();
