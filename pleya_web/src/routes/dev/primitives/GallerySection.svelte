<!--
  Eén blok in de galerij. Het id is het anker waar het screenshotscript per
  sectie op knipt, dus het is ook de bestandsnaam in docs/qa/s7-primitives/.
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
  <h2 class="gs__title t-title-lg" id="{id}-title">{title}</h2>
  {@render children()}
</section>

<style>
  .gs {
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
    padding: var(--space-2) var(--inset);
    border-top: 1px solid var(--fill);
  }

  .gs__title {
    margin: 0;
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
    gap: var(--space-1-5);
    align-items: start;
  }

  /* Meldingen staan in de mockups over de volle breedte, niet in een raster. */
  .gs :global(.gs__stack) {
    display: flex;
    flex-direction: column;
    gap: var(--space);
  }

  .gs :global(.gs__caption) {
    margin: 0 0 var(--space-half);
    color: var(--ink-3);
    font-size: 12px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
</style>
