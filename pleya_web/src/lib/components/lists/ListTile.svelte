<!--
  Eén lijst in het overzicht van scherm 17: een vierluik uit de eerste vier
  posters met titel en onderregel. Minder dan vier posters laat het vlak van het
  paneel zien; het is een plaatje van de inhoud, dus alt blijft leeg en de titel
  draagt de linknaam.
-->
<script lang="ts">
  import Artwork from '../Artwork.svelte';

  let { href, title, meta, artwork }: { href: string; title: string; meta: string; artwork: string[] } = $props();

  const cells = $derived(Array.from({ length: 4 }, (_, index) => artwork[index] ?? null));
</script>

<a class="tile" {href}>
  <span class="tile__art" aria-hidden="true">
    {#each cells as artworkId, index (index)}
      <span class="tile__cell">
        {#if artworkId}<Artwork {artworkId} alt="" shape="poster" flat />{/if}
      </span>
    {/each}
  </span>
  <span class="tile__title">{title}</span>
  <span class="tile__meta">{meta}</span>
</a>

<style>
  .tile {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    color: inherit;
    text-decoration: none;
  }

  .tile__art {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px;
    margin-bottom: 6px;
    overflow: hidden;
    border-radius: var(--radius-card);
    background: var(--panel);
    box-shadow: inset 0 0 0 1px var(--hairline);
    transition: transform var(--dur-normal) var(--ease);
  }

  .tile__cell {
    display: block;
    min-width: 0;
    aspect-ratio: var(--aspect-poster);
    overflow: hidden;
  }

  .tile__title,
  .tile__meta {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .tile__title {
    font-size: var(--text-card-title-size);
    font-weight: 500;
    color: var(--ink);
  }

  .tile__meta {
    font-size: var(--text-card-sub-size);
    color: var(--ink-3);
  }

  @media (hover: hover) {
    .tile:hover .tile__art {
      transform: translateY(-3px);
    }
  }

  .tile:focus-visible {
    outline: none;
  }

  .tile:focus-visible .tile__art {
    box-shadow:
      0 0 0 3px var(--bg),
      0 0 0 calc(3px + var(--ring)) var(--ink);
  }

  @media (forced-colors: active) {
    .tile:focus-visible .tile__art {
      outline: var(--ring) solid CanvasText;
      outline-offset: 3px;
    }
  }
</style>
