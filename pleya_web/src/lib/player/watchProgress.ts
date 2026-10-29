import type { UserState, WatchStateEvent } from './types';
import { realTimers, type Timers } from './transcodeHold';

interface Options {
  report: (body: WatchStateEvent, keepalive: boolean) => Promise<UserState>;
  enabled: boolean;
  ownership: boolean;
  itemId: string;
  revision?: number;
  sample: () => { position: number; duration: number };
  timers?: Timers;
}

/** One actual viewing; passive updates never acquire ownership. */
export class WatchProgress {
  #options: Options;
  #timers: Timers;
  #sessionId = crypto.randomUUID();
  #revision: number | undefined;
  #started = false;
  #closed = false;
  #timer: unknown = null;
  #sending = false;
  #pending: { body: WatchStateEvent; keepalive: boolean } | null = null;

  constructor(options: Options) {
    this.#options = options;
    this.#revision = options.revision;
    this.#timers = options.timers ?? realTimers;
  }

  play(): void {
    if (!this.#options.enabled || this.#closed || this.#started) return;
    this.#started = true;
    this.#queue('playback_started', false);
    this.#timer = this.#timers.setInterval(() => this.report(), 15_000);
  }

  report(): void {
    if (this.#started && !this.#closed) this.#queue('none', false);
  }

  finish(keepalive: boolean): void {
    if (this.#closed) return;
    this.#closed = true;
    if (this.#timer !== null) this.#timers.clearInterval(this.#timer);
    this.#timer = null;
    if (this.#started) this.#queue('none', keepalive, true);
  }

  #queue(action: WatchStateEvent['explicit_action'], keepalive: boolean, final = false): void {
    const sample = this.#options.sample();
    const duration = Number.isFinite(sample.duration) && sample.duration > 0 ? Math.round(sample.duration * 1000) : 0;
    const position = Number.isFinite(sample.position) ? Math.max(0, Math.round(sample.position * 1000)) : 0;
    this.#pending = {
      body: {
        item_id: this.#options.itemId,
        session_id: this.#sessionId,
        position_ms: duration > 0 ? Math.min(position, duration) : position,
        ...(duration > 0 ? { duration_ms: duration } : {}),
        occurred_at: new Date().toISOString(),
        completed: final && duration > 0 && position >= 0.9 * duration,
        explicit_action: action,
        ...(this.#options.ownership ? { backlog: false } : {})
      }, keepalive
    };
    if (keepalive && this.#sending) {
      const pending = this.#pending!;
      this.#pending = null;
      // Best effort on pagehide: a stale CAS is safely rejected by the server.
      void this.#options.report(this.#body(pending.body), true).catch(() => undefined);
      return;
    }
    void this.#flush();
  }

  #body(body: WatchStateEvent): WatchStateEvent {
    return { ...body, ...(this.#options.ownership && this.#revision !== undefined ? { base_revision: this.#revision } : {}) };
  }

  async #flush(): Promise<void> {
    if (this.#sending) return;
    this.#sending = true;
    try {
      while (this.#pending) {
        const pending = this.#pending;
        this.#pending = null;
        const body = this.#body(pending.body);
        try {
          const state = await this.#options.report(body, pending.keepalive);
          if (Number.isSafeInteger(state.revision) && state.revision! >= (this.#revision ?? 0)) this.#revision = state.revision;
        } catch {
          // A later passive tick may retry; failure never grants ownership.
        }
      }
    } finally {
      this.#sending = false;
    }
  }
}
