/**
 * Opnamen van serverbeheer (S10.1, S10.7 en het overzicht, scherm 20) tegen
 * een draaiende server, op de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en
 * 320. Zelfde opzet als chain-shots.ts: inloggen, per breedte herladen, de
 * horizontale paginaoverloop meten en een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 PLEYA_E2E_USER=… PLEYA_E2E_PASS=… \
 *     bun run scripts/admin-shots.ts [uitvoermap]
 *
 * `/admin` is vanaf 900 het overzicht en daaronder de mobiele index (33); het
 * overzicht op telefoonbreedte staat op `/admin/overview`. Een sectie zonder
 * eigen scherm (`/admin/network`) laat de lege staat zien. Het overzicht wordt
 * ook als hele pagina vastgelegd, zoals de northstar dat op breed doet.
 */
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const USER = process.env['PLEYA_E2E_USER'] ?? '';
const PASS = process.env['PLEYA_E2E_PASS'] ?? '';
const OUT = process.argv[2] ?? '../docs/qa/s10-admin-shell';
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

async function shoot(path: string, name: string, widths = WIDTHS, fullPage = false) {
  await page.goto(`${BASE}${path}`);
  for (const width of widths) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    await page.screenshot({
      path: `${OUT}/${name}@${width}.jpg`,
      fullPage,
      type: 'jpeg',
      quality: 70
    });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await shoot('/', 'home-beheerpil', [1440, 390]);
await shoot('/admin', 'admin');
await shoot('/admin/overview', 'admin-overzicht-mobiel', [390, 320]);
await shoot('/admin', 'admin-volledig', [1920, 1440, 1280], true);
await shoot('/admin/network', 'admin-sectie-leeg', [1440, 390]);

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
await browser.close();
