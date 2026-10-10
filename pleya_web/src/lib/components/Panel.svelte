<!--
  Een paneel (`.panel` in web.css): vlak op --surface met kaartradius, waar
  beheerschermen hun blokken in zetten. Kop en acties staan op één regel; onder
  900 schuiven de acties naar een eigen regel onder de titel.

  De acties staan bewust naast de kop en niet erin: een link in een <h3> wordt
  deel van de kopnaam, en dan leest een schermlezer "Recente taken Alles
  bekijken" als titel. De sectie krijgt de kop als naam via aria-labelledby.

  `flush` is de smalle binnenrand van 6 bij 8 die de mockups (21, 27) bij een
  tabel gebruiken; `danger` is de rode rand van een gevarenzone (22, 27). Beide
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
    padding: 18px 20px;
    border-radius: var(--radius-card);
    background: var(--surface);
  }

  .panel--flush {
    padding: 6px 8px;
  }

  .panel--danger {
    /* rgba(229,20,15,.35) in de mockup: de merkrode rand op 35 procent. */
    border: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
  }

  /* rgba(255,176,32,.35) in mockup 35: amber op 35 procent. */
  .panel--warn {
    border: 1px solid color-mix(in srgb, var(--amber) 35%, transparent);
  }

  .panel__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 12px;
  }

  /* Een flush paneel houdt zijn kop op dezelfde lijn als een gewoon paneel. */
  .panel--flush .panel__head {
    padding: 12px 12px 0;
  }

  .panel__title {
    min-width: 0;
    font-size: 16px;
    font-weight: 700;
    line-height: 1.3;
    color: var(--ink);
  }

  /* #FF6A63 in mockup 22, 27 en 31; dat is --danger-ink. */
  .panel--danger .panel__title {
    color: var(--danger-ink);
  }

  .panel--warn .panel__title {
    color: var(--amber);
  }

  .panel__actions {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
    font-size: 13px;
    font-weight: 500;
    color: var(--ink-2);
  }

  @media (max-width: 899px) {
    .panel__head {
      flex-wrap: wrap;
    }

    .panel__actions {
      width: 100%;
      margin-left: 0;
    }
  }
</style>
