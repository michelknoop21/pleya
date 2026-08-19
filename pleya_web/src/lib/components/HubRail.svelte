<!--
  Een horizontale rij, zoals `hub_section.dart` er een tekent: kop links, de
  kaarten daaronder in één schuivende rij.

  Het schuiven is browser-eigen (`overflow-x`, `scroll-snap`) en niet
  nagebouwd. De pijlknoppen bestaan alleen waar een aanwijzer is; op een
  aanraakscherm veegt de gebruiker, en op een toetsenbord loopt de tabvolgorde
  door de kaarten heen, waarbij de browser zelf meeschuift.

  Een rij zonder inhoud tekent zichzelf niet. `continue_watching` en `next_up`
  leveren vandaag een lege lijst omdat er nog geen kijkstatus is; een lege rij
  met een kop erboven zou beloven dat daar ooit iets staat zonder dat de
  server dat zegt.
-->
<script lang="ts">
  import MediaCard from './MediaCard.svelte';
  import type { Item } from '../api/types';

  interface Props {
    title: string;
    items: Item[];
    href?: string | undefined;
    viewAllLabel?: string;
  }

  let { title, items, href, viewAllLabel }: Props = $props();

  // Dezelfde regel als in MediaGrid: één vorm voor de hele rij, anders staan er
  // twee hoogtes naast elkaar.
  const shape = $derived(
    items.length > 0 && items.every((item) => item.kind === 'episode') ? 'wide' : 'poster'
  );

  let track = $state<HTMLUListElement | null>(null);

  function scrollBy(direction: -1 | 1): void {
    if (!track) return;
    track.scrollBy({ left: direction * track.clientWidth * 0.8, behavior: 'smooth' });
  }
</script>

{#if items.length > 0}
  <section class="rail">
    <div class="rail__header">
      {#if href}
        <a class="rail__title t-title-lg" {href}>
          {title}
          {#if viewAllLabel}<span class="rail__more">{viewAllLabel}</span>{/if}
          <span class="rail__chevron" aria-hidden="true">›</span>
        </a>
      {:else}
        <h2 class="rail__title t-title-lg">{title}</h2>
      {/if}

      <div class="rail__controls">
        <button type="button" class="rail__arrow" onclick={() => scrollBy(-1)} aria-label="Scroll left">
          ‹
        </button>
        <button type="button" class="rail__arrow" onclick={() => scrollBy(1)} aria-label="Scroll right">
          ›
        </button>
      </div>
    </div>

    <ul class="rail__track scroll-x" bind:this={track} aria-label={title}>
      {#each items as item, index (item.id)}
        <li class="rail__cell" data-wide={shape === 'wide' ? 'true' : undefined}>
          <MediaCard {item} {shape} eager={index < 8} />
        </li>
      {/each}
    </ul>
  </section>
{/if}

<style>
  .rail {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
  }

  .rail__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space);
    padding-inline: var(--page-inset, var(--space));
  }

  .rail__title {
    color: var(--text);
    display: inline-flex;
    align-items: center;
    gap: var(--space-half);
    min-height: var(--touch-target);
  }

  .rail__more {
    font-size: var(--text-small-size);
    font-weight: 600;
    color: var(--text-muted);
    opacity: 0;
    transition: opacity var(--dur-fast) var(--ease);
  }

  .rail__chevron {
    font-size: 1.2em;
    line-height: 1;
    color: var(--text-muted);
  }

  @media (hover: hover) {
    .rail__title:hover .rail__more {
      opacity: 1;
    }
  }

  .rail__title:focus-visible .rail__more {
    opacity: 1;
  }

  .rail__controls {
    display: none;
    gap: var(--space-quarter);
  }

  @media (hover: hover) and (min-width: 900px) {
    .rail__controls {
      display: flex;
    }
  }

  .rail__arrow {
    width: var(--touch-target);
    height: var(--touch-target);
    border-radius: var(--radius-pill);
    background: color-mix(in srgb, var(--text) 8%, transparent);
    color: var(--text);
    font-size: 20px;
    line-height: 1;
    transition: background var(--dur-fast) var(--ease);
  }

  @media (hover: hover) {
    .rail__arrow:hover {
      background: color-mix(in srgb, var(--text) 16%, transparent);
    }
  }

  .rail__track {
    display: flex;
    gap: var(--space);
    padding-inline: var(--page-inset, var(--space));
    padding-block: var(--space-quarter);
    scroll-snap-type: x proximity;
    /*
     * Zonder scroll-padding lijnt scroll-snap-align: start de eerste kaart uit
     * op de rand van het schuifvlak en niet op de padding, waarna de rij bij
     * het openen al 16 px verschoven staat en de eerste poster de zijkant
     * raakt terwijl de kop netjes inspringt.
     */
    scroll-padding-inline: var(--page-inset, var(--space));
    scrollbar-width: thin;
  }

  .rail__cell {
    flex: 0 0 auto;
    width: 132px;
    scroll-snap-align: start;
  }

  .rail__cell[data-wide='true'] {
    width: 236px;
  }

  @media (min-width: 900px) {
    .rail__cell {
      width: 150px;
    }
    .rail__cell[data-wide='true'] {
      width: 268px;
    }
  }

  @media (min-width: 1200px) {
    .rail__cell {
      width: 168px;
    }
    .rail__cell[data-wide='true'] {
      width: 300px;
    }
  }
</style>
