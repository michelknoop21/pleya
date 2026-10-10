<!--
  De tabbalk onder 900 px (web.css `.tabbar`): vast onderaan, doorschijnend met
  een blur, labels van 11 px, het actieve tabblad in het merkrood.

  Het aantal tabs volgt de slots uit navItems: Boeken verschijnt alleen met een
  boekenbibliotheek, en dan is er plek voor vijf in plaats van vier.
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

<nav class="tabbar" aria-label={t('nav.primary')}>
  <ul class="tabs">
    {#each items as item (item.id)}
      <li class="cell">
        <a
          class="tab"
          class:tab--on={item.id === activeId}
          href={item.href}
          aria-current={item.id === activeId ? 'page' : undefined}
        >
          <NavIcon name={item.icon} size={24} />
          <span class="label">{item.label}</span>
        </a>
      </li>
    {/each}
  </ul>
</nav>

<style>
  .tabbar {
    position: fixed;
    inset-inline: 0;
    bottom: 0;
    z-index: 40;
    height: calc(var(--bottom-bar-height) + env(safe-area-inset-bottom, 0px));
    padding-top: 6px;
    background: var(--bar-backdrop);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border-top: 1px solid var(--outline);
  }

  .tabs {
    display: flex;
    justify-content: space-around;
    padding: 0 4px;
  }

  .cell {
    flex: 1 1 0;
    min-width: 0;
    display: flex;
    justify-content: center;
  }

  .tab {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    width: 64px;
    color: var(--ink-2);
    font-size: 11px;
  }

  .tab--on {
    color: var(--accent);
    font-weight: 600;
  }

  .label {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
