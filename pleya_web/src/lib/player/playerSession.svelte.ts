/**
 * Eén afspeelpoging, van capability-probe tot opruimen.
 *
 * De volgorde volgt de app (`getPlaybackInitialization` in
 * `lib/services/pleya_server_client/parts/playback.dart`): plan vragen met wat
 * dit toestel kan, de weg uit het plan nemen, en een omzetsessie levend houden
 * tot er gestopt wordt. Het verschil met de app zit in het credential: een
 * `<video src>` kan geen header zetten, dus direct play loopt over een
 * browser-streamsessie, en HLS over hls.js met de bearer in de header.
 *
 * Elke start krijgt een volgnummer. Een antwoord dat binnenkomt nadat de
 * speler al gesloten of opnieuw gestart is, wordt weggegooid, en een
 * omzetsessie die daarbij hoort meteen gestopt: anders blijft hij op de server
 * staan tot de time-out van een minuut.
 *
 * Bewust weggelaten, omdat het contract of deze slice het niet draagt:
 * - kijkstatus schrijven (`POST /watch-state`, S13.3);
 * - een startpositie in een omzetsessie: `PlaybackPlanRequest` kent geen
 *   positie en de server begint de omzetting bij nul, dus hervatten werkt
 *   alleen bij direct play;
 * - een ander audiospoor in een omzetsessie: het plan kent geen spoorkeuze en
 *   de omzetter neemt het eerste audiospoor.
 */
import type { Capabilities } from '../api/types';
import type { DeviceCapabilities } from './types';
import type { HlsSupport } from './capabilities';
import {
  absolute,
  chooseDelivery,
  DeliveryError,
  directUrlWithSession,
  urlWithStreamToken,
  type Delivery
} from './delivery';
import { attachHls, type HlsCtor, type HlsHandle } from './hlsEngine';
import type { PlaybackApi } from './playbackApi';
import {
  mediaErrorCode,
  playerProblem,
  playerProblemFromCode,
  type PlayerProblem
} from './playerErrors';
import { StreamSessionCache } from './streamSessionCache';
import { TranscodeHold, type Timers } from './transcodeHold';

export type PlayerPhase = 'idle' | 'loading' | 'ready' | 'error';

export interface PlayerDeps {
  api: PlaybackApi;
  /** De capabilities uit `GET /info`; null als die (nog) niet bekend zijn. */
  server: Capabilities | null;
  probe: () => { caps: DeviceCapabilities; hls: HlsSupport };
  loadHls: () => Promise<HlsCtor>;
  origin: string;
  timers?: Timers;
  /** Gedeeld per tabblad in de browser; zonder waarde een eigen cache. */
  streamSessions?: StreamSessionCache;
}

export interface PlayerTarget {
  itemId: string;
  versionId: string | null;
  /** Hervatpositie in seconden; alleen bij direct play. */
  startAt?: number;
}

export class PlayerSession {
  phase = $state<PlayerPhase>('idle');
  problem = $state<PlayerProblem | null>(null);
  delivery = $state<Delivery | null>(null);

  #deps: PlayerDeps;
  #hold: TranscodeHold;
  #hls: HlsHandle | null = null;
  #media: HTMLMediaElement | null = null;
  #run = 0;
  #streamSessions: StreamSessionCache;

  constructor(deps: PlayerDeps) {
    this.#deps = deps;
    this.#streamSessions = deps.streamSessions ?? new StreamSessionCache();
    this.#hold = new TranscodeHold(deps.api, () => this.#sessionLost(), deps.timers);
  }

  /** De id van de omzetsessie die nu levend gehouden wordt, of null. */
  get heldSession(): string | null {
    return this.#hold.sessionId;
  }

  async start(media: HTMLMediaElement, target: PlayerTarget): Promise<void> {
    const run = ++this.#run;
    this.#teardown(false);
    this.#media = media;
    this.phase = 'loading';
    this.problem = null;
    this.delivery = null;
    const { api, server } = this.#deps;
    const stale = () => run !== this.#run;

    try {
      const { caps, hls } = this.#deps.probe();
      let plan = null;
      if (server?.playback_plan) {
        plan = await api.plan({
          item_id: target.itemId,
          ...(target.versionId ? { version_id: target.versionId } : {}),
          capabilities: caps
        });
        // Een plan met een sessie wordt meteen vastgehouden, ook als de speler
        // al weg is: dan ruimt `release` hem hieronder direct op.
        if (plan.session_id) this.#hold.hold(plan.session_id);
        if (stale()) {
          if (plan.session_id) this.#hold.release(false);
          return;
        }
      }
      if (!plan && !target.versionId) throw new DeliveryError('client.no_version');

      const delivery = chooseDelivery(plan, target.versionId ?? '', hls);
      if (delivery.kind === 'hls') await this.#openHls(media, delivery, stale);
      else await this.#openDirect(media, delivery, target.startAt ?? 0, stale);
      if (stale()) return;

      this.delivery = delivery;
      this.phase = 'ready';
      media.play()?.catch(() => {
        // Autoplay geweigerd: de speler staat klaar en wacht op de knop.
      });
    } catch (err) {
      if (stale()) return;
      this.#fail(playerProblem(err));
    }
  }

