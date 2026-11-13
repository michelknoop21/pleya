<!--
  Het slotscherm van het doelbeeld Kijken-speler-slot: wat je net keek, je
  cijfer, favoriet, opnieuw kijken en de rij Verder kijken. De speler tekent de
  tegel met het doorlopende beeld en de terugknop; dit is de rest.

  Cijfer en favoriet staan er alleen onder `capabilities.ratings` en
  `capabilities.favorites`. "Meer zoals dit" uit het doelbeeld ontbreekt: de
  server heeft geen aanbevelingsroute.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';

  import { describeError } from '../api/errors';
  import { personalApi } from '../api/personal';
  import type { Item } from '../api/types';
  import ContinueWatchingRail from '../components/ContinueWatchingRail.svelte';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import { formatDuration } from '../util/format';

  interface Props {
    item: Item;
    /** De kop: de serie bij een aflevering, anders de titel zelf. */
    heading: string;
    subheading?: string | null;
    onchange: (next: Item) => void;
    onreplay: () => void;
  }

  let { item, heading, subheading = null, onchange, onreplay }: Props = $props();

  let busy = $state(false);
  let error = $state<string | null>(null);
  let others = $state<Item[]>([]);
  let active = true;
  onDestroy(() => { active = false; });

  const meta = $derived(subheading ?? [item.year, formatDuration(item.duration_ms)].filter(Boolean).join(' · '));

  // Zonder rij is het scherm ook af: een mislukte aanvraag laat hem gewoon weg.
  $effect(() => {
    const id = item.id;
    const controller = new AbortController();
    session.client.hub('continue_watching', { limit: 12 }, controller.signal)
      .then((page) => { others = page.items.filter((other) => other.id !== id); })
      .catch(() => undefined);
    return () => controller.abort();
  });

  async function change(operation: (api: ReturnType<typeof personalApi>) => Promise<Partial<Item>>): Promise<void> {
    if (busy) return;
    busy = true;
    error = null;
    try {
      const patch = await operation(personalApi(session.client));
      if (active) onchange({ ...item, ...patch });
    } catch (err) {
      if (active) error = describeError(err);
    } finally {
      busy = false;
    }
  }

  // Nog een keer op je eigen cijfer haalt het weg.
  const rate = (value: number) => {
    const rating = item.rating === value ? null : value;
    void change(async (api) => { await api.setRating(item.id, rating); return { rating }; });
  };
  const favorite = () => {
    const next = !item.favorite;
    void change(async (api) => { await api.setFavorite(item.id, next); return { favorite: next }; });
  };
</script>

<div class="end__summary">
  <p class="lbl">{t('player.watched')}</p>
  <h1 class="title">{heading}</h1>
  {#if meta}<p class="meta">{meta}</p>{/if}
  <div class="acts">
    {#if session.capabilities?.ratings}
      <div class="rating" role="group" aria-label={t('player.yourRating')}>
        <span class="rating__label">{t('player.yourRating')}</span>
        {#each Array.from({ length: 10 }, (_, i) => i + 1) as value (value)}
          <button
            class="act act--num"
            type="button"
            aria-label={t('player.rateValue', { rating: value })}
            aria-pressed={item.rating === value}
            aria-disabled={busy}
            onclick={() => rate(value)}
          >{value}</button>
        {/each}
      </div>
    {/if}
    {#if session.capabilities?.favorites}
      <button class="act" type="button" aria-pressed={!!item.favorite} aria-disabled={busy} onclick={favorite}>
        {t('player.favorite')}
      </button>
    {/if}
    <button class="act" type="button" onclick={onreplay}>{t('player.rewatch')}</button>
  </div>
  {#if error}<p class="meta" role="alert">{error}</p>{/if}
</div>

{#if others.length > 0}
  <div class="end__rail"><ContinueWatchingRail items={others} /></div>
{/if}

<style>
  .lbl {
    margin: 0;
    font-size: var(--text-caps-size);
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: rgba(255, 255, 255, 0.7);
  }

  .title {
    margin: 8px 0;
    font-size: clamp(26px, 3.4vw, 40px);
    line-height: 1.1;
    overflow-wrap: anywhere;
  }

  .meta {
    margin: 0 0 20px;
    font-size: 14px;
    color: rgba(255, 255, 255, 0.78);
  }

  .acts,
  .rating {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px;
  }

  /* Het cijfer krijgt zijn eigen regel; favoriet en opnieuw kijken staan eronder. */
  .rating {
    flex: 0 0 100%;
    gap: 6px;
  }

  .rating__label {
    flex-basis: 100%;
    font-size: 14px;
  }

  .act {
    min-height: var(--touch-target);
    padding: 0 18px;
    border-radius: var(--radius-pill);
    border: 1px solid rgba(255, 255, 255, 0.3);
    color: #fff;
    font-size: 14px;
    font-weight: 500;
  }

  .act--num {
    width: var(--touch-target);
    padding: 0;
    font-variant-numeric: tabular-nums;
  }

  .act[aria-pressed='true'] {
    background: #fff;
    border-color: #fff;
    color: #111;
    font-weight: 700;
  }

  /* aria-disabled en niet disabled: de focus blijft op de knop terwijl de aanvraag loopt. */
  .act[aria-disabled='true'] {
    opacity: 0.5;
    cursor: progress;
  }

  .act:focus-visible {
    outline-color: var(--player-focus);
  }

  @media (hover: hover) {
    .act:not([aria-pressed='true']):hover {
      background: rgba(255, 255, 255, 0.12);
    }
  }
</style>
