/**
 * Speelt titels echt af in een echte browser tegen een echte Pleya Server, en
 * controleert wat de speler belooft (S13.2, S18.3):
 *
 * - de `<video>` loopt (currentTime groeit) en de leveringswijze klopt;
 * - geen enkele aangevraagde URL draagt het accesstoken, en hls.js zet nooit
 *   een `stream_token` in de query;
 * - na sluiten staat er geen omzetsessie meer in `GET /transcode-sessions`.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5191 \
 *   PLEYA_LIVE_USER=... PLEYA_LIVE_PASS=... \
 *   bun run scripts/player-live-check.ts "Direct" "Omzet"
 *
 * Gebruikersnaam en wachtwoord komen uit de omgeving en worden nergens
 * afgedrukt of opgeslagen. Het script schrijft niets naar de server behalve
 * wat de speler zelf doet (plan, streamsessie, hartslag, stoppen). Standaard
 * draait het in Google Chrome (`PLEYA_LIVE_CHANNEL=chrome`), omdat de
 * Playwright-Chromium geen H.264 of AAC decodeert.
 */
import { chromium, type Page } from '@playwright/test';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5191';
const USER = process.env['PLEYA_LIVE_USER'] ?? '';
const PASS = process.env['PLEYA_LIVE_PASS'] ?? '';
const CHANNEL = process.env['PLEYA_LIVE_CHANNEL'] ?? 'chrome';
const TITLES = process.argv.slice(2);

if (!USER || !PASS || TITLES.length === 0) {
  console.error('PLEYA_LIVE_USER, PLEYA_LIVE_PASS en minstens één titel zijn verplicht.');
  process.exit(2);
}

const browser = await chromium.launch({ channel: CHANNEL === 'chromium' ? undefined : CHANNEL });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const urls: string[] = [];
page.on('request', (r) => urls.push(r.url()));

await page.goto(`${BASE}/login`);
await page.locator('input[autocomplete="username"]').fill(USER);
await page.locator('input[type="password"]').fill(PASS);
await page.locator('form button[type="submit"]').click();
await page.waitForURL((u) => !u.pathname.startsWith('/login'));

const access = async (p: Page) =>
  p.evaluate(() => {
    const raw = sessionStorage.getItem('pleya.access_token');
    return raw ? (JSON.parse(raw) as { token: string }).token : '';
  });

async function api<T>(path: string): Promise<{ status: number; body: T }> {
  const token = await access(page);
  const res = await page.request.get(`${BASE}/pleya/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  return { status: res.status(), body: (await res.json().catch(() => null)) as T };
}

type ItemRow = { id: string; title: string };
const libs = await api<{ items: { id: string }[] }>('/libraries');
const all: ItemRow[] = [];
for (const lib of libs.body.items) {
  all.push(...(await api<{ items: ItemRow[] }>(`/libraries/${lib.id}/items?limit=100`)).body.items);
}

let failures = 0;
const tokens = new Set<string>();

for (const title of TITLES) {
  const item = all.find((i) => i.title === title);
  if (!item) {
    console.log(`${title}: niet gevonden`);
    failures++;
    continue;
  }
  await page.goto(`${BASE}/items/${item.id}/play`);
  tokens.add(await access(page));
  const started = Date.now();
  let state = { t: 0, src: '', error: '' };
  while (Date.now() - started < 60_000) {
    state = await page.evaluate(() => {
      const v = document.querySelector('video');
      const alert = document.querySelector('[role="alert"]');
      return { t: v?.currentTime ?? 0, src: v?.currentSrc ?? '', error: alert?.textContent?.trim() ?? '' };
    });
    if (state.t > 3 || state.error) break;
    await page.waitForTimeout(500);
  }
  const chip = (await page.locator('.player .chip').last().textContent().catch(() => '')) ?? '';
  const srcKind = state.src.startsWith('blob:') ? 'blob (hls.js)' : state.src.replace(/\?.*$/, '?…');
  const srcQuery = state.src.includes('?') ? new URL(state.src).searchParams : null;
  const queryKeys = srcQuery ? [...srcQuery.keys()].join(',') : '';

  // Tien seconden vooruit met het toetsenbord en kijken of de positie meeloopt.
  const before = await page.evaluate(() => document.querySelector('video')?.currentTime ?? 0);
  await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(1500);
  const after = await page.evaluate(() => document.querySelector('video')?.currentTime ?? 0);

  // Met PLEYA_LIVE_ADMIN_STOP=1 stopt een beheerder de omzetsessie terwijl er
  // gekeken wordt (DELETE /transcode-sessions/{id}); de speler hoort dan een
  // foutstaat met uitweg te tonen in plaats van stil te blijven staan.
  let afterAdminStop: string | null = null;
  if (process.env['PLEYA_LIVE_ADMIN_STOP'] === '1' && state.src.startsWith('blob:')) {
    const running = await api<{ items: { id: string }[] }>('/transcode-sessions');
    const token = await access(page);
    for (const s of running.body.items) {
      await page.request.delete(`${BASE}/pleya/v1/transcode-sessions/${s.id}`, {
        headers: { Authorization: `Bearer ${token}` }
      });
    }
    afterAdminStop = await page
      .locator('[role="alert"]')
      .textContent({ timeout: 40_000 })
      .catch(() => null);
  }

  // De besturing verbergt zich na drie seconden zonder beweging; een muisbeweging haalt hem terug.
  await page.mouse.move(400, 300);
  await page.mouse.move(420, 320);
  await page.getByRole('button', { name: /^(Back|Terug)$/ }).click();
  await page.waitForURL((u) => !u.pathname.endsWith('/play'));
  await page.waitForTimeout(1500);
  const sessions = await api<{ items: unknown[] }>('/transcode-sessions');

  const ok = !state.error && state.t > 3 && sessions.body.items.length === 0;
  if (!ok) failures++;
  console.log(
    JSON.stringify({
      title,
      speelt: state.t > 3,
      positie_s: Number(state.t.toFixed(1)),
      fout: state.error || null,
      levering: chip,
      bron: srcKind,
      query: queryKeys,
      zoeken_s: Number((after - before).toFixed(1)),
      ...(afterAdminStop !== null || process.env['PLEYA_LIVE_ADMIN_STOP'] === '1'
        ? { na_beheerstop: afterAdminStop?.trim() ?? null }
        : {}),
      omzetsessies_na_sluiten: sessions.body.items.length
    })
  );
}

const leaked = urls.filter((u) => [...tokens].some((tok) => tok && u.includes(tok)));
const tokenInHls = urls.filter((u) => u.includes('/playback/sessions/') && u.includes('stream_token='));
console.log(`aanvragen: ${urls.length}, met accesstoken in de URL: ${leaked.length}, HLS met stream_token: ${tokenInHls.length}`);
if (leaked.length || tokenInHls.length) failures++;
await browser.close();
process.exit(failures ? 1 : 0);
