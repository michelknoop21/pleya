/**
 * Schermafbeeldingen van de primitievengalerij (/dev/primitives) voor
 * docs/qa/s7-primitives/. Heeft geen server nodig, alleen `vite dev`:
 *
 *   bun run dev
 *   PLEYA_DEV_URL=http://localhost:5173 bun run scripts/primitives-shots.ts
 *
 * Naast de opnamen print hij twee metingen die een plaatje niet laat zien:
 * of de pagina achter de open dialoog meescrolt (scrollY voor en na een
 * wielscroll van 600 px, moet gelijk blijven), en de berekende kleur van
 * het skelet naast die van een artworkvlak zonder beeld.
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync } from 'node:fs';

import { SECTIONS as GALLERY_SECTIONS } from '../src/routes/dev/primitives/sections';

const BASE = process.env['PLEYA_DEV_URL'] ?? 'http://localhost:5173';
const OUT = process.argv[2] ?? '../docs/qa/s7-primitives';
const GALLERY = `${BASE}/dev/primitives`;

const WIDTHS = [393, 1024, 1600];
const SKELETON_WIDTHS = [393, 768, 1024, 1280, 1600];
// Elke sectie uit de index, behalve de dialoog: die opent hieronder apart.
const SECTIONS = GALLERY_SECTIONS.map((s) => s.id).filter((id) => id !== 'dialoog');

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();

async function open(url: string, width: number, theme = 'dark'): Promise<void> {
  await page.setViewportSize({ width, height: width < 600 ? 852 : 900 });
  await page.goto(GALLERY);
  await page.evaluate((t) => localStorage.setItem('pleya.theme', t), theme);
  await page.goto(url);
  await page.locator('main').waitFor({ timeout: 60_000 });
  await page.waitForTimeout(400);
}

async function shot(target: Page | ReturnType<Page['locator']>, name: string, full = false) {
  const path = `${OUT}/${name}.png`;
  if ('goto' in target) await target.screenshot({ path, fullPage: full });
  else await target.screenshot({ path });
  console.log(path);
}

// PLEYA_SHOTS_THEME=light (of oled, of dark) maakt alleen de opnamen van dat
// thema opnieuw, voor een gerichte herronde. PLEYA_SHOTS_SECTIONS=velden,tabel
// beperkt een ronde tot die secties plus de focusopname, en slaat de galerij,
// de dialoog en de skeletpagina's over.
const ONLY = process.env['PLEYA_SHOTS_THEME'];
const PICK = process.env['PLEYA_SHOTS_SECTIONS']?.split(',').filter(Boolean);
const pick = (ids: readonly string[]) => (PICK ? ids.filter((id) => PICK.includes(id)) : [...ids]);

/** De globale focusring (base.css) op een gewone knop, in een paneel. */
async function focusButton(name: string): Promise<void> {
  const button = page.locator('#panelen .btn').first();
  await button.scrollIntoViewIfNeeded();
  await page.keyboard.press('Shift'); // toetsenbordmodaliteit, zodat :focus-visible geldt
  await button.focus();
  await page.waitForTimeout(200);
  const ring = await button.evaluate((el) => {
    const c = getComputedStyle(el);
    return {
      matches: el.matches(':focus-visible'),
      outline: `${c.outlineWidth} ${c.outlineStyle} ${c.outlineColor}`,
      offset: c.outlineOffset
    };
  });
  console.log(`${name}: ${JSON.stringify(ring)}`);
  await shot(page.locator('#panelen .panel').first(), name);
}

/**
 * Kaarten: hover en toetsenbordfocus zijn echte staten, dus de muis gaat over
 * de tweede kaart terwijl de derde de focus heeft, zoals specimen v3 ze naast
 * elkaar toont. Eerst wachten tot het gegenereerde artwork er staat.
 */
async function cardStates(name: string): Promise<void> {
  // Sectiekop net onder de indexstrook (64 hoog onder 900), zodat de hover-
  // kaart in beeld staat en de strook niet over de opname valt.
  await page.evaluate(() => {
    const top = document.getElementById('kaarten')!.getBoundingClientRect().top + scrollY;
    scrollTo(0, top - 72);
  });
  await page.waitForFunction(() => document.querySelectorAll('#kaarten img').length >= 9);
  await page.keyboard.press('Shift');
  await page.locator('#kaarten [data-demo="focus"] a').focus();
  await page.locator('#kaarten [data-demo="hover"] .card').hover();
  await page.waitForTimeout(400); // lift en overlay lopen over --dur-normal
  // Een sectie hoger dan het venster: knippen uit de hele pagina in plaats van
  // een elementopname, die zou scrollen en de muis van de kaart halen.
  const box = await page.evaluate(() => {
    const r = document.getElementById('kaarten')!.getBoundingClientRect();
    return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height };
  });
  const path = `${OUT}/${name}.png`;
  await page.screenshot({ path, fullPage: true, clip: box });
  console.log(path);
}

