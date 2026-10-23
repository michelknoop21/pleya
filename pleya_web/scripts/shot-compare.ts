/**
 * Een opname naast het northstar-beeld op dezelfde breedte, als één beeld.
 *
 * Gedeeld door `primitives-shots.ts` (galerij) en `routes-shots.ts` (routes en
 * staten). Links de app, rechts de northstar, allebei op halve schaal naast
 * elkaar, zodat een reviewer compositie en maat in één oogopslag vergelijkt.
 */
import type { BrowserContext } from '@playwright/test';
import { readFileSync } from 'node:fs';

export const NORTHSTAR = '../docs/assets/pleya-web-northstar';

/**
 * Schrijft `{prefix}-vs-northstar@{width}.{png|jpeg}` en geeft het pad terug.
 * `label` is het bijschrift boven de linkerhelft.
 */
export async function compare(
  context: BrowserContext,
  prefix: string,
  mine: string,
  northstarFile: string,
  width: number,
  options: { label?: string; type?: 'png' | 'jpeg' } = {}
): Promise<string> {
  const b64 = (p: string) => readFileSync(p).toString('base64');
  const mime = mine.endsWith('.png') ? 'image/png' : 'image/jpeg';
  const label = options.label ?? 'galerij (pleya_web)';
  const html = `<body style="margin:0;background:#000;color:#aaa;font:12px sans-serif">
    <div style="display:flex;gap:16px;padding:12px;align-items:flex-start">
      <figure style="margin:0;flex:1 1 0;min-width:0"><figcaption style="padding:0 0 6px">${label}</figcaption>
        <img style="width:100%" src="data:${mime};base64,${b64(mine)}"></figure>
      <figure style="margin:0;flex:1 1 0;min-width:0"><figcaption style="padding:0 0 6px">northstar ${northstarFile}</figcaption>
        <img style="width:100%" src="data:image/jpeg;base64,${b64(`${NORTHSTAR}/${northstarFile}`)}"></figure>
    </div></body>`;
  const type = options.type ?? 'png';
  const cmp = await context.newPage();
  await cmp.setViewportSize({ width: Math.max(width * 2 + 56, 900), height: 800 });
  await cmp.setContent(html);
  await cmp.waitForFunction(() => Array.from(document.images).every((i) => i.complete));
  const path = `${prefix}-vs-northstar@${width}.${type === 'png' ? 'png' : 'jpg'}`;
  await cmp.screenshot({ path, fullPage: true, type, ...(type === 'jpeg' ? { quality: 75 } : {}) });
  await cmp.close();
  return path;
}
