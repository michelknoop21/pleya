<!--
  De onderbalk van het doelbeeld Kijken-speler: de zoekbalk, daaronder de
  positie links en "nog 28:48 · klaar om 21:47" rechts, en dan één rij met
  terug, afspelen, vooruit, volgende aflevering en geluid links, en
  ondertitels, instellingen, beeld in beeld en volledig scherm rechts.

  Onder 900 px past die rij niet: terug, afspelen en vooruit staan dan midden
  in beeld en de volumeschuif valt weg. Elke functie blijft bereikbaar.
-->
<script lang="ts">
  import { t } from '../i18n';
  import { formatClock } from '../util/format';
  import { formatPlayTime } from './keyboard';
  import PlayerIcon from './PlayerIcon.svelte';
  import PlayerSeekBar from './PlayerSeekBar.svelte';

  interface Props {
    paused: boolean;
    current: number;
    total: number;
    buffered: number;
    limit: number | null;
    volume: number;
    muted: boolean;
    rate: number;
    fullscreen: boolean;
    /** De bron speelt; tot dan is er niets om in te spoelen. */
    ready: boolean;
    /** Het label van de actieve ondertitel, of null als ze uit staan. */
    subtitleLabel: string | null;
    subtitlePreparing?: boolean;
    /** "Ondertitels voorbereiden" of de mislukking; de film speelt intussen door. */
    subtitleNote?: string | null;
    menu: 'subtitles' | 'settings' | null;
    ontoggle: () => void;
    onseek: (seconds: number) => void;
    onvolume: (volume: number) => void;
    onmute: () => void;
    onfullscreen: () => void;
    onsubtitles: () => void;
    onsettings: () => void;
    /** Alleen als er een volgende aflevering is. */
    onnext?: (() => void) | null;
    /** Alleen als de browser beeld in beeld kent. */
    onpip?: (() => void) | null;
  }

  let p: Props = $props();

  const left = $derived(Math.max(0, p.total - p.current));
  const endsAt = $derived(
    p.total > 0 ? formatClock(new Date(Date.now() + (left / (p.rate || 1)) * 1000).toISOString()) : null
  );
</script>

