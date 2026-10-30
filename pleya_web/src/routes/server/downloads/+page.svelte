<script lang="ts">
  import Artwork from '#lib/components/Artwork.svelte';
  import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import Panel from '#lib/components/Panel.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import StatusPill, { type PillTone } from '#lib/components/StatusPill.svelte';
  import { personalApi } from '#lib/api/personal.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Download, Item } from '#lib/api/types.js';
  import { session } from '#lib/stores/session.svelte.js';
  import { formatBytes, formatDate } from '#lib/util/format.js';
  import { t } from '#lib/i18n/index.js';

  // Een download draagt alleen ids. De titel komt uit het item, en een item dat
  // de aanvrager niet meer mag zien houdt zijn regel, zodat hij hem kan intrekken.
  const POLL_MS = 5_000;
  const ITEM_BATCH = 4;
  const STATUS: Record<string, { label: () => string; tone: PillTone }> = {
    ready: { label: () => t('downloads.ready'), tone: 'ok' },
    preparing: { label: () => t('downloads.preparing'), tone: 'run' },
    failed: { label: () => t('downloads.failed'), tone: 'err' }
  };

  let downloads = $state<Download[]>([]);
  let items = $state<Record<string, Item | null>>({});
  let loading = $state(true);
  let error = $state<string | null>(null);
  let retry = $state(0);
  let pending = $state<Download | null>(null);
  let removing = $state(false);
  let removeError = $state<string | null>(null);
  let api: ReturnType<typeof personalApi>;

  const ready = $derived(downloads.filter((download) => download.sha256));
  const totalBytes = $derived(downloads.reduce((sum, download) => sum + (download.size_bytes ?? 0), 0));

  const titleOf = (download: Download): string => items[download.item_id]?.title ?? t('downloads.unknownTitle');
  const status = (download: Download) => STATUS[download.status] ?? { label: () => t('downloads.unknownStatus'), tone: 'idle' as PillTone };

  function detail(download: Download): string {
    const version = items[download.item_id]?.versions?.find((candidate) => candidate.id === download.version_id);
    return [
      t('downloads.original'), version?.container.toUpperCase(),
      download.size_bytes === null ? null : formatBytes(download.size_bytes),
      formatDate(download.created_at)
    ].filter(Boolean).join(' · ');
  }

  async function fetchItems(list: Download[], signal: AbortSignal): Promise<void> {
    const missing = [...new Set(list.map((download) => download.item_id))].filter((id) => !(id in items));
    for (let start = 0; start < missing.length && !signal.aborted; start += ITEM_BATCH) {
      const batch = missing.slice(start, start + ITEM_BATCH);
      const found = await Promise.all(batch.map((id) => session.client.item(id, signal).catch(() => null)));
      if (signal.aborted) return;
      items = { ...items, ...Object.fromEntries(batch.map((id, index) => [id, found[index] ?? null])) };
    }
  }

  async function refresh(signal: AbortSignal): Promise<void> {
    const list = await api.downloads(signal);
    if (signal.aborted) return;
    await fetchItems(list, signal);
    if (!signal.aborted) downloads = list;
  }

  async function withdraw(): Promise<void> {
    if (!pending) return;
    const target = pending;
    removing = true;
    removeError = null;
    try {
      await api.deleteDownload(target.id);
      downloads = downloads.filter((download) => download.id !== target.id);
      pending = null;
    } catch (err) {
      removeError = describeError(err);
    } finally {
      removing = false;
    }
  }

  $effect(() => {
    const allowed = session.capabilities?.downloads;
    void session.client.sessionGeneration;
    void retry;
    downloads = [];
    items = {};
    pending = null;
    error = null;
    loading = Boolean(allowed);
    if (!allowed) return;
    const controller = new AbortController();
    const { signal } = controller;
    api = personalApi(session.client);
    let timer: ReturnType<typeof setTimeout> | undefined;
    const tick = async (): Promise<void> => {
      try {
        await refresh(signal);
        if (signal.aborted) return;
        error = null;
        if (downloads.some((download) => download.status === 'preparing')) timer = setTimeout(() => void tick(), POLL_MS);
      } catch (err) {
        if (!signal.aborted) error = describeError(err);
      } finally {
        if (!signal.aborted) loading = false;
      }
    };
    void tick();
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  });
</script>

