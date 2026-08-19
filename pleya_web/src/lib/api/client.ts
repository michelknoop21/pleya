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
import type {
  Info,
  Item,
  ItemKind,
  ItemPage,
  Library,
  LibraryList,
  ServerDetail,
  SortOption,
  TokenPair
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
  const path = url.startsWith(baseUrl) ? url.slice(baseUrl.length) : url;
  for (const p of PUBLIC_PATHS) if (path === p || path.startsWith(`${p}?`)) return true;
  return false;
}

export interface PleyaClientOptions {
  baseUrl?: string;
  tokens?: TokenStore;
  fetch?: FetchLike;
  /** Wordt aangeroepen zodra de sessie onherstelbaar weg is. */
  onSessionLost?: () => void;
}

export class PleyaClient {
  readonly baseUrl: string;
  readonly tokens: TokenStore;

  #raw: Client<paths>;
  #fetch: FetchLike;
  #refreshing: Promise<boolean> | null = null;
  #onSessionLost: (() => void) | undefined;

  constructor(options: PleyaClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
    this.tokens = options.tokens ?? new TokenStore();
    this.#fetch = options.fetch ?? ((...args) => globalThis.fetch(...args));
    this.#onSessionLost = options.onSessionLost;

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
        const access = this.tokens.accessToken;
        if (access) request.headers.set('Authorization', `Bearer ${access}`);
        return request;
      },
      onResponse: async ({ request, response }) => {
        if (response.status !== 401) return response;
        if (isPublic(request.url, this.baseUrl)) return response;
        if (request.headers.get('x-pleya-retry') === '1') return response;

        const refreshed = await this.#refreshOnce();
        if (!refreshed) return response;

        // Opnieuw sturen met het verse accesstoken. De markering voorkomt dat
        // een tweede 401 een lus wordt.
        const retry = new Request(request, { headers: new Headers(request.headers) });
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
    if (this.#refreshing) return this.#refreshing;

    const refresh = this.tokens.refreshToken;
    if (!refresh) {
      this.#loseSession();
      return Promise.resolve(false);
    }

    this.#refreshing = (async () => {
      try {
        const { data, error, response } = await this.#raw.POST('/auth/refresh', {
          body: { refresh_token: refresh }
        });
        if (error || !data) {
          this.#loseSession();
          if (error) throw toApiError(response.status, error);
          return false;
        }
        this.tokens.set(data);
        return true;
      } catch (err) {
        if (err instanceof ApiError) return false;
        // Een netwerkstoring is geen verlopen sessie: het token blijft staan
        // zodat de volgende poging het opnieuw kan proberen.
        return false;
      } finally {
        this.#refreshing = null;
      }
    })();

    return this.#refreshing;
  }

  #loseSession(): void {
    this.tokens.clear();
    this.#onSessionLost?.();
  }

  /** Wikkelt een openapi-fetch-resultaat om naar "waarde of geworpen fout". */
  async #unwrap<T>(
    call: Promise<{ data?: T; error?: unknown; response: Response }>
  ): Promise<T> {
    let result: { data?: T; error?: unknown; response: Response };
    try {
      result = await call;
    } catch (cause) {
      throw new TransportError(cause);
    }
    if (result.error !== undefined || result.data === undefined) {
      throw toApiError(result.response.status, result.error);
    }
    return result.data;
  }

  // --- Ontdekken en authenticatie ---------------------------------------

  info(signal?: AbortSignal): Promise<Info> {
    return this.#unwrap(this.#raw.GET('/info', { signal }));
  }

  async setup(input: {
    setup_code: string;
    username: string;
    password: string;
  }): Promise<TokenPair> {
    const pair = await this.#unwrap(this.#raw.POST('/auth/setup', { body: input }));
    this.tokens.set(pair);
    return pair;
  }

  async login(input: { username: string; password: string }): Promise<TokenPair> {
    const pair = await this.#unwrap(this.#raw.POST('/auth/login', { body: input }));
    this.tokens.set(pair);
    return pair;
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
    if (!this.tokens.refreshToken) return Promise.resolve(false);
    return this.#refreshOnce();
  }

  /**
   * Meldt lokaal af. Het protocol kent geen uitlogendpoint (voorstel 5.2), dus
   * er valt hier niets te versturen: het refreshtoken wordt weggegooid en
   * vervalt vanzelf.
   */
  signOut(): void {
    this.tokens.clear();
  }

  server(signal?: AbortSignal): Promise<ServerDetail> {
    return this.#unwrap(this.#raw.GET('/server', { signal }));
  }

  // --- Catalogus --------------------------------------------------------

  async libraries(signal?: AbortSignal): Promise<Library[]> {
    const list = await this.#unwrap<LibraryList>(this.#raw.GET('/libraries', { signal }));
    return list.items;
  }

  libraryItems(
    libraryId: string,
    query: { limit?: number; cursor?: string; sort?: SortOption } = {},
    signal?: AbortSignal
  ): Promise<ItemPage> {
    return this.#unwrap(
      this.#raw.GET('/libraries/{library_id}/items', {
        params: { path: { library_id: libraryId }, query },
        signal
      })
    );
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
  async artworkBlob(artworkId: string, signal?: AbortSignal): Promise<Blob> {
    const url = `${this.baseUrl}/artwork/${encodeURIComponent(artworkId)}`;
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
