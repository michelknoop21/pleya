/**
 * Opnamen van de spelerschil (S13.2, S18.3, doelbeeld Kijken-speler) op 1920
 * bij 1080, 1440, 1280, 390 en 320: laden, spelend met besturing, de
 * foutstaat, het instellingenmenu met afspeelinfo, het ondertitelmenu, de
 * kaart "volgende aflevering", het slotscherm, en de detailpagina met de
 * hervatknop. Per breedte herladen, de horizontale overloop meten, een jpeg op
 * kwaliteit 62, alleen het venster.
 *
 *   ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=24:duration=60 \
 *     -f lavfi -i sine=frequency=440:duration=60 -c:v libx264 -pix_fmt yuv420p \
 *     -c:a aac -shortest -movflags +faststart /tmp/pleya-testbeeld.mp4
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 PLEYA_SHOT_VIDEO=/tmp/pleya-testbeeld.mp4 \
 *     bun run scripts/player-shots.ts [uitvoermap]
 *
 * Geen echte server: elke aanvraag naar `/pleya/v1` wordt in de browser
 * beantwoord, met een gegenereerd testbeeld als stream. Alleen de aanvragen
 * die de speler zelf doet (plan, streamsessie, hartslag) krijgen antwoord;
 * elke andere schrijvende aanvraag wordt afgebroken en geteld, ook het stoppen
 * van een sessie. De beelden dragen daarom `-nagebootst`.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync, readFileSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const VIDEO = process.env['PLEYA_SHOT_VIDEO'] ?? '';
const OUT = process.argv[2] ?? '../docs/qa/s18-player';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : w < 600 ? 844 : 900);

if (!VIDEO) throw new Error('PLEYA_SHOT_VIDEO wijst naar een klein testbeeld; zie de kop van dit script.');
const videoBytes = readFileSync(VIDEO);

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const ITEM = {
  id: 'item-1',
  kind: 'movie',
  title: 'Testbeeld: Kleurbalken',
  year: 2024,
  added_at: '2026-10-01T10:00:00Z',
  duration_ms: 60_000,
  artwork: null,
  user_state: { position_ms: 24_000, watched: false, play_count: 0, updated_at: '2026-10-20T20:00:00Z' },
  versions: [
    {
      id: 'v-1',
      container: 'mp4',
      duration_ms: 60_000,
      file_count: 1,
      video_streams: [{ id: 'vs', index: 0, codec: 'h264', width: 1280, height: 720 }],
      audio_streams: [
        { id: 'a1', index: 1, codec: 'aac', channels: 2, language: 'dut', is_default: true },
        { id: 'a2', index: 2, codec: 'eac3', channels: 6, language: 'eng', title: 'Commentaar' }
      ],
      subtitle_streams: [
        { id: 'sub-nl', format: 'vtt', is_external: true, is_forced: false, is_hearing_impaired: false, language: 'dut' },
        { id: 'sub-en', format: 'srt', is_external: true, is_forced: false, is_hearing_impaired: true, language: 'eng' },
        { id: 'sub-pgs', format: 'pgs', index: 3, is_external: false, is_forced: false, is_hearing_impaired: false }
      ]
    }
  ]
};

// Een aflevering met seizoen, serie en een opvolger: de kop en de kaart "volgende aflevering".
const SHOW = { id: 'show-1', kind: 'show', title: 'Testbeeld: de serie', added_at: ITEM.added_at, artwork: null };
const SEASON = { id: 'season-2', kind: 'season', title: 'Seizoen 2', index: 2, parent_id: 'show-1', added_at: ITEM.added_at, artwork: null };
const EPISODE = { ...ITEM, id: 'ep-3', kind: 'episode', title: 'Kleurbalken', index: 3, parent_id: 'season-2', year: null, user_state: null };
const EPISODE_NEXT = { ...EPISODE, id: 'ep-4', title: 'Testtoon', index: 4, duration_ms: 3_060_000, versions: undefined };
const CONTINUE = [
  { ...ITEM, id: 'c-1', title: 'Rasterbeeld', versions: undefined, user_state: { ...ITEM.user_state, position_ms: 20_000 } },
  { ...ITEM, id: 'c-2', title: 'Grijstrap', versions: undefined, user_state: { ...ITEM.user_state, position_ms: 45_000 } },
  { ...ITEM, id: 'c-3', title: 'Zoneplaat', versions: undefined, user_state: { ...ITEM.user_state, position_ms: 9_000 } }
];
const ITEMS: Record<string, unknown> = {
  '/items/item-1': ITEM, '/items/ep-3': EPISODE, '/items/ep-4': EPISODE_NEXT, '/items/season-2': SEASON, '/items/show-1': SHOW,
  '/items/season-2/children': { items: [EPISODE, EPISODE_NEXT] },
  '/items/show-1/children': { items: [SEASON] },
  '/hubs/continue_watching': { items: CONTINUE }
};

const PLAN = {
  item_id: 'item-1',
  version_id: 'v-1',
  delivery_mode: 'direct_play',
  stream_url: '/pleya/v1/stream/v-1',
  container: 'original',
  video: { action: 'copy' },
  audio: { action: 'copy' },
  seekable: true,
  session_id: null,
  reason: { code: 'direct.supported', params: {} },
  reasons: [{ code: 'direct.supported', params: {} }]
};

type Mode = 'play' | 'hang' | 'busy';
let mode: Mode = 'play';

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

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
  if (method === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', expires_in_ms: 3_600_000 });
  }
  if (method === 'POST' && path === '/playback/plan') {
    if (mode === 'hang') return; // laat de aanvraag hangen: de laadstaat
    if (mode === 'busy') {
      return json(route, { error: { code: 'playback.transcode_busy', message: 'nagebootst', retryable: true } }, 503);
    }
    const body = request.postDataJSON() as { item_id: string };
    return json(route, { ...PLAN, item_id: body.item_id });
  }
  if (method === 'POST' && path === '/auth/stream-session') {
    return json(route, { stream_session_id: 'ss-nagebootst', expires_at: new Date(Date.now() + 1_800_000).toISOString() });
  }
  if (method !== 'GET') {
    blocked.push(`${method} ${path}`);
    return route.abort();
  }
  if (path.startsWith('/stream/')) {
    // HTTP-range zoals /stream/{version_id} het levert; zonder 206 kan de
    // browser niet zoeken en blijft de opname op het eerste beeld staan.
    const range = /bytes=(\d+)-(\d*)/.exec(request.headers()['range'] ?? '');
    if (!range) return route.fulfill({ status: 200, contentType: 'video/mp4', body: videoBytes });
    const start = Number(range[1]);
    const end = range[2] ? Math.min(Number(range[2]), videoBytes.length - 1) : videoBytes.length - 1;
    return route.fulfill({
      status: 206,
      contentType: 'video/mp4',
      headers: {
        'Accept-Ranges': 'bytes',
        'Content-Range': `bytes ${start}-${end}/${videoBytes.length}`
      },
      body: videoBytes.subarray(start, end + 1)
    });
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 's1', setup_accepts_name: false },
        capabilities: {
          browse: true, search: true, artwork: true, watch_state: true, playback_plan: true, transcode: true, stream_sessions: true,
          playback_quality: true, playback_audio_selection: true, ratings: true, favorites: true
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: '2026-10-20T10:00:00Z' });
    case '/libraries':
      return json(route, { items: [{ id: 'l1', title: 'Films', kind: 'movies', item_count: 1 }] });
    case '/subtitles/sub-nl':
      return route.fulfill({
        status: 200,
        contentType: 'text/vtt',
        body: 'WEBVTT\n\n00:00:00.000 --> 00:01:00.000\nEen ondertitel in WebVTT, nagebootst.\n'
      });
    default:
      if (ITEMS[path]) return json(route, ITEMS[path]);
      return json(route, { error: { code: 'library.not_found', message: 'nagebootst', retryable: false } }, 404);
  }
});

await page.goto(`${BASE}/login`);
await page.getByLabel(t('login.username')).fill('nagebootst');
await page.getByLabel(t('login.password'), { exact: true }).fill('nagebootst');
await page.getByRole('button', { name: t('login.submit') }).click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

async function measure(name: string, width: number): Promise<void> {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  await page.screenshot({ path: `${OUT}/${name}@${width}.jpg`, type: 'jpeg', quality: 62 });
  console.log(`${name}@${width}: overloop ${over}px`);
}

/** Zet de video op een vast beeld en houdt de besturing in beeld; `play` laat hem daarna lopen. */
async function settle(p: Page, at = 24, play = true): Promise<void> {
  await p.waitForFunction(() => (document.querySelector('video')?.readyState ?? 0) >= 2, null, { timeout: 15_000 });
  await p.evaluate(async ([seconds, run]) => {
    const v = document.querySelector('video')!;
    v.pause();
    v.currentTime = seconds as number;
    await new Promise((r) => v.addEventListener('seeked', r, { once: true }));
    if (run) await v.play().catch(() => undefined);
  }, [at, play] as const);
  await p.mouse.move(200, 200);
  await p.mouse.move(220, 220);
  // De besturing komt met een overgang in beeld; zonder wachten staat ze half doorzichtig op de opname.
  await p.waitForTimeout(600);
}

