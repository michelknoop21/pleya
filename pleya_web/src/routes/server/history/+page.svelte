<script lang="ts">
  import { untrack } from 'svelte';
  import Artwork from '#lib/components/Artwork.svelte';
  import Chips from '#lib/components/Chips.svelte';
  import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
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

  // Met `personal_data` filtert de server. Een oudere server negeert `kind` stil,
  // dus daar filteren de chips wat er geladen is en staat "Meer laden" eronder.
  type Filter = 'all' | 'movie' | 'episode';
  type Pending = { kind: 'one'; entry: HistoryEntry } | { kind: 'all' };
  const FILTERS: { id: Filter; label: string }[] = [
    { id: 'all', label: t('search.filters.all') },
    { id: 'movie', label: t('search.filters.movies') },
    { id: 'episode', label: t('search.filters.episodes') }
  ];
  const RATINGS_PAGE = 6;

  let filter = $state<Filter>('all');
  let pager = $state(emptyPager<HistoryEntry>());
  let favorites = $state<Item[]>([]);
  let favoriteTotal = $state<number | null>(null);
  let ratingPager = $state(emptyPager<Item>());
  let pending = $state<Pending | null>(null);
  let removing = $state(false);
  let removeError = $state<string | null>(null);
  let reload = $state(0);
  let signal: AbortSignal | undefined;
  let panelSignal: AbortSignal | undefined;
  let api: ReturnType<typeof personalApi>;
  let panelApi: ReturnType<typeof personalApi>;

  const managed = $derived(session.capabilities?.personal_data === true);
  const serverKind = $derived(managed && filter !== 'all' ? filter : null);
  const visible = $derived(filter === 'all' || managed ? pager.items : pager.items.filter((entry) => entry.item.kind === filter));
  const days = $derived(groupByDay(visible));
  const rated = $derived.by(() => {
    if (!session.capabilities?.ratings) return [];
    if (managed) return ratingPager.items;
    return ratedItems([...pager.items.map((entry) => entry.item), ...favorites]).slice(0, RATINGS_PAGE);
  });

  async function more(): Promise<void> {
    if (!signal || signal.aborted || pager.loading || pager.done) return;
    const activeSignal = signal;
    const current = untrack(() => pager);
    const kind = untrack(() => serverKind);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext<HistoryEntry>(current,
      (cursor, requestSignal) => api.history({ limit: 50, ...(cursor ? { cursor } : {}), ...(kind ? { kind } : {}) }, requestSignal), activeSignal);
    if (activeSignal.aborted) return;
    pager = next;
    if (restarted) await more();
  }

  async function moreRatings(): Promise<void> {
    if (!panelSignal || panelSignal.aborted || ratingPager.loading || ratingPager.done) return;
    const activeSignal = panelSignal;
    const current = untrack(() => ratingPager);
    ratingPager = { ...current, loading: true, error: null };
    const { next } = await loadNext<Item>(current,
      (cursor, requestSignal) => panelApi.ratings({ limit: RATINGS_PAGE, ...(cursor ? { cursor } : {}) }, requestSignal), activeSignal);
    if (!activeSignal.aborted) ratingPager = next;
  }

  // Het paneel is een aanvulling op de geschiedenis: een fout hier laat de
  // regels staan en het paneel weg.
  async function loadFavorites(requestSignal: AbortSignal): Promise<void> {
    try {
      const page = await panelApi.favorites({ limit: 6 }, requestSignal);
      if (requestSignal.aborted) return;
      favorites = page.items;
      favoriteTotal = page.total_estimate ?? null;
    } catch {
      if (!requestSignal.aborted) favorites = [];
    }
  }

  async function confirmRemove(): Promise<void> {
    if (!pending) return;
    const target = pending;
    removing = true;
    removeError = null;
    try {
      if (target.kind === 'all') {
        await api.clearHistory();
        pending = null;
        reload++;
      } else {
        await api.deleteHistoryEntry(target.entry.id);
        pending = null;
        pager = { ...pager, items: pager.items.filter((entry) => entry.id !== target.entry.id) };
        if (!pager.items.length) await more();
      }
    } catch (err) {
      removeError = describeError(err);
    } finally {
      removing = false;
    }
  }

  // Een andere soort is een andere lijst: de cursor hoort bij de vorige, en een
  // antwoord dat nog onderweg is mag de nieuwe lijst niet meer vullen.
  $effect(() => {
    const allowed = session.capabilities?.history;
    void session.client.sessionGeneration;
    void serverKind;
    void reload;
    pager = emptyPager<HistoryEntry>();
    pending = null;
    if (!allowed) return;
    const controller = new AbortController();
    signal = controller.signal;
    api = personalApi(session.client);
    untrack(() => void more());
    return () => controller.abort();
  });

  $effect(() => {
    const allowed = session.capabilities?.history;
    const withFavorites = session.capabilities?.favorites;
    const withRatings = session.capabilities?.ratings === true && managed;
    void session.client.sessionGeneration;
    favorites = [];
    favoriteTotal = null;
    ratingPager = emptyPager<Item>();
    if (!allowed) return;
    const controller = new AbortController();
    panelSignal = controller.signal;
    panelApi = personalApi(session.client);
    untrack(() => {
      if (withFavorites) void loadFavorites(controller.signal);
      if (withRatings) void moreRatings();
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
        {#if pager.items.length || filter !== 'all'}
          <Chips label={t('history.filter')} options={FILTERS} selected={[filter]} onchange={(selected) => (filter = selected[0] as Filter)} />
        {/if}
        {#each days as day (day.key)}
          <section aria-labelledby="day-{day.key}">
            <h2 class="day" id="day-{day.key}">{day.label}</h2>
            <ul class="rows">
              {#each day.entries as entry (entry.id)}
                {@const percent = historyPercent(entry)}
                <li class="line">
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
                  {#if managed}
                    <button type="button" class="icon" disabled={pager.loading} aria-label={t('history.remove', { title: entry.item.title })} onclick={() => { removeError = null; pending = { kind: 'one', entry }; }}>
                      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M4 7h16M9 7V4h6v3m3 0-1 13H7L6 7m4 4v5m4-5v5" /></svg>
                    </button>
                  {/if}
                </li>
              {/each}
            </ul>
          </section>
        {/each}
        {#if pager.loading && !pager.items.length}<SkeletonPage variant="grid" />
        {:else if pager.error}<StateView kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
        {:else if pager.done && !pager.items.length && serverKind}<StateView compact title={t('history.emptyKind')} />
        {:else if pager.done && !pager.items.length}<StateView title={t('history.empty')} message={t('history.emptyBody')} />
        {:else if pager.items.length && !visible.length}<StateView compact title={t('history.emptyFilter')} />{/if}
        {#if pager.items.length && !pager.done && !pager.error}
          <button class="btn btn--secondary" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
        {/if}
        {#if managed && (pager.items.length || serverKind)}
          <button type="button" class="btn btn--ghost" onclick={() => { removeError = null; pending = { kind: 'all' }; }}>{t('history.clear')}</button>
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
              {#if !managed}<p class="note">{t('history.ratingsNote')}</p>{/if}
              {#if managed && !ratingPager.done && !ratingPager.error}
                <button class="btn btn--secondary" disabled={ratingPager.loading} onclick={() => void moreRatings()}>{t('libraries.loadMore')}</button>
              {/if}
            </Panel>
          {/if}
        </aside>
      {/if}
    </div>
  {:else}
    <StateView message={t('history.unavailable')} />
  {/if}
</div>

<ConfirmDialog
  open={pending !== null}
  title={pending?.kind === 'all' ? t('history.clearTitle') : t('history.removeTitle')}
  message={pending?.kind === 'one' ? t('history.removeBody', { title: pending.entry.item.title }) : t('history.clearBody')}
  confirmLabel={pending?.kind === 'all' ? t('history.clearConfirm') : t('history.removeConfirm')}
  danger
  busy={removing}
  onconfirm={() => void confirmRemove()}
  oncancel={() => (pending = null)}
>
  {#if removeError}<p class="note" role="alert">{removeError}</p>{/if}
</ConfirmDialog>

<style>
  .page { padding: var(--page-top) var(--inset) var(--space-2); }
  .layout { display: grid; grid-template-columns: minmax(0, 1fr); gap: var(--space-1-5); margin-top: var(--space); }
  .main, .side { display: flex; flex-direction: column; gap: var(--space); min-width: 0; }
  .day { margin: 0 0 8px; font-size: 13px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--ink-2); }
  .rows { list-style: none; margin: 0; padding: 0; overflow: hidden; border-radius: var(--radius-md); background: var(--panel); }
  .rows li + li { border-top: 1px solid var(--hairline); }
  .line { display: flex; align-items: center; }
  .row { display: flex; flex: 1; align-items: center; gap: 14px; min-width: 0; min-height: var(--touch-target); padding: 12px 18px; color: inherit; text-decoration: none; }
  .icon { flex: none; display: inline-flex; align-items: center; justify-content: center; width: var(--touch-target); height: var(--touch-target); margin-right: 8px; border: 0; border-radius: 50%; background: transparent; color: var(--ink-2); cursor: pointer; }
  .icon:disabled { opacity: 0.5; cursor: default; }
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
