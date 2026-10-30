<!--
  Een klein actiemenu achter de knop met drie punten (18: kop en rijen). Knop met
  aria-haspopup, lijst met role="menu". Pijltjes lopen door de acties, Escape en
  een klik ernaast sluiten, en de focus keert terug naar de knop.

  De lijst hangt met position: fixed aan de knop en niet in de stroom, zodat een
  rij of paneel met overflow hem niet afknipt; hij blijft binnen het venster.
-->
<script lang="ts">
  import { tick } from 'svelte';

  interface MenuAction {
    label: string;
    danger?: boolean;
    onselect: () => void;
  }

  let { label, actions, size = 'icon' }: { label: string; actions: MenuAction[]; size?: 'icon' | 'plain' } = $props();

  const MARGIN = 8;
  const WIDTH = 220;
  let open = $state(false);
  let button = $state<HTMLButtonElement>();
  let menu = $state<HTMLDivElement>();
  let place = $state({ top: 0, left: 0 });

  async function show(): Promise<void> {
    const box = button?.getBoundingClientRect();
    if (!box) return;
    open = true;
    const left = Math.min(box.right - WIDTH, window.innerWidth - WIDTH - MARGIN);
    place = { top: box.bottom + 4, left: Math.max(MARGIN, left) };
    await tick();
    const height = menu?.offsetHeight ?? 0;
    if (place.top + height > window.innerHeight - MARGIN) {
      place = { ...place, top: Math.max(MARGIN, box.top - height - 4) };
    }
    menu?.querySelector<HTMLButtonElement>('button')?.focus();
  }

  function hide(returnFocus = true): void {
    open = false;
    if (returnFocus) button?.focus();
  }

  function choose(action: MenuAction): void {
    hide();
    action.onselect();
  }

  function keydown(event: KeyboardEvent): void {
    const items = [...(menu?.querySelectorAll<HTMLButtonElement>('button') ?? [])];
    const at = items.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      hide();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      items[(at + 1) % items.length]?.focus();
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      items[(at - 1 + items.length) % items.length]?.focus();
    } else if (event.key === 'Tab') {
      hide(false);
    }
  }

  function outside(event: PointerEvent): void {
    if (open && !menu?.contains(event.target as Node) && !button?.contains(event.target as Node)) hide(false);
  }
</script>

<svelte:window onpointerdown={outside} onscroll={() => open && hide(false)} onresize={() => open && hide(false)} />

<button
  bind:this={button}
  type="button"
  class="more"
  class:more--plain={size === 'plain'}
  aria-label={label}
  aria-haspopup="menu"
  aria-expanded={open}
  onclick={() => (open ? hide() : void show())}
>
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="currentColor">
    <circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" />
  </svg>
</button>

{#if open}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    bind:this={menu}
    class="menu"
    role="menu"
    aria-label={label}
    style:top="{place.top}px"
    style:left="{place.left}px"
    style:width="{WIDTH}px"
    tabindex="-1"
    onkeydown={keydown}
  >
    {#each actions as action (action.label)}
      <button type="button" role="menuitem" class="menu__item" class:menu__item--danger={action.danger} onclick={() => choose(action)}>
        {action.label}
      </button>
    {/each}
  </div>
{/if}

<style>
  .more {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    flex: none;
    border: 0;
    border-radius: 999px;
    background: var(--elevated);
    color: var(--ink);
    cursor: pointer;
  }

  .more--plain {
    background: transparent;
    color: var(--ink-2);
  }

  @media (hover: hover) {
    .more:hover {
      background: var(--fill);
      color: var(--ink);
    }
  }

  .more:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 2px;
  }

  .menu {
    position: fixed;
    z-index: 60;
    display: flex;
    flex-direction: column;
    padding: 6px;
    border-radius: var(--radius-md);
    background: var(--elevated);
    box-shadow: 0 0 0 1px var(--hairline), 0 12px 32px color-mix(in srgb, #000 45%, transparent);
  }

  .menu__item {
    min-height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--ink);
    font: inherit;
    font-size: 14px;
    text-align: left;
    cursor: pointer;
  }

  .menu__item--danger {
    color: var(--danger-ink);
  }

  .menu__item:hover,
  .menu__item:focus-visible {
    background: var(--fill);
    outline: none;
  }

  .menu__item:focus-visible {
    box-shadow: inset 0 0 0 var(--ring) var(--ink);
  }
</style>
