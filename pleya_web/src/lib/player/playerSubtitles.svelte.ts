/**
 * De gekozen ondertitel van één speler: ophalen, wachten op een ingebed spoor
 * dat de server nog voorbereidt, en de `blob:`-URL opruimen. Een nieuwe keuze
 * vervangt de vorige pas na succes; een fout laat het vorige spoor staan.
 */
import { t } from '../i18n';
import type { Version } from '../api/types';
import type { PlaybackApi } from './playbackApi';
import { SUBTITLE_FAILURE_MEMORY_MS, pause, subtitleTextWhenReady } from './subtitleRetry';
import { cueText, subtitleBlobUrl } from './tracks';

export class PlayerSubtitles {
  activeId = $state<string | null>(null);
  pendingId = $state<string | null>(null);
  /** Een ingebed spoor in voorbereiding; de film speelt intussen door. */
  preparing = $state(false);
  error = $state<string | null>(null);
  failedId = $state<string | null>(null);
  url = $state<string | null>(null);
  caption = $state('');

  #controller: AbortController | null = null;
  /** Seconden in de film waar de stream begint; de cues schuiven zoveel terug. */
  #offset = 0;
  /** Hoeveel de cues van een spoor al verschoven zijn. */
  #shifted = new WeakMap<TextTrack, number>();
  #track: TextTrack | null = null;
  #revoke: (() => void) | null = null;
  /** Vóór dit moment geeft de server voor `failedId` zijn bewaarde fout terug. */
  #retryAt = 0;

  constructor(
    private readonly api: Pick<PlaybackApi, 'subtitleText'>,
    private readonly version: () => Version | undefined
  ) {}

  async choose(id: string | null): Promise<void> {
    const wait = id !== null && id === this.failedId ? this.#retryAt - Date.now() : 0;
    this.abort();
    this.#controller = null;
    this.pendingId = null;
    this.preparing = false;
    this.error = null;
    this.failedId = null;
    if (!id) {
      this.activeId = null;
      this.caption = '';
      this.#revoke?.();
      this.#revoke = null;
      this.url = null;
      return;
    }
    const controller = new AbortController();
    const stream = this.version()?.subtitle_streams?.find((s) => s.id === id);
    const embedded = stream?.is_external === false;
    this.#controller = controller;
    this.pendingId = id;
    this.preparing = embedded;
    try {
      if (wait > 0) await pause(wait, controller.signal);
      const loaded = await subtitleBlobUrl(
        () => subtitleTextWhenReady((signal) => this.api.subtitleText(id, signal), controller.signal),
        stream?.format ?? 'vtt'
      );
      if (controller.signal.aborted) return loaded.revoke();
      this.#revoke?.();
      this.caption = '';
      this.activeId = id;
      this.#revoke = loaded.revoke;
      this.url = loaded.url;
    } catch {
      if (!controller.signal.aborted) {
        this.error = t(embedded ? 'player.subtitlePrepareFailed' : 'player.subtitleLoadFailed');
        this.failedId = id;
        this.#retryAt = embedded ? Date.now() + SUBTITLE_FAILURE_MEMORY_MS : 0;
      }
    } finally {
      if (this.#controller === controller) {
        this.#controller = null;
        this.pendingId = null;
        this.preparing = false;
      }
    }
  }

  retry(): void {
    if (this.failedId) void this.choose(this.failedId);
  }

  /**
   * De ondertitel tekent de speler zelf, boven de besturing. De browser zou hem
   * tegen de onderrand van het element zetten, en dat is hier het hele venster:
   * onder de knoppen. Het spoor staat daarom op `hidden` (de cues lopen wel, ze
   * worden alleen niet door de browser getekend).
   */
  syncCues = (event: Event): void => {
    const track = (event.currentTarget as HTMLTrackElement).track;
    if (!track) return;
    if (track.mode !== 'hidden') track.mode = 'hidden';
    this.#track = track;
    // Na `load` zijn de cues net uit het bestand gelezen en nog niet verschoven.
    if (event.type === 'load') this.#shifted.delete(track);
    this.#align(track);
    this.caption = cueText(track.activeCues as ArrayLike<VTTCue> | null);
  };

  /**
   * Een stream met een startpositie telt vanaf zijn eigen nul, de cues vanaf het
   * begin van de film. Ze schuiven met de offset mee, ook bij een nieuw plan op
   * een ander punt met hetzelfde spoor.
   */
  setOffset(offset: number): void {
    this.#offset = offset;
    if (this.#track) this.#align(this.#track);
  }

  #align(track: TextTrack): void {
    const delta = this.#offset - (this.#shifted.get(track) ?? 0);
    if (delta === 0 || !track.cues?.length) return;
    for (let i = 0; i < track.cues.length; i++) {
      const cue = track.cues[i]!;
      cue.startTime -= delta;
      cue.endTime -= delta;
    }
    this.#shifted.set(track, this.#offset);
  }

  abort(): void {
    this.#controller?.abort();
  }

  dispose(): void {
    this.abort();
    this.#revoke?.();
  }
}
