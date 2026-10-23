/**
 * Meting bij M-1: breekt hero B in de galerij op de taal van de pagina?
 *
 *   bun run dev --port 5199
 *   PLEYA_DEV_URL=http://localhost:5199 bun run scripts/hyphenation-check.ts
 *
 * Per taal en breedte drie waarden van de titel van hero B:
 * - `hyphens`: wat `getComputedStyle` geeft (verwacht `auto`);
 * - `lang`: de taal van de dichtstbijzijnde voorouder met `lang`;
 * - `woordbreuken`: hoe vaak een regel midden in een woord eindigt;
 * - `zonderStreepje`: of de titel overloopt zodra `overflow-wrap` op `normal`
 *   gaat. Een breuk op een lettergreep met streepje heeft die vangrail niet
 *   nodig; een breuk midden in een woord zonder streepje wel. Overloop met de
 *   vangrail uit betekent dus: er staat een samenstelling zonder streepje
 *   gebroken.
 *
 * De opname blijft het oordeel; dit maakt alleen meetbaar wat het beeld toont.
 */
import { chromium } from '@playwright/test';

import { forgetStoredLocale, localeContextOptions, type ShotLocale } from './shot-locale';

const BASE = process.env['PLEYA_DEV_URL'] ?? 'http://localhost:5173';
const LOCALES: ShotLocale[] = ['nl', 'en'];
const WIDTHS = [393, 1024, 1600];

const browser = await chromium.launch();
for (const locale of LOCALES) {
  const context = await browser.newContext(localeContextOptions(locale));
  await forgetStoredLocale(context);
  const page = await context.newPage();
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${BASE}/dev/primitives`);
    const title = page.locator('#hero .hero__title').nth(1);
    await title.waitFor();
    await page.evaluate(() => document.fonts.ready);
    const result = await title.evaluate((el) => {
      const text = el.firstChild as Text;
      const range = document.createRange();
      let breaks = 0;
      let lastTop: number | null = null;
      for (let i = 0; i < text.length; i += 1) {
        range.setStart(text, i);
        range.setEnd(text, i + 1);
        const top = range.getBoundingClientRect().top;
        const ch = text.data[i]!;
        const prev = text.data[i - 1] ?? ' ';
        if (lastTop !== null && top > lastTop + 1 && ch !== ' ' && prev !== ' ') breaks += 1;
        if (ch !== ' ') lastTop = top;
      }
      const style = getComputedStyle(el);
      const element = el as HTMLElement;
      element.style.overflowWrap = 'normal';
      const overflows = element.scrollWidth > element.clientWidth + 1;
      element.style.overflowWrap = '';
      return {
        hyphens: style.hyphens,
        lang: el.closest('[lang]')?.getAttribute('lang') ?? null,
        woordbreuken: breaks,
        zonderStreepje: overflows
      };
    });
    console.log(`${locale}@${width}: ${JSON.stringify(result)}`);
  }
  await context.close();
}
await browser.close();
