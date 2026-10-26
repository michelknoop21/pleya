/**
 * Opnamen van Opslag (24) en Scans en taken (25), S10.3, op de vaste breedtes
 * 1920 bij 1080, 1440, 1280, 390 en 320. Zelfde opzet als
 * admin-libraries-shots.ts: inloggen, per breedte herladen, de horizontale
 * paginaoverloop meten en een jpeg op kwaliteit 70.
 *
 *   bun run dev    # in een ander venster, poort 5173
 *   bun run scripts/admin-storage-shots.ts [uitvoermap]
 *
 * Alles komt uit een nagebootste server: elke aanvraag naar /pleya/v1 wordt in
 * de browser beantwoord met de gegevens hieronder, en niets raakt een echte
 * server. De gegevens volgen de northstar (Films, Series, Kids, Boeken en een
 * usb-archief; Boeken is niet gemount), zodat de beelden er een-op-een mee te
 * vergelijken zijn. Elke aanvraag die iets zou veranderen wordt vastgelegd en
 * afgebroken, en het script meldt er het aantal van.
 *
 * Een opname tegen een echte testinstance is hetzelfde script met
 * PLEYA_E2E_LIVE=1, PLEYA_E2E_USER en PLEYA_E2E_PASS: dan wordt niets
 * nagebootst en alleen GET en de inlogroutes gaan door.
 */
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const LIVE = process.env['PLEYA_E2E_LIVE'] === '1';
const USER = process.env['PLEYA_E2E_USER'] ?? 'michel';
const PASS = process.env['PLEYA_E2E_PASS'] ?? 'x';
const OUT = process.argv[2] ?? '../docs/qa/s10-storage-scans';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const ago = (minutes: number) => new Date(NOW - minutes * 60_000).toISOString();
const TB = 1_000_000_000_000;
const GB = 1_000_000_000;

const libs = [
  { id: 'lib-films', title: 'Films', kind: 'movies', item_count: 4210, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'lib-series', title: 'Series', kind: 'shows', item_count: 612, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'lib-kids', title: 'Kids', kind: 'shows', item_count: 88, managed: 'db', scan_interval_seconds: null, scan_on_start: true },
  { id: 'lib-boeken', title: 'Boeken', kind: 'movies', item_count: 12, managed: 'db', scan_interval_seconds: null, scan_on_start: true }
];
const ref = (...ids: string[]) => ids.map((id) => ({ id, title: libs.find((l) => l.id === id)!.title }));
const roots = [
  { path: '/volume1/media/Films', fs_type: 'btrfs', inode_trusted: true, inode_trust_source: 'measured', mounted: true, free_bytes: 1.1 * TB, total_bytes: 6 * TB, libraries: ref('lib-films') },
  { path: '/volume2/media/Films-4K', fs_type: 'btrfs', inode_trusted: true, inode_trust_source: 'measured', mounted: true, free_bytes: 2.1 * TB, total_bytes: 6 * TB, libraries: ref('lib-films') },
  { path: '/volume1/media/Series', fs_type: 'btrfs', inode_trusted: true, inode_trust_source: 'measured', mounted: true, free_bytes: 240 * GB, total_bytes: 4 * TB, libraries: ref('lib-series', 'lib-kids').slice(0, 1) },
  { path: '/volume1/media/Boeken', fs_type: null, inode_trusted: false, inode_trust_source: 'fstype_default', mounted: false, free_bytes: 0, total_bytes: 0, libraries: ref('lib-boeken') },
  { path: '/mnt/usb-archief', fs_type: 'fuseblk.ntfs', inode_trusted: false, inode_trust_source: 'fstype_default', mounted: true, free_bytes: 1.2 * TB, total_bytes: 2 * TB, libraries: [] }
].map((r) => ({ ...r, free_bytes: Math.round(r.free_bytes), total_bytes: Math.round(r.total_bytes) }));

