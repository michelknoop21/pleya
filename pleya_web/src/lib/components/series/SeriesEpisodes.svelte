<!--
  De afleveringen van een serie: een pil per seizoen, de telling van het
  gekozen seizoen, het hele seizoen in één keer als gezien markeren, en de
  lijst zelf.

  Afleveringen komen uit `/items/{seizoen}/children` en worden per seizoen
  opgehaald zodra het gekozen is. Een seizoen markeren is met
  `capabilities.watch_state_tree` één aanroep op het seizoen, die de server in
  één transactie uitvoert; zonder die vlag de gewone kijkstatus-aanroep, één
  per aflevering en na elkaar. De knop staat er pas als alle afleveringen van
  het seizoen geladen zijn.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import EpisodeRow from './EpisodeRow.svelte';
  import StateView from '../StateView.svelte';
  import { describeError } from '../../api/errors';
  import { personalApi } from '../../api/personal';
  import type { Item } from '../../api/types';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import { emptyPager, loadNext, type PagerState } from '../../util/paging';

  interface Props {
    seasons: Item[];
    seasonId: string;
    onselect: (seasonId: string) => void;
    /** Een aflevering wisselde van kijkstand: +1 is erbij gezien, -1 eraf. */
    onwatch: (delta: number) => void;
  }
  let { seasons, seasonId, onselect, onwatch }: Props = $props();

  let pager = $state<PagerState>(emptyPager());
  let signal: AbortSignal | undefined;
  let busy = $state(false);
  let error = $state('');

  const episodes = $derived(pager.items);
  const counts = $derived.by(() => {
    const watched = episodes.filter(episode => episode.user_state?.watched).length;
    const busyCount = episodes.filter(episode => !episode.user_state?.watched && (episode.user_state?.position_ms ?? 0) > 0).length;
    return { watched, busy: busyCount, unwatched: episodes.length - watched - busyCount };
  });
  const allWatched = $derived(episodes.length > 0 && counts.watched === episodes.length);
  const canWatch = $derived(session.capabilities?.watch_state === true);

  async function fetchMore(id: string, active: AbortSignal): Promise<void> {
    const current = untrack(() => pager);
    if (active.aborted || current.loading || current.done) return;
    pager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext(current,
      (cursor, sig) => session.client.children(id, { limit: 100, cursor }, sig), active);
    if (active.aborted) return;
    pager = next;
    if (restarted) await fetchMore(id, active);
  }
  function more(): void {
    if (signal) void fetchMore(seasonId, signal);
  }

  $effect(() => {
    const id = seasonId;
    const controller = new AbortController();
    signal = controller.signal;
    untrack(() => {
      pager = emptyPager();
      error = '';
      if (id) void fetchMore(id, controller.signal);
    });
    return () => controller.abort();
  });

  function patch(id: string, change: Partial<Item>, notify = true): void {
    const before = pager.items.find(episode => episode.id === id);
    if (!before) return;
    pager = { ...pager, items: pager.items.map(episode => (episode.id === id ? { ...episode, ...change } : episode)) };
    const delta = Number(!!change.user_state?.watched) - Number(!!before.user_state?.watched);
    if (notify && 'user_state' in change) onwatch(delta);
  }

  async function markSeason(watched: boolean): Promise<void> {
    if (busy) return;
    busy = true;
    error = '';
    const api = personalApi(session.client);
    // Wisselt de kijker van seizoen, dan stopt de reeks na de lopende aanvraag.
    // Wat al geschreven is telt wel mee, in één melding aan de kop.
    const active = signal;
    let written = 0;
    try {
      if (session.capabilities?.watch_state_tree === true) {
        // De stand vóór de aanroep: wisselt de kijker intussen van seizoen, dan
        // telt de kop toch wat de server schreef.
        const before = new Map(pager.items.map(episode => [episode.id, !!episode.user_state?.watched]));
        const tree = await api.setTreeWatched(seasonId, watched);
        for (const entry of tree.items) {
          if (!before.has(entry.item_id)) continue;
          if (before.get(entry.item_id) !== watched) written += 1;
          if (!active?.aborted) patch(entry.item_id, { user_state: entry.state }, false);
        }
        return;
      }
      for (const episode of episodes.filter(candidate => !!candidate.user_state?.watched !== watched)) {
        // Een aflevering die de kijker intussen los heeft gezet, telt al mee via haar eigen knop.
        if (!!pager.items.find(current => current.id === episode.id)?.user_state?.watched === watched) continue;
        const state = await api.setWatched(episode.id, watched, episode.duration_ms ?? undefined);
        written += 1;
        if (active?.aborted) break;
        patch(episode.id, { user_state: state }, false);
      }
    } catch (err) {
      if (!active?.aborted) error = describeError(err);
    } finally {
      busy = false;
      if (written > 0) onwatch(watched ? written : -written);
    }
  }
</script>

<div class="seasons">
  <div class="seasons__pills" role="group" aria-label={t('item.seasons')}>
    {#each seasons as season (season.id)}
      <button type="button" class="pill" aria-pressed={season.id === seasonId} onclick={() => onselect(season.id)}>
        {typeof season.child_count === 'number' ? `${season.title} · ${season.child_count}` : season.title}
      </button>
    {/each}
  </div>
  {#if canWatch && episodes.length > 0}
    <span class="seasons__counts">{t('series.seasonCounts', counts)}</span>
    {#if pager.done}
      <button type="button" class="ghost" aria-disabled={busy} onclick={() => void markSeason(!allWatched)}>
        {t(allWatched ? 'series.markSeasonUnwatched' : 'series.markSeasonWatched')}
      </button>
    {/if}
  {/if}
</div>
{#if error}<p class="seasons__note" role="alert">{error}</p>{/if}

{#if episodes.length > 0}
  <ul class="episodes" aria-label={t('item.episodes')}>
    {#each episodes as episode, index (episode.id)}
      <EpisodeRow item={episode} eager={index < 6} onchange={change => patch(episode.id, change)} />
    {/each}
  </ul>
{/if}
{#if pager.error}
  <StateView compact kind="error" message={describeError(pager.error)} onRetry={more} />
{:else if pager.loading}
  <p class="seasons__note" aria-live="polite">{t('libraries.loading')}</p>
{:else if episodes.length === 0 && pager.done}
  <StateView compact title={t('item.noChildren')} />
{:else if seasonId && !pager.done}
  <button type="button" class="btn btn--secondary" onclick={more}>{t('libraries.loadMore')}</button>
{/if}

<style>
  .seasons { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin: 20px 0 8px; }
  .seasons__pills { display: flex; flex-wrap: wrap; gap: 8px; flex: 1 1 auto; min-width: 0; }
  .seasons__counts, .seasons__note { font-size: 13px; color: var(--ink-2); }
  .pill, .ghost {
    min-height: var(--button-height);
    padding: 0 18px;
    border: 1px solid color-mix(in srgb, var(--text) 22%, transparent);
    border-radius: var(--radius-pill);
    background: transparent;
    color: var(--ink);
    font-size: 14px;
    font-weight: 500;
    white-space: nowrap;
    cursor: pointer;
  }
  .pill[aria-pressed='true'] { background: var(--ink); border-color: var(--ink); color: var(--bg); }
  .ghost[aria-disabled='true'] { opacity: 0.5; cursor: progress; }
  .episodes { list-style: none; margin: 0; padding: 0; }
  @media (max-width: 599px) {
    .ghost { white-space: normal; padding-block: 8px; }
  }
</style>
