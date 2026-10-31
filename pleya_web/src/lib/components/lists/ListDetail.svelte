<!--
  Scherm 18 en de inhoud van een verzameling: kop met titel en samenvatting, de
  rijen, en voor de eigenaar herordenen als eigen modus. Herordenen vraagt de hele
  lijst, dus die wordt pas bij het binnengaan van de modus compleet opgehaald.

  De kop leest zijn getallen altijd opnieuw van de server na een wijziging: de
  speelduur is de som van de rijen, en die rekent de server per kijker uit.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import { goto } from '$app/navigation';
  import PageHeader from '../PageHeader.svelte';
  import StateView from '../StateView.svelte';
  import SkeletonPage from '../SkeletonPage.svelte';
  import ConfirmDialog from '../ConfirmDialog.svelte';
  import ActionMenu from './ActionMenu.svelte';
  import ListRows from './ListRows.svelte';
  import ListReorder from './ListReorder.svelte';
  import ListFormDialog from './ListFormDialog.svelte';
  import { collectionMeta, playlistMeta } from './listText';
  import type { Collection, Item, Playlist } from '../../api/types';
  import { ApiError, describeError } from '../../api/errors';
  import { listsApi, type ListKind } from '../../api/lists';
  import { playerHref } from '../../player/route';
  import { session } from '../../stores/session.svelte';
  import { emptyPager, loadNext } from '../../util/paging';
  import { t } from '../../i18n';

  let { kind, id }: { kind: ListKind; id: string } = $props();

  const PAGE = 100;
  let list = $state<Collection | Playlist | null>(null);
  let pager = $state(emptyPager<Item>());
  let loadError = $state<unknown>(null);
  let reordering = $state<Item[] | null>(null);
  let actionError = $state<string | null>(null);
  let editing = $state(false);
  let deleting = $state(false);
  let busy = $state(false);
  let signal: AbortSignal | undefined;

  const api = () => listsApi(session.client);
  const backHref = $derived(kind === 'collection' ? '/server/collections' : '/server/playlists');
  const collection = $derived(kind === 'collection' ? (list as Collection | null) : null);
  const canEdit = $derived(kind === 'playlist' ? list !== null : collection?.is_owner === true);
  const canPlay = $derived(kind === 'playlist' && pager.items.length > 0 && session.capabilities?.playback_plan === true);
  const missing = $derived(loadError instanceof ApiError && loadError.code === 'library.not_found');
  const sub = $derived(
    !list ? '' : kind === 'playlist'
      ? `${t('lists.playlistWord')} · ${playlistMeta(list as Playlist)}`
      : collectionMeta(list as Collection)
  );

  async function readList(activeSignal?: AbortSignal): Promise<void> {
    list = await (kind === 'collection' ? api().collection(id, activeSignal) : api().playlist(id, activeSignal));
  }

  async function more(): Promise<void> {
    if (!signal || signal.aborted || pager.loading || pager.done) return;
    const activeSignal = signal;
    const current = untrack(() => pager);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext<Item>(current, (cursor, requestSignal) =>
      api().items(kind, id, { limit: PAGE, ...(cursor ? { cursor } : {}) }, requestSignal), activeSignal);
    if (activeSignal.aborted) return;
    pager = next;
    if (restarted) await more();
  }

  async function open(activeSignal: AbortSignal): Promise<void> {
    list = null;
    loadError = null;
    pager = emptyPager<Item>();
    reordering = null;
    try {
      await readList(activeSignal);
      if (!activeSignal.aborted) await more();
    } catch (err) {
      if (!activeSignal.aborted) loadError = err;
    }
  }

  async function reload(): Promise<void> {
    pager = emptyPager<Item>();
    await Promise.all([readList(signal), more()]);
  }

  $effect(() => {
    void id;
    void session.client.sessionGeneration;
    const controller = new AbortController();
    signal = controller.signal;
    untrack(() => void open(controller.signal));
    return () => controller.abort();
  });

  async function startReorder(): Promise<void> {
    actionError = null;
    try {
      reordering = await api().allItems(kind, id, signal);
    } catch (err) {
      actionError = describeError(err);
    }
  }

  async function saveOrder(order: string[]): Promise<void> {
    await api().saveOrder(kind, id, order, signal);
    reordering = null;
    await reload();
  }

  async function removeItem(item: Item): Promise<void> {
    actionError = null;
    try {
      await api().removeItem(kind, id, item.id);
      await reload();
    } catch (err) {
      actionError = describeError(err);
    }
  }

  async function removeList(): Promise<void> {
    if (busy) return;
    busy = true;
    actionError = null;
    try {
      await api().remove(kind, id);
      deleting = false;
      await goto(backHref);
    } catch (err) {
      deleting = false;
      actionError = describeError(err);
    } finally {
      busy = false;
    }
  }

  const menu = $derived([
    { label: t('lists.edit'), onselect: () => (editing = true) },
    { label: t('lists.delete'), danger: true, onselect: () => (deleting = true) }
  ]);
