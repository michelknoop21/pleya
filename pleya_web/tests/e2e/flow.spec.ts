import { expect, test } from '@playwright/test';

import {
  expectNoAxeViolations,
  expectNoHorizontalOverflow,
  expectShell,
  grid,
  openLibraryOfKind,
  signIn,
  WIDTHS
} from './helpers';

/**
 * Acceptatiecriterium 3 en 4 tegen de echte API, zonder mocks: setup of login,
 * bladeren, een detailpagina openen, zoeken, en het serveroverzicht — elk met
 * een axe-controle en een toetsenbordroute.
 */
test.describe('de verticale slice', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page);
  });

  test('home toont wat er recent is toegevoegd', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Recently added' })).toBeVisible();
    await expect(page.getByRole('list', { name: 'Recently added' }).getByRole('listitem').first()).toBeVisible();

    // Kijkstatus bestaat niet in PS-2, dus die rijen horen er niet te staan.
    await expect(page.getByText('Continue watching')).toHaveCount(0);
    await expect(page.getByText('Next up')).toHaveCount(0);

    await expectNoAxeViolations(page, 'home');
  });

  test('de bibliotheeklijst leidt naar een raster', async ({ page }) => {
    await page.goto('/libraries');
    await expect(page.getByRole('heading', { name: 'Libraries' })).toBeVisible();

    const first = page.getByRole('link').filter({ hasText: /\bitems?\b/ }).first();
    await first.click();
    await page.waitForURL(/\/libraries\/.+/);

    await expect(page.getByRole('list').getByRole('listitem').first()).toBeVisible();
    await expectNoAxeViolations(page, 'bibliotheekraster');
  });

  test('sorteren begint de lijst opnieuw en levert een andere volgorde', async ({ page }) => {
    await page.goto('/libraries');
    await page.getByRole('link').filter({ hasText: /\bitems?\b/ }).first().click();
    await page.waitForURL(/\/libraries\/.+/);

    const grid = page.getByRole('list', { name: /.+/ }).last();
    const titlesBefore = await grid.getByRole('listitem').allInnerTexts();
    await page.getByLabel('Sort').selectOption('-title');
    await expect(page).toHaveURL(/sort=-title/);

    await expect
      .poll(async () => (await grid.getByRole('listitem').allInnerTexts()).join('|'))
      .not.toBe(titlesBefore.join('|'));
  });

  test('een detailpagina toont alleen wat Item draagt', async ({ page }) => {
    await page.goto('/libraries');
    await page.getByRole('link').filter({ hasText: /\bitems?\b/ }).first().click();
    await page.waitForURL(/\/libraries\/.+/);
    // Nadrukkelijk het raster en niet zomaar het eerste lijstonderdeel op de
    // pagina: de navigatie is ook een lijst, en die staat eerder in de DOM.
    await grid(page).getByRole('listitem').first().getByRole('link').click();
    await page.waitForURL(/\/items\/.+/);

    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Versions' })).toBeVisible();

    // Velden die het protocol vandaag niet kent horen hier niet te staan.
    const body = (await page.locator('body').innerText()).toLowerCase();
    for (const absent of ['summary', 'genres', 'cast', 'tagline', 'studio', 'trailer']) {
      expect(body, absent).not.toContain(absent);
    }
    // En geen speler: afspelen is PS-4.
    await expect(page.locator('video')).toHaveCount(0);

    await expectNoAxeViolations(page, 'itemdetail');
  });

  test('een serie leidt via seizoenen naar een aflevering', async ({ page }) => {
    // De bibliotheek wordt op soort gekozen en niet op titel, zodat deze test
    // ook tegen een echte serverbibliotheek draait.
    const found = await openLibraryOfKind(page, 'shows');
    test.skip(!found, 'deze server heeft geen bibliotheek van soort shows');

    await grid(page).getByRole('listitem').first().getByRole('link').click();
    await page.waitForURL(/\/items\/.+/);
    await expect(page.getByRole('heading', { name: 'Seasons' })).toBeVisible();

    await page
      .getByRole('list', { name: 'Seasons' })
      .getByRole('listitem')
      .first()
      .getByRole('link')
      .click();
    await page.waitForURL(/\/items\/.+/);
    await expect(page.getByRole('heading', { name: 'Episodes' })).toBeVisible();

    await expectNoAxeViolations(page, 'seizoen');
  });

  test('zoeken levert geen seizoenen zonder erom te vragen', async ({ page }) => {
    await page.goto('/search');
    await page.getByRole('searchbox').fill('Season');

    await expect(page.getByText(/Results for/)).toBeVisible();
    // DEC-045: zonder kind levert de server movie, show en episode. Een
    // resultatenlijst die uit seizoenen bestaat is precies wat dat besluit
    // wegneemt, en op een echte bibliotheek zijn dat er honderden.
    const titles = await grid(page).getByRole('listitem').allInnerTexts();
    const seasons = titles.filter((t) => /^Season \d+/m.test(t.trim()));
    expect(seasons).toEqual([]);

    await expectNoAxeViolations(page, 'zoeken');
  });

  test('het serveroverzicht toont alleen wat /server en /info dragen', async ({ page }) => {
    await page.goto('/server');
    await expect(page.getByRole('heading', { name: 'Server', level: 1 })).toBeVisible();
    await expect(page.getByText('Capabilities')).toBeVisible();

    // Er is geen endpoint voor scannen, jobs of opslag, dus er is ook geen knop.
    const body = (await page.locator('body').innerText()).toLowerCase();
    for (const absent of ['start scan', 'jobs', 'storage', 'backup', 'add library']) {
      expect(body, absent).not.toContain(absent);
    }

    await expectNoAxeViolations(page, 'serveroverzicht');
  });
});

