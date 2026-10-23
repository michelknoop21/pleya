<!--
  De paginakop (`.page-title` in web.css): één h1, met eventueel een aantal
  ernaast in --ink-3 (05: "Alle films 461") en acties rechts (17).

  De acties staan naast de h1 en niet erin, anders dan in de mockup: een knop
  in een kop wordt deel van de kopnaam, en dan leest een schermlezer "Films
  Alle films" als titel (dezelfde keuze als in Panel). Het aantal hoort wel in
  de kop, want "Alle films, 461" is samen de naam van de pagina.

  Maat: designsysteem v2 (--text-page-title-size) vanaf 900, 26 eronder. Het
  gewicht is 700 en niet de 800 uit het systeem: de gebundelde Inter heeft geen
  800, en de browser zou hem dan zelf vetter maken. Onder 900 zakken de acties
  onder de titel en lopen ze over de volle breedte, zoals web.css het doet.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    /** Bijschrift naast de titel, meestal een aantal. */
    sub?: string | number;
    actions?: Snippet;
  }

  let { title, sub, actions }: Props = $props();
</script>

<div class="ph">
  <h1 class="ph__title">
    {title}{#if sub !== undefined && sub !== ''}
      {' '}<span class="ph__sub">{sub}</span>
    {/if}
  </h1>
  {#if actions}
    <div class="ph__actions">{@render actions()}</div>
  {/if}
</div>

<style>
  .ph {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 16px;
    margin: 12px 0 18px;
  }

  .ph__title {
    min-width: 0;
    margin: 0;
    font-size: var(--text-page-title-size);
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .ph__sub {
    font-size: 15px;
    font-weight: 400;
    letter-spacing: 0;
    color: var(--ink-3);
  }

  .ph__actions {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
  }

  @media (max-width: 899px) {
    .ph {
      flex-wrap: wrap;
      margin: 6px 0 12px;
    }

    .ph__title {
      font-size: 26px;
    }

    .ph__sub {
      display: block;
      margin-top: 4px;
    }

    .ph__actions {
      width: 100%;
      gap: 8px;
    }

    /* Een gewone knop vult de regel; een icoonknop houdt zijn eigen maat. */
    .ph__actions :global(.btn:not(.btn--icon)) {
      flex: 1 1 100%;
    }
  }
</style>
