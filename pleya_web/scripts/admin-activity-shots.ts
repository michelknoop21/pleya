/**
 * Opnamen van Scans en taken (scherm 25) voor het paneel Fouten met een
 * bibliotheek waarvan de laatste scan mislukte, op de vaste breedtes 1920 bij
 * 1080, 1440, 1280, 390 en 320.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-activity-shots.ts [uitvoermap]
 *
 * Praat met geen enkele server: elke aanvraag naar `/pleya/v1` wordt in de
 * browser beantwoord met verzonnen gegevens, want een mislukte laatste scan is
 * op een gezonde server niet uit te lokken en dat doen we ook niet. Elke
 * aanvraag die iets zou veranderen wordt afgebroken, dus een klik raakt niets.
 * Twee staten: een bibliotheek met Nu scannen naast een met een niet-gemounte
 * root (alleen als root gemeld, met Opslag), en een rustige server zonder fouten.
 */
import { chromium, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s10-activity-scan-mislukt';
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
page.on('response', (r) => r.status() === 404 && errors.push(`404 ${r.url()}`));

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

const mkLibrary = (id: string, title: string, kind = 'movies') => ({
  id,
  title,
  kind,
  item_count: 120,
  managed: 'db',
  scan_interval_seconds: null,
  scan_on_start: true
});
const LIBRARIES = [mkLibrary('l1', 'Films'), mkLibrary('l2', 'Series', 'shows'), mkLibrary('l3', 'Kids')];
const mkRoot = (path: string, owner: { id: string; title: string }, mounted = true) => ({
  path,
  fs_type: 'btrfs',
  inode_trusted: true,
  inode_trust_source: 'measured',
  mounted,
  free_bytes: 1_100_000_000_000,
  total_bytes: 2_000_000_000_000,
  libraries: [{ id: owner.id, title: owner.title }]
});
const mkScan = (id: string, library: string, state: string, startedAgo: number, extra: object = {}) => ({
  id,
  library_id: library,
  trigger: 'startup',
  state,
  started_at: ago(startedAgo),
  finished_at: ago(startedAgo - 3),
  files_seen: 3087,
  files_new: 0,
  files_renamed: 0,
  files_changed: 0,
  files_probed: 0,
  files_missing: 0,
  bytes_hashed: 0,
  items_created: 0,
  versions_created: 0,
  error_count: 0,
  last_error: null,
  current_path: null,
  ...extra
});

// Wat elke staat laat zien. De laatste scan per bibliotheek komt vooraan.
const STATES = {
  'fouten-scan-mislukt': {
    roots: [
      mkRoot('/media/library/Films', LIBRARIES[0]!),
      mkRoot('/media/library/Series', LIBRARIES[1]!),
      mkRoot('/media/library/Kids', LIBRARIES[2]!, false)
    ],
    scans: [
      mkScan('s-kids', 'l3', 'failed', 45, { files_seen: 0, last_error: 'root niet gemount: /media/library/Kids' }),
      mkScan('s-series', 'l2', 'failed', 90, {
        files_seen: 11305,
        last_error: 'lezen van /media/library/Series afgebroken: input/output error'
      }),
      mkScan('s-films', 'l1', 'done', 120)
    ]
  },
  'fouten-leeg': {
    roots: [
      mkRoot('/media/library/Films', LIBRARIES[0]!),
      mkRoot('/media/library/Series', LIBRARIES[1]!),
      mkRoot('/media/library/Kids', LIBRARIES[2]!)
    ],
    scans: [
      mkScan('s-kids', 'l3', 'done', 45, { files_seen: 133 }),
      mkScan('s-series', 'l2', 'done', 90, { files_seen: 24272 }),
      mkScan('s-films', 'l1', 'done', 120)
    ]
  }
} as const;
let current: keyof typeof STATES = 'fouten-scan-mislukt';

await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  if (request.method() === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', token_type: 'bearer', expires_in_ms: 3_600_000 });
  }
  if (request.method() !== 'GET') {
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  }
  const state = STATES[current];
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 'srv', setup_accepts_name: false },
        capabilities: { browse: true, search: true, artwork: true, users: true, administration: true, sessions: true },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 'srv', name: 'Pleya-server', version: '0.9.0', started_at: ago(600) });
    case '/libraries':
      return json(route, { items: LIBRARIES });
    case '/storage/roots':
      return json(route, { roots: state.roots });
    case '/scans': {
      const library = url.searchParams.get('library_id');
      const items = library ? state.scans.filter((s) => s.library_id === library).slice(0, 1) : state.scans;
      return json(route, { items, next_cursor: null });
    }
    case '/jobs':
      return json(route, { items: [], next_cursor: null });
    case '/users/me':
      return json(route, { id: 'u1', username: 'Michel', role: 'owner' });
    default:
      return json(route, { error: { code: 'auth.user_not_found', message: 'nagebootst', retryable: false } }, 404);
  }
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill('nagebootst');
await page.getByLabel(t('login.password'), { exact: true }).fill('nagebootst');
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function shoot(name: keyof typeof STATES): Promise<void> {
  current = name;
  await page.goto(`${BASE}/admin/activity`);
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(600);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage: true, type: 'jpeg', quality: 70 });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await shoot('fouten-scan-mislukt');
await shoot('fouten-leeg');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
