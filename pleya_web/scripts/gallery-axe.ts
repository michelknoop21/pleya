/**
 * Axe en overloop op de primitievengalerij, op de vaste breedtes.
 *
 *   bun run dev
 *   PLEYA_DEV_URL=http://localhost:5173 bun run scripts/gallery-axe.ts
 *
 * De galerij bestaat alleen onder `vite dev` (404 in de bundel), dus de
 * e2e-suite tegen de binary kan hem niet meten. Dit script doet dezelfde meting
 * als `a11y-routes.spec.ts`, met dezelfde tags, en eindigt met code 1 bij een
 * overtreding of overloop.
 */
import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

import { AXE_TAGS } from '../tests/e2e/helpers';

const BASE = process.env['PLEYA_DEV_URL'] ?? 'http://localhost:5173';
const WIDTHS = [320, 390, 1280, 1440, 1920];

const browser = await chromium.launch();
let failed = false;
for (const theme of ['dark', 'light', 'oled']) {
  const context = await browser.newContext({ locale: 'nl-NL' });
  await context.addInitScript((t) => localStorage.setItem('pleya.theme', t), theme);
  const page = await context.newPage();
  await page.goto(`${BASE}/dev/primitives`);
  await page.locator('h1').first().waitFor();
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: width >= 1920 ? 1080 : 900 });
    await page.waitForTimeout(300);
    const { violations } = await new AxeBuilder({ page }).withTags(AXE_TAGS).analyze();
    const over = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    const ids = violations.map((v) => `${v.id} (${v.nodes.map((n) => n.target.join(' ')).join(', ')})`);
    console.log(`galerij ${theme}@${width}: axe ${ids.length ? ids.join('; ') : '0'}, overloop ${over}px`);
    if (ids.length || over > 1) failed = true;
  }
  await context.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
