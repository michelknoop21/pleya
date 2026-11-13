/** De paden van de speler, op één plek voor de schil en de detailpagina. */

const PLAYER_PATH = /^\/items\/[^/]+\/play$/;

export function isPlayerPath(pathname: string): boolean {
  return PLAYER_PATH.test(pathname);
}

/** De sporen die de detailpagina voor de eerstvolgende afspeelactie koos (stream-id's). */
export interface TrackPick {
  audio?: string;
  subtitle?: string;
}

/** `/items/{id}/play`, met een hervatpositie in hele seconden als die er is. */
export function playerHref(itemId: string, startAtMs?: number | null, versionId?: string, playlistId?: string, tracks?: TrackPick): string {
  const base = `/items/${encodeURIComponent(itemId)}/play`;
  const seconds = startAtMs ? Math.floor(startAtMs / 1000) : 0;
  const query = new URLSearchParams();
  if (seconds > 0) query.set('t', String(seconds));
  if (versionId) query.set('version', versionId);
  // Binnen een afspeellijst gaat de speler aan het eind door naar de volgende rij.
  if (playlistId) query.set('playlist', playlistId);
  if (tracks?.audio) query.set('audio', tracks.audio);
  if (tracks?.subtitle) query.set('subtitle', tracks.subtitle);
  return query.size ? `${base}?${query}` : base;
}
