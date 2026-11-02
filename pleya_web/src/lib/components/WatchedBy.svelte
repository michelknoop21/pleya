<!--
  "Bekeken door" op het detailscherm (S20.4, matrixrij "Wie heeft dit gekeken").

  `GET /watch-history` is klasse `admin`, heeft een venster van hoogstens 31
  dagen en geen itemfilter. Een lid krijgt deze rij dus niet, en een fout laat
  hem weg: het is een aanvulling op de pagina, geen onderdeel van de titel.
-->
<script lang="ts">
  import { adminApi } from '../api/admin';
  import type { Item, WatchHistoryEntry } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import { formatRelative } from '../util/format';

  const DAYS = 31;

  let { item }: { item: Pick<Item, 'id' | 'kind'> } = $props();
  let viewers = $state<WatchHistoryEntry[]>([]);
  let truncated = $state(false);

  function latestPerUser(entries: WatchHistoryEntry[], id: string): WatchHistoryEntry[] {
    const seen = new Set<string>();
    return entries.filter((entry) => {
      if ((entry.item_id !== id && entry.series_id !== id) || seen.has(entry.user_id)) return false;
      seen.add(entry.user_id);
      return true;
    });
  }

  $effect(() => {
    const { id, kind } = item;
    viewers = [];
    truncated = false;
    if (!session.canAdminister || kind === 'season') return;
    const controller = new AbortController();
    adminApi(session.client).watchHistory(DAYS, controller.signal).then((history) => {
      if (controller.signal.aborted) return;
      viewers = latestPerUser(history.items, id);
      truncated = history.truncated;
    }).catch(() => undefined);
    return () => controller.abort();
  });
</script>

{#if viewers.length}
  <section class="watched" aria-labelledby="watched-by">
    <h2 class="watched__h" id="watched-by">{t('watchedBy.title')}</h2>
    <ul>
      {#each viewers as viewer (viewer.user_id)}
        <li><span>{viewer.username}</span> <span class="watched__when">{formatRelative(viewer.updated_at)}</span></li>
      {/each}
    </ul>
    <p class="watched__when">{t(truncated ? 'watchedBy.truncated' : 'watchedBy.window', { days: DAYS })}</p>
  </section>
{/if}

<style>
  .watched { display: flex; flex-direction: column; gap: 8px; }
  .watched__h { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.01em; color: var(--ink); }
  .watched ul { display: flex; flex-wrap: wrap; gap: 8px 24px; list-style: none; margin: 0; padding: 0; }
  .watched li { overflow-wrap: anywhere; }
  .watched__when { margin: 0; font-size: 13px; color: var(--ink-2); }
  @media (max-width: 899px) { .watched__h { font-size: 18px; } }
</style>
