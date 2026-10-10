<!--
  Een statuslabel (`.pill` met `.dot` in web.css): capsule van 24 hoog met een
  stip en een kort woord, getint naar de toon. In een tabelcel (mockup 21) is
  hij 20 hoog; dat is `size="sm"`.

  De toonkleuren zijn dezelfde als die van Alert en Chips: groen (--ok) voor
  klaar, amber (--amber) voor overgeslagen of bezig, --danger-ink voor een
  fout, inkt voor een lopende sessie en gedimde inkt voor niets aan de hand.
  Kleur draagt nooit de betekenis alleen: het label zegt het altijd ook.
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
    icon?: Snippet;
  }

  let { label, tone = 'idle', dot = true, size = 'md', icon }: Props = $props();
</script>

<span class="pill pill--{tone}" class:pill--sm={size === 'sm'}>
  {#if icon}
    <span class="pill__icon" aria-hidden="true">{@render icon()}</span>
  {:else if dot}
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

  .pill--sm {
    height: 20px;
    padding: 0 8px;
  }

  /* Achtergronden zijn de mockup-rgba's als mengsel van de toonkleur. */
  .pill--ok {
    background: color-mix(in srgb, var(--ok) 15%, transparent);
    color: var(--ok);
  }

  .pill--warn {
    background: color-mix(in srgb, var(--amber) 15%, transparent);
    color: var(--amber);
  }

  .pill--err {
    background: color-mix(in srgb, var(--accent) 18%, transparent);
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
