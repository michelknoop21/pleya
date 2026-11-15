/**
 * Opnamen van de beheerschermen uit het doelbeeld (Bibliotheek toevoegen,
 * Activiteit met geplande taken en log, Media en streaming, Match corrigeren)
 * op de vaste breedtes 1920 bij 1080, 1440, 1280, 390 en 320.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-beheer-shots.ts [uitvoermap]
 *
 * Praat met geen enkele server: elke aanvraag naar `/pleya/v1` wordt in de
 * browser beantwoord met verzonnen gegevens, en elke aanvraag die iets zou
 * veranderen wordt afgebroken en geteld. Zelfde opzet als
 * admin-activity-shots.ts.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/beheer-doelbeeld';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();
const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const mkLibrary = (id: string, title: string, kind: string, interval: number | null, count: number) => ({
  id,
  title,
  kind,
  item_count: count,
  managed: 'db',
  scan_interval_seconds: interval,
  scan_on_start: true
});
const LIBRARIES = [
  mkLibrary('l1', 'Films', 'movies', 21600, 461),
  mkLibrary('l2', 'Series', 'shows', 21600, 97),
  mkLibrary('l3', 'Kids', 'movies', null, 133)
];
const mkRoot = (path: string, owner: (typeof LIBRARIES)[number] | null, extra: object = {}) => ({
  path,
  fs_type: 'btrfs',
  inode_trusted: true,
  inode_trust_source: 'measured',
  mounted: true,
  free_bytes: 1_100_000_000_000,
  total_bytes: 2_000_000_000_000,
  libraries: owner ? [{ id: owner.id, title: owner.title }] : [],
  ...extra
});
const ROOTS = [
  mkRoot('/volume1/media/Films', LIBRARIES[0]!),
  mkRoot('/volume1/media/Series', LIBRARIES[1]!),
  mkRoot('/volume1/media/Kids', LIBRARIES[2]!, { mounted: false }),
  mkRoot('/volume1/media/Documentaires', null),
  mkRoot('/volume2/archief/Docu', null, { fs_type: 'fuseblk.ntfs', inode_trusted: false, inode_trust_source: 'fstype_default' })
];
const mkScan = (id: string, library: string, state: string, startedAgo: number, extra: object = {}) => ({
  id,
  library_id: library,
  trigger: 'schedule',
  state,
  started_at: ago(startedAgo),
  finished_at: state === 'running' ? null : ago(startedAgo - 12),
  files_seen: 3104,
  files_new: 4,
  files_renamed: 0,
  files_changed: 0,
  files_probed: 41,
  files_missing: 0,
  bytes_hashed: 128_000_000,
  items_created: 3,
  versions_created: 0,
  error_count: 0,
  last_error: null,
  current_path: null,
  ...extra
});
const SCANS = [
  mkScan('s-series', 'l2', 'running', 9, { current_path: 'Series/Severance/Season 02/Severance.S02E07.mkv' }),
  mkScan('s-films', 'l1', 'done', 380, { files_seen: 28412 }),
  mkScan('s-kids', 'l3', 'failed', 400, { files_seen: 0, last_error: 'root niet gemount: /volume1/media/Kids' })
];
const JOBS = [
  {
    id: 'j1',
    kind: 'scan_library',
    state: 'running',
    attempts: 1,
    max_attempts: 3,
    last_error: null,
    run_at: ago(9),
    created_at: ago(9),
    finished_at: null,
    cancel_requested_at: null,
    library_id: 'l2',
    scan_id: 's-series'
  }
];
const LOG = [
  { at: ago(4), level: 'error', component: 'scanner', message: 'analyse: ffprobe gaf na 60 s geen antwoord path=Films/Nosferatu (2024)/Nosferatu.mkv attempt=3' },
  { at: ago(6), level: 'warn', component: 'scanner', message: 'analyse: ffprobe traag (41 s) path=Films/Nosferatu (2024)/Nosferatu.mkv attempt=2' },
  { at: ago(400), level: 'warn', component: 'scanner', message: 'scan: root /volume1/media/Kids niet gemount, bibliotheek Kids overgeslagen' },
  { at: ago(430), level: 'warn', component: 'storage', message: 'opslag: /volume1/media/Kids niet meer bereikbaar, inhoud blijft zichtbaar' }
];
const SETTINGS = {
  server_name: { value: 'Pleya-server', source: 'env' },
  access_token_ttl: { value: '15m0s', source: 'env' },
  refresh_token_ttl: { value: '720h0m0s', source: 'db' },
  stream_token_ttl: { value: '5m0s', source: 'env' },
  stream_session_ttl: { value: '30m0s', source: 'env' },
  max_stream_sessions: { value: 8, source: 'env' },
  public_url: { value: 'https://pleya.example', source: 'env' },
  web_origin: { value: '', source: 'env' },
  cors_origins: { value: [], source: 'env' }
};
const USERS = [
  { id: 'u1', username: 'Michel', role: 'owner' },
  { id: 'u2', username: 'Sanne', role: 'member' }
];
const alt = (id: string, title: string, year: number | null) => ({ external_id: id, title, year });
const attention = (id: string, title: string, year: number, state: string, alternatives: unknown[], kind = 'movie') => ({
  item_id: id,
  library_id: kind === 'show' ? 'l2' : 'l1',
  kind,
  title,
  year,
  state,
  alternatives,
  updated_at: ago(90)
});
const ATTENTION = {
  total: 4,
  items: [
    attention('i1', 'The Simple Life', 2003, 'ambiguous', [alt('4369', 'The Simple Life', 2003), alt('31284', 'The Simple Life', 1998), alt('870154', 'Simple Life', 2021)], 'show'),
    attention('i2', 'Kantelpunt', 2019, 'ambiguous', [alt('301775', 'Kantelpunt', 2019), alt('301776', 'Kantelpunt', 2019)]),
    attention('i3', 'Het Lichtschip', 2024, 'unmatched', []),
    attention('i4', 'Anemoon', 2022, 'failed', [])
  ]
};

const browser = await chromium.launch();
const context = await browser.newContext({
  ...localeContextOptions('nl'),
  viewport: { width: 1440, height: 900 }
});
const page = await context.newPage();
const errors: string[] = [];
const blocked: string[] = [];
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

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
  if (/^\/libraries\/[^/]+\/metadata-coverage$/.test(path)) {
    return json(route, { items: 461, with_sidecar: 420, with_summary: 420, with_genres: 411, ratio: 0.9, threshold: 0.8, gate_met: true });
  }
  if (/^\/items\/[^/]+\/metadata-match$/.test(path)) {
    return json(route, {
      item_id: path.split('/')[2],
      application_state: 'unknown',
      requested_external_ids: null,
      applied_external_ids: null,
      updated_at: null
    });
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 'srv', setup_accepts_name: false },
        capabilities: {
          browse: true, search: true, artwork: true, watch_state: true, users: true, administration: true,
          sessions: true, transcode: true, downloads: true,
          metadata_search: true, metadata_match_status: true, metadata_overrides: true, artwork_choices: true
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, {
        id: 'srv', name: 'Pleya-server', version: '0.9.0', started_at: ago(60 * 24 * 6),
        build: 'go1.24.2 linux/amd64', database: { version: '18.1', schema: 36 },
        ffprobe: { found: true, version: 'ffprobe version 7.1.1-1+b1 Copyright (c) 2007-2026 the FFmpeg developers' },
        health: { ready: true, jobs_running: 1, jobs_failed: 0 }
      });
    case '/libraries':
      return json(route, { items: LIBRARIES });
    case '/storage/roots':
      return json(route, { roots: ROOTS });
    case '/scans': {
      const library = url.searchParams.get('library_id');
      const items = library ? SCANS.filter((s) => s.library_id === library).slice(0, 1) : SCANS;
      return json(route, { items, next_cursor: null });
    }
    case '/jobs':
      return json(route, { items: JOBS, next_cursor: null });
    case '/server/log': {
      const order = ['debug', 'info', 'warn', 'error'];
      const floor = order.indexOf(url.searchParams.get('level') ?? 'debug');
      return json(route, { entries: LOG.filter((e) => order.indexOf(e.level) >= floor) });
    }
    case '/settings':
      return json(route, SETTINGS);
    case '/server/environment':
      return json(route, {
        entries: [
          { key: 'PLEYA_SERVER_FFPROBE_TIMEOUT', value: '60s', redacted: false },
          { key: 'PLEYA_SERVER_TRANSCODE_MAX_SESSIONS', value: '2', redacted: false }
        ]
      });
    case '/transcode-sessions':
      return json(route, {
        max_sessions: 2,
        hardware: { accel: 'vaapi', reason: null },
        items: [{ id: 't1', user_id: 'u2', version_id: 'v1', mode: 'transcode', hw_accel: 'vaapi', started_at: ago(14), last_heartbeat_at: ago(0) }]
      });
    case '/users':
      return json(route, { items: USERS });
    case '/users/me':
      return json(route, USERS[0]);
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

async function shoot(path: string, name: string, prepare?: (p: Page) => Promise<void>): Promise<void> {
  await page.goto(`${BASE}${path}`);
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(600);
    await prepare?.(page);
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage: true, type: 'jpeg', quality: 70 });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await shoot('/admin/libraries/new', 'bibliotheek-nieuw', async (p) => {
  await p.getByRole('textbox', { name: t('admin.lib.form.name') }).fill('Documentaires');
  await p.getByRole('checkbox', { name: /Documentaires/ }).check();
  await p.getByRole('checkbox', { name: /archief/ }).check();
});
await shoot('/admin/libraries/l1', 'bibliotheek-verwijderen', async (p) => {
  await p.getByRole('button', { name: t('admin.lib.delete.open') }).click();
  await p.getByRole('dialog').waitFor();
});
await shoot('/admin/activity', 'activiteit');
await shoot('/admin/activity', 'activiteit-log-zoeken', async (p) => {
  await p.getByRole('searchbox', { name: t('admin.act.log.search') }).fill('ffprobe');
});
await shoot('/admin/media', 'media-en-streaming');
await shoot('/admin/metadata/match', 'match');

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
