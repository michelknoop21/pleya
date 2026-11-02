// Alleen echte loopbackhandlers uit de opt-in Task6-testfixture, geen productiedata.
import { chromium, expect, request, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
const base = 'http://127.0.0.1:8843';
const out = '/tmp/task6-web-1102/screens'; mkdirSync(out, { recursive: true });
const api = await request.newContext({ baseURL: base });
const headers = { 'X-Task6-Fixture': 'synthetic-only' };
const fixture = await api.get('/__task6/fixture', { headers }); expect(fixture.ok()).toBe(true);
const info = await fixture.json(); expect(info.server).toBe('synthetic-only');
const login = await api.post('/pleya/v1/auth/login', { data: { username: 'michel', password: 'een-lang-genoeg-wachtwoord' } }); expect(login.ok()).toBe(true);
const owner = (await login.json()).access_token;
const browser = await chromium.launch({ headless: true });
const manifest: Record<string, unknown>[] = []; const checks: Record<string, unknown>[] = []; let serial = 0;
async function control(path: string) { expect((await api.post(`/__task6/${path}`, { headers })).ok()).toBe(true); }
async function account(role = 'admin') {
  const username = `editor${++serial}`;
  const result = await api.post('/pleya/v1/users', { headers: { Authorization: `Bearer ${owner}` }, data: { username, password: 'een-lang-genoeg-wachtwoord', role } });
  expect(result.status()).toBe(200); return username;
}
async function pageFor(width: number, theme: string, role = 'admin') {
  const context = await browser.newContext({ viewport: { width, height: width < 900 ? 844 : 1000 }, deviceScaleFactor: 1, hasTouch: width < 900 });
  await context.addInitScript(({ theme }) => { localStorage.setItem('pleya.locale', 'nl'); localStorage.setItem('pleya.theme', theme); }, { theme });
  const page = await context.newPage(); const errors: string[] = []; const writes: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => { if (['PUT', 'DELETE'].includes(request.method()) && request.url().includes('/overrides')) writes.push(`${request.method()} ${request.url()}`); });
  const username = await account(role);
  await page.goto(base); await page.waitForURL('**/login');
  await page.getByLabel('Gebruikersnaam', { exact: true }).fill(username); await page.getByLabel('Wachtwoord', { exact: true }).fill('een-lang-genoeg-wachtwoord');
  await page.getByRole('button', { name: 'Inloggen', exact: true }).click(); await page.waitForURL(url => url.pathname !== '/login');
  return { context, page, errors, writes };
}
async function shot(page: Page, name: string, width: number, theme: string, state: string, top = true) {
  if (top) await page.evaluate(() => window.scrollTo(0, 0));
  await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
  const file = `${name}.png`; const fullFile = `${name}-full.png`;
  await page.screenshot({ path: `${out}/${file}`, fullPage: false }); await page.screenshot({ path: `${out}/${fullFile}`, fullPage: true });
  const geometry = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth, panel: document.querySelector('.metadata-editor .panel')?.getBoundingClientRect().toJSON() }));
  expect(geometry.document).toBeLessThanOrEqual(width + 1);
  if (width >= 1280 && geometry.panel) expect(Math.round(geometry.panel.width)).toBe(840);
  manifest.push({ screen: new URL(page.url()).pathname, width, theme, state, file, fullFile, geometry, zoom: 1, dpr: 1 });
}
const title = (page: Page) => page.getByRole('textbox', { name: 'Titel', exact: true });
const summary = (page: Page) => page.getByRole('textbox', { name: 'Samenvatting', exact: true });
try {
  const cases = [320, 390, 1440].flatMap(width => ['dark', 'oled', 'light'].map(theme => ({ width, theme })));
  cases.push({ width: 1280, theme: 'dark' }, { width: 1920, theme: 'dark' });
  for (const { width, theme } of cases) {
    await control('reset'); const { context, page, errors, writes } = await pageFor(width, theme);
    await page.goto(`${base}/items/${info.item}`);
    const entry = page.getByRole('link', { name: 'Metadata bewerken', exact: true }); await expect(entry).toBeVisible();
    if (width === 1440 && theme === 'dark') await shot(page, '1440-dark-item-entry', width, theme, 'existing movie detail exposes separate matching and field editing actions');
    await entry.click(); await expect(title(page)).toHaveValue('Grease');
    await shot(page, `${width}-${theme}-initial`, width, theme, 'actual source values, source provenance, unlocked state and typed people');
    if ((width === 1440 && theme === 'dark') || (width === 390 && theme === 'light') || (width === 320 && theme === 'oled')) {
      const result = await new AxeBuilder({ page }).include('.metadata-editor').analyze();
      expect(result.violations.map(v => `${v.id}: ${v.description}`)).toEqual([]);
      checks.push({ width, theme, axeViolations: 0 });
    }
    // Keyboard Space performs an ordinary clear action; discard must issue no write.
    await page.getByRole('button', { name: 'Leegmaken: Jaar', exact: true }).focus(); await page.keyboard.press('Space');
    await expect(page.getByRole('textbox', { name: 'Jaar', exact: true })).toHaveValue('');
    await page.getByRole('button', { name: 'Wijzigingen terugzetten', exact: true }).click(); expect(writes).toHaveLength(0);
    if (width === 1440 && theme === 'dark') {
      const longTitle = 'De laatste overtocht — een uitzonderlijk lange titel met meerdere woorden om de echte veldeditor te beoordelen';
      await title(page).fill(longTitle);
      for (const field of ['Jaar', 'Samenvatting', 'Genres', 'Leeftijdsclassificatie', 'Personen']) await page.getByRole('button', { name: `Leegmaken: ${field}`, exact: true }).click();
      await page.getByRole('button', { name: 'Persoon toevoegen', exact: true }).click();
      await page.getByRole('textbox', { name: 'Naam 1', exact: true }).fill('Synthetic credited performer');
      await page.getByRole('textbox', { name: 'Personage 1 (optioneel)', exact: true }).fill('The navigator');
      await shot(page, '1440-dark-typed-people', width, theme, 'typed actor row with optional character; edits not saved', false);
      await page.getByRole('button', { name: 'Wijzigingen opslaan', exact: true }).click(); await expect(page.getByText('Wijzigingen opgeslagen en vergrendeld.', { exact: true })).toBeVisible();
      await expect(page.getByRole('heading', { level: 2, name: longTitle, exact: true })).toBeVisible();
      await shot(page, '1440-dark-saved', width, theme, 'real PUT confirmation, six manual fields and wrapped long title');
      const fields = await (await api.get(`/pleya/v1/items/${info.item}/metadata`, { headers: { Authorization: `Bearer ${owner}` } })).json();
      expect(fields.fields.year.value).toBe(null); expect(fields.fields.summary.value).toBe(''); expect(fields.fields.genres.value).toEqual([]); expect(fields.fields.people.value).toEqual([{ name: 'Synthetic credited performer', role: 'actor', character: 'The navigator' }]);
      await control('rounds'); await page.reload(); await expect(title(page)).toHaveValue(longTitle); await expect(summary(page)).toHaveValue('');
      await expect(page.getByRole('button', { name: 'Ontgrendelen: Samenvatting', exact: true })).toBeVisible();
      await shot(page, '1440-dark-reloaded-three-rounds', width, theme, 'browser reload and three real fresh runners retain manual locks');
      await control('fallback');
      const refusal = page.waitForResponse(response => response.url().endsWith('/overrides/summary') && response.request().method() === 'DELETE');
      await page.getByRole('button', { name: 'Ontgrendelen: Samenvatting', exact: true }).click(); expect((await refusal).status()).toBe(409);
      await expect(page.getByRole('alert')).toContainText('Je waarde blijft vergrendeld'); await expect(summary(page)).toHaveValue('');
      await expect(page.getByRole('button', { name: 'Ontgrendelen: Samenvatting', exact: true })).toBeEnabled();
      await shot(page, '1440-dark-unlock409', width, theme, 'actual server409 caused by unavailable underlying source; lock retained');
      await control('rounds'); await page.getByRole('button', { name: 'Ontgrendelen: Samenvatting', exact: true }).click();
      await expect(page.getByText('Samenvatting volgt nu de bron.', { exact: true })).toBeVisible(); await expect(summary(page)).toHaveValue(/Synthetic candidate preview/);
      await shot(page, '1440-dark-unlocked', width, theme, 'successful DELETE restores newly observed provider value');
      const status = await (await api.get(`/pleya/v1/items/${info.item}/metadata-match`, { headers: { Authorization: `Bearer ${owner}` } })).json(); expect(status.applied_external_ids.tmdb).toBe(10);
      await page.getByRole('navigation', { name: 'Metadatavelden', exact: true }).getByRole('link', { name: 'Match corrigeren', exact: true }).click();
      await expect(page.getByRole('button', { name: 'Zoeken', exact: true })).toBeVisible(); await expect(page.getByRole('link', { name: 'Metadata bewerken', exact: true })).toBeVisible();
      await shot(page, '1440-dark-matching-preserved', width, theme, 'existing matching/search/artwork preview remains reachable');
    } else if ((width === 320 || width === 390) && theme === 'light') {
      await page.getByRole('button', { name: 'Persoon toevoegen', exact: true }).tap();
      await page.getByRole('textbox', { name: 'Naam 3', exact: true }).fill('Synthetic additional writer'); await page.getByRole('combobox', { name: 'Rol 3', exact: true }).selectOption('writer');
      await shot(page, `${width}-light-people-touch`, width, theme, 'typed people rows in mobile document flow; touch add and native role select', false);
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      const safe = await page.evaluate(() => ({ button: [...document.querySelectorAll('button')].find(button => button.textContent?.trim() === 'Wijzigingen opslaan')!.getBoundingClientRect().bottom, bar: document.querySelector('.tabbar')!.getBoundingClientRect().top }));
      expect(safe.button).toBeLessThanOrEqual(safe.bar);
      await shot(page, `${width}-light-actions-safe`, width, theme, 'save/discard remain above the native mobile tabbar in ordinary document flow', false);
      await page.getByRole('button', { name: 'Wijzigingen terugzetten', exact: true }).tap(); expect(writes).toHaveLength(0);
      if (width === 320) {
        await title(page).fill('Een lange handmatige filmtitel die over meerdere regels blijft passen in de mobiele editor');
        await page.getByRole('button', { name: 'Wijzigingen opslaan', exact: true }).tap();
        await expect(page.getByText('Wijzigingen opgeslagen en vergrendeld.', { exact: true })).toBeVisible();
        await shot(page, '320-light-long-saved-title', width, theme, 'confirmed long title and manual lock at320 without overflow');
      }
    }
    expect(errors).toEqual([]); checks.push({ width, theme, keyboardSpace: true, discardNoWrite: true, noOverflow: true, pageErrors: errors }); await context.close();
  }
  { const { context, page, errors } = await pageFor(390, 'oled');
    await page.goto(`${base}/items/${info.show}`); await page.getByRole('link', { name: 'Metadata bewerken', exact: true }).click();
    await expect(title(page)).not.toHaveValue(''); await expect(page.getByRole('button', { name: 'Wijzigingen opslaan', exact: true })).toBeDisabled();
    await shot(page, '390-oled-series-editor', 390, 'oled', 'real series detail entry opens the same typed editor without changing matching/artwork');
    expect(errors).toEqual([]); checks.push({ scenario: 'series entry', pageErrors: errors }); await context.close(); }
  // The actual admin route gate must refuse a member before any metadata request.
  { const { context, page, errors } = await pageFor(390, 'dark', 'member'); const reads: string[] = [];
    page.on('request', request => { if (request.url().endsWith(`/items/${info.item}/metadata`)) reads.push(request.url()); });
    await page.goto(`${base}/admin/metadata/edit?item=${info.item}`); await expect(page.getByRole('heading', { name: '404', exact: true })).toBeVisible();
    expect(reads).toEqual([]); expect(await page.getByRole('button', { name: 'Wijzigingen opslaan', exact: true }).count()).toBe(0);
    await shot(page, '390-dark-member-refused', 390, 'dark', 'actual admin route404 for member, no metadata read or edit'); expect(errors).toEqual([]); await context.close(); }
  writeFileSync(`${out}/manifest.json`, JSON.stringify({ scope: 'opt-in synthetic loopback Go handlers + built product Web', fixture: info, manifest, checks }, null, 2));
  console.log(JSON.stringify({ screenshots: manifest.length, scenarios: checks.length, checks: 'PASS' }));
} finally { await browser.close(); await api.dispose(); }
