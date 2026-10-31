import type { UserState, WatchStateEvent } from './types';
import { realTimers, type Timers } from './transcodeHold';
import { randomId } from '../auth/device';

interface Options {
  report: (body: WatchStateEvent, keepalive: boolean) => Promise<UserState>;
  enabled: boolean;
  ownership: boolean;
  itemId: string;
  revision?: number;
  sample: () => { position: number; duration: number };
  timers?: Timers;
}

/**
 * Keeps the old resume point until playback reaches it. A seek can fail, or land short when a
 * conversion has not got that far yet; reporting where the video really is would erase the
 * resume point with a position nobody chose. A seek by the viewer does choose, so it releases.
 */
export class ResumeFloor {
  #floor: number;

  constructor(startAt: number) {
    this.#floor = startAt;
  }

  /** The position to report for what the video shows now. */
  position(current: number): number {
    if (current >= this.#floor - 1) this.#floor = 0;
    return Math.max(current, this.#floor);
  }

  release(): void {
    this.#floor = 0;
  }
}

/** One actual viewing; passive updates never acquire ownership. */
export class WatchProgress {
  #options: Options;
  #timers: Timers;
  #sessionId = randomId();
  #revision: number | undefined;
  #started = false;
  /** The server has answered a start; a start that failed is repeated by the next report. */
  #claimed = false;
  #startRetried = false;
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
    this.#queue(false);
    this.#timer = this.#timers.setInterval(() => this.report(), 15_000);
  }

  report(): void {
    if (this.#started && !this.#closed) this.#queue(false);
  }

  finish(keepalive: boolean): void {
    if (this.#closed) return;
    this.#closed = true;
    if (this.#timer !== null) this.#timers.clearInterval(this.#timer);
    this.#timer = null;
    if (this.#started) this.#queue(keepalive, true);
  }

  #queue(keepalive: boolean, final = false): void {
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
        explicit_action: 'none',
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

  // Decided at send time: a queued report may go out after the start was answered, or fail.
  #body(body: WatchStateEvent): WatchStateEvent {
    const ownership = this.#options.ownership;
    return {
      ...body,
      ...(this.#claimed ? {} : { explicit_action: 'playback_started' as const }),
      ...(ownership && !this.#claimed ? { cause: 'user_started' as const } : {}),
      ...(ownership && this.#revision !== undefined ? { base_revision: this.#revision } : {})
    };
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
          // user_started overrules any lease, so a refused start means a stale revision: the page was loaded
          // before this title's last write. The answer carries the current one; one retry is enough.
          if (body.explicit_action === 'playback_started') {
            if (state.owned_by_this_session === false && !this.#startRetried && !this.#closed) {
              this.#startRetried = true;
              this.#pending ??= pending;
            } else {
              this.#claimed = true;
            }
          }
        } catch {
          // The server said nothing about ownership. An unanswered start is repeated by the next
          // report, or one 503 costs the whole viewing: passive reports never acquire it.
        }
      }
    } finally {
      this.#sending = false;
    }
  }
}
