/**
 * Opnamen van de schermen 17 en 18 (S19) op de vaste breedtes 1920 bij 1080, 1440,
 * 1280, 390 en 320, tegen een echte server met posters: elke breedte een verse
 * lading, de horizontale overloop gemeten, een png.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/lists-shots.ts [uitvoermap]
 *
 * Gebruikt PLEYA_E2E_USER en PLEYA_E2E_PASS, en vult niets: de lijsten moeten er
 * al staan. Het script leest ze via de API en opent de eerste verzameling en de
 * eerste afspeellijst.
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync } from 'node:fs';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const USER = process.env['PLEYA_E2E_USER'] ?? 'e2e';
const PASS = process.env['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';
const OUT = process.argv[2] ?? '../.build/pleya-completion-evidence/s19';
const LOCALE = process.argv[3] ?? 'nl-NL';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

mkdirSync(OUT, { recursive: true });

async function signIn(page: Page): Promise<void> {
  await page.goto(`${BASE}/login`);
  await page.locator('input').first().fill(USER);
  await page.locator('input[type="password"]').fill(PASS);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

async function shoot(page: Page, name: string, path: string, act?: (page: Page) => Promise<void>): Promise<void> {
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.goto(`${BASE}${path}`);
    await page.waitForLoadState('load');
    await page.locator('[aria-busy="true"]').first().waitFor({ state: 'detached', timeout: 15_000 }).catch(() => undefined);
    await page.waitForTimeout(700);
    await act?.(page);
    await page.waitForTimeout(250);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await page.screenshot({ path: `${OUT}/${name}@${width}.png`, fullPage: false });
    console.log(`${name}@${width}: overloop ${overflow}`);
  }
}

const browser = await chromium.launch();
const context = await browser.newContext({ locale: LOCALE, colorScheme: 'dark' });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('paginafout:', error.message));
await signIn(page);

const login = await context.request.post(`${BASE}/pleya/v1/auth/login`, { data: { username: USER, password: PASS } });
const headers = { Authorization: `Bearer ${((await login.json()) as { access_token: string }).access_token}` };
const read = async (resource: string) => (await (await context.request.get(`${BASE}/pleya/v1/${resource}`, { headers })).json()) as { items: { id: string }[] };
const collections = process.env['PLEYA_SHOT_COLLECTION'] ?? (await read('collections')).items[0]?.id;
const playlist = process.env['PLEYA_SHOT_PLAYLIST'] ?? (await read('playlists')).items[0]?.id;

await shoot(page, '17-verzamelingen', '/server/collections');
await shoot(page, '17-afspeellijsten', '/server/playlists');
await shoot(page, '17-verzameling', `/server/collections/${collections}`);
await shoot(page, '18-afspeellijst', `/server/playlists/${playlist}`);
await shoot(page, '18-herordenen', `/server/playlists/${playlist}`, async (p) => {
  await p.locator('.ph__actions button.btn--secondary').first().click();
});
await shoot(page, '18-menu', `/server/playlists/${playlist}`, async (p) => {
  await p.locator('.row button.more').first().click();
});
await shoot(page, '08-kaartmenu', '/films', async (p) => {
  await p.locator('.card__add').first().click({ force: true });
});
await shoot(page, '17-nieuw', '/server/collections', async (p) => {
  await p.locator('.ph__actions button.btn').first().click();
});
await shoot(page, '18-onbekend', '/server/playlists/00000000-0000-7000-8000-000000000000');
await browser.close();
