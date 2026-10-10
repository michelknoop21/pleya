<script lang="ts">
  import { tick, untrack } from 'svelte';
  import { centralVisibleCard } from '$lib/util/visible-card';
  import LibraryAtmosphere from '$lib/components/LibraryAtmosphere.svelte';
  import { page } from '$app/state';
  import { replaceState } from '$app/navigation';

  import MediaGrid from '$lib/components/MediaGrid.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import SkeletonPage from '$lib/components/SkeletonPage.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { describeError } from '$lib/api/errors';
  import { SORT_OPTIONS, isSortOption, type SortOption, type Item } from '$lib/api/types';
  import { emptyPager, loadNext, type PagerState } from '$lib/util/paging';
  import { formatCount } from '$lib/util/format';
  import { plural, t } from '$lib/i18n';

  const libraryId = $derived(page.params['id'] ?? '');
  const library = $derived(session.library(libraryId));

  const initialSort = page.url.searchParams.get('sort');
  let sort = $state<SortOption>(initialSort && isSortOption(initialSort) ? initialSort : 'title');
  let pager = $state<PagerState>(emptyPager());
  let sentinel = $state<HTMLDivElement | null>(null);
  let highlighted = $state<Item | null>(null);
  let gridHost = $state<HTMLDivElement | null>(null);
  let highlightTimer: ReturnType<typeof setTimeout> | undefined;

  function highlight(item: Item): void {
    clearTimeout(highlightTimer);
    highlightTimer = setTimeout(() => {
      if (pager.items.some((candidate) => candidate.id === item.id)) highlighted = item;
    }, 150);
  }

  function sampleVisible(): void {
    // Pointer/keyboard selection remains the desktop cursor.
    if (window.matchMedia('(hover: hover)').matches || !gridHost) return;
    const cards = Array.from(gridHost.querySelectorAll('li'), (card) => {
      const rect = card.getBoundingClientRect();
      return { left: rect.left, top: rect.top, width: rect.width, height: rect.height, id: card.dataset['itemId'] };
    });
    const selected = centralVisibleCard(cards, innerWidth, innerHeight);
    const nearest = pager.items.find((item) => item.id === selected?.id);
    if (nearest) highlight(nearest);
  }

  $effect(() => {
    const items = pager.items;
    const current = untrack(() => highlighted);
    highlighted = items.find((item) => item.id === current?.id) ?? items[0] ?? null;
    let active = true;
    void tick().then(() => { if (active) sampleVisible(); });
    return () => { active = false; clearTimeout(highlightTimer); };
  });

  const sortLabels: Record<SortOption, string> = {
    title: t('libraries.sort.title'),
    '-title': t('libraries.sort.-title'),
    added_at: t('libraries.sort.added_at'),
    '-added_at': t('libraries.sort.-added_at'),
    year: t('libraries.sort.year'),
    '-year': t('libraries.sort.-year')
  };

  /**
   * Haalt de volgende pagina op.
   *
   * `untrack` staat er niet voor de netheid. Deze functie leest `pager` en
   * schrijft hem daarna, en ze wordt vanuit een `$effect` aangeroepen. Zonder
   * die grens wordt het lezen een afhankelijkheid van dat effect, waarna het
   * schrijven het effect opnieuw laat lopen, dat de lijst weer leegmaakt en
   * opnieuw begint. Wat je daarvan ziet is een raster dat leeg blijft terwijl
   * de server gewoon antwoordt.
   */
  async function fetchMore(signal: AbortSignal): Promise<void> {
    const currentSort = sort;
    const current = untrack(() => pager);

    const { next, restarted } = await loadNext(
      current,
      (cursor, sig) =>
        session.client.libraryItems(libraryId, { cursor, sort: currentSort, limit: 100 }, sig),
      signal
    );
    if (signal.aborted || currentSort !== sort) return;
    pager = next;
    // Een cursor die bij een andere sortering hoorde is ongeldig geworden; de
    // lijst begint dan opnieuw en haalt meteen de eerste pagina op.
    if (restarted) await fetchMore(signal);
  }

  // Sorteren of van bibliotheek wisselen begint de lijst opnieuw: de cursor
  // hoort bij precies één sortering.
  $effect(() => {
    void libraryId;
    void sort;
    const controller = new AbortController();
    untrack(() => {
      pager = emptyPager();
      void fetchMore(controller.signal);
    });
    return () => controller.abort();
  });

  // Oneindig doorbladeren met een waarnemer onder de lijst; de knop eronder
  // blijft bestaan zodat het ook zonder waarnemer en met toetsenbord werkt.
  $effect(() => {
    if (!sentinel || typeof IntersectionObserver !== 'function') return;
    const controller = new AbortController();
    const observer = new IntersectionObserver(
      (entries) => {
        const state = untrack(() => pager);
        for (const entry of entries) {
          if (entry.isIntersecting && !state.loading && !state.done) {
            void fetchMore(controller.signal);
          }
        }
      },
      { rootMargin: '600px' }
    );
    observer.observe(sentinel);
    return () => {
      observer.disconnect();
      controller.abort();
    };
  });

  function changeSort(value: string): void {
    if (!isSortOption(value)) return;
    sort = value;
    const url = new URL(page.url);
    url.searchParams.set('sort', value);
    replaceState(url, page.state);
  }
