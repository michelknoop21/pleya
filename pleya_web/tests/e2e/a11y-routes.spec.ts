import { expect, test, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

import type { Locale } from '../../src/lib/i18n';
import {
  AXE_TAGS,
  axeMessage,
  grid,
  label,
  openLibraryOfKind,
  setupRequired,
  signIn,
  WIDTHS
} from './helpers';

/**
 * De a11y-meetlat van S7.6: axe, horizontale overloop en de documenttaal, op
 * elke route, op de vijf breedtes van de northstar en in beide talen.
 *
 * Eén ingelogde test per taal met zachte asserties, zodat één run de hele
 * matrix rapporteert in plaats van te stoppen bij de eerste rode cel, en er
 * niet per doel opnieuw ingelogd wordt.
 *
 * De bestandsnaam staat alfabetisch vóór `auth.spec.ts`. Dat is opzet: de
 * setupmeting heeft een server zonder eigenaar nodig, en de eerste spec die
 * inlogt maakt die eigenaar aan. De setuptests staan daarom ook bovenaan dit
 * bestand, vóór de ingelogde test die hetzelfde doet.
 */

const LOCALES: { locale: Locale; context: string }[] = [
  { locale: 'en', context: 'en-US' },
  { locale: 'nl', context: 'nl-NL' }
];

const NO_HITS = 'zqxjvw-geen-treffer';

type Target = { name: string; path: string };

/**
 * Elke test begint met een schone taalkeuze en het donkere thema.
 *
 * De taal komt dan uit de browsertaal van de context (`test.use({ locale })`),
 * zoals bij een eerste bezoek. Een bewaarde keuze uit een eerdere test zou dat
 * overstemmen; dezelfde vorm als `forgetStoredLocale` in `scripts/shot-locale.ts`.
 */
async function prepare(page: Page, projectName: string): Promise<void> {
  test.skip(
    projectName !== 'chromium',
    'de spec zet zelf vijf breedtes; in het mobiele project zou hij dezelfde matrix nog eens meten'
  );
  test.setTimeout(300_000);
  await page.addInitScript(() => {
    try {
      localStorage.removeItem('pleya.locale');
      localStorage.setItem('pleya.theme', 'dark');
    } catch {
      // Opslag geweigerd: dan beslist de browsertaal al, en het thema volgt de app.
    }
  });
}

/** Wacht tot er niets meer laadt. Bij een bewust vastgehouden laadstaat niet. */
async function settle(page: Page): Promise<void> {
  await page.waitForLoadState('networkidle');
  await expect(page.locator('[aria-busy="true"]')).toHaveCount(0, { timeout: 15_000 });
}

/**
 * Meet één doel op alle vijf breedtes: axe, overloop en `lang`, en binnen de
 * schil ook de naam van de hoofdnavigatie.
 *
 * Die laatste staat er omdat axe een naamloze navigatie niet afkeurt zolang er
 * maar één is, en onder 900 px is de tabbalk de enige. Een tabbalk zonder naam
 * viel daardoor door de axe-meting heen; deze controle vangt hem, in de taal van
 * de run.
 *
 * Een overtreding wordt naast de zachte assertie ook als annotatie vastgelegd,
 * zodat de nulmeting uit de JSON-uitvoer van één run als tabel op te bouwen is.
 * `incomplete` van `color-contrast` faalt niet: dat is tekst over artwork, die
 * axe niet kan beoordelen. Die plekken gaan naar de annotaties en de gate meet
 * ze met pixels.
 */
async function measure(
  page: Page,
  target: string,
  locale: Locale,
  options: { settle?: boolean; shell?: boolean } = {}
): Promise<void> {
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    if (options.settle !== false) await settle(page);
    const where = `${target} [${locale}]`;

    const results = await new AxeBuilder({ page }).withTags(AXE_TAGS).analyze();
    for (const v of results.violations) {
      test.info().annotations.push({
        type: 'axe-overtreding',
        description: `${target}|${width}|${locale}|${v.id}|${v.nodes.length}`
      });
    }
    const ids = results.violations.map((v) => v.id);
    expect.soft(ids, axeMessage(page, results.violations, where)).toEqual([]);

    if (options.shell !== false) {
      const nav = page.getByRole('navigation', { name: label(locale, 'nav.primary'), exact: true });
      await expect.soft(nav, `hoofdnavigatie met naam op ${where} bij ${width}px`).toHaveCount(1);
    }

    const contrast = results.incomplete.find((r) => r.id === 'color-contrast');
    if (contrast) {
      test.info().annotations.push({
        type: 'contrast-incomplete',
        description: `${target}|${width}|${locale}|${contrast.nodes.map((n) => n.target.join(' ')).join(', ')}`
      });
    }

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    expect.soft(overflow, `horizontale overloop op ${where} bij ${width}px`).toBeLessThanOrEqual(1);

    const lang = await page.evaluate(() => document.documentElement.lang);
    expect.soft(lang, `documenttaal op ${where} bij ${width}px`).toBe(locale);
  }
}

/** Het pad van de eerste kaart in het raster, of `null` als het raster leeg is. */
async function firstCardHref(page: Page): Promise<string | null> {
  const link = grid(page).getByRole('listitem').first().getByRole('link');
  await link.waitFor({ timeout: 15_000 }).catch(() => undefined);
  return (await link.count()) ? link.getAttribute('href') : null;
}

/**
 * Zoekt de doelen op tijdens de run.
 *
 * Niets uit de testdata geraden: een film, een serie en een seizoen komen uit
 * de eerste bibliotheek van hun soort, en de zoekterm met treffers is het
 * eerste woord van de gevonden filmtitel. Zo draait dezelfde matrix ook tegen
 * een echte server.
 */
