<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';

  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import Chips from '#lib/components/Chips.svelte';
  import Field from '#lib/components/Field.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import { emptyPager, loadNext } from '#lib/util/paging.js';
  import type { ItemKind } from '#lib/api/types.js';
  import { t } from '#lib/i18n/index.js';

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

  const SECTIONS: { kind: ItemKind; label: string }[] = [
    { kind: 'movie', label: t('search.filters.movies') },
    { kind: 'show', label: t('search.filters.shows') },
    { kind: 'episode', label: t('search.filters.episodes') }
  ];
  const INPUT_ID = 'search-query';

  let query = $state(page.url.searchParams.get('q') ?? '');
  let filter = $state<'all' | ItemKind>('all');
  let pager = $state(emptyPager());
  let searching = $state(false);
  let searched = $state(false);
  // De server levert geen "bedoelde je"; dit is de laatste term met treffers.
  let lastHit = $state<string | null>(null);
  let activeTerm = $state('');
  let activeKind = $state<'all' | ItemKind>('all');
  let activeSignal: AbortSignal | undefined;
  let retry = $state(0);

  const sections = $derived(
    SECTIONS.map((section) => ({ ...section, items: pager.items.filter((item) => item.kind === section.kind) }))
      .filter((section) => section.items.length > 0)
  );
  const countSuffix = $derived(pager.done ? '' : '+');
  const hasFilms = $derived(session.libraries.some((library) => library.kind === 'movies'));

  const pageOf = (term: string, kind: 'all' | ItemKind) => (cursor: string | undefined, signal: AbortSignal) =>
    session.client.search({ q: term, ...(kind === 'all' ? {} : { kind }), limit: 100, ...(cursor ? { cursor } : {}) }, signal);

  async function run(term: string, kind: 'all' | ItemKind, signal: AbortSignal): Promise<void> {
    if (term.length === 0) {
      pager = emptyPager();
      searched = false;
      return;
    }
    searching = true;
    const { next } = await loadNext(emptyPager(), pageOf(term, kind), signal);
    if (signal.aborted) return;
    pager = next;
    activeTerm = term;
    activeKind = kind;
    activeSignal = signal;
    searched = !next.error;
    searching = false;
    if (next.items.length > 0) lastHit = term;
  }

  async function more(): Promise<void> {
    const signal = activeSignal;
    if (!signal || signal.aborted || pager.loading || pager.done) return;
    const current = untrack(() => pager);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext(current, pageOf(activeTerm, activeKind), signal);
    if (signal.aborted) return;
    pager = next;
    if (restarted) await more();
  }

  function clear(): void {
    query = '';
    document.getElementById(INPUT_ID)?.focus();
  }

  // Debounce plus annulering: elke toetsaanslag breekt de vorige aanvraag af,
  // zodat een traag antwoord van drie letters geleden niet over een nieuwer
  // resultaat heen valt.
  $effect(() => {
    const term = query.trim();
    const kind = filter;
    void retry;
    const controller = new AbortController();
    const timer = setTimeout(() => void run(term, kind, controller.signal), 250);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  });

  // `page.url` blijft bij shallow routing staan en `page.state` wordt elke keer
  // een nieuw object: wie die hier leest, maakt een lus die het tabblad bevriest.
  $effect(() => {
    const term = query.trim();
    untrack(() => {
      const url = new URL(location.href);
      if (term) url.searchParams.set('q', term);
      else url.searchParams.delete('q');
      if (url.href !== location.href) void goto(url, { shallow: true, replace: true, state: page.state });
    });
  });
</script>

<svelte:head><title>{t('search.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={t('search.title')} />

  <form class="search" role="search" onsubmit={(event) => event.preventDefault()}>
    <div class="search__field">
      <Field
        id={INPUT_ID}
        type="search"
        label={t('search.hint')}
        hideLabel
        placeholder={t('search.hint')}
        autocomplete="off"
        bind:value={query}
      />
      {#if query}
        <button type="button" class="search__clear" aria-label={t('search.clear')} onclick={clear}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M6 6l12 12M18 6L6 18" /></svg>
        </button>
      {/if}
    </div>

    <Chips
      variant="outline"
      label={t('search.filters.label')}
      options={FILTERS}
      selected={[filter]}
      onchange={(selected) => (filter = selected[0] as 'all' | ItemKind)}
    />
  </form>

  <p class="search__status" aria-live="polite">
    {#if searching}
      {t('loading')}
    {:else if searched}
      {t('search.resultsFor', { query: query.trim() })}
    {/if}
  </p>

  {#if pager.error && !pager.items.length}
    <StateView kind="error" message={describeError(pager.error)} onRetry={() => retry++} />
  {:else if !searched && !searching}
    <StateView title={t('search.searchYourMedia')} message={t('search.enterTitleActorOrKeyword')} />
  {:else if searched && pager.items.length === 0 && !searching}
    <StateView title={t('search.nothingFor', { query: query.trim() })} message={t('search.emptyBody')}>
      {#snippet icon()}
        <svg viewBox="0 0 24 24" width="40" height="40" aria-hidden="true" focusable="false"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" /></g></svg>
      {/snippet}
      {#snippet actions()}
        {#if lastHit && lastHit !== query.trim()}
          {@const term = lastHit}
          <button type="button" class="btn btn--secondary" onclick={() => (query = term)}>{t('search.didYouMean', { query: term })}</button>
        {/if}
        <a class="btn btn--secondary" href={hasFilms ? '/films' : '/libraries'}>{t(hasFilms ? 'search.browseFilms' : 'search.browseCatalog')}</a>
      {/snippet}
      <p>{t('search.seasonsNote')}</p>
    </StateView>
  {:else}
    {#each sections as section (section.kind)}
      <section class="section" aria-labelledby="results-{section.kind}">
        <h2 class="section__h" id="results-{section.kind}">{section.label} <span class="section__count">{section.items.length}{countSuffix}</span></h2>
        <MediaGrid items={section.items} label={section.label} />
      </section>
    {/each}
    {#if pager.error}
      <StateView compact kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
    {:else if pager.items.length > 0 && !pager.done}
      <button type="button" class="btn btn--secondary" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
    {/if}
  {/if}
</div>

<style>
  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .page {
    display: flex;
    flex-direction: column;
    gap: var(--space);
    padding: 8px var(--inset) var(--space-2);
  }

  .search {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
  }

  .search__field {
    position: relative;
  }

  .search__field :global(input::-webkit-search-cancel-button) {
    display: none;
  }

  .search__clear {
    position: absolute;
    inset-block: 0;
    inset-inline-end: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: var(--touch-target);
    border: 0;
    background: transparent;
    color: var(--ink-2);
    cursor: pointer;
  }

  .section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  /* web.css .section-h: 20/700, onder 900 18. */
  .section__h {
    margin: 0;
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .section__count {
    font-size: 15px;
    font-weight: 400;
    color: var(--ink-3);
  }

  @media (max-width: 899px) {
    .section__h {
      font-size: 18px;
    }
  }

  .search__status {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  /* De live region blijft in de DOM (een schermlezer meldt anders de eerste
     tekst niet), maar een lege regel mag de kolomafstand niet verdubbelen. */
  .search__status:empty {
    margin-top: calc(-1 * var(--space));
  }
</style>
