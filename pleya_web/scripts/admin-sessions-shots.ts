/**
 * Opnamen van Oude toestellen opruimen (DEC-164) op scherm 31 (beveiliging) en
 * 27 (één gebruiker), op de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en
 * 320, in de stijl van admin-users-shots.ts: per breedte herladen, de
 * horizontale paginaoverloop meten, een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-sessions-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server: elke aanvraag naar `/pleya/v1`
 * wordt in de browser beantwoord met verzonnen gegevens, en elke aanvraag die
 * iets zou veranderen wordt afgebroken en geteld. Daardoor eindigt het opruimen
 * in de opname altijd in de foutmelding: dat is de gedeeltelijke-mislukking-
 * toestand, en het bewijs dat er niets naar buiten ging. Inloggen gaat met een
 * nepantwoord; het script drukt af welke toestelnaam de client daarbij meestuurt.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/sessions-cleanup';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (daysAgo: number) => new Date(NOW - daysAgo * 86_400_000).toISOString();

const USERS = [
  { id: 'u1', username: 'Michel', role: 'owner' },
  { id: 'u2', username: 'Sanne', role: 'member' }
];
const session = (id: string, device: string, created: number, seen: number, extra: Record<string, unknown> = {}) => ({
  id,
  device_name: device,
  created_at: iso(created),
  last_seen_at: iso(seen),
  current: false,
  kind: 'device',
  ...extra
});
const SESSIONS: Record<string, unknown[]> = {
  u1: [
    session('s1', 'Safari op macOS', 3, 0, { current: true }),
    session('s2', 'Apple TV woonkamer', 80, 0.02),
    session('s3', 'Unknown device', 60, 52),
    session('s4', 'Unknown device', 58, 52),
    session('s5', 'Unknown device', 44, 41),
    session('s6', 'Firefox op Windows', 70, 64),
    session('s7', 'Home Assistant', 120, 90, { kind: 'api', scope: 'read', expires_at: iso(-200) })
  ],
  u2: [session('s8', 'iPhone van Sanne', 30, 0.1), session('s9', 'Unknown device', 100, 95)]
};

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const blocked: string[] = [];
const errors: string[] = [];
let loginDevice = '(niet meegestuurd)';

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
    const body = (request.postDataJSON() ?? {}) as Record<string, unknown>;
    loginDevice = `${String(body['device_name'] ?? '(geen naam)')}, id ${body['device_id'] ? 'meegestuurd' : 'niet meegestuurd'}`;
    return json(route, { access_token: 'nep', refresh_token: 'nep', token_type: 'bearer', expires_in_ms: 3_600_000 });
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
      return json(route, { id: 'srv', name: 'Pleya-server', version: '0.9.0', started_at: iso(6) });
    case '/libraries':
      return json(route, { items: [] });
    case '/users/me':
      return json(route, USERS[0]);
    case '/users':
      return json(route, { items: USERS });
    case '/sessions':
      return json(route, { items: SESSIONS[url.searchParams.get('user_id') ?? ''] ?? [] });
    case '/settings':
      return json(route, {
        server_name: { value: 'Pleya-server', source: 'env' },
        access_token_ttl: { value: '15m0s', source: 'env' },
        refresh_token_ttl: { value: '720h0m0s', source: 'env' },
        stream_token_ttl: { value: '5m0s', source: 'env' },
        stream_session_ttl: { value: '30m0s', source: 'env' },
        max_stream_sessions: { value: 8, source: 'env' },
        public_url: { value: '', source: 'env' },
        web_origin: { value: '', source: 'env' },
        cors_origins: { value: [], source: 'env' }
      });
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

async function shoot(path: string, name: string, prepare?: (p: Page) => Promise<void>): Promise<void> {
  await page.goto(`${BASE}${path}`);
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    if (prepare) await prepare(page);
    await measure(name, width, !prepare);
  }
}

const openCleanup = async (p: Page) => {
  await p.getByRole('button', { name: t('admin.devices.cleanup.open') }).click();
  await p.getByRole('dialog').waitFor();
  await p.waitForTimeout(300);
};

const runCleanup = async (p: Page) => {
  await openCleanup(p);
  await p.getByRole('dialog').getByRole('button', { name: /uitloggen$/ }).click();
  await p.getByRole('dialog').waitFor({ state: 'detached' });
  await p.waitForTimeout(500);
  await p.getByRole('button', { name: t('admin.devices.cleanup.retry') }).scrollIntoViewIfNeeded();
};

await shoot('/admin/security', 'beveiliging-toestellen-nagebootst');
await shoot('/admin/security', 'beveiliging-opruimen-nagebootst', openCleanup);
await shoot('/admin/security', 'beveiliging-opruimen-mislukt-nagebootst', runCleanup);
await shoot('/admin/users/u1', 'gebruiker-toestellen-nagebootst');
await shoot('/admin/users/u1', 'gebruiker-opruimen-nagebootst', openCleanup);

console.log(`toestel bij inloggen: ${loginDevice}`);
console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of [...new Set(blocked)]) console.log(`  ${b} (${blocked.filter((x) => x === b).length}x)`);
await browser.close();