async function chooseDutch(p: Page): Promise<void> {
  await p.getByRole('button', { name: t('player.subtitles') }).click();
  await p.getByRole('radio', { name: 'Nederlands', exact: true }).check();
  await p.waitForTimeout(400);
}

async function shoot(name: string, m: Mode, prepare?: (p: Page) => Promise<void>, path = '/items/item-1/play?t=24'): Promise<void> {
  mode = m;
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: height(width) });
    await page.goto(`${BASE}${path}`);
    await page.waitForTimeout(700);
    if (prepare) await prepare(page);
    await measure(name, width);
  }
}

await shoot('detail-hervatten-nagebootst', 'play', undefined, '/items/item-1');
await shoot('laden-nagebootst', 'hang');
await shoot('spelend-nagebootst', 'play', settle);
await shoot('fout-bezet-nagebootst', 'busy', (p) => p.getByRole('alert').waitFor().then(() => undefined));
const EPISODE_PLAY = '/items/ep-3/play?t=24';
await shoot('speler-instellingen-nagebootst', 'play', async (p) => {
  await settle(p);
  await chooseDutch(p);
  await p.getByRole('button', { name: t('player.settings') }).click();
  await p.getByRole('menuitemcheckbox', { name: new RegExp(t('player.info')) }).click();
  await p.mouse.move(240, 240);
}, EPISODE_PLAY);
await shoot('speler-ondertitelmenu-nagebootst', 'play', async (p) => {
  await settle(p);
  await chooseDutch(p);
  await p.mouse.move(240, 240);
}, EPISODE_PLAY);
// Lopend en zonder muis: de kaart staat er ook als de besturing weg is.
await shoot('speler-einde-nagebootst', 'play', async (p) => {
  await settle(p, 32);
  await p.mouse.move(0, 0);
  await p.waitForTimeout(3400);
}, EPISODE_PLAY);
await shoot('speler-slot-nagebootst', 'play', async (p) => {
  await settle(p, 40, false);
  await p.getByRole('button', { name: t('player.rewatch') }).waitFor();
  await p.waitForTimeout(500);
});

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of [...new Set(blocked)]) console.log(`  ${b}`);
await browser.close();
