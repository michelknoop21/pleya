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
 * Wat bewaard wordt is alleen de niet-geheime id, die het contract zelf in
 * URL's, browsergeschiedenis en logs toelaat. Hij staat in `sessionStorage`
 * zodat een herlaadbeurt van de speler geen nieuwe sessie kost; het geheim zit
 * in de HttpOnly-cookie en is voor deze code onzichtbaar. Geen `localStorage`:
 * de id hoort bij dit tabblad en zijn cookie, niet bij de browser.
 */
import type { StreamSession } from './types';

/** Een sessie die binnen een minuut verloopt wordt niet meer uitgegeven. */
const MARGIN_MS = 60_000;
export const STREAM_SESSION_KEY = 'pleya.stream_sessions';

type Entry = { id: string; expiresAt: number };

export interface IdStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export class StreamSessionCache {
  #now: () => number;
  #storage: IdStorage | null;
  #memory: Record<string, Entry> = {};

  constructor(now: () => number = () => Date.now(), storage: IdStorage | null = null) {
    this.#now = now;
    this.#storage = storage;
  }

  #read(): Record<string, Entry> {
    try {
      const raw = this.#storage?.getItem(STREAM_SESSION_KEY);
      if (raw) this.#memory = JSON.parse(raw) as Record<string, Entry>;
    } catch {
      // Onleesbaar of geweigerd: dan alleen het geheugen.
    }
    return this.#memory;
  }

  #write(entries: Record<string, Entry>): void {
    const now = this.#now();
    // Verlopen ids ruimen zichzelf op, zodat de opslag niet groeit.
    this.#memory = Object.fromEntries(Object.entries(entries).filter(([, e]) => e.expiresAt > now));
    try {
      this.#storage?.setItem(STREAM_SESSION_KEY, JSON.stringify(this.#memory));
    } catch {
      // Opslag vol of geweigerd: het geheugen houdt hem tot de pagina sluit.
    }
  }

  async get(versionId: string, open: () => Promise<StreamSession>): Promise<string> {
    const cached = this.#read()[versionId];
    if (cached && cached.expiresAt - MARGIN_MS > this.#now()) return cached.id;
    const fresh = await open();
    const expiresAt = Date.parse(fresh.expires_at);
    if (Number.isFinite(expiresAt)) {
      this.#write({ ...this.#read(), [versionId]: { id: fresh.stream_session_id, expiresAt } });
    }
    return fresh.stream_session_id;
  }

  /** Na een weigering van de bron: de volgende poging vraagt een nieuwe. */
  forget(versionId: string): void {
    const entries = { ...this.#read() };
    delete entries[versionId];
    this.#write(entries);
  }
}

function tabStorage(): IdStorage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

/** Eén cache per tabblad, gedeeld door elke speler die erin opent. */
export const streamSessions = new StreamSessionCache(() => Date.now(), tabStorage());
