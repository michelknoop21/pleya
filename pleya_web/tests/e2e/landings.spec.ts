import { expect, test } from '@playwright/test';
import { expectNoAxeViolations, expectNoHorizontalOverflow, signIn } from './helpers';

test('Films navigation opens its landing and rows lead to the catalog', async ({ page }) => {
  await signIn(page);
  const films = page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'Films', exact: true });
  test.skip(!await films.count(), 'requires a movie library');
  await films.click();
  await expect(page).toHaveURL(/\/films$/);
  await expect(page.getByRole('heading', { name: 'Films', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Continue watching', exact: true })).toHaveCount(0);
  const recent = page.locator('section.rail').filter({ has: page.getByRole('heading', { name: /^Recently added/ }) }).first();
  await expect(recent).toBeVisible();
  await expect(films).toHaveAttribute('aria-current', 'page');
  await expectNoAxeViolations(page, 'Films landing');
  await expectNoHorizontalOverflow(page);
  await recent.getByRole('link', { name: 'View all', exact: true }).click();
  await expect(page).toHaveURL(/\/libraries\/[^?]+\?sort=-added_at$/);
  await expect(page.getByRole('combobox', { name: 'Sort' })).toHaveValue('-added_at');
});

test('an old server receives only supported landing requests', async ({ page }) => {
  await page.route('**/pleya/v1/info', async route => {
    const response = await route.fetch();
    const body = await response.json();
    await route.fulfill({ response, json: { ...body, capabilities: { ...body.capabilities, filters: false, watch_state: false } } });
  });
  const unsupported: string[] = [];
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.pathname.endsWith('/facets') || url.searchParams.has('watch') || url.searchParams.has('genre')) unsupported.push(url.pathname + url.search);
  });
  await signIn(page);
  await page.goto('/films');
  await expect(page.getByRole('heading', { name: /^Recently added/ }).first()).toBeVisible();
  await expect(page.getByRole('heading', { name: /^Not watched/ })).toHaveCount(0);
  expect(unsupported).toEqual([]);
});
