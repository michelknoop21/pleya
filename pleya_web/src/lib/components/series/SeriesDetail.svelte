<!--
  Het seriedetail: kop met backdrop, poster en acties, het paneel met de
  aflevering waar je verder kijkt, en daaronder twee onderdelen: de
  afleveringen per seizoen, en details met cast.

  Seizoenen komen uit `/items/{serie}/children`. Welke aflevering de volgende
  is bepaalt de server: de hubs continue_watching en next_up, waaruit hier de
  eerste aflevering van een seizoen van deze serie wordt gekozen. Dat seizoen
  staat dan ook voor in de lijst. Lukt de hub niet, dan blijft het paneel weg
  en begint de lijst bij het eerste seizoen.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import SeriesContinue from './SeriesContinue.svelte';
  import SeriesEpisodes from './SeriesEpisodes.svelte';
  import Artwork from '../Artwork.svelte';
  import CardMenu from '../CardMenu.svelte';
  import ItemPersonalActions from '../ItemPersonalActions.svelte';
  import StateView from '../StateView.svelte';
  import WatchedBy from '../WatchedBy.svelte';
  import { describeError } from '../../api/errors';
  import type { Item } from '../../api/types';
  import { plural, t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import { formatDate } from '../../util/format';
  import { emptyPager, loadNext, type PagerState } from '../../util/paging';
  import { canRefreshMetadata, refreshMetadata } from '../refreshMetadata';

  let { item, onchange }: { item: Item; onchange: (next: Item) => void } = $props();
  const uid = $props.id();

  type Tab = 'episodes' | 'details';
  const tabs = $derived<{ id: Tab; label: string }[]>([
    { id: 'episodes', label: t('series.tabEpisodes') },
    { id: 'details', label: t('series.tabDetails') }
  ]);
  // "Bekeken door" in het kaartmenu linkt naar #watched-by, en dat staat bij de details.
  // Het menu in de kop van deze pagina navigeert alleen de hash, zonder dat het
  // component opnieuw wordt opgebouwd; de tab volgt de URL dus ook daarna.
  let tab = $state<Tab>('episodes');
  $effect(() => {
    if (page.url.hash === '#watched-by') tab = 'details';
  });

  let seasonPager = $state<PagerState>(emptyPager());
  let candidates = $state<Item[]>([]);
  let seasonId = $state('');
  let hubsSettled = $state(false);
  let watchedDelta = $state(0);
  let signal: AbortSignal | undefined;
  let hubRun = 0;
  let refreshNote = $state('');

  const seasons = $derived(seasonPager.items);
  const caps = $derived(session.capabilities);
  const nextEpisode = $derived(
    candidates.find(candidate => candidate.kind === 'episode' && seasons.some(season => season.id === candidate.parent_id)) ?? null
  );
  const nextSeason = $derived(seasons.find(season => season.id === nextEpisode?.parent_id));
  const watchedCount = $derived(
    typeof item.watched_episode_count === 'number' ? item.watched_episode_count + watchedDelta : null
  );
  const credits = $derived((['director', 'actor', 'writer'] as const).map(role => ({
    role, label: t(`item.${role}`), people: item.people?.filter(person => person.role === role && person.name.trim()) ?? []
  })).filter(group => group.people.length > 0));
  const facts = $derived([
    { label: t('item.added'), value: formatDate(item.added_at) },
    { label: t('item.episodes'), value: typeof item.episode_count === 'number' ? String(item.episode_count) : null }
  ].filter(fact => fact.value));
  const metaStart = $derived(
    [item.year, typeof item.child_count === 'number' ? plural('item.seasonsCount', item.child_count) : null].filter(Boolean).join(' · ')
  );
  const genres = $derived((item.genres ?? []).filter(genre => genre.trim()).join(', '));

  async function fetchSeasons(active: AbortSignal): Promise<void> {
    const current = untrack(() => seasonPager);
    if (active.aborted || current.loading || current.done) return;
    seasonPager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext(current,
      (cursor, sig) => session.client.children(item.id, { limit: 100, cursor }, sig), active);
    if (active.aborted) return;
    seasonPager = next;
    if (restarted) await fetchSeasons(active);
  }
  function moreSeasons(): void {
    if (signal) void fetchSeasons(signal);
  }

  // ponytail: de hubs gaan over de hele server en geven hooguit één pagina; een
  // serie die daar niet in staat krijgt geen paneel. Een route per serie lost dat op.
  async function fetchNext(active?: AbortSignal): Promise<void> {
    try {
      if (caps?.watch_state !== true) return;
      // Alleen het laatst gestarte antwoord telt: een eerder antwoord dat later
      // binnenkomt zou een net gemarkeerde aflevering weer als volgende tonen.
      const run = ++hubRun;
      const pages = await Promise.all((['continue_watching', 'next_up'] as const)
        .map(hub => session.client.hub(hub, { limit: 500 }, active)));
      if (!active?.aborted && run === hubRun) candidates = pages.flatMap(found => found.items);
    } catch {
      // Een aanvulling op de pagina: zonder hub blijft alleen het paneel weg.
    } finally {
      hubsSettled = true;
    }
  }

  $effect(() => {
    const controller = new AbortController();
    signal = controller.signal;
    untrack(() => {
      void fetchSeasons(controller.signal);
      void fetchNext(controller.signal);
    });
    return () => controller.abort();
  });

  // Het seizoen van de volgende aflevering staat voor, anders het eerste. Eenmaal
  // gekozen blijft het staan, ook als de hub na een markering iets anders noemt.
  $effect(() => {
    if (hubsSettled && seasons.length > 0 && !untrack(() => seasonId)) {
      seasonId = nextEpisode?.parent_id ?? seasons[0]!.id;
    }
  });

  function watchChanged(delta: number): void {
    watchedDelta += delta;
    void fetchNext(signal);
  }
  function tabKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    tab = tab === 'episodes' ? 'details' : 'episodes';
    document.getElementById(`${uid}-tab-${tab}`)?.focus();
  }
