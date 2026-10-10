<!--
  De bovenbalk vanaf 900 px: merk links, de vijf slots als capsules in het
  midden, acties rechts. Dit is het rootcontract van de TV-familie op webmaat
  (web.css `.topnav`); onder 900 neemt MobileHeader met TabBar het over.

  Het actieve slot is een witte capsule met donkere tekst. Focus krijgt de
  ring op een gap van 3 px via de globale :focus-visible.
-->
<script lang="ts">
  import NavIcon from './NavIcon.svelte';
  import type { NavItem } from './navItems';
  import { t } from '../i18n';

  interface Props {
    items: NavItem[];
    activeId: string | null;
    /** Alleen waar de server zoeken aanbiedt. */
    showSearch?: boolean;
    searchActive?: boolean;
  }

  let { items, activeId, showSearch = false, searchActive = false }: Props = $props();
</script>

<nav class="topnav" aria-label={t('nav.primary')}>
  <a class="brand" href="/">
    <img src="/brand/pleya-mark-64.png" alt="" width="30" height="30" />
    <span class="brand__name">{t('app.name')}</span>
  </a>

  <ul class="cluster">
    {#each items as item (item.id)}
      <li>
        <a
          class="item"
          class:item--on={item.id === activeId}
          href={item.href}
          aria-current={item.id === activeId ? 'page' : undefined}
        >
          {item.label}
        </a>
      </li>
    {/each}
  </ul>

  <div class="actions">
    {#if showSearch}
      <!--
        Het zoekveld van web.css `.search-inline`: een link die eruitziet als
        een veld en naar de zoekpagina gaat, waar het echte veld staat. Een
        tweede invoerveld in de kop zou twee bronnen voor de zoekterm geven.
      -->
      <a
        class="search"
        class:search--on={searchActive}
        href="/search"
        aria-label={t('nav.search')}
        aria-current={searchActive ? 'page' : undefined}
      >
        <NavIcon name="search" size={18} />
        <span class="search__ph">{t('nav.searchPlaceholder')}</span>
      </a>
    {/if}
  </div>
</nav>

<style>
  .topnav {
    position: sticky;
    top: 0;
    z-index: 30;
    height: var(--nav-h);
    padding: 0 var(--inset);
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    background: linear-gradient(var(--bg) 60%, transparent);
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    justify-self: start;
  }

  .brand__name {
    font-weight: 700;
    font-size: var(--text-title-size);
    letter-spacing: -0.2px;
  }

  .cluster {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .item {
    display: block;
    height: 40px;
    line-height: 40px;
    padding: 0 16px;
    border-radius: var(--radius-pill);
    font-size: 16px;
    font-weight: 500;
    color: var(--ink-2);
    white-space: nowrap;
  }

  .item--on {
    background: var(--ink);
    color: var(--bg);
  }

  .actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 18px;
    color: var(--ink-2);
  }

  .search {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 260px;
    height: 40px;
    padding: 0 14px;
    border-radius: var(--radius-pill);
    background: var(--fill);
    color: var(--ink-3);
    font-size: 14px;
  }

  .search--on {
    color: var(--ink);
  }

  @media (max-width: 1199px) {
    .item {
      padding: 0 12px;
      font-size: 15px;
    }
    .actions {
      gap: 12px;
    }
    .search {
      width: 170px;
    }
  }
</style>
