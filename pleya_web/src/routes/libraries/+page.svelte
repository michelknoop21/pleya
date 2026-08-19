<script lang="ts">
  import StateView from '$lib/components/StateView.svelte';
  import NavIcon from '$lib/components/NavIcon.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { formatCount } from '$lib/util/format';
  import { plural, t } from '$lib/i18n';
</script>

<svelte:head><title>{t('libraries.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <h1 class="t-headline">{t('libraries.title')}</h1>

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
              <span class="t-small">
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
  .page {
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
    padding: var(--space-1-5) var(--page-inset, var(--space));
  }

  .list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: var(--space);
  }

  .tile {
    display: flex;
    align-items: center;
    gap: var(--space);
    min-height: 72px;
    padding: var(--space);
    background: var(--surface);
    border-radius: var(--radius-card);
    border: 1px solid var(--outline);
    transition: background var(--dur-fast) var(--ease);
  }

  @media (hover: hover) {
    .tile:hover {
      background: var(--surface-elevated);
    }
  }

  .tile__icon {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: var(--radius-md);
    background: color-mix(in srgb, var(--text) 8%, transparent);
    color: var(--text);
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
</style>