</script>

<svelte:head><title>{list?.title ?? t('loading')} · {t('app.name')}</title></svelte:head>

<div class="page">
  {#if loadError}
    <PageHeader title={t(kind === 'collection' ? 'lists.collections' : 'lists.playlists')} />
    {#if missing}
      <StateView message={t('lists.notFound')}>
        {#snippet actions()}<a class="btn btn--ghost" href={backHref}>{t('lists.back')}</a>{/snippet}
      </StateView>
    {:else}
      <StateView kind="error" message={describeError(loadError)} onRetry={() => { if (signal) void open(signal); }} />
    {/if}
  {:else if !list}
    <SkeletonPage variant="compact" />
  {:else}
    <PageHeader title={list.title} sub={reordering ? t('lists.reorderTitle') : sub}>
      {#snippet actions()}
        {#if !reordering}
          {#if canPlay && pager.items[0]}
            <a class="btn" href={playerHref(pager.items[0].id, undefined, undefined, id)}>
              <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="currentColor"><path d="M7 4.5v15l13-7.5z" /></svg>
              {t('lists.playAll')}
            </a>
          {/if}
          {#if canEdit && pager.items.length > 1}
            <button type="button" class="btn btn--secondary" onclick={() => void startReorder()}>
              <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01" /></svg>
              {t('lists.reorder')}
            </button>
          {/if}
          {#if canEdit}<ActionMenu label={t('lists.more')} actions={menu} />{/if}
        {/if}
      {/snippet}
    </PageHeader>

    {#if actionError}<p class="error" role="alert">{actionError}</p>{/if}

    {#if reordering}
      <ListReorder items={reordering} onsave={saveOrder} oncancel={() => (reordering = null)} />
    {:else}
      {#if pager.items.length}
        <ListRows items={pager.items} numbered={kind === 'playlist'} onremove={canEdit ? (item) => void removeItem(item) : undefined} />
        {#if !pager.done && !pager.error}
          <button class="btn btn--secondary load" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
        {/if}
      {/if}
      {#if pager.loading && !pager.items.length}
        <SkeletonPage variant="compact" />
      {:else if pager.error}
        <StateView kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
      {:else if pager.done && !pager.items.length}
        <StateView title={t('lists.empty.items')} message={t('lists.empty.itemsBody')}>
          {#snippet actions()}<a class="btn btn--ghost" href={backHref}>{t('lists.back')}</a>{/snippet}
        </StateView>
      {/if}
      <p class="note">{t(kind === 'playlist' ? 'lists.playlistNote' : 'lists.hiddenNote')}</p>
    {/if}
  {/if}
</div>

{#if list}
  <ListFormDialog bind:open={editing} {kind} {list} onsaved={(saved) => { list = saved; }} />
  <ConfirmDialog
    bind:open={deleting}
    title={t('lists.deleteTitle', { title: list.title })}
    message={t('lists.deleteBody')}
    confirmLabel={t('lists.delete')}
    {busy}
    onconfirm={() => void removeList()}
  />
{/if}

<style>
  .page {
    padding: var(--page-top) var(--inset) var(--space-2);
  }

  .note {
    margin: 12px 0 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  .load {
    margin-top: 16px;
  }

  .error {
    margin: 0 0 12px;
    color: var(--danger-ink);
    font-size: 14px;
  }
</style>
