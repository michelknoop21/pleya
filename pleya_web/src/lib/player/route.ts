/** De paden van de speler, op één plek voor de schil en de detailpagina. */

const PLAYER_PATH = /^\/items\/[^/]+\/play$/;

export function isPlayerPath(pathname: string): boolean {
  return PLAYER_PATH.test(pathname);
}

/** `/items/{id}/play`, met een hervatpositie in hele seconden als die er is. */
export function playerHref(itemId: string, startAtMs?: number | null): string {
  const base = `/items/${encodeURIComponent(itemId)}/play`;
  const seconds = startAtMs ? Math.floor(startAtMs / 1000) : 0;
  return seconds > 0 ? `${base}?t=${seconds}` : base;
}
