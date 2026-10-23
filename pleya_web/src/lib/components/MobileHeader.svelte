<!--
  De kop onder 900 px (web.css `.mhead`): merk links, zoeken rechts, 52 hoog.
  De navigatie zelf staat in TabBar.
-->
<script lang="ts">
  import NavIcon from './NavIcon.svelte';
  import Wordmark from './Wordmark.svelte';
  import { t } from '../i18n';

  interface Props {
    showSearch?: boolean;
    searchActive?: boolean;
  }

  let { showSearch = false, searchActive = false }: Props = $props();
</script>

<header class="mhead">
  <a class="brand" href="/">
    <Wordmark size="mobile" />
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
    min-height: var(--touch-target);
  }

  .search {
    display: grid;
    place-items: center;
    width: var(--touch-target);
    height: var(--touch-target);
    margin-right: -10px;
  }
</style>
