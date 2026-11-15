/**
 * Opnamen van de drie servergaten in Pleya Web (DEC-XXX, drie servergaten), op
 * de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en 320:
 *
 * - Geplande taken met de kolom Volgende (`next_scan_at`, één bibliotheek met
 *   een tijd en één zonder planning);
 * - een seizoen in één keer als gezien gemarkeerd (`POST /items/{id}/watch-state`);
 * - Metadata verversen op de seriepagina (tab Details) en in het menu van een film.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/server-gaten-shots.ts [uitvoermap]
 *
 * Praat met geen enkele server: elke aanvraag naar `/pleya/v1` wordt in de
 * browser beantwoord met verzonnen gegevens. Alleen de twee nieuwe POST-routes
 * krijgen een antwoord; elke andere schrijfaanvraag wordt afgebroken.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/server-gaten';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({ ...localeContextOptions('nl'), viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
const errors: string[] = [];
const blocked: string[] = [];
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
const at = (minutes: number) => new Date(Date.now() + minutes * 60_000).toISOString();

const mkLibrary = (id: string, title: string, kind: string, next: string | null) => ({
  id, title, kind, item_count: 120, managed: 'db', scan_interval_seconds: null, scan_on_start: true, next_scan_at: next
});
const LIBRARIES = [mkLibrary('l1', 'Films', 'movies', at(95)), mkLibrary('l2', 'Series', 'shows', null)];
const mkRoot = (path: string, owner: { id: string; title: string }) => ({
  path, fs_type: 'btrfs', inode_trusted: true, inode_trust_source: 'measured', mounted: true,
  free_bytes: 1_100_000_000_000, total_bytes: 2_000_000_000_000, libraries: [{ id: owner.id, title: owner.title }]
});

const stamp = at(-60);
const state = (watched: boolean, position = 0) => ({ position_ms: position, watched, play_count: watched ? 1 : 0, updated_at: stamp });
const SHOW = {
  id: 'show', kind: 'show', title: 'How I Met Your Mother', year: 2005, added_at: stamp, child_count: 2, episode_count: 5,
  watched_episode_count: 1, summary: 'Ted vertelt zijn kinderen hoe hij hun moeder ontmoette.', genres: ['Comedy']
};
const SEASONS = [1, 2].map((n) => ({ id: `s${n}`, kind: 'season', title: `Seizoen ${n}`, index: n, parent_id: 'show', added_at: stamp, child_count: n === 1 ? 2 : 3 }));
const episode = (s: number, n: number, user: object | null) => ({
  id: `s${s}e${n}`, kind: 'episode', title: `Aflevering ${s}.${n}`, index: n, parent_id: `s${s}`, added_at: stamp,
  duration_ms: 1_320_000, summary: `Samenvatting ${s}.${n}`, versions: [{ id: `v${s}${n}`, container: 'mkv', duration_ms: 1_320_000, file_count: 1 }],
  user_state: user
});
const episodes: Record<string, ReturnType<typeof episode>[]> = {
  s1: [episode(1, 1, state(true)), episode(1, 2, state(false, 300_000))],
  s2: [episode(2, 1, null), episode(2, 2, null), episode(2, 3, null)]
};
const MOVIE = { id: 'movie', kind: 'movie', title: 'Grease', year: 1978, added_at: stamp, duration_ms: 6_600_000, versions: [] };

await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  if (request.method() === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', token_type: 'bearer', expires_in_ms: 3_600_000 });
  }
  const tree = /^\/items\/([^/]+)\/watch-state$/.exec(path);
  if (request.method() === 'POST' && tree) {
    const id = tree[1]!;
    const watched = (JSON.parse(request.postData() ?? '{}') as { explicit_action?: string }).explicit_action === 'mark_watched';
    const ids = [id, ...(episodes[id] ?? []).map((e) => e.id)];
    for (const e of episodes[id] ?? []) e.user_state = state(watched);
    return json(route, { items: ids.map((item) => ({ item_id: item, state: state(watched) })) });
  }
  if (request.method() === 'POST' && /^\/items\/[^/]+\/refresh-metadata$/.test(path)) {
    return json(route, { items: path.startsWith('/items/show') ? 6 : 1 }, 202);
  }
  if (request.method() !== 'GET') {
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  }
  const children = /^\/items\/([^/]+)\/children$/.exec(path);
  if (children) {
    const id = children[1]!;
    return json(route, { items: id === 'show' ? SEASONS : (episodes[id] ?? []), next_cursor: null });
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 'srv', setup_accepts_name: false },
        capabilities: {
          browse: true, search: true, artwork: true, users: true, administration: true, sessions: true,
          watch_state: true, watch_state_tree: true, item_metadata_refresh: true, scan_schedule: true,
          metadata_overrides: true
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 'srv', name: 'Pleya-server', version: '0.9.0', started_at: at(-600) });
    case '/libraries':
      return json(route, { items: LIBRARIES });
    case '/storage/roots':
      return json(route, { roots: [mkRoot('/media/library/Films', LIBRARIES[0]!), mkRoot('/media/library/Series', LIBRARIES[1]!)] });
    case '/scans':
    case '/jobs':
      return json(route, { items: [], next_cursor: null });
    case '/users/me':
      return json(route, { id: 'u1', username: 'Michel', role: 'owner' });
    case '/items/show':
      return json(route, SHOW);
    case '/items/movie':
      return json(route, MOVIE);
    default:
      if (path.startsWith('/hubs/')) return json(route, { items: [], next_cursor: null });
      return json(route, { error: { code: 'library.not_found', message: 'nagebootst', retryable: false } }, 404);
  }
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill('nagebootst');
await page.getByLabel(t('login.password'), { exact: true }).fill('nagebootst');
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function shoot(name: string, url: string, act: (p: Page) => Promise<void>): Promise<void> {
  for (const width of WIDTHS) {
    for (const e of episodes['s2']!) e.user_state = null;
    await page.setViewportSize({ width, height: height(width) });
    await page.goto(`${BASE}${url}`, { waitUntil: 'networkidle' });
    await act(page);
    await page.waitForTimeout(500);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage: true, type: 'jpeg', quality: 70 });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await shoot('gepland-volgende', '/admin/activity', async () => {
  await page.getByText(t('admin.act.sched.next')).first().waitFor();
});
await shoot('seizoen-gezien', '/items/show', async (p) => {
  await p.getByRole('button', { name: 'Seizoen 2 · 3' }).click();
  await p.getByRole('button', { name: t('series.markSeasonWatched') }).click();
  await p.getByRole('button', { name: t('series.markSeasonUnwatched') }).waitFor();
});
await shoot('serie-metadata-verversen', '/items/show', async (p) => {
  await p.getByRole('tab', { name: t('series.tabDetails') }).click();
  await p.getByRole('button', { name: t('detail.refreshMetadata') }).click();
  await p.getByRole('status').first().waitFor();
});
await shoot('film-menu-verversen', '/items/movie', async (p) => {
  await p.getByRole('button', { name: t('detail.moreActions') }).click();
  await p.getByRole('menuitem', { name: t('detail.refreshMetadata') }).click();
  await p.getByRole('status').first().waitFor();
});

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
