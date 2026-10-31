/** Cookie-capable logins keep access in memory; a legacy session in storage moves to the cookie at its next refresh, where the server can. */

const REFRESH_KEY = 'pleya.refresh_token';
const ACCESS_KEY = 'pleya.access_token';
// Gedeeld tussen tabbladen: de HttpOnly-cookie is dat ook, en die is voor JavaScript niet te wissen.
const EPOCH_KEY = 'pleya.session_epoch';
const SIGNED_OUT_KEY = 'pleya.signed_out';
// Zegt dat er een cookie is, geen credential. De cookie zelf is HttpOnly en dus onzichtbaar voor deze code.
const COOKIE_SESSION_KEY = 'pleya.cookie_session';

/** Marge op het vervalmoment, zodat een token niet onderweg verloopt. */
const EXPIRY_SKEW_MS = 30_000;

export interface TokenStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

function safeStorage(pick: () => Storage): TokenStorage | null {
  try {
    const store = pick();
    return store ?? null;
  } catch {
    // Een browser met opslag uit. De sessie werkt dan tot de pagina herlaadt.
    return null;
  }
}

interface StoredAccess {
  token: string;
  expiresAt: number;
}

export class TokenStore {
  #memoryAccess: StoredAccess | null = null;
  #memoryOnly = false;
  #persistent: TokenStorage | null;
  #session: TokenStorage | null;
  #now: () => number;

  constructor(
    persistent: TokenStorage | null = safeStorage(() => localStorage),
    session: TokenStorage | null = safeStorage(() => sessionStorage),
    now: () => number = () => Date.now()
  ) {
    this.#persistent = persistent;
    this.#session = session;
    this.#now = now;
  }

  setMemoryOnly(value: boolean): void {
    if (value === this.#memoryOnly) return;
    this.#clearTokens();
    this.#memoryOnly = value;
  }

  #readAccess(): StoredAccess | null {
    if (this.#memoryOnly) return this.#memoryAccess;
    if (this.#memoryAccess) return this.#memoryAccess;
    try {
      const raw = this.#session?.getItem(ACCESS_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as StoredAccess;
      if (typeof parsed?.token !== 'string' || typeof parsed?.expiresAt !== 'number') return null;
      this.#memoryAccess = parsed;
      return parsed;
    } catch {
      return null;
    }
  }

  /** Het accesstoken, of null zodra het (bijna) verlopen is. */
  get accessToken(): string | null {
    const stored = this.#readAccess();
    if (!stored) return null;
    if (stored.expiresAt - EXPIRY_SKEW_MS <= this.#now()) return null;
    return stored.token;
  }

  get refreshToken(): string | null {
    if (this.#memoryOnly) return null;
    try {
      return this.#persistent?.getItem(REFRESH_KEY) ?? null;
    } catch {
      return null;
    }
  }

  /**
   * `refresh_token` is optioneel omdat het contract het sinds S1.8 weglaat
   * wanneer de aanvraag `credential_mode: cookie` droeg: het credential zit dan
   * in een HttpOnly-cookie en de pagina hoort het niet te zien. Wat hier
   * telt is dat een antwoord zonder dat veld geen `undefined` in `localStorage`
   * schrijft en daarna als bewaard token terugleest.
   */
  set(pair: { access_token: string; refresh_token?: string; expires_in_ms?: number }): void {
    const lifetime = typeof pair.expires_in_ms === 'number' ? pair.expires_in_ms : 0;
    this.#memoryAccess = {
      token: pair.access_token,
      expiresAt: this.#now() + lifetime
    };
    this.#write(COOKIE_SESSION_KEY, this.#memoryOnly ? '1' : null);
    if (this.#memoryOnly) return;
    try {
      this.#session?.setItem(ACCESS_KEY, JSON.stringify(this.#memoryAccess));
      if (pair.refresh_token) {
        this.#persistent?.setItem(REFRESH_KEY, pair.refresh_token);
      } else {
        this.#persistent?.removeItem(REFRESH_KEY);
      }
    } catch {
      // Opslag geweigerd: de sessie blijft in het geheugen bestaan.
    }
  }

  /** De sessie is voorbij: de tokens weg, en ook de aantekening dat er een cookie is. */
  clear(): void {
    this.#clearTokens();
    this.#write(COOKIE_SESSION_KEY, null);
  }

  /**
   * Alleen wat van dit tabblad is. Voor een tabblad dat vervangen is: het refreshtoken en de aantekening
   * in localStorage horen dan bij de login in een ander tabblad.
   */
  clearLocal(): void {
    this.#memoryAccess = null;
    try {
      this.#session?.removeItem(ACCESS_KEY);
    } catch {
      // niets te doen
    }
  }

  #clearTokens(): void {
    this.clearLocal();
    try {
      this.#persistent?.removeItem(REFRESH_KEY);
    } catch {
      // niets te doen
    }
  }

  #read(key: string): string | null {
    try {
      return this.#persistent?.getItem(key) ?? null;
    } catch {
      return null;
    }
  }

  #write(key: string, value: string | null): void {
    try {
      if (value === null) this.#persistent?.removeItem(key);
      else this.#persistent?.setItem(key, value);
    } catch {
      // Opslag geweigerd: de aantekening gaat verloren, de sessie niet.
    }
  }

  /** Verandert bij elke in- en uitlog in dit browserprofiel, ook in een ander tabblad. */
  get epoch(): string | null {
    return this.#read(EPOCH_KEY);
  }

  rotateEpoch(): string | null {
    try {
      this.#persistent?.setItem(EPOCH_KEY, `${Date.now()}-${Math.random()}`);
    } catch {
      // Opslag geweigerd: dan is er ook geen ander tabblad om mee te vergelijken.
    }
    return this.epoch;
  }

  /** Waar als een uitlog de cookiesessie niet op de server kon sluiten. */
  get signedOut(): boolean {
    return this.#read(SIGNED_OUT_KEY) !== null;
  }

  setSignedOut(value: boolean): void {
    try {
      if (value) this.#persistent?.setItem(SIGNED_OUT_KEY, '1');
      else this.#persistent?.removeItem(SIGNED_OUT_KEY);
    } catch {
      // niets te doen
    }
  }

  /** Er is iets om mee te beginnen: een lopende sessie of een te verzilveren refreshtoken. */
  get hasSomething(): boolean {
    return this.accessToken !== null || this.refreshToken !== null;
  }

  /**
   * Of deze browser bij het laatste contact ingelogd was. Dat is meer dan `hasSomething`: een cookiesessie
   * heeft na een herlaadbeurt geen enkel token in beeld, en als `GET /info` dan mislukt weet deze client ook nog
   * niet dat de server cookies kent. Dit is een aantekening en geen oordeel: alleen de server weet of de sessie leeft.
   *
   * Alleen wat gedeeld is telt: een accesstoken staat per tabblad en overleeft een uitlog in een ander tabblad. Zonder
   * opslag is er geen ander tabblad en is dat token alles wat er is.
   */
  get signedIn(): boolean {
    if (!this.#persistent) return this.hasSomething;
    return this.refreshToken !== null || this.#read(COOKIE_SESSION_KEY) !== null;
  }
}