</script>

<article class="series">
  <header class="series__hero">
    {#if item.artwork?.backdrop_id}
      <div class="series__backdrop" aria-hidden="true">
        <Artwork artworkId={item.artwork.backdrop_id} alt="" shape="free" role="backdrop" eager flat />
      </div>
    {/if}
    <a class="series__back" href="/series"><span aria-hidden="true">‹</span> {t('nav.series')}</a>
    <div class="series__head">
      <div class="series__poster">
        <Artwork artworkId={item.artwork?.poster_id} alt="" shape="poster" role="poster" eager />
      </div>
      <div class="series__meta">
        <h1 class="series__title">{item.title}</h1>
        <p class="series__line">
          {metaStart}{#if item.content_rating?.trim()}{metaStart ? ' · ' : ''}<span class="series__chip">{item.content_rating}</span>{/if}{#if genres}{metaStart || item.content_rating?.trim() ? ' · ' : ''}{genres}{/if}
        </p>
        {#if item.summary?.trim()}<p class="series__summary">{item.summary}</p>{/if}
        <div class="series__acts">
          {#if caps?.favorites || caps?.ratings || caps?.collections || caps?.playlists}
            <ItemPersonalActions {item} icons {onchange} />
          {/if}
          <CardMenu {item} onchange={patch => onchange({ ...item, ...patch })} />
          {#if caps?.watch_state === true && watchedCount !== null && (item.episode_count ?? 0) > 0}
            <span class="series__watched">{t('series.watchedOf', { watched: watchedCount, total: item.episode_count ?? 0 })}</span>
          {/if}
        </div>
      </div>
    </div>
  </header>

  <div class="series__body">
    {#if nextEpisode}
      <SeriesContinue episode={nextEpisode} season={nextSeason} />
    {/if}

    <section>
      <div class="series__tabs" role="tablist" aria-label={t('series.tabs')}>
        {#each tabs as entry (entry.id)}
          <button
            type="button"
            role="tab"
            class="series__tab"
            id="{uid}-tab-{entry.id}"
            aria-selected={tab === entry.id}
            aria-controls="{uid}-panel"
            tabindex={tab === entry.id ? 0 : -1}
            onclick={() => (tab = entry.id)}
            onkeydown={tabKey}
          >{entry.label}</button>
        {/each}
      </div>

      <div id="{uid}-panel" role="tabpanel" aria-labelledby="{uid}-tab-{tab}">
        {#if tab === 'episodes'}
          {#if seasons.length > 0 && seasonId}
            <SeriesEpisodes {seasons} {seasonId} onselect={id => (seasonId = id)} onwatch={watchChanged} />
          {/if}
          {#if seasonPager.error}
            <StateView compact kind="error" message={describeError(seasonPager.error)} onRetry={moreSeasons} />
          {:else if seasonPager.loading || (seasons.length > 0 && !seasonId)}
            <p class="series__note" aria-live="polite">{t('libraries.loading')}</p>
          {:else if seasons.length === 0 && seasonPager.done}
            <StateView compact title={t('item.noChildren')} />
          {:else if !seasonPager.done}
            <p class="series__more"><button type="button" class="btn btn--secondary" onclick={moreSeasons}>{t('libraries.loadMore')}</button></p>
          {/if}
        {:else}
          <div class="series__details">
            {#if credits.length}
              <dl class="credits">
                {#each credits as group (group.role)}
                  <div><dt>{group.label}</dt><dd><ul>
                    {#each group.people as person, index (index)}<li><span>{person.name}</span>{#if person.character?.trim()} · {person.character}{/if}</li>{/each}
                  </ul></dd></div>
                {/each}
              </dl>
            {/if}
            <dl class="credits">
              {#each facts as fact (fact.label)}<div><dt>{fact.label}</dt><dd>{fact.value}</dd></div>{/each}
            </dl>
            {#if session.canAdminister}
              <div class="series__admin">
                {#if caps?.metadata_overrides === true || caps?.artwork_choices === true}<a class="btn btn--secondary" href="/admin/metadata/edit?item={encodeURIComponent(item.id)}">{t('admin.metadata.editor.title')}</a>{/if}
                <a class="btn btn--secondary" href="/admin/metadata/match?item={encodeURIComponent(item.id)}">{t('admin.match.title')}</a>
                {#if canRefreshMetadata()}
                  <button type="button" class="btn btn--secondary" onclick={() => void refreshMetadata(item.id).then(text => (refreshNote = text))}>{t('detail.refreshMetadata')}</button>
                {/if}
              </div>
              {#if refreshNote}<p class="series__note" role="status">{refreshNote}</p>{/if}
            {/if}
            {#if caps?.watch_state}<WatchedBy {item} />{/if}
          </div>
        {/if}
      </div>
    </section>
  </div>
</article>

<style>
  .series__hero {
    position: relative;
    isolation: isolate;
    overflow: hidden;
    padding: 20px var(--inset) 36px;
    background: var(--panel);
  }
  .series__backdrop { position: absolute; inset: 0; z-index: -1; }
  .series__backdrop :global(.artwork) { height: 100%; }
  .series__backdrop::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(90deg, var(--scrim) 0%, color-mix(in srgb, var(--scrim) 82%, transparent) 45%, color-mix(in srgb, var(--scrim) 30%, transparent) 100%);
  }
  .series__back { display: inline-flex; align-items: center; gap: 6px; min-height: var(--button-height); font-size: 14px; color: var(--ink-2); }
  .series__head { display: flex; flex-wrap: wrap; gap: 36px; margin-top: 20px; }
  .series__poster { flex: none; width: 220px; aspect-ratio: 2 / 3; border-radius: var(--radius-card); overflow: hidden; }
  .series__poster :global(.artwork) { height: 100%; }
  .series__meta { flex: 999 1 420px; min-width: 0; }
  .series__title {
    margin: 0;
    font-family: var(--font-display);
    font-size: clamp(30px, 4vw, 52px);
    line-height: 1.05;
    letter-spacing: 0.02em;
    text-transform: uppercase;
    overflow-wrap: anywhere;
  }
  .series__line { margin: 14px 0 0; color: var(--ink); }
  .series__chip { display: inline-block; padding: 4px 10px; border-radius: var(--radius-sm); background: var(--elevated); font-size: 12px; font-weight: 500; }
  .series__summary { margin: 16px 0 0; max-width: 680px; font-size: 16px; line-height: 24px; white-space: pre-line; overflow-wrap: anywhere; }
  .series__acts { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; margin-top: 24px; }
  .series__acts :global(button.more) {
    width: 48px;
    height: 48px;
    border: 1px solid color-mix(in srgb, var(--text) 30%, transparent);
    background: color-mix(in srgb, var(--bg) 50%, transparent);
    color: var(--ink);
  }
  .series__watched { font-size: 14px; color: var(--ink-2); }

  .series__body { display: flex; flex-direction: column; gap: 32px; padding: 32px var(--inset) 56px; }
  .series__tabs { display: flex; gap: 28px; border-bottom: 1px solid var(--hairline-strong); }
  .series__tab {
    min-height: var(--button-height);
    padding: 0 4px;
    border: 0;
    border-bottom: 2px solid transparent;
    background: none;
    color: var(--ink-2);
    font-size: 16px;
    font-weight: 500;
    cursor: pointer;
  }
  .series__tab[aria-selected='true'] { color: var(--ink); border-bottom-color: var(--accent); }
  .series__note { font-size: 13px; color: var(--ink-2); }
  .series__more { margin: 12px 0 0; }
  .series__details { display: flex; flex-direction: column; gap: var(--space-2); padding-top: 20px; }
  .series__admin { display: flex; flex-wrap: wrap; gap: var(--space); }
  .credits { margin: 0; display: grid; gap: 8px; }
  .credits > div { display: grid; grid-template-columns: 96px minmax(0, 1fr); align-items: baseline; gap: 12px; }
  .credits dd { margin: 0; min-width: 0; }
  .credits dt { color: var(--ink-2); font-size: 13px; }
  .credits ul { display: flex; flex-wrap: wrap; gap: 8px 16px; list-style: none; padding: 0; margin: 0; }
  .credits li { overflow-wrap: anywhere; }

  @media (max-width: 899px) {
    .series__hero { padding-bottom: 24px; }
    .series__head { gap: 20px; margin-top: 8px; }
    .series__poster { width: 132px; }
    .series__body { gap: 24px; padding-top: 24px; }
  }
  @media (max-width: 599px) {
    .series__poster { width: 110px; }
    .series__meta { flex-basis: 100%; }
    .series__tabs { gap: 16px; }
  }
</style>
