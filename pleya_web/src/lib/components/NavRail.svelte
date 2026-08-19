<!--
  De zijbalk, met dezelfde maten als de app: 80 px ingeklapt, 220 px
  uitgeklapt (`SideNavigationRailState.collapsedWidth` en `expandedWidth`), en
  hij klapt uit bij aanwijzer of focus.

  Uitklappen op hover staat achter `@media (hover: hover)`. Op focus gebeurt
  het altijd, want een toetsenbordgebruiker moet de labels kunnen lezen.

  Het actieve item draagt links een massieve rode balk van 3 px, zoals in
  `NavigationRailItem`.
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
  let focusWithin = $state(false);
</script>

<nav
  class="rail"
  class:rail--open={focusWithin}
  aria-label={t('nav.primary')}
  onfocusin={() => (focusWithin = true)}
  onfocusout={(event) => {
    const next = event.relatedTarget;
    if (!(next instanceof Node) || !event.currentTarget.contains(next)) focusWithin = false;
  }}
>
  <a class="rail__brand" href="/">
    <img src="/brand/pleya-mark-256.png" alt={t('app.name')} width="36" height="36" />
    <span class="rail__brandName">{t('app.name')}</span>
  </a>

  <ul class="rail__items">
    {#each items as item (item.id)}
      <li>
        <a
          class="rail__item"
          class:rail__item--active={item.id === activeId}
          href={item.href}
          aria-current={item.id === activeId ? 'page' : undefined}
        >
          <NavIcon name={item.icon} />
          <span class="rail__label">{item.label}</span>
        </a>
      </li>
    {/each}
  </ul>
</nav>

<style>
  .rail {
    position: sticky;
    top: 0;
    height: 100dvh;
    width: var(--rail-collapsed);
    /*
     * flex-basis blijft bewust `auto`, zodat `width` de breedte bepaalt. Met
     * `flex: 0 0 var(--rail-collapsed)` wint de basis van de breedte, en dan
     * verandert er niets meer wanneer het uitklappen hieronder alleen `width`
     * aanpast: de balk bleef 80 px, hoe je er ook overheen ging.
     */
    flex: 0 0 auto;
    background: var(--surface);
    border-right: 1px solid var(--outline);
    padding: var(--space) 0;
    display: flex;
    flex-direction: column;
    gap: var(--space);
    overflow: hidden;
    transition: width var(--dur-normal) var(--ease);
    z-index: 20;
  }

  /* Uitklappen mag de inhoud niet verschuiven: de balk groeit over de pagina
     heen, net als in de app, waar de rail zijn breedte animeert binnen een
     vaste kolom. */
  .rail--open {
    width: var(--rail-expanded);
    box-shadow: 8px 0 24px rgb(0 0 0 / 0.28);
  }

  @media (hover: hover) {
    .rail:hover {
      width: var(--rail-expanded);
      box-shadow: 8px 0 24px rgb(0 0 0 / 0.28);
    }
  }

  .rail__brand,
  .rail__item {
    display: flex;
    align-items: center;
    gap: 11px;
    padding: var(--space) 17px;
    min-height: var(--touch-target);
    white-space: nowrap;
  }

  .rail__brand img {
    width: 36px;
    height: 36px;
    flex: 0 0 auto;
    margin-inline-start: -6px;
  }

  .rail__brandName {
    font-weight: 700;
    letter-spacing: -0.2px;
    font-size: var(--text-title-size);
  }

  .rail__items {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
    padding-inline: var(--space);
  }

  .rail__item {
    position: relative;
    border-radius: var(--radius-md);
    color: var(--text-muted);
    transition:
      background var(--dur-fast) var(--ease),
      color var(--dur-fast) var(--ease);
  }

  .rail__item--active {
    color: var(--text);
    background: var(--nav-selected-wash);
  }

  /* De rode balk op het actieve item. */
  .rail__item--active::before {
    content: '';
    position: absolute;
    inset-inline-start: 0;
    top: 8px;
    bottom: 8px;
    width: 3px;
    border-radius: 2px;
    background: var(--accent);
  }

  @media (hover: hover) {
    .rail__item:hover {
      background: var(--nav-focus-wash);
      color: var(--text);
    }
  }

  .rail__label,
  .rail__brandName {
    opacity: 0;
    transition: opacity var(--dur-fast) var(--ease);
  }

  .rail--open .rail__label,
  .rail--open .rail__brandName {
    opacity: 1;
  }

  @media (hover: hover) {
    .rail:hover .rail__label,
    .rail:hover .rail__brandName {
      opacity: 1;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .rail,
    .rail__label,
    .rail__brandName,
    .rail__item {
      transition: none;
    }
  }
</style>
