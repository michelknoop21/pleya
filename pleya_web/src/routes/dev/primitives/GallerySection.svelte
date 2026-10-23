<!--
  Eén blok in de galerij. Het id is het anker waar het screenshotscript per
  sectie op knipt, dus het is ook de bestandsnaam in docs/qa/s7-primitives/,
  en de index links springt ernaartoe (sections.ts houdt de lijst bij).

  De kop is een label van 11 px in kapitalen met een haarlijn erachter, zoals
  de tabelkoppen en de zijbalklabels in specimen v2: de sectienaam ordent, de
  primitieven eronder zijn het onderwerp.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    id: string;
    title: string;
    children: Snippet;
  }

  let { id, title, children }: Props = $props();
</script>

<section class="gs" {id} aria-labelledby="{id}-title">
  <h2 class="gs__title" id="{id}-title">{title}</h2>
  {@render children()}
</section>

<style>
  .gs {
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
    padding: var(--space-2) 0 var(--space-3);
    /* Onder 900 staat de index als strook bovenaan; een anker landt eronder. */
    scroll-margin-top: var(--gal-sticky, 0px);
  }

  .gs__title {
    display: flex;
    align-items: center;
    gap: var(--space);
    margin: 0;
    font-size: var(--text-caps-size);
    font-weight: 600;
    line-height: 1;
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: var(--ink-3);
  }

  .gs__title::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--hairline);
  }

  .gs :global(.gs__row) {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space);
    align-items: flex-start;
  }

  .gs :global(.gs__grid) {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr));
    gap: 14px;
    align-items: start;
  }

  /* Tegels in één rij zijn even hoog, ook als de ene een toelichting heeft. */
  .gs :global(.gs__grid--stretch) {
    align-items: stretch;
  }

  /* Meldingen staan in de mockups over de volle breedte, niet in een raster. */
  .gs :global(.gs__stack) {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .gs :global(.gs__caption) {
    margin: 0 0 var(--space-half);
    color: var(--ink-3);
    font-size: 12px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
</style>
