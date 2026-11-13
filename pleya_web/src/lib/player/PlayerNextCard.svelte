<!--
  De kaart "volgende aflevering" uit het doelbeeld Kijken-speler-einde. Hij
  staat er in de laatste dertig seconden; de knop telt af en de aflevering
  start dan vanzelf. "Aftiteling kijken" haalt de kaart weg en laat het beeld
  doorlopen. De tekening uit het doelbeeld ontbreekt: die asset staat niet in
  pleya_web.
-->
<script lang="ts">
  import type { Item } from '../api/types';
  import Artwork from '../components/Artwork.svelte';
  import { t } from '../i18n';
  import { formatClock, formatDuration } from '../util/format';
  import { NEXT_COUNTDOWN_S } from './upNext';

  interface Props {
    next: Item;
    /** Seconden tot de aflevering vanzelf start. */
    seconds: number;
    onplay: () => void;
    oncredits: () => void;
  }

  let { next, seconds, onplay, oncredits }: Props = $props();

  const title = $derived(typeof next.index === 'number' ? `${next.index}. ${next.title}` : next.title);
  const meta = $derived(
    [
      formatDuration(next.duration_ms),
      next.duration_ms ? t('player.endsAt', { time: formatClock(new Date(Date.now() + next.duration_ms).toISOString()) ?? '' }) : null
    ].filter(Boolean).join(' · ')
  );
</script>

<section class="next" aria-labelledby="player-next-title">
  <div class="next__top">
    <div class="next__thumb">
      <Artwork artworkId={next.artwork?.backdrop_id ?? next.artwork?.poster_id} alt="" shape="wide" eager />
    </div>
    <div class="next__text">
      <p class="next__label" id="player-next-title">{t('player.next')}</p>
      <p class="next__title">{title}</p>
      {#if meta}<p class="next__meta">{meta}</p>{/if}
    </div>
  </div>
  <div class="next__actions">
    <button class="next__go" type="button" aria-label={t('player.nextPlayLabel', { seconds })} onclick={onplay}>
      <span class="next__fill" aria-hidden="true" style:width={`${(1 - seconds / NEXT_COUNTDOWN_S) * 100}%`}></span>
      <span class="next__count">{t('player.nextPlay', { seconds })}</span>
    </button>
    <button class="next__stay" type="button" onclick={oncredits}>{t('player.watchCredits')}</button>
  </div>
</section>

<style>
  .next {
    position: absolute;
    right: 0;
    bottom: var(--space);
    width: min(440px, 100%);
    padding: 16px;
    border-radius: 18px;
    border: 1px solid rgba(255, 255, 255, 0.2);
    background: #1a1a1a;
    pointer-events: auto;
  }

  .next__top {
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .next__thumb {
    flex: none;
    width: 168px;
    border-radius: 10px;
    overflow: hidden;
  }

  .next__text {
    flex: 1;
    min-width: 0;
  }

  .next__text p {
    margin: 0;
  }

  .next__label {
    font-size: var(--text-caps-size);
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: rgba(255, 255, 255, 0.7);
  }

  .next__title {
    margin-top: 4px;
    font-size: 18px;
    font-weight: 700;
    overflow-wrap: anywhere;
  }

  .next__meta {
    font-size: 13px;
    color: rgba(255, 255, 255, 0.78);
  }

  .next__actions {
    display: flex;
    gap: 10px;
    margin-top: 16px;
  }

  .next__go,
  .next__stay {
    flex: 1;
    min-height: 52px;
    border-radius: var(--radius-pill);
    font-size: 15px;
  }

  .next__go {
    position: relative;
    overflow: hidden;
    background: rgba(255, 255, 255, 0.28);
    color: #111;
    font-weight: 700;
  }

  .next__fill {
    position: absolute;
    inset: 0 auto 0 0;
    background: #fff;
    transition: width 1s linear;
  }

  .next__count {
    position: relative;
  }

  .next__stay {
    border: 1px solid rgba(255, 255, 255, 0.4);
    color: #fff;
    font-weight: 500;
  }

  .next :focus-visible {
    outline-color: var(--player-focus);
  }

  @media (prefers-reduced-motion: reduce) {
    .next__fill {
      transition: none;
    }
  }

  /* Smal: het beeld wijkt, de twee knoppen houden hun 52 px. */
  @media (max-width: 479px) {
    .next__thumb {
      width: 96px;
    }

    .next__go,
    .next__stay {
      font-size: 14px;
    }
  }
</style>
