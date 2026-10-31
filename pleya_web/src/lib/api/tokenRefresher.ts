/**
 * Het tokenpaar vernieuwen: hoogstens één keer tegelijk per tabblad, en met
 * `navigator.locks` ook tussen tabbladen.
 *
 * Het refreshtoken roteert bij elk gebruik, dus twee aanvragen met hetzelfde
 * credential zijn precies de race die de server als hergebruik kan lezen. Binnen
 * een tabblad voegt `run` ze samen. Tussen tabbladen doet het slot dat: het
 * tweede tabblad wacht, leest daarna het geroteerde token of stuurt de nieuwe
 * cookie mee, en krijgt zijn eigen accesstoken. Dat accesstoken valt niet te
 * delen, want het staat per tabblad.
 *
 * Het slot dekt één aanvraag met het opslaan van het antwoord, niet de hele ronde:
 * wie op een 429 wacht houdt niemand op.
 *
 * Web Locks bestaat alleen in een secure context (MDN, LockManager.request), dus op
 * `http://nas:8832` is er geen slot en gelden het respijt en de jitter hieronder,
 * zoals vóór deze code.
 */
import type { Client } from 'openapi-fetch';

import type { paths, components } from './schema';
import { type ApiError, isSessionRejected, toApiError } from './errors';
import type { TokenStore } from '../auth/tokens';

/** Hoe vaak een verversing een 429 mag krijgen voor deze ronde opgeeft. */
const REFRESH_LIMIT_ATTEMPTS = 5;
/** Ruim boven wat de server vraagt; een proxy die langer vraagt krijgt geen hangend scherm. */
const REFRESH_LIMIT_MAX_WAIT_MS = 30_000;
/**
 * Tabbladen die dezelfde 429 kregen, komen niet op hetzelfde moment terug. Twee
 * gelijktijdige verversingen met één cookie zijn precies de race die de sessie kan
 * laten vallen; met dit verschil ziet de tweede de cookie van de eerste.
 */
const REFRESH_LIMIT_JITTER_MS = 750;
const REFRESH_LOCK = 'pleya.auth.refresh';

/** De wachttijd van een 429: `Retry-After`, anders `details.retry_after_ms`, anders een seconde. */
function refreshRetryDelayMs(response: Response, error: unknown): number {
  const seconds = Number(response.headers.get('Retry-After'));
  if (Number.isFinite(seconds) && seconds > 0) return seconds * 1000;
  return toApiError(response.status, error).retryAfterMs ?? 1000;
}

/** Het deel van `LockManager` dat hier gebruikt wordt. */
export interface RefreshLocks {
  request<T>(name: string, callback: () => Promise<T>): Promise<T>;
}

/** Het slot van deze browser, of null waar de API niet bestaat. */
export function browserLocks(): RefreshLocks | null {
  return (globalThis.navigator as { locks?: RefreshLocks } | undefined)?.locks ?? null;
}

type RefreshBody = components['schemas']['RefreshRequest'];

/** Wat de client met de verversing deelt; de sessie zelf blijft van hem. */
export interface RefreshHost {
  readonly tokens: TokenStore;
  readonly generation: number;
  /** Een ander tabblad wisselde van account of meldde af. */
  readonly replaced: boolean;
  cookieAuth: boolean;
  readonly supportsUpgrade: boolean;
  readonly raw: Client<paths>;
  readonly delay: (ms: number) => Promise<void>;
  readonly locks: RefreshLocks | null;
  loseSession(): void;
}

export class TokenRefresher {
  #host: RefreshHost;
  #round: Promise<boolean> | null = null;
  #roundGeneration = -1;
  #unavailable = false;
  #refused: ApiError | null = null;
  #upgradeRefused = false;

  constructor(host: RefreshHost) {
    this.#host = host;
  }

