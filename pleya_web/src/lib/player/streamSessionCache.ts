/**
 * Hergebruik van browser-streamsessies per versie, binnen dit tabblad.
 *
 * Het contract begrenst een subject op acht actieve streamsessies
 * (`session.stream_session_limit`) en kent geen route waarmee een client zijn
 * eigen streamsessie beëindigt; een sessie verloopt alleen vanzelf. Een nieuwe
 * sessie per druk op afspelen zou die acht dus binnen een half uur opmaken,
 * terwijl de cookie van de vorige nog geldig in de browser staat. Daarom: zelfde
 * versie, nog niet bijna verlopen, dan dezelfde id. De server verlengt de
 * sessie bij elke aanvraag, dus `expires_at` van het aanmaken is hier de
 * voorzichtige ondergrens.
 *
 * Alleen de niet-geheime id staat hier, in het geheugen; het geheim zit in de
 * HttpOnly-cookie en is voor deze code onzichtbaar.
 */
import type { StreamSession } from './types';

/** Een sessie die binnen een minuut verloopt wordt niet meer uitgegeven. */
const MARGIN_MS = 60_000;

export class StreamSessionCache {
  #byVersion = new Map<string, { id: string; expiresAt: number }>();
  #now: () => number;

  constructor(now: () => number = () => Date.now()) {
    this.#now = now;
  }

  async get(versionId: string, open: () => Promise<StreamSession>): Promise<string> {
    const cached = this.#byVersion.get(versionId);
    if (cached && cached.expiresAt - MARGIN_MS > this.#now()) return cached.id;
    const fresh = await open();
    const expiresAt = Date.parse(fresh.expires_at);
    if (Number.isFinite(expiresAt)) {
      this.#byVersion.set(versionId, { id: fresh.stream_session_id, expiresAt });
    }
    return fresh.stream_session_id;
  }

  /** Na een weigering van de bron: de volgende poging vraagt een nieuwe. */
  forget(versionId: string): void {
    this.#byVersion.delete(versionId);
  }
}

/** Eén cache per tabblad, gedeeld door elke speler die erin opent. */
export const streamSessions = new StreamSessionCache();
