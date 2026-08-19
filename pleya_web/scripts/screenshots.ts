/**
 * Schermafbeeldingen op de vijf breedtes uit de responsive-strategie, in de
 * drie themamodi. Bedoeld als bewijs bij een review, niet als test: een
 * afwijking die een mens ziet en een assertie niet is precies waar dit voor is.
 *
 *   eval "$(scripts/e2e-stack.sh up)"
 *   bun run scripts/screenshots.ts [uitvoermap]
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync } from 'node:fs';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';
const SETUP_CODE = process.env['PLEYA_E2E_SETUP_CODE'] ?? '';
const OUT = process.argv[2] ?? '/tmp/pleya-shots';

const WIDTHS = [390, 768, 1024, 1280, 1600];
const THEMES = ['oled', 'dark', 'light'] as const;

mkdirSync(OUT, { recursive: true });

async function signIn(page: Page): Promise<void> {
  await page.goto(BASE);
  const info = await page.request.get(`${BASE}/pleya/v1/info`);
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    await page.getByLabel('Setup code').fill(SETUP_CODE);
    await page.getByLabel('Username').fill('e2e');
    await page.getByLabel('Password', { exact: false }).fill('een-lang-genoeg-wachtwoord');
    await page.getByRole('button', { name: 'Create owner' }).click();
  } else {
    await page.waitForURL('**/login');
    await page.getByLabel('Username').fill('e2e');
    await page.getByLabel('Password').fill('een-lang-genoeg-wachtwoord');
    await page.getByRole('button', { name: 'Sign in' }).click();
  }
  await page.getByRole('navigation', { name: 'Primary' }).waitFor();
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
await signIn(page);

// Het grootste raster opzoeken voor de bibliotheek- en detailopnamen.
await page.goto(`${BASE}/libraries`);
await page.locator('main a[href^="/libraries/"]').first().waitFor();
const hrefs = await page
  .locator('main a[href^="/libraries/"]')
  .evaluateAll((els) => els.map((el) => el.getAttribute('href') ?? ''));
const bigLibrary = hrefs.at(-1) ?? hrefs[0] ?? '/libraries';

await page.goto(`${BASE}${bigLibrary}`);
await page.getByRole('main').getByRole('list').last().getByRole('listitem').first().waitFor();
const firstItem = await page
  .getByRole('main')
  .getByRole('list')
  .last()
  .getByRole('listitem')
  .first()
  .getByRole('link')
  .getAttribute('href');

const screens: { name: string; path: string }[] = [
  { name: 'home', path: '/' },
  { name: 'libraries', path: '/libraries' },
  { name: 'library-grid', path: bigLibrary },
  { name: 'item', path: firstItem ?? '/' },
  { name: 'search', path: '/search?q=e' },
  { name: 'server', path: '/server' }
];

for (const theme of THEMES) {
  await page.goto(`${BASE}/`);
  if (page.url().includes('/login')) await signIn(page);
  await page.evaluate((t) => localStorage.setItem('pleya.theme', t), theme);

  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    for (const screen of screens) {
      await page.goto(`${BASE}${screen.path}`);
      // Wachten tot de schil er is; elke goto herlaadt de SPA, en die haalt
      // eerst een vers tokenpaar op voordat er iets te zien valt.
      //
      // Belandt hij op /login, dan is het refreshtoken onderweg geroteerd
      // terwijl dit script alweer wegnavigeerde. Dat gebeurt alleen bij deze
      // reeks herlaadbeurten achter elkaar; opnieuw inloggen en doorgaan.
      if (page.url().includes('/login')) {
        await signIn(page);
        await page.goto(`${BASE}${screen.path}`);
      }
      await page.getByRole('navigation', { name: 'Primary' }).waitFor({ timeout: 15_000 });
      await page.waitForLoadState('networkidle').catch(() => {});
      await page.waitForTimeout(700);
      const file = `${OUT}/${theme}-${width}-${screen.name}.png`;
      await page.screenshot({ path: file, fullPage: false });
      console.log(file);
    }
  }
}

await browser.close();
