<!--
  Een statuslabel (`.pill` in web.css): capsule van 24 hoog met een kort woord,
  getint naar de toon. Geen enkele northstar-pill tekent een stip, dus die is
  opt-in met `dot`. In een tabelcel (mockup 21) is hij 20 hoog; dat is
  `size="sm"`.

  De toonkleuren zijn dezelfde als die van Alert en Chips: groen (--ok) voor
  klaar, amber (--amber) voor overgeslagen of bezig, --danger-ink voor een
  fout, inkt voor een lopende sessie en gedimde inkt voor niets aan de hand.
  Kleur draagt nooit de betekenis alleen: het label zegt het altijd ook.

  Designsysteem v2 voegt `variant="dot"` toe: geen capsule, alleen een stip van
  8 px in de toonkleur met de tekst in gedimde inkt, zoals de statuskolom van
  een beheertabel. Bij `run` is de stip amber en pulseert hij. De kleine maat (`size="sm"`) is
  in v2 een tag met hoeken van 6 px in plaats van een capsule.
-->
<script lang="ts" module>
  export type PillTone = 'ok' | 'warn' | 'err' | 'run' | 'idle';
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    label: string;
    tone?: PillTone;
    dot?: boolean;
    size?: 'md' | 'sm';
    /** `dot`: stip plus tekst zonder capsule, voor een statuscel in een tabel. */
    variant?: 'pill' | 'dot';
    icon?: Snippet;
  }

  let {
    label,
    tone = 'idle',
    dot = false,
    size = 'md',
    variant = 'pill',
    icon
  }: Props = $props();
</script>

<span
  class="pill pill--{tone}"
  class:pill--sm={size === 'sm' && variant === 'pill'}
  class:pill--status={variant === 'dot'}
>
  {#if icon}
    <span class="pill__icon" aria-hidden="true">{@render icon()}</span>
  {:else if dot || variant === 'dot'}
    <span class="pill__dot" aria-hidden="true"></span>
  {/if}
  {label}
</span>

<style>
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 24px;
    padding: 0 10px;
    border-radius: var(--radius-pill);
    background: var(--fill);
    font-size: 12px;
    font-weight: 600;
    line-height: 1;
    color: var(--ink-2);
    white-space: nowrap;
    vertical-align: middle;
  }

  /* `.tag` in specimen v2: 20 hoog, hoeken van 6, 11 px. */
  .pill--sm {
    height: 20px;
    padding: 0 8px;
    border-radius: 6px;
    font-size: 11px;
    letter-spacing: 0.01em;
  }

  /* Achtergronden zijn de rgba's uit specimen v2 als mengsel van de toonkleur. */
  .pill--ok {
    background: color-mix(in srgb, var(--ok) 14%, transparent);
    color: var(--ok-ink);
  }

  .pill--warn {
    background: color-mix(in srgb, var(--amber) 14%, transparent);
    color: var(--warn-ink);
  }

  .pill--err {
    background: color-mix(in srgb, var(--danger-ink) 14%, transparent);
    color: var(--danger-ink);
  }

  .pill--run {
    background: var(--fill-2);
    color: var(--ink);
  }

  .pill__dot {
    flex: none;
    width: 7px;
    height: 7px;
    border-radius: var(--radius-pill);
    background: currentColor;
  }

  /* De stip van "niets aan de hand" is stiller dan de tekst (`.dot.idle`). */
  .pill--idle .pill__dot {
    background: var(--ink-4);
  }

  /*
   * Statusvorm (`.st` in specimen v2). Na de toonregels, zodat de capsule en
   * de getinte tekst wegvallen; de toonkleur zit alleen nog in de stip.
   */
  .pill--status {
    gap: 8px;
    height: auto;
    padding: 0;
    border-radius: 0;
    background: none;
    font-size: 13.5px;
    font-weight: 400;
    line-height: 1.3;
    font-variant-numeric: tabular-nums;
    color: var(--ink-2);
  }

  .pill--status .pill__dot {
    width: 8px;
    height: 8px;
  }

  .pill--status.pill--ok .pill__dot {
    background: var(--ok-ink);
  }

  .pill--status.pill--warn .pill__dot {
    background: var(--warn-ink);
  }

  .pill--status.pill--err .pill__dot {
    background: var(--danger-ink);
  }

  /*
   * In de statusvorm is `run` amber en pulseert hij: "bezig" in northstar 21 en
   * het specimen. De capsule `run` blijft inkt, zoals een lopende sessie in 25.
   */
  .pill--status.pill--run .pill__dot {
    background: var(--warn-ink);
    animation: pill-pulse 1.6s ease-in-out infinite;
  }

  @keyframes pill-pulse {
    50% {
      opacity: 0.35;
    }
  }

  /* base.css zet animaties bij minder beweging al op nul; dit is expliciet. */
  @media (prefers-reduced-motion: reduce) {
    .pill--status.pill--run .pill__dot {
      animation: none;
    }
  }

  .pill__icon {
    display: grid;
    place-items: center;
    width: 12px;
    height: 12px;
  }

  .pill__icon :global(svg) {
    width: 100%;
    height: 100%;
  }
</style>
