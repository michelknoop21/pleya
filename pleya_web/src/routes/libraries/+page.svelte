<script lang="ts">
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import NavIcon from '#lib/components/NavIcon.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { formatCount } from '#lib/util/format.js';
  import { plural, t } from '#lib/i18n/index.js';
</script>

<svelte:head><title>{t('libraries.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={t('libraries.title')} />

  {#if session.libraries.length === 0}
    <StateView title={t('libraries.emptyTitle')} message={t('libraries.emptyBody')} />
  {:else}
    <ul class="list">
      {#each session.libraries as library (library.id)}
        <li>
          <a class="tile" href="/libraries/{library.id}">
            <span class="tile__icon">
              <NavIcon name={library.kind === 'shows' ? 'show' : 'movie'} size={24} />
            </span>
            <span class="tile__text">
              <span class="t-title">{library.title}</span>
              <span class="tile__count">
                {plural('libraries.itemCount', library.item_count, {
                  count: formatCount(library.item_count)
                })}
              </span>
            </span>
          </a>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .page {
    padding: 8px var(--inset) var(--space-2);
  }

  .list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: var(--space);
  }

  /* Een tegel is een paneel dat je aanklikt: --panel met een haarlijn, de
     radius van een kaart. De hover hoort achter hover: hover, anders blijft hij
     op een telefoon na een tik hangen. */
  .tile {
    display: flex;
    align-items: center;
    gap: var(--space);
    min-height: 72px;
    padding: var(--space);
    background: var(--panel);
    border: 1px solid var(--hairline);
    border-radius: var(--radius-card);
    transition: background var(--dur-fast) var(--ease);
  }

  @media (hover: hover) {
    .tile:hover {
      background: var(--panel-2);
    }
  }

  .tile__icon {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: var(--radius-md);
    background: var(--fill);
    color: var(--ink);
    flex: 0 0 auto;
  }

  .tile__text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .tile__text > :first-child {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .tile__count {
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
