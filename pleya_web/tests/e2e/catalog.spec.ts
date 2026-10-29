import { expect, test } from '@playwright/test';
import { expectNoAxeViolations, expectNoHorizontalOverflow, openLibraryOfKind, signIn } from './helpers';

test.beforeEach(async ({ page }) => { await signIn(page); });

test('catalog filters follow URL history and clear an empty result', async ({ page }) => {
  const path = await openLibraryOfKind(page, 'movies');
  test.skip(!path, 'requires a movie library');
  await expect(page.getByRole('combobox', { name: 'Sort' })).toBeVisible();
  const filters = page.getByRole('button', { name: 'Filters', exact: true });
  test.skip(!await filters.count(), 'requires server filters');
  await expect(filters).toBeEnabled();
  await page.getByRole('combobox', { name: 'Sort' }).selectOption('-duration');
  await expect(page).toHaveURL(/sort=-duration/);
  await filters.click();
  const dialog = page.getByRole('dialog', { name: 'Filters' });
  const watched = dialog.getByRole('button', { name: /^Not watched/ });
  test.skip(!await watched.count(), 'requires watch state');
  await watched.click();
  await dialog.getByRole('button', { name: 'Apply filters' }).click();
  await expect(page).toHaveURL(/watch=unwatched/);
  const active = page.getByRole('group', { name: 'Active filters' });
  await expect(active).toBeVisible();
  await page.goBack();
  await expect(active).not.toBeVisible();
  await expect(page.getByRole('combobox', { name: 'Sort' })).toHaveValue('-duration');
  await page.goForward();
  await expect(active).toBeVisible();
  await page.goto(`${path}?genre=__pleya_test_no_such_genre__`);
  await expect(page.getByText('No titles match these filters.')).toBeVisible();
  await page.getByRole('main').getByRole('button', { name: 'Clear filters', exact: true }).last().click();
  await expect(page).not.toHaveURL(/genre=/);
  await expect(page.getByText('No titles match these filters.')).not.toBeVisible();
});

test('filter dialog actions cover fixed navigation and restore keyboard focus', async ({ page }) => {
  const path = await openLibraryOfKind(page, 'movies');
  test.skip(!path, 'requires a movie library');
  await expect(page.getByRole('combobox', { name: 'Sort' })).toBeVisible();
  const filters = page.getByRole('button', { name: 'Filters', exact: true });
  test.skip(!await filters.count(), 'requires server filters');
  await expect(filters).toBeEnabled();
  await filters.click();
  const dialog = page.getByRole('dialog', { name: 'Filters' });
  const cancel = dialog.getByRole('button', { name: 'Cancel', exact: true });
  await expect(cancel).toBeVisible();
  expect(await cancel.evaluate(button => {
    const box = button.getBoundingClientRect();
    return button.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
  })).toBe(true);
  await expectNoAxeViolations(page, 'catalog filters');
  await expectNoHorizontalOverflow(page);
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(filters).toBeFocused();
});
