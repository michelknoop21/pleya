<script lang="ts">
  import { untrack } from 'svelte';
  import Artwork from '#lib/components/Artwork.svelte';
  import Chips from '#lib/components/Chips.svelte';
  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import Panel from '#lib/components/Panel.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import StatusPill from '#lib/components/StatusPill.svelte';
  import { personalApi } from '#lib/api/personal.js';
  import { describeError } from '#lib/api/errors.js';
  import type { HistoryEntry, Item } from '#lib/api/types.js';
  import { session } from '#lib/stores/session.svelte.js';
  import { formatCount } from '#lib/util/format.js';
  import { groupByDay, historyLine, historyPercent, ratedItems } from '#lib/util/history.js';
  import { emptyPager, loadNext } from '#lib/util/paging.js';
  import { t } from '#lib/i18n/index.js';

  // `GET /history` kent geen soortfilter en boeken staan er niet in; de chips
  // filteren dus wat er geladen is, en daarom staat "Meer laden" er altijd onder.
  type Filter = 'all' | 'movie' | 'episode';
  const FILTERS: { id: Filter; label: string }[] = [
    { id: 'all', label: t('search.filters.all') },
    { id: 'movie', label: t('search.filters.movies') },
    { id: 'episode', label: t('search.filters.episodes') }
  ];

  let filter = $state<Filter>('all');
  let pager = $state(emptyPager<HistoryEntry>());
  let favorites = $state<Item[]>([]);
  let favoriteTotal = $state<number | null>(null);
  let signal: AbortSignal | undefined;
  let api: ReturnType<typeof personalApi>;

  const visible = $derived(filter === 'all' ? pager.items : pager.items.filter((entry) => entry.item.kind === filter));
  const days = $derived(groupByDay(visible));
  const rated = $derived(
    session.capabilities?.ratings ? ratedItems([...pager.items.map((entry) => entry.item), ...favorites]).slice(0, 6) : []
  );

  async function more(): Promise<void> {
    if (!signal || signal.aborted || pager.loading || pager.done) return;
    const activeSignal = signal;
    const current = untrack(() => pager);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext<HistoryEntry>(current,
      (cursor, requestSignal) => api.history({ limit: 50, ...(cursor ? { cursor } : {}) }, requestSignal), activeSignal);
    if (activeSignal.aborted) return;
    pager = next;
    if (restarted) await more();
  }

  // Het paneel is een aanvulling op de geschiedenis: een fout hier laat de
  // regels staan en het paneel weg.
  async function loadFavorites(requestSignal: AbortSignal): Promise<void> {
    try {
      const page = await api.favorites({ limit: 6 }, requestSignal);
      if (requestSignal.aborted) return;
      favorites = page.items;
      favoriteTotal = page.total_estimate ?? null;
    } catch {
      if (!requestSignal.aborted) favorites = [];
    }
  }

  $effect(() => {
    const allowed = session.capabilities?.history;
    const withFavorites = session.capabilities?.favorites;
    void session.client.sessionGeneration;
    pager = emptyPager<HistoryEntry>();
    favorites = [];
    favoriteTotal = null;
    if (!allowed) return;
    const controller = new AbortController();
    signal = controller.signal;
    api = personalApi(session.client);
    untrack(() => {
      void more();
      if (withFavorites) void loadFavorites(controller.signal);
    });
    return () => controller.abort();
  });
</script>

