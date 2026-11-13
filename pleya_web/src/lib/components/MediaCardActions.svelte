<!--
  De handelingen op een kaart, als zuster van de link en dus nooit een knop in
  een <a>. Twee vormen:

  Zonder `quick` alleen het kaartmenu rechtsboven op het beeld, zoals het was.

  Met `quick` (Home) een laag over het hele beeld met vier acties: afspelen,
  gezien, favoriet en hetzelfde kaartmenu. Met een muis verschijnt de laag bij
  hover, met een toetsenbord zodra de focus in de kaart staat; de knoppen
  volgen in de tabvolgorde direct op de kaartlink. Op een aanraakscherm is er
  geen hover: daar staat alleen het menu, rechtsonder op het beeld, en dat
  draagt dezelfde acties. De detailpagina blijft de gewone tik op de kaart.

  Elke actie volgt de capability van de server en de soort van het item: geen
  knop voor wat de server niet kan. Een serie heeft geen afspeelknop en geen
  gezien-knop, want kijkstatus en afspelen horen bij een film of aflevering.

  De laag krijgt geen transform: het menu hangt met position: fixed aan zijn
  knop, en een transform op een voorouder zou dat aan de kaart ophangen.
-->
<script lang="ts">
  import CardMenu from './CardMenu.svelte';
  import { describeError } from '../api/errors';
  import { personalApi } from '../api/personal';
  import type { Item } from '../api/types';
  import { t } from '../i18n';
  import { playerHref } from '../player/route';
  import { session } from '../stores/session.svelte';

  interface Props {
    /** Het item zoals de kaart het nu toont, dus met wat hier al gewijzigd is. */
    item: Item;
    shape: 'poster' | 'wide';
    quick?: boolean;
    /** Id van de kaarttitel: zegt bij een knop over welke titel hij gaat. */
    titleId?: string;
    onchange: (patch: Partial<Item>) => void;
  }

  let { item, shape, quick = false, titleId, onchange }: Props = $props();

  let busy = $state(false);
  let error = $state('');

  const caps = $derived(session.capabilities);
  const playable = $derived(item.kind === 'movie' || item.kind === 'episode');
  const canPlay = $derived(
    caps?.playback_plan === true && playable && (item.versions?.length ?? 0) > 0
  );
  const canWatch = $derived(caps?.watch_state === true && playable);
  const canFavorite = $derived(caps?.favorites === true);
  const watched = $derived(!!item.user_state?.watched);
  const favorite = $derived(!!item.favorite);

  async function change(work: () => Promise<Partial<Item>>): Promise<void> {
    if (busy) return;
    busy = true;
    error = '';
    try {
      onchange(await work());
    } catch (err) {
      error = describeError(err);
    } finally {
      busy = false;
    }
  }

  function toggleWatched(): void {
    const next = !watched;
    void change(async () => ({
      user_state: await personalApi(session.client).setWatched(item.id, next, item.duration_ms ?? undefined)
    }));
  }

  function toggleFavorite(): void {
    const next = !favorite;
    void change(async () => {
      await personalApi(session.client).setFavorite(item.id, next);
      return { favorite: next };
    });
  }
</script>

