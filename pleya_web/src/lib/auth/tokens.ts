/**
 * Waar de twee tokens staan.
 *
 * Het refreshtoken staat in `localStorage`, en dat is een vastgelegde afweging
 * en geen eindmodel. Een strikte CSP maakt XSS moeilijker, niet onmogelijk;
 * zolang het token vanuit JavaScript bereikbaar is, is het bij een geslaagde
 * injectie te stelen. Rotatie met hergebruikdetectie aan de serverkant begrenst
 * de schade zonder hem op te heffen. Het model dat dit werkelijk oplost is een
 * door de server gezette HttpOnly-cookie, en dat is een wijziging van het
 * authcontract met een CSRF-afweging eraan vast. Zie onderdeel 4.2 van
 * docs/pleya-server-ps3w-proposal.md.
 *
 * Het accesstoken staat in `sessionStorage`, met zijn vervalmoment ernaast.
 * Dat is geen extra risico bovenop het bovenstaande — het is dezelfde
 * JS-bereikbare opslag, tabgebonden en korter houdbaar — en het lost een
 * probleem op dat "alleen in het geheugen" veroorzaakt: dan heeft elke
 * herlaadbeurt een refresh nodig, het refreshtoken roteert bij elk gebruik, en
 * een herlaadbeurt die middenin die aanvraag valt verbruikt het oude token
 * zonder het nieuwe te ontvangen. De volgende poging is dan hergebruik, de
 * server trekt de hele keten in, en de gebruiker vliegt eruit terwijl hij
 * alleen F5 indrukte. Met een bewaard accesstoken is een refresh de
 * uitzondering in plaats van de regel.
 *
 * Er is bewust geen uitlogendpoint aangeroepen: het protocol heeft er geen
 * (5.2 van hetzelfde voorstel). Afmelden is hier lokaal, en het refreshtoken
 * vervalt vanzelf of bij de volgende rotatie.
 */

const REFRESH_KEY = 'pleya.refresh_token';
const ACCESS_KEY = 'pleya.access_token';

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

  #readAccess(): StoredAccess | null {
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
    try {
      return this.#persistent?.getItem(REFRESH_KEY) ?? null;
    } catch {
      return null;
    }
  }

  set(pair: { access_token: string; refresh_token: string; expires_in_ms?: number }): void {
    const lifetime = typeof pair.expires_in_ms === 'number' ? pair.expires_in_ms : 0;
    this.#memoryAccess = {
      token: pair.access_token,
      expiresAt: this.#now() + lifetime
    };
    try {
      this.#session?.setItem(ACCESS_KEY, JSON.stringify(this.#memoryAccess));
      this.#persistent?.setItem(REFRESH_KEY, pair.refresh_token);
    } catch {
      // Opslag geweigerd: de sessie blijft in het geheugen bestaan.
    }
  }

  clear(): void {
    this.#memoryAccess = null;
    try {
      this.#session?.removeItem(ACCESS_KEY);
      this.#persistent?.removeItem(REFRESH_KEY);
    } catch {
      // niets te doen
    }
  }

  /** Er is iets om mee te beginnen: een lopende sessie of een te verzilveren refreshtoken. */
  get hasSomething(): boolean {
    return this.accessToken !== null || this.refreshToken !== null;
  }
}
