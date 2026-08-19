<script lang="ts">
  import { page } from '$app/state';

  import Artwork from '$lib/components/Artwork.svelte';
  import MediaGrid from '$lib/components/MediaGrid.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { describeError } from '$lib/api/errors';
  import type { Item } from '$lib/api/types';
  import { formatDate, formatDuration } from '$lib/util/format';
  import { t } from '$lib/i18n';

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
  <StateView kind="loading" />
{:else if error}
  <StateView
    kind="error"
    message={error}
    onRetry={() => void load(itemId, new AbortController().signal)}
  />
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
      <section class="section">
        <h2 class="t-title-lg">{t('item.versions')}</h2>
        <div class="version">
          <p class="t-small">
            {[version.container, formatDuration(version.duration_ms)].filter(Boolean).join(' · ')}
          </p>

          {#if version.video_streams && version.video_streams.length > 0}
            <h3 class="t-title">{t('item.video')}</h3>
            <ul class="streams">
              {#each version.video_streams as stream (stream.id)}
                <li class="t-small">
                  {[
                    stream.codec,
                    stream.width && stream.height ? `${stream.width}×${stream.height}` : null,
                    stream.bit_depth ? `${stream.bit_depth}-bit` : null,
                    stream.frame_rate ? `${stream.frame_rate.toFixed(3)} fps` : null
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </li>
              {/each}
            </ul>
          {/if}

          {#if version.audio_streams && version.audio_streams.length > 0}
            <h3 class="t-title">{t('item.audio')}</h3>
            <ul class="streams">
              {#each version.audio_streams as stream (stream.id)}
                <li class="t-small">
                  {[
                    stream.language,
                    stream.codec,
                    stream.channels ? `${stream.channels}ch` : null,
                    stream.title,
                    stream.is_default ? t('item.default') : null
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </li>
              {/each}
            </ul>
          {/if}

          {#if version.subtitle_streams && version.subtitle_streams.length > 0}
            <h3 class="t-title">{t('item.subtitles')}</h3>
            <ul class="streams">
              {#each version.subtitle_streams as stream (stream.id)}
                <li class="t-small">
                  {[
                    stream.language,
                    stream.format,
                    stream.is_forced ? t('item.forced') : null,
                    stream.is_hearing_impaired ? t('item.sdh') : null,
                    stream.is_external ? t('item.external') : null
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </li>
              {/each}
            </ul>
          {/if}
        </div>
      </section>
    {/if}

    {#if item.kind === 'show' || item.kind === 'season'}
      <section class="section">
        <h2 class="t-title-lg">{childHeading}</h2>
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
    padding: var(--space-1-5) var(--page-inset, var(--space));
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
    color: var(--text-muted);
    min-height: var(--touch-target);
    display: inline-flex;
    align-items: center;
  }

  .detail__line {
    color: var(--text-muted);
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

  .version {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    padding: var(--space);
    background: var(--surface);
    border: 1px solid var(--outline);
    border-radius: var(--radius-card);
  }

  .streams {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
</style>
