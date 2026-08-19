<script lang="ts">
  import { page } from '$app/state';
  import { replaceState } from '$app/navigation';

  import MediaGrid from '$lib/components/MediaGrid.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { describeError } from '$lib/api/errors';
  import type { Item, ItemKind } from '$lib/api/types';
  import { t } from '$lib/i18n';

  /*
   * Zonder `kind` levert de server films, series en afleveringen. Seizoenen
   * blijven eruit, want hun titel is "Season 3" en draagt niets van wat iemand
   * intypt (DEC-045). Het filter hieronder biedt daarom geen seizoenen aan:
   * dat zou een lijst opleveren die alleen op het woord "Season" matcht.
   */
  const FILTERS: { id: 'all' | ItemKind; label: string }[] = [
    { id: 'all', label: t('search.filters.all') },
    { id: 'movie', label: t('search.filters.movies') },
    { id: 'show', label: t('search.filters.shows') },
    { id: 'episode', label: t('search.filters.episodes') }
  ];

  let query = $state(page.url.searchParams.get('q') ?? '');
  let filter = $state<'all' | ItemKind>('all');
  let results = $state<Item[]>([]);
  let searching = $state(false);
  let error = $state<string | null>(null);
  let searched = $state(false);

  async function run(term: string, kind: 'all' | ItemKind, signal: AbortSignal): Promise<void> {
    if (term.trim().length === 0) {
      results = [];
      searched = false;
      return;
    }
    searching = true;
    error = null;
    try {
      const found = await session.client.search(
        { q: term.trim(), ...(kind === 'all' ? {} : { kind }), limit: 100 },
        signal
      );
      if (signal.aborted) return;
      results = found.items;
      searched = true;
    } catch (err) {
      if (signal.aborted) return;
      error = describeError(err);
    } finally {
      if (!signal.aborted) searching = false;
    }
  }

  // Debounce plus annulering: elke toetsaanslag breekt de vorige aanvraag af,
  // zodat een traag antwoord van drie letters geleden niet over een nieuwer
  // resultaat heen valt.
  $effect(() => {
    const term = query;
    const kind = filter;
    const controller = new AbortController();
    const timer = setTimeout(() => void run(term, kind, controller.signal), 250);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  });

  $effect(() => {
    const url = new URL(page.url);
    if (query.trim()) url.searchParams.set('q', query.trim());
    else url.searchParams.delete('q');
    if (url.href !== page.url.href) replaceState(url, page.state);
  });
</script>

<svelte:head><title>{t('search.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <h1 class="t-headline">{t('search.title')}</h1>

  <form class="search" role="search" onsubmit={(event) => event.preventDefault()}>
    <label class="search__field">
      <span class="visually-hidden">{t('search.hint')}</span>
      <input
        class="field"
        type="search"
        bind:value={query}
        placeholder={t('search.hint')}
        autocomplete="off"
        spellcheck="false"
      />
    </label>

    <div class="search__filters" role="group" aria-label={t('search.filters.all')}>
      {#each FILTERS as option (option.id)}
        <button
          type="button"
          class="chip"
          class:chip--active={filter === option.id}
          aria-pressed={filter === option.id}
          onclick={() => (filter = option.id)}
        >
          {option.label}
        </button>
      {/each}
    </div>
  </form>

  <p class="t-small" aria-live="polite">
    {#if searching}
      {t('loading')}
    {:else if searched}
      {t('search.resultsFor', { query: query.trim() })}
    {/if}
  </p>

  {#if error}
    <StateView kind="error" message={error} />
  {:else if !searched && !searching}
    <StateView title={t('search.searchYourMedia')} message={t('search.enterTitleActorOrKeyword')} />
  {:else if searched && results.length === 0 && !searching}
    <StateView title={t('search.noResultsTitle')} message={t('search.tryDifferentTerm')}>
      <p class="t-small">{t('search.seasonsNote')}</p>
    </StateView>
  {:else}
    <MediaGrid items={results} label={t('search.title')} />
  {/if}
</div>

<style>
  .page {
    display: flex;
    flex-direction: column;
    gap: var(--space);
    padding: var(--space-1-5) var(--page-inset, var(--space));
  }

  .search {
    display: flex;
    flex-direction: column;
    gap: var(--space);
  }

  .search__field {
    display: block;
    max-width: 560px;
  }

  .search__filters {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-half);
  }

  .chip {
    min-height: var(--touch-target);
    padding: var(--space-half) var(--space-1-5);
    border-radius: var(--radius-pill);
    background: color-mix(in srgb, var(--text) 8%, transparent);
    color: var(--text-muted);
    font-weight: 600;
    font-size: var(--text-small-size);
    transition:
      background var(--dur-fast) var(--ease),
      color var(--dur-fast) var(--ease);
  }

  .chip--active {
    background: var(--text);
    color: var(--bg);
  }

  @media (hover: hover) {
    .chip:not(.chip--active):hover {
      background: color-mix(in srgb, var(--text) 16%, transparent);
      color: var(--text);
    }
  }
</style>
