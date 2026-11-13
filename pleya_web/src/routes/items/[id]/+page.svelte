<script lang="ts">
  import { untrack } from 'svelte';
  import { emptyPager, loadNext, type PagerState } from '#lib/util/paging.js';
  import { page } from '$app/state';

  import Artwork from '#lib/components/Artwork.svelte';
  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import Select from '#lib/components/Select.svelte';
  import ItemPersonalActions from '#lib/components/ItemPersonalActions.svelte';
  import VersionPanel from '#lib/components/VersionPanel.svelte';
  import TrackChoice from '#lib/components/TrackChoice.svelte';
  import CastCrew from '#lib/components/CastCrew.svelte';
  import FileFacts from '#lib/components/FileFacts.svelte';
  import ItemAdminMenu from '#lib/components/ItemAdminMenu.svelte';
  import WatchedBy from '#lib/components/WatchedBy.svelte';
  import SeriesDetail from '#lib/components/series/SeriesDetail.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { formatClock, formatDate, formatDuration } from '#lib/util/format.js';
  import { t } from '#lib/i18n/index.js';
  import { playerHref, type TrackPick } from '#lib/player/route.js';
  import { formatPlayTime } from '#lib/player/keyboard.js';
  import { videoContext, type VideoContext } from '#lib/util/videoContext.js';

  const itemId = $derived(page.params['id'] ?? '');

  let item = $state<Item | null>(null);
  let context = $state<VideoContext>({});
  let childPager = $state<PagerState>(emptyPager());
  const children = $derived(childPager.items);
  let loadSignal: AbortSignal | undefined;
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedVersionId = $state('');
  // De spoorkeuze van het filmdetail; bij serie, seizoen en aflevering blijft ze leeg.
  let tracks = $state<TrackPick>({});
  let now = $state(Date.now());
  let retry = $state(0);

  async function load(id: string, signal: AbortSignal): Promise<void> {
    loading = true;
    error = null;
    item = null;
    context = {};
    childPager = emptyPager();
    loadSignal = signal;
    selectedVersionId = '';
    tracks = {};
    try {
      const loaded = await session.client.item(id, signal);
      if (signal.aborted || id !== itemId) return;
      item = loaded;
      // Ancestor failures leave this item's metadata, playback and children
      // available. Do not make the whole page wait for inherited artwork.
      void videoContext(loaded, (parentId, active) => session.client.item(parentId, active), signal)
        .then(value => { if (!signal.aborted && id === itemId) context = value; });

      // Afleveringen van een seizoen komen uit /children. Voor een film is dat
      // een lege lijst en geen fout, dus die aanvraag wordt overgeslagen in
      // plaats van weggegooid. Een serie haalt haar seizoenen zelf op (SeriesDetail).
      if (loaded.kind === 'season') {
        await fetchChildren(id, signal);
      }
    } catch (err) {
      if (signal.aborted || id !== itemId) return;
      error = describeError(err);
    } finally {
      if (!signal.aborted) loading = false;
    }
  }

  async function fetchChildren(id: string, signal: AbortSignal): Promise<void> {
    const current = untrack(() => childPager);
    if (signal.aborted || current.loading || current.done) return;
    childPager = { ...current, loading: true, error: null };
    const { next, restarted } = await loadNext(current,
      (cursor, activeSignal) => session.client.children(id, { limit: 100, cursor }, activeSignal), signal);
    if (signal.aborted || id !== itemId) return;
    childPager = next;
    if (restarted) await fetchChildren(id, signal);
  }
  function moreChildren(): void {
    if (loadSignal) void fetchChildren(itemId, loadSignal);
  }

  $effect(() => {
    const id = itemId;
    void retry;
    if (!id) return;
    const controller = new AbortController();
    void load(id, controller.signal);
    return () => controller.abort();
  });

  const version = $derived(item?.versions?.find(candidate => candidate.id === selectedVersionId) ?? item?.versions?.[0]);
  const versionOptions = $derived((item?.versions ?? []).map((candidate, index) => ({
    value: candidate.id,
    label: [t('item.versionNumber', {number: index + 1}), candidate.edition, candidate.container.toUpperCase(), formatDuration(candidate.duration_ms)].filter(Boolean).join(' · ')
  })));
  const credits = $derived((['director', 'actor', 'writer'] as const).map(role => ({
    role, label: t(`item.${role}`), people: item?.people?.filter(person => person.role === role && person.name.trim()) ?? []
  })).filter(group => group.people.length > 0));
  const playable = $derived(
    session.capabilities?.playback_plan === true && (item?.kind === 'movie' || item?.kind === 'episode') && (item?.versions?.length ?? 0) > 0
  );
  const resumeMs = $derived(
    item?.user_state && !item.user_state.watched && item.user_state.position_ms > 0
      ? item.user_state.position_ms
      : null
  );
  const isMovie = $derived(item?.kind === 'movie');
  const movieDuration = $derived(isMovie ? item?.duration_ms ?? version?.duration_ms ?? null : null);
  // "klaar om 23:31": nu plus wat er nog te kijken is, in de klok van de browser.
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 30_000);
    return () => clearInterval(timer);
  });
  const endsAt = $derived.by(() => {
    if (!movieDuration) return null;
    const clock = formatClock(new Date(now + Math.max(0, movieDuration - (resumeMs ?? 0))).toISOString());
    return clock ? t('detail.endsAt', { time: clock }) : null;
  });
  const watchedPercent = $derived(movieDuration && resumeMs ? Math.min(100, Math.round((resumeMs / movieDuration) * 100)) : null);
  const childHeading = $derived(t('item.episodes'));
  const backdropId = $derived(item?.artwork?.backdrop_id ?? context.show?.artwork?.backdrop_id ?? context.season?.artwork?.backdrop_id);
  const posterId = $derived(item?.artwork?.poster_id ?? context.season?.artwork?.poster_id ?? context.show?.artwork?.poster_id);

  const facts = $derived.by(() => {
    if (!item) return [] as { label: string; value: string }[];
    const rows: { label: string; value: string }[] = [];
    const duration = formatDuration(item.duration_ms);
    if (duration) rows.push({ label: t('item.duration'), value: duration });
    const added = formatDate(item.added_at);
    if (added) rows.push({ label: t('item.added'), value: added });
    if (typeof item.episode_count === 'number') {
      rows.push({ label: t('item.episodes'), value: String(item.episode_count) });
    }
    return rows;
  });
