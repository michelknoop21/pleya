<!--
  De spoorkiezer: audio en ondertitels als twee groepen keuzerondjes. Wat de
  browser of het contract niet kan leveren staat erbij als zin, niet als een
  knop die niets doet (zie `tracks.ts`).
-->
<script lang="ts">
  import { onMount } from 'svelte';

  import { plural, t } from '../i18n';
  import PlayerIcon from './PlayerIcon.svelte';
  import type { TrackOption } from './tracks';

  interface Props {
    audio: TrackOption[];
    audioIndex: number;
    audioSwitchable: boolean;
    onaudio: (index: number) => void;
    subtitles: TrackOption[];
    subtitleId: string | null;
    skippedSubtitles: number;
    onsubtitle: (id: string | null) => void;
    onclose: () => void;
  }

  let {
    audio,
    audioIndex,
    audioSwitchable,
    onaudio,
    subtitles,
    subtitleId,
    skippedSubtitles,
    onsubtitle,
    onclose
  }: Props = $props();

  let panel = $state<HTMLElement | null>(null);

  onMount(() => {
    panel?.querySelector<HTMLInputElement>('input:checked, input')?.focus();
  });
</script>

<div class="menu" role="dialog" aria-label={t('player.tracks')} bind:this={panel}>
  <div class="menu__head">
    <h2 class="menu__title">{t('player.tracks')}</h2>
    <button class="menu__close" type="button" aria-label={t('player.closeMenu')} onclick={onclose}>
      <PlayerIcon name="close" size={18} />
    </button>
  </div>

  <fieldset class="group">
    <legend class="group__title">{t('item.audio')}</legend>
    {#each audio as option, i (option.id)}
      <label class="row">
        <input
          type="radio"
          name="player-audio"
          checked={i === audioIndex}
          disabled={!audioSwitchable && i !== audioIndex}
          onchange={() => onaudio(i)}
        />
        <span>{option.label}</span>
      </label>
    {/each}
    {#if !audioSwitchable && audio.length > 1}
      <p class="note">{t('player.audioFixed')}</p>
    {/if}
  </fieldset>

  <fieldset class="group">
    <legend class="group__title">{t('player.subtitles')}</legend>
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
          checked={subtitleId === option.id}
          onchange={() => onsubtitle(option.id)}
        />
        <span>{option.label}</span>
      </label>
    {/each}
    {#if subtitles.length === 0 && skippedSubtitles === 0}
      <p class="note">{t('player.subtitlesNone')}</p>
    {/if}
    {#if skippedSubtitles > 0}
      <p class="note">{plural('player.subtitlesSkipped', skippedSubtitles)}</p>
    {/if}
  </fieldset>
</div>

<style>
  .menu {
    /* De onderbalk staat al op de inset; het menu lijnt rechts uit op die balk. */
    position: absolute;
    right: 0;
    bottom: calc(100% + var(--space));
    width: min(340px, 100%);
    max-height: min(60vh, 460px);
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

  .menu__title {
    margin: 0;
    font-size: 16px;
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
    margin: var(--space) 0 0;
    padding: 0;
    border: 0;
    min-width: 0;
  }

  .group__title {
    padding: 0;
    margin-bottom: var(--space-half);
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

  .menu :focus-visible {
    outline-color: #fff;
  }
</style>
