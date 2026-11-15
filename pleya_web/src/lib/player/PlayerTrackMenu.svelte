<!--
  Het ondertitelmenu van het doelbeeld Kijken-speler-menu: uit of een spoor,
  met erachter het formaat en waar het vandaan komt, en de tekstgrootte. Wat de
  browser of het contract niet kan leveren staat erbij als zin, niet als een
  knop die niets doet (zie `tracks.ts`). Audio staat in het instellingenmenu.
-->
<script lang="ts">
  import { onMount } from 'svelte';

  import { plural, t } from '../i18n';
  import PlayerIcon from './PlayerIcon.svelte';
  import type { TrackOption } from './tracks';

  export type SubtitleSize = 'small' | 'normal' | 'large';

  interface Props {
    subtitles: TrackOption[];
    subtitleId: string | null;
    skippedSubtitles: number;
    size: SubtitleSize;
    onsize: (size: SubtitleSize) => void;
    error?: string | null;
    loading?: boolean;
    preparing?: boolean;
    onsubtitle: (id: string | null) => void;
    onsubtitleretry?: (() => void) | null;
    onclose: () => void;
  }

  let {
    subtitles,
    subtitleId,
    skippedSubtitles,
    size,
    onsize,
    error = null,
    loading = false,
    preparing = false,
    onsubtitle,
    onsubtitleretry = null,
    onclose
  }: Props = $props();

  let panel = $state<HTMLElement | null>(null);

  onMount(() => {
    const opener = document.activeElement;
    panel?.querySelector<HTMLInputElement>('input:checked, input')?.focus();
    return () => { if (opener instanceof HTMLElement && opener.isConnected) opener.focus(); };
  });
</script>

<div class="menu" aria-busy={loading} role="dialog" aria-label={t('player.subtitles')} bind:this={panel}>
  <div class="group" role="radiogroup" aria-label={t('player.subtitles')}>
    <div class="menu__head">
      <h2 class="group__title">{t('player.subtitles')}</h2>
      <button class="menu__close" type="button" aria-label={t('player.closeMenu')} onclick={onclose}>
        <PlayerIcon name="close" size={18} />
      </button>
    </div>
    {#if loading}<p class="note" role="status">{preparing ? t('player.subtitlePreparing') : t('loading')}</p>{/if}
    {#if error}
      <p class="note" role="alert">{error}</p>
      {#if onsubtitleretry}
        <button class="retry" type="button" onclick={onsubtitleretry}>{t('player.subtitleRetry')}</button>
      {/if}
    {/if}
    <label class="row">
      <input
        type="radio"
        name="player-subtitles"
        checked={subtitleId === null}
        onchange={() => onsubtitle(null)}
      />
      <span>{t('player.subtitlesOff')}</span>
    </label>
    {#each subtitles as option (option.id)}
      <label class="row">
        <input
          type="radio"
          name="player-subtitles"
          aria-label={option.label}
          checked={subtitleId === option.id}
          onchange={() => onsubtitle(option.id)}
        />
        <span>{option.label}</span>
        {#if option.note}<span class="row__note">{option.note}</span>{/if}
      </label>
    {/each}
    {#if subtitles.length === 0 && skippedSubtitles === 0}
      <p class="note">{t('player.subtitlesNone')}</p>
    {/if}
    {#if skippedSubtitles > 0}
      <p class="note">{plural('player.subtitlesSkipped', skippedSubtitles)}</p>
    {/if}
  </div>
  <div class="size" role="group" aria-label={t('player.subtitleSize')}>
    <span class="size__label">{t('player.subtitleSize')}</span>
    {#each ['small', 'normal', 'large'] as const as option (option)}
      <button class="size__btn" type="button" aria-pressed={size === option} onclick={() => onsize(option)}>
        {t(`player.subtitleSize.${option}`)}
      </button>
    {/each}
  </div>
</div>

<style>
  .menu {
    /* De onderbalk staat al op de inset; het menu lijnt rechts uit op die balk. */
    position: absolute;
    right: 0;
    bottom: var(--space);
    width: min(340px, 100%);
    max-height: min(calc(100% - var(--space)), 60vh, 460px);
    pointer-events: auto;
    overflow-y: auto;
    padding: var(--space) var(--space-1-5) var(--space-1-5);
    border-radius: var(--radius-card);
    background: rgba(20, 20, 20, 0.94);
    color: #fff;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
  }

  .menu__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .row__note {
    margin-left: auto;
    padding-left: var(--space);
    color: rgba(255, 255, 255, 0.7);
    font-size: 13px;
    text-align: right;
  }

  .size {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: var(--space-half);
    padding-top: var(--space);
    border-top: 1px solid rgba(255, 255, 255, 0.12);
  }

  .size__label {
    flex: 1;
    font-size: 14px;
    font-weight: 500;
  }

  .size__btn {
    min-height: var(--touch-target);
    min-width: 52px;
    padding: 0 12px;
    border-radius: var(--radius-pill);
    border: 1px solid rgba(255, 255, 255, 0.22);
    color: #fff;
    font-size: 13px;
    font-weight: 500;
  }

  @media (max-width: 379px) {
    .size__label {
      flex-basis: 100%;
    }
  }

  .size__btn[aria-pressed='true'] {
    background: #fff;
    border-color: #fff;
    color: #111;
    font-weight: 700;
  }

  .menu__close {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: var(--touch-target);
    height: var(--touch-target);
    margin-right: calc(-1 * var(--space-half));
    border-radius: 50%;
    color: inherit;
  }

  .group {
    min-width: 0;
  }

  .group__title {
    margin: 0;
    font-weight: 400;
    font-size: var(--text-caps-size);
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: rgba(255, 255, 255, 0.6);
  }

  .row {
    display: flex;
    align-items: center;
    gap: var(--space);
    min-height: var(--touch-target);
    font-size: 14px;
    cursor: pointer;
  }

  .row:has(input:disabled) {
    color: rgba(255, 255, 255, 0.45);
    cursor: default;
  }

  .row input {
    accent-color: var(--accent);
    width: 18px;
    height: 18px;
    margin: 0;
    flex: none;
  }

  .row span {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .note {
    margin: var(--space-half) 0 0;
    font-size: var(--text-small-size);
    line-height: var(--text-small-line);
    color: rgba(255, 255, 255, 0.65);
  }

  .retry {
    min-height: var(--touch-target);
    padding: 0;
    color: inherit;
    font-size: 14px;
    font-weight: 700;
    text-decoration: underline;
  }

  .menu :focus-visible {
    outline-color: #fff;
  }
</style>