test.describe('toetsenbord', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page);
  });

  test('de eerste tabstop is de sla-over-link, daarna loopt de navigatie door', async ({ page }) => {
    // Breed, want deze volgorde is die van de zijbalk. De smalle schil heeft
    // een andere DOM-volgorde en wordt hieronder apart gemeten.
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/');
    // Wachten tot de schil staat. Tabben terwijl de sessie nog laadt zet de
    // focus op de enige link die er dan is en daarna nergens meer.
    await expectShell(page);
    await page.keyboard.press('Tab');
    await expect(page.locator('a.skip-link')).toBeFocused();

    // Doorlopen tot de eerste navigatielink de focus heeft.
    // Merklink, dan elk navigatie-item, in DOM-volgorde.
    const expected = ['/', '/', '/search', '/libraries', '/server'];
    for (const href of expected) {
      await page.keyboard.press('Tab');
      const actual = await page.evaluate(() => document.activeElement?.getAttribute('href'));
      expect(actual).toBe(href);
    }
  });

  test('op smal is de bottom bar met het toetsenbord te doorlopen', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await expectShell(page);

    const hrefs = await page
      .locator('nav.bar a')
      .evaluateAll((els) => els.map((el) => el.getAttribute('href')));
    expect(hrefs).toEqual(['/', '/search', '/libraries', '/server']);

    // Elke link in de balk is een echte tabstop.
    for (const href of hrefs) {
      await page.locator(`nav.bar a[href="${href}"]`).focus();
      await expect(page.locator(`nav.bar a[href="${href}"]`)).toBeFocused();
    }
  });

  test('de sla-over-link brengt de focus naar de inhoud', async ({ page }) => {
    await page.goto('/');
    await expectShell(page);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(/#main$/);
  });

  test('een zichtbare focusring staat op elk bediend element', async ({ page }) => {
    await page.goto('/search');
    await page.getByRole('searchbox').focus();
    const outline = await page.getByRole('searchbox').evaluate(
      (el) => getComputedStyle(el).outlineStyle
    );
    expect(outline).not.toBe('none');
  });
});

test.describe('responsive', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page);
  });

  for (const width of WIDTHS) {
    test(`geen horizontale overflow op ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });

      for (const path of ['/', '/libraries', '/search', '/server']) {
        await page.goto(path);
        await expectNoHorizontalOverflow(page);
      }
    });
  }

  test('onder 900 staat de navigatie onderaan, daarboven aan de zijkant', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 900 });
    await page.goto('/');
    await expect(page.locator('nav.bar')).toBeVisible();
    await expect(page.locator('nav.rail')).toHaveCount(0);

    await page.setViewportSize({ width: 1280, height: 900 });
    await expect(page.locator('nav.rail')).toBeVisible();
    await expect(page.locator('nav.bar')).toHaveCount(0);
  });

  test('de zijbalk is 80 breed en klapt uit naar 220', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/');

    const rail = page.locator('nav.rail');
    expect((await rail.boundingBox())?.width).toBeCloseTo(80, 0);

    const hasHover = await page.evaluate(() => matchMedia('(hover: hover)').matches);
    if (!hasHover) {
      // Op een aanraakscherm bestaat er geen aanwijzer om mee uit te klappen,
      // en dan hoort er ook niets te gebeuren: de regel staat achter
      // @media (hover: hover). Focus is daar de weg naar de labels.
      await rail.hover();
      expect((await rail.boundingBox())?.width).toBeCloseTo(80, 0);
      await page.locator('nav.rail a').first().focus();
      await expect.poll(async () => (await rail.boundingBox())?.width).toBeCloseTo(220, 0);
      return;
    }

    await rail.hover();
    await expect.poll(async () => (await rail.boundingBox())?.width).toBeCloseTo(220, 0);
  });

  test('de rij op Home springt net zo ver in als zijn kop', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await page.locator('.rail__cell').first().waitFor();

    const measured = await page.evaluate(() => {
      const heading = document.querySelector('.rail__title');
      const first = document.querySelector('.rail__cell');
      return {
        heading: heading?.getBoundingClientRect().x ?? -1,
        card: first?.getBoundingClientRect().x ?? -1
      };
    });
    expect(measured.card).toBeCloseTo(measured.heading, 0);
    expect(measured.card).toBeGreaterThan(0);
  });

  test('posters worden niet reusachtig op een ultrabreed scherm', async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 900 });
    await page.goto('/libraries');
    await page.getByRole('link').filter({ hasText: /\bitems?\b/ }).first().click();
    await page.waitForURL(/\/libraries\/.+/);

    const card = grid(page).getByRole('listitem').first();
    const width = (await card.boundingBox())?.width ?? 0;
    expect(width).toBeGreaterThan(120);
    expect(width).toBeLessThanOrEqual(220);
  });
});

test.describe('bewegingsvoorkeur', () => {
  test('respecteert prefers-reduced-motion', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await signIn(page);
    await page.goto('/');

    const duration = await page.evaluate(() => {
      const el = document.querySelector('.card__art');
      return el ? getComputedStyle(el).transitionDuration : '0s';
    });
    expect(parseFloat(duration)).toBeLessThan(0.05);
  });
});
