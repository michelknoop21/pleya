/**
 * Opnamen van Transcode-sessies (S18.5, scherm 37) op de vaste breedtes 1920
 * bij 1080, 1440, 1280, 390 en 320, in de stijl van admin-users-shots.ts: per
 * breedte herladen, de horizontale paginaoverloop meten, een jpeg op kwaliteit
 * 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-transcode-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server: elke aanvraag naar `/pleya/v1`
 * wordt in de browser beantwoord met verzonnen gegevens (Michel, Sanne, Kids),
 * en elke aanvraag die iets zou veranderen wordt afgebroken en geteld. De
 * beelden dragen daarom `-nagebootst`.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s18-transcode';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (minutesAgo: number) => new Date(NOW - minutesAgo * 60_000).toISOString();

const USERS = [
  { id: 'u1', username: 'Michel', role: 'owner' },
  { id: 'u2', username: 'Sanne', role: 'member' },
  { id: 'u3', username: 'Kids', role: 'restricted' }
];

const sessionOf = (id: string, user: string, mode: string, hw: string | null, started: number) => ({
  id,
  user_id: user,
  version_id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77',
  mode,
  hw_accel: hw,
  started_at: iso(started),
  last_heartbeat_at: new Date(NOW - 3000).toISOString()
});

type Scenario = 'full' | 'room' | 'empty' | 'off';
let scenario: Scenario = 'full';

function transcodeList() {
  const hardware = scenario === 'empty'
    ? { accel: 'none', reason: 'geen render node gevonden' }
    : { accel: 'vaapi', reason: null };
  const all = [
    sessionOf('t-1', 'u2', 'transcode', 'vaapi', 8),
    sessionOf('t-2', 'u3', 'transcode', null, 3)
  ];
  if (scenario === 'full') return { max_sessions: 2, hardware, items: all };
  if (scenario === 'room') return { max_sessions: 4, hardware, items: all.slice(0, 1) };
  if (scenario === 'off') return { max_sessions: 0, hardware: { accel: 'none', reason: null }, items: [] };
  return { max_sessions: 2, hardware, items: [] };
}

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
        capabilities: { browse: true, search: true, artwork: true, watch_state: true, users: true, administration: true, transcode: scenario !== 'off' },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: iso(9000) });
    case '/libraries':
      return json(route, { items: [] });
    case '/transcode-sessions':
      return json(route, transcodeList());
    case '/users/me':
      return json(route, USERS[0]);
    case '/users':
      return json(route, { items: USERS });
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

const SCREEN = '/admin/media/transcode';

scenario = 'full';
await shoot(SCREEN, 'transcode-vol-nagebootst');
await shoot(SCREEN, 'transcode-stoppen-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.media.transcode.stopNamed', { name: 'Sanne' }) }).click();
  await p.waitForTimeout(300);
});
scenario = 'room';
await shoot(SCREEN, 'transcode-ruimte-nagebootst');
scenario = 'empty';
await shoot(SCREEN, 'transcode-leeg-nagebootst');
scenario = 'off';
await shoot(SCREEN, 'transcode-uit-nagebootst');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
