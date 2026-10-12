import { CORE, L, LATER, MOUTHS, POSES, type Box } from './layers';

const LASH = '#2a0604';
const LIMB = '#1b0b09';

const img = (href: string, b: Box, extra = '') => `<image href="${href}" x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" ${extra}/>`;
const full = (href: string, extra = '') => `<image href="${href}" x="0" y="0" width="${L.w}" height="${L.h}" ${extra}/>`;
// Poses arrive after the first paint: the element exists, the image is attached once loaded.
const later = (src: string, b?: Box) => {
  const box = b ?? { x: 0, y: 0, w: L.w, h: L.h };
  return `<image data-later="${src}" x="${box.x}" y="${box.y}" width="${box.w}" height="${box.h}"/>`;
};

const leg = (side: 'l' | 'r') => {
  const g = L.legs[side];
  const src = CORE.legs[side];
  return `<g class="leg" data-side="${side}">${img(src.upper, g.upper)}<g class="shin">${img(src.lower, g.lower)}</g></g>`;
};

/**
 * One <svg> with a single rig group: all motion is a transform on that group plus the arm,
 * legs, brows and eyelids. `n` makes the gradient and clip-path ids unique per figure.
 */
export function buildSvg(n: number): string {
  const [fx, fy] = L.feet;
  const [ax, ay] = L.aim.pivot;
  const eyes = L.eyes
    .map(
      (e, i) => `<clipPath id="bigp${n}-eye${i}"><ellipse cx="${e.cx}" cy="${e.cy}" rx="${e.rx + 3}" ry="${e.ry + 3}"/></clipPath>
      <linearGradient id="bigp${n}-lid${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${e.lid}"/><stop offset=".7" stop-color="${e.lid}"/><stop offset="1" stop-color="#7a0905"/></linearGradient>
      <g clip-path="url(#bigp${n}-eye${i})"><path class="lid" fill="url(#bigp${n}-lid${i})"/><path class="lash" fill="none" stroke="${LASH}" stroke-width="7"/></g>`,
    )
    .join('');
  return `<svg viewBox="0 0 ${L.w} ${L.h}" focusable="false" style="position:absolute;inset:0;width:100%;height:100%;overflow:visible;display:block">
    <defs><radialGradient id="bigp${n}-floor"><stop offset="0" stop-color="#e5140f" stop-opacity=".42"/><stop offset=".55" stop-color="#e5140f" stop-opacity=".14"/><stop offset="1" stop-color="#e5140f" stop-opacity="0"/></radialGradient></defs>
    <g class="stage">
      <ellipse cx="${fx}" cy="${fy + 6}" rx="470" ry="80" fill="url(#bigp${n}-floor)"/>
      <ellipse class="shadow" cx="${fx}" cy="${fy + 4}" rx="300" ry="20" fill="#000" opacity=".55"/>
      <g class="rig">
        <g class="legs">${leg('r')}${leg('l')}</g>
        <g class="p-wijzen" opacity="0">
          <circle cx="${ax}" cy="${ay}" r="26" fill="${LIMB}"/>
          <g class="aimarm">${later(LATER.wijzen[1], L.aim)}</g>
          ${later(LATER.wijzen[0])}
        </g>
        ${full(CORE.rest, 'class="p-rest"')}
        ${POSES.map((p) => `<g class="p-${p}" opacity="0">${later(LATER[p][0])}</g>`).join('')}
        <g class="wavearm" opacity="0">${later(LATER.zwaaien[1], L.wave)}</g>
        <g class="face">
          ${MOUTHS.map((m) => img(CORE.mouths[m], L.mouth, `class="mouth" data-m="${m}" opacity="${m === 'rest' ? 1 : 0}"`)).join('')}
          ${eyes}
          <g class="brow">${img(CORE.browL, L.browL)}</g>
          <g class="brow">${img(CORE.browR, L.browR)}</g>
        </g>
      </g>
    </g></svg>`;
}

const loads = new Map<string, Promise<void>>();

/** Fetch and decode an image once for the whole page; every figure then attaches it from cache. */
export function preload(src: string): Promise<void> {
  let p = loads.get(src);
  if (!p) {
    p = new Promise<void>((resolve, reject) => {
      const im = new Image();
      im.onload = () => resolve();
      im.onerror = () => reject(new Error(`Big P layer failed to load: ${src}`));
      im.src = src;
    });
    loads.set(src, p);
  }
  return p;
}
