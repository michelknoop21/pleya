<!--
  Eén item in een raster of een rij, met de staten van northstar-scherm 16:
  rust, hover, toetsenbordfocus, voortgang, gezien, nieuw, versies, aflevering
  in Verder kijken, volgende aflevering (wide) en geen artwork. Maten uit
  web.css (.card en verwanten) zoals specimen v3 ze toont.

  De kaart is een div; de link dekt beeld en bijschrift, en de acties liggen
  als zuster boven het beeld. Zo staat er nooit een knop in een <a>, en blijft
  de rest van het beeld gewoon de link.

  De kaart vult de breedte van zijn cel. Hoe breed die is (poster, of 1,78
  keer zo breed voor wide) bepaalt het raster of de rij eromheen.

  Hover bestaat alleen achter `@media (hover: hover)`. De northstar tilt de
  kaart 3 px op en vergroot hem niet; de oude schaal van 1,04 is weg.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Artwork from './Artwork.svelte';
  import MediaCardBadges from './MediaCardBadges.svelte';
  import type { Item } from '../api/types';
  import {
    artworkAspect,
    cardArtworkId,
    cardSubtitle,
    isWatched,
    itemProgress
  } from '../util/format';

  interface Props {
    item: Item;
    /** Het beeld meteen laden, voor kaarten die altijd in beeld staan. */
    eager?: boolean;
    /**
     * De vorm van het beeld. Blijft hij leeg, dan volgt hij de soort: een
     * aflevering 16:9, de rest een poster. Een raster geeft hem expliciet mee,
     * zodat elke rij één hoogte heeft.
     */
    shape?: 'poster' | 'wide';
    /** De aanroeper bepaalt wat nieuw is sinds het laatste bezoek (S8). */
    isNew?: boolean;
    /**
     * Overschrijft het afgeleide beeld, bijvoorbeeld de serieposter bij een
     * aflevering in Verder kijken. `null` betekent uitdrukkelijk geen beeld.
     */
    artworkId?: string | null;
    /** Overschrijft de onderregel, bijvoorbeeld "S2 · E3 · 31m left". */
    subtitle?: string;
    /** Knoppen in de hover-overlay. Zonder snippet is er geen overlay. */
    actions?: Snippet;
  }

  let {
    item,
    eager = false,
    shape: shapeOverride,
    isNew = false,
    artworkId: artworkOverride,
    subtitle: subtitleOverride,
    actions
  }: Props = $props();

  // De linknaam begint bij de titel; de tekens op het beeld zijn beschrijving.
  const uid = $props.id();
  const shape = $derived(shapeOverride ?? artworkAspect(item.kind));
  const artworkId = $derived(
    artworkOverride !== undefined ? artworkOverride : cardArtworkId(item, shape)
  );
  const watched = $derived(isWatched(item));
  const progress = $derived(itemProgress(item));
  const subtitle = $derived(subtitleOverride ?? cardSubtitle(item));
</script>

