<!--
  Eén item in een raster of een rij.

  De maatvoering volgt `MediaCardGridLayout`: de poster houdt zijn eigen
  verhouding en het bijschrift staat eronder, buiten de afbeelding. Titel 13px
  in 600, metaregel 11px, regelhoogte 1.1 — dezelfde waarden als in de app.

  Hover bestaat alleen achter `@media (hover: hover)`. Het TV-focusmodel uit
  `lib/focus/` wordt niet nagebouwd: een browservenster is geen televisie.
-->
<script lang="ts">
  import Artwork from './Artwork.svelte';
  import type { Item } from '../api/types';
  import { artworkAspect, itemSubtitle } from '../util/format';

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
  }

  let { item, eager = false, shape: shapeOverride }: Props = $props();

  const shape = $derived(shapeOverride ?? artworkAspect(item.kind));
  const artworkId = $derived(
    shape === 'wide' ? (item.artwork?.backdrop_id ?? item.artwork?.poster_id) : item.artwork?.poster_id
  );
  const subtitle = $derived(itemSubtitle(item));
</script>

<a class="card" href="/items/{item.id}" data-kind={item.kind}>
  <div class="card__art">
    <Artwork artworkId={artworkId} alt="" {shape} {eager} />
  </div>
  <div class="card__caption">
    <span class="card__title">{item.title}</span>
    <span class="card__meta">{subtitle ?? ''}</span>
  </div>
</a>

<style>
  .card {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
    padding: var(--space-quarter) 0;
    border-radius: var(--radius-sm);
  }

  .card__art {
    transition:
      transform var(--dur-fast) var(--ease),
      box-shadow var(--dur-fast) var(--ease);
    border-radius: var(--radius-sm);
    overflow: hidden;
  }

  .card__caption {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .card__title {
    font-size: var(--text-card-title-size);
    line-height: var(--text-card-line);
    font-weight: 600;
    color: var(--text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .card__meta {
    font-size: var(--text-card-sub-size);
    line-height: var(--text-card-line);
    color: var(--text-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    /* Altijd gereserveerd, ook leeg: anders krijgt een rij kaarten met en
       zonder metaregel twee verschillende hoogtes. */
    min-height: calc(var(--text-card-sub-size) * var(--text-card-line));
  }

  .card:focus-visible {
    outline-offset: 4px;
  }

  @media (hover: hover) {
    .card:hover .card__art {
      transform: scale(1.04);
      box-shadow: 0 8px 24px rgb(0 0 0 / 0.35);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .card__art {
      transition: none;
    }
    .card:hover .card__art {
      transform: none;
    }
  }
</style>
