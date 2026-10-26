<!--
  De kop onder 900 px (web.css `.mhead`): merk links, zoeken rechts, 52 hoog.
  De navigatie zelf staat in TabBar.
  Met `back` wordt het de terugkop (`.mhead.nav`, schermen 20 en 33): pijl en
  titel links, geen merk. Beheer gebruikt hem; de Beheer-pil staat er dan niet
  bij, want je bent er al.
-->
<script lang="ts">
  import AdminIcon from './AdminIcon.svelte';
  import AdminPill from './AdminPill.svelte';
  import NavIcon from './NavIcon.svelte';
  import Wordmark from './Wordmark.svelte';
  import { t } from '../i18n';

  interface Props {
    showSearch?: boolean;
    searchActive?: boolean;
    /** Alleen voor eigenaar of beheerder (`session.canAdminister`). */
    showAdmin?: boolean;
    back?: { href: string; title: string } | null;
  }

  let { showSearch = false, searchActive = false, showAdmin = false, back = null }: Props =
    $props();
</script>

{#if back}
  <header class="mhead mhead--nav">
    <a class="back" href={back.href} aria-label={t('common.back')}>
      <AdminIcon name="back" size={26} />
    </a>
    <span class="title">{back.title}</span>
  </header>
{:else}
  <header class="mhead">
    <a class="brand" href="/">
      <Wordmark size="mobile" />
    </a>

    <div class="actions">
      {#if showAdmin}
        <AdminPill compact />
      {/if}
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
    </div>
  </header>
{/if}

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

  .actions {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .mhead--nav {
    justify-content: flex-start;
    gap: 12px;
  }

  .back {
    display: grid;
    place-items: center;
    width: var(--touch-target);
    height: var(--touch-target);
    margin-left: -9px;
  }

  .title {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 18px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
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
