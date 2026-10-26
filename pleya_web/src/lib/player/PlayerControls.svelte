<!--
  De onderbalk van mockup 50: zoekbalk, en daaronder tijd, afspelen,
  volume, ondertitels en snelheid links, spoorkiezer, volledig scherm en
  totale duur rechts.

  De slaaptimer uit de mockup hoort niet bij S13.2 of S18.3 en staat er niet;
  het pop-outicoon is hier volledig scherm, dat de opdracht vraagt.
-->
<script lang="ts">
  import { t } from '../i18n';
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
    subtitlesOn: boolean;
    menuOpen: boolean;
    ontoggle: () => void;
    onseek: (seconds: number) => void;
    onvolume: (volume: number) => void;
    onmute: () => void;
    onrate: () => void;
    onfullscreen: () => void;
    onmenu: () => void;
  }

  let p: Props = $props();

  const rateLabel = $derived(
    `${new Intl.NumberFormat(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 2 }).format(p.rate)}×`
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
  <div class="row">
    <div class="side">
      <span class="time">{formatPlayTime(p.current)}</span>
      <button
        class="icon"
        type="button"
        aria-label={p.paused ? t('player.play') : t('player.pause')}
        onclick={p.ontoggle}
      >
        <PlayerIcon name={p.paused ? 'play' : 'pause'} />
      </button>
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
      <button
        class="icon"
        class:icon--on={p.subtitlesOn}
        type="button"
        aria-label={t('player.subtitles')}
        aria-expanded={p.menuOpen}
        onclick={p.onmenu}
      >
        <PlayerIcon name="cc" />
      </button>
      <button
        class="pill speed"
        type="button"
        aria-label={t('player.speed', { speed: rateLabel })}
        onclick={p.onrate}
      >
        {rateLabel}
      </button>
    </div>
    <div class="side">
      <button
        class="icon"
        type="button"
        aria-label={t('player.tracks')}
        aria-expanded={p.menuOpen}
        onclick={p.onmenu}
      >
        <PlayerIcon name="tracks" />
      </button>
      <button
        class="icon"
        type="button"
        aria-label={p.fullscreen ? t('player.exitFullscreen') : t('player.fullscreen')}
        onclick={p.onfullscreen}
      >
        <PlayerIcon name={p.fullscreen ? 'fullscreen-exit' : 'fullscreen'} />
      </button>
      <span class="time time--total">{formatPlayTime(p.total)}</span>
    </div>
  </div>
</div>

<style>
  .bar {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-half);
    min-width: 0;
  }

  .side {
    display: flex;
    align-items: center;
    gap: 2px;
    min-width: 0;
  }

  .time {
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: rgba(255, 255, 255, 0.85);
    padding-right: var(--space-half);
    white-space: nowrap;
  }

  .time--total {
    padding: 0 0 0 var(--space-half);
  }

  .icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: var(--touch-target);
    height: var(--touch-target);
    border-radius: 50%;
    color: #fff;
    flex: none;
  }

  .icon--on {
    color: var(--accent);
  }

  .pill {
    min-height: 32px;
    padding: 0 12px;
    margin: 0 var(--space-half);
    border-radius: var(--radius-pill);
    border: 1px solid rgba(255, 255, 255, 0.35);
    color: #fff;
    font-size: 13px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .volume {
    width: 84px;
    accent-color: #fff;
    margin: 0 var(--space-half) 0 0;
  }

  @media (hover: hover) {
    .icon:hover,
    .pill:hover {
      background: rgba(255, 255, 255, 0.12);
    }
  }

  /* Smal: de volumeschuif valt weg (de knop blijft), net als in mockup 50 op 393. */
  @media (max-width: 899px) {
    .volume,
    .time--total {
      display: none;
    }
  }

  /* 320 tot 379: de snelheid wijkt, de knoppen houden hun 44 px. */
  @media (max-width: 379px) {
    .speed {
      display: none;
    }
    .time {
      padding-right: 2px;
    }
  }
</style>
