/**
 * Opnamen van elke route en staat naast de northstar (S7.6).
 *
 *   eval "$(scripts/e2e-stack.sh up)"
 *   bun run scripts/routes-shots.ts [uitvoermap] [--locale nl|en]
 *
 * Twee soorten beelden. Op de vaste breedtes van de werkafspraak (1920 bij 1080,
 * 1440, 1280, 390 en 320) één scherm per route en staat, met een meting van de
 * horizontale paginaoverloop. Op de breedtes waarop de northstar een beeld
 * heeft een vergelijking `*-vs-northstar@{w}.jpg`: links de app, rechts het
 * goedgekeurde beeld, allebei als hele pagina vanaf 900 en als één scherm
 * daaronder (DESIGN.md hoofdstuk 3, "Screenshot").
 *
 * De staten zonder eigen route worden met `page.route` neergezet: inloggen met
 * een fout wachtwoord (12), een lege bibliotheek (13), een server die niet
 * antwoordt (14) en Home met een vastgehouden hub-aanvraag (15).
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { compare } from './shot-compare';
import { forgetStoredLocale, localeContextOptions, parseLocaleFlag } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';
const USER = process.env['PLEYA_E2E_USER'] ?? 'e2e';
const PASS = process.env['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';
const { locale: FLAG, rest: ARGS } = parseLocaleFlag(process.argv.slice(2));
const LOCALE = FLAG ?? 'nl';
const OUT = ARGS[0] ?? '../docs/qa/s7-routes';

const HOUSE = [1920, 1440, 1280, 390, 320];
const CMP = { label: `pleya_web (${LOCALE})`, type: 'jpeg' } as const;
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale(LOCALE);
mkdirSync(OUT, { recursive: true });

type Screen = {
  name: string;
  path: string;
  /** Northstar-beeld per breedte; zonder regel geen vergelijking. */
  northstar?: Record<number, string>;
  /** Zet de staat neer vóór de navigatie; geeft een opruimfunctie terug. */
  arrange?: (page: Page) => Promise<() => Promise<void>>;
  signedOut?: boolean;
};

const ns = (n: string, widths: number[]) =>
  Object.fromEntries(widths.map((w) => [w, `${n}@${w}.jpg`]));

const browser = await chromium.launch();
const context = await browser.newContext(localeContextOptions(LOCALE));
await forgetStoredLocale(context);
await context.addInitScript(() => localStorage.setItem('pleya.theme', 'dark'));
const page = await context.newPage();

async function signIn(): Promise<void> {
  await page.goto(`${BASE}/login`);
  await page.getByLabel(t('login.username')).fill(USER);
  await page.getByLabel(t('login.password'), { exact: true }).fill(PASS);
  await page.getByRole('button', { name: t('login.submit') }).click();
  await page.getByRole('navigation', { name: t('nav.primary') }).waitFor({ timeout: 20_000 });
}

/** Opent een pad met een sessie; een geroteerd refreshtoken betekent opnieuw inloggen. */
async function open(path: string, shell = true): Promise<void> {
  await page.goto(`${BASE}${path}`);
  if (shell && page.url().includes('/login')) {
    await signIn();
    await page.goto(`${BASE}${path}`);
  }
}

async function settle(): Promise<void> {
  await page
    .locator('[aria-busy="true"]')
    .first()
    .waitFor({ state: 'detached', timeout: 15_000 })
    .catch(() => undefined);
  await page.waitForTimeout(600);
}

async function overflow(label: string): Promise<void> {
  const over = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  console.log(`overloop ${label}: ${over}px${over > 1 ? '  <-- LOOPT OVER' : ''}`);
}

async function shoot(screen: Screen, width: number, file: string, full: boolean): Promise<void> {
  await page.setViewportSize({ width, height: height(width) });
  await page.waitForTimeout(300);
  await overflow(`${screen.name}@${width}`);
  await page.screenshot({ path: file, fullPage: full, type: 'jpeg', quality: 70 });
  console.log(file);
}

// Het eerste item van elke soort, tijdens de run opgezocht.
await signIn();
await open('/server');
await page.locator('[data-library-kind]').first().waitFor();
const libs = await page
  .locator('[data-library-kind]')
  .evaluateAll((els) => els.map((e) => [e.getAttribute('data-library-kind'), e.getAttribute('data-library-id')]));
const movies = libs.find(([k]) => k === 'movies')?.[1];
const shows = libs.find(([k]) => k === 'shows')?.[1];

async function firstHref(path: string): Promise<string | null> {
  await open(path);
  const link = page.getByRole('main').getByRole('list').last().getByRole('link').first();
  await link.waitFor({ timeout: 15_000 }).catch(() => undefined);
  return (await link.count()) ? link.getAttribute('href') : null;
}
const film = movies ? await firstHref(`/libraries/${movies}`) : null;
const show = shows ? await firstHref(`/libraries/${shows}`) : null;

