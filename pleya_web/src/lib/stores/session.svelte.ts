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
import type { Capabilities, Info, Library, ServerDetail, User } from '../api/types';
import { describeError } from '../api/errors';
import { readLastContact, writeLastContact, type LastContact } from './lastContact';

export type SessionPhase = 'starting' | 'setup' | 'signed-out' | 'ready' | 'unreachable';

class SessionState {
  phase = $state<SessionPhase>('starting');
  info = $state<Info | null>(null);
  server = $state<ServerDetail | null>(null);
  libraries = $state<Library[]>([]);
  /** De ingelogde gebruiker met zijn rol, uit `GET /users/me`; null als de server dat niet kent. */
  me = $state<User | null>(null);
  error = $state<string | null>(null);
  /** Wat er de laatste keer van de server bekend was; alleen gelezen bij onbereikbaar. */
  lastContact = $state<LastContact | null>(null);

  readonly client: PleyaClient;

  #started: Promise<void> | null = null;

  constructor(client?: PleyaClient) {
    this.client =
      client ??
      new PleyaClient({
        onSessionLost: () => {
          this.server = null;
          this.libraries = [];
          this.me = null;
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
   * Of deze gebruiker het beheeroppervlak krijgt: eigenaar of beheerder, op een
   * server die een beheeroppervlak heeft. Dit is netheid en geen beveiliging;
   * de server weigert een lid met 404, wat de client ook vraagt. De
   * beheerlaag vraagt daarom niets zolang dit onwaar is (S10.7).
   */
  get canAdminister(): boolean {
    const role = this.me?.role;
    return (
      this.phase === 'ready' &&
      this.capabilities?.administration === true &&
      (role === 'owner' || role === 'admin')
    );
  }

  /**
   * Start de sessie hoogstens één keer en geeft die ene poging terug.
   *
   * De schil start bij het mounten, maar de load van `/admin` draait vóór dat
   * mounten en moet de rol al weten. Twee losse starts zouden twee
   * refreshaanvragen kunnen geven, en het refreshtoken roteert bij elk gebruik.
   */
  ensureStarted(): Promise<void> {
    this.#started ??= this.start();
    return this.#started;
  }

  /**
   * Bepaalt waar de gebruiker terechtkomt: setup, inloggen of de app.
   *
   * `GET /info` is klasse public en is dus altijd de eerste vraag. Zolang
   * `auth.setup_required` waar is, bestaat er nog geen eigenaar en heeft
   * inloggen geen betekenis.
   */
  async start(): Promise<void> {
    // Een nieuwe poging vanuit onbereikbaar blijft in die fase tot er een
    // antwoord is. Via `starting` zou de schil met de staat erin even
    // verdwijnen voor het compacte skelet en dan terugkomen: een sprong per
    // poging, elke 30 s opnieuw.
    if (this.phase !== 'unreachable') this.phase = 'starting';
    this.error = null;
    try {
      this.info = await this.client.info();
    } catch (err) {
      this.error = describeError(err);
      this.lastContact = readLastContact();
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
      const [server, libraries, me] = await Promise.all([
        this.client.server(),
        this.client.libraries(),
        // Een oudere server kent /users/me niet (404). Dan is de rol onbekend en
        // blijft het beheeroppervlak dicht; de rest van de app werkt gewoon.
        this.info?.capabilities.users === true
          ? this.client.me().catch(() => null)
          : Promise.resolve(null)
      ]);
      this.server = server;
      this.libraries = libraries;
      this.me = me;
      this.phase = 'ready';
      this.error = null;
      writeLastContact({
        name: server.name,
        at: new Date().toISOString(),
        browse: this.info?.capabilities.browse === true,
        libraries: libraries.map((l) => ({ id: l.id, kind: l.kind }))
      });
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

  /**
   * Afmelden. Op een server met `capabilities.sessions` trekt dat ook de sessie
   * in; `local` slaat dat over voor het geval waarin de server alle sessies al
   * heeft ingetrokken (een geroteerde ondertekensleutel).
   */
  async signOut(options: { local?: boolean } = {}): Promise<void> {
    await this.client.signOut({ remote: !options.local && this.capabilities?.sessions === true });
    this.server = null;
    this.libraries = [];
    this.me = null;
    this.phase = this.info?.auth.setup_required ? 'setup' : 'signed-out';
  }

  library(id: string): Library | undefined {
    return this.libraries.find((l) => l.id === id);
  }
}

export const session = new SessionState();
export { SessionState };