const base = { trigger: 'schedule', files_renamed: 0, files_changed: 0, files_probed: 0, files_missing: 0, bytes_hashed: 0, items_created: 0, versions_created: 0, error_count: 0, last_error: null, current_path: null };
const scans = [
  { ...base, id: 'sc1', library_id: 'lib-series', trigger: 'manual', state: 'running', started_at: ago(9), finished_at: null, files_seen: 3104, files_new: 0, files_probed: 41, files_renamed: 2, bytes_hashed: 128_000_000, current_path: '…/Severance/Season 02/Severance.S02E07.mkv' },
  { ...base, id: 'sc2', library_id: 'lib-films', state: 'done', started_at: ago(250), finished_at: ago(239), files_seen: 28412, files_new: 3, error_count: 1 },
  { ...base, id: 'sc3', library_id: 'lib-kids', state: 'done', started_at: ago(250), finished_at: ago(249.3), files_seen: 212, files_new: 0 },
  { ...base, id: 'sc4', library_id: 'lib-boeken', state: 'failed', started_at: ago(250), finished_at: ago(249.9), files_seen: 0, last_error: 'root niet gemount' },
  { ...base, id: 'sc5', library_id: 'lib-series', state: 'done', started_at: ago(1100), finished_at: ago(1086), files_seen: 4998, files_new: 2 },
  { ...base, id: 'sc6', library_id: 'lib-films', trigger: 'manual', state: 'cancelled', started_at: ago(1180), finished_at: ago(1178), files_seen: 8811, files_new: 0 }
];
const jobBase = { attempts: 1, max_attempts: 3, last_error: null, run_at: ago(10), created_at: ago(10), finished_at: null, cancel_requested_at: null };
const jobs = [
  { ...jobBase, id: 'j1', kind: 'scan_library', state: 'running', library_id: 'lib-series', scan_id: 'sc1' },
  { ...jobBase, id: 'j2', kind: 'scan_library', state: 'failed', attempts: 3, last_error: 'ffprobe gaf na 60 s geen antwoord', library_id: 'lib-films', finished_at: ago(300), created_at: ago(320) },
  { ...jobBase, id: 'j3', kind: 'backup_create', state: 'failed', attempts: 2, last_error: 'geen schrijfrechten op /backups', finished_at: ago(600), created_at: ago(610) }
];

const json = (body: unknown, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const blocked: string[] = [];
const errors: string[] = [];
const browser = await chromium.launch();
const context = await browser.newContext({ ...localeContextOptions('nl'), viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

await context.route('**/pleya/v1/**', (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  const method = request.method();
  if (LIVE) {
    if (method === 'GET' || path.startsWith('/auth/')) return route.fallback();
    blocked.push(`${method} ${path}`);
    return route.abort();
  }
  if (method !== 'GET' && path !== '/auth/login') {
    blocked.push(`${method} ${path}`);
    return route.abort();
  }
  switch (path) {
    case '/info':
      return route.fulfill(json({ protocol: { major: 1, feature_level: 1, profile: 'full' }, server: { id: 's1' }, capabilities: { browse: true, search: true, artwork: true, watch_state: true, users: true, administration: true }, auth: { methods: ['password'], setup_required: false } }));
    case '/auth/login':
      return route.fulfill(json({ access_token: 'a', refresh_token: 'r', token_type: 'bearer', expires_in_ms: 3_600_000 }));
    case '/users/me':
      return route.fulfill(json({ id: 'u1', username: 'michel', role: 'owner' }));
    case '/users':
      return route.fulfill(json({ items: [{ id: 'u1', username: 'michel', role: 'owner' }] }));
    case '/server':
      return route.fulfill(json({ id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: ago(5000) }));
    case '/libraries':
      return route.fulfill(json({ items: libs }));
    case '/storage/roots':
      return route.fulfill(json({ roots }));
    case '/scans':
      return route.fulfill(json({ items: scans, next_cursor: null }));
    case '/jobs':
      return route.fulfill(json({ items: jobs, next_cursor: null }));
    case '/stream-sessions':
      return route.fulfill(json({ items: [] }));
    case '/transcode-sessions':
      return route.fulfill(json({ max_sessions: 0, hardware: { accel: 'none', reason: null }, items: [] }));
    default:
      return route.fulfill(json({ items: [], next_cursor: null }));
  }
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill(USER);
await page.getByLabel(t('login.password'), { exact: true }).fill(PASS);
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function shoot(path: string, name: string, wait: string): Promise<void> {
  await page.goto(`${BASE}${path}`);
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.reload({ waitUntil: 'networkidle' });
    await page.getByText(wait).first().waitFor();
    await page.waitForTimeout(500);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, fullPage: width >= 1280, type: 'jpeg', quality: 70 });
    console.log(`${name}@${width}: overloop ${over}px`);
  }
}

await shoot('/admin/storage', 'opslag', '/volume1/media/Films');
await shoot('/admin/activity', 'scans-en-taken', t('admin.act.history.title'));

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