async function discoverTargets(page: Page, locale: Locale): Promise<Target[]> {
  const targets: Target[] = [
    { name: 'home', path: '/' },
    { name: 'bibliotheken', path: '/libraries' }
  ];

  const movies = await openLibraryOfKind(page, 'movies');
  const film = movies ? await firstCardHref(page) : null;
  let query: string | null = null;
  if (movies) targets.push({ name: 'filmbibliotheek', path: movies });
  if (film) {
    targets.push({ name: 'film', path: film });
    await page.goto(film);
    const title = await page.getByRole('heading', { level: 1 }).innerText();
    query = title.split(/\s+/)[0] ?? null;
  }

  const shows = await openLibraryOfKind(page, 'shows');
  const show = shows ? await firstCardHref(page) : null;
  if (shows) targets.push({ name: 'seriebibliotheek', path: shows });
  if (show) {
    targets.push({ name: 'serie', path: show });
    await page.goto(show);
    const seasons = page.getByRole('list', { name: label(locale, 'item.seasons') });
    const season = seasons.getByRole('listitem').first().getByRole('link');
    await season.waitFor({ timeout: 15_000 }).catch(() => undefined);
    const href = (await season.count()) ? await season.getAttribute('href') : null;
    if (href) targets.push({ name: 'seizoen', path: href });
  }

  targets.push({ name: 'zoeken leeg', path: '/search' });
  if (query) {
    targets.push({ name: 'zoeken met treffers', path: `/search?q=${encodeURIComponent(query)}` });
  }
  targets.push({ name: 'zoeken zonder treffers', path: `/search?q=${NO_HITS}` });
  targets.push({ name: 'server', path: '/server' });

  // Een ontbrekend doel is geen rode cel maar een gat in de matrix, en dat
  // hoort in de uitvoer te staan in plaats van stil weg te vallen.
  for (const kind of ['film', 'serie', 'seizoen', 'zoeken met treffers']) {
    if (!targets.some((t) => t.name === kind)) {
      test.info().annotations.push({ type: 'doel-ontbreekt', description: `${kind} [${locale}]` });
    }
  }
  return targets;
}

// Zonder sessie, vóór er een eigenaar is.
for (const { locale, context } of LOCALES) {
  test.describe(`a11y zonder eigenaar (${locale})`, () => {
    test.use({ locale: context });

    test(`/setup op vijf breedtes (${locale})`, async ({ page }, info) => {
      await prepare(page, info.project.name);
      await page.goto('/setup');
      test.skip(
        !(await setupRequired(page)),
        'deze stack heeft al een eigenaar; de setupmeting draait alleen op een verse stack'
      );
      await page.getByRole('button', { name: label(locale, 'setup.submit') }).waitFor();
      await measure(page, '/setup', locale, { shell: false });
    });
  });
}

// Ingelogd: de hele routematrix, één test per taal.
for (const { locale, context } of LOCALES) {
  test.describe(`a11y ingelogd (${locale})`, () => {
    test.use({ locale: context });

    test(`elke route op vijf breedtes (${locale})`, async ({ page }, info) => {
      await prepare(page, info.project.name);
      await signIn(page, locale);

      for (const target of await discoverTargets(page, locale)) {
        await page.setViewportSize({ width: WIDTHS[0], height: 900 });
        await page.goto(target.path);
        await page.getByRole('heading', { level: 1 }).first().waitFor({ timeout: 15_000 });
        await measure(page, `${target.name} (${target.path})`, locale);
      }
    });

    test(`home terwijl hij laadt (${locale})`, async ({ page }, info) => {
      await prepare(page, info.project.name);
      // Nulmeting S7.6: het Home-skelet heeft geen h1, en axe meldt
      // `page-has-heading-one` op alle vijf breedtes in beide talen. Taak 3 legt
      // het skelet naast beeld 15 en haalt deze regel weg. Staat hij er dan nog,
      // dan meldt Playwright "expected to fail" en valt het meteen op.
      test.fail(true, 'bekend rood tot S7.6 taak 3: het Home-skelet heeft geen h1');
      await signIn(page, locale);

      // De hub-aanvraag blijft hangen tot de meting klaar is, zodat axe het
      // skelet ziet en niet de geladen pagina.
      let release: () => void = () => undefined;
      const held = new Promise<void>((resolve) => (release = resolve));
      await page.route('**/pleya/v1/hubs/**', async (route) => {
        await held;
        await route.continue().catch(() => undefined);
      });

      await page.goto('/');
      await page.locator('[aria-busy="true"]').first().waitFor();
      await measure(page, 'home laden (/)', locale, { settle: false });
      release();
    });

    test.fixme(`onbereikbare server (${locale})`, async () => {
      // S7.6 taak 4 bouwt de staat voor een server die niet antwoordt. Dan komt
      // hier een `page.route` die `/pleya/v1/info` laat mislukken, en dezelfde
      // `measure` als hierboven.
    });
  });
}

// Zonder sessie, nadat de ingelogde test een eigenaar heeft gemaakt: /login
// stuurt zolang er geen eigenaar is door naar /setup.
for (const { locale, context } of LOCALES) {
  test.describe(`a11y inlogscherm (${locale})`, () => {
    test.use({ locale: context });

    test(`/login op vijf breedtes (${locale})`, async ({ page }, info) => {
      await prepare(page, info.project.name);
      await page.goto('/login');
      test.skip(
        await setupRequired(page),
        'deze stack heeft nog geen eigenaar, dus /login stuurt door naar /setup'
      );
      await page.getByRole('button', { name: label(locale, 'login.submit') }).waitFor();
      await measure(page, '/login', locale, { shell: false });
    });
  });
}
