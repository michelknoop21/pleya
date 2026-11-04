<script lang="ts">
  import { untrack } from 'svelte';
  import HubRail from './HubRail.svelte';
  import PageHeader from './PageHeader.svelte';
  import SkeletonPage from './SkeletonPage.svelte';
  import StateView from './StateView.svelte';
  import { session } from '../stores/session.svelte.js';
  import { describeError } from '../api/errors';
  import type { Item, LibraryItemsQuery } from '../api/types';
  import { t } from '../i18n';

  let { kind }: { kind: 'movies' | 'shows' } = $props();
  const libraries = $derived(session.libraries.filter(library => library.kind === kind));
  const title = $derived(kind === 'movies' ? t('nav.films') : t('nav.series'));
  const allLabel = $derived(kind === 'movies' ? t('catalog.allFilms') : t('catalog.allSeries'));
  const allHref = $derived(libraries.length === 1 ? `/libraries/${encodeURIComponent(libraries[0]!.id)}` : `/libraries?kind=${kind}`);
  let rows = $state<{id:string;title:string;items:Item[];href?:string}[]>([]);
  let loading = $state(true);
  let error = $state<unknown>(null);
  let retry = $state(0);

  async function load(signal: AbortSignal): Promise<void> {
    loading = true; error = null; rows = [];
    try {
      if (session.capabilities?.browse !== true) return;
      const watch = session.capabilities?.watch_state === true;
      const filters = session.capabilities?.filters === true;
      const groups = await Promise.all(libraries.map(async library => {
        const prefix = libraries.length > 1 ? ` · ${library.title}` : '';
        const base = `/libraries/${encodeURIComponent(library.id)}`;
        const previews: typeof rows = [];
        const items = async (id: string, label: string, query: LibraryItemsQuery) => {
          const url = new URL(base, 'http://catalog.invalid');
          for (const [key, value] of Object.entries(query)) {
            for (const entry of Array.isArray(value) ? value : [value]) if (entry !== undefined) url.searchParams.append(key, String(entry));
          }
          const page = await session.client.libraryItems(library.id, { ...query, limit: 24 }, signal);
          return { id: `${library.id}:${id}`, title: label + prefix, items: page.items, href: url.pathname + url.search };
        };
        if (kind === 'shows') {
          if (watch) previews.push({ id: `${library.id}:next`, title: t('home.nextUp') + prefix,
            items: (await session.client.hub('next_up', {library_id:library.id,limit:24}, signal)).items });
          previews.push({ id: `${library.id}:episodes`, title: t('catalog.newEpisodes') + prefix,
            items: (await session.client.hub('recently_added', {library_id:library.id,limit:24}, signal)).items });
        }
        previews.push(await items('recent', t('home.recentlyAdded'), {sort:'-added_at'}));
        if (filters && watch) previews.push(await items('unwatched', t('catalog.unwatched'), {watch:'unwatched',sort:'-added_at'}));
        if (filters) {
          const facets = await session.client.libraryFacets(library.id, signal);
          // shortcut: three genre previews; expand when the approved landing adds more rows.
          const genres = facets.genres.filter(genre => genre.count > 0).sort((a,b)=>b.count-a.count || a.value.localeCompare(b.value)).slice(0,3);
          previews.push(...await Promise.all(genres.map(genre => items(`genre:${genre.value}`,genre.value,{genre:[genre.value],sort:'-added_at'}))));
        }
        if (filters && watch) previews.push(await items('watched', t('catalog.recentlyWatched'), {watch:'watched',sort:'-last_played_at'}));
        return previews;
      }));
      if (!signal.aborted) rows = groups.flat();
    } catch (cause) { if (!signal.aborted) error = cause; }
    finally { if (!signal.aborted) loading = false; }
  }
  $effect(() => {
    void kind; void libraries; void retry; void session.capabilities;
    const controller = new AbortController();
    untrack(() => { void load(controller.signal); });
    return () => controller.abort();
  });
</script>

<svelte:head><title>{title} · {t('app.name')}</title></svelte:head>
<div class="landing__head">
  <PageHeader {title}>
    {#snippet actions()}{#if libraries.length > 0 && session.capabilities?.browse === true}<a class="btn btn--secondary btn--sm" href={allHref}>{allLabel} ›</a>{/if}{/snippet}
  </PageHeader>
</div>
{#if loading}
  <SkeletonPage variant="grid" />
{:else if error}
  <StateView kind="error" message={describeError(error)} onRetry={() => retry++} />
{:else if rows.every(row => row.items.length === 0)}
  <StateView title={t('home.emptyTitle')} message={t('home.emptyBody')}>
    {#snippet actions()}<a class="btn btn--sm" href="/server">{t('home.emptyAction')}</a>{/snippet}
  </StateView>
{:else}
  <div class="landing__rows">
    {#each rows as row (row.id)}<HubRail title={row.title} items={row.items} href={row.href} />{/each}
  </div>
{/if}
<style>
  .landing__head { padding: var(--page-top) var(--inset) 0; }
  .landing__rows { display: flex; flex-direction: column; gap: var(--section-gap); }
</style>
