<script lang="ts">
  import HubRail from '#lib/components/HubRail.svelte';
  import ContinueWatchingRail from '#lib/components/ContinueWatchingRail.svelte';
  import Hero from '#lib/components/Hero.svelte';
  import PageHeader from '#lib/components/PageHeader.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { t } from '#lib/i18n/index.js';
  import { playerHref } from '#lib/player/route.js';
  import { homeHero } from '#lib/util/homeArtwork.js';

  let items = $state<Item[]>([]);
  let continuing = $state<Item[]>([]);
  let next = $state<Item[]>([]);
  let recent = $state<{ id: string; title: string; items: Item[] }[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  async function load(signal: AbortSignal): Promise<void> {
    loading = true;
    error = null;
    try {
      const libraries = session.libraries.filter((library) => library.kind === 'movies' || library.kind === 'shows');
      const watchState = session.capabilities?.watch_state === true;
      const [page, continuePage, nextPage, libraryPages] = await Promise.all([
        session.client.hub('recently_added', { limit: 5 }, signal),
        watchState ? session.client.hub('continue_watching', { limit: 24 }, signal) : { items: [] },
        watchState ? session.client.hub('next_up', { limit: 24 }, signal) : { items: [] },
        Promise.all(libraries.map(async (library) => ({
          id: library.id,
          title: library.title,
          items: (await session.client.hub('recently_added', { library_id: library.id, limit: 24 }, signal)).items
        })))
      ]);
      if (signal.aborted) return;
      items = page.items;
      continuing = continuePage.items;
      next = nextPage.items;
      recent = libraryPages;
    } catch (err) {
      if (signal.aborted) return;
      error = describeError(err);
    } finally {
      if (!signal.aborted) loading = false;
    }
  }

  $effect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  });

  const hero = $derived(homeHero(items));
  const empty = $derived(items.length === 0 && continuing.length === 0 && next.length === 0 && recent.every((row) => row.items.length === 0));
</script>

<svelte:head><title>{t('home.title')} · {t('app.name')}</title></svelte:head>

<!--
  Laden is beeld 15: het skelet in de maten van hero en rij, met een verborgen
  h1 omdat de echte h1 (de titel in de hero) er nog niet is. Fout en leeg
  hebben geen hero, dus daar staat de paginakop zichtbaar boven de staat, zoals
  "Boeken" boven de lege staat in 13.
-->
{#if loading}
  <SkeletonPage cinema variant="home" heading={t('home.title')} />
{:else if error}
  <div class="home-page">
    <PageHeader title={t('home.title')} />
    <StateView
      kind="error"
      message={error}
      onRetry={() => {
        const controller = new AbortController();
        void load(controller.signal);
      }}
    />
  </div>
{:else if empty}
  <div class="home-page">
    <PageHeader title={t('home.title')} />
    <!-- De uitweg is Mijn Pleya: daar staan de bibliotheken en hun scanstand. -->
    <StateView title={t('home.emptyTitle')} message={t('home.emptyBody')}>
      {#snippet actions()}
        <a class="btn btn--sm" href="/server">{t('home.emptyAction')}</a>
      {/snippet}
    </StateView>
  </div>
{:else}
  {#if hero}
    <Hero cinema item={hero} summary={hero.summary ?? undefined} playHref={session.capabilities?.playback_plan === true && (hero.kind === 'movie' || hero.kind === 'episode') && (hero.versions?.length ?? 0) > 0 ? playerHref(hero.id) : undefined} />
  {/if}
  <div class="home" class:home--with-hero={Boolean(hero)}>
    {#if !hero}<h1 class="sr-only">{t('home.title')}</h1>{/if}
    <ContinueWatchingRail items={continuing} />
    <HubRail title={t('home.nextUp')} items={next} />
    {#each recent as row (row.id)}
      <HubRail title={`${t('home.recentlyAdded')} · ${row.title}`} items={row.items} href={`/libraries/${encodeURIComponent(row.id)}`} />
    {/each}
  </div>
{/if}

<style>
  /* Tussen hero en rij de ruimte van .section in web.css; het skelet leest
     hetzelfde token, zodat de rij niet verspringt als de data binnenkomt. */
  .home {
    display: flex;
    flex-direction: column;
    gap: var(--section-gap);
    padding-top: 0;
    position: relative;

  }

  .home--with-hero { margin-top: -24px; }

  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .home-page {
    padding: var(--page-top) var(--inset) 0;
  }
</style>
