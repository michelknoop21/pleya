<script lang="ts">
  import HubRail from '$lib/components/HubRail.svelte';
  import Hero from '$lib/components/Hero.svelte';
  import StateView from '$lib/components/StateView.svelte';
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

{#if loading}
  <StateView kind="loading" />
{:else if error}
  <StateView
    kind="error"
    message={error}
    onRetry={() => {
      const controller = new AbortController();
      void load(controller.signal);
    }}
  />
{:else if items.length === 0}
  <StateView title={t('home.emptyTitle')} message={t('home.emptyBody')} />
{:else}
  {#if hero}
    <Hero item={hero} />
  {/if}
  <div class="home">
    <HubRail title={t('home.recentlyAdded')} items={rail} />
  </div>
{/if}

<style>
  .home {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding-top: var(--space-2);
  }
</style>
