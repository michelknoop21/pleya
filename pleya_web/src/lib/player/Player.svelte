<!--
  Filmbeeld volgens het doelbeeld Kijken-speler: terug en titel bovenaan, de
  tijdlijn en één rij knoppen onderaan, met het ondertitelmenu, het
  instellingenmenu en de afspeelinfo erboven. In de laatste dertig seconden
  komt de kaart "volgende aflevering", of het slotscherm als er niets volgt.

  Het afspeelpad zelf zit in PlayerSession; deze component koppelt alleen de
  `<video>` aan de knoppen, het toetsenbord en de levenscyclus. Sluiten,
  navigeren en `pagehide` ruimen alle drie op: hls.js weg, de `<video>`
  ontkoppeld en de omzetsessie gestopt.
-->
<script lang="ts">
  import { onDestroy, onMount, type Snippet } from 'svelte';

  import type { Item, Version } from '../api/types';
  import { t } from '../i18n';
  import { formatDuration } from '../util/format';
  import { clamp, keyAction } from './keyboard';
  import PlayerControls from './PlayerControls.svelte';
  import PlayerIcon from './PlayerIcon.svelte';
  import PlayerInfo from './PlayerInfo.svelte';
  import PlayerNextCard from './PlayerNextCard.svelte';
  import PlayerSettingsMenu, { type Aspect } from './PlayerSettingsMenu.svelte';
  import PlayerTrackMenu, { type SubtitleSize } from './PlayerTrackMenu.svelte';
  import { PlayerSession, type PlayerDeps } from './playerSession.svelte';
  import { PlayerSubtitles } from './playerSubtitles.svelte';
  import { audioOptions, defaultAudioIndex, subtitleOptions } from './tracks';
  import { deliveryLabel, playbackInfo, qualityOptions, type QualityOption } from './labels';
  import { nextCountdown } from './upNext';
  import { ResumeFloor, resumePoint, WatchProgress } from './watchProgress';
  // De gedeelde spelerregels zijn globaal met `.player` als voorvoegsel.
  import './player.css';

  interface Props {
    item: Item;
    version: Version | undefined;
    startAt?: number;
    /** Stream-id's uit `?audio=` en `?subtitle=`: de keuze van het filmdetail voor deze afspeelactie. */
    audioId?: string | null;
    subtitleId?: string | null;
    deps: PlayerDeps;
    onclose: () => void;
    onlogin: () => void;
    /** Het item is uitgespeeld; een afspeellijst gaat dan door. */
    onfinished?: () => void;
    /** Bij een aflevering: de serie als kop en "S2 · A3 · titel" eronder. */
    heading?: string | null;
    subheading?: string | null;
    /** De aflevering hierna; met `onnext` komt de knop en, in de laatste dertig seconden, de kaart. */
    next?: Item | null;
    /** Een belofte die afwijst (afgebroken navigatie) maakt een nieuwe poging mogelijk. */
    onnext?: () => void | Promise<unknown>;
    /** Het element dat volledig scherm krijgt; de route geeft er een dat een volgende aflevering overleeft. */
    fullscreenTarget?: HTMLElement | null;
    /** Het slotscherm, voor een titel waar niets op volgt. Zonder snippet blijft het beeld staan. */
    end?: Snippet<[{ replay: () => void }]>;
  }

  let {
    item, version, startAt = 0, audioId = null, subtitleId = null, deps, onclose, onlogin, onfinished,
    heading = null, subheading = null, next = null, onnext, fullscreenTarget = null, end
  }: Props = $props();

  // svelte-ignore state_referenced_locally
  const session = new PlayerSession(deps);
  // svelte-ignore state_referenced_locally
  const subtitles = new PlayerSubtitles(deps.api, () => version);
  let root = $state<HTMLElement | null>(null);
  let video = $state<HTMLVideoElement | null>(null);

  let paused = $state(true);
  let current = $state(0);
  let mediaDuration = $state(0);
  let buffered = $state(0);
  let seekLimit = $state(0);
  let volume = $state(1);
  let muted = $state(false);
  let rate = $state(1);
  let fullscreen = $state(false);
  let menu = $state<'subtitles' | 'settings' | null>(null);
  let active = $state(true);
  let audioIndex = $state(0);
  // svelte-ignore state_referenced_locally
  let audioPick = $state(audioId);
  let quality = $state<QualityOption | null>(null);
  let aspect = $state<Aspect>('contain');
  let subtitleSize = $state<SubtitleSize>('normal');
  let infoOpen = $state(false);
  let frames = $state<{ dropped: number; total: number } | null>(null);
  let ended = $state(false);
  let credits = $state(false);
  let advanced = false;
  /** Waar de laatste start begon: een keuze tijdens het laden en "Opnieuw" gaan daar verder. */
  let resumeAt = 0;
  let subtitlePicked = false;
  let nativeAudio = $state(0);
  const canPip = typeof document !== 'undefined' && document.pictureInPictureEnabled === true;
  let progress: WatchProgress | null = null;
  let lastPosition = 0;
  let resumeFloor = new ResumeFloor(0);
  let idleTimer: ReturnType<typeof setTimeout> | null = null;

  const total = $derived(
    version?.duration_ms ? version.duration_ms / 1000 : Number.isFinite(mediaDuration) ? mediaDuration : 0
  );
  const isHls = $derived(session.delivery?.kind === 'hls');
  const audio = $derived(audioOptions(version));
  const subs = $derived(subtitleOptions(version, deps.server?.embedded_subtitles === true));
  const wantedAudio = $derived(audio.findIndex((option) => option.id === audioPick));
  const planAudioSelection = $derived(deps.server?.playback_audio_selection === true && version !== undefined);
  const qualities = $derived(deps.server?.playback_quality === true ? qualityOptions(version) : []);
  // De sporenlijst van het element is niet reactief; `applyPicks` leest hem bij `loadedmetadata`.
  const audioSwitchable = $derived(!isHls && nativeAudio > 0 && nativeAudio === audio.length);
  const meta = $derived(subheading ?? [item.year, formatDuration(total * 1000)].filter(Boolean).join(' · '));
  const modeLabel = $derived(session.delivery ? deliveryLabel(session.delivery.mode, version) : null);
  const subtitleLabel = $derived(subs.usable.find((s) => s.id === subtitles.activeId)?.label ?? null);
  const subtitleNote = $derived(subtitles.preparing ? t('player.subtitlePreparing') : subtitles.error);
  const showChrome = $derived(active || paused || menu !== null || session.phase !== 'ready');
  const countdown = $derived(session.phase === 'ready' ? nextCountdown(current, total) : null);
  const hasNext = $derived(next !== null && onnext !== undefined);
  const showNext = $derived(hasNext && countdown !== null && !credits && !ended);
  const showEnd = $derived(end !== undefined && !hasNext && (ended || (countdown !== null && !credits)));
  const info = $derived(playbackInfo({
    mode: session.delivery?.mode, version, audio: audio[audioIndex]?.label, subtitle: subtitleLabel,
    ahead: buffered - current, frames
  }));

  /** Start, of herstart met een andere kwaliteit of een ander audiospoor vanaf `from` seconden. */
  function start(from: number = resumeAt): void {
    if (!video) return;
    resumeAt = from;
    nativeAudio = 0;
    subtitles.abort();
    progress?.finish(false);
    progress = null;
    lastPosition = 0;
    resumeFloor = new ResumeFloor(from);
    audioIndex = 0;
    void session.start(video, {
      itemId: item.id, versionId: version?.id ?? null, startAt: from,
      ...(plannedAudio() && audioPick ? { audioStreamId: audioPick } : {}),
      ...(quality?.quality ? { quality: quality.quality } : {})
    });
  }

  // Alleen een afwijkend spoor gaat naar de planner: een expliciete audiokeuze valt nooit terug op direct play.
  const plannedAudio = () => deps.server?.playback_audio_selection === true && wantedAudio >= 0 && wantedAudio !== defaultAudioIndex(audio);

  $effect(() => {
    if (!session.delivery) return;
    // Een gepland spoor is het spoor dat speelt, ook als de omzetting er maar één draagt. Zonder plan
    // geldt de wens pas als het element hem uitvoert (`applyPicks`): anders toont het menu een spoor dat niet speelt.
    audioIndex = plannedAudio() ? wantedAudio : session.delivery.kind === 'hls' ? 0 : defaultAudioIndex(audio);
  });

  // De keuze van het filmdetail, toegepast zodra de sporen van het element bekend zijn.
  function applyPicks(): void {
    // Rechtstreeks gelezen: de sporenlijst van het element is niet reactief.
    nativeAudio = (video as { audioTracks?: { length: number } } | null)?.audioTracks?.length ?? 0;
    if (wantedAudio >= 0 && audioSwitchable) chooseAudio(wantedAudio);
    // Eén keer: na een planwissel komt `loadedmetadata` opnieuw, en een ondertitel die de kijker uitzette blijft uit.
    if (subtitlePicked || !subtitleId || !subs.usable.some((option) => option.id === subtitleId)) return;
    subtitlePicked = true;
    void subtitles.choose(subtitleId);
  }

  // Positie in de film: een stream met een startpositie begint op `session.offset` en niet op nul.
  const filmTime = () => session.offset + (video?.currentTime ?? 0);

  // Teardown empties the element, so a report after an error reads the last position that played.
  function samplePosition(): number {
    if (video && session.phase === 'ready') lastPosition = resumeFloor.position(filmTime());
    return lastPosition;
  }

  // On `playing`, not `play`: `play` fires before a resume seek lands and would report position 0.
  function playing(): void {
    if (!video || session.phase !== 'ready') return;
    progress ??= new WatchProgress({
      report: (body, keepalive) => deps.api.reportWatchState(body, keepalive),
      enabled: deps.server?.watch_state === true,
      ownership: deps.server?.watch_state_ownership === true,
      itemId: item.id, revision: item.user_state?.revision,
      sample: () => ({ position: samplePosition(), duration: total }),
      ...(deps.timers ? { timers: deps.timers } : {})
    });
    progress.play();
  }

  // De film speelt door; zonder dit gaat een mislukte voorbereiding achter verborgen knoppen schuil.
  $effect(() => {
    if (subtitles.error) poke();
  });

  // De ondertitel staat in filmtijd; het element telt vanaf het begin van de stream.
  $effect(() => subtitles.setOffset(session.offset));

  $effect(() => {
    if (session.phase === 'error') {
      progress?.finish(false);
      progress = null;
    }
  });

  function poke(): void {
    active = true;
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = setTimeout(() => (active = false), 3000);
  }

  function toggle(): void {
    if (!video || session.phase !== 'ready') return;
    if (video.paused) void video.play().catch(() => undefined);
    else video.pause();
  }

  /** Zoeken in filmtijd. Vóór het begin van deze stream ligt niets: dat wordt een nieuw plan vanaf dat punt. */
  function seekTo(seconds: number): void {
    if (!video || session.phase !== 'ready') return;
    if (seconds < session.offset) return start(Math.max(0, seconds));
    const max = isHls ? seekLimit : total || session.offset + video.duration;
    resumeFloor.release();
    video.currentTime = Math.max(0, clamp(seconds, 0, Number.isFinite(max) ? max : seconds) - session.offset);
  }

  function setVolume(next: number): void {
    if (!video) return;
    video.volume = clamp(next, 0, 1);
    video.muted = video.volume === 0;
  }

  async function toggleFullscreen(): Promise<void> {
    if (document.fullscreenElement) {
      await document.exitFullscreen().catch(() => undefined);
    } else if (root?.requestFullscreen) {
      await (fullscreenTarget ?? root).requestFullscreen().catch(() => undefined);
    } else {
      // iOS Safari kent alleen volledig scherm op de video zelf.
      (video as { webkitEnterFullscreen?: () => void } | null)?.webkitEnterFullscreen?.();
    }
  }

  function chooseAudio(index: number): void {
    const tracks = (video as { audioTracks?: ArrayLike<{ enabled: boolean }> } | null)?.audioTracks;
    if (!tracks) return;
    for (let i = 0; i < tracks.length; i++) tracks[i]!.enabled = i === index;
    audioIndex = index;
  }

  // Tijdens het laden staat het element leeg; dan geldt waar de lopende start begon.
  const here = () => (session.phase === 'ready' ? current : resumeAt);

  // Het menu: wisselen in de browser als het element de sporen draagt, anders een nieuw plan. Direct play
  // hervat op de positie, en een omzetting ook als de server een startpositie kent; zonder begint hij
  // bij het begin, en het menu zegt dat erbij.
  function pickAudio(index: number): void {
    if (audioSwitchable) return chooseAudio(index);
    if (!planAudioSelection || index === audioIndex) return;
    audioPick = audio[index]?.id ?? null;
    start(here());
  }

  function pickQuality(option: QualityOption): void {
    if (option.id === (quality?.id ?? 'original')) return;
    quality = option;
    start(here());
  }

  async function togglePip(): Promise<void> {
    if (document.pictureInPictureElement) await document.exitPictureInPicture().catch(() => undefined);
    else await video?.requestPictureInPicture().catch(() => undefined);
  }

  function advance(): void {
    if (advanced || !onnext) return;
    advanced = true;
    void Promise.resolve(onnext()).catch(() => { advanced = false; });
  }

  // De kaart telt af op de afspeelpositie; op nul start de volgende aflevering vanzelf.
  $effect(() => {
    if (showNext && countdown === 0 && menu === null) advance();
  });

  // Terugspoelen uit het eindvenster: de volgende keer komt de kaart of het slotscherm weer.
  $effect(() => {
    if (countdown === null) credits = false;
  });

  function finished(): void {
    paused = true;
    ended = true;
    progress?.finish(false);
    progress = null;
    if (hasNext) advance();
    else onfinished?.();
  }

  function replay(): void {
    credits = true;
    seekTo(0);
    void video?.play().catch(() => undefined);
  }

  function onKey(event: KeyboardEvent): void {
    const target = event.target as HTMLElement | null;
    const action = keyAction({
      key: event.key,
      ctrlKey: event.ctrlKey,
      metaKey: event.metaKey,
      altKey: event.altKey,
      targetTag: target?.tagName,
      targetType: (target as HTMLInputElement | null)?.type
    });
    if (!action) return;
    if (action.kind === 'escape') {
      if (menu !== null) {
        menu = null;
        event.preventDefault();
      }
      return;
    }
    // In een open menu zijn de pijlen van het menu.
    // Alleen het instellingenmenu heeft pijlnavigatie; in het ondertitelmenu blijven pijlen spoelen en volume regelen.
    if (menu === 'settings' && (action.kind === 'seekBy' || action.kind === 'volumeBy')) return;
    event.preventDefault();
    poke();
    if (action.kind === 'toggle') toggle();
    else if (action.kind === 'seekBy') seekTo(filmTime() + action.seconds);
    else if (action.kind === 'volumeBy') setVolume((video?.volume ?? 1) + action.delta);
    else if (action.kind === 'mute' && video) video.muted = !video.muted;
    else if (action.kind === 'fullscreen') void toggleFullscreen();
  }

  function syncTime(): void {
    if (!video) return;
    samplePosition();
    const offset = session.offset;
    current = filmTime();
    mediaDuration = offset + video.duration;
    const b = video.buffered;
    buffered = b.length ? offset + b.end(b.length - 1) : 0;
    const s = video.seekable;
    seekLimit = s.length ? offset + s.end(s.length - 1) : 0;
    const q = infoOpen ? video.getVideoPlaybackQuality?.() : null;
    frames = q ? { dropped: q.droppedVideoFrames, total: q.totalVideoFrames } : null;
  }

  const onPageHide = () => { subtitles.abort(); progress?.finish(true); progress = null; session.dispose(true); };
  const onPageShow = (e: PageTransitionEvent) => {
    if (e.persisted) start();
  };
  const onFullscreen = () => (fullscreen = !!document.fullscreenElement);

  onMount(() => {
    window.addEventListener('pagehide', onPageHide);
    window.addEventListener('pageshow', onPageShow);
    document.addEventListener('fullscreenchange', onFullscreen);
    poke();
    onFullscreen();
    // Alleen de eerste start: het hervatpunt hoort bij de titel en kan voorbij het eind van deze versie liggen.
    // The contract's duration, not the element's: a growing transcode has no end of its own yet.
    start(resumePoint(startAt, (version?.duration_ms ?? 0) / 1000));
  });

  onDestroy(() => {
    window.removeEventListener('pagehide', onPageHide);
    window.removeEventListener('pageshow', onPageShow);
    document.removeEventListener('fullscreenchange', onFullscreen);
    if (idleTimer) clearTimeout(idleTimer);
    progress?.finish(false);
    progress = null;
    session.dispose(false);
    subtitles.dispose();
  });