</script>

<svelte:head><title>{item?.title ?? t('loading')} · {t('app.name')}</title></svelte:head>

{#if loading}
  <SkeletonPage variant="detail" heading={t('item.title')} />
{:else if error}
  <!-- De fout is een h2 onder de paginakop; zonder kop stond hij los in de pagina. -->
  <div class="detail">
    <PageHeader title={t('item.title')} />
    <StateView
      kind="error"
      message={error}
      onRetry={() => retry++}
    />
  </div>
{:else if item?.kind === 'show'}
  {#key item.id}
    <SeriesDetail {item} onreload={() => retry++} onchange={updated => { if (item?.id === updated.id) item = updated; }} />
  {/key}
{:else if item}
  <article class="detail">
    <header class="detail__head" class:detail__head--artwork={Boolean(backdropId)}>
      {#if backdropId}
        <div class="detail__backdrop" aria-hidden="true"><Artwork artworkId={backdropId} alt="" shape="free" role="backdrop" eager flat /></div>
      {/if}
      <div class="detail__poster" class:detail__poster--portrait={Boolean(posterId)}>
        <Artwork
          artworkId={posterId ?? backdropId}
          alt=""
          shape="free"
          role={posterId ? 'poster' : 'backdrop'}
          eager
        />
      </div>

      <div class="detail__meta">
        {#if item.parent_id}
          <a class="detail__parent t-small" href="/items/{item.parent_id}">
            {context.show ? [context.show.title, item.kind === 'episode' ? context.season?.title : null].filter(Boolean).join(' · ') : t('item.backToShow')}
          </a>
        {/if}
        <h1 class="t-headline">{item.title}</h1>
        <p class="detail__line t-body">
          {[item.year, formatDuration(movieDuration), item.kind === 'episode' && typeof item.index === 'number'
            ? t('item.episode', { index: item.index })
            : null,
          item.content_rating, ...(item.genres ?? []).filter(genre => genre.trim()),
          item.kind === 'season' && typeof item.index === 'number'
            ? t('item.season', { index: item.index })
            : null, endsAt]
            .filter(Boolean)
            .join(' · ')}
        </p>

        {#if item.summary?.trim()}<p class="detail__summary t-body">{item.summary}</p>{/if}
        {#if playable || (session.canAdminister && (isMovie || session.capabilities?.media_delete === true))}
          <!-- S13.2: de kijkstatus wordt hier gelezen en getoond (PS-4E), niet geschreven. -->
          <div class="detail__play">
            {#if playable && resumeMs}
              <a class="btn" href={playerHref(item.id, resumeMs, version?.id, undefined, tracks)}>
                {t('player.resume', { time: formatPlayTime(resumeMs / 1000) })}
              </a>
              <a class="btn btn--secondary" href={playerHref(item.id, undefined, version?.id, undefined, tracks)}>{t('player.playFromStart')}</a>
            {:else if playable}
              <a class="btn" href={playerHref(item.id, undefined, version?.id, undefined, tracks)}>{t('player.play')}</a>
            {/if}
            <ItemAdminMenu {item} onreload={() => retry++} />
          </div>
        {/if}
        {#if watchedPercent !== null}
          <progress class="detail__progress" max="100" value={watchedPercent} aria-label={t('detail.progress', { percent: watchedPercent })}></progress>
        {/if}

        {#if session.capabilities?.favorites || session.capabilities?.ratings || session.capabilities?.watch_state}
          {#key item.id}
            <ItemPersonalActions {item} onchange={updated => { if (item?.id === updated.id) item = updated; }} />
          {/key}
        {/if}

        {#if isMovie}
          {#key item.id}
            <TrackChoice {item} {version} {versionOptions} onversion={value => selectedVersionId = value} onpick={value => tracks = value} />
          {/key}
        {:else if versionOptions.length > 1}
          <Select label={t('item.version')} value={version?.id ?? ''} options={versionOptions} onchange={value => selectedVersionId = value} />
        {/if}
        {#if !isMovie && credits.length}
          <dl class="credits">
            {#each credits as group (group.role)}
              <div><dt>{group.label}</dt><dd><ul>
                {#each group.people as person, index (index)}<li><span>{person.name}</span>{#if person.character?.trim()} · {person.character}{/if}</li>{/each}
              </ul></dd></div>
            {/each}
          </dl>
        {/if}
        {#if !isMovie && facts.length > 0}
          <dl class="facts">
            {#each facts as fact (fact.label)}
              <div class="facts__row">
                <dt class="t-small">{fact.label}</dt>
                <dd class="t-body">{fact.value}</dd>
              </div>
            {/each}
          </dl>
        {/if}
      </div>
    </header>

    <!-- Film: sporen staan in de keuzelijsten, de rest van de versie in "Bestand" onderaan. -->
    {#if isMovie}
      <CastCrew people={item.people} />
    {:else if version}
      <VersionPanel {version} />
    {/if}

    {#if session.capabilities?.watch_state}<WatchedBy {item} />{/if}
    {#if isMovie}<FileFacts {item} {version} />{/if}

    {#if item.kind === 'season'}
      <section class="section">
        <h2 class="section-h">{childHeading}</h2>
        {#if children.length > 0}<MediaGrid items={children} label={childHeading} />{/if}
        {#if childPager.error}
          <StateView compact kind="error" message={describeError(childPager.error)} onRetry={moreChildren} />
        {:else if childPager.loading}
          <p class="t-small" aria-live="polite">{t('libraries.loading')}</p>
        {:else if children.length === 0 && childPager.done}
          <StateView compact title={t('item.noChildren')} />
        {/if}
        {#if !childPager.done && !childPager.loading && !childPager.error}
          <button type="button" class="btn btn--secondary" onclick={moreChildren}>{t('libraries.loadMore')}</button>
        {/if}
      </section>
    {/if}
  </article>
{/if}

<style>
  .detail {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-1-5) var(--inset);
  }

  .detail__head {
    position: relative;
    isolation: isolate;
    display: grid;
    gap: var(--space-1-5);
    grid-template-columns: minmax(0, 1fr);
    padding: var(--space-1-5);
    overflow: hidden;
    border-radius: var(--radius-hero);
    background: var(--panel);
  }
  .detail__poster { aspect-ratio: 16 / 9; overflow: hidden; border-radius: var(--radius-md); }
  .detail__poster--portrait { aspect-ratio: 2 / 3; max-width: 180px; }
  .detail__poster :global(.artwork) { height: 100%; }
  .detail__backdrop { display: none; }
  @media (min-width: 900px) {
    .detail__head { grid-template-columns: minmax(160px, 220px) minmax(0, 1fr); align-items: start; }
    .detail__poster { aspect-ratio: 2 / 3; max-width: none; }
    .detail__head--artwork { grid-template-columns: minmax(0, 1fr); min-height: 460px; padding: clamp(24px, 4vw, 48px); }
    .detail__head--artwork .detail__poster { display: none; }
    .detail__meta { max-width: 720px; }
    .detail__head h1 { font-family: var(--font-sans); font-size: clamp(38px,4vw,58px); font-weight: 700; text-transform: none; line-height: 1.08; letter-spacing: -0.045em; overflow-wrap: anywhere; }
    .detail__backdrop { display: block; position: absolute; inset: 0; z-index: -1; }
    .detail__backdrop :global(.artwork) { height: 100%; }
    .detail__backdrop::after { content: ''; position: absolute; inset: 0; background: linear-gradient(90deg, var(--scrim), color-mix(in srgb, var(--scrim) 80%, transparent) 38%, transparent 86%); }
  }

  .detail__play :global(.btn) { border-radius: 999px; }
  .detail__progress { width: min(100%, 420px); height: 4px; accent-color: var(--accent); }

  .detail__meta {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    min-width: 0;
  }

  .detail__summary { white-space: pre-line; overflow-wrap: anywhere; max-width: 70ch; }
  .credits { margin-block: var(--space-half); display: grid; gap: 8px; }
  .credits > div { display: grid; grid-template-columns: max-content minmax(0, 1fr); align-items: baseline; gap: 12px; }
  .credits dd { margin: 0; min-width: 0; }
  .credits dt { color: var(--ink-2); font-size: 13px; }
  .credits ul { display: flex; flex-wrap: wrap; gap: 8px 16px; list-style: none; padding: 0; margin: 0; }
  .credits li { overflow-wrap: anywhere; }

  .detail__parent {
    color: var(--ink-2);
    min-height: var(--touch-target);
    display: inline-flex;
    align-items: center;
  }

  .detail__line { color: var(--ink-2); }

  .detail__play {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space);
    margin-top: var(--space-half);
  }

  .facts {
    display: grid;
    gap: var(--space-half);
    margin: var(--space-half) 0 0;
  }

  .facts__row {
    display: flex;
    gap: var(--space-half);
    align-items: baseline;
  }

  .facts__row dt { min-width: 88px; }
  .facts__row dd { margin: 0; }

  .section {
    display: flex;
    flex-direction: column;
    gap: var(--space);
  }

  /* web.css .section-h: 20/700, onder 900 18. */
  .section-h {
    margin: 0;
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  @media (max-width: 899px) { .section-h { font-size: 18px; } }
</style>
