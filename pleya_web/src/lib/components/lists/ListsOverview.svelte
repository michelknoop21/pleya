<!--
  Scherm 17: verzamelingen en afspeellijsten onder Mijn Pleya. Links het segment,
  rechts de sortering, zodat een filter niet op een sortering lijkt. Het segment
  is een echte navigatie tussen twee routes, dus een terugknop en een link werken.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import { goto } from '$app/navigation';
  import PageHeader from '../PageHeader.svelte';
  import Chips from '../Chips.svelte';
  import StateView from '../StateView.svelte';
  import SkeletonPage from '../SkeletonPage.svelte';
  import ListTile from './ListTile.svelte';
  import ListFormDialog from './ListFormDialog.svelte';
  import { collectionMeta, playlistMeta } from './listText';
  import type { Collection, Playlist } from '../../api/types';
  import { listsApi, type ListKind } from '../../api/lists';
  import { describeError } from '../../api/errors';
  import { session } from '../../stores/session.svelte';
  import { emptyPager, loadNext } from '../../util/paging';
  import { t } from '../../i18n';

  type Row = Collection | Playlist;
  type SortKey = '-updated_at' | 'title';

  let { kind }: { kind: ListKind } = $props();

  const PAGE = 48;
  const available = $derived(session.capabilities?.[kind === 'collection' ? 'collections' : 'playlists'] === true);
  const other = $derived<ListKind>(kind === 'collection' ? 'playlist' : 'collection');
  const otherAvailable = $derived(session.capabilities?.[other === 'collection' ? 'collections' : 'playlists'] === true);
  const heading = $derived(t(kind === 'collection' ? 'lists.collections' : 'lists.playlists'));

  let sort = $state<SortKey>('-updated_at');
  let pager = $state(emptyPager<Row>());
  let otherCount = $state<number | undefined>(undefined);
  let creating = $state(false);
  let signal: AbortSignal | undefined;

  function fetchPage(listKind: ListKind, query: { sort: SortKey; limit: number; cursor?: string }, requestSignal?: AbortSignal) {
    const api = listsApi(session.client);
    return listKind === 'collection' ? api.collections(query, requestSignal) : api.playlists(query, requestSignal);
  }

  async function more(): Promise<void> {
    if (!signal || signal.aborted || pager.loading || pager.done) return;
    const activeSignal = signal;
    const current = untrack(() => pager);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext<Row>(current, (cursor, requestSignal) =>
      fetchPage(kind, { sort, limit: PAGE, ...(cursor ? { cursor } : {}) }, requestSignal), activeSignal);
    if (activeSignal.aborted) return;
    pager = next;
    if (restarted) await more();
  }

  async function countOther(requestSignal: AbortSignal): Promise<void> {
    try {
      const page = await fetchPage(other, { sort: '-updated_at', limit: PAGE }, requestSignal);
      if (!requestSignal.aborted) otherCount = page.next_cursor ? undefined : page.items.length;
    } catch {
      // Het getal op de chip is een extra; zonder blijft de chip werken.
    }
  }

  $effect(() => {
    const allowed = available;
    void sort;
    void session.client.sessionGeneration;
    pager = emptyPager<Row>();
    if (!allowed) return;
    const controller = new AbortController();
    signal = controller.signal;
    untrack(() => {
      void more();
      if (otherAvailable) void countOther(controller.signal);
    });
    return () => controller.abort();
  });

  const hrefFor = (listKind: ListKind) => (listKind === 'collection' ? '/server/collections' : '/server/playlists');
  const segment = $derived([
    ...(session.capabilities?.collections ? [{ id: 'collection', label: t('lists.collections'), count: kind === 'collection' ? (pager.done ? pager.items.length : undefined) : otherCount }] : []),
    ...(session.capabilities?.playlists ? [{ id: 'playlist', label: t('lists.playlists'), count: kind === 'playlist' ? (pager.done ? pager.items.length : undefined) : otherCount }] : [])
  ]);
  const sortLabel = $derived(t(sort === 'title' ? 'lists.sortTitle' : 'lists.sortUpdated'));
</script>

<svelte:head><title>{heading} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={heading}>
    {#snippet actions()}
      {#if available}
        <button type="button" class="btn" onclick={() => (creating = true)}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg>
          {t(kind === 'collection' ? 'lists.newCollection' : 'lists.newPlaylist')}
        </button>
      {/if}
    {/snippet}
  </PageHeader>

  {#if available}
    <div class="bar">
      <Chips label={t('lists.kind')} options={segment} selected={[kind]} onchange={(next) => { const chosen = next[0] as ListKind | undefined; if (chosen) void goto(hrefFor(chosen)); }} />
      <button
        type="button"
        class="btn btn--secondary btn--sm sort"
        aria-label="{t('lists.sort')}: {sortLabel}"
        onclick={() => (sort = sort === 'title' ? '-updated_at' : 'title')}
      >
        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4v16M7 20l-3-3M7 20l3-3M17 20V4M17 4l-3 3M17 4l3 3" /></svg>
        {sortLabel}
      </button>
    </div>

    {#if pager.items.length}
      <ul class="tiles" aria-label={heading}>
        {#each pager.items as row (row.id)}
          <li>
            {#if kind === 'collection'}
              <ListTile href="/server/collections/{row.id}" title={row.title} meta={collectionMeta(row as Collection)} artwork={row.artwork} />
            {:else}
              <ListTile href="/server/playlists/{row.id}" title={row.title} meta={playlistMeta(row as Playlist)} artwork={row.artwork} />
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
    {#if pager.loading && !pager.items.length}
      <SkeletonPage variant="grid" />
    {:else if pager.error}
      <StateView kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
    {:else if pager.done && !pager.items.length}
      <StateView
        title={t(kind === 'collection' ? 'lists.empty.collections' : 'lists.empty.playlists')}
        message={t(kind === 'collection' ? 'lists.empty.collectionsBody' : 'lists.empty.playlistsBody')}
      >
        {#snippet actions()}
          <button type="button" class="btn" onclick={() => (creating = true)}>{t(kind === 'collection' ? 'lists.newCollection' : 'lists.newPlaylist')}</button>
          <a class="btn btn--ghost" href="/server">{t('nav.my')}</a>
        {/snippet}
      </StateView>
    {/if}
    {#if pager.items.length && !pager.done && !pager.error}
      <button class="btn btn--secondary load" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
    {/if}
  {:else}
    <StateView message={t('lists.unavailable')}>
      {#snippet actions()}<a class="btn btn--ghost" href="/server">{t('nav.my')}</a>{/snippet}
    </StateView>
  {/if}
</div>

<ListFormDialog bind:open={creating} {kind} onsaved={(list) => void goto(`${hrefFor(kind)}/${list.id}`)} />

<style>
  .page {
    padding: var(--page-top) var(--inset) var(--space-2);
  }

  .bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px 16px;
    margin-bottom: 14px;
  }

  .sort {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(232px, 1fr));
    gap: 22px 16px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .load {
    margin-top: 20px;
  }

  @media (max-width: 899px) {
    .tiles {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 18px 12px;
    }
  }
</style>
