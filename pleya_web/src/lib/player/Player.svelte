<!--
  De spelerschil uit mockup 50 (S13.2, S18.3): beeld over het hele venster,
  bovenaan terug met titel en regel, rechtsboven wat er speelt, in het midden
  tien seconden terug, afspelen en tien vooruit, onderaan de zoekbalk en de
  knoppen (PlayerControls).

  Het afspeelpad zelf zit in PlayerSession; deze component koppelt alleen de
  `<video>` aan de knoppen, het toetsenbord en de levenscyclus. Sluiten,
  navigeren en `pagehide` ruimen alle drie op: hls.js weg, de `<video>`
  ontkoppeld en de omzetsessie gestopt.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';

  import type { Item, Version } from '../api/types';
  import { t } from '../i18n';
  import { formatDuration } from '../util/format';
  import { clamp, keyAction, nextSpeed } from './keyboard';
  import PlayerControls from './PlayerControls.svelte';
  import PlayerIcon from './PlayerIcon.svelte';
  import PlayerTrackMenu from './PlayerTrackMenu.svelte';
  import { PlayerSession, type PlayerDeps } from './playerSession.svelte';
  import { audioOptions, cueText, defaultAudioIndex, subtitleBlobUrl, subtitleOptions } from './tracks';
  import { deliveryLabel } from './labels';
  // Globaal en niet gescoped, met `.player` als voorvoegsel: zo blijft deze
  // component onder de 400 regels.
  import './player.css';

  interface Props {
    item: Item;
    version: Version | undefined;
    startAt?: number;
    deps: PlayerDeps;
    onclose: () => void;
    onlogin: () => void;
  }

  let { item, version, startAt = 0, deps, onclose, onlogin }: Props = $props();

  // svelte-ignore state_referenced_locally
  const session = new PlayerSession(deps);
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
  let menuOpen = $state(false);
  let active = $state(true);
  let subtitleId = $state<string | null>(null);
  let subtitleUrl = $state<string | null>(null);
  let revokeSubtitle: (() => void) | null = null;
  let audioIndex = $state(0);
  let caption = $state('');
  let idleTimer: ReturnType<typeof setTimeout> | null = null;

  const total = $derived(
    version?.duration_ms ? version.duration_ms / 1000 : Number.isFinite(mediaDuration) ? mediaDuration : 0
  );
  const isHls = $derived(session.delivery?.kind === 'hls');
  const audio = $derived(audioOptions(version));
  const subs = $derived(subtitleOptions(version));
  const audioSwitchable = $derived(
    !isHls && (video as { audioTracks?: { length: number } } | null)?.audioTracks?.length === audio.length
  );
  const remaining = $derived(formatDuration(Math.max(0, total - current) * 1000));
  const meta = $derived(
    [item.year, formatDuration(total * 1000), remaining ? t('player.remaining', { duration: remaining }) : null]
      .filter(Boolean)
      .join(' · ')
  );
  const modeLabel = $derived(session.delivery ? deliveryLabel(session.delivery.mode, version) : null);
  const subtitleLabel = $derived(subs.usable.find((s) => s.id === subtitleId)?.label ?? null);
  const showChrome = $derived(active || paused || menuOpen || session.phase !== 'ready');

  function start(): void {
    if (!video) return;
    audioIndex = 0;
    void session.start(video, { itemId: item.id, versionId: version?.id ?? null, startAt });
  }

  $effect(() => {
    if (session.delivery) audioIndex = session.delivery.kind === 'hls' ? 0 : defaultAudioIndex(audio);
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

  function seekTo(seconds: number): void {
    if (!video || session.phase !== 'ready') return;
    const max = isHls ? seekLimit : total || video.duration;
    video.currentTime = clamp(seconds, 0, Number.isFinite(max) ? max : seconds);
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
      await root.requestFullscreen().catch(() => undefined);
    } else {
      // iOS Safari kent alleen volledig scherm op de video zelf.
      (video as { webkitEnterFullscreen?: () => void } | null)?.webkitEnterFullscreen?.();
    }
  }

  async function chooseSubtitle(id: string | null): Promise<void> {
    subtitleId = id;
    caption = '';
    revokeSubtitle?.();
    revokeSubtitle = null;
    subtitleUrl = null;
    if (!id) return;
    try {
      const loaded = await subtitleBlobUrl(() => deps.api.subtitleText(id));
      if (subtitleId !== id) return loaded.revoke();
      revokeSubtitle = loaded.revoke;
      subtitleUrl = loaded.url;
    } catch {
      subtitleId = null;
    }
  }

  /**
   * De ondertitel tekent deze speler zelf, boven de besturing. De browser zou
   * hem tegen de onderrand van het element zetten, en dat is hier het hele
   * venster: onder de knoppen. Het spoor staat daarom op `hidden` (de cues
   * lopen wel, ze worden alleen niet door de browser getekend).
   */
  function syncCues(event: Event): void {
    const track = (event.currentTarget as HTMLTrackElement).track;
    if (!track) return;
    if (track.mode !== 'hidden') track.mode = 'hidden';
    caption = cueText(track.activeCues as ArrayLike<VTTCue> | null);
  }

  function chooseAudio(index: number): void {
    const tracks = (video as { audioTracks?: ArrayLike<{ enabled: boolean }> } | null)?.audioTracks;
    if (!tracks) return;
    for (let i = 0; i < tracks.length; i++) tracks[i]!.enabled = i === index;
    audioIndex = index;
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
      if (menuOpen) {
        menuOpen = false;
        event.preventDefault();
      }
      return;
    }
    event.preventDefault();
    poke();
    if (action.kind === 'toggle') toggle();
    else if (action.kind === 'seekBy') seekTo((video?.currentTime ?? 0) + action.seconds);
    else if (action.kind === 'volumeBy') setVolume((video?.volume ?? 1) + action.delta);
    else if (action.kind === 'mute' && video) video.muted = !video.muted;
    else if (action.kind === 'fullscreen') void toggleFullscreen();
  }

  function syncTime(): void {
    if (!video) return;
    current = video.currentTime;
    mediaDuration = video.duration;
    const b = video.buffered;
    buffered = b.length ? b.end(b.length - 1) : 0;
    const s = video.seekable;
    seekLimit = s.length ? s.end(s.length - 1) : 0;
  }

  const onPageHide = () => session.dispose(true);
  const onPageShow = (e: PageTransitionEvent) => {
    if (e.persisted) start();
  };
  const onFullscreen = () => (fullscreen = document.fullscreenElement !== null);

  onMount(() => {
    window.addEventListener('pagehide', onPageHide);
    window.addEventListener('pageshow', onPageShow);
    document.addEventListener('fullscreenchange', onFullscreen);
    poke();
    start();
  });

  onDestroy(() => {
    window.removeEventListener('pagehide', onPageHide);
    window.removeEventListener('pageshow', onPageShow);
    document.removeEventListener('fullscreenchange', onFullscreen);
    if (idleTimer) clearTimeout(idleTimer);
    session.dispose(false);
    revokeSubtitle?.();
  });
