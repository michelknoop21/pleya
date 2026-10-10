<!--
  Een paneel (`.panel` in web.css): het vlak waar beheerschermen hun blokken in
  zetten. Designsysteem v2: --panel boven de pagina, met een haarlijn en een
  zachte ring en schaduw, zodat het ook in OLED loskomt van zwart. Kop en
  acties staan op één regel; past dat niet, dan breekt de rij af en blijven de
  acties rechts.

  De acties staan bewust naast de kop en niet erin: een link in een <h3> wordt
  deel van de kopnaam, en dan leest een schermlezer "Recente taken Alles
  bekijken" als titel. De sectie krijgt de kop als naam via aria-labelledby.

  `flush` haalt de binnenrand weg voor een tabel of lijst die zelf tot de rand
  loopt (21, 27); de kop houdt de gewone inzet van 20, en de inhoud doet dat
  ook (DataTable zet zijn cellen op 20), zodat alles op één lijn staat; `danger` is de rode rand van een gevarenzone (22, 27). Beide
  stonden in de mockup als inline style, en dat laat de CSP hier niet toe.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title?: Snippet;
    actions?: Snippet;
    children: Snippet;
    level?: 2 | 3 | 4;
    flush?: boolean;
    /**
     * Gekleurde rand en titel: `danger` voor een onomkeerbare actie (mockup 22,
     * 27, 31), `warn` voor iets dat de dienst raakt maar terug kan (35).
     */
    tone?: 'danger' | 'warn';
    /** Oude vorm van `tone="danger"`; blijft werken. */
    danger?: boolean;
  }

  let {
    title,
    actions,
    children,
    level = 3,
    flush = false,
    tone,
    danger = false
  }: Props = $props();

  const resolvedTone = $derived(tone ?? (danger ? 'danger' : undefined));

  const uid = $props.id();
  const titleId = `${uid}-title`;
</script>

<section
  class="panel"
  class:panel--flush={flush}
  class:panel--danger={resolvedTone === 'danger'}
  class:panel--warn={resolvedTone === 'warn'}
  aria-labelledby={title ? titleId : undefined}
>
  {#if title || actions}
    <div class="panel__head">
      {#if title}
        <svelte:element this={`h${level}`} class="panel__title" id={titleId}>
          {@render title()}
        </svelte:element>
      {/if}
      {#if actions}
        <div class="panel__actions">{@render actions()}</div>
      {/if}
    </div>
  {/if}
  {@render children()}
</section>

<style>
  .panel {
    min-width: 0;
    padding: 18px 20px 20px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
    box-shadow: var(--ring-shadow);
  }

  .panel--flush {
    padding: 0 0 8px;
  }

  /* rgba(255,106,99,.34) in specimen v2: de gevareninkt op 34 procent. */
  .panel--danger {
    border-color: color-mix(in srgb, var(--danger-ink) 34%, transparent);
  }

  /* rgba(255,176,32,.35) in mockup 35: amber op 35 procent. */
  .panel--warn {
    border-color: color-mix(in srgb, var(--amber) 35%, transparent);
  }

  .panel__head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px 10px;
    min-height: 32px;
    margin-bottom: 14px;
  }

  /* Een flush paneel houdt zijn kop op dezelfde lijn als een gewoon paneel. */
  .panel--flush .panel__head {
    margin-bottom: 4px;
    padding: 18px 20px 0;
  }

  .panel__title {
    min-width: 0;
    font-size: 16px;
    font-weight: 600;
    line-height: 1.3;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  /* #FF6A63 in mockup 22, 27 en 31; dat is --danger-ink. */
  .panel--danger .panel__title {
    color: var(--danger-ink);
  }

  .panel--warn .panel__title {
    color: var(--warn-ink);
  }

  .panel__actions {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
    font-size: 13px;
    font-weight: 500;
    color: var(--ink-3);
  }
</style>
