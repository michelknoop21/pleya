<!--
  De hero bovenaan Home.

  De waas over het beeld draait mee met het thema, en dat is niet cosmetisch:
  artwork flipt niet met de modus, dus een zwarte veil onder bijna-zwarte
  lichte-modus-tekst is onleesbaar. `MonoTokens.artworkScrim` is daarom altijd
  de achtergrondkleur en de dekking verschilt per modus, waarbij licht harder
  en verder wast. Dezelfde regel staat in `artworkScrimAlpha`.

  Er staat geen afspeelknop. Afspelen is PS-4, en poort 3 en poort 4 staan nog
  open; een knop die naar niets leidt is erger dan geen knop.
-->
<script lang="ts">
  import Artwork from './Artwork.svelte';
  import type { Item } from '../api/types';
  import { formatDuration, itemSubtitle } from '../util/format';
  import { t } from '../i18n';

  interface Props {
    item: Item;
  }

  let { item }: Props = $props();

  const artworkId = $derived(item.artwork?.backdrop_id ?? item.artwork?.poster_id);
  const meta = $derived(
    [itemSubtitle(item), formatDuration(item.duration_ms)].filter(Boolean).join(' · ')
  );
</script>

<section class="hero" aria-label={t('home.recentlyAdded')}>
  <div class="hero__art">
    <Artwork artworkId={artworkId} alt="" shape="free" eager flat />
  </div>
  <div class="hero__scrim" aria-hidden="true"></div>
  <div class="hero__content">
    <h1 class="hero__title">{item.title}</h1>
    {#if meta}<p class="hero__meta t-body">{meta}</p>{/if}
    <a class="btn btn--secondary hero__action" href="/items/{item.id}">
      {t('home.heroAction')}
    </a>
  </div>
</section>

<style>
  .hero {
    position: relative;
    isolation: isolate;
    min-height: 46vw;
    max-height: 62dvh;
    display: flex;
    align-items: flex-end;
    overflow: hidden;
  }

  .hero__art {
    position: absolute;
    inset: 0;
    z-index: -2;
  }

  .hero__art :global(.artwork) {
    height: 100%;
  }

  /*
   * Twee verlopen: een van onderaf voor de tekst, een van links voor de
   * navigatie. Beide wassen met --scrim, dus met de achtergrondkleur van het
   * thema, en de dekkingen komen uit de tokens.
   */
  .hero__scrim {
    position: absolute;
    inset: 0;
    z-index: -1;
    background:
      linear-gradient(
        to top,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-strong) * 100%), transparent) 0%,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-mid) * 60%), transparent) 55%,
        transparent 100%
      ),
      linear-gradient(
        to right,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-strong) * 100%), transparent) 0%,
        transparent 62%
      );
  }

  .hero__content {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    padding: var(--space-2) var(--page-inset, var(--space)) var(--space-2);
    max-width: min(100%, 56ch);
    color: var(--on-artwork);
  }

  .hero__title {
    font-size: clamp(28px, 6vw, 57px);
    line-height: 1.05;
    font-weight: 700;
    letter-spacing: -0.5px;
  }

  .hero__meta {
    color: color-mix(in srgb, var(--text) calc(var(--on-artwork-ink) * 100%), transparent);
  }

  .hero__action {
    align-self: flex-start;
    margin-top: var(--space-half);
  }

  @media (min-width: 900px) {
    .hero {
      min-height: 420px;
    }
  }

  @media (min-width: 1600px) {
    .hero {
      min-height: 520px;
    }
  }
</style>
