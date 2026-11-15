<!--
  Een paneelkop met een stapnummer ervoor, voor Bibliotheek toevoegen: 1 soort,
  2 naam, 3 mappen. Het nummer is tekening; de stap zit al in de volgorde.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { n, children }: { n: number; children: Snippet } = $props();
</script>

<span class="num" aria-hidden="true">{n}</span>{@render children()}

<style>
  .num {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    margin-right: 10px;
    border-radius: var(--radius-pill);
    background: var(--fill);
    font-size: 13px;
    font-weight: 700;
    color: var(--ink);
    vertical-align: middle;
  }
</style>
