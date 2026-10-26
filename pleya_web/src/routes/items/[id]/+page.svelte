<script lang="ts">
  import { page } from '$app/state';

  import Artwork from '#lib/components/Artwork.svelte';
  import MediaGrid from '#lib/components/MediaGrid.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import VersionPanel from '#lib/components/VersionPanel.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { formatDate, formatDuration } from '#lib/util/format.js';
  import { t } from '#lib/i18n/index.js';
  import { playerHref } from '#lib/player/route.js';
  import { formatPlayTime } from '#lib/player/keyboard.js';

  const itemId = $derived(page.params['id'] ?? '');

  let item = $state<Item | null>(null);
  let children = $state<Item[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  async function load(id: string, signal: AbortSignal): Promise<void> {
    loading = true;
    error = null;
    item = null;
    children = [];
    try {
      const loaded = await session.client.item(id, signal);
      if (signal.aborted) return;
      item = loaded;

      // Seizoenen van een serie en afleveringen van een seizoen komen uit
      // /children. Voor een film is dat een lege lijst en geen fout, dus die
      // aanvraag wordt overgeslagen in plaats van weggegooid.
      if (loaded.kind === 'show' || loaded.kind === 'season') {
        const page1 = await session.client.children(id, { limit: 100 }, signal);
        if (signal.aborted) return;
        children = page1.items;
      }
    } catch (err) {
      if (signal.aborted) return;
      error = describeError(err);
    } finally {
      if (!signal.aborted) loading = false;
    }
  }

  $effect(() => {
    const id = itemId;
    if (!id) return;
    const controller = new AbortController();
    void load(id, controller.signal);
    return () => controller.abort();
  });

  const version = $derived(item?.versions?.[0]);
  const playable = $derived(
    (item?.kind === 'movie' || item?.kind === 'episode') && (item?.versions?.length ?? 0) > 0
  );
  const resumeMs = $derived(
    item?.user_state && !item.user_state.watched && item.user_state.position_ms > 0
      ? item.user_state.position_ms
      : null
  );
  const childHeading = $derived(item?.kind === 'show' ? t('item.seasons') : t('item.episodes'));

  /*
   * Alleen wat `Item` vandaag draagt. Samenvatting, genres, cast,
   * beoordelingen, studio, tagline, trailers en extra's bestaan niet in dit
   * protocol; die komen in PS-7 en krijgen daar hun veld. Een plaatshouder
   * ervoor zou beloven wat de server niet heeft.
   */
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
      onRetry={() => void load(itemId, new AbortController().signal)}
    />
  </div>
{:else if item}
  <article class="detail">
    <header class="detail__head">
      <div class="detail__poster">
        <Artwork
          artworkId={item.artwork?.poster_id ?? item.artwork?.backdrop_id}
          alt=""
          shape={item.kind === 'episode' ? 'wide' : 'poster'}
          eager
        />
      </div>

      <div class="detail__meta">
        {#if item.parent_id}
          <a class="detail__parent t-small" href="/items/{item.parent_id}">
            {t('item.backToShow')}
          </a>
        {/if}
        <h1 class="t-headline">{item.title}</h1>
        <p class="detail__line t-body">
          {[item.year, item.kind === 'episode' && typeof item.index === 'number'
            ? t('item.episode', { index: item.index })
            : null,
          item.kind === 'season' && typeof item.index === 'number'
            ? t('item.season', { index: item.index })
            : null]
            .filter(Boolean)
            .join(' · ')}
        </p>

        {#if playable}
          <!-- S13.2: de kijkstatus wordt hier gelezen en getoond (PS-4E), niet geschreven. -->
          <div class="detail__play">
            {#if resumeMs}
              <a class="btn" href={playerHref(item.id, resumeMs)}>
                {t('player.resume', { time: formatPlayTime(resumeMs / 1000) })}
              </a>
              <a class="btn btn--secondary" href={playerHref(item.id)}>{t('player.playFromStart')}</a>
            {:else}
              <a class="btn" href={playerHref(item.id)}>{t('player.play')}</a>
            {/if}
          </div>
        {/if}

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
      </div>
    </header>

    {#if version}
      <VersionPanel {version} />
    {/if}

    {#if item.kind === 'show' || item.kind === 'season'}
      <section class="section">
        <h2 class="section-h">{childHeading}</h2>
        {#if children.length === 0}
          <StateView compact title={t('item.noChildren')} />
        {:else}
          <MediaGrid items={children} label={childHeading} />
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
    display: grid;
    gap: var(--space-1-5);
    grid-template-columns: 1fr;
  }

  @media (min-width: 600px) {
    .detail__head {
      grid-template-columns: minmax(160px, 240px) 1fr;
      align-items: start;
    }
  }

  .detail__poster {
    max-width: 240px;
    border-radius: var(--radius-md);
    overflow: hidden;
  }

  .detail__meta {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    min-width: 0;
  }

  .detail__parent {
    color: var(--ink-2);
    min-height: var(--touch-target);
    display: inline-flex;
    align-items: center;
  }

  .detail__line {
    color: var(--ink-2);
  }

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

  .facts__row dt {
    min-width: 88px;
  }

  .facts__row dd {
    margin: 0;
  }

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

  @media (max-width: 899px) {
    .section-h {
      font-size: 18px;
    }
  }
</style>
