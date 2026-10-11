/**
 * Opnamen van de taalkeuze op /server, in beide talen en op twee breedten.
 * Draait tegen `vite dev` met een nagebootste API (alleen voor de opname),
 * en controleert dat de keuze de schil wisselt, `<html lang>` meeneemt en een
 * herlaad overleeft.
 *
 *   bun run dev --port 5199
 *   PLEYA_DEV_URL=http://localhost:5199 bun run scripts/language-picker-shots.ts
 */
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';

const BASE = process.env['PLEYA_DEV_URL'] ?? 'http://localhost:5173';
const OUT = process.argv[2] ?? '../docs/qa/s7-primitives';
mkdirSync(OUT, { recursive: true });

const caps = Object.fromEntries(
  ['browse', 'search', 'artwork', 'watch_state', 'playback_plan', 'users'].map((k) => [k, true])
);
const json = (body: unknown) => ({ contentType: 'application/json', body: JSON.stringify(body) });

const browser = await chromium.launch();
const context = await browser.newContext({ locale: 'en-GB' });
const page = await context.newPage();
await page.route('**/pleya/v1/**', (route) => {
  const path = new URL(route.request().url()).pathname.replace('/pleya/v1', '');
  if (path === '/info') {
    return route.fulfill(
      json({
        protocol: { major: 1, feature_level: 5, profile: 'full' },
        server: { id: 'srv', setup_accepts_name: true },
        capabilities: caps,
        auth: { methods: ['password'], setup_required: false }
      })
    );
  }
  if (path === '/auth/refresh') {
    return route.fulfill(
      json({ access_token: 'a', refresh_token: 'r', token_type: 'bearer', expires_in: 900 })
    );
  }
  if (path === '/server') {
    return route.fulfill(
      json({ id: 'srv', name: 'Thuis', version: '1.0.0', started_at: '2026-10-11T08:00:00Z' })
    );
  }
  if (path === '/libraries') return route.fulfill(json({ items: [] }));
  return route.fulfill({ status: 404, ...json({ error: { code: 'not_found', message: 'x' } }) });
});
await page.addInitScript(() => {
  if (!localStorage.getItem('pleya.refresh_token')) {
    localStorage.setItem('pleya.refresh_token', 'r');
  }
  localStorage.setItem('pleya.theme', 'dark');
});

const htmlLang = () => page.evaluate(() => document.documentElement.lang);

for (const width of [393, 1280]) {
  await page.setViewportSize({ width, height: width < 600 ? 852 : 800 });
  await page.goto(`${BASE}/server`);
  await page.locator('h1').waitFor({ timeout: 8000 });
  const select = page.getByLabel('Language');
  console.log(`${width} en lang=${await htmlLang()} value=${await select.inputValue()}`);
  await page.screenshot({ path: `${OUT}/taalkeuze-en@${width}.png` });

  await Promise.all([page.waitForNavigation(), select.selectOption('nl')]);
  await page.locator('h1').waitFor();
  const nl = page.getByLabel('Taal');
  const heading = await page.locator('h2').first().innerText();
  console.log(`${width} nl lang=${await htmlLang()} value=${await nl.inputValue()} h2=${heading}`);
  await page.screenshot({ path: `${OUT}/taalkeuze-nl@${width}.png` });

  await page.reload();
  await page.locator('h1').waitFor();
  const kept = await page.getByLabel('Taal').inputValue();
  console.log(`${width} na herlaad lang=${await htmlLang()} value=${kept}`);

  await Promise.all([page.waitForNavigation(), page.getByLabel('Taal').selectOption('en')]);
  await page.locator('h1').waitFor();
  console.log(`${width} terug lang=${await htmlLang()}`);
}
await browser.close();
