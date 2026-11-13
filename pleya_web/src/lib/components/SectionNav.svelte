<!--
  De onderdelen van een beheerpagina als rij links onder de kop (doelbeeld
  Activiteit en Media en streaming). Het zijn links en geen tabs: elk onderdeel
  blijft op de pagina staan en de link springt ernaartoe, of gaat naar het
  scherm dat het onderdeel volledig toont. Op smal schuift de rij zelf opzij,
  zodat de pagina niet horizontaal gaat schuiven.
-->
<script lang="ts">
  export interface SectionLink {
    href: string;
    label: string;
  }

  let { label, items }: { label: string; items: SectionLink[] } = $props();
</script>

<nav class="sections" aria-label={label}>
  {#each items as item (item.href)}
    <a href={item.href}>{item.label}</a>
  {/each}
</nav>

<style>
  .sections {
    display: flex;
    gap: 24px;
    margin-bottom: 16px;
    overflow-x: auto;
    border-bottom: 1px solid var(--hairline);
  }

  a {
    display: inline-flex;
    flex: none;
    align-items: center;
    min-height: var(--touch-target);
    border-bottom: 2px solid transparent;
    font-size: 14px;
    font-weight: 500;
    color: var(--ink-2);
    white-space: nowrap;
  }

  a:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: -3px;
  }

  @media (hover: hover) {
    a:hover {
      border-bottom-color: var(--ink-3);
      color: var(--ink);
    }
  }
</style>
