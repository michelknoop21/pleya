/**
 * De enige plek waar Pleya Web met de server praat.
 *
 * REST loopt over `/pleya/v1`; MCP gebruikt zijn eigen transport op `/mcp`.
 * Er is geen `/internal/`-route of directe database. DEC-046 geeft de
 * meegeleverde bundel geen extra rechten.
 *
 * De paden en de typen komen uit `schema.d.ts`, dat gegenereerd is uit
 * `docs/pleya-protocol/v1/openapi.yaml`. Het aparte MCP-HTTP-contract staat
 * in `mcpHttp.ts` en gebruikt dezelfde authenticatiemiddleware.
 */
import createClient, { type Client, type Middleware } from 'openapi-fetch';

import type { paths } from './schema';
import { isMcpToolSummary, type McpHttpPaths, type McpToolSummary } from './mcpHttp';
import { type ApiError, TransportError, toApiError } from './errors';
import { browserLocks, REFRESH_TIMEOUT_MS, TokenRefresher, type RefreshLocks } from './tokenRefresher';
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
  /** Het slot tussen tabbladen; zonder waarde `navigator.locks` als die bestaat. */
  locks?: RefreshLocks | null;
  /** Hoe lang het slot en de verversing elk mogen duren; alleen tests vervangen dit. */
  refreshTimeoutMs?: number;
}

export class PleyaClient {
  readonly baseUrl: string;
  readonly tokens: TokenStore;

  #raw: Client<paths>;
  #mcpRaw: Client<McpHttpPaths>;
  #fetch: FetchLike;
  #refresher: TokenRefresher;
  #sessionGeneration = 0;
  #epoch: string | null;
  #supportsCookieAuth = false;
  #supportsCookieUpgrade = false;
  #cookieAuth = false;
  #requests = new WeakMap<Request, { generation: number; replay: Request }>();

  get sessionGeneration(): number { return this.#sessionGeneration; }
  /** De laatste verversing gaf op zonder oordeel over het token (429, 5xx, geen verbinding). De sessie bestaat nog. */
  get refreshUnavailable(): boolean { return this.#refresher.unavailable; }
  /** De server weigerde deze verversing om iets dat herhalen niet oplost, zoals `auth.origin_rejected`. De sessie bestaat nog. */
  get refreshRefused(): ApiError | null { return this.#refresher.refused; }
  #onSessionLost: (() => void) | undefined;

  constructor(options: PleyaClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
    this.tokens = options.tokens ?? new TokenStore();
    this.#fetch = options.fetch ?? ((...args) => globalThis.fetch(...args));
    this.#onSessionLost = options.onSessionLost;
    this.#epoch = this.tokens.epoch;

    this.#raw = createClient<paths>({
      baseUrl: this.baseUrl,
      fetch: this.#fetch
    });
    this.#raw.use(this.#authMiddleware());
    this.#mcpRaw = createClient<McpHttpPaths>({
      baseUrl: this.baseUrl.replace(/\/pleya\/v1\/?$/, ''),
      fetch: this.#fetch
    });
    this.#mcpRaw.use(this.#authMiddleware());

    const client = this;
    this.#refresher = new TokenRefresher({
      tokens: this.tokens,
      raw: this.#raw,
      delay: options.delay ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))),
      locks: options.locks === undefined ? browserLocks() : options.locks,
      timeoutMs: options.refreshTimeoutMs ?? REFRESH_TIMEOUT_MS,
      get generation() { return client.#sessionGeneration; },
      get replaced() { return client.tokens.epoch !== client.#epoch; },
      get supportsUpgrade() { return client.#supportsCookieUpgrade; },
      get cookieAuth() { return client.#cookieAuth; },
      set cookieAuth(value) { client.#cookieAuth = value; },
      loseSession: () => this.#loseSession()
    });
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

        const refreshed = await this.#refresher.run();
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

  #loseSession(): void {
    this.#sessionGeneration++;
    // Een ander tabblad wisselde van sessie: wat in localStorage staat is dan van die sessie, niet van deze.
    if (this.tokens.epoch !== this.#epoch) this.tokens.clearLocal();
    else this.tokens.clear();
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
    this.#supportsCookieUpgrade = this.#supportsCookieAuth && info.capabilities?.cookie_upgrade === true;
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
      server_name?: string;
      username: string;
      password: string;
    } & DeviceFields
  ): Promise<void> {
    const generation = ++this.#sessionGeneration;
    const { setup_code, server_name, ...credentials } = input;
    // SetupRequest is gesloten: credential_mode hoort bij login en refresh, en de server antwoordt erop
    // met een 401 die leest als een verkeerde setupcode. Setup levert dus altijd een refreshtoken in het
    // lichaam. Op een server met cookie_auth wordt dat nergens bewaard: de setupsessie gaat eerst dicht,
    // anders blijft hij als tweede rij in de toestellenlijst staan, en daarna volgt de cookielogin.
    const pair = await this.#unwrap(this.#raw.POST('/auth/setup', { body: { setup_code, ...credentials, ...(server_name === undefined ? {} : { server_name }) } }));
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
    this.#refresher.clearFailure();
    // Een geldig accesstoken overleeft een herlaadbeurt, dus meestal is er
    // niets te verversen. Dat scheelt niet alleen een aanvraag: het
    // refreshtoken roteert bij elk gebruik, en een refresh per paginaladen
    // maakt van elke herlaadbeurt een kans om er middenin te vallen.
    if (this.tokens.accessToken) return Promise.resolve(true);
    this.#refresher.followUpgrade();
    if (!this.#cookieAuth && !this.tokens.refreshToken) return Promise.resolve(false);
    if (this.#cookieAuth && this.tokens.signedOut) return Promise.resolve(false);
    return this.#refresher.run();
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
    this.#refresher.followUpgrade();
    // In cookiemodus is een verlopen accesstoken geen reden om de sessie te laten leven: de cookie is
    // voor JavaScript niet te wissen, en de volgende herlaadbeurt zou er weer mee inloggen.
    if (options.remote && this.#cookieAuth && !this.tokens.accessToken) await this.bearer();
    // Een overstap die nog onderweg is zet zo meteen een cookie. Hem afmelden kan pas met zijn antwoord,
    // dus de marker blijft staan, ook als die afmelding niet aankomt.
    let closed = !this.#cookieAuth && !this.#refresher.upgrading;
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
    this.#refresher.followUpgrade();
    if (!this.#cookieAuth && !this.tokens.refreshToken) return null;
    return (await this.#refresher.run()) ? this.tokens.accessToken : null;
  }

  async mcpTools(signal?: AbortSignal): Promise<McpToolSummary[]> {
    const response = await this.#unwrap(this.#mcpRaw.POST('/mcp', {
      body: { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} },
      headers: { Accept: 'application/json, text/event-stream', 'MCP-Protocol-Version': '2025-06-18' },
      signal
    }));
    const tools = response.result?.tools;
    if (response.error || !Array.isArray(tools) || !tools.every(isMcpToolSummary) || new Set(tools.map((tool) => tool.name)).size !== tools.length) {
      throw new TransportError(new Error('MCP tool list unavailable'));
    }
    return tools;
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

    if (response.status === 401 && (await this.#refresher.run())) {
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