const holdHubs = async (p: Page) => {
  let release: () => void = () => undefined;
  const held = new Promise<void>((r) => (release = r));
  const handler = async (route: Route) => {
    await held;
    await route.continue().catch(() => undefined);
  };
  await p.route('**/pleya/v1/hubs/**', handler);
  return async () => {
    release();
    await p.unroute('**/pleya/v1/hubs/**', handler);
  };
};

const emptyLibrary = async (p: Page) => {
  const handler = async (route: Route) => {
    const res = await route.fetch();
    const body = (await res.json()) as Record<string, unknown>;
    await route.fulfill({ response: res, json: { ...body, items: [], next_cursor: null, total_estimate: 0 } });
  };
  await p.route('**/pleya/v1/libraries/*/items*', handler);
  return () => p.unroute('**/pleya/v1/libraries/*/items*', handler);
};

const unreachable = async (p: Page) => {
  const handler = (route: Route) => route.abort('connectionrefused');
  await p.route('**/pleya/v1/info', handler);
  return () => p.unroute('**/pleya/v1/info', handler);
};

const screens: Screen[] = [
  { name: '01-home', path: '/', northstar: ns('01-home', [393, 1024, 1280, 1600]) },
  { name: '15-skeleton', path: '/', arrange: holdHubs, northstar: ns('15-skeleton', [393, 1600]) },
  { name: '14-server-offline', path: '/', arrange: unreachable, northstar: ns('14-server-offline', [393, 1600]) },
  { name: 'bibliotheken', path: '/libraries' },
  ...(movies
    ? [{ name: '05-alle-films', path: `/libraries/${movies}`, northstar: ns('05-alle-films', [393, 1600]) }]
    : []),
  ...(movies
    ? [{ name: '13-lege-bibliotheek', path: `/libraries/${movies}`, arrange: emptyLibrary, northstar: ns('13-lege-bibliotheek', [393, 1600]) }]
    : []),
  ...(film ? [{ name: '08-film-detail', path: film, northstar: ns('08-film-detail', [393, 1024, 1600]) }] : []),
  ...(show ? [{ name: '09-serie-detail', path: show, northstar: ns('09-serie-detail', [393, 1600]) }] : []),
  { name: '06-zoeken', path: '/search?q=e', northstar: ns('06-zoeken', [393, 1600]) },
  { name: '07-zoeken-leeg', path: '/search?q=zqxjvw', northstar: ns('07-zoeken-leeg', [393, 1600]) },
  { name: '11-mijn-pleya', path: '/server', northstar: ns('11-mijn-pleya', [393, 1600]) }
];

async function render(screen: Screen): Promise<void> {
  const cleanup = screen.arrange ? await screen.arrange(page) : null;
  await page.setViewportSize({ width: 1280, height: 900 });
  await open(screen.path);
  if (screen.arrange === unreachable) {
    await page.getByRole('button', { name: t('unreachable.retryNow') }).waitFor({ timeout: 20_000 });
  } else if (screen.arrange === holdHubs) {
    await page.locator('[aria-busy="true"]').first().waitFor();
  } else {
    await settle();
  }

  for (const width of HOUSE) {
    await shoot(screen, width, `${OUT}/${screen.name}@${width}-${LOCALE}.jpg`, false);
  }
  for (const [w, file] of Object.entries(screen.northstar ?? {})) {
    const width = Number(w);
    const mine = `${OUT}/${screen.name}@${width}-${LOCALE}-app.jpg`;
    await shoot(screen, width, mine, width >= 900);
    console.log(await compare(context, `${OUT}/${screen.name}`, mine, file, width, CMP));
  }
  if (cleanup) await cleanup();
}

for (const screen of screens) await render(screen);

// Inloggen in de foutstaat (12), in een context zonder sessie.
const signedOut = await browser.newContext(localeContextOptions(LOCALE));
await forgetStoredLocale(signedOut);
await signedOut.addInitScript(() => localStorage.setItem('pleya.theme', 'dark'));
const login = await signedOut.newPage();
await login.goto(`${BASE}/login`);
await login.getByLabel(t('login.username')).fill(`shots-fout-${LOCALE}`);
await login.getByLabel(t('login.password'), { exact: true }).fill('dit-is-niet-het-wachtwoord');
await login.getByRole('button', { name: t('login.submit') }).click();
await login.locator('[aria-invalid="true"]').first().waitFor();
for (const width of [...HOUSE, 393, 1600]) {
  await login.setViewportSize({ width, height: height(width) });
  await login.waitForTimeout(300);
  const over = await login.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  console.log(`overloop 12-inloggen@${width}: ${over}px${over > 1 ? '  <-- LOOPT OVER' : ''}`);
  const nsWidth = width === 393 || width === 1600;
  const file = `${OUT}/12-inloggen@${width}-${LOCALE}${nsWidth ? '-app' : ''}.jpg`;
  await login.screenshot({ path: file, fullPage: width >= 900, type: 'jpeg', quality: 70 });
  console.log(file);
  if (nsWidth) {
    console.log(await compare(signedOut, `${OUT}/12-inloggen`, file, `12-inloggen@${width}.jpg`, width, CMP));
  }
}

await browser.close();
