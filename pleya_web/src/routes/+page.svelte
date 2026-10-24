<script lang="ts">
  import HubRail from '$lib/components/HubRail.svelte';
  import Hero from '$lib/components/Hero.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import SkeletonPage from '$lib/components/SkeletonPage.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { describeError } from '$lib/api/errors';
  import type { Item } from '$lib/api/types';
  import { t } from '$lib/i18n';

  let items = $state<Item[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  async function load(signal: AbortSignal): Promise<void> {
    loading = true;
    error = null;
    try {
      const page = await session.client.hub('recently_added', { limit: 24 }, signal);
      if (signal.aborted) return;
      items = page.items;
    } catch (err) {
      if (signal.aborted) return;
      error = describeError(err);
    } finally {
      if (!signal.aborted) loading = false;
    }
  }

  /*
   * `continue_watching` en `next_up` worden niet opgevraagd. `capabilities`
   * zegt vandaag `watch_state: false`, en dan levert de server per definitie
   * lege lijsten. Ze toch ophalen zou twee aanvragen per bezoek kosten om
   * daarna niets te tekenen; capabilities is leidend, dus dit is de plek waar
   * die vraag beantwoord hoort te worden.
   */
  $effect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  });

  const hero = $derived(items[0]);
  const rail = $derived(items);
</script>

<svelte:head><title>{t('home.title')} · {t('app.name')}</title></svelte:head>

<!--
  Laden is beeld 15: het skelet in de maten van hero en rij, met een verborgen
  h1 omdat de echte h1 (de titel in de hero) er nog niet is. Fout en leeg
  hebben geen hero, dus daar staat de paginakop zichtbaar boven de staat, zoals
  "Boeken" boven de lege staat in 13.
-->
{#if loading}
  <SkeletonPage variant="home" heading={t('home.title')} />
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
{:else if items.length === 0}
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
    <Hero item={hero} />
  {/if}
  <div class="home">
    <HubRail title={t('home.recentlyAdded')} items={rail} />
  </div>
{/if}

<style>
  /* Tussen hero en rij de ruimte van .section in web.css; het skelet leest
     hetzelfde token, zodat de rij niet verspringt als de data binnenkomt. */
  .home {
    display: flex;
    flex-direction: column;
    gap: var(--section-gap);
    padding-top: var(--section-gap);
  }

  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .home-page {
    padding: var(--page-top) var(--inset) 0;
  }
</style>