{#if quick}
  <div class="acts acts--quick" class:acts--wide={shape === 'wide'}>
    {#if canPlay}
      <a
        class="act act--play"
        href={playerHref(item.id, watched ? 0 : item.user_state?.position_ms)}
        aria-label={t('card.play', { title: item.title })}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>
      </a>
    {/if}
    <div class="acts__row">
      <!-- aria-disabled en niet disabled: een knop die tijdens de aanvraag
           uitgeschakeld raakt, verliest de toetsenbordfocus. -->
      {#if canWatch}
        <button
          type="button"
          class="act"
          class:act--on={watched}
          aria-label={t(watched ? 'personal.markUnwatched' : 'personal.markWatched')}
          aria-describedby={titleId}
          aria-disabled={busy}
          onclick={toggleWatched}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </button>
      {/if}
      {#if canFavorite}
        <button
          type="button"
          class="act"
          class:act--on={favorite}
          aria-label={t(favorite ? 'personal.removeFavorite' : 'personal.addFavorite')}
          aria-describedby={titleId}
          aria-disabled={busy}
          onclick={toggleFavorite}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" fill={favorite ? 'currentColor' : 'none'} stroke="currentColor" stroke-width="2" stroke-linejoin="round" /></svg>
        </button>
      {/if}
      <CardMenu {item} {onchange} />
    </div>
    {#if error}<p class="acts__error" role="alert">{error}</p>{/if}
  </div>
{:else}
  <div class="acts acts--menu"><CardMenu {item} {onchange} /></div>
{/if}

<style>
  .acts {
    position: absolute;
    z-index: 2;
  }

  /* Alleen het menu: rechtsboven op het beeld. */
  .acts--menu {
    top: calc(var(--space-quarter) + 6px);
    right: 6px;
  }

  /* De laag ligt precies over het beeld: zelfde start, breedte en verhouding. */
  .acts--quick {
    top: var(--space-quarter);
    left: 0;
    right: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    aspect-ratio: var(--aspect-poster);
    border-radius: var(--radius-sm);
    background: color-mix(in srgb, var(--art-shade) 55%, transparent);
    /* De laag zelf vangt niets: een klik naast de knoppen is de kaartlink. */
    pointer-events: none;
  }

  .acts--wide {
    aspect-ratio: var(--aspect-episode);
  }

  /* Geen enkele actie voor dit item op deze server: dan ook geen lege laag. */
  .acts--quick:not(:has(:global(a), :global(button))) {
    display: none;
  }

  .acts__row {
    display: flex;
    gap: 8px;
  }

  .act,
  .acts :global(button.more) {
    position: relative;
    display: grid;
    place-items: center;
    flex: none;
    width: var(--touch-target);
    height: var(--touch-target);
    padding: 0;
    border: 1px solid color-mix(in srgb, var(--art-ink) 40%, transparent);
    border-radius: var(--radius-pill);
    background: color-mix(in srgb, var(--art-shade) 72%, transparent);
    color: var(--art-ink);
    cursor: pointer;
    pointer-events: auto;
  }

  .act svg,
  .acts :global(button.more svg) {
    width: 20px;
    height: 20px;
  }

  .act--play {
    width: 60px;
    height: 60px;
    border: 0;
    background: var(--art-ink);
    color: var(--art-shade);
  }

  .act--play svg {
    width: 26px;
    height: 26px;
  }

  /* Aan: gevuld, zodat de stand ook zonder het label te lezen is. */
  .act--on {
    background: var(--art-ink);
    color: var(--art-shade);
  }

  .act[aria-disabled='true'] {
    cursor: progress;
  }

  /* Over artwork is de ring altijd wit; --ink zou in light verdwijnen. */
  .act:focus-visible,
  .acts :global(button.more:focus-visible) {
    outline: var(--ring) solid var(--art-ink);
    outline-offset: 2px;
  }

  .acts__error {
    max-width: calc(100% - 16px);
    margin: 0;
    font-size: 11px;
    line-height: 1.3;
    text-align: center;
    color: var(--art-ink);
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    overflow: hidden;
  }

  /* Het losse menu tekent 32 met een raakvlak van 44. */
  .acts--menu :global(button.more) {
    width: 32px;
    height: 32px;
    border: 0;
    background: color-mix(in srgb, var(--art-shade) 70%, transparent);
  }

  .acts--menu :global(button.more svg) {
    width: 18px;
    height: 18px;
  }

  .acts--menu :global(button.more)::after {
    content: '';
    position: absolute;
    inset: -6px;
  }

  .acts--menu :global(button.more:focus-visible) {
    outline-offset: 1px;
  }

  /*
   * Onder 900 is een poster 110 breed: drie knoppen van 44 passen daar niet.
   * Drie van 30 met 6 ertussen wel.
   */
  @media (max-width: 899px) {
    .acts--quick {
      gap: 8px;
    }

    .acts__row {
      gap: 6px;
    }

    .acts--quick .act,
    .acts--quick :global(button.more) {
      width: 30px;
      height: 30px;
    }

    .acts--quick .act svg,
    .acts--quick :global(button.more svg) {
      width: 16px;
      height: 16px;
    }

    .acts--quick .act--play {
      width: 40px;
      height: 40px;
    }
  }

  @media (hover: hover) {
    .acts {
      opacity: 0;
      transition: opacity var(--dur-fast) var(--ease);
    }

    :global(.card:hover) > .acts,
    .acts--menu:focus-within,
    :global(.card:focus-within) > .acts--quick {
      opacity: 1;
    }

    /* Het beeld tilt 3 px op onder de muis; de laag gaat mee. */
    :global(.card:hover) > .acts--quick {
      top: calc(var(--space-quarter) - 3px);
    }

    .act:hover,
    .acts--quick :global(button.more:hover) {
      border-color: var(--art-ink);
    }
  }

  /*
   * Aanraakscherm: geen laag en geen losse knoppen, alleen het menu, in de
   * hoek waar geen teken staat (versies linksboven, gezien rechtsboven). Wie
   * daar met een toetsenbord door de kaart loopt, krijgt de volledige laag.
   */
  @media (hover: none) {
    :global(.card:not(:has(:focus-visible))) > .acts--quick {
      align-items: flex-end;
      justify-content: flex-end;
      padding: 0 6px 10px;
      background: none;
    }

    :global(.card:not(:has(:focus-visible))) > .acts--quick .act,
    :global(.card:not(:has(:focus-visible))) > .acts--quick .acts__error {
      display: none;
    }

    /* Het raakvlak blijft 44, ook waar de knop 30 tekent. */
    .acts--quick :global(button.more)::after {
      content: '';
      position: absolute;
      inset: -7px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .acts {
      transition: none;
    }

    :global(.card:hover) > .acts--quick {
      top: var(--space-quarter);
    }
  }
</style>
