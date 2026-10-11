import { expect, test } from '@playwright/test';

import { expectNoAxeViolations, expectShell, PASSWORD, SETUP_CODE, USERNAME } from './helpers';

/**
 * Setup en inloggen tegen de echte auth-endpoints. Welke van de twee schermen
 * er komt zegt `GET /info`; de test raadt dat niet.
 */
test('setup of inloggen brengt de gebruiker in de app', async ({ page }) => {
  await page.goto('/');

  const info = await page.request.get('/pleya/v1/info');
  const body = (await info.json()) as { auth: { setup_required: boolean } };

  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    await expectNoAxeViolations(page, 'setup');

    await page.getByLabel('Setup code').fill(SETUP_CODE);
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password', { exact: false }).fill(PASSWORD);
    await page.getByRole('button', { name: 'Create owner' }).click();
  } else {
    await page.waitForURL('**/login');
    await expectNoAxeViolations(page, 'login');

    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password').fill(PASSWORD);
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
  await page.getByLabel('Password').fill('dit-is-niet-het-wachtwoord');
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
  const password = page.getByLabel('Password');
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
  await page.getByLabel('Password').fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expectShell(page);

  await page.reload();
  // Het accesstoken staat alleen in het geheugen; het refreshtoken haalt de
  // sessie terug zonder opnieuw inloggen.
  await expectShell(page);
});