</script>

<!-- Toetsen op het venster: ze werken ook als de focus nog nergens staat. -->
<svelte:window onkeydown={onKey} />

<section
  class="player"
  class:player--idle={!showChrome}
  aria-label={t('player.title')}
  bind:this={root}
  onpointermove={poke}
>
  <!-- svelte-ignore a11y_media_has_caption -->
  <video
    class="player__video"
    bind:this={video}
    playsinline
    onplay={() => (paused = false)}
    onpause={() => (paused = true)}
    ontimeupdate={syncTime}
    ondurationchange={syncTime}
    onprogress={syncTime}
    onvolumechange={() => {
      volume = video?.volume ?? 1;
      muted = video?.muted ?? false;
    }}
    onratechange={() => (rate = video?.playbackRate ?? 1)}
    onerror={() => session.mediaFailed(video?.error ?? null)}
    onclick={toggle}
  >
    {#if subtitleUrl}
      <track kind="subtitles" src={subtitleUrl} label={subtitleLabel ?? ''} default onload={syncCues} oncuechange={syncCues} />
    {/if}
  </video>

  {#if caption && subtitleUrl}
    <p class="caption" class:caption--low={!showChrome}>{caption}</p>
  {/if}

  <div class="scrim scrim--top" aria-hidden="true"></div>
  <div class="scrim scrim--bottom" aria-hidden="true"></div>

  <header class="top">
    <button class="round" type="button" aria-label={t('player.back')} onclick={onclose}>
      <PlayerIcon name="back" />
    </button>
    <div class="top__text">
      <h1 class="top__title">{item.title}</h1>
      {#if meta}<p class="top__meta">{meta}</p>{/if}
    </div>
    <div class="chips">
      {#if subtitleLabel}
        <span class="chip"><PlayerIcon name="cc" size={16} />{subtitleLabel}</span>
      {/if}
      {#if modeLabel}<span class="chip">{modeLabel}</span>{/if}
    </div>
  </header>

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
            <button class="btn" type="button" onclick={start}>{t('player.retry')}</button>
          {:else if session.problem.wayOut === 'login'}
            <button class="btn" type="button" onclick={onlogin}>{t('player.signIn')}</button>
          {/if}
          <button class="btn btn--ghost" type="button" onclick={onclose}>{t('player.toDetail')}</button>
        </div>
      </div>
    </div>
  {:else}
    <div class="center center--controls">
      <button class="round round--side" type="button" aria-label={t('player.rewind')} onclick={() => seekTo(current - 10)}>
        <PlayerIcon name="rewind" size={26} />
      </button>
      <button class="round round--main" type="button" aria-label={paused ? t('player.play') : t('player.pause')} onclick={toggle}>
        <PlayerIcon name={paused ? 'play' : 'pause'} size={30} />
      </button>
      <button class="round round--side" type="button" aria-label={t('player.forward')} onclick={() => seekTo(current + 10)}>
        <PlayerIcon name="forward" size={26} />
      </button>
    </div>
  {/if}

  <div class="bottom" hidden={session.phase === 'error'}>
    {#if menuOpen}
      <PlayerTrackMenu
        {audio}
        {audioIndex}
        {audioSwitchable}
        onaudio={chooseAudio}
        subtitles={subs.usable}
        {subtitleId}
        skippedSubtitles={subs.skipped}
        onsubtitle={(id) => void chooseSubtitle(id)}
        onclose={() => (menuOpen = false)}
      />
    {/if}
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
      subtitlesOn={subtitleId !== null}
      {menuOpen}
      ontoggle={toggle}
      onseek={seekTo}
      onvolume={setVolume}
      onmute={() => video && (video.muted = !video.muted)}
      onrate={() => video && (video.playbackRate = nextSpeed(rate))}
      onfullscreen={() => void toggleFullscreen()}
      onmenu={() => (menuOpen = !menuOpen)}
    />
  </div>
</section>

