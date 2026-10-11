/**
 * Schermafbeeldingen op de vijf breedtes uit de responsive-strategie, in de
 * drie themamodi. Bedoeld als bewijs bij een review, niet als test: een
 * afwijking die een mens ziet en een assertie niet is precies waar dit voor is.
 *
 *   eval "$(scripts/e2e-stack.sh up)"
 *   bun run scripts/screenshots.ts [uitvoermap] [--locale nl|en]
 *
 * Met `--locale` wordt het de taalronde (S7.5): alleen dark, Home, een
 * bibliotheek en /server, plus /setup en /login zonder sessie. Op 393, 1024 en
 * 1600 een opname met de taal in de naam, op alle vijf breedtes een meting van
 * horizontale paginaoverloop. /setup bestaat alleen zolang de server nog geen
 * eigenaar heeft, dus de eerste taalronde op een verse stack neemt hem mee.
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { forgetStoredLocale, localeContextOptions, parseLocaleFlag } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';
const SETUP_CODE = process.env['PLEYA_E2E_SETUP_CODE'] ?? '';
const { locale: LOCALE, rest: ARGS } = parseLocaleFlag(process.argv.slice(2));
const OUT = ARGS[0] ?? '/tmp/pleya-shots';

const WIDTHS = LOCALE ? [393, 768, 1024, 1280, 1600] : [390, 768, 1024, 1280, 1600];
const SHOT_WIDTHS = LOCALE ? [393, 1024, 1600] : WIDTHS;
const THEMES = LOCALE ? (['dark'] as const) : (['oled', 'dark', 'light'] as const);
const tag = LOCALE ? `-${LOCALE}` : '';

// De labels waarop het script zoekt komen uit dezelfde catalogus als de app,
// in de taal van de ronde; zonder vlag Engels, zoals de e2e-suite.
setLocale(LOCALE ?? 'en');

mkdirSync(OUT, { recursive: true });

/** Loopt de pagina horizontaal over? Rails schuiven in hun eigen container. */
async function measureOverflow(page: Page, label: string): Promise<void> {
  const over = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  console.log(`overloop ${label}: ${over}px${over > 0 ? '  <-- LOOPT OVER' : ''}`);
}

async function signIn(page: Page): Promise<void> {
  await page.goto(BASE);
  const info = await page.request.get(`${BASE}/pleya/v1/info`);
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    if (LOCALE) await shootAuth(page, 'setup');
    await page.getByLabel(t('setup.code')).fill(SETUP_CODE);
    await page.getByLabel(t('setup.username')).fill('e2e');
    await page.getByLabel(t('setup.password'), { exact: false }).fill('een-lang-genoeg-wachtwoord');
    await page.getByRole('button', { name: t('setup.submit') }).click();
  } else {
    await page.waitForURL('**/login');
    await page.getByLabel(t('login.username')).fill('e2e');
    await page.getByLabel(t('login.password')).fill('een-lang-genoeg-wachtwoord');
    await page.getByRole('button', { name: t('login.submit') }).click();
  }
  await page.getByRole('navigation', { name: t('nav.primary') }).waitFor();
}

/** /setup of /login op elke breedte, zonder sessie en zonder herladen. */
async function shootAuth(page: Page, name: 'setup' | 'login'): Promise<void> {
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    await page.locator('h1').waitFor();
    await page.waitForTimeout(300);
    await measureOverflow(page, `dark-${width}-${name}${tag}`);
    if (!SHOT_WIDTHS.includes(width)) continue;
    const file = `${OUT}/dark-${width}-${name}${tag}.png`;
    await page.screenshot({ path: file });
    console.log(file);
  }
  await page.setViewportSize({ width: 1280, height: 900 });
}

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1280, height: 900 },
  ...localeContextOptions(LOCALE)
});
if (LOCALE) {
  await forgetStoredLocale(context);
  // De taalronde is alleen dark, ook op /setup vóór de eerste themakeuze.
  await context.addInitScript(() => localStorage.setItem('pleya.theme', 'dark'));
}
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

const allScreens: { name: string; path: string }[] = [
  { name: 'home', path: '/' },
  { name: 'libraries', path: '/libraries' },
  { name: 'library-grid', path: bigLibrary },
  { name: 'item', path: firstItem ?? '/' },
  { name: 'search', path: '/search?q=e' },
  { name: 'server', path: '/server' }
];
const LOCALE_SCREENS = ['home', 'library-grid', 'server'];
const screens = LOCALE ? allScreens.filter((s) => LOCALE_SCREENS.includes(s.name)) : allScreens;

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
      await page.getByRole('navigation', { name: t('nav.primary') }).waitFor({ timeout: 15_000 });
      await page.waitForLoadState('networkidle').catch(() => {});
      await page.waitForTimeout(700);
      if (LOCALE) await measureOverflow(page, `${theme}-${width}-${screen.name}${tag}`);
      if (!SHOT_WIDTHS.includes(width)) continue;
      const file = `${OUT}/${theme}-${width}-${screen.name}${tag}.png`;
      await page.screenshot({ path: file, fullPage: false });
      console.log(file);
    }
  }
}

// Inloggen zonder sessie: een verse context, dus geen refreshtoken.
if (LOCALE) {
  const signedOut = await browser.newContext(localeContextOptions(LOCALE));
  await forgetStoredLocale(signedOut);
  await signedOut.addInitScript(() => localStorage.setItem('pleya.theme', 'dark'));
  const loginPage = await signedOut.newPage();
  await loginPage.goto(`${BASE}/login`);
  await shootAuth(loginPage, 'login');
  await signedOut.close();
}

await browser.close();
