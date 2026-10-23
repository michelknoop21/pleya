<script lang="ts">
  import { tick, untrack } from 'svelte';
  import { centralVisibleCard } from '$lib/util/visible-card';
  import LibraryAtmosphere from '$lib/components/LibraryAtmosphere.svelte';
  import { page } from '$app/state';
  import { replaceState } from '$app/navigation';

  import MediaGrid from '$lib/components/MediaGrid.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import Select from '$lib/components/Select.svelte';
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

  // Onder 900 staat `sub` op een eigen regel. Verschijnt het aantal pas als de
  // eerste pagina binnen is, dan springt het raster een regel omlaag; een
  // niet-afbrekende spatie houdt die regel vast zolang het aantal onbekend is.
  const RESERVED_LINE = '\u00A0';

  const sortOptions = SORT_OPTIONS.map((value) => ({ value, label: sortLabels[value] }));

  // Een schatting die groter is dan wat er staat is "ongeveer"; is de lijst
  // even groot of kleiner, dan telt het werkelijke aantal. Zo staat er nooit
  // "ongeveer 1 titel" boven een lijst met die ene titel.
  const countLabel = $derived.by(() => {
    const loaded = pager.items.length;
    const estimate = pager.totalEstimate;
    if (estimate !== null && estimate > loaded) {
      return plural('libraries.approximate', estimate, { count: formatCount(estimate) });
    }
    if (estimate === null && !pager.done) return undefined;
    if (loaded === 0) return undefined;
    return plural('libraries.itemCount', loaded, { count: formatCount(loaded) });
  });

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
  <PageHeader title={library?.title ?? t('libraries.title')} sub={countLabel ?? RESERVED_LINE}>
    {#snippet actions()}
      <div class="page__sort">
        <Select
          label={t('libraries.sort')}
          hideLabel
          value={sort}
          options={sortOptions}
          onchange={changeSort}
        />
      </div>
    {/snippet}
  </PageHeader>

  {#if pager.error && pager.items.length === 0}
    <StateView
      kind="error"
      message={describeError(pager.error)}
      onRetry={() => {
        pager = emptyPager();
        void fetchMore(new AbortController().signal);
      }}
    />
  {:else if pager.items.length === 0 && pager.cursor === null && !pager.done}
    <!--
      Niet op `pager.loading`: loadNext geeft de ladende toestand pas terug als
      het antwoord er al is, dus tijdens de eerste aanvraag stond hier "niets
      hier". Leeg zonder cursor en nog niet klaar is de eerste aanvraag; leeg en
      klaar is echt leeg. Een eerste pagina met nul items en een next_cursor
      valt door naar de lijst, want alleen daar staat de waarnemer die verder
      bladert; anders bleef het skelet staan.
    -->
    <SkeletonPage variant="grid" />
  {:else if pager.items.length === 0 && pager.done}
    <StateView title={t('states.emptyTitle')} />
  {:else}
    {#if pager.items.length > 0}
      <div bind:this={gridHost}>
        <MediaGrid items={pager.items} onHighlight={highlight} label={library?.title ?? t('libraries.title')} />
      </div>
    {/if}

    <div bind:this={sentinel} class="page__more">
      {#if pager.loading}
        <p class="page__note" aria-live="polite">{t('libraries.loading')}</p>
      {:else if pager.error}
        <p class="page__note" role="alert">{describeError(pager.error)}</p>
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
        <p class="page__note">{t('libraries.endOfList')}</p>
      {/if}
    </div>
  {/if}
</div>

<style>
  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .page {
    position: relative;
    isolation: isolate;
    padding: var(--page-top) var(--inset) var(--space-2);
  }

  /* Onder 900 vult de actie de regel (PageHeader); erboven houdt hij een
     vaste breedte naast de titel. */
  .page__sort {
    width: 100%;
  }

  @media (min-width: 900px) {
    .page__sort {
      width: 240px;
    }
  }

  .page__note {
    font-size: 13px;
    color: var(--ink-3);
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