<svelte:head><title>{t('downloads.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={t('downloads.title')} />
  <a class="btn btn--ghost" href="/server">{t('nav.my')}</a>
  {#if !session.capabilities?.downloads}
    <StateView message={t('downloads.unavailable')} />
  {:else if loading}
    <SkeletonPage variant="grid" />
  {:else if error}
    <StateView kind="error" message={error} onRetry={() => retry++} />
  {:else if !downloads.length}
    <StateView title={t('downloads.empty')} message={t('downloads.emptyBody')} />
  {:else}
    <div class="layout">
      <div class="main">
        <ul class="rows">
          {#each downloads as download (download.id)}
            {@const item = items[download.item_id]}
            {@const state = status(download)}
            <li class="row">
              <span class="row__art"><Artwork artworkId={item?.artwork?.poster_id ?? item?.artwork?.backdrop_id} alt="" shape="free" /></span>
              <span class="row__text">
                {#if item}<a class="row__title" href="/items/{item.id}">{item.title}</a>{:else}<span class="row__title">{titleOf(download)}</span>{/if}
                <span class="row__meta">{detail(download)}</span>
                {#if download.sha256}<span class="row__digest" title={download.sha256}>SHA-256 {download.sha256.slice(0, 12)}</span>{/if}
              </span>
              <StatusPill tone={state.tone} label={state.label()} />
              <button type="button" class="icon" aria-label={t('downloads.withdraw', { title: titleOf(download) })} onclick={() => { removeError = null; pending = download; }}>
                <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M4 7h16M9 7V4h6v3m3 0-1 13H7L6 7m4 4v5m4-5v5" /></svg>
              </button>
            </li>
          {/each}
        </ul>
        <p class="note">{t('downloads.note')}</p>
      </div>
      <aside class="side">
        <Panel level={2}>
          {#snippet title()}{t('downloads.integrity')}{/snippet}
          <p class="note">{t('downloads.integrityBody')}</p>
          <p class="note">{t('downloads.integrityCount', { ready: ready.length, total: downloads.length })}</p>
        </Panel>
        <Panel level={2}>
          {#snippet title()}{t('downloads.space')}{/snippet}
          <dl class="space"><dt>{t('downloads.spaceTotal')}</dt><dd>{formatBytes(totalBytes)}</dd></dl>
        </Panel>
      </aside>
    </div>
  {/if}
</div>

<ConfirmDialog
  open={pending !== null}
  title={t('downloads.confirmTitle')}
  message={pending ? t('downloads.confirmBody', { title: titleOf(pending) }) : ''}
  confirmLabel={t('downloads.confirm')}
  danger
  busy={removing}
  onconfirm={() => void withdraw()}
  oncancel={() => (pending = null)}
>
  {#if removeError}<p class="note" role="alert">{removeError}</p>{/if}
</ConfirmDialog>

<style>
  .page { padding: var(--page-top) var(--inset) var(--space-2); }
  .layout { display: grid; grid-template-columns: minmax(0, 1fr); gap: var(--space-1-5); margin-top: var(--space); }
  .main, .side { display: flex; flex-direction: column; gap: var(--space); min-width: 0; }
  .rows { list-style: none; margin: 0; padding: 0; overflow: hidden; border-radius: var(--radius-md); background: var(--panel); }
  .row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 14px; padding: 12px 18px; }
  .row + .row { border-top: 1px solid var(--hairline); }
  .row__art { flex: none; width: 40px; aspect-ratio: 2 / 3; overflow: hidden; border-radius: 6px; }
  .row__art :global(.artwork) { height: 100%; }
  .row__text { display: flex; flex: 1 1 200px; flex-direction: column; gap: 2px; min-width: 0; }
  .row__title { font-size: 15px; font-weight: 600; overflow-wrap: anywhere; color: var(--ink); }
  .row__meta { font-size: 13px; color: var(--ink-2); overflow-wrap: anywhere; }
  .row__digest { font-family: var(--font-mono); font-size: 12px; color: var(--ink-2); }
  .icon { display: inline-flex; align-items: center; justify-content: center; width: var(--touch-target); height: var(--touch-target); border: 0; border-radius: 50%; background: var(--panel-2); color: var(--ink); cursor: pointer; }
  .note { margin: 0; font-size: 13px; color: var(--ink-2); }
  .space { display: flex; justify-content: space-between; gap: 12px; margin: 0; font-size: 14px; }
  .space dt { color: var(--ink-2); }
  .space dd { margin: 0; color: var(--ink); }
  @media (min-width: 900px) {
    .layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); align-items: start; }
  }
</style>
