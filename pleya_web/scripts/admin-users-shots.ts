/**
 * Opnamen van gebruikersbeheer (S10.4, schermen 26 en 27) op de vaste
 * breedtes 1920 bij 1080, 1440, 1280, 390 en 320, in de stijl van
 * admin-libraries-shots.ts: per breedte herladen, de horizontale
 * paginaoverloop meten, een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-users-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server en gebruikt geen echte
 * gebruikers: elke aanvraag naar `/pleya/v1` wordt in de browser beantwoord met
 * verzonnen gegevens (Michel, Sanne, Kids, Daan en twee bibliotheken), en elke
 * aanvraag die iets zou veranderen wordt afgebroken en geteld. De beelden
 * dragen daarom `-nagebootst`. Inloggen gaat met een nepantwoord van de mock.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s10-users';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (minutesAgo: number) => new Date(NOW - minutesAgo * 60_000).toISOString();

const USERS = [
  { id: 'u1', username: 'Michel', role: 'owner' },
  { id: 'u2', username: 'Sanne', role: 'member' },
  { id: 'u3', username: 'Kids', role: 'restricted' },
  { id: 'u4', username: 'Daan', role: 'admin' }
];
const LIBRARIES = [
  { id: 'l1', title: 'Films', kind: 'movies', item_count: 461, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'l2', title: 'Series', kind: 'shows', item_count: 97, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'l3', title: 'Kids', kind: 'movies', item_count: 5, managed: 'db', scan_interval_seconds: null, scan_on_start: true }
];
const session = (id: string, device: string, created: number, seen: number, current = false) => ({
  id,
  device_name: device,
  created_at: iso(created),
  last_seen_at: iso(seen),
  current,
  kind: 'device'
});
const SESSIONS: Record<string, unknown[]> = {
  u1: [session('s1', 'Apple TV woonkamer', 60 * 24 * 60, 1), session('s2', 'MacBook', 60 * 24 * 50, 120), session('s3', 'iPad', 60 * 24 * 20, 600, true)],
  u2: [session('s4', 'iPhone van Sanne', 60 * 24 * 60, 38), session('s5', 'Firefox op Windows', 60 * 24 * 53, 60 * 24 * 12)],
  u3: [session('s6', 'Apple TV kinderkamer', 60 * 24 * 40, 60 * 20)],
  u4: []
};

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const blocked: string[] = [];
const errors: string[] = [];

const browser = await chromium.launch();
const context = await browser.newContext({
  ...localeContextOptions('nl'),
  viewport: { width: 1440, height: 900 }
});
const page = await context.newPage();
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  if (request.method() === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', expires_in_ms: 3_600_000 });
  }
  if (request.method() !== 'GET') {
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 's1', setup_accepts_name: false },
        capabilities: { browse: true, search: true, artwork: true, watch_state: true, users: true, administration: true },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: iso(9000) });
    case '/libraries':
      return json(route, { items: LIBRARIES });
    case '/users/me':
      return json(route, USERS[0]);
    case '/users':
      return json(route, { items: USERS });
    case '/sessions':
      return json(route, { items: SESSIONS[url.searchParams.get('user_id') ?? ''] ?? [] });
    default:
      return json(route, { error: { code: 'auth.user_not_found', message: 'nagebootst', retryable: false } }, 404);
  }
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill('nagebootst');
await page.getByLabel(t('login.password'), { exact: true }).fill('nagebootst');
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function measure(name: string, width: number, fullPage: boolean): Promise<void> {
  const over = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage, type: 'jpeg', quality: 70 });
  console.log(`${name}@${width}: overloop ${over}px`);
}

async function shoot(
  path: string,
  name: string,
  prepare?: (p: Page) => Promise<void>
): Promise<void> {
  await page.goto(`${BASE}${path}`);
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    if (prepare) await prepare(page);
    await measure(name, width, !prepare);
  }
}

const tick = (p: Page, library: string, rung: string) =>
  p.getByRole('checkbox', { name: `${library}, ${rung}` }).check();

await shoot('/admin/users', 'gebruikers-nagebootst');
await shoot('/admin/users/u2', 'gebruiker-nagebootst');
await shoot('/admin/users/u2', 'gebruiker-rechten-opslaan-nagebootst', async (p) => {
  await tick(p, 'Films', t('admin.users.perm.download'));
  await tick(p, 'Series', t('admin.users.perm.view'));
  await p.getByRole('button', { name: t('admin.users.action.save') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/users/u4', 'gebruiker-degraderen-nagebootst', async (p) => {
  await p.getByRole('radio', { name: t('admin.users.role.member') }).check({ force: true });
  await p.getByRole('button', { name: t('admin.users.action.save') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/users/u2', 'gebruiker-verwijderen-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.users.delete.open') }).click();
  await p.getByRole('dialog').getByRole('textbox').fill('San');
  await p.waitForTimeout(300);
});
await shoot('/admin/users/u2', 'gebruiker-wachtwoord-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.users.account.reset') }).click();
  await p.getByLabel(t('admin.users.account.newPassword'), { exact: false }).fill('kort');
  await p.getByRole('button', { name: t('admin.users.account.setPassword') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/users/u1', 'gebruiker-eigenaar-nagebootst');
await shoot('/admin/users/u3', 'gebruiker-beperkt-nagebootst');
await shoot('/admin/users/new', 'gebruiker-toevoegen-nagebootst');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
