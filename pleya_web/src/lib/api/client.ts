/**
 * De enige plek waar Pleya Web met de server praat.
 *
 * Alles loopt over `/pleya/v1`. Er is geen tweede API, geen `/internal/`-route
 * en geen directe database, ook niet nu de bundel in dezelfde binary zit als
 * de server: DEC-046 legt vast dat co-distributie geen extra rechten geeft.
 *
 * De paden en de typen komen uit `schema.d.ts`, dat gegenereerd is uit
 * `docs/pleya-protocol/v1/openapi.yaml`. Een pad dat het contract niet kent
 * bestaat hier niet, want dan compileert het niet.
 */
import createClient, { type Client, type Middleware } from 'openapi-fetch';

import type { paths } from './schema';
import { ApiError, TransportError, toApiError } from './errors';
import { TokenStore } from '../auth/tokens';
import type { DeviceFields } from '../auth/device';
import type {
  Info,
  Item,
  ItemKind,
  ItemPage,
  Library,
  LibraryList,
  ServerDetail,
  Facets,
  LibraryItemsQuery,
  TokenPair,
  User
} from './types';

export const DEFAULT_BASE_URL = '/pleya/v1';

/**
 * Wat deze client van een fetch nodig heeft, en niet meer.
 *
 * Structureel getypeerd en niet als `typeof globalThis.fetch`: die vorm
 * verschilt per runtime (Bun hangt er `preconnect` aan), en dan zou een
 * testdubbel eigenschappen moeten hebben die hier nooit worden aangeroepen.
 */
export type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

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

/** De wachttijd van een 429: `Retry-After`, anders `details.retry_after_ms`, anders een seconde. */
function refreshRetryDelayMs(response: Response, error: unknown): number {
  const seconds = Number(response.headers.get('Retry-After'));
  if (Number.isFinite(seconds) && seconds > 0) return seconds * 1000;
  return toApiError(response.status, error).retryAfterMs ?? 1000;
}

/** Endpoints van klasse `public`: ze krijgen nooit een Authorization-header. */
const PUBLIC_PATHS = new Set(['/info', '/auth/setup', '/auth/login', '/auth/refresh']);

function isPublic(url: string, baseUrl: string): boolean {
  const base = new URL(baseUrl, url);
  const target = new URL(url, base);
  if (target.origin !== base.origin) return false;
  const prefix = base.pathname.replace(/\/$/, '');
  return target.pathname.startsWith(`${prefix}/`) && PUBLIC_PATHS.has(target.pathname.slice(prefix.length));
}

export interface PleyaClientOptions {
  baseUrl?: string;
  tokens?: TokenStore;
  fetch?: FetchLike;
  /** Wordt aangeroepen zodra de sessie onherstelbaar weg is. */
  onSessionLost?: () => void;
  /** Wachten tussen twee pogingen; alleen tests vervangen dit. */
  delay?: (ms: number) => Promise<void>;
}

export class PleyaClient {
  readonly baseUrl: string;
  readonly tokens: TokenStore;

  #raw: Client<paths>;
  #fetch: FetchLike;
  #refreshing: Promise<boolean> | null = null;
  #refreshGeneration = -1;
  #refreshThrottled = false;
  #sessionGeneration = 0;
  #epoch: string | null;
  #supportsCookieAuth = false;
  #cookieAuth = false;
  #requests = new WeakMap<Request, { generation: number; replay: Request }>();

  get sessionGeneration(): number { return this.#sessionGeneration; }
  /** De laatste verversing gaf op bij een 429. De sessie bestaat nog; de server wil alleen even niet. */
  get refreshThrottled(): boolean { return this.#refreshThrottled; }
  #onSessionLost: (() => void) | undefined;
  #delay: (ms: number) => Promise<void>;

  constructor(options: PleyaClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
    this.tokens = options.tokens ?? new TokenStore();
    this.#fetch = options.fetch ?? ((...args) => globalThis.fetch(...args));
    this.#onSessionLost = options.onSessionLost;
    this.#delay = options.delay ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.#epoch = this.tokens.epoch;

    this.#raw = createClient<paths>({
      baseUrl: this.baseUrl,
      fetch: this.#fetch
    });
    this.#raw.use(this.#authMiddleware());
  }

