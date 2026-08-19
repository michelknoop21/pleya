/**
 * De toestand van de verbinding met deze server.
 *
 * Eén bron voor drie dingen die elk scherm nodig heeft: is er ingelogd, wat
 * kan deze server (capabilities is leidend, niet feature_level), en welke
 * bibliotheken zijn er. De schil leest hier uit welke navigatie-items er
 * mogen bestaan; een item zonder capability wordt niet getekend, ook niet
 * uitgegrijsd.
 */
import { PleyaClient } from '../api/client';
import type { Capabilities, Info, Library, ServerDetail } from '../api/types';
import { describeError } from '../api/errors';

export type SessionPhase = 'starting' | 'setup' | 'signed-out' | 'ready' | 'unreachable';

class SessionState {
  phase = $state<SessionPhase>('starting');
  info = $state<Info | null>(null);
  server = $state<ServerDetail | null>(null);
  libraries = $state<Library[]>([]);
  error = $state<string | null>(null);

  readonly client: PleyaClient;

  constructor(client?: PleyaClient) {
    this.client =
      client ??
      new PleyaClient({
        onSessionLost: () => {
          this.server = null;
          this.libraries = [];
          // Een server zonder eigenaar blijft een server zonder eigenaar. Een
          // 401 zegt daar niets over, en hem hier als "uitgelogd" boeken zou
          // een inlogscherm opleveren waar niemand op kan inloggen.
          this.phase = this.info?.auth.setup_required ? 'setup' : 'signed-out';
        }
      });
  }

  get capabilities(): Capabilities | null {
    return this.info?.capabilities ?? null;
  }

  /**
   * Bepaalt waar de gebruiker terechtkomt: setup, inloggen of de app.
   *
   * `GET /info` is klasse public en is dus altijd de eerste vraag. Zolang
   * `auth.setup_required` waar is, bestaat er nog geen eigenaar en heeft
   * inloggen geen betekenis.
   */
  async start(): Promise<void> {
    this.phase = 'starting';
    this.error = null;
    try {
      this.info = await this.client.info();
    } catch (err) {
      this.error = describeError(err);
      this.phase = 'unreachable';
      return;
    }

    if (this.info.auth.setup_required) {
      this.phase = 'setup';
      return;
    }

    const restored = await this.client.restore();
    if (!restored) {
      this.phase = 'signed-out';
      return;
    }
    await this.load();
  }

  /** Haalt op wat achter authenticatie zit. Aanroepen na setup of login. */
  async load(): Promise<void> {
    try {
      const [server, libraries] = await Promise.all([
        this.client.server(),
        this.client.libraries()
      ]);
      this.server = server;
      this.libraries = libraries;
      this.phase = 'ready';
      this.error = null;
    } catch (err) {
      this.error = describeError(err);
      this.phase = 'signed-out';
    }
  }

  /** Na een geslaagde setup of login: info opnieuw lezen en doorlopen. */
  async afterAuth(): Promise<void> {
    try {
      this.info = await this.client.info();
    } catch {
      // Info is niet kritiek voor de volgende stap; capabilities blijven staan.
    }
    await this.load();
  }

  signOut(): void {
    this.client.signOut();
    this.server = null;
    this.libraries = [];
    this.phase = this.info?.auth.setup_required ? 'setup' : 'signed-out';
  }

  library(id: string): Library | undefined {
    return this.libraries.find((l) => l.id === id);
  }
}

export const session = new SessionState();
export { SessionState };
