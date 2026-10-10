<!--
  De kop onder 900 px (web.css `.mhead`): merk links, zoeken rechts, 52 hoog.
  De navigatie zelf staat in TabBar.
-->
<script lang="ts">
  import NavIcon from './NavIcon.svelte';
  import { t } from '../i18n';

  interface Props {
    showSearch?: boolean;
    searchActive?: boolean;
  }

  let { showSearch = false, searchActive = false }: Props = $props();
</script>

<header class="mhead">
  <a class="brand" href="/">
    <img src="/brand/pleya-mark-64.png" alt="" width="28" height="28" />
    <span class="brand__name">{t('app.name')}</span>
  </a>

  {#if showSearch}
    <a
      class="search"
      href="/search"
      aria-label={t('nav.search')}
      aria-current={searchActive ? 'page' : undefined}
    >
      <NavIcon name="search" size={24} />
    </a>
  {/if}
</header>

<style>
  .mhead {
    position: sticky;
    top: 0;
    z-index: 30;
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 52px;
    padding: 0 var(--inset);
    background: var(--bg);
  }

  .brand {
    display: inline-flex;
    align-items: center;
    gap: var(--space-half);
  }

  .brand__name {
    font-weight: 700;
    letter-spacing: -0.2px;
  }

  .search {
    display: grid;
    place-items: center;
    width: var(--touch-target);
    height: var(--touch-target);
    margin-right: -10px;
  }
</style>