<svelte:head><title>{t('history.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={t('history.title')} />
  <a class="btn btn--ghost" href="/server">{t('nav.my')}</a>
  {#if session.capabilities?.history}
    <div class="layout">
      <div class="main">
        {#if pager.items.length}
          <Chips label={t('history.filter')} options={FILTERS} selected={[filter]} onchange={(selected) => (filter = selected[0] as Filter)} />
        {/if}
        {#each days as day (day.key)}
          <section aria-labelledby="day-{day.key}">
            <h2 class="day" id="day-{day.key}">{day.label}</h2>
            <ul class="rows">
              {#each day.entries as entry (entry.id)}
                {@const percent = historyPercent(entry)}
                <li>
                  <a class="row" href="/items/{entry.item.id}">
                    <span class="row__art"><Artwork artworkId={entry.item.artwork?.poster_id ?? entry.item.artwork?.backdrop_id} alt="" shape="free" /></span>
                    <span class="row__text">
                      <span class="row__title">{entry.item.title}</span>
                      <span class="row__meta">{historyLine(entry)}</span>
                    </span>
                    {#if entry.completed}
                      <StatusPill tone="ok" label={t('history.watched')} />
                    {:else if percent !== null}
                      <StatusPill label="{percent}%" />
                    {/if}
                  </a>
                </li>
              {/each}
            </ul>
          </section>
        {/each}
        {#if pager.loading && !pager.items.length}<SkeletonPage variant="grid" />
        {:else if pager.error}<StateView kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
        {:else if pager.done && !pager.items.length}<StateView title={t('history.empty')} message={t('history.emptyBody')} />
        {:else if pager.items.length && !visible.length}<StateView compact title={t('history.emptyFilter')} />{/if}
        {#if pager.items.length && !pager.done && !pager.error}
          <button class="btn btn--secondary" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
        {/if}
      </div>

      {#if favorites.length || rated.length}
        <aside class="side">
          {#if favorites.length}
            <Panel level={2}>
              {#snippet title()}{t('personal.favorites')}{/snippet}
              {#snippet actions()}
                <a class="side__all" href="/server/favorites">{favoriteTotal === null ? t('history.favoritesLink') : t('history.allFavorites', { count: formatCount(favoriteTotal) })}</a>
              {/snippet}
              <MediaGrid items={favorites} label={t('personal.favorites')} />
            </Panel>
          {/if}
          {#if rated.length}
            <Panel level={2}>
              {#snippet title()}{t('history.ratings')}{/snippet}
              <ul class="rated">
                {#each rated as item (item.id)}
                  <li>
                    <a href="/items/{item.id}"><span class="row__title">{item.title}</span></a>
                    <StatusPill label={t('history.ratingScore', { rating: item.rating ?? 0 })} />
                  </li>
                {/each}
              </ul>
              <p class="note">{t('history.ratingsNote')}</p>
            </Panel>
          {/if}
        </aside>
      {/if}
    </div>
  {:else}
    <StateView message={t('history.unavailable')} />
  {/if}
</div>

<style>
  .page { padding: var(--page-top) var(--inset) var(--space-2); }
  .layout { display: grid; grid-template-columns: minmax(0, 1fr); gap: var(--space-1-5); margin-top: var(--space); }
  .main, .side { display: flex; flex-direction: column; gap: var(--space); min-width: 0; }
  .day { margin: 0 0 8px; font-size: 13px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--ink-2); }
  .rows { list-style: none; margin: 0; padding: 0; overflow: hidden; border-radius: var(--radius-md); background: var(--panel); }
  .rows li + li { border-top: 1px solid var(--hairline); }
  .row { display: flex; align-items: center; gap: 14px; min-height: var(--touch-target); padding: 12px 18px; color: inherit; text-decoration: none; }
  .row:focus-visible { outline-offset: -2px; }
  .row__art { flex: none; width: 40px; aspect-ratio: 2 / 3; overflow: hidden; border-radius: 6px; }
  .row__art :global(.artwork) { height: 100%; }
  .row__text { display: flex; flex: 1; flex-direction: column; gap: 2px; min-width: 0; }
  .row__title { font-size: 15px; font-weight: 600; overflow-wrap: anywhere; color: var(--ink); }
  .row__meta { font-size: 13px; color: var(--ink-2); overflow-wrap: anywhere; }
  .side__all { display: inline-flex; align-items: center; min-height: var(--touch-target); font-size: 13px; color: var(--ink-2); }
  .rated { display: flex; flex-direction: column; list-style: none; margin: 0; padding: 0; }
  .rated li { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: var(--touch-target); }
  .rated a { min-width: 0; }
  .note { margin: 8px 0 0; font-size: 13px; color: var(--ink-2); }
  @media (min-width: 900px) {
    .layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); align-items: start; }
  }
</style>