  #authMiddleware(): Middleware {
    return {
      onRequest: ({ request }) => {
        if (isPublic(request.url, this.baseUrl)) return request;
        this.#requests.set(request, { generation: this.#sessionGeneration, replay: request.clone() });
        const access = this.tokens.accessToken;
        if (access) request.headers.set('Authorization', `Bearer ${access}`);
        return request;
      },
      onResponse: async ({ request, response }) => {
        if (response.status !== 401) return response;
        if (isPublic(request.url, this.baseUrl)) return response;
        if (request.headers.get('x-pleya-retry') === '1') return response;
        const original = this.#requests.get(request);
        if (!original || original.generation !== this.#sessionGeneration) return response;
        const generation = original.generation;

        const refreshed = await this.#refreshOnce();
        if (!refreshed || generation !== this.#sessionGeneration) return response;

        // Opnieuw sturen met het verse accesstoken. De markering voorkomt dat
        // een tweede 401 een lus wordt.
        const retry = new Request(original.replay, { headers: new Headers(request.headers) });
        retry.headers.set('Authorization', `Bearer ${this.tokens.accessToken ?? ''}`);
        retry.headers.set('x-pleya-retry', '1');
        return await this.#fetch(retry);
      }
    };
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
  #refreshOnce(): Promise<boolean> {
    const generation = this.#sessionGeneration;
    if (this.#refreshing && this.#refreshGeneration === generation) return this.#refreshing;
    this.#refreshGeneration = generation;

    // De cookie is van het hele browserprofiel: na een wissel in een ander tabblad zou deze client
    // zich als die andere gebruiker verversen en zijn aanvraag met diens credential herhalen.
    const replaced = () => this.tokens.epoch !== this.#epoch;
    const stale = () => (!this.#cookieAuth && !this.tokens.refreshToken) || (this.#cookieAuth && this.tokens.signedOut) || replaced();
    if (stale()) {
      this.#loseSession();
      return Promise.resolve(false);
    }

    this.#refreshThrottled = false;
    this.#refreshing = (async () => {
      try {
        for (let attempt = 1; ; attempt++) {
          // Elke poging leest het token opnieuw: een ander tabblad kan het tijdens het wachten geroteerd hebben.
          const refresh = this.tokens.refreshToken;
          const { data, error, response } = await this.#raw.POST('/auth/refresh', {
            body: this.#cookieAuth ? { credential_mode: 'cookie' } : { refresh_token: refresh! }
          });
          if (generation !== this.#sessionGeneration) return false;
          if (response.status === 429) {
            // Geen sessieverlies: de server heeft niets geroteerd en het token is nog goed. Tokens blijven
            // staan, ook als deze ronde opgeeft; de aanvraag die erop wachtte faalt en de volgende probeert het.
            const wait = refreshRetryDelayMs(response, error);
            if (attempt >= REFRESH_LIMIT_ATTEMPTS || wait > REFRESH_LIMIT_MAX_WAIT_MS) {
              this.#refreshThrottled = true;
              return false;
            }
            await this.#delay(wait + Math.random() * REFRESH_LIMIT_JITTER_MS);
            if (generation !== this.#sessionGeneration) return false;
            // Een ander tabblad ververste intussen, of deze client kreeg via de bewaarde sleutel een nieuw token.
            if (this.tokens.accessToken) return true;
            if (stale()) {
              this.#loseSession();
              return false;
            }
            continue;
          }
          if (error || !data || replaced()) {
            this.#loseSession();
            if (error) throw toApiError(response.status, error);
            return false;
          }
          this.tokens.set(data);
          return true;
        }
      } catch (err) {
        if (err instanceof ApiError) return false;
        // Een netwerkstoring is geen verlopen sessie: het token blijft staan
        // zodat de volgende poging het opnieuw kan proberen.
        return false;
      } finally {
        if (this.#refreshGeneration === generation) this.#refreshing = null;
      }
    })();

    return this.#refreshing;
  }

  #loseSession(): void {
    this.#sessionGeneration++;
    this.tokens.clear();
    this.#onSessionLost?.();
  }

  /** Wikkelt een openapi-fetch-resultaat om naar "waarde of geworpen fout". */
  async #unwrap<T>(
    call: Promise<{ data?: T; error?: unknown; response: Response }>
  ): Promise<T> {
    const generation = this.#sessionGeneration;
    let result: { data?: T; error?: unknown; response: Response };
    try {
      result = await call;
    } catch (cause) {
      throw new TransportError(cause);
    }
    if (result.error !== undefined || result.data === undefined) {
      throw toApiError(result.response.status, result.error);
    }
    if (generation !== this.#sessionGeneration) throw new TransportError(new Error('Account changed during request'));
    return result.data;
  }

  // --- Ontdekken en authenticatie ---------------------------------------

  async info(signal?: AbortSignal): Promise<Info> {
    const info = await this.#unwrap(this.#raw.GET('/info', { signal }));
    this.#supportsCookieAuth = info.capabilities?.cookie_auth === true;
    if (!this.#supportsCookieAuth) {
      this.#cookieAuth = false;
      this.tokens.setMemoryOnly(false);
    } else if (!this.tokens.refreshToken) {
      this.#cookieAuth = true;
      this.tokens.setMemoryOnly(true);
    }
    return info;
  }

  /**
   * `device_id` en `device_name` gaan alleen mee als de aanroeper ze geeft, en
   * dat doet hij alleen bij `capabilities.sessions` (zie `deviceFields`).
   */
  async setup(
    input: {
      setup_code: string;
      username: string;
      password: string;
    } & DeviceFields
  ): Promise<void> {
    const generation = ++this.#sessionGeneration;
    const { setup_code, ...credentials } = input;
    // SetupRequest is gesloten: credential_mode hoort bij login en refresh, en de server antwoordt erop
    // met een 401 die leest als een verkeerde setupcode. Setup levert dus altijd een refreshtoken in het
    // lichaam. Op een server met cookie_auth wordt dat nergens bewaard: de setupsessie gaat eerst dicht,
    // anders blijft hij als tweede rij in de toestellenlijst staan, en daarna volgt de cookielogin.
    const pair = await this.#unwrap(this.#raw.POST('/auth/setup', { body: { setup_code, ...credentials } }));
    if (generation !== this.#sessionGeneration) throw new Error('Account changed during setup');
    if (!this.#supportsCookieAuth) {
      this.#cookieAuth = false;
      this.tokens.setMemoryOnly(false);
      this.tokens.set(pair);
      this.#markSignedIn();
      return;
    }
    await this.#raw
      .POST('/auth/logout', { headers: { Authorization: `Bearer ${pair.access_token}` } })
      .catch(() => undefined);
    if (generation !== this.#sessionGeneration) throw new Error('Account changed during setup');
    // De setupcode is nu verbruikt, dus een fout hier is geen mislukte setup: de eigenaar bestaat en de
    // router stuurt hem zonder sessie naar het inlogscherm.
    await this.login(credentials).catch(() => undefined);
  }

  async login(input: { username: string; password: string } & DeviceFields): Promise<TokenPair> {
    const generation = ++this.#sessionGeneration;
    const cookie = this.#supportsCookieAuth;
    const pair = await this.#unwrap(this.#raw.POST('/auth/login', { body: { ...input, ...(cookie ? { credential_mode: 'cookie' as const } : {}) } }));
    if (generation !== this.#sessionGeneration) throw new Error('Account changed during login');
    this.#cookieAuth = cookie;
    this.tokens.setMemoryOnly(cookie);
    this.tokens.set(pair);
    this.#markSignedIn();
    return pair;
  }

  #markSignedIn(): void {
    this.tokens.setSignedOut(false);
    this.#epoch = this.tokens.rotateEpoch();
  }

  /**
   * Zet een bewaard refreshtoken om in een lopende sessie.
   *
   * Geeft `false` wanneer er niets te herstellen valt of het token niet meer
   * geldig is; dat is een normale toestand en geen fout.
   */
  restore(): Promise<boolean> {
    // Een geldig accesstoken overleeft een herlaadbeurt, dus meestal is er
    // niets te verversen. Dat scheelt niet alleen een aanvraag: het
    // refreshtoken roteert bij elk gebruik, en een refresh per paginaladen
    // maakt van elke herlaadbeurt een kans om er middenin te vallen.
    if (this.tokens.accessToken) return Promise.resolve(true);
    if (!this.#cookieAuth && !this.tokens.refreshToken) return Promise.resolve(false);
    if (this.#cookieAuth && this.tokens.signedOut) return Promise.resolve(false);
    return this.#refreshOnce();
  }

  /**
   * Meldt af. Met `remote` trekt de server eerst de eigen sessie in
   * (`POST /auth/logout`, onder `capabilities.sessions`); anders bleef die rij
   * tot het eind van zijn refreshketen in de toestellenlijst staan, en kreeg
   * dezelfde browser na opnieuw inloggen een tweede rij erbij.
   *
   * Lukt de aanroep niet, dan meldt de browser toch af: lokaal uitloggen hoort
   * niet te hangen aan een server die er even niet is. De sessie verloopt dan
   * zoals vroeger, of de opruimronde neemt hem mee. In cookiemodus leeft de
   * cookie zo lang door, dus een marker houdt `restore()` tegen tot de volgende
   * login; anders is de gebruiker na een herlaadbeurt weer stilletjes binnen.
   */
  async signOut(options: { remote?: boolean } = {}): Promise<void> {
    const generation = ++this.#sessionGeneration;
    // In cookiemodus is een verlopen accesstoken geen reden om de sessie te laten leven: de cookie is
    // voor JavaScript niet te wissen, en de volgende herlaadbeurt zou er weer mee inloggen.
    if (options.remote && this.#cookieAuth && !this.tokens.accessToken) await this.bearer();
    let closed = !this.#cookieAuth;
    if (options.remote && this.tokens.accessToken) {
      try {
        const { response } = await this.#raw.POST('/auth/logout', {});
        closed = closed || response.ok;
      } catch {
        // Geen verbinding: alleen lokaal.
      }
    }
    if (generation !== this.#sessionGeneration) return;
    this.tokens.clear();
    this.tokens.setSignedOut(!closed);
    this.#epoch = this.tokens.rotateEpoch();
  }

  /**
   * Een geldig accesstoken voor een aanvraag die niet via deze client loopt,
   * zoals de segmenten die hls.js zelf ophaalt. Verlopen betekent eerst één
   * keer verversen; het token komt alleen in een header, nooit in een URL.
   */
  async bearer(): Promise<string | null> {
    const access = this.tokens.accessToken;
    if (access) return access;
    if (!this.#cookieAuth && !this.tokens.refreshToken) return null;
    return (await this.#refreshOnce()) ? this.tokens.accessToken : null;
  }

  server(signal?: AbortSignal): Promise<ServerDetail> {
    return this.#unwrap(this.#raw.GET('/server', { signal }));
  }

  /** De aanvrager zelf, met zijn rol. Klasse `authenticated`, elke rol krijgt 200. */
  me(signal?: AbortSignal): Promise<User> {
    return this.#unwrap(this.#raw.GET('/users/me', { signal }));
  }

  /**
   * Eén getypeerde aanvraag met dezelfde authenticatie en foutvertaling als de
   * methoden hier. Bedoeld voor een tweede API-module (`admin.ts`), zodat niet
   * elke beheerroute in dit bestand een methode hoeft te krijgen.
   */
  request<T>(
    call: (raw: Client<paths>) => Promise<{ data?: T; error?: unknown; response: Response }>
  ): Promise<T> {
    return this.#unwrap(call(this.#raw));
  }

  // --- Catalogus --------------------------------------------------------

  async libraries(signal?: AbortSignal): Promise<Library[]> {
    const list = await this.#unwrap<LibraryList>(this.#raw.GET('/libraries', { signal }));
    return list.items;
  }

  libraryItems(
    libraryId: string,
    query: LibraryItemsQuery = {},
    signal?: AbortSignal
  ): Promise<ItemPage> {
    return this.#unwrap(
      this.#raw.GET('/libraries/{library_id}/items', {
        params: { path: { library_id: libraryId }, query },
        signal
      })
    );
  }

  libraryFacets(libraryId: string, signal?: AbortSignal): Promise<Facets> {
    return this.#unwrap(this.#raw.GET('/libraries/{library_id}/facets', {
      params: { path: { library_id: libraryId } }, signal
    }));
  }

  item(itemId: string, signal?: AbortSignal): Promise<Item> {
    return this.#unwrap(
      this.#raw.GET('/items/{item_id}', { params: { path: { item_id: itemId } }, signal })
    );
  }

  children(
    itemId: string,
    query: { limit?: number; cursor?: string } = {},
    signal?: AbortSignal
  ): Promise<ItemPage> {
    return this.#unwrap(
      this.#raw.GET('/items/{item_id}/children', {
        params: { path: { item_id: itemId }, query },
        signal
      })
    );
  }

  search(
    query: { q: string; kind?: ItemKind; limit?: number; cursor?: string },
    signal?: AbortSignal
  ): Promise<ItemPage> {
    return this.#unwrap(this.#raw.GET('/search', { params: { query }, signal }));
  }

  hub(
    hubId: 'recently_added' | 'continue_watching' | 'next_up',
    query: { library_id?: string; limit?: number; cursor?: string } = {},
    signal?: AbortSignal
  ): Promise<ItemPage> {
    return this.#unwrap(
      this.#raw.GET('/hubs/{hub_id}', { params: { path: { hub_id: hubId }, query }, signal })
    );
  }

  // --- Artwork ----------------------------------------------------------

  /**
   * Haalt de bytes van een afbeelding op.
   *
   * `GET /artwork/{id}` is klasse `authenticated` en accepteert uitsluitend
   * een Authorization-header, en een `<img src>` kan er geen zetten. De bytes
   * komen dus hier binnen en gaan als object-URL aan het element. Een
   * querytoken zou een protocolwijziging zijn en die valt buiten PS-3W.
   */
  async artworkBlob(artworkId: string, signal?: AbortSignal, width?: number): Promise<Blob> {
    const base = `${this.baseUrl}/artwork/${encodeURIComponent(artworkId)}`;
    // Alleen met een gekozen artworkladder-trede; anders het origineel.
    const url = width !== undefined ? `${base}?width=${width}` : base;
    const headers = new Headers();
    const access = this.tokens.accessToken;
    if (access) headers.set('Authorization', `Bearer ${access}`);

    let response: Response;
    try {
      response = await this.#fetch(url, { headers, signal });
    } catch (cause) {
      throw new TransportError(cause);
    }

    if (response.status === 401 && (await this.#refreshOnce())) {
      const retryHeaders = new Headers();
      retryHeaders.set('Authorization', `Bearer ${this.tokens.accessToken ?? ''}`);
      try {
        response = await this.#fetch(url, { headers: retryHeaders, signal });
      } catch (cause) {
        throw new TransportError(cause);
      }
    }

    if (!response.ok) {
      let body: unknown;
      try {
        body = await response.json();
      } catch {
        body = undefined;
      }
      throw toApiError(response.status, body);
    }
    return await response.blob();
  }
}
