<!--
  Een kengetal (`.stat` in web.css, beheeroverzicht 20): klein label boven, de
  waarde groot eronder, een toelichting daaronder en rechtsboven een icoon.

  Label en waarde zijn een <dl>-paar, zodat een schermlezer "Opslag, 3,2 TB
  vrij" leest en niet twee losse zinnen. Het icoon is versiering en blijft
  buiten de toegankelijkheidsboom. De rij tegels zelf (vier kolommen, twee
  onder 1200) is lay-out van het scherm, niet van de tegel.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    label: string;
    value: string;
    sub?: string;
    icon?: Snippet;
  }

  let { label, value, sub, icon }: Props = $props();
</script>

<dl class="stat">
  {#if icon}
    <span class="stat__icon" aria-hidden="true">{@render icon()}</span>
  {/if}
  <dt class="stat__label">{label}</dt>
  <dd class="stat__value">{value}</dd>
  {#if sub}
    <dd class="stat__sub">{sub}</dd>
  {/if}
</dl>

<style>
  .stat {
    position: relative;
    min-width: 0;
    min-height: 96px;
    margin: 0;
    padding: 16px 18px;
    border-radius: var(--radius-card);
    background: var(--surface);
  }

  .stat__icon {
    position: absolute;
    top: 16px;
    right: 16px;
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    color: var(--ink-3);
  }

  .stat__icon :global(svg) {
    width: 100%;
    height: 100%;
  }

  .stat__label {
    /* Ruimte voor het icoon, zodat een lang label er niet onder loopt. */
    padding-right: 28px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .stat__value {
    margin: 6px 0 0;
    font-size: 26px;
    font-weight: 700;
    line-height: 1.2;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .stat__sub {
    margin: 4px 0 0;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-2);
  }
</style>
