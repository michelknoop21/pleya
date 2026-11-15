<!--
  De tabs van de pagina van één gebruiker: Profiel, Toegang en Toestellen. Het
  zijn echte links naar `?tab=`, zodat herladen op dezelfde tab blijft en een
  tab in een nieuw venster te openen is; de actieve draagt
  `aria-current="page"`. Een gewone klik wisselt zonder de pagina opnieuw op te
  bouwen (UserEditor houdt de keuze bij en zet de query), zodat een nog niet
  opgeslagen rol of recht blijft staan.
-->
<script lang="ts">
  import { t, type MessageKey } from '../i18n';
  import { USER_TABS, type UserTab } from './users';

  interface Props {
    active: UserTab;
    onselect: (tab: UserTab) => void;
  }

  let { active, onselect }: Props = $props();

  function click(event: MouseEvent, tab: UserTab): void {
    // Met een toets erbij wil iemand een nieuw tabblad of venster: laat de link zijn werk doen.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    onselect(tab);
  }
</script>

<nav class="tabs" aria-label={t('admin.users.tabs.label')}>
  {#each USER_TABS as tab (tab)}
    <a
      class="tab"
      href={`?tab=${tab}`}
      aria-current={tab === active ? 'page' : undefined}
      onclick={(event) => click(event, tab)}
    >
      {t(`admin.users.tabs.${tab}` as MessageKey)}
    </a>
  {/each}
</nav>

<style>
  .tabs {
    display: flex;
    gap: 24px;
    margin-bottom: 18px;
    border-bottom: 1px solid var(--hairline-strong);
    overflow-x: auto;
  }

  .tab {
    display: inline-flex;
    flex: none;
    align-items: center;
    min-height: var(--touch-target);
    padding: 0 4px;
    border-bottom: 2px solid transparent;
    font-size: 15px;
    font-weight: 500;
    color: var(--ink-2);
  }

  .tab[aria-current='page'] {
    border-bottom-color: var(--accent);
    color: var(--ink);
  }

  .tab:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: -3px;
    border-radius: var(--radius-focus);
  }

  @media (hover: hover) {
    .tab:hover {
      color: var(--ink);
    }
  }

  @media (max-width: 479px) {
    .tabs {
      gap: 16px;
    }
  }
</style>
