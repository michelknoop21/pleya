<!--
  De bottom bar onder 900 px, met dezelfde vorm als de app: doorschijnende
  bijna-zwarte balk met een blur eronder, labels van 11 px, en een massieve
  rode indicator van 18 bij 3 px boven het actieve item
  (`_buildBottomNavigationBar` in main_screen.dart).
-->
<script lang="ts">
  import NavIcon from './NavIcon.svelte';
  import type { NavItem } from './navItems';
  import { t } from '../i18n';

  interface Props {
    items: NavItem[];
    activeId: string | null;
  }

  let { items, activeId }: Props = $props();
</script>

<nav class="bar" aria-label={t('nav.primary')}>
  <ul class="bar__items">
    {#each items as item (item.id)}
      <li class="bar__cell">
        <a
          class="bar__item"
          class:bar__item--active={item.id === activeId}
          href={item.href}
          aria-current={item.id === activeId ? 'page' : undefined}
        >
          <NavIcon name={item.icon} />
          <span class="bar__label t-label">{item.label}</span>
        </a>
      </li>
    {/each}
  </ul>
</nav>

<style>
  .bar {
    position: fixed;
    inset-inline: 0;
    bottom: 0;
    z-index: 30;
    background: var(--bar-backdrop);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border-top: 1px solid var(--outline);
    padding-bottom: env(safe-area-inset-bottom, 0);
  }

  .bar__items {
    display: flex;
  }

  .bar__cell {
    flex: 1 1 0;
    min-width: 0;
  }

  .bar__item {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    min-height: var(--bottom-bar-height);
    padding: var(--space-half) var(--space-quarter);
    color: var(--text);
    opacity: 0.6;
  }

  .bar__item--active {
    opacity: 1;
  }

  .bar__item--active .bar__label {
    font-weight: 600;
  }

  .bar__item--active::before {
    content: '';
    position: absolute;
    top: 0;
    width: 18px;
    height: 3px;
    border-radius: 2px;
    background: var(--accent);
  }

  .bar__label {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
