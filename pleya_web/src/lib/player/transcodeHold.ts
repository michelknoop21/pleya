/**
 * Houdt een omzetsessie levend zolang er gekeken wordt, en ruimt hem op.
 *
 * De server stopt een sessie na een minuut zonder hartslag of
 * bestandsaanvraag (`POST /playback/sessions/{id}/heartbeat`, S18). Hetzelfde
 * ritme als de app (`_heartbeatEvery`, 15 s in
 * `lib/services/pleya_server_client/parts/playback.dart`): ruim binnen die
 * minuut, ook als een tik mislukt.
 *
 * Opruimen gebeurt op drie momenten: de speler sluit (unmount, routewissel),
 * de pagina verdwijnt (`pagehide`), of de server meldt dat de sessie weg is
 * (404 op de hartslag, bijvoorbeeld na `DELETE /transcode-sessions/{id}` door
 * een beheerder). In het laatste geval valt er niets meer te stoppen.
 */
import { ApiError } from '../api/errors';
import type { PlaybackApi } from './playbackApi';

export const HEARTBEAT_EVERY_MS = 15_000;

export interface Timers {
  setInterval(fn: () => void, ms: number): unknown;
  clearInterval(handle: unknown): void;
}

const realTimers: Timers = {
  setInterval: (fn, ms) => globalThis.setInterval(fn, ms),
  clearInterval: (h) => globalThis.clearInterval(h as ReturnType<typeof setInterval>)
};

export class TranscodeHold {
  #api: Pick<PlaybackApi, 'heartbeat' | 'stop'>;
  #timers: Timers;
  #onLost: () => void;
  #sessionId: string | null = null;
  #handle: unknown = null;

  constructor(
    api: Pick<PlaybackApi, 'heartbeat' | 'stop'>,
    onLost: () => void,
    timers: Timers = realTimers
  ) {
    this.#api = api;
    this.#onLost = onLost;
    this.#timers = timers;
  }

  get sessionId(): string | null {
    return this.#sessionId;
  }

  /** Begint de hartslag. Een vorige sessie wordt eerst gestopt. */
  hold(sessionId: string): void {
    if (this.#sessionId && this.#sessionId !== sessionId) this.release(false);
    this.#sessionId = sessionId;
    this.#handle = this.#timers.setInterval(() => void this.#beat(), HEARTBEAT_EVERY_MS);
  }

  async #beat(): Promise<void> {
    const id = this.#sessionId;
    if (!id) return;
    try {
      await this.#api.heartbeat(id);
    } catch (err) {
      if (err instanceof ApiError && err.status === 404 && this.#sessionId === id) {
        // De server kent hem niet meer. Stoppen heeft geen zin; de speler
        // hoort dat hij straks geen segmenten meer krijgt.
        this.#clearTimer();
        this.#sessionId = null;
        this.#onLost();
      }
      // Een netwerkhapering is geen verlies: de volgende tik probeert opnieuw,
      // en hls.js telt intussen zelf als hartslag met elke segmentaanvraag.
    }
  }

  #clearTimer(): void {
    if (this.#handle !== null) this.#timers.clearInterval(this.#handle);
    this.#handle = null;
  }

  /**
   * Stopt de hartslag en de sessie. Twee keer aanroepen stuurt één DELETE.
   * `keepalive` hoort bij `pagehide`, waar de pagina de aanvraag niet afwacht.
   */
  release(keepalive: boolean): void {
    this.#clearTimer();
    const id = this.#sessionId;
    this.#sessionId = null;
    if (id) this.#api.stop(id, keepalive);
  }
}