  /** De laatste verversing gaf op zonder oordeel over het token (429, 5xx, geen verbinding). De sessie bestaat nog. */
  get unavailable(): boolean { return this.#unavailable; }
  /** De server weigerde deze verversing om iets dat herhalen niet oplost, zoals `auth.origin_rejected`. De sessie bestaat nog. */
  get refused(): ApiError | null { return this.#refused; }

  /** Een oordeel over een vorige ronde zegt niets over de volgende. */
  clearFailure(): void {
    this.#unavailable = false;
    this.#refused = null;
  }

  /**
   * Een ander tabblad stapte over op de cookie: het token is weg en de epoch is gelijk,
   * want er is niemand in- of uitgelogd. Zonder dit verliest dit tabblad zijn sessie.
   */
  followUpgrade(): void {
    const { tokens, cookieAuth, supportsUpgrade, replaced } = this.#host;
    if (cookieAuth || !supportsUpgrade || replaced || tokens.refreshToken) return;
    this.#host.cookieAuth = true;
    tokens.setMemoryOnly(true);
  }

  #stale(): boolean {
    const { tokens, cookieAuth, replaced } = this.#host;
    return (!cookieAuth && !tokens.refreshToken) || (cookieAuth && tokens.signedOut) || replaced;
  }

  /**
   * Vernieuwt het tokenpaar, hoogstens één keer tegelijk.
   *
   * Zonder die samenvoeging stuurt een scherm met vier gelijktijdige aanvragen
   * vier refreshverzoeken. Het refreshtoken roteert bij elk gebruik, dus de
   * tweede is per definitie hergebruik: de server trekt dan de hele keten in
   * (auth.refresh_token_reused) en de gebruiker vliegt eruit terwijl er niets
   * mis was.
   */
  run(): Promise<boolean> {
    const host = this.#host;
    const generation = host.generation;
    if (this.#round && this.#roundGeneration === generation) return this.#round;
    this.#roundGeneration = generation;
    this.clearFailure();
    this.followUpgrade();

    // De cookie is van het hele browserprofiel: na een wissel in een ander tabblad zou deze client
    // zich als die andere gebruiker verversen en zijn aanvraag met diens credential herhalen.
    if (this.#stale()) {
      host.loseSession();
      return Promise.resolve(false);
    }
    this.#round = this.#attempts(generation, host.tokens.accessToken);
    return this.#round;
  }

  async #attempts(generation: number, startedWith: string | null): Promise<boolean> {
    const host = this.#host;
    try {
      for (let attempt = 1; ; attempt++) {
        const send = () => this.#attempt(generation, attempt);
        const outcome = await (host.locks ? host.locks.request(REFRESH_LOCK, send) : send());
        if (typeof outcome === 'boolean') return outcome;
        await host.delay(outcome + Math.random() * REFRESH_LIMIT_JITTER_MS);
        if (generation !== host.generation) return false;
        // Alleen een ander token telt als geslaagd: het accesstoken staat per tabblad, dus hetzelfde
        // token is geen teken dat iemand ververst heeft, ook al is het lokaal nog geldig.
        const access = host.tokens.accessToken;
        if (access && access !== startedWith) return true;
      }
    } catch {
      // Een netwerkstoring is geen verlopen sessie: het token blijft staan
      // zodat de volgende poging het opnieuw kan proberen.
      if (generation === host.generation) this.#unavailable = true;
      return false;
    } finally {
      if (this.#roundGeneration === generation) this.#round = null;
    }
  }

  /** Eén aanvraag. Geeft de uitkomst van de ronde, of hoe lang er gewacht moet worden voor de volgende. */
  async #attempt(generation: number, attempt: number): Promise<boolean | number> {
    const host = this.#host;
    if (generation !== host.generation) return false;
    // Na het wachten op het slot of op een 429 kan een ander tabblad alles veranderd hebben.
    this.followUpgrade();
    if (this.#stale()) {
      host.loseSession();
      return false;
    }
    const upgrade = !host.cookieAuth && host.supportsUpgrade && !this.#upgradeRefused;
    const body = this.#body(upgrade);
    const { data, error, response } = await host.raw.POST('/auth/refresh', { body });
    if (generation !== host.generation) return false;
    if (response.status === 429) {
      // Geen sessieverlies: de server heeft niets geroteerd en het token is nog goed. Tokens blijven
      // staan, ook als deze ronde opgeeft; de aanvraag die erop wachtte faalt en de volgende probeert het.
      const wait = refreshRetryDelayMs(response, error);
      if (attempt >= REFRESH_LIMIT_ATTEMPTS || wait > REFRESH_LIMIT_MAX_WAIT_MS) {
        this.#unavailable = true;
        return false;
      }
      return wait;
    }
    if (host.replaced || (error !== undefined && isSessionRejected(toApiError(response.status, error)))) {
      host.loseSession();
      return false;
    }
    if (error !== undefined || !data) {
      const failure = toApiError(response.status, error);
      if (failure.code === 'auth.origin_rejected') {
        // Geweigerd vóór de rotatie, dus het token is nog goed, en deze sessie werkte al zonder cookie.
        if (upgrade) {
          this.#upgradeRefused = true;
          return 0;
        }
        // Opnieuw proberen verandert hier niets: de origin van deze pagina wordt geweigerd. Dat
        // is een instelling van de server of proxy, dus de tokens blijven en de diagnose gaat mee.
        this.#refused = failure;
        return false;
      }
      // Alleen een afwijzing van het token beëindigt de sessie. Een 5xx of een proxyfout zegt
      // daar niets over; het token blijft staan en de volgende poging probeert het opnieuw.
      this.#unavailable = true;
      return false;
    }
    // Vóór het slot vrijkomt: het volgende tabblad moet dit token al zien.
    if (upgrade) {
      host.cookieAuth = true;
      host.tokens.setMemoryOnly(true);
    }
    host.tokens.set(data);
    return true;
  }

  // Elke poging leest het token opnieuw: een ander tabblad kan het tijdens het wachten geroteerd hebben.
  #body(upgrade: boolean): RefreshBody {
    if (this.#host.cookieAuth) return { credential_mode: 'cookie' };
    const refresh_token = this.#host.tokens.refreshToken!;
    return upgrade ? { refresh_token, credential_mode: 'cookie_upgrade' } : { refresh_token };
  }
}
