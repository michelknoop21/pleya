/**
 * Opnamen van Match en overrides (S22.6, scherm 36) en de link vanaf scherm 29,
 * op de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en 320, in de stijl van
 * admin-users-shots.ts: per breedte herladen, de horizontale paginaoverloop
 * meten, een jpeg op kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-match-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server: elke aanvraag naar `/pleya/v1`
 * wordt in de browser beantwoord met verzonnen titels, en elke aanvraag die
 * iets zou veranderen (PUT of DELETE op de match) wordt afgebroken en geteld.
 * De beelden dragen daarom `-nagebootst`.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s22-metadata-match';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (minutesAgo: number) => new Date(NOW - minutesAgo * 60_000).toISOString();

const USER = { id: 'u1', username: 'Michel', role: 'owner' };
const LIBRARIES = [
  { id: 'l1', title: 'Films', kind: 'movies', item_count: 461, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'l2', title: 'Series', kind: 'shows', item_count: 97, managed: 'db', scan_interval_seconds: null, scan_on_start: true }
];
const COVERAGE: Record<string, unknown> = {
  l1: { items: 461, with_sidecar: 420, with_summary: 420, with_genres: 411, ratio: 0.891, threshold: 0.8, gate_met: true },
  l2: { items: 97, with_sidecar: 82, with_summary: 82, with_genres: 79, ratio: 0.814, threshold: 0.8, gate_met: true }
};
const alt = (id: string, title: string, year: number | null) => ({ external_id: id, title, year });
const item = (id: string, title: string, year: number | null, state: string, alternatives: unknown[], kind = 'movie', minutes = 90) => ({
  item_id: id,
  library_id: kind === 'show' ? 'l2' : 'l1',
  kind,
  title,
  year,
  state,
  alternatives,
  updated_at: iso(minutes)
});
const ATTENTION = {
  total: 12,
  items: [
    item('i1', 'Zoutvlakte', 2021, 'ambiguous', [alt('510231', 'Zoutvlakte', 2021), alt('604418', 'Zoutvlakte: deel twee', 2024), alt('88120', 'Zoutvlakte', 1984)], 'movie', 35),
    item('i2', 'Kantelpunt', 2019, 'ambiguous', [alt('301775', 'Kantelpunt', 2019), alt('301776', 'Kantelpunt', 2019)], 'movie', 120),
    item('i3', 'Havenlicht', 2023, 'ambiguous', [alt('77310', 'Havenlicht', 2023), alt('64002', 'Havenlicht', 2023), alt('9921', 'Havenlicht Revisited', null)], 'show', 300),
    item('i4', 'Het Lichtschip', 2024, 'unmatched', [], 'movie', 60 * 20),
    item('i5', 'Anemoon', 2022, 'failed', [], 'movie', 60 * 26),
    item('i6', 'Noordwind', 2017, 'rejected', [], 'movie', 60 * 50)
  ]
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
  const coverage = path.match(/^\/libraries\/([^/]+)\/metadata-coverage$/);
  if (coverage) return json(route, COVERAGE[coverage[1]!]);
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
      return json(route, USER);
    case '/metadata/attention':
      return json(route, ATTENTION);
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

await shoot('/admin/metadata', 'metadata-link-nagebootst');
await shoot('/admin/metadata/match', 'match-nagebootst');
await shoot('/admin/metadata/match?item=i4', 'match-niets-gevonden-nagebootst');
await shoot('/admin/metadata/match?item=i6', 'match-afgewezen-nagebootst');
await shoot('/admin/metadata/match?item=i1', 'match-kiezen-bevestigen-nagebootst', async (p) => {
  await p.getByRole('radio', { name: /deel twee/ }).check({ force: true });
  await p.getByRole('button', { name: t('admin.match.cand.pick') }).click();
  await p.waitForTimeout(300);
});
await shoot('/admin/metadata/match?item=i1', 'match-afwijzen-bevestigen-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.match.cand.reject') }).click();
  await p.waitForTimeout(300);
});

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
