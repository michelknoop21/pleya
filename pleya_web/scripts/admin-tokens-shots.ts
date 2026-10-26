/**
 * Opnamen van Agents en API-tokens (S10.6, scherm 34) op de vaste breedtes
 * 1920 bij 1080, 1440, 1280, 390 en 320, in de stijl van admin-users-shots.ts:
 * per breedte herladen, de horizontale paginaoverloop meten, een jpeg op
 * kwaliteit 70.
 *
 *   PLEYA_E2E_BASE_URL=http://127.0.0.1:5173 bun run scripts/admin-tokens-shots.ts [uitvoermap]
 *
 * Dit script praat niet met een echte server en gebruikt geen echte tokens:
 * elke aanvraag naar `/pleya/v1` wordt in de browser beantwoord met verzonnen
 * gegevens (Michel, Sanne, Kids en vier tokens), het geheim is een duidelijk
 * nep-waarde, en elke schrijfaanvraag wordt afgebroken en geteld. Alleen
 * `POST /auth/api-tokens` krijgt een nepantwoord, om het eenmalige paneel te
 * kunnen opnemen; ook dat gaat nooit naar een server. De beelden dragen
 * daarom `-nagebootst`.
 */
import { chromium, type Page, type Route } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { setLocale, t } from '../src/lib/i18n';
import { localeContextOptions } from './shot-locale';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:5173';
const OUT = process.argv[2] ?? '../docs/qa/s10-tokens';
const WIDTHS = [1920, 1440, 1280, 390, 320];
const height = (w: number) => (w >= 1920 ? 1080 : 900);
const NEP_SECRET = 'plyat1_NEP-GEEN-ECHT-GEHEIM-0123456789abcdef';

setLocale('nl');
mkdirSync(OUT, { recursive: true });

const NOW = Date.now();
const iso = (minutesAgo: number) => new Date(NOW - minutesAgo * 60_000).toISOString();
const inDays = (days: number) => new Date(NOW + days * 86_400_000).toISOString();

const USERS = [
  { id: 'u1', username: 'Michel', role: 'owner' },
  { id: 'u2', username: 'Sanne', role: 'member' },
  { id: 'u3', username: 'Kids', role: 'restricted' }
];
const tok = (id: string, user: string, name: string, scope: string, seen: number, days: number) => ({
  id,
  user_id: user,
  name,
  scope,
  created_at: iso(60 * 24 * 30),
  last_seen_at: iso(seen),
  expires_at: inDays(days)
});
const TOKENS: Record<string, unknown[]> = {
  u1: [
    tok('t1', 'u1', 'Claude Code op de Mac', 'admin', 2, 89),
    tok('t2', 'u1', 'Nachtelijke scanrobot', 'maintenance', 60 * 11, 12)
  ],
  u2: [tok('t3', 'u2', 'Sannes leesassistent', 'read', 60 * 27, 400)],
  u3: []
};
const AUDIT = [
  { id: 'a1', at: iso(40), source: 'mcp', operation: 'startLibraryScan', target: 'l2', outcome: 'ok', user_id: 'u1', session_id: 't1' },
  { id: 'a2', at: iso(44), source: 'mcp', operation: 'patchSettings', target: 'scan_interval', outcome: 'ok', user_id: 'u1', session_id: 't1' },
  { id: 'a3', at: iso(45), source: 'mcp', operation: 'deleteLibrary', target: 'l3', outcome: 'denied', user_id: 'u1', session_id: 't1' },
  { id: 'a4', at: iso(60 * 11), source: 'mcp', operation: 'startLibraryScan', target: 'l1', outcome: 'ok', user_id: 'u1', session_id: 't2' }
];

let apiTokens = true;
let mcp: unknown = { enabled: true, url: 'https://web.pleya.app/mcp', tool_count: 31 };

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

const blocked: string[] = [];
const unknown = new Set<string>();
const errors: string[] = [];

const browser = await chromium.launch();
const context = await browser.newContext({
  ...localeContextOptions('nl'),
  viewport: { width: 1440, height: 900 }
});
const page = await context.newPage();
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