<div class="card" data-kind={item.kind} data-shape={shape}>
  <a
    class="card__link"
    href="/items/{item.id}"
    aria-labelledby="{uid}-title {uid}-meta"
    aria-describedby="{uid}-badges"
  >
    <div class="card__art">
      <Artwork {artworkId} alt="" {shape} {eager}>
        {#snippet fallback()}
          <!--
            Titel en jaar als gegenereerde inhoud: ze staan al in het bijschrift
            eronder, dus dit vlak is beeld en geen tweede kopie van de tekst
            (geen dubbele linknaam, geen dubbele treffer bij zoeken in de pagina).
          -->
          <div
            class="card__none"
            aria-hidden="true"
            data-title={item.title}
            data-year={item.year ?? ''}
          ></div>
        {/snippet}
      </Artwork>
      <MediaCardBadges
        id="{uid}-badges"
        versions={item.versions?.length ?? 0}
        {watched}
        {isNew}
        progress={progress?.fraction ?? null}
      />
    </div>
    <div class="card__caption">
      <span class="card__title" id="{uid}-title">{item.title}</span>
      <span class="card__meta" id="{uid}-meta">{subtitle ?? ''}</span>
    </div>
  </a>
  {#if actions}
    <div class="card__over" class:card__over--wide={shape === 'wide'}>
      <div class="card__actions">{@render actions()}</div>
    </div>
  {/if}
</div>

<style>
  .card {
    position: relative;
    display: flex;
    flex-direction: column;
    min-width: 0;
    padding: var(--space-quarter) 0;
  }

  .card__link {
    display: flex;
    flex-direction: column;
    gap: var(--card-caption-gap);
    color: inherit;
  }

  /* De ring hoort om het beeld, niet om beeld plus bijschrift. */
  .card__link:focus-visible {
    outline: none;
  }

  .card__art {
    position: relative;
    border-radius: var(--radius-sm);
    overflow: hidden;
    transition:
      transform var(--dur-normal) var(--ease),
      box-shadow var(--dur-normal) var(--ease);
  }

  .card__caption {
    display: flex;
    flex-direction: column;
    gap: var(--card-caption-line-gap);
    min-width: 0;
  }

  .card__title,
  .card__meta {
    line-height: var(--text-card-line);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .card__title {
    font-size: var(--text-card-title-size);
    font-weight: 500;
    color: var(--ink);
  }

  .card__meta {
    font-size: var(--text-card-sub-size);
    color: var(--ink-3);
    /* Altijd gereserveerd, ook leeg: anders krijgt een rij kaarten met en
       zonder metaregel twee verschillende hoogtes. */
    min-height: calc(var(--text-card-sub-size) * var(--text-card-line));
  }

  /* Geen artwork: titel en jaar op het paneel, met de haarlijn uit v2. */
  .card__none {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    height: 100%;
    padding: var(--space);
    background: var(--panel);
    box-shadow: inset 0 0 0 1px var(--hairline);
    border-radius: inherit;
    text-align: center;
  }

  .card__none::before {
    content: attr(data-title);
    font-size: 15px;
    font-weight: 700;
    line-height: 1.25;
    color: var(--ink);
  }

  .card__none::after {
    content: attr(data-year);
    font-size: 12px;
    color: var(--ink-3);
  }

  /*
   * Toetsenbordfocus: ring in inkt op een gap van 3 px in de paginakleur,
   * zonder lift. De gap houdt de ring los van een licht beeld.
   */
  .card__link:focus-visible .card__art {
    box-shadow:
      0 0 0 3px var(--bg),
      0 0 0 calc(3px + var(--ring)) var(--ink);
  }

  /* Forced colors gooit box-shadow weg; zonder outline verdwijnt de ring. */
  @media (forced-colors: active) {
    .card__link:focus-visible .card__art {
      outline: var(--ring) solid CanvasText;
      outline-offset: 3px;
    }
  }

  /* De overlay ligt precies over het beeld: zelfde start, breedte en verhouding. */
  .card__over {
    position: absolute;
    top: var(--space-quarter);
    left: 0;
    right: 0;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    aspect-ratio: var(--aspect-poster);
    padding-bottom: 12px;
    border-radius: var(--radius-sm);
    background: linear-gradient(
      180deg,
      transparent 40%,
      color-mix(in srgb, var(--art-shade) 70%, transparent)
    );
    opacity: 0;
    /* Het verloop zelf vangt niets: een klik naast de knoppen is de link. */
    pointer-events: none;
    transition:
      opacity var(--dur-fast) var(--ease),
      transform var(--dur-normal) var(--ease);
  }

  .card__over--wide {
    aspect-ratio: var(--aspect-episode);
  }

  /* Onzichtbaar betekent ook onklikbaar, anders tikt een touchscherm erop. */
  .card__actions {
    display: flex;
    gap: 8px;
    pointer-events: none;
  }

  /* Wie naar de knoppen tabt ziet ze verschijnen; ook zonder muis bereikbaar. */
  .card:focus-within .card__over {
    opacity: 1;
  }

  .card:focus-within .card__actions {
    pointer-events: auto;
  }

  .card__actions :global(.card-action) {
    position: relative;
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    padding: 0;
    border-radius: var(--radius-pill);
    border: 1px solid color-mix(in srgb, var(--art-ink) 50%, transparent);
    background: color-mix(in srgb, var(--art-shade) 55%, transparent);
    color: var(--art-ink);
    cursor: pointer;
  }

  .card__actions :global(.card-action--primary) {
    width: 40px;
    height: 40px;
    border: 0;
    background: var(--art-ink);
    color: var(--art-shade);
  }

  .card__actions :global(.card-action svg) {
    width: 16px;
    height: 16px;
  }

  /* Over artwork is de ring altijd wit; --ink zou in light verdwijnen. */
  .card__actions :global(.card-action:focus-visible) {
    outline-color: var(--art-ink);
    border-radius: var(--radius-pill);
  }

  /* Raakvlak van 44 px rond een knop van 34. */
  .card__actions :global(.card-action::after) {
    content: '';
    position: absolute;
    inset: -5px;
  }

  /*
   * Onder 900 is de kaart 110 breed: 40 + 34 + 34 plus tussenruimte past daar
   * niet. Specimen v3: knoppen van 34 en 30, en geen vergroot raakvlak, want
   * dat zou over de buurknop vallen.
   */
  @media (max-width: 899px) {
    .card__none::before {
      font-size: 13px;
    }
    .card__none::after {
      font-size: 11px;
    }
    .card__over {
      padding-bottom: 8px;
    }
    .card__actions {
      gap: 6px;
    }
    .card__actions :global(.card-action) {
      width: 30px;
      height: 30px;
    }
    .card__actions :global(.card-action--primary) {
      width: 34px;
      height: 34px;
    }
    .card__actions :global(.card-action::after) {
      content: none;
    }
  }

  @media (hover: hover) {
    .card:hover .card__art {
      transform: translateY(-3px);
      box-shadow:
        0 0 0 var(--ring) var(--ink),
        0 18px 40px color-mix(in srgb, var(--art-shade) 55%, transparent);
    }

    .card:hover .card__title {
      font-weight: 700;
    }

    .card:hover .card__over {
      opacity: 1;
      transform: translateY(-3px);
    }

    .card:hover .card__actions {
      pointer-events: auto;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .card__art,
    .card__over {
      transition: none;
    }
    .card:hover .card__art,
    .card:hover .card__over {
      transform: none;
    }
  }
</style>
