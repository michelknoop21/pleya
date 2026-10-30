import { expect, test } from '@playwright/test';

import { expectNoAxeViolations, expectShell, PASSWORD, SETUP_CODE, USERNAME } from './helpers';

/**
 * Setup en inloggen tegen de echte auth-endpoints. Welke van de twee schermen
 * er komt zegt `GET /info`; de test raadt dat niet.
 */
test('eerste setup eindigt in een cookiesessie zonder leesbaar refreshtoken en zonder tweede sessie', async ({ page, context }) => {
  await page.goto('/');
  const info = await (await page.request.get('/pleya/v1/info')).json();
  test.skip(!info.auth.setup_required || !info.capabilities.cookie_auth, 'alleen op een verse server met cookie_auth');

  await page.waitForURL('**/setup');
  await page.getByLabel('Setup code').fill(SETUP_CODE);
  await page.getByLabel('Username').fill(USERNAME);
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Create owner' }).click();
  await expectShell(page);

  const readable = () => page.evaluate(() => ({ local: { ...localStorage }, session: { ...sessionStorage }, cookie: document.cookie }));
  const assertNothingReadable = async () => {
    const seen = await readable();
    expect(Object.keys(seen.local).filter((key) => /token/i.test(key))).toEqual([]);
    expect(Object.keys(seen.session).filter((key) => /token/i.test(key))).toEqual([]);
    expect(seen.cookie).not.toContain('pleya_refresh');
  };
  await assertNothingReadable();
  const cookie = (await context.cookies()).find((entry) => entry.name === 'pleya_refresh');
  expect(cookie).toMatchObject({ httpOnly: true, sameSite: 'Strict', path: '/pleya/v1/auth/refresh' });

  await page.reload();
  await expectShell(page);
  await assertNothingReadable();

  const login = await page.request.post('/pleya/v1/auth/login', { data: { username: USERNAME, password: PASSWORD } });
  const headers = { Authorization: `Bearer ${(await login.json()).access_token}` };
  const sessions = (await (await page.request.get('/pleya/v1/sessions', { headers })).json()).items as unknown[];
  // De cookiesessie van de browser en deze controlelogin; de setupsessie is ingetrokken.
  expect(sessions).toHaveLength(2);
  await page.request.post('/pleya/v1/auth/logout', { headers });
});

test('setup of inloggen brengt de gebruiker in de app', async ({ page }) => {
  await page.goto('/');

  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };

  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    await expectNoAxeViolations(page, 'setup');

    await page.getByLabel('Setup code').fill(SETUP_CODE);
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
    await page.getByRole('button', { name: 'Create owner' }).click();
  } else {
    await page.waitForURL('**/login');
    await expectNoAxeViolations(page, 'login');

    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in' }).click();
  }

  await expectShell(page);
});

test('een verkeerd wachtwoord geeft de vertaalde foutcode en geen serverbericht', async ({
  page
}) => {
  await page.goto('/');
  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  test.skip(body.auth.setup_required, 'er is nog geen eigenaar om verkeerd bij in te loggen');

  await page.waitForURL('**/login');
  await page.getByLabel('Username').fill(USERNAME);
  await page.getByLabel('Password', { exact: true }).fill('dit-is-niet-het-wachtwoord');
  await page.getByRole('button', { name: 'Sign in' }).click();

  // De regio voor de schermlezer is visueel verborgen; de zichtbare fout staat
  // onder het veld en wordt in de test hieronder gecontroleerd.
  const alert = page.getByRole('alert');
  await expect(alert).toContainText('do not match');
});

test('de fout hangt aan het wachtwoordveld', async ({ page }) => {
  await page.goto('/');
  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  test.skip(body.auth.setup_required, 'er is nog geen eigenaar om verkeerd bij in te loggen');

  await page.waitForURL('**/login');
  const password = page.getByLabel('Password', { exact: true });
  await page.getByLabel('Username').fill(USERNAME);
  await password.fill('dit-is-niet-het-wachtwoord');
  await page.getByRole('button', { name: 'Sign in' }).click();

  // Beeld 12: de fout staat onder het veld en niet in een los vak. Het veld
  // zegt zelf dat het fout is en verwijst naar die tekst, zodat een
  // schermlezer bij focus hoort wat er mis is.
  await expect(password).toHaveAttribute('aria-invalid', 'true');
  const ids = ((await password.getAttribute('aria-describedby')) ?? '').split(/\s+/);
  const described = page.locator(
    ids
      .filter(Boolean)
      .map((id) => `[id="${id}"]`)
      .join(', ') || '#geen-beschrijving'
  );
  await expect(described.first()).toBeVisible();
  await expect(described.first()).toContainText('do not match');
});

test('de sessie overleeft een herlaadbeurt', async ({ page }) => {
  await page.goto('/');
  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };
  test.skip(body.auth.setup_required, 'setup moet eerst gedaan zijn');

  await page.waitForURL('**/login');
  await page.getByLabel('Username').fill(USERNAME);
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expectShell(page);

  await page.reload();
  // Het accesstoken staat alleen in het geheugen; het refreshtoken haalt de
  // sessie terug zonder opnieuw inloggen.
  await expectShell(page);
});

test('cookie-auth keeps credentials out of browser storage and restores after reload', async ({ page }) => {
  const info = await page.request.get('/pleya/v1/info');
  const details = await info.json();
  test.skip(details.capabilities.cookie_auth !== true, 'older server uses the existing token path');
  test.skip(details.auth.setup_required, 'setup must be completed first');
  await page.goto('/');
  await page.waitForURL('**/login');
  await page.getByLabel('Username').fill(USERNAME);
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expectShell(page);
  const storageIsEmpty = () => page.evaluate(() =>
    localStorage.getItem('pleya.refresh_token') === null && sessionStorage.getItem('pleya.access_token') === null);
  expect(await storageIsEmpty()).toBe(true);
  const cookie = (await page.context().cookies()).find(cookie => cookie.name === 'pleya_refresh');
  expect(cookie !== undefined).toBe(true);
  expect(cookie?.httpOnly).toBe(true);
  expect(cookie?.sameSite).toBe('Strict');
  expect(await page.evaluate(() => document.cookie.includes('pleya_refresh='))).toBe(false);
  await page.reload();
  await expectShell(page);
  expect(await storageIsEmpty()).toBe(true);
});
