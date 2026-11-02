/** De paden van de speler, op één plek voor de schil en de detailpagina. */

const PLAYER_PATH = /^\/items\/[^/]+\/play$/;

export function isPlayerPath(pathname: string): boolean {
  return PLAYER_PATH.test(pathname);
}

/** `/items/{id}/play`, met een hervatpositie in hele seconden als die er is. */
export function playerHref(itemId: string, startAtMs?: number | null, versionId?: string, playlistId?: string): string {
  const base = `/items/${encodeURIComponent(itemId)}/play`;
  const seconds = startAtMs ? Math.floor(startAtMs / 1000) : 0;
  const query = new URLSearchParams();
  if (seconds > 0) query.set('t', String(seconds));
  if (versionId) query.set('version', versionId);
  // Binnen een afspeellijst gaat de speler aan het eind door naar de volgende rij.
  if (playlistId) query.set('playlist', playlistId);
  return query.size ? `${base}?${query}` : base;
}
