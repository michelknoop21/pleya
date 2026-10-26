/**
 * Opnamen van Onderhoud en back-ups (S25.6, scherm 35) op de vaste breedtes
 * 1920 bij 1080, 1440, 1280, 390 en 320, in de stijl van admin-users-shots.ts.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5183 bun run scripts/admin-backups-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server en gebruikt geen echte gegevens:
 * elke aanvraag naar `/pleya/v1` wordt in de browser beantwoord met verzonnen
 * back-ups. Elke schrijfaanvraag wordt afgebroken en geteld, op één na: de
 * restore krijgt van de mock een 202, zodat de wachtstaat getekend kan worden.
 * Dat gaat nooit naar een server: de mock is het enige dat antwoordt. De beelden
 * dragen daarom `-nagebootst`.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s25-backups';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);
const PATH = '/admin/diagnostics/maintenance';

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (hoursAgo: number) => new Date(NOW - hoursAgo * 3_600_000).toISOString();
const sentence = (started: string) =>
  `herstel ${started}: kijkstatus, gebruikers, sessies, instellingen en scans van daarna gaan verloren`;

function backup(id: string, hoursAgo: number, extra: Record<string, unknown> = {}) {
  const started = iso(hoursAgo);
  const status = (extra['status'] as string | undefined) ?? 'ok';
  return {
    id,
    status,
    trigger: 'schedule',
    started_at: started,
    finished_at: status === 'running' ? null : iso(hoursAgo - 0.03),
    size_bytes: status === 'running' ? null : 412_000_000,
    schema_version: 22,
    titles: 576,
    secrets_included: true,
    failure_code: null,
    restore_confirmation: status === 'ok' ? sentence(started) : null,
    last_restore_test: null,
    ...extra
  };
}
const test = (hoursAgo: number, extra: Record<string, unknown> = {}) => ({
  id: 't1',
  status: 'ok',
  started_at: iso(hoursAgo),
  finished_at: iso(hoursAgo - 0.03),
  schema_from: 22,
  schema_to: 22,
  titles_expected: 576,
  titles_found: 576,
  failure_code: null,
  ...extra
});

const ITEMS = [
  backup('b4', 10, { last_restore_test: test(9.9) }),
  backup('b3', 34, { size_bytes: 411_000_000, last_restore_test: test(33) }),
  backup('b2', 24 * 12, { size_bytes: 409_000_000 }),
  backup('b1', 24 * 50, { trigger: 'upgrade', schema_version: 7, secrets_included: false, size_bytes: 380_000_000 })
];
const LIST = {
  items: ITEMS,
  dir: '/backups',
  schedule: '03:30',
  retention_days: 14,
  same_failure_domain: true,
  secrets_key_configured: false
};
const HEALTHY = { ...LIST, same_failure_domain: false, secrets_key_configured: true };

let current: unknown = LIST;
let maintenanceLeft = 0;

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
  const method = request.method();
  if (method === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', expires_in_ms: 3_600_000 });
  }
  if (method === 'POST' && /^\/backups\/[^/]+\/restore$/.test(path)) {
    blocked.push(`${method} ${path} (door de mock beantwoord met 202)`);
    maintenanceLeft = 1_000_000;
    return json(route, ITEMS[0], 202);
  }
  if (method !== 'GET') {
    blocked.push(`${method} ${path}`);
    return route.abort();
  }
  if (path === '/backups' && maintenanceLeft > 0) {
    maintenanceLeft -= 1;
    return json(route, { error: { code: 'server.maintenance', message: 'nagebootst', retryable: true } }, 503);
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 's1', setup_accepts_name: false },
        capabilities: {
          browse: true, search: true, artwork: true, watch_state: true, users: true, administration: true, backups: true
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: iso(200) });
    case '/libraries':
      return json(route, { items: [] });
    case '/users/me':
      return json(route, { id: 'u1', username: 'Michel', role: 'owner' });
    case '/backups':
      return json(route, current);
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
  name: string,
  data: unknown,
  prepare?: (p: Page) => Promise<void>
): Promise<void> {
  current = data;
  for (const width of WIDTHS) {
    maintenanceLeft = 0;
    await page.setViewportSize({ width, height: height(width) });
    await page.goto(`${BASE}${PATH}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(600);
    if (prepare) await prepare(page);
    await measure(name, width, !prepare);
  }
}

const rowOf = (p: Page, id: string) => p.locator(`tr[data-backup="${id}"]`);
const restoreOf = (p: Page, id: string) =>
  rowOf(p, id).getByRole('button', { name: /terugzetten/i });

await shoot('onderhoud-waarschuwingen-nagebootst', LIST);
await shoot('onderhoud-gezond-nagebootst', HEALTHY);
await shoot('onderhoud-leeg-nagebootst', { ...HEALTHY, items: [] });
await shoot(
  'onderhoud-back-up-loopt-nagebootst',
  { ...HEALTHY, items: [backup('b5', 0.02, { status: 'running', schema_version: null, titles: null, size_bytes: null }), ...ITEMS.slice(0, 2)] }
);
await shoot(
  'onderhoud-laatste-mislukt-nagebootst',
  { ...HEALTHY, items: [backup('b6', 1, { status: 'failed', failure_code: 'storage.full', size_bytes: null }), ...ITEMS.slice(0, 2)] }
);
await shoot('onderhoud-terugzetten-dialoog-nagebootst', HEALTHY, async (p) => {
  await restoreOf(p, 'b3').click();
  await p.waitForTimeout(300);
});
await shoot('onderhoud-terugzetten-zin-fout-nagebootst', HEALTHY, async (p) => {
  await restoreOf(p, 'b3').click();
  await p.getByRole('dialog').getByRole('textbox').fill('herstel');
  await p.waitForTimeout(300);
});
await shoot('onderhoud-terugzetten-wacht-nagebootst', HEALTHY, async (p) => {
  await restoreOf(p, 'b3').click();
  const dialog = p.getByRole('dialog');
  await dialog.getByRole('textbox').fill(ITEMS[1]!.restore_confirmation as string);
  await dialog.getByRole('button', { name: t('admin.bak.restore.confirm') }).click();
  await p.waitForTimeout(600);
});
await shoot('onderhoud-hersteltest-afgebroken-nagebootst', HEALTHY, async (p) => {
  await rowOf(p, 'b3').getByRole('button', { name: /Hersteltest/ }).click();
  await p.waitForTimeout(400);
});

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`schrijfaanvragen (afgebroken, of door de mock beantwoord): ${blocked.length}`);
for (const b of new Set(blocked)) console.log(`  ${b}`);
await browser.close();