if (!ONLY || ONLY === 'dark') {
for (const width of WIDTHS) {
  await open(GALLERY, width);
  if (!PICK) await shot(page, `galerij@${width}`, true);
  for (const id of pick(SECTIONS)) {
    if (id === 'velden') {
      await page.locator('#veld-hint').focus();
      await page.waitForTimeout(300); // randovergang van --dur-fast
    }
    if (id === 'kaarten') {
      await cardStates(`${id}@${width}`);
      continue;
    }
    await shot(page.locator(`#${id}`), `${id}@${width}`);
  }
  if (pick(['chips']).length) {
    await page.locator('#chips button').first().focus();
    await shot(page.locator('#chips'), `chips-focus@${width}`);
  }
  await focusButton(`focus-knop@${width}`);
  if (!pick(['velden']).length) continue;
  // Een veld kan maar één focus hebben: het foutveld met focus apart.
  await page.locator('#veld-fout-focus').focus();
  await page.waitForTimeout(300);
  await shot(page.locator('#velden'), `velden-foutfocus@${width}`);
  const ring = await page.evaluate(() => {
    const c = getComputedStyle(document.getElementById('veld-fout-focus')!);
    return { border: c.borderTopColor, width: c.borderTopWidth, shadow: c.boxShadow, outline: c.outlineStyle };
  });
  console.log(`foutveld met focus @${width}: ${JSON.stringify(ring)}`);
}

for (const width of PICK ? [] : [393, 1600]) {
  for (const kind of ['plain', 'phrase']) {
    await open(GALLERY, width);
    const trigger = page.locator(`[data-open="${kind}"]`);
    await trigger.scrollIntoViewIfNeeded();
    await trigger.click();
    await page.getByRole('dialog').waitFor();
    await page.waitForTimeout(300);
    await shot(page, `dialoog-${kind}@${width}`);
    // Scrolt de pagina achter de dialoog mee? Wiel boven het scherm, buiten de kaart.
    const before = await page.evaluate(() => scrollY);
    await page.mouse.move(width / 2, 20);
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(300);
    const after = await page.evaluate(() => scrollY);
    const locked = await page.evaluate(() =>
      document.documentElement.classList.contains('scroll-locked')
    );
    console.log(`scroll achter dialoog-${kind}@${width}: ${before} -> ${after} (scroll-locked=${locked})`);
    if (kind === 'phrase' && width === 393) await shot(page, `dialoog-${kind}-gescrold@${width}`);
  }
}

}
// Dezelfde secties in OLED en light, om contrast en scheiding per thema te zien.
// Dark staat hierboven al; die opnamen houden hun naam zonder themasuffix.
const THEMED = [
  'overzicht',
  'opslagmeter',
  'velden',
  'panelen',
  'meldingen',
  'pillen',
  'chips',
  'tabel',
  'stappen'
];
const THEMES = ONLY ? (ONLY === 'dark' ? [] : [ONLY]) : ['oled', 'light'];
for (const theme of THEMES) {
  for (const width of [393, 1600]) {
    await open(GALLERY, width, theme);
    for (const id of pick(THEMED)) await shot(page.locator(`#${id}`), `${id}-${theme}@${width}`);
    await focusButton(`focus-knop-${theme}@${width}`);
    if (PICK) continue;
    await page.locator('#veld-fout-focus').focus();
    await page.waitForTimeout(300);
    await shot(page.locator('#velden'), `velden-foutfocus-${theme}@${width}`);
    const colours = await page.evaluate(() => {
      const css = (sel: string, prop: 'color' | 'backgroundColor' | 'borderTopColor') => {
        const el = document.querySelector(sel);
        return el ? getComputedStyle(el)[prop] : null;
      };
      return {
        foutrand: css('#veld-fout-focus', 'borderTopColor'),
        fouttekst: css('#velden .fld__help--err', 'color'),
        errPill: css('#pillen .pill--err', 'color'),
        runStip: css('#pillen .pill--status.pill--run .pill__dot', 'backgroundColor'),
        runPill: css('#pillen .pill--run:not(.pill--status)', 'color'),
        inset: css('#veld-hint', 'backgroundColor'),
        paneel: css('#panelen .panel', 'backgroundColor')
      };
    });
    console.log(`kleuren ${theme}@${width}: ${JSON.stringify(colours)}`);
    const trigger = page.locator('[data-open="phrase"]');
    await trigger.scrollIntoViewIfNeeded();
    await trigger.click();
    await page.getByRole('dialog').waitFor();
    await page.waitForTimeout(300);
    await shot(page, `dialoog-phrase-${theme}@${width}`);
  }
}

if (!ONLY && !PICK) {
for (const width of SKELETON_WIDTHS) {
  for (const variant of ['home', 'grid', 'detail']) {
    await open(`${GALLERY}?skeleton=${variant}`, width);
    await shot(page, `skeleton-${variant}@${width}`);
  }
}

for (const theme of ['oled', 'light']) {
  await open(GALLERY, 1024, theme);
  await shot(page.locator('#skelet'), `skelet-${theme}@1024`);
  const colours = await page.evaluate(() => {
    const skel = document.querySelector('#skelet .skel');
    const art = document.querySelector('#skelet .artwork');
    return {
      skeleton: skel ? getComputedStyle(skel).backgroundColor : null,
      artwork: art ? getComputedStyle(art).backgroundColor : null
    };
  });
  console.log(`kleuren ${theme}: ${JSON.stringify(colours)}`);
}

}
await browser.close();
