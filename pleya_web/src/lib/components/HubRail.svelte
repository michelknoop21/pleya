<!--
  Een horizontale rij zoals beeld 01 en specimen v3 hem tekenen: kop met de
  titel links en "View all" rechts, daaronder een spoor dat tot de rand van
  het venster doorloopt. De eerste kaart lijnt uit op --inset, de rest loopt
  onder de rand door en een verloop rechts laat zien dat er meer is.

  De rail wordt zonder paginapadding geplaatst (Home zet hem direct onder de
  hero), dus de bleed is de breedte van de container zelf en de inzet zit in
  de padding van kop en spoor. Wie hem in een ingesprongen container zet, heft
  die inzet daar op met een negatieve marge, zoals de galerij doet.

  Het schuiven is browser-eigen (`overflow-x`, `scroll-snap`) en niet
  nagebouwd. Op een aanraakscherm veegt de gebruiker; op een toetsenbord loopt
  de tabvolgorde door de kaarten en schuift de browser zelf mee. De pijlen zijn
  een extra voor de muis en bestaan alleen vanaf 900 met hover.

  Een rij zonder inhoud tekent zichzelf niet. Een lege rij met een kop erboven
  zou beloven dat daar ooit iets staat zonder dat de server dat zegt.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import MediaCard from './MediaCard.svelte';
  import type { Item } from '../api/types';
  import { t } from '../i18n';
  import { RailScroll } from './railScroll.svelte';

  interface Props {
    title: string;
    items: Item[];
    href?: string | undefined;
    /** Tekst van de doorkliklink; standaard "View all". */
    viewAllLabel?: string;
    /**
     * De vorm van de hele rij. Blijft hij leeg, dan volgt hij de inhoud: alleen
     * afleveringen is wide, de rest poster. Een aanroeper die afleveringen als
     * serieposter toont, zet hier `poster`, anders krijgt zijn kaart een
     * brede cel.
     */
    shape?: 'poster' | 'wide';
    /**
     * Tekent één cel. Zo geeft een aanroeper zijn eigen MediaCard-props mee
     * (bijvoorbeeld `isNew`); zonder snippet tekent de rail de standaardkaart.
     * Het derde argument is de vorm van de rij, voor de `shape` van de kaart.
     */
    card?: Snippet<[Item, number, 'poster' | 'wide']>;
  }

  let { title, items, href, viewAllLabel, shape: shapeOverride, card }: Props = $props();

  const uid = $props.id();
  const headingId = `${uid}-title`;
  const trackId = `${uid}-track`;

  // Dezelfde regel als in MediaGrid: één vorm voor de hele rij, anders staan er
  // twee hoogtes naast elkaar.
  const shape = $derived<'poster' | 'wide'>(
    shapeOverride ??
      (items.length > 0 && items.every((item) => item.kind === 'episode') ? 'wide' : 'poster')
  );

  let track = $state<HTMLUListElement | null>(null);
  const rail = new RailScroll();

  $effect(() => {
    if (!track) return;
    return rail.attach(track);
  });

  // De ResizeObserver ziet alleen het spoor zelf, en dat wordt niet breder
  // als er kaarten bijkomen: alleen de schuifbreedte groeit. Daarom opnieuw
  // meten zodra het aantal verandert, anders blijven fade en pijl uit.
  $effect(() => {
    void items.length;
    rail.measure();
  });
</script>