  async #openDirect(
    media: HTMLMediaElement,
    delivery: Extract<Delivery, { kind: 'direct' }>,
    startAt: number,
    stale: () => boolean
  ): Promise<void> {
    const { api, server } = this.#deps;
    let src: string;
    if (server?.stream_sessions) {
      const id = await this.#streamSessions.get(delivery.versionId, () =>
        api.streamSession(delivery.versionId)
      );
      src = directUrlWithSession(delivery, id);
    } else {
      const token = await api.streamToken(delivery.versionId);
      src = urlWithStreamToken(delivery.path, token.stream_token);
    }
    if (stale()) return;
    if (startAt > 0) {
      media.addEventListener(
        'loadedmetadata',
        () => {
          if (Number.isFinite(media.duration) && startAt < media.duration) {
            media.currentTime = startAt;
          }
        },
        { once: true }
      );
    }
    media.src = src;
  }

  async #openHls(
    media: HTMLMediaElement,
    delivery: Extract<Delivery, { kind: 'hls' }>,
    stale: () => boolean
  ): Promise<void> {
    const { api, origin } = this.#deps;
    if (delivery.engine === 'native') {
      // Alleen een browser zonder MediaSource komt hier (iOS vóór 17.1). Die
      // kan geen header zetten; het contract staat voor zo'n speler het
      // streamtoken in de query toe, en de server hangt het aan elke
      // verwijzing in de afspeellijst. Het token leeft enkele minuten, dus een
      // lange omzetting kan hier halverwege stranden; zie de PR-tekst.
      const token = await api.streamToken(delivery.versionId);
      if (stale()) return;
      media.src = urlWithStreamToken(delivery.path, token.stream_token);
      return;
    }
    const Hls = await this.#deps.loadHls();
    if (stale()) return;
    this.#hls = attachHls({
      Hls,
      media,
      url: absolute(delivery.path, origin),
      bearer: () => api.bearer(),
      onFatal: (code) => {
        this.#hls = null;
        this.#fail(playerProblemFromCode(code));
      }
    });
  }

  /** Een fout van het `<video>`-element. Onder hls.js beslist hls.js zelf. */
  mediaFailed(error: { code: number } | null): void {
    if (this.phase !== 'ready' || this.#hls) return;
    const code = mediaErrorCode(error);
    if (!code) return;
    // Een geweigerde bron kan een verlopen streamsessie zijn: opnieuw proberen
    // vraagt dan een verse in plaats van dezelfde id nog eens.
    if (this.delivery?.kind === 'direct') this.#streamSessions.forget(this.delivery.versionId);
    this.#fail(playerProblemFromCode(code));
  }

  #sessionLost(): void {
    if (this.phase === 'error' || this.phase === 'idle') return;
    this.#fail(playerProblemFromCode('client.session_ended'));
  }

  #fail(problem: PlayerProblem): void {
    this.#teardown(false);
    this.problem = problem;
    this.phase = 'error';
  }

  #teardown(keepalive: boolean): void {
    this.#hls?.destroy();
    this.#hls = null;
    this.#hold.release(keepalive);
    const media = this.#media;
    if (media) {
      media.pause();
      // Ontkoppelen: zonder `load()` na het weghalen van `src` blijft de
      // browser de oude bron vasthouden en soms ook verder ophalen.
      media.removeAttribute('src');
      media.load();
    }
  }

  /**
   * Sluiten: bij unmount, routewissel of `pagehide`. Een lopende start wordt
   * ongeldig, hls.js gaat weg, de `<video>` laat los en de omzetsessie stopt.
   */
  dispose(keepalive = false): void {
    this.#run += 1;
    this.#teardown(keepalive);
    this.#media = null;
    this.phase = 'idle';
  }
}
