<!--
  Het paneel "Verder kijken" op het seriedetail: de aflevering waar de kijker
  mee bezig is, of anders de volgende. Welke dat is bepaalt de server (de hubs
  continue_watching en next_up); dit tekent hem alleen.

  "Klaar om" is nu plus wat er nog te kijken is, in de klok van de browser, en
  wordt bij het tekenen berekend.
-->
<script lang="ts">
  import Artwork from '../Artwork.svelte';
  import type { Item } from '../../api/types';
  import { t } from '../../i18n';
  import { formatPlayTime } from '../../player/keyboard';
  import { playerHref } from '../../player/route';
  import { session } from '../../stores/session.svelte';
  import { formatClock, formatDuration, itemProgress } from '../../util/format';

  let { episode, season }: { episode: Item; season?: Item } = $props();
  const uid = $props.id();

  const progress = $derived(itemProgress(episode));
  const resumeMs = $derived(progress ? episode.user_state?.position_ms ?? 0 : 0);
  const playable = $derived(session.capabilities?.playback_plan === true && (episode.versions?.length ?? 0) > 0);
  const label = $derived(
    [
      t(progress ? 'home.continueWatching' : 'series.nextEpisode'),
      season?.title ?? (typeof season?.index === 'number' ? t('item.season', { index: season.index }) : null),
      typeof episode.index === 'number' ? t('item.episode', { index: episode.index }) : null
    ].filter(Boolean).join(' · ')
  );
  const remainingMs = $derived(progress?.remainingMs ?? episode.duration_ms ?? 0);
  const timing = $derived.by(() => {
    if (remainingMs <= 0) return '';
    const duration = formatDuration(remainingMs);
    const clock = formatClock(new Date(Date.now() + remainingMs).toISOString());
    return [
      duration ? (progress ? t('card.remaining', { duration }) : duration) : null,
      clock ? t('series.endsAt', { time: clock }) : null
    ].filter(Boolean).join(' · ');
  });
</script>

<section class="next" aria-labelledby="{uid}-label">
  <div class="next__art">
    <Artwork artworkId={episode.artwork?.backdrop_id ?? episode.artwork?.poster_id} alt="" shape="wide" eager />
    {#if progress}
      <span class="next__prog" aria-hidden="true"><i style:width="{progress.fraction * 100}%"></i></span>
    {/if}
  </div>
  <div class="next__text">
    <div class="next__label" id="{uid}-label">{label}</div>
    <a class="next__title" href="/items/{encodeURIComponent(episode.id)}">{episode.title}</a>
    {#if episode.summary?.trim()}<p class="next__summary">{episode.summary}</p>{/if}
    <div class="next__acts">
      {#if playable && resumeMs > 0}
        <a class="btn" href={playerHref(episode.id, resumeMs)}>{t('player.resume', { time: formatPlayTime(resumeMs / 1000) })}</a>
        <a class="btn btn--quiet" href={playerHref(episode.id)}>{t('player.playFromStart')}</a>
      {:else if playable}
        <a class="btn" href={playerHref(episode.id)}>{t('player.play')}</a>
      {/if}
      {#if timing}<span class="next__timing">{timing}</span>{/if}
    </div>
  </div>
</section>

<style>
  .next {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 24px;
    padding: 20px;
    border-radius: var(--radius-panel);
    background: var(--panel);
  }
  .next__art {
    position: relative;
    flex: 1 1 300px;
    max-width: 360px;
    aspect-ratio: 16 / 9;
    border-radius: var(--radius-md);
    overflow: hidden;
  }
  .next__art :global(.artwork) { height: 100%; }
  .next__prog { position: absolute; left: 0; right: 0; bottom: 0; height: 4px; background: color-mix(in srgb, var(--art-shade) 50%, transparent); }
  .next__prog i { display: block; height: 100%; background: var(--accent); }
  .next__text { flex: 999 1 320px; min-width: 0; }
  .next__label { font-size: var(--text-caps-size); letter-spacing: var(--text-caps-track); text-transform: uppercase; color: var(--ink-2); }
  .next__title { display: block; margin: 6px 0; font-size: 24px; line-height: 1.2; font-weight: 700; color: var(--ink); overflow-wrap: anywhere; }
  .next__summary { margin: 0 0 16px; max-width: 620px; color: var(--ink-2); overflow-wrap: anywhere; }
  .next__acts { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
  .next__acts .btn:first-child { min-height: 48px; padding-inline: 26px; }
  .next__timing { font-size: 13px; color: var(--ink-2); }
  @media (max-width: 599px) {
    .next { padding: 14px; gap: 14px; }
    .next__art { max-width: none; }
    .next__title { font-size: 20px; }
  }
</style>
