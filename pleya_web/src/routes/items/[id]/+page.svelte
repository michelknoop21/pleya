<script lang="ts">
  import { untrack } from 'svelte';
  import { emptyPager, loadNext, type PagerState } from '#lib/util/paging.js';
  import { page } from '$app/state';

  import Artwork from '#lib/components/Artwork.svelte';
  import DetailIcon from '#lib/components/DetailIcon.svelte';
  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import Select from '#lib/components/Select.svelte';
  import ItemPersonalActions from '#lib/components/ItemPersonalActions.svelte';
  import VersionPanel from '#lib/components/VersionPanel.svelte';
  import WatchedBy from '#lib/components/WatchedBy.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { formatDate, formatDuration } from '#lib/util/format.js';
  import { t } from '#lib/i18n/index.js';
  import { playerHref } from '#lib/player/route.js';
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
  let retry = $state(0);
  let moreMenu = $state<HTMLDetailsElement | null>(null);

  async function load(id: string, signal: AbortSignal): Promise<void> {
    loading = true;
    error = null;
    item = null;
    context = {};
    childPager = emptyPager();
    loadSignal = signal;
    selectedVersionId = '';
    try {
      const loaded = await session.client.item(id, signal);
      if (signal.aborted || id !== itemId) return;
      item = loaded;
      // Ancestor failures leave this item's metadata, playback and children
      // available. Do not make the whole page wait for inherited artwork.
      void videoContext(loaded, (parentId, active) => session.client.item(parentId, active), signal)
        .then(value => { if (!signal.aborted && id === itemId) context = value; });

      // Seizoenen van een serie en afleveringen van een seizoen komen uit
      // /children. Voor een film is dat een lege lijst en geen fout, dus die
      // aanvraag wordt overgeslagen in plaats van weggegooid.
      if (loaded.kind === 'show' || loaded.kind === 'season') {
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
  const credits = $derived((['actor', 'director', 'writer'] as const).map(role => ({
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
  const childHeading = $derived(item?.kind === 'show' ? t('item.seasons') : t('item.episodes'));
  const backdropId = $derived(item?.artwork?.backdrop_id ?? context.show?.artwork?.backdrop_id ?? context.season?.artwork?.backdrop_id);
  const posterId = $derived(item?.artwork?.poster_id ?? context.season?.artwork?.poster_id ?? context.show?.artwork?.poster_id);

  const durationMs = $derived(item?.duration_ms || version?.duration_ms || 0);
  const videoDetail = $derived(item != null && ['movie', 'show', 'season', 'episode'].includes(item.kind));
  const hasPersonalActions = $derived(session.capabilities?.favorites || session.capabilities?.ratings || session.capabilities?.watch_state || session.capabilities?.collections || session.capabilities?.playlists);
  const canManage = $derived(session.canAdminister && (item?.kind === 'movie' || item?.kind === 'show'));

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

<svelte:document onkeydown={event => { if (event.key === 'Escape' && moreMenu?.open && event.target instanceof Node && moreMenu.contains(event.target)) { moreMenu.open = false; moreMenu.querySelector('summary')?.focus(); } }} />
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
{:else if item}
  <article class="detail" class:detail--preplay={videoDetail}>
    {#if videoDetail}
      <a class="detail__back" href={item.parent_id ? `/items/${item.parent_id}` : item.kind === 'movie' ? '/films' : '/series'}><DetailIcon name="back" />{item.parent_id ? t('common.back') : t(item.kind === 'movie' ? 'nav.films' : 'nav.series')}</a>
    {/if}
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
        {#if videoDetail}<p class="detail__eyebrow">{t(item.kind === 'movie' ? 'nav.films' : 'nav.series')}</p>{/if}
        <h1 class="t-headline">{item.title}</h1>
        <p class="detail__line t-body">
          {[item.year, formatDuration(durationMs), item.kind === 'episode' && typeof item.index === 'number'
            ? t('item.episode', { index: item.index })
            : null,
          item.content_rating, ...(item.genres ?? []).filter(genre => genre.trim()),
          item.kind === 'season' && typeof item.index === 'number'
            ? t('item.season', { index: item.index })
            : null]
            .filter(Boolean)
            .join(' · ')}
        </p>

        {#if item.summary?.trim()}<p class="detail__summary t-body">{item.summary}</p>{/if}
        <div class="detail__actions">
        {#if playable}
          <!-- S13.2: de kijkstatus wordt hier gelezen en getoond (PS-4E), niet geschreven. -->
          <div class="detail__play">
            {#if resumeMs}
              <a class="btn" href={playerHref(item.id, resumeMs, version?.id)}>
                <DetailIcon name="play" />{t('player.resume', { time: formatPlayTime(resumeMs / 1000) })}
              </a>

            {:else}
              <a class="btn" href={playerHref(item.id, undefined, version?.id)}><DetailIcon name="play" />{t('player.play')}</a>
            {/if}
          </div>
        {/if}

          {#if item.kind === 'show' || item.kind === 'season'}
            <a class="btn" href="#detail-children"><DetailIcon name="play" />{item.kind === 'show' ? t('item.viewSeasons') : t('item.episodes')}</a>
          {/if}
        {#if hasPersonalActions}
          {#key item.id}
            <ItemPersonalActions compact {item} onchange={updated => { if (item?.id === updated.id) item = updated; }} />
          {/key}
        {/if}

          {#if (playable && resumeMs) || canManage || version}
            <details class="detail__more" bind:this={moreMenu}>
              <summary aria-label={t('item.moreActions')} title={t('item.moreActions')}><DetailIcon name="more" /></summary>
              <div class="detail__more-panel">
                {#if playable && resumeMs}<a href={playerHref(item.id, undefined, version?.id)}>{t('player.playFromStart')}</a>{/if}
                {#if canManage}
                  {#if session.capabilities?.metadata_overrides === true || session.capabilities?.artwork_choices === true}<a href="/admin/metadata/edit?item={encodeURIComponent(item.id)}">{t('admin.metadata.editor.title')}</a>{/if}
                  <a href="/admin/metadata/match?item={encodeURIComponent(item.id)}">{t('admin.match.title')}</a>
                {/if}
                {#if version}<a href="#detail-versions">{t('item.versions')}</a>{/if}
              </div>
            </details>
          {/if}
        </div>
        {#if playable && resumeMs && durationMs > 0}
          <div class="detail__progress">
            <progress value={Math.min(resumeMs, durationMs)} max={durationMs} aria-label={t('player.resume', { time: formatPlayTime(resumeMs / 1000) })}></progress>
            <span>{t('player.remaining', { duration: formatDuration(Math.max(0, durationMs - resumeMs)) ?? '' })}</span>
          </div>
        {/if}

      </div>
    </header>

    {#if item.kind === 'show' || item.kind === 'season'}
      <section class="section detail__section detail__children" id="detail-children">
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
    {#if credits.length}
      <section class="detail__section" aria-labelledby="detail-credits">
        <h2 id="detail-credits" class="section-h">{t('item.credits')}</h2>
        <ul class="credits">
          {#each credits as group (group.role)}
            {#each group.people as person, index (index)}
              <li><strong>{person.name}</strong><span>{group.label}{#if person.character?.trim()} · {person.character}{/if}</span></li>
            {/each}
          {/each}
        </ul>
      </section>
    {/if}
    {#if version}
      <section class="detail__section" id="detail-versions">
        <h2 class="section-h">{t('item.mediaInfo')}</h2>
        <VersionPanel {version} plain>
        {#snippet picker()}
        {#if versionOptions.length > 1}
          <Select label={t('item.version')} value={version?.id ?? ''} options={versionOptions} onchange={value => selectedVersionId = value} />
        {/if}
        {/snippet}
        </VersionPanel>
      </section>
    {/if}
    <div class="detail__section detail__additional">
        {#if facts.length > 0}
          <dl class="facts">
            {#each facts as fact (fact.label)}
              <div class="facts__row">
                <dt class="t-small">{fact.label}</dt>
                <dd class="t-body">{fact.value}</dd>
              </div>
            {/each}
          </dl>
        {/if}
      {#if session.capabilities?.watch_state}<WatchedBy {item} />{/if}
    </div>

  </article>
{/if}

<style>
.detail { display:flex;flex-direction:column;padding:0;min-width:0; }
.detail__back { display:inline-flex;align-items:center;gap:8px;min-height:64px;padding:20px 44px 0;color:var(--ink-2);font-size:13px; }
.detail__head { position:relative;isolation:isolate;display:grid;gap:24px;padding:36px 44px;background:var(--bg); }
.detail__meta { display:flex;flex-direction:column;align-items:flex-start;gap:18px;min-width:0;max-width:610px; }
.detail__head h1 { font-family:var(--font-sans);font-size:clamp(36px,4vw,58px);font-weight:700;line-height:1.08;letter-spacing:-.045em;overflow-wrap:anywhere;margin:0; }
.detail__eyebrow { color:var(--ink-2);text-transform:uppercase;letter-spacing:.12em;font-size:12px;font-weight:700;margin:0; }
.detail__line { color:var(--ink-2);font-size:13px;margin:4px 0; }
.detail__summary { white-space:pre-line;overflow-wrap:anywhere;max-width:610px;font-size:15px;line-height:1.65;margin:0 0 8px; }
.detail__parent { color:var(--ink-2);min-height:44px;display:inline-flex;align-items:center; }
.detail__poster { width:180px;aspect-ratio:2 / 3;overflow:hidden;border-radius:var(--radius-md); }
.detail__poster :global(.artwork) { height:100%; }
.detail__backdrop { position:absolute;inset:0;overflow:hidden;z-index:-1; }
.detail__backdrop :global(.artwork) { height:100%; }
.detail__backdrop :global(img) { object-position:70% 25%; }
.detail__backdrop::after { content:'';position:absolute;inset:0;background:linear-gradient(90deg,var(--bg) 1%,color-mix(in srgb,var(--bg) 92%,transparent) 28%,transparent 86%),linear-gradient(0deg,var(--bg),transparent 75%); }
.detail__actions { display:flex;align-items:center;gap:10px;flex-wrap:wrap;width:100%; }
.detail__play { display:flex;flex-wrap:wrap;gap:10px; }
.detail__actions :global(.btn) { border-radius:999px;min-height:48px; }
.detail__play .btn,.detail__actions > .btn { background:var(--ink);color:var(--bg);border-color:transparent;display:inline-flex;align-items:center;gap:12px; }
.detail__progress { display:grid;gap:8px;width:245px;max-width:100%;margin-top:6px;font-size:12px;color:var(--ink-2); }
progress { appearance:none;width:100%;height:3px;border:none;border-radius:4px;overflow:hidden;background:var(--hairline); }
progress::-webkit-progress-bar { background:var(--hairline); } progress::-webkit-progress-value { background:var(--accent); } progress::-moz-progress-bar { background:var(--accent); }
.detail__more { min-width:48px; }
.detail__more summary { list-style:none;width:48px;height:48px;border-radius:50%;display:grid;place-items:center;background:var(--panel);cursor:pointer; }
.detail__more summary::-webkit-details-marker { display:none; }
.detail__more[open] { flex-basis:100%; }
.detail__more-panel { display:grid;width:min(320px,100%);padding:8px;margin-top:8px;background:var(--panel);border:1px solid var(--hairline);border-radius:14px; }
.detail__more-panel a { padding:12px;min-height:44px;border-radius:8px;font-size:14px; } .detail__more-panel a:hover { background:var(--fill); }
.detail__section { padding:0 44px 40px;min-width:0;scroll-margin-top:24px; }
.section-h { font-size:24px;font-weight:700;line-height:1.3;letter-spacing:-.035em;margin:0 0 22px; }
.credits { display:flex;flex-wrap:wrap;gap:24px 48px;padding:26px 0 10px;margin:0;list-style:none;border-top:1px solid var(--hairline); }
.credits li { display:flex;flex-direction:column;gap:4px;max-width:280px;overflow-wrap:anywhere; } .credits strong { font-size:14px;font-weight:600; } .credits span { color:var(--ink-2);font-size:12px; }
 .detail__additional:empty { display:none; }
.detail__additional { display:grid;gap:24px; } .facts { display:flex;flex-wrap:wrap;gap:16px 40px;margin:0; } .facts__row { display:grid;gap:6px; } .facts__row dt { color:var(--ink-2);font-size:12px; } .facts__row dd { margin:0;font-size:14px; }
.detail__children :global(.grid) { grid-template-columns:repeat(auto-fill,minmax(140px,148px));gap:24px 20px; }
@media(min-width:900px) { .detail--preplay .detail__head { min-height:610px;padding-top:90px;padding-bottom:72px;align-content:start; } .detail__head--artwork .detail__poster { display:none; } .detail__head:not(.detail__head--artwork) { grid-template-columns:180px minmax(0,1fr); } }
@media(max-width:899px) { .detail__back { min-height:45px;padding:12px 22px 0; } .detail__head { padding:24px 22px 40px; } .detail__backdrop { height:430px; } .detail__backdrop::after { background:linear-gradient(0deg,var(--bg) 2%,color-mix(in srgb,var(--bg) 88%,transparent) 48%,transparent 100%); } .detail__poster { width:100px; } .detail__meta { gap:16px; } .detail__head h1 { font-size:36px; } .detail__section { padding:0 22px 30px; } .detail__actions :global(.btn),.detail__more summary { min-height:44px; } .credits { display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px; } .detail__children :global(.grid) { grid-template-columns:repeat(2,minmax(0,1fr)); } }
</style>
