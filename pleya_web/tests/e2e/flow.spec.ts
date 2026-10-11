import { expect, test } from '@playwright/test';

import {
  expectNoAxeViolations,
  expectNoHorizontalOverflow,
  expectShell,
  grid,
  label,
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

  test('de filtergroep op zoeken heeft een eigen naam en zet aria-pressed', async ({ page }) => {
    await page.goto('/search');

    // Niet "Alles": dat is de naam van de eerste chip, geen groepsnaam.
    const group = page.getByRole('group', { name: label('en', 'search.filters.label'), exact: true });
    await expect(group).toBeVisible();

    const all = group.getByRole('button', { name: 'All', exact: true });
    const movies = group.getByRole('button', { name: 'Movies', exact: true });
    await expect(all).toHaveAttribute('aria-pressed', 'true');
    await expect(movies).toHaveAttribute('aria-pressed', 'false');

    await movies.click();
    await expect(movies).toHaveAttribute('aria-pressed', 'true');
    await expect(all).toHaveAttribute('aria-pressed', 'false');
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

    // Merklink, dan elk slot in DOM-volgorde (Home, Series, Films, Mijn
    // Pleya), dan de zoekactie. Bibliotheek-ids zijn per stack anders, dus de
    // slots voor Series en Films worden op hun pad-voorvoegsel getoetst.
    const expected: (string | RegExp)[] = [
      '/',
      '/',
      /^\/libraries\/[0-9a-f-]+$/,
      /^\/libraries\/[0-9a-f-]+$/,
      '/server',
      '/search'
    ];
    for (const href of expected) {
      await page.keyboard.press('Tab');
      const actual = await page.evaluate(() => document.activeElement?.getAttribute('href'));
      if (typeof href === 'string') expect(actual).toBe(href);
      else expect(actual).toMatch(href);
    }
  });

  test('op smal is de tabbalk met het toetsenbord te doorlopen', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await expectShell(page);

    const links = page.locator('nav.tabbar a');
    const hrefs = await links.evaluateAll((els) => els.map((el) => el.getAttribute('href')));
    expect(hrefs).toHaveLength(4);
    expect(hrefs[0]).toBe('/');
    expect(hrefs[1]).toMatch(/^\/libraries\//);
    expect(hrefs[2]).toMatch(/^\/libraries\//);
    expect(hrefs[3]).toBe('/server');

    // Elke link in de balk is een echte tabstop.
    for (let n = 0; n < hrefs.length; n++) {
      await links.nth(n).focus();
      await expect(links.nth(n)).toBeFocused();
    }
  });

  test('de sla-over-link brengt de focus naar de inhoud', async ({ page }) => {
    await page.goto('/');
    await expectShell(page);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(/#main$/);
  });

  test('focus is zichtbaar op het zoekveld en op een chip', async ({ page }) => {
    await page.goto('/search');
    const box = page.getByRole('searchbox');
    const border = () => box.evaluate((el) => getComputedStyle(el).borderTopColor);

    await box.focus();
    // Een tekstvak toont focus als een inkt-rand zonder ring (Field, beeld 23).
    // De rand loopt over een korte overgang, dus pollen in plaats van één meting.
    const ink = await page.evaluate(() => {
      const probe = document.createElement('span');
      probe.style.color = 'var(--ink)';
      document.body.append(probe);
      const resolved = getComputedStyle(probe).color;
      probe.remove();
      return resolved;
    });
    await expect.poll(border).toBe(ink);

    // Een chip is een knop en houdt wel de ring.
    await page.keyboard.press('Tab');
    const chip = page.locator('.chips__hit:focus-visible .chip');
    await expect(chip).toBeVisible();
    expect(await chip.evaluate((el) => getComputedStyle(el).outlineStyle)).not.toBe('none');
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

  test('onder 900 staat de navigatie onderaan, daarboven bovenin', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 900 });
    await page.goto('/');
    await expect(page.locator('nav.tabbar')).toBeVisible();
    await expect(page.locator('nav.topnav')).toHaveCount(0);

    await page.setViewportSize({ width: 1280, height: 900 });
    await expect(page.locator('nav.topnav')).toBeVisible();
    await expect(page.locator('nav.tabbar')).toHaveCount(0);
  });

  test('de bovenbalk is 64 hoog en blijft bovenaan bij scrollen', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 600 });
    await page.goto('/');

    const bar = page.locator('nav.topnav');
    expect((await bar.boundingBox())?.height).toBeCloseTo(64, 0);

    await page.evaluate(() => window.scrollTo(0, 400));
    expect((await bar.boundingBox())?.y).toBeCloseTo(0, 0);
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

  // Beeld 15: het skelet neemt de ruimte in van wat erna komt. Verschuift de
  // eerste rij zodra de data binnenkomt, dan springt de pagina onder de muis of
  // de vinger van iemand die al wilde klikken.
  for (const width of [393, 1280]) {
    test(`de eerste rij op Home verspringt niet als de data binnenkomt (${width}px)`, async ({
      page
    }) => {
      await page.setViewportSize({ width, height: 900 });

      // De hub-aanvraag blijft hangen tot het skelet gemeten is.
      let release: () => void = () => undefined;
      const held = new Promise<void>((resolve) => (release = resolve));
      await page.route('**/pleya/v1/hubs/**', async (route) => {
        await held;
        await route.continue().catch(() => undefined);
      });

      const firstRow = (rail: string, art: string) =>
        page.evaluate(
          ([railSelector, artSelector]) => ({
            rail: document.querySelector(railSelector)?.getBoundingClientRect().top ?? -1,
            art: document.querySelector(artSelector)?.getBoundingClientRect().top ?? -1
          }),
          [rail, art] as const
        );

      await page.goto('/');
      await page.locator('.skp__rail').first().waitFor();
      const skeleton = await firstRow('.skp__rail', '.skp__cell .skc__art');

      release();
      await page.locator('.rail__cell').first().waitFor();
      const loaded = await firstRow('section.rail', '.rail__cell .card__art');
      await page.unroute('**/pleya/v1/hubs/**');

      const seen = JSON.stringify({ skeleton, loaded });
      expect(skeleton.rail, 'het skelet heeft geen rij getekend').toBeGreaterThan(0);
      expect(Math.abs(loaded.rail - skeleton.rail), `kop van de rij ${seen}`).toBeLessThanOrEqual(2);
      expect(Math.abs(loaded.art - skeleton.art), `eerste poster ${seen}`).toBeLessThanOrEqual(2);
    });
  }

  // Onder 900 staat het aantal op een eigen regel onder de titel. Komt het pas
  // met de eerste pagina, dan zakt het raster een regel; de route reserveert
  // die regel, en deze meting bewaakt dat.
  for (const width of [393, 1280]) {
    test(`het raster van een bibliotheek verspringt niet als het aantal binnenkomt (${width}px)`, async ({
      page
    }) => {
      await page.setViewportSize({ width, height: 900 });
      await page.goto('/libraries');
      const href = await page
        .getByRole('link')
        .filter({ hasText: /\bitems?\b/ })
        .first()
        .getAttribute('href');

      let release: () => void = () => undefined;
      const held = new Promise<void>((resolve) => (release = resolve));
      await page.route('**/pleya/v1/libraries/*/items*', async (route) => {
        await held;
        await route.continue().catch(() => undefined);
      });

      // Client-side navigeren: een harde load zou de sessie opnieuw opbouwen.
      await page.locator(`a[href="${href}"]`).first().click();
      await page.locator('.skp__grid').waitFor();
      const top = (selector: string) =>
        page.evaluate(
          (sel) => document.querySelector(sel)?.getBoundingClientRect().top ?? -1,
          selector
        );
      const skeleton = await top('.skp__grid > *');

      release();
      await page.locator('ul.grid li').first().waitFor();
      const loaded = await top('ul.grid li');
      await page.unroute('**/pleya/v1/libraries/*/items*');

      expect(skeleton, 'het skelet heeft geen raster getekend').toBeGreaterThan(0);
      expect(
        Math.abs(loaded - skeleton),
        `eerste kaart skelet ${skeleton} geladen ${loaded}`
      ).toBeLessThanOrEqual(2);
    });
  }

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
