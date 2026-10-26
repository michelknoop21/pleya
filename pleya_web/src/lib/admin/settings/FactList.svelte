<!--
  Een lijst met feiten (`dl`), label links en waarde rechts, zoals "Luistert
  op" en "Gezien via" in 30 en "Versies" in 32. Onder 600 staat het label
  boven de waarde: een lange waarde (een DSN, een pad) breekt dan af in plaats
  van het scherm breder te maken.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children, label }: { children: Snippet; label?: string } = $props();
</script>

<dl class="facts" aria-label={label}>
  {@render children()}
</dl>

<style>
  .facts {
    display: grid;
    grid-template-columns: minmax(96px, 150px) minmax(0, 1fr);
    gap: 9px 16px;
    margin: 0;
    font-size: 14px;
  }

  .facts :global(dt) {
    color: var(--ink-3);
  }

  .facts :global(dd) {
    margin: 0;
    min-width: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .facts :global(.muted) {
    color: var(--ink-3);
  }

  /* Een tweede regel onder een waarde, zoals de naam van een variabele. */
  .facts :global(.sub) {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .facts :global(.mono) {
    font-family: var(--font-mono);
    font-size: 13px;
  }

  @media (max-width: 599px) {
    .facts {
      grid-template-columns: minmax(0, 1fr);
      gap: 2px;
    }

    .facts :global(dd) {
      margin-bottom: 8px;
    }
  }
</style>
