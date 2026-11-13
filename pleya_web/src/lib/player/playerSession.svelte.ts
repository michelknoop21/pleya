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
 * Kijkstatus volgt de werkelijke media-events in Player via WatchProgress.
 * De audiokeuze gaat als `audio_stream_id` mee en een kwaliteitslimiet als `quality`.
 *
 * Startpositie (DEC-XXX, startpositie in het afspeelplan): met
 * `playback_start_position` vraagt een start op een later punt het plan vanaf
 * dat punt, en begint een omzetting daar in plaats van op nul. Het antwoord
 * meldt het eerste tijdstempel van de stream; de segmenten dragen filmtijd.
 * hls.js verschuift de stream naar nul, dus dat getal is `offset`, en de
 * positie in de film is overal `offset + currentTime`. Alleen onder hls.js: wat
 * de eigen HLS-speler van Safari met de tijden van zo'n stream doet is niet
 * gemeten, dus die houdt het oude gedrag.
 */
import type { Capabilities } from '../api/types';
import type { DeviceCapabilities, PlaybackQuality } from './types';
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

/** Zo lang wacht een volgend plan hooguit op de DELETE van de vorige omzetsessie. */
export const STOP_WAIT_MS = 3000;

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
  /** Of de laatste verversing opgaf zonder oordeel over het token. */
  refreshUnavailable?: () => boolean;
}

export interface PlayerTarget {
  itemId: string;
  versionId: string | null;
  /** Hervatpositie in seconden. */
  startAt?: number;
  /** Een expliciet gekozen audiospoor; alleen met `playback_audio_selection` en een versie. */
  audioStreamId?: string;
  /** Een kwaliteitslimiet uit het instellingenmenu; alleen met `playback_quality`. */
  quality?: PlaybackQuality;
}

/** Zoekt naar het hervatpunt zodra de bron bekend is; een groeiende omzetting heeft geen duur en wel `seekable`. */
function seekAfterMetadata(media: HTMLMediaElement, startAt: number): void {
  if (startAt <= 0) return;
  media.addEventListener(
    'loadedmetadata',
    () => {
      const seekable = media.seekable;
      const end = Number.isFinite(media.duration)
        ? media.duration
        : seekable?.length ? seekable.end(seekable.length - 1) : 0;
      if (startAt < end) media.currentTime = startAt;
    },
    { once: true }
  );
}

export class PlayerSession {
  phase = $state<PlayerPhase>('idle');
  problem = $state<PlayerProblem | null>(null);
  delivery = $state<Delivery | null>(null);
  /** Seconden in de film waar de huidige stream begint (hls.js telt vanaf daar 0); 0 zonder startpositie. */
  offset = $state(0);

  #deps: PlayerDeps;
  #hold: TranscodeHold;
  /** De DELETE's die nog onderweg zijn; een volgend plan wacht erop, want een sessie telt mee voor de limiet. */
  #stopping: Promise<void> | null = null;
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

  /** Of een omzetting op de gevraagde positie begint, en niet op nul. */
  get startsAtPosition(): boolean {
    return this.#deps.server?.playback_start_position === true && this.#deps.probe().hls.hlsjs;
  }

