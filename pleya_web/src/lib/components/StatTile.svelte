<!--
  Een kengetal (`.stat` in web.css, beheeroverzicht 20): klein label boven, de
  waarde groot eronder, een toelichting daaronder en rechtsboven een icoon.
  Designsysteem v2: de tegel is een paneel, de waarde 32/750 in tabulaire
  cijfers, een eenheid (`unit`) staat er klein en grijs achter, en `spark`
  tekent rechtsonder een verloop zonder dat de tegel hoger wordt.

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
    /** Eenheid achter de waarde, kleiner en grijs: "TB vrij", "%". */
    unit?: string;
    icon?: Snippet;
    /** Versiering rechtsonder, zoals een sparkline; aria-hidden. */
    spark?: Snippet;
  }

  let { label, value, sub, unit, icon, spark }: Props = $props();
</script>

<dl class="stat">
  {#if icon}
    <span class="stat__icon" aria-hidden="true">{@render icon()}</span>
  {/if}
  <dt class="stat__label">{label}</dt>
  <dd class="stat__value">
    <!-- De spatie staat buiten de span, anders snoeit Svelte hem en leest een
         schermlezer "3,2TB vrij". -->
    {value}{#if unit}{' '}<span class="stat__unit">{unit}</span>{/if}
  </dd>
  {#if sub}
    <dd class="stat__sub">{sub}</dd>
  {/if}
  {#if spark}
    <span class="stat__spark" aria-hidden="true">{@render spark()}</span>
  {/if}
</dl>

<style>
  .stat {
    position: relative;
    min-width: 0;
    min-height: 96px;
    margin: 0;
    padding: 16px 18px;
    overflow: hidden;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
    box-shadow: var(--ring-shadow);
  }

  .stat__icon {
    position: absolute;
    top: 16px;
    right: 18px;
    display: grid;
    place-items: center;
    width: 18px;
    height: 18px;
    color: var(--ink-3);
  }

  .stat__icon :global(svg) {
    width: 100%;
    height: 100%;
  }

  .stat__label {
    /* Ruimte voor het icoon, zodat een lang label er niet onder loopt. */
    padding-right: 28px;
    font-size: 13px;
    font-weight: 500;
    color: var(--ink-3);
  }

  .stat__value {
    margin: 14px 0 0;
    font-size: var(--text-value-size);
    font-weight: 750;
    line-height: 1;
    letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums;
    color: var(--ink);
  }

  .stat__unit {
    font-size: 15px;
    font-weight: 600;
    letter-spacing: 0;
    color: var(--ink-3);
  }

  .stat__sub {
    position: relative;
    z-index: 1;
    margin: 8px 0 0;
    font-size: 12.5px;
    line-height: 1.4;
    font-variant-numeric: tabular-nums;
    color: var(--ink-3);
  }

  /* Het verloop vult de rechteronderhoek en schuift onder de toelichting door. */
  .stat__spark {
    position: absolute;
    right: 0;
    bottom: 0;
    width: 46%;
    height: 46px;
    color: var(--ok);
    pointer-events: none;
  }

  .stat__spark :global(svg) {
    display: block;
    width: 100%;
    height: 100%;
  }
</style>
