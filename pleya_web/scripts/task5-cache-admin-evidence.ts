// Opt-in synthetische serverfixture; echte HTTP, jobs en bestanden. Geen browserroute-interceptie.
import { chromium, expect, request, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
const base = 'http://127.0.0.1:8861';
const out = '/tmp/task5-artwork-cache-admin-1102';
mkdirSync(`${out}/screens`, { recursive: true });
const api = await request.newContext({ baseURL: base });
const headers = { 'X-Task5-Cache-Fixture': 'synthetic-only' };
const ready = await (await api.get('/__cache-admin/ready', { headers })).json();
expect(ready.server).toBe('synthetic-only');
const browser = await chromium.launch({ headless: true });
const manifest: unknown[] = [], checks: string[] = [];
const control = async (action: string) => {
  const response = await api.post(`/__cache-admin/${action}`, { headers });
  expect(response.ok(), `${action}: ${await response.text()}`).toBe(true);
  return response;
};
const receivedMutations = async (): Promise<string[]> => (await (await api.get('/__cache-admin/mutations',{headers})).json()) ?? [];
const panel = (page: Page) => page.getByRole('region', { name: 'Verkleinde afbeeldingen', exact: true });
async function shot(page: Page, name: string, width: number, state: string) {
  await panel(page).scrollIntoViewIfNeeded();
  const geometry = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth }));
  if (geometry.document > width + 1) {
    const overflow = await page.evaluate(() => [...document.querySelectorAll('main *')].filter(e => e.getBoundingClientRect().right > innerWidth + 1).map(e => ({tag:e.tagName,cls:e.className,text:e.textContent?.slice(0,100),rect:{x:e.getBoundingClientRect().x,width:e.getBoundingClientRect().width},minWidth:getComputedStyle(e).minWidth})).slice(0,40));
    writeFileSync(`${out}/overflow.json`,JSON.stringify(overflow,null,2));
    await page.screenshot({path:`${out}/screens/${name}-overflow.png`,fullPage:true});
  }
  expect(geometry.document).toBeLessThanOrEqual(width + 1);
  await page.screenshot({ path: `${out}/screens/${name}.png` });
  await page.screenshot({ path: `${out}/screens/${name}-full.png`, fullPage: true });
  manifest.push({ screen: '/admin/storage', width, state, file: `screens/${name}.png`, fullFile: `screens/${name}-full.png`, geometry });
}
try {
  for (const width of [320, 390, 1440]) {
    await control('rebuild');
    const beforeMutations = (await receivedMutations()).length;
    const context = await browser.newContext({ viewport: { width, height: width < 900 ? 844 : 1000 }, hasTouch: width < 900, deviceScaleFactor: 1 });
    await context.addInitScript((theme) => {
      localStorage.setItem('pleya.locale', 'nl'); localStorage.setItem('pleya.theme', theme);
    }, width === 390 ? 'light' : 'dark');
    const page = await context.newPage(); page.setDefaultTimeout(15000);
    const errors: string[] = []; page.on('pageerror', e => errors.push(e.message));
    const mutations: string[] = [];
    page.on('request', r => { if (r.method() === 'DELETE' && r.url().endsWith('/artwork/cache')) mutations.push(r.postData() ?? ''); });
    await page.goto(base); await page.waitForURL('**/login');
    await page.getByLabel('Gebruikersnaam', { exact: true }).fill('michel');
    await page.getByLabel('Wachtwoord', { exact: true }).fill('een-lang-genoeg-wachtwoord');
    await page.getByRole('button', { name: 'Inloggen', exact: true }).click();
    await page.waitForURL(url => url.pathname !== '/login');
    await page.goto(`${base}/admin/storage`);
    await expect(panel(page).locator('.summary')).toContainText('1 bestand');
    await expect(page.getByRole('heading', { name: 'Wat de server hier beheert' })).toBeVisible();
    await shot(page, `${width}-cache-ready`, width, 'real cached ladder counts; existing storage table and controls');
    expect(mutations).toHaveLength(0);
    expect(await receivedMutations()).toHaveLength(beforeMutations);
    await panel(page).getByRole('button', { name: 'Afbeeldingscache leegmaken', exact: true }).click();
    const dialog = page.getByRole('dialog'); await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Annuleren', exact: true })).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(dialog.getByRole('button', { name: 'Leegmaken inplannen', exact: true })).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(dialog.getByRole('button', { name: 'Annuleren', exact: true })).toBeFocused();
    await shot(page, `${width}-cache-confirm`, width, 'existing ConfirmDialog, safe initial focus and trapped keyboard');
    await page.keyboard.press('Escape'); await expect(dialog).toHaveCount(0); expect(mutations).toHaveLength(0);
    expect(await receivedMutations()).toHaveLength(beforeMutations);
    await panel(page).getByRole('button', { name: 'Afbeeldingscache leegmaken', exact: true }).click();
    await dialog.getByRole('button', { name: 'Leegmaken inplannen', exact: true }).click();
    await expect(panel(page).getByText('Taak ontvangen. Volg de uitvoering bij Scans en taken.', { exact: true })).toBeVisible();
    await expect(panel(page).getByText('Afbeeldingscache leeggemaakt.', { exact: true })).toHaveCount(0);
    expect(mutations).toHaveLength(1);
    expect((await receivedMutations()).slice(beforeMutations)).toEqual(['{"confirm":"purge"}']);
    await shot(page, `${width}-cache-accepted`, width, 'real202 means received; no optimistic completion');
    await expect(panel(page).getByText('Afbeeldingscache leeggemaakt.', { exact: true })).toBeVisible({ timeout: 10000 });
    await expect(panel(page).locator('.summary')).toHaveText('0 B · 0 bestanden');
    await shot(page, `${width}-cache-succeeded`, width, 'real durable succeeded and exact refreshed zero');
    await control('rebuild');
    await panel(page).getByRole('button', { name: 'Afbeeldingscache herladen', exact: true }).click();
    await expect(panel(page).locator('.summary')).toContainText('1 bestand');
    if (width === 390) {
      await control('break-cache');
      await panel(page).getByRole('button', { name: 'Afbeeldingscache herladen', exact: true }).click();
      await expect(panel(page).getByRole('alert')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Wat de server hier beheert' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Opnieuw controleren', exact: true }).first()).toBeEnabled();
      await shot(page, '390-cache-error-isolated', width, 'actual symlink-cache read error; roots and recheck remain reachable');
      await control('recover');
      await panel(page).getByRole('button', { name: 'Afbeeldingscache herladen', exact: true }).click();
      await expect(panel(page).getByRole('alert')).toHaveCount(0);
    }
    if (width === 1440) {
      await control('fail-next');
      await panel(page).getByRole('button', { name: 'Afbeeldingscache leegmaken', exact: true }).click();
      await dialog.getByRole('button', { name: 'Leegmaken inplannen', exact: true }).click();
      await expect(panel(page).getByText('De cachetaak is mislukt. Bekijk de fout en probeer opnieuw bij Scans en taken.', { exact: true })).toBeVisible({ timeout: 10000 });
      await shot(page, '1440-cache-job-failed', width, 'real durable filesystem failure, no false completion');
      await control('recover');
      await panel(page).getByRole('link', { name: 'Scans en taken', exact: true }).click();
      await expect(page.getByText('Afbeeldingscache leegmaken', { exact: true }).first()).toBeVisible();
      // Retry/cancel blijven gewone jobacties; de HTTP-tests bewijzen beide statussen.
      await expect(page.getByRole('button', { name: /opnieuw proberen|opnieuw uitvoeren/i }).first()).toBeVisible();
      await page.screenshot({ path: `${out}/screens/1440-activity-job-failed.png`, fullPage: true });
      manifest.push({ screen: '/admin/activity', width, state: 'existing Activity failure and retry', file: 'screens/1440-activity-job-failed.png' });
      const retried = page.waitForResponse(r => r.request().method() === 'POST' && r.url().includes('/jobs/') && r.url().endsWith('/retry'));
      await page.getByRole('button', {name:/opnieuw proberen|opnieuw uitvoeren/i}).first().click();
      expect((await retried).status()).toBe(200);
      await page.goto(`${base}/admin/storage`);
      await expect(panel(page).locator('.summary')).toHaveText('0 B · 0 bestanden',{timeout:10000});
      await shot(page,'1440-cache-retry-succeeded',width,'existing Activity retry200 followed by real successful purge');
    }
    const violations = (await new AxeBuilder({ page }).include('main').analyze()).violations;
    if(violations.length){
      const scroll = await page.locator('.tbl__scroll').evaluateAll(nodes=>nodes.map(e=>({clientWidth:e.clientWidth,scrollWidth:e.scrollWidth,clientHeight:e.clientHeight,scrollHeight:e.scrollHeight,tabindex:e.getAttribute('tabindex'),overflowX:getComputedStyle(e).overflowX,overflowY:getComputedStyle(e).overflowY})));
      writeFileSync(`${out}/axe-failure.json`,JSON.stringify({width,violations,scroll},null,2));
    }
    expect(violations).toEqual([]); expect(errors).toEqual([]);
    await context.close(); checks.push(`${width}: stats, confirmation keyboard/cancel, real202/succeeded, rebuild, overflow, axe, no page errors`);
  }
  writeFileSync(`${out}/received-mutations.json`,JSON.stringify(await receivedMutations(),null,2));
  const integrity = await (await control('integrity')).json();
  writeFileSync(`${out}/integrity.json`, JSON.stringify(integrity, null, 2));
  checks.push('source hash, pins/config/backup/temporary/unknown sentinels and ten exact catalog/personal row snapshots unchanged');
  console.log(`PASS ${manifest.length} states; ${checks.length} checks`);
} finally {
  writeFileSync(`${out}/screens-manifest.json`, JSON.stringify(manifest, null, 2));
  writeFileSync(`${out}/browser-checks.json`, JSON.stringify(checks, null, 2));
  await browser.close(); await api.dispose();
}