  async start(media: HTMLMediaElement, target: PlayerTarget): Promise<void> {
    const run = ++this.#run;
    this.#teardown(false);
    const stopping = this.#stopping;
    this.#media = media;
    this.phase = 'loading';
    this.problem = null;
    this.delivery = null;
    this.offset = 0;
    const { api, server } = this.#deps;
    const stale = () => run !== this.#run;

    try {
      const { caps, hls } = this.#deps.probe();
      const startAt = target.startAt ?? 0;
      const startMs = server?.playback_start_position === true && hls.hlsjs && startAt > 0 ? Math.round(startAt * 1000) : null;
      let plan = null;
      if (server?.playback_plan) {
        // De vorige omzetsessie is eerst weg: anders telt hij nog mee voor de limiet van de server.
        // Dat geldt ook na een fout ("Opnieuw") en na een plan dat tijdens het laden verouderde.
        if (stopping) {
          await stopping;
          if (stale()) return;
        }
        plan = await api.plan({
          item_id: target.itemId,
          ...(target.versionId ? { version_id: target.versionId } : {}),
          ...(target.versionId && target.audioStreamId ? { audio_stream_id: target.audioStreamId } : {}),
          ...(target.quality && server.playback_quality === true ? { quality: target.quality } : {}),
          ...(startMs !== null ? { start_position_ms: startMs } : {}),
          capabilities: caps
        });
        // Eerst verouderd, dan pas vasthouden: `hold` stopt de vorige sessie, en
        // na twee snelle keuzes is dat de sessie van de start die wel speelt.
        if (stale()) {
          if (plan.session_id) this.#track(api.stop(plan.session_id, false));
          return;
        }
        if (plan.session_id) this.#hold.hold(plan.session_id);
      }
      if (!plan && !target.versionId) throw new DeliveryError('client.no_version');

      const delivery = chooseDelivery(plan, target.versionId ?? '', hls);
      // Bij direct play meldt de server 0: de stream is het bestand en het element zoekt zelf.
      const offset = (plan?.start_position_ms ?? 0) / 1000;
      // De server begon al op (het keyframe vóór) de positie; de stream speelt dan vanaf zijn eigen nul.
      // hls.js begint op de gevraagde positie binnen de stream: anders speelt het stuk vanaf het keyframe opnieuw.
      const local = offset > 0 ? Math.max(0, startAt - offset) : startAt;
      if (delivery.kind === 'hls') await this.#openHls(media, delivery, local, stale);
      else await this.#openDirect(media, delivery, local, stale);
      if (stale()) return;

      this.offset = offset;
      this.delivery = delivery;
      this.phase = 'ready';
      media.play()?.catch(() => {
        // Autoplay geweigerd: de speler staat klaar en wacht op de knop.
      });
    } catch (err) {
      if (stale()) return;
      this.#fail(playerProblem(err, this.#deps.refreshUnavailable?.() === true));
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
    seekAfterMetadata(media, startAt);
    media.src = src;
  }

  async #openHls(
    media: HTMLMediaElement,
    delivery: Extract<Delivery, { kind: 'hls' }>,
    startAt: number,
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
      seekAfterMetadata(media, startAt);
      media.src = urlWithStreamToken(delivery.path, token.stream_token);
      return;
    }
    const Hls = await this.#deps.loadHls();
    if (stale()) return;
    this.#hls = attachHls({
      Hls,
      media,
      url: absolute(delivery.path, origin),
      startAt,
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
    void this.#teardown(false);
    this.problem = problem;
    this.phase = 'error';
  }

  #teardown(keepalive: boolean): Promise<void> {
    this.#hls?.destroy();
    this.#hls = null;
    const held = this.#hold.sessionId !== null;
    const stopped = this.#hold.release(keepalive);
    if (held) this.#track(stopped);
    const media = this.#media;
    if (media) {
      media.pause();
      // Ontkoppelen: zonder `load()` na het weghalen van `src` blijft de
      // browser de oude bron vasthouden en soms ook verder ophalen.
      media.removeAttribute('src');
      media.load();
    }
    return stopped;
  }

  #track(stop: Promise<void>): void {
    // Begrensd: een DELETE die nooit antwoordt mag een volgende start niet op
    // "laden" laten hangen. De server ruimt een sessie zonder hartslag zelf op.
    const bounded = Promise.race([stop.catch(() => undefined), new Promise<void>((r) => setTimeout(r, STOP_WAIT_MS))]);
    const all: Promise<void> = Promise.all([this.#stopping, bounded]).then(() => {
      if (this.#stopping === all) this.#stopping = null;
    });
    this.#stopping = all;
  }

  /**
   * Sluiten: bij unmount, routewissel of `pagehide`. Een lopende start wordt
   * ongeldig, hls.js gaat weg, de `<video>` laat los en de omzetsessie stopt.
   */
  dispose(keepalive = false): void {
    this.#run += 1;
    void this.#teardown(keepalive);
    this.#media = null;
    this.phase = 'idle';
  }
}
