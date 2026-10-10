<!--
  Een rij filterchips (`.chips` en `.chip` in web.css). Twee varianten uit de
  mockup: `outline` met een dunne rand die aan staat rood getint wordt, en
  `quiet` op een vlak dat aan staat wit (inkt) wordt, zoals de filters in
  zoeken.

  Elke chip is een toggle-button met aria-pressed. Spatie en Enter komen met de
  button mee, Tab loopt de chips af. Zonder `multiple` gedraagt de rij zich als
  één keuze: de gekozen chip blijft staan als je hem nog eens indrukt, zodat er
  altijd een filter actief is. Met `multiple` zet elke chip zichzelf aan en uit.

  De chip tekent 36 hoog; de button eromheen is 44 hoog, het raakvlak. De rij
  scrolt horizontaal in plaats van af te kappen (de mockup zegt overflow:
  hidden), anders vallen chips buiten beeld die je met Tab nog wel bereikt.
-->
<script lang="ts" module>
  export interface ChipOption {
    id: string;
    label: string;
    count?: number;
  }
</script>

<script lang="ts">
  interface Props {
    options: ChipOption[];
    selected?: string[];
    label: string;
    multiple?: boolean;
    variant?: 'outline' | 'quiet';
    onchange?: (selected: string[]) => void;
  }

  let {
    options,
    selected = $bindable([]),
    label,
    multiple = false,
    variant = 'outline',
    onchange
  }: Props = $props();

  function press(id: string): void {
    const on = selected.includes(id);
    if (multiple) {
      selected = on ? selected.filter((s) => s !== id) : [...selected, id];
    } else {
      if (on) return;
      selected = [id];
    }
    onchange?.(selected);
  }
</script>

<div class="chips" role="group" aria-label={label}>
  {#each options as option (option.id)}
    {@const on = selected.includes(option.id)}
    <button type="button" class="chips__hit" aria-pressed={on} onclick={() => press(option.id)}>
      <span class="chip chip--{variant}" class:chip--on={on}>
        {option.label}
        {#if option.count !== undefined}
          <span class="chip__badge">{option.count}</span>
        {/if}
      </span>
    </button>
  {/each}
</div>

<style>
  .chips {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    /*
     * De scrollcontainer knipt alles buiten zijn padding af. De ring steekt
     * 4 px buiten de chip uit (3 + 1 offset); horizontaal vangt deze padding
     * dat op, verticaal doet de 44 px hoge button het al.
     */
    padding-inline: 4px;
    overflow-x: auto;
    scrollbar-width: none;
  }

  .chips::-webkit-scrollbar {
    display: none;
  }

  .chips__hit {
    flex: none;
    display: inline-flex;
    align-items: center;
    min-width: var(--touch-target);
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    background: none;
    color: inherit;
    font: inherit;
    cursor: pointer;
  }

  .chips__hit:focus-visible {
    outline: none;
  }

  .chips__hit:focus-visible .chip {
    outline: var(--ring) solid var(--ink);
    /* 36 + 2 x (1 + 3) = 44: de ring past precies in de scrollende rij. */
    outline-offset: 1px;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    height: 36px;
    padding: 0 14px;
    border: 1px solid transparent;
    border-radius: var(--radius-pill);
    font-size: 14px;
    font-weight: 500;
    color: var(--ink);
    white-space: nowrap;
    transition:
      background var(--dur-fast) var(--ease),
      border-color var(--dur-fast) var(--ease),
      color var(--dur-fast) var(--ease);
  }

  /* rgba(255,255,255,.25) in de mockup: inkt op 25 procent, draait mee met het thema. */
  .chip--outline {
    border-color: color-mix(in srgb, var(--text) 25%, transparent);
  }

  .chip--outline.chip--on {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    color: var(--danger-ink);
  }

  .chip--quiet {
    background: var(--fill);
    color: var(--ink-2);
  }

  .chip--quiet.chip--on {
    background: var(--ink);
    color: var(--bg);
    font-weight: 600;
  }

  .chip__badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 18px;
    height: 18px;
    padding: 0 5px;
    border-radius: 9px;
    background: var(--ink);
    color: var(--bg);
    font-size: 11px;
    font-weight: 700;
  }

  .chip--outline.chip--on .chip__badge {
    background: var(--accent);
    /* De badge is wit op merkrood in elk thema (web.css `.chip.on .badge`). */
    color: #fff;
  }

  @media (hover: hover) {
    .chips__hit:hover .chip--quiet:not(.chip--on) {
      background: var(--fill-2);
      color: var(--ink);
    }

    .chips__hit:hover .chip--outline:not(.chip--on) {
      border-color: color-mix(in srgb, var(--text) 45%, transparent);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .chip {
      transition: none;
    }
  }
</style>