await context.route('**/pleya/v1/**', async (route) => {
  const request = route.request();
  const url = new URL(request.url());
  const path = url.pathname.slice('/pleya/v1'.length);
  if (request.method() === 'POST' && path === '/auth/login') {
    return json(route, { access_token: 'nep', refresh_token: 'nep', expires_in_ms: 3_600_000 });
  }
  if (request.method() === 'POST' && path === '/auth/api-tokens') {
    const body = request.postDataJSON() as { name: string; scope: string };
    return json(
      route,
      { token: tok('t9', 'u1', body.name, body.scope, 0, 90), secret: NEP_SECRET },
      201
    );
  }
  if (request.method() !== 'GET') {
    blocked.push(`${request.method()} ${path}`);
    return route.abort();
  }
  switch (path) {
    case '/info':
      return json(route, {
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 's1', setup_accepts_name: false },
        capabilities: {
          browse: true,
          search: true,
          artwork: true,
          watch_state: true,
          users: true,
          administration: true,
          api_tokens: apiTokens
        },
        auth: { methods: ['password'], setup_required: false }
      });
    case '/server':
      return json(route, { id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: iso(9000), mcp });
    case '/libraries':
      return json(route, { items: [] });
    case '/users/me':
      return json(route, USERS[0]);
    case '/users':
      return json(route, { items: USERS });
    case '/auth/api-tokens':
      return json(route, { items: TOKENS[url.searchParams.get('user_id') ?? ''] ?? [] });
    case '/hubs/recently_added':
      return json(route, { items: [] });
    case '/sessions':
      return json(route, { items: [] });
    case '/settings':
      return json(route, {
        server_name: { value: 'Pleya-server', source: 'env' },
        access_token_ttl: { value: '15m0s', source: 'env' },
        refresh_token_ttl: { value: '720h0m0s', source: 'env' },
        stream_token_ttl: { value: '5m0s', source: 'env' },
        stream_session_ttl: { value: '30m0s', source: 'env' },
        max_stream_sessions: { value: 8, source: 'env' },
        public_url: { value: 'https://web.pleya.app', source: 'env' },
        web_origin: { value: '', source: 'env' },
        cors_origins: { value: [], source: 'env' }
      });
    case '/audit':
      return json(route, { items: url.searchParams.get('source') === 'mcp' ? AUDIT : [], next_cursor: null });
    default:
      unknown.add(path);
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

const AGENTS = '/admin/security/agents';
const fillName = (p: Page, value: string) => p.getByLabel(t('admin.tok.form.name'), { exact: false }).first().fill(value);
const submit = (p: Page) => p.getByRole('button', { name: t('admin.tok.form.submit') }).click();

await shoot(AGENTS, 'agents-nagebootst');
await shoot('/admin/security', 'beveiliging-ingang-nagebootst');
await shoot(AGENTS, 'agents-geheim-nagebootst', async (p) => {
  await fillName(p, 'Home Assistant');
  await submit(p);
  await p.getByTestId('token-secret').waitFor();
  await p.evaluate(() => window.scrollTo(0, 0));
  await p.waitForTimeout(300);
});
await shoot(AGENTS, 'agents-beheer-bevestigen-nagebootst', async (p) => {
  await fillName(p, 'Beheeragent');
  await p.getByRole('radio', { name: /^Beheer/ }).check({ force: true });
  await submit(p);
  await p.getByRole('dialog').waitFor();
  await p.waitForTimeout(300);
});
await shoot(AGENTS, 'agents-intrekken-nagebootst', async (p) => {
  await p.getByRole('button', { name: t('admin.tok.revokeNamed', { name: 'Sannes leesassistent' }) }).click();
  await p.getByRole('dialog').waitFor();
  await p.waitForTimeout(300);
});
await shoot(AGENTS, 'agents-naam-ontbreekt-nagebootst', async (p) => {
  await submit(p);
  await p.getByLabel(t('admin.tok.form.name'), { exact: false }).first().scrollIntoViewIfNeeded();
  await p.waitForTimeout(300);
});

mcp = { enabled: false, tool_count: 0 };
await shoot(AGENTS, 'agents-mcp-uit-nagebootst');
mcp = { enabled: true, url: 'https://web.pleya.app/mcp', tool_count: 31 };

apiTokens = false;
await shoot(AGENTS, 'agents-niet-ondersteund-nagebootst');
apiTokens = true;

console.log(`consolefouten: ${errors.length}`);
for (const e of errors) console.log(`  ${e}`);
console.log(`onbekende paden (404 van de mock): ${[...unknown].join(', ') || 'geen'}`);
console.log(`afgebroken schrijfaanvragen: ${blocked.length}`);
for (const b of blocked) console.log(`  ${b}`);
await browser.close();
