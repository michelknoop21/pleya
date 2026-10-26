/**
 * Opnamen van de instellingenschermen (S10.5, schermen 28 tot 32) op de vaste
 * breedtes 1920 bij 1080, 1440, 1280, 390 en 320, in de stijl van
 * admin-users-shots.ts: per breedte herladen, de horizontale paginaoverloop
 * meten, een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-settings-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server: elke aanvraag naar `/pleya/v1`
 * wordt in de browser beantwoord met verzonnen gegevens, en elke aanvraag die
 * iets zou veranderen wordt afgebroken en geteld. De beelden dragen daarom
 * `-nagebootst`. De omgeving bevat bewust een regel met een geheim om te laten
 * zien dat het scherm hem maskeert; het is een verzonnen waarde.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s10-settings';
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
const LIBRARIES = [
  { id: 'l1', title: 'Films', kind: 'movies', item_count: 461, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'l2', title: 'Series', kind: 'shows', item_count: 97, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'l3', title: 'Kids', kind: 'movies', item_count: 5, managed: 'db', scan_interval_seconds: null, scan_on_start: true }
];
const COVERAGE: Record<string, unknown> = {
  l1: { items: 461, with_sidecar: 420, with_summary: 418, with_genres: 411, ratio: 411 / 461, threshold: 0.8, gate_met: true },
  l2: { items: 97, with_sidecar: 82, with_summary: 80, with_genres: 79, ratio: 79 / 97, threshold: 0.8, gate_met: true },
  l3: { items: 5, with_sidecar: 2, with_summary: 2, with_genres: 2, ratio: 0.4, threshold: 0.8, gate_met: false }
};
const device = (id: string, name: string, seen: number, current = false) => ({
  id,
  device_name: name,
  created_at: iso(60 * 24 * 30),
  last_seen_at: iso(seen),
  current,
  kind: 'device'
});
const SESSIONS: Record<string, unknown[]> = {
  u1: [device('s1', 'Apple TV woonkamer', 1), device('s2', 'Deze browser', 0, true), device('s3', 'iPhone van Michel', 38)],
  u2: [device('s4', 'iPhone van Sanne', 40)],
  u3: [device('s5', 'Apple TV kinderkamer', 60 * 20)]
};
const SETTINGS = {
  server_name: { value: 'Pleya-server', source: 'env' },
  access_token_ttl: { value: '15m0s', source: 'env' },
  refresh_token_ttl: { value: '720h0m0s', source: 'db' },
  stream_token_ttl: { value: '5m0s', source: 'env' },
  stream_session_ttl: { value: '30m0s', source: 'env' },
  max_stream_sessions: { value: 8, source: 'env' },
  public_url: { value: 'https://web.pleya.app', source: 'env' },
  web_origin: { value: '', source: 'env' },
  cors_origins: { value: [], source: 'env' }
};
const ENVIRONMENT = [
  { key: 'DATABASE_URL', value: 'postgres://pleya:•••@db:5432/pleya', redacted: true },
  { key: 'PLEYA_SERVER_CACHE_DIR', value: '/cache', redacted: false },
  { key: 'PLEYA_SERVER_CONFIG_DIR', value: '/config', redacted: false },
  { key: 'PLEYA_SERVER_FFPROBE_TIMEOUT', value: '60s', redacted: false },
  { key: 'PLEYA_SERVER_HTTP_ADDR', value: ':8080', redacted: false },
  { key: 'PLEYA_SERVER_JOB_WORKERS', value: '2', redacted: false },
  { key: 'PLEYA_SERVER_LOG_LEVEL', value: 'info', redacted: false },
  { key: 'PLEYA_SERVER_MEDIA_DIRS', value: '/volume1/media,/volume2/media,/mnt/usb-archief', redacted: false },
  { key: 'PLEYA_SERVER_TRANSCODE_MAX_SESSIONS', value: '2', redacted: false },
  { key: 'PLEYA_SERVER_TRUSTED_PROXIES', value: '172.18.0.0/16', redacted: false }
];
const LOG = [
  { at: iso(40), level: 'warn', component: 'scanner', message: 'scan root not mounted, skipping library=boeken root=/volume1/media/Boeken' },
  { at: iso(360), level: 'error', component: 'ffprobe', message: 'probe ffprobe timeout after 60s attempts=3' },
  { at: iso(560), level: 'warn', component: 'config', message: 'library from env still present after takeover, ignored slug=kids' },
  { at: iso(60 * 20), level: 'warn', component: 'auth', message: 'login rate limited user=sanne' }
];

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
page.on('response', (r) => r.status() === 404 && errors.push(`404 ${new URL(r.url()).pathname}`));

await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  if (request.method() === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', expires_in_ms: 3_600_000 });
  }
  if (request.method() === 'POST' && path === '/server/connectivity-check') {
    return json(route, { public_url_reachable: true, range_intact: true, behind_proxy: true });
  }
  if (request.method() !== 'GET') {
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77', setup_accepts_name: true },
        capabilities: {
          browse: true, search: true, artwork: true, watch_state: true, watch_state_ownership: true,
          stream_sessions: true, users: true, sessions: true, administration: true, ebooks: true, filters: true,
          playback_plan: false, transcode: true, downloads: true, live_tv: false, realtime: false
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, {
        id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77', name: 'Pleya-server', version: '0.9.0', started_at: iso(60 * 24 * 6),
        public_url: 'https://web.pleya.app', listen: ':8080', behind_proxy: true, trusted_proxies: ['172.18.0.0/16'],
        build: 'go1.24.2 linux/amd64', database: { version: '18.1', schema: 8 }, ffprobe: { found: true, version: 'ffmpeg 5.1.9 (Debian)' },
        health: { ready: true, jobs_running: 1, jobs_failed: 2 }, mcp: { enabled: false, tool_count: 0 }
      });
    case '/settings':
      return json(route, SETTINGS);
    case '/libraries':
      return json(route, { items: LIBRARIES });
    case '/users/me':
      return json(route, USERS[0]);
    case '/users':
      return json(route, { items: USERS });
    case '/sessions':
      return json(route, { items: SESSIONS[url.searchParams.get('user_id') ?? ''] ?? [] });
    case '/transcode-sessions':
      return json(route, {
        max_sessions: 2,
        hardware: { accel: 'vaapi', reason: null },
        items: [{ id: 't1', user_id: 'u2', version_id: 'v1', mode: 'transcode', hw_accel: 'vaapi', started_at: iso(14), last_heartbeat_at: iso(0) }]
      });
    case '/server/environment':
      return json(route, { entries: ENVIRONMENT });
    case '/server/log':
      return json(route, { entries: LOG });
    case '/metadata/attention':
      return json(route, {
        total: 3,
        items: [
          { item_id: 'i1', library_id: 'l1', kind: 'movie', title: 'Nosferatu', year: 2024, state: 'ambiguous', alternatives: [], updated_at: iso(60) },
          { item_id: 'i2', library_id: 'l1', kind: 'movie', title: 'Heat', year: 1995, state: 'unmatched', alternatives: [], updated_at: iso(90) },
          { item_id: 'i3', library_id: 'l2', kind: 'show', title: 'Sneaky Pete', year: 2015, state: 'failed', alternatives: [], updated_at: iso(120) }
        ]
      });
    default: {
      const coverage = path.match(/^\/libraries\/([^/]+)\/metadata-coverage$/);
      if (coverage && COVERAGE[coverage[1]!]) return json(route, COVERAGE[coverage[1]!]);
      return json(route, { error: { code: 'auth.user_not_found', message: 'nagebootst', retryable: false } }, 404);
    }
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

await shoot('/admin/media', '28-media-nagebootst');
await shoot('/admin/media', '28-media-opslaan-nagebootst', async (p) => {
  await p.getByLabel(t('admin.media.streams.max')).selectOption('4');
  await p.getByRole('button', { name: t('admin.set.action.save') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/metadata', '29-metadata-nagebootst');
await shoot('/admin/network', '30-netwerk-nagebootst');
await shoot('/admin/network', '30-netwerk-buitensluiten-nagebootst', async (p) => {
  await p.getByLabel(t('admin.set.field.web_origin')).fill('https://nieuw.example.org');
  await p.getByRole('button', { name: t('admin.set.action.save') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/network', '30-netwerk-getest-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.net.conn.test') }).click();
  await p.waitForTimeout(500);
});
await shoot('/admin/security', '31-beveiliging-nagebootst');
await shoot('/admin/security', '31-beveiliging-roteren-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.sec.key.rotate') }).click();
  await p.getByRole('dialog').getByRole('textbox').fill('rot');
  await p.waitForTimeout(300);
});
await shoot('/admin/diagnostics', '32-diagnostiek-nagebootst');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
