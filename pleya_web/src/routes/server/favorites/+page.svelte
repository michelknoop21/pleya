<script lang="ts">
  import { untrack } from 'svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { personalApi } from '#lib/api/personal.js';
  import { describeError } from '#lib/api/errors.js';
  import { emptyPager, loadNext } from '#lib/util/paging.js';
  import { t } from '#lib/i18n/index.js';

  let pager = $state(emptyPager());
  let signal: AbortSignal | undefined;
  let api: ReturnType<typeof personalApi>;
  async function more(): Promise<void> {
    if (!signal || signal.aborted || !session.capabilities?.favorites || pager.loading || pager.done) return;
    const activeSignal = signal;
    const current = untrack(() => pager);
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext(current,
      (cursor, requestSignal) => api.favorites({ limit: 48, cursor }, requestSignal), activeSignal);
    if (activeSignal.aborted) return;
    pager = next;
    if (restarted) await more();
  }
  $effect(() => {
    const allowed = session.capabilities?.favorites;
    const generation = session.client.sessionGeneration;
    void generation;
    pager = emptyPager();
    if (!allowed) return;
    const controller = new AbortController();
    signal = controller.signal;
    api = personalApi(session.client);
    untrack(() => void more());
    return () => controller.abort();
  });
</script>

<svelte:head><title>{t('personal.favorites')} · {t('app.name')}</title></svelte:head>
<div class="page">
  <PageHeader title={t('personal.favorites')} />
  <a class="btn btn--ghost" href="/server">{t('nav.my')}</a>
  {#if session.capabilities?.favorites}
    {#if pager.items.length}<MediaGrid items={pager.items} label={t('personal.favorites')} />{/if}
    {#if pager.loading && !pager.items.length}<SkeletonPage variant="grid" />
    {:else if pager.error}<StateView kind="error" message={describeError(pager.error)} onRetry={() => void more()} />
    {:else if pager.done && !pager.items.length}<StateView title={t('personal.emptyFavorites')} message={t('personal.emptyFavoritesBody')} />{/if}
    {#if !pager.done && !pager.error}
      <button class="btn btn--secondary" disabled={pager.loading} onclick={() => void more()}>{t('libraries.loadMore')}</button>
    {/if}
  {:else}
    <StateView message={t('personal.unavailable')} />
  {/if}
</div>
