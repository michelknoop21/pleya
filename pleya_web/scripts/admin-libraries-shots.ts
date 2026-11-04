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
 *
 * Met `PLEYA_SHOTS_MOCK=1` praat dit script met geen enkele server: elke
 * aanvraag naar `/pleya/v1` wordt in de browser beantwoord met verzonnen
 * gegevens (alle opslagroots bezet, zoals op productie) en alleen de staten van
 * de nieuwe submap worden opgenomen, met `-nieuwe-map` in de bestandsnaam. De
 * `POST /libraries` van Opslaan krijgt daar een gemockte weigering
 * (`storage.root_not_offered`, reden `overlaps_library`).
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const USER = process.env['PLEYA_E2E_USER'] ?? '';
const PASS = process.env['PLEYA_E2E_PASS'] ?? '';
const OUT = process.argv[2] ?? '../docs/qa/s10-libraries';
const MOCK = process.env['PLEYA_SHOTS_MOCK'] === '1';
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

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const mkLibrary = (id: string, title: string) => ({
  id,
  title,
  kind: 'movies',
  item_count: 120,
  managed: 'db',
  scan_interval_seconds: null,
  scan_on_start: true
});
const MOCK_LIBRARIES = [mkLibrary('l1', 'Films'), mkLibrary('l2', 'Series'), mkLibrary('l3', 'Kids')];
const mkRoot = (path: string, owner: { id: string; title: string }) => ({
  path,
  fs_type: 'btrfs',
  inode_trusted: true,
  inode_trust_source: 'measured',
  mounted: true,
  free_bytes: 1_100_000_000_000,
  total_bytes: 2_000_000_000_000,
  libraries: [{ id: owner.id, title: owner.title }]
});
const MOCK_ROOTS = [
  mkRoot('/media/library/Films', MOCK_LIBRARIES[0]!),
  mkRoot('/media/library/Series', MOCK_LIBRARIES[1]!),
  mkRoot('/media/library/Kids', MOCK_LIBRARIES[2]!),
  mkRoot('/media/library2/Films', MOCK_LIBRARIES[0]!),
  mkRoot('/media/library2/Series', MOCK_LIBRARIES[1]!)
];

if (MOCK) {
  await context.route('**/pleya/v1/**', (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.slice('/pleya/v1'.length);
    if (request.method() === 'POST' && path === '/auth/login') {
      return json(route, { access_token: 'nep', refresh_token: 'nep', token_type: 'bearer', expires_in_ms: 3_600_000 });
    }
    if (request.method() === 'POST' && path === '/libraries') {
      return json(
        route,
        {
          error: {
            code: 'storage.root_not_offered',
            message: 'nagebootst',
            retryable: false,
            details: {
              reason: 'overlaps_library',
              root: '/media/library',
              with: '/media/library/Films',
              library: 'Films'
            }
          }
        },
        400
      );
    }
    if (request.method() !== 'GET') {
      blocked.push(`${request.method()} ${path}`);
      return route.abort();
    }
    switch (path) {
      case '/info':
        return json(route, {
          protocol: { major: 1, feature_level: 1, profile: 'full' },
          server: { id: 'srv', setup_accepts_name: false },
          capabilities: { browse: true, search: true, artwork: true, users: true, administration: true, sessions: true },
          auth: { methods: ['password'], setup_required: false }
        });
      case '/server':
        return json(route, { id: 'srv', name: 'Pleya-server', version: '0.9.0', started_at: new Date().toISOString() });
      case '/libraries':
        return json(route, { items: MOCK_LIBRARIES });
      case '/storage/roots':
        return json(route, { roots: MOCK_ROOTS });
      case '/scans':
        return json(route, { items: [], next_cursor: null });
      case '/users/me':
        return json(route, { id: 'u1', username: 'Michel', role: 'owner' });
      default:
        return json(route, { error: { code: 'auth.user_not_found', message: 'nagebootst', retryable: false } }, 404);
    }
  });
} else {
  // Vangnet: niets dat schrijft komt bij de server.
  await context.route('**/pleya/v1/**', (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() === 'GET' || path.includes('/pleya/v1/auth/')) return route.fallback();
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  });
}

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill(MOCK ? 'nagebootst' : USER);
await page.getByLabel(t('login.password'), { exact: true }).fill(MOCK ? 'nagebootst' : PASS);
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
    await measure(name, width, MOCK || (width >= 1280 && !prepare));
  }
}

const field = (p: Page) => p.getByRole('textbox', { name: t('admin.lib.new.label') });

if (MOCK) {
  // Alle roots bezet, zoals op productie: het veld is de enige weg.
  await shoot('/admin/libraries/new', 'bibliotheek-nieuwe-map-leeg');
  await shoot('/admin/libraries/new', 'bibliotheek-nieuwe-map-toegevoegd', WIDTHS, async (p) => {
    await p.getByRole('textbox', { name: t('admin.lib.form.name') }).fill('Documentaires');
    await field(p).fill('/media/library/Documentaires');
    await p.getByRole('button', { name: t('admin.lib.new.add') }).click();
    await p.waitForTimeout(200);
  });
  await shoot('/admin/libraries/new', 'bibliotheek-nieuwe-map-fout', WIDTHS, async (p) => {
    await field(p).fill('documentaires/nieuw');
    await p.getByRole('button', { name: t('admin.lib.new.add') }).click();
    await p.waitForTimeout(200);
  });
  await shoot('/admin/libraries/new', 'bibliotheek-nieuwe-map-geweigerd', WIDTHS, async (p) => {
    await p.getByRole('textbox', { name: t('admin.lib.form.name') }).fill('Documentaires');
    await field(p).fill('/media/library');
    await p.getByRole('button', { name: t('admin.lib.new.add') }).click();
    await p.getByRole('button', { name: t('admin.lib.form.create'), exact: true }).click();
    await p.getByRole('alert').first().waitFor();
    await p.waitForTimeout(300);
  });
} else {
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
}

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