{#if items.length > 0}
  <section class="rail" class:rail--wide={shape === 'wide'}>
    <div class="rail__head">
      <h2 class="rail__title" id={headingId}>{title}</h2>
      {#if href}
        <!-- "View all" alleen is op een pagina met vijf rijen vijf keer
             hetzelfde; aria-describedby koppelt hem aan zijn rij. -->
        <a class="rail__all" {href} aria-describedby={headingId}>
          {viewAllLabel ?? t('rail.viewAll')}
          <svg class="rail__chev" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M9 6l6 6-6 6" />
          </svg>
        </a>
      {/if}
    </div>

    <div class="rail__wrap">
      <!--
        De pijlen staan in de DOM vóór het spoor, zodat een toetsenbord er na
        de kop langskomt en niet pas na de laatste kaart. Uitgeschakeld via
        aria-disabled en niet via `disabled`: een knop die onder de focus
        uitgeschakeld raakt (aan het eind van de rij) verliest anders de
        focus aan de body.
      -->
      <button
        type="button"
        class="rail__arrow rail__arrow--left"
        aria-label={t('rail.scrollLeft')}
        aria-controls={trackId}
        aria-disabled={rail.atStart}
        onclick={() => rail.scrollBy(-1)}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
      </button>
      <button
        type="button"
        class="rail__arrow rail__arrow--right"
        aria-label={t('rail.scrollRight')}
        aria-controls={trackId}
        aria-disabled={rail.atEnd}
        onclick={() => rail.scrollBy(1)}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
      </button>

      <!--
        Normaal loopt de tab door de kaartlinks en schuift de browser mee. Een
        snippet zonder link of knop laat het toetsenbord anders zonder weg
        om te schuiven; alleen dan krijgt het spoor zelf de tab (een
        schuifvlak met focus schuift met de pijltoetsen). Met focusbare
        kaarten zou dat een overbodige extra tabstop zijn. Zelfde patroon als
        het schuifvlak van DataTable, vandaar de ignore.
      -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <ul
        class="rail__track"
        id={trackId}
        bind:this={track}
        aria-labelledby={headingId}
        tabindex={rail.hasFocusable ? undefined : 0}
        onscroll={rail.schedule}
      >
        {#each items as item, index (item.id)}
          <li class="rail__cell">
            {#if card}
              {@render card(item, index, shape)}
            {:else}
              <MediaCard {item} {shape} eager={index < 8} />
            {/if}
          </li>
        {/each}
      </ul>

      <div class="rail__fade" class:rail__fade--on={!rail.atEnd} aria-hidden="true"></div>
    </div>
  </section>
{/if}

<style>
  /*
   * Celbreedte en beeldhoogte uit --poster-w: een poster is 2:3, een
   * wide-kaart 1,78 keer zo breed en 16:9 (web.css .card.wide). De hoogte is
   * er voor de verticale plek van de pijlen.
   */
  .rail {
    --rail-cell: var(--poster-w);
    --rail-art-h: calc(var(--poster-w) * 1.5);
  }

  .rail--wide {
    --rail-cell: calc(var(--poster-w) * 1.78);
    --rail-art-h: calc(var(--poster-w) * 1.78 * 9 / 16);
  }

  /* Kop, web.css .section-h: 20/700, 18 onder 900; link 14/500 in --ink-2. */
  .rail__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 4px;
    padding-inline: var(--inset);
  }

  .rail__title {
    display: flex;
    align-items: center;
    min-height: var(--touch-target);
    margin: 0;
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .rail__all {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    gap: 4px;
    min-height: var(--touch-target);
    font-size: 14px;
    font-weight: 500;
    color: var(--ink-2);
    text-decoration: none;
    white-space: nowrap;
  }

  @media (hover: hover) {
    .rail__all:hover {
      color: var(--ink);
    }
  }

  .rail__chev {
    width: 14px;
    height: 14px;
  }

  .rail__chev path,
  .rail__arrow path {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  @media (max-width: 899px) {
    .rail__title {
      font-size: 18px;
    }

    .rail__all {
      font-size: 13px;
    }
  }

  .rail__wrap {
    position: relative;
  }

  /*
   * Het spoor: 6 boven voor de lift en de ring van een kaart onder de muis,
   * 4 onder. Geen zichtbare schuifbalk, zoals het specimen; schuiven gaat met
   * vegen, de pijlen, het wiel of de tabtoets.
   */
  .rail__track {
    display: flex;
    gap: var(--rail-gap);
    margin: 0;
    padding: 6px var(--inset) 4px;
    list-style: none;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
    scroll-snap-type: x proximity;
    /*
     * Zonder scroll-padding lijnt scroll-snap-align: start de eerste kaart uit
     * op de rand van het schuifvlak en niet op de padding, waarna de rij bij
     * het openen al verschoven staat terwijl de kop netjes inspringt.
     */
    scroll-padding-inline: var(--inset);
  }

  .rail__track::-webkit-scrollbar {
    display: none;
  }

  /* SkeletonPage leest dezelfde tokens, zodat skelet en rail even breed zijn. */
  .rail__cell {
    flex: 0 0 var(--rail-cell);
    width: var(--rail-cell);
    scroll-snap-align: start;
  }

  .rail__fade {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    width: 90px;
    background: linear-gradient(90deg, transparent, var(--bg));
    pointer-events: none;
    opacity: 0;
    transition: opacity var(--dur-fast) var(--ease);
  }

  .rail__fade--on {
    opacity: 1;
  }

  /*
   * Pijlen, specimen v3: rond, 44, op de helft van het beeld en half over de
   * inzet. De achtergrond is --bg op 78 procent; in dark is dat precies de
   * rgba(20, 20, 20, .78) van het specimen, en in light blijft hij licht onder
   * een donkere pijl.
   */
  .rail__arrow {
    position: absolute;
    /* Het beeld begint onder de 6 van het spoor plus de 3 van de kaart. */
    top: calc(6px + var(--space-quarter) + var(--rail-art-h) / 2 - var(--touch-target) / 2);
    z-index: 2;
    display: none;
    place-items: center;
    width: var(--touch-target);
    height: var(--touch-target);
    padding: 0;
    border: 1px solid var(--hairline-strong);
    border-radius: var(--radius-pill);
    background: color-mix(in srgb, var(--bg) 78%, transparent);
    color: var(--ink);
    opacity: 0;
    pointer-events: none;
    transition: opacity var(--dur-fast) var(--ease);
  }

  .rail__arrow svg {
    width: 20px;
    height: 20px;
  }

  .rail__arrow--left {
    left: calc(var(--inset) - var(--touch-target) / 2);
  }

  .rail__arrow--right {
    right: calc(var(--inset) - var(--touch-target) / 2);
  }

  .rail__arrow[aria-disabled='true'] {
    cursor: default;
  }

  @media (hover: hover) and (min-width: 900px) {
    .rail__arrow {
      display: grid;
    }

    /* Een pijl die nergens heen kan blijft zichtbaar maar gedimd, zoals in
       het specimen. */
    .rail:hover .rail__arrow,
    .rail:focus-within .rail__arrow {
      opacity: 1;
      pointer-events: auto;
    }

    .rail:hover .rail__arrow[aria-disabled='true'],
    .rail:focus-within .rail__arrow[aria-disabled='true'] {
      opacity: 0.35;
    }

    /* De dekking geldt ook voor de outline; een gedimde pijl met focus zou
       een ring van 2,3:1 geven. Met focus staat de pijl dus altijd vol. */
    .rail:focus-within .rail__arrow:focus-visible {
      opacity: 1;
    }

    .rail__arrow[aria-disabled='false']:hover {
      background: color-mix(in srgb, var(--bg) 92%, transparent);
    }
  }
</style>
