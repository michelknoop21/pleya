/**
 * De artworkladder: welke breedte er gevraagd wordt voor een vlak.
 *
 * Een echt `srcset`-attribuut is hier onmogelijk. Artwork komt binnen via
 * `fetch` met een Authorization-header en hangt als object-URL aan het
 * element (README 'Artwork'), dus de browser kan zelf geen bron kiezen. Deze
 * helper doet het werk van `srcset` en `sizes` aan de clientkant: één trede
 * per vlak, gemeten aan de getekende breedte.
 *
 * Alleen als de server `capabilities.artwork_sizes` meldt gaat er een
 * `?width=` over de lijn (DEC-154). Zonder die vlag, bij een oudere server, is
 * de terugval het origineel, precies wat het contract belooft.
 */

/** RB-7, poster en boekcover. */
export const POSTER_LADDER = [240, 480, 960, 1920] as const;
/** RB-7, backdrop en hero. */
export const BACKDROP_LADDER = [480, 960, 1920, 3840] as const;

export type ArtworkRole = 'poster' | 'backdrop';

/** Kleinste trede die cssWidth * dpr dekt; boven de top de top. */
export function ladderStep(
  cssWidth: number,
  dpr: number,
  role: ArtworkRole,
): number {
  const ladder = role === 'poster' ? POSTER_LADDER : BACKDROP_LADDER;
  const needed = cssWidth * dpr;
  for (const step of ladder as readonly number[]) {
    if (step >= needed) return step;
  }
  return ladder[ladder.length - 1] as number;
}

/**
 * De breedte om te vragen, of undefined: dan het origineel. Een onmeetbaar
 * vlak (breedte 0, nog niet getekend) vraagt ook het origineel. `available` is
 * `capabilities.artwork_sizes` van de server.
 */
export function requestWidth(
  cssWidth: number,
  dpr: number,
  role: ArtworkRole,
  available: boolean,
): number | undefined {
  if (!available) return undefined;
  if (!(cssWidth > 0) || !(dpr > 0)) return undefined;
  return ladderStep(cssWidth, dpr, role);
}