</script>

<svelte:head><title>{library?.title ?? t('libraries.title')} · {t('app.name')}</title></svelte:head>

<svelte:window onscroll={sampleVisible} onresize={sampleVisible} />

<div class="page">
  <LibraryAtmosphere artworkId={highlighted?.artwork?.backdrop_id ?? highlighted?.artwork?.poster_id} />
  <header class="page__header">
    <div class="page__heading">
      <h1 class="t-headline">{library?.title ?? t('libraries.title')}</h1>
      {#if pager.totalEstimate !== null}
        <p class="t-small">
          {plural('libraries.approximate', pager.totalEstimate, {
            count: formatCount(pager.totalEstimate)
          })}
        </p>
      {/if}
    </div>

    <label class="page__sort">
      <span class="visually-hidden">{t('libraries.sort')}</span>
      <select
        class="page__select"
        value={sort}
        onchange={(event) => changeSort(event.currentTarget.value)}
      >
        {#each SORT_OPTIONS as option (option)}
          <option value={option}>{sortLabels[option]}</option>
        {/each}
      </select>
    </label>
  </header>

  {#if pager.error && pager.items.length === 0}
    <StateView
      kind="error"
      message={describeError(pager.error)}
      onRetry={() => {
        pager = emptyPager();
        void fetchMore(new AbortController().signal);
      }}
    />
  {:else if pager.items.length === 0 && !pager.done}
    <!--
      Niet op `pager.loading`: loadNext geeft de ladende toestand pas terug als
      het antwoord er al is, dus tijdens de eerste aanvraag stond hier "niets
      hier". Leeg en nog niet klaar is laden; leeg en klaar is echt leeg.
    -->
    <SkeletonPage variant="grid" />
  {:else if pager.items.length === 0}
    <StateView title={t('states.emptyTitle')} />
  {:else}
    <div bind:this={gridHost}>
      <MediaGrid items={pager.items} onHighlight={highlight} label={library?.title ?? t('libraries.title')} />
    </div>

    <div bind:this={sentinel} class="page__more">
      {#if pager.loading}
        <p class="t-small" aria-live="polite">{t('libraries.loading')}</p>
      {:else if pager.error}
        <p class="t-small" role="alert">{describeError(pager.error)}</p>
        <button
          type="button"
          class="btn btn--secondary"
          onclick={() => void fetchMore(new AbortController().signal)}
        >
          {t('common.retry')}
        </button>
      {:else if !pager.done}
        <button
          type="button"
          class="btn btn--secondary"
          onclick={() => void fetchMore(new AbortController().signal)}
        >
          {t('libraries.loadMore')}
        </button>
      {:else}
        <p class="t-small">{t('libraries.endOfList')}</p>
      {/if}
    </div>
  {/if}
</div>

<style>
  .page {
    position: relative;
    isolation: isolate;
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
    padding: var(--space-1-5) var(--page-inset, var(--space));
  }

  .page__header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: var(--space);
  }

  .page__heading {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .page__select {
    min-height: var(--touch-target);
    padding: var(--space-half) var(--space);
    border-radius: var(--radius-md);
    border: 0;
    background: color-mix(in srgb, var(--surface) 78%, transparent);
    backdrop-filter: blur(24px);
    color: var(--text);
  }

  .page__more {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-half);
    padding: var(--space-2) 0;
    min-height: 64px;
  }
</style>