</script>

<!-- Toetsen op het venster: ze werken ook als de focus nog nergens staat. -->
<svelte:window onkeydown={onKey} />

<section
  class="player"
  class:player--idle={!showChrome}
  class:player--end={showEnd}
  aria-label={t('player.title')}
  bind:this={root}
  onpointermove={poke}
>
  <!-- svelte-ignore a11y_media_has_caption -->
  <video
    class="player__video"
    class:player__video--cover={aspect === 'cover' && !showEnd}
    bind:this={video}
    playsinline
    onplay={() => { paused = false; ended = false; }}
    onplaying={playing}
    onpause={() => { paused = true; progress?.report(); }}
    onseeked={() => progress?.report()}
    onended={finished}
    ontimeupdate={syncTime}
    ondurationchange={syncTime}
    onloadedmetadata={applyPicks}
    onprogress={syncTime}
    onvolumechange={() => {
      volume = video?.volume ?? 1;
      muted = video?.muted ?? false;
    }}
    onratechange={() => (rate = video?.playbackRate ?? 1)}
    onerror={() => session.mediaFailed(video?.error ?? null)}
    onclick={toggle}
  >
    {#if subtitles.url}
      <track kind="subtitles" src={subtitles.url} label={subtitleLabel ?? ''} default onload={subtitles.syncCues} oncuechange={subtitles.syncCues} />
    {/if}
  </video>

  <div class="scrim scrim--top" aria-hidden="true"></div>

  <header class="top">
    <button class="round" type="button" aria-label={t('player.back')} onclick={onclose}>
      <PlayerIcon name="back" />
    </button>
    <div class="film__text">
      <h1 class="film__title">{heading ?? item.title}</h1>
      {#if meta}<p class="film__meta">{meta}</p>{/if}
    </div>
    {#if modeLabel && session.phase === 'ready'}<div class="chips"><span class="chip">{modeLabel}</span></div>{/if}
  </header>

  {#if infoOpen && session.phase === 'ready' && !showEnd}<PlayerInfo rows={info} />{/if}

  {#if session.phase === 'loading' || session.phase === 'idle'}
    <div class="center" role="status" aria-live="polite">
      <span class="spinner" aria-hidden="true"></span>
      <p class="center__text">{t('player.loading')}</p>
    </div>
  {:else if session.phase === 'error' && session.problem}
    <div class="center">
      <div class="problem" role="alert">
        <p class="problem__text">{session.problem.message}</p>
        <div class="problem__actions">
          {#if session.problem.wayOut === 'retry'}
            <!-- Verder waar het speelde; zonder gespeeld stuk waar de laatste start begon. -->
            <button class="btn" type="button" onclick={() => start(lastPosition || resumeAt)}>{t('player.retry')}</button>
          {:else if session.problem.wayOut === 'login'}
            <button class="btn" type="button" onclick={onlogin}>{t('player.signIn')}</button>
          {/if}
          <button class="btn btn--ghost" type="button" onclick={onclose}>{t('player.toDetail')}</button>
        </div>
      </div>
    </div>
  {/if}

  <div class="bottom" hidden={session.phase === 'error'}>
    <div class="bottom__menu">
      {#if menu === 'subtitles'}
        <PlayerTrackMenu
          subtitles={subs.usable}
          subtitleId={subtitles.pendingId ?? subtitles.activeId}
          error={subtitles.error}
          loading={subtitles.pendingId !== null}
          preparing={subtitles.preparing}
          skippedSubtitles={subs.skipped}
          size={subtitleSize}
          onsize={(size) => (subtitleSize = size)}
          onsubtitle={(id) => void subtitles.choose(id)}
          onsubtitleretry={subtitles.failedId ? () => subtitles.retry() : null}
          onclose={() => (menu = null)}
        />
      {:else if menu === 'settings'}
        <PlayerSettingsMenu
          quality={qualities}
          qualityId={quality?.id ?? 'original'}
          onquality={pickQuality}
          {audio}
          {audioIndex}
          audioSwitchable={audioSwitchable || planAudioSelection}
          audioReplans={!audioSwitchable && planAudioSelection}
          replanFromStart={!session.startsAtPosition}
          onaudio={pickAudio}
          {rate}
          onrate={(next) => video && (video.defaultPlaybackRate = video.playbackRate = next)}
          {aspect}
          onaspect={(next) => (aspect = next)}
          info={infoOpen}
          oninfo={() => { infoOpen = !infoOpen; syncTime(); }}
        />
      {:else if showNext && next && countdown !== null}
        <PlayerNextCard {next} seconds={countdown} onplay={advance} oncredits={() => (credits = true)} />
      {/if}
    </div>
    <div class="bottom__controls">
      <PlayerControls
        {paused}
        {current}
        {total}
        {buffered}
        limit={isHls ? seekLimit : null}
        {volume}
        {muted}
        {rate}
        {fullscreen}
        ready={session.phase === 'ready'}
        {subtitleLabel}
        subtitlePreparing={subtitles.preparing}
        {subtitleNote}
        {menu}
        ontoggle={toggle}
        onseek={seekTo}
        onvolume={setVolume}
        onmute={() => video && (video.muted = !video.muted)}
        onfullscreen={() => void toggleFullscreen()}
        onsubtitles={() => (menu = menu === 'subtitles' ? null : 'subtitles')}
        onsettings={() => (menu = menu === 'settings' ? null : 'settings')}
        onnext={hasNext ? advance : null}
        onpip={canPip ? () => void togglePip() : null}
      />
    </div>
    {#if subtitles.caption && subtitles.url}
      <p class="caption" class:caption--low={!showChrome} class:caption--small={subtitleSize === 'small'} class:caption--large={subtitleSize === 'large'}>{subtitles.caption}</p>
    {/if}
  </div>
  {#if subtitleNote && menu !== 'subtitles' && showChrome}
    <div class="player-toast" class:player-toast--wait={subtitles.preparing} role="status">
      <span class="player-toast__icon"><PlayerIcon name="cc" size={17} /></span>
      <span>{subtitleNote}</span>
      {#if subtitles.failedId}
        <button type="button" onclick={() => subtitles.retry()}>{t('player.subtitleRetry')}</button>
      {/if}
    </div>
  {/if}
  {#if showEnd && end}
    <div class="end">
      <button class="round" type="button" aria-label={t('player.back')} onclick={onclose}>
        <PlayerIcon name="back" />
      </button>
      {#if !ended}
        <button class="end__tile" type="button" aria-label={t('player.creditsFull')} onclick={() => (credits = true)}></button>
      {/if}
      {@render end({ replay })}
    </div>
  {/if}
</section>

