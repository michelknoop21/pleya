<!--
  Opslag per bibliotheek als één gesegmenteerde balk met een legenda eronder,
  het handelsmerk van designsysteem v2 (specimen "Opslag per bibliotheek",
  beheeroverzicht 20 en opslag 24).

  De legenda draagt de gegevens: een lijst met per segment de naam en de
  geformatteerde waarde, benoemd met `label`. De balk herhaalt dat alleen in
  beeld en staat daarom buiten de toegankelijkheidsboom; anders leest een
  schermlezer alles twee keer, en een kale balk zonder getallen zegt niets.

  Breedtes gaan via `style:flex-grow` (de CSP laat geen style-attribuut toe):
  het aandeel in procenten van `total`, of van de som als `total` ontbreekt.
  Een segment van 0 valt uit de balk maar blijft in de legenda, want "Boeken
  0 GB" is ook een antwoord. Een piepklein segment krijgt minstens één
  procent, anders verdwijnt het tussen de spleten. Is `total` groter dan de
  som, dan tekent de balk de rest als gedempt vrij vlak.
-->
<script lang="ts" module>
  export type MeterTone = 'ink' | 'amber' | 'red' | 'blue' | 'free';

  export interface MeterSegment {
    label: string;
    value: number;
    tone?: MeterTone;
  }

  /** Ondergrens in procenten voor een segment dat niet nul is. */
  export const MIN_SHARE = 1;
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    segments: MeterSegment[];
    /** Naam van de legenda voor een schermlezer: "Opslag per bibliotheek". */
    label: string;
    /** Het geheel; zonder deze waarde is dat de som van de segmenten. */
    total?: number;
    /** Waarde naar tekst, met eenheid: `(v) => `${v} TB``. */
    format?: (value: number) => string;
    /** In plaats van de legenda als er niets te tonen is (totaal 0). */
    empty?: Snippet;
  }

  let { segments, label, total, format = (v) => String(v), empty }: Props = $props();

  const sum = $derived(segments.reduce((acc, s) => acc + Math.max(0, s.value), 0));
  const whole = $derived(Math.max(total ?? sum, sum));

  // Twee decimalen is fijner dan een pixel op elke balkbreedte, en houdt de
  // waarde in het style-attribuut leesbaar.
  function share(value: number): number {
    return Math.round((value / whole) * 10000) / 100;
  }

  const bars = $derived.by(() => {
    if (whole <= 0) return [];
    const drawn = segments
      .filter((s) => s.value > 0)
      .map((s) => ({ tone: s.tone ?? 'ink', grow: Math.max(share(s.value), MIN_SHARE) }));
    const rest = whole - sum;
    if (rest > 0) drawn.push({ tone: 'free', grow: Math.max(share(rest), MIN_SHARE) });
    return drawn;
  });
</script>

<div class="meter">
  <div class="meter__bar" class:meter__bar--empty={bars.length === 0} aria-hidden="true">
    {#each bars as bar, i (i)}
      <span class="meter__seg meter__seg--{bar.tone}" style:flex-grow={bar.grow}></span>
    {/each}
  </div>
  {#if whole <= 0 && empty}
    <div class="meter__empty">{@render empty()}</div>
  {:else}
    <ul class="meter__legend" aria-label={label}>
      {#each segments as segment, i (i)}
        <li class="meter__item">
          <span class="meter__swatch meter__seg--{segment.tone ?? 'ink'}" aria-hidden="true"></span>
          <!-- De spatie staat apart, anders snoeit Svelte hem en leest een
               schermlezer "Films7,4 TB". -->
          {segment.label}{' '}<span class="meter__value">{format(segment.value)}</span>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .meter {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
  }

  /* 10 px hoog met 3 px spleten, zoals het specimen. */
  .meter__bar {
    display: flex;
    gap: 3px;
    height: 10px;
    overflow: hidden;
    border-radius: 5px;
  }

  /* Leeg of onbekend: een gedempt spoor over de volle breedte. */
  .meter__bar--empty {
    background: var(--fill-2);
  }

  .meter__seg {
    flex-basis: 0;
    /* Vangnet onder de één procent uit het script: nooit smaller dan 4 px. */
    min-width: 4px;
    border-radius: 2px;
  }

  .meter__seg--ink {
    background: var(--ink);
  }

  .meter__seg--amber {
    background: var(--amber-graphic);
  }

  /* --accent is het merkrood; 4,7:1 op wit, 3,6:1 op het donkere paneel. */
  .meter__seg--red {
    background: var(--accent);
  }

  .meter__seg--blue {
    background: var(--blue);
  }

  .meter__seg--free {
    background: var(--fill-2);
  }

  .meter__legend {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 20px;
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: 13px;
    line-height: 1.4;
    font-variant-numeric: tabular-nums;
    color: var(--ink-2);
  }

  .meter__item {
    display: flex;
    align-items: center;
    gap: 8px;
    white-space: nowrap;
  }

  .meter__swatch {
    flex: none;
    width: 9px;
    height: 9px;
    border-radius: 3px;
  }

  .meter__value {
    margin-left: -2px;
    color: var(--ink-3);
  }

  .meter__empty {
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
