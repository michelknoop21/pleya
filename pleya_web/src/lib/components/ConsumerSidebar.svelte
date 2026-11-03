<script lang="ts">
  import NavIcon from './NavIcon.svelte';
  import Wordmark from './Wordmark.svelte';
  import type { NavItem } from './navItems';
  import { t } from '../i18n';
  let { items, activeId, showSearch = false, searchActive = false, showAdmin = false, showFavorites = false, favoritesActive = false, compact = $bindable(false) }: {
    items: NavItem[]; activeId: string | null; showSearch?: boolean; searchActive?: boolean;
    showAdmin?: boolean; showFavorites?: boolean; favoritesActive?: boolean; compact?: boolean;
  } = $props();
</script>

<aside class="consumer-sidebar" class:consumer-sidebar--compact={compact}>
  <div class="consumer-sidebar__brand">
    <a href="/" aria-label={t('app.name')}><span class="consumer-sidebar__wordmark"><Wordmark /></span><img class="consumer-sidebar__mark" src="/brand/pleya-mark-64.png" alt="" /></a>
    <button type="button" aria-label={t('nav.primary')} aria-expanded={!compact} onclick={() => compact = !compact}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 5h16v14H4zM9 5v14" /></svg>
    </button>
  </div>
  <nav aria-label={t('nav.primary')}>
    {#each items.filter(item => item.id === 'my') as item (item.id)}
      <a href={item.href} aria-label={item.label} aria-current={item.id === activeId && !favoritesActive ? 'page' : undefined}><NavIcon name={item.icon} /><span>{item.label}</span></a>
    {/each}
    {#if showSearch}<a href="/search" aria-label={t('nav.search')} aria-current={searchActive ? 'page' : undefined}><NavIcon name="search" /><span>{t('nav.search')}</span></a>{/if}
    {#each items.filter(item => item.id === 'home') as item (item.id)}
      <a href={item.href} aria-label={item.label} aria-current={item.id === activeId ? 'page' : undefined}><NavIcon name={item.icon} /><span>{item.label}</span></a>
    {/each}
    <div class="consumer-sidebar__label">{t('libraries.title')}</div>
    {#each ['films', 'series', 'books'].flatMap(id => items.filter(item => item.id === id)) as item (item.id)}
      <a href={item.href} aria-label={item.label} aria-current={item.id === activeId ? 'page' : undefined}><NavIcon name={item.icon} /><span>{item.label}</span></a>
    {/each}
    {#if items.some(item => item.id !== 'my')}<a href="/libraries" aria-label={t('libraries.title')}><NavIcon name="library" /><span>{t('libraries.title')}</span></a>{/if}
    {#if showFavorites}<a href="/server/favorites" aria-label={t('personal.favorites')} aria-current={favoritesActive ? 'page' : undefined}><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M6 3h12v18l-6-4-6 4z" /></svg><span>{t('personal.favorites')}</span></a>{/if}
    {#if showAdmin}<a href="/admin" aria-label={t('admin.pill')}><NavIcon name="settings" /><span>{t('admin.pill')}</span></a>{/if}
  </nav>
</aside>

<style>
  .consumer-sidebar { position: fixed; inset: 12px auto 12px 12px; width: 208px; z-index: 30; display: flex; flex-direction: column; padding: 16px 12px; background: var(--surface); border: 1px solid var(--hairline); border-radius: 20px; overflow-y: auto; }
  .consumer-sidebar__brand { display: flex; align-items: center; justify-content: space-between; min-height: 44px; margin-bottom: 32px; }
  .consumer-sidebar__brand button { display: grid; place-items: center; width: 44px; height: 44px; flex: none; border: none; background: transparent; color: var(--ink-2); border-radius: 50%; cursor: pointer; }
  .consumer-sidebar__brand button:hover { background: var(--fill); color: var(--ink); }
  nav { display: flex; flex-direction: column; gap: 6px; }
  nav a { display: flex; align-items: center; gap: 12px; min-height: 44px; padding: 10px 12px; color: var(--ink-2); border-radius: var(--radius-pill); font-size: 14px; white-space: nowrap; }
  nav a :global(svg) { flex: none; }
  nav a:hover { color: var(--ink); background: var(--fill); }
  nav a[aria-current] { background: var(--ink); color: var(--bg); font-weight: 600; }
  .consumer-sidebar__label { margin: 24px 12px 6px; font-size: 11px; color: var(--ink-3); }
  .consumer-sidebar__mark { display: none; }
  .consumer-sidebar--compact { width: 56px; padding-inline: 5px; }
  .consumer-sidebar--compact .consumer-sidebar__brand { flex-direction: column; gap: 12px; }
  .consumer-sidebar--compact .consumer-sidebar__mark { display: block; width: 32px; height: 32px; }
  .consumer-sidebar--compact .consumer-sidebar__wordmark, .consumer-sidebar--compact nav span, .consumer-sidebar--compact .consumer-sidebar__label { display: none; }
  .consumer-sidebar--compact nav a { justify-content: center; padding-inline: 0; }
</style>
