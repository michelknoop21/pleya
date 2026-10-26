/**
 * Gegevens en rekenregels van Transcode-sessies (scherm 37, S18.5).
 *
 * Alles komt uit `GET /transcode-sessions` (`max_sessions`, `hardware`, de
 * sessies) en `GET /users` voor de namen. Wat de northstar verder tekent en het
 * contract niet draagt, staat hier niet en is niet verzonnen:
 * - de titel en het toestel per sessie (een sessie draagt alleen `user_id` en
 *   `version_id`, en er is geen route die een versie naar een titel vertaalt);
 * - voortgang, snelheid ten opzichte van realtime en de omzetting zelf
 *   (bron- en doelcodec, resolutie, ingebrande ondertitel);
 * - de grootte van de transcodemap en haar quotum;
 * - het lijstje "Vandaag afgelopen" met de reden van het einde (de server
 *   bewaart geen afgeronde sessies).
 */
import type { AdminApi } from '../../api/admin';
import type { TranscodeSession, TranscodeSessionList, User } from '../../api/types';

/** Zo vaak ververst de pagina zolang er sessies zijn. */
export const TRANSCODE_POLL_MS = 5000;

export interface TranscodeData {
  list: TranscodeSessionList;
  /** Null als de gebruikers niet te lezen waren; dan staat er "onbekend" en geen gok. */
  users: User[] | null;
}

export async function loadTranscode(api: AdminApi, signal?: AbortSignal): Promise<TranscodeData> {
  const [list, users] = await Promise.all([
    api.transcodeSessions(signal),
    api.users(signal).catch(() => null)
  ]);
  return { list, users };
}

/** Moet de pagina blijven verversen? Alleen als er sessies lopen. */
export function isLive(data: TranscodeData): boolean {
  return data.list.items.length > 0;
}

/** De server draait op zijn maximum: een volgende aanvraag krijgt `playback.transcode_busy`. */
export function atMaximum(list: TranscodeSessionList): boolean {
  return list.max_sessions > 0 && list.items.length >= list.max_sessions;
}

/** De oudste sessie bovenaan: die loopt het langst en is de eerste kandidaat om te stoppen. */
export function sortedSessions(items: TranscodeSession[]): TranscodeSession[] {
  return [...items].sort((a, b) => Date.parse(a.started_at) - Date.parse(b.started_at));
}

/** De eerste acht tekens van een id: genoeg om twee sessies uit elkaar te houden. */
export function shortId(id: string): string {
  return id.slice(0, 8);
}