<div class="bar">
  <PlayerSeekBar
    current={p.current}
    total={p.total}
    buffered={p.buffered}
    limit={p.limit}
    onseek={p.onseek}
  />
  <div class="times">
    <span>{formatPlayTime(p.current)}</span>
    {#if p.total > 0}
      <span>
        {t('player.remaining', { duration: formatPlayTime(left) })}{#if endsAt}<span class="ends">&nbsp;· {t('player.endsAt', { time: endsAt })}</span>{/if}
      </span>
    {/if}
  </div>
  <div class="row">
    <div class="transport" class:transport--covered={p.menu !== null}>
      {#if p.ready}
        <button class="icon" type="button" aria-label={t('player.rewind')} onclick={() => p.onseek(p.current - 10)}>
          <PlayerIcon name="rewind" size={26} />
        </button>
      {/if}
      <button
        class="icon icon--primary"
        type="button"
        aria-label={p.paused ? t('player.play') : t('player.pause')}
        onclick={p.ontoggle}
      >
        <PlayerIcon name={p.paused ? 'play' : 'pause'} size={28} />
      </button>
      {#if p.ready}
        <button class="icon" type="button" aria-label={t('player.forward')} onclick={() => p.onseek(p.current + 10)}>
          <PlayerIcon name="forward" size={26} />
        </button>
      {/if}
    </div>
    {#if p.onnext}
      <button class="icon" type="button" aria-label={t('player.next')} onclick={p.onnext}>
        <PlayerIcon name="next" />
      </button>
    {/if}
    <button
      class="icon"
      type="button"
      aria-label={p.muted ? t('player.unmute') : t('player.mute')}
      aria-pressed={p.muted}
      onclick={p.onmute}
    >
      <PlayerIcon name={p.muted || p.volume === 0 ? 'muted' : 'volume'} />
    </button>
    <input
      class="volume"
      type="range"
      min="0"
      max="1"
      step="0.05"
      value={p.muted ? 0 : p.volume}
      aria-label={t('player.volume')}
      oninput={(e) => p.onvolume(Number(e.currentTarget.value))}
    />
    <span class="gap"></span>
    <button
      class="subs"
      class:subs--on={p.subtitleLabel !== null}
      class:subs--open={p.menu === 'subtitles'}
      class:subs--preparing={p.subtitlePreparing}
      type="button"
      aria-label={p.subtitleNote ?? t('player.subtitles')}
      aria-expanded={p.menu === 'subtitles'}
      title={p.subtitleNote ?? undefined}
      onclick={p.onsubtitles}
    >
      <span class="subs__icon"><PlayerIcon name="cc" /></span>
      <span class="subs__text">{t('player.subtitles')}{p.subtitleLabel ? ` · ${p.subtitleLabel}` : ''}</span>
    </button>
    <button
      class="icon"
      class:icon--open={p.menu === 'settings'}
      type="button"
      aria-label={t('player.settings')}
      aria-expanded={p.menu === 'settings'}
      onclick={p.onsettings}
    >
      <PlayerIcon name="settings" />
    </button>
    {#if p.onpip}
      <button class="icon" type="button" aria-label={t('player.pip')} onclick={p.onpip}>
        <PlayerIcon name="pip" />
      </button>
    {/if}
    <button
      class="icon"
      type="button"
      aria-label={p.fullscreen ? t('player.exitFullscreen') : t('player.fullscreen')}
      onclick={p.onfullscreen}
    >
      <PlayerIcon name={p.fullscreen ? 'fullscreen-exit' : 'fullscreen'} />
    </button>
  </div>
</div>

<style>
  .bar {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
  }

  .times {
    display: flex;
    justify-content: space-between;
    gap: var(--space);
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: rgba(255, 255, 255, 0.86);
    white-space: nowrap;
  }

  .row,
  .transport {
    display: flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }

  .row {
    margin: var(--space-half) -8px 0;
  }

  .gap {
    flex: 1;
  }

  .icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 48px;
    height: 48px;
    border-radius: 50%;
    color: #fff;
    flex: none;
  }

  .icon--primary {
    width: 60px;
    height: 60px;
    background: var(--player-primary);
    color: var(--player-primary-ink);
  }

  .icon--open {
    background: rgba(255, 255, 255, 0.18);
  }

  .subs {
    display: inline-flex;
    align-items: center;
    height: 48px;
    padding: 0 16px;
    margin-right: 4px;
    border-radius: var(--radius-pill);
    border: 1px solid rgba(255, 255, 255, 0.4);
    color: #fff;
    font-size: 14px;
    font-weight: 500;
    white-space: nowrap;
    min-width: 0;
  }

  .subs__text {
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .subs__icon {
    display: none;
  }

  .subs--on {
    background: rgba(255, 255, 255, 0.14);
  }

  .subs--open {
    background: #fff;
    border-color: #fff;
    color: #111;
    font-weight: 700;
  }

  .subs--preparing {
    animation: cc-wait 1.4s ease-in-out infinite;
  }

  @keyframes cc-wait {
    50% {
      opacity: 0.45;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .subs--preparing {
      animation: none;
    }
  }

  .volume {
    width: 110px;
    accent-color: #fff;
    margin: 0 var(--space-half) 0 0;
  }

  @media (hover: hover) {
    .icon:not(.icon--primary):hover,
    .subs:not(.subs--open):hover {
      background: rgba(255, 255, 255, 0.12);
    }
  }

  /*
   * Smal: terug, afspelen en vooruit midden in beeld, de ondertitelknop als
   * pictogram, geen volumeschuif (de geluidsknop blijft). Bij 320 passen zo
   * zes knoppen van 44 px naast elkaar.
   */
  @media (max-width: 899px) {
    .transport {
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      gap: 24px;
    }

    /* Een open menu ligt op smal over het midden; de knoppen schemeren er anders doorheen. */
    .transport--covered {
      visibility: hidden;
    }

    .transport .icon:not(.icon--primary) {
      width: 52px;
      height: 52px;
      background: rgba(0, 0, 0, 0.38);
      border: 1px solid rgba(255, 255, 255, 0.22);
    }

    .transport .icon--primary {
      width: 68px;
      height: 68px;
    }

    .row {
      gap: 0;
      margin: 0 -6px;
    }

    .icon,
    .subs {
      width: var(--touch-target);
      height: var(--touch-target);
    }

    .subs {
      justify-content: center;
      padding: 0;
      margin: 0;
      border: 0;
      border-radius: 50%;
    }

    .subs--on {
      background: none;
      color: var(--player-focus);
    }

    .subs--open {
      background: rgba(255, 255, 255, 0.18);
      color: #fff;
    }

    .subs__text,
    .volume,
    .ends {
      display: none;
    }

    .subs__icon {
      display: inline-flex;
    }
  }

  /* Liggende telefoon: de middenrij mag de onderbalk niet raken. */
  @media (max-width: 899px) and (max-height: 440px) {
    .transport {
      top: 42%;
    }
  }
</style>
