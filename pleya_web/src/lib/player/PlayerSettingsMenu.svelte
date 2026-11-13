<!--
  Het instellingenmenu van het doelbeeld Kijken-speler: kwaliteit, audio,
  snelheid, beeldverhouding en afspeelinfo. Een rij opent zijn keuzes in
  hetzelfde paneel. Kwaliteit staat er alleen als de server limieten aanneemt
  (`capabilities.playback_quality`).
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';

  import { intlLocale, t } from '../i18n';
  import { SPEEDS } from './keyboard';
  import type { QualityOption } from './labels';
  import PlayerIcon from './PlayerIcon.svelte';
  import type { TrackOption } from './tracks';

  export type Aspect = 'contain' | 'cover';
  type Page = 'quality' | 'audio' | 'speed' | 'aspect';

  interface Props {
    /** Leeg als de server geen kwaliteitslimiet aanneemt. */
    quality: QualityOption[];
    qualityId: string;
    onquality: (option: QualityOption) => void;
    audio: TrackOption[];
    audioIndex: number;
    /** Of een ander spoor kiezen iets doet: in de browser zelf of via een nieuw plan. */
    audioSwitchable: boolean;
    /** Een ander spoor loopt via een nieuw plan, net als een andere kwaliteit. */
    audioReplans: boolean;
    onaudio: (index: number) => void;
    rate: number;
    onrate: (rate: number) => void;
    aspect: Aspect;
    onaspect: (aspect: Aspect) => void;
    info: boolean;
    oninfo: () => void;
  }

  let p: Props = $props();

  let panel = $state<HTMLElement | null>(null);
  let page = $state<Page | null>(null);

  const speedLabel = (rate: number) => `${new Intl.NumberFormat(intlLocale(), { maximumFractionDigits: 2 }).format(rate)}×`;
  const speeds = [...SPEEDS].sort((a, b) => a - b);

  const rows = $derived<{ page: Page; label: string; value: string }[]>([
    ...(p.quality.length > 1
      ? [{ page: 'quality' as const, label: t('player.quality'), value: p.quality.find((q) => q.id === p.qualityId)?.label ?? '' }]
      : []),
    ...(p.audio.length > 0
      ? [{ page: 'audio' as const, label: t('item.audio'), value: p.audio[p.audioIndex]?.label ?? '' }]
      : []),
    { page: 'speed', label: t('player.speedTitle'), value: speedLabel(p.rate) },
    { page: 'aspect', label: t('player.aspect'), value: t(`player.aspect.${p.aspect}`) }
  ]);

  const choices = $derived.by((): { label: string; checked: boolean; disabled?: boolean; pick: () => void }[] => {
    if (page === 'quality') return p.quality.map((q) => ({ label: q.label, checked: q.id === p.qualityId, pick: () => p.onquality(q) }));
    if (page === 'audio')
      return p.audio.map((a, i) => ({
        label: a.label, checked: i === p.audioIndex, disabled: !p.audioSwitchable && i !== p.audioIndex, pick: () => p.onaudio(i)
      }));
    if (page === 'speed') return speeds.map((s) => ({ label: speedLabel(s), checked: Math.abs(s - p.rate) < 0.001, pick: () => p.onrate(s) }));
    return (['contain', 'cover'] as const).map((a) => ({ label: t(`player.aspect.${a}`), checked: a === p.aspect, pick: () => p.onaspect(a) }));
  });

  async function open(next: Page | null): Promise<void> {
    page = next;
    await tick();
    (panel?.querySelector<HTMLElement>('[role="menuitemradio"][aria-checked="true"]') ?? panel?.querySelector<HTMLElement>('button'))?.focus();
  }

  // Omhoog en omlaag verplaatsen de focus; de speler zelf laat de pijlen met rust zolang een menu open staat.
  function onKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault();
    const items = [...(panel?.querySelectorAll<HTMLElement>('button:not(:disabled)') ?? [])];
    const step = event.key === 'ArrowDown' ? 1 : -1;
    items[(items.indexOf(document.activeElement as HTMLElement) + step + items.length) % items.length]?.focus();
  }

  onMount(() => {
    const opener = document.activeElement;
    panel?.querySelector<HTMLElement>('button')?.focus();
    return () => { if (opener instanceof HTMLElement && opener.isConnected) opener.focus(); };
  });
</script>

<div class="menu" role="menu" tabindex="-1" aria-label={t('player.settings')} bind:this={panel} onkeydown={onKey}>
  {#if page === null}
    {#each rows as row (row.page)}
      <button class="mi" type="button" role="menuitem" aria-haspopup="true" onclick={() => void open(row.page)}>
        {row.label}<span class="mi__value">{row.value}</span>
      </button>
    {/each}
    <button class="mi" class:mi--on={p.info} type="button" role="menuitemcheckbox" aria-checked={p.info} onclick={p.oninfo}>
      {t('player.info')}<span class="mi__value">{t(p.info ? 'player.on' : 'player.off')}</span>
    </button>
  {:else}
    <button class="mi mi--back" type="button" role="menuitem" aria-label={t('player.back')} onclick={() => void open(null)}>
      <PlayerIcon name="back" size={18} />{rows.find((row) => row.page === page)?.label}
    </button>
    {#each choices as choice, index (index)}
      <button
        class="mi"
        class:mi--on={choice.checked}
        type="button"
        role="menuitemradio"
        aria-checked={choice.checked}
        disabled={choice.disabled}
        onclick={choice.pick}
      >
        {choice.label}
      </button>
    {/each}
    {#if page === 'quality' || (page === 'audio' && p.audioReplans)}
      <p class="note">{t('player.replanNote')}</p>
    {/if}
    {#if page === 'audio' && !p.audioSwitchable && p.audio.length > 1}
      <p class="note">{t('player.audioFixed')}</p>
    {/if}
  {/if}
</div>

<style>
  .menu {
    position: absolute;
    right: 0;
    bottom: var(--space);
    width: min(300px, 100%);
    max-height: min(calc(100% - var(--space)), 60vh, 460px);
    pointer-events: auto;
    overflow-y: auto;
    padding: 8px;
    border-radius: var(--radius-card);
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(20, 20, 20, 0.94);
    color: #fff;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
  }

  .mi {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    min-height: var(--touch-target);
    padding: 0 12px;
    border-radius: 8px;
    color: #fff;
    font-size: 14px;
    font-weight: 500;
    text-align: left;
  }

  .mi--on {
    background: #2f2f2f;
  }

  .mi--back {
    color: rgba(255, 255, 255, 0.7);
    font-size: var(--text-caps-size);
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
  }

  .mi:disabled {
    color: rgba(255, 255, 255, 0.45);
  }

  .mi__value {
    margin-left: auto;
    color: rgba(255, 255, 255, 0.7);
    text-align: right;
  }

  .note {
    margin: var(--space-half) 12px;
    font-size: var(--text-small-size);
    line-height: var(--text-small-line);
    color: rgba(255, 255, 255, 0.65);
  }

  .menu :focus-visible {
    outline-color: #fff;
  }

  @media (hover: hover) {
    .mi:not(:disabled):hover {
      background: rgba(255, 255, 255, 0.1);
    }
  }
</style>
