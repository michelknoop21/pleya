<!--
  /items/{id}/play: de browserspeler (S13.2, S18.3). `?version=` kiest een
  versie, `?t=` een hervatpositie in seconden; die komt van de knop "Verder
  vanaf" op de detailpagina, die hem uit `user_state.position_ms` leest. De
  speler zelf schrijft geen kijkstatus (S13.3).

  De route laadt het item voor titel, duur en sporen; het afspeelpad zelf loopt
  in Player via `POST /playback/plan`.
-->
<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';

  import Player from '#lib/player/Player.svelte';
  import { browserPlayerDeps } from '#lib/player/browserDeps.js';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { t } from '#lib/i18n/index.js';

  const itemId = $derived(page.params['id'] ?? '');
  const versionParam = $derived(page.url.searchParams.get('version'));
  const startAt = $derived.by(() => {
    const raw = Number(page.url.searchParams.get('t') ?? 0);
    return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 0;
  });

  let item = $state<Item | null>(null);
  let error = $state<string | null>(null);

  async function load(id: string, signal: AbortSignal): Promise<void> {
    item = null;
    error = null;
    try {
      const loaded = await session.client.item(id, signal);
      if (!signal.aborted) item = loaded;
    } catch (err) {
      if (!signal.aborted) error = describeError(err);
    }
  }

  $effect(() => {
    const id = itemId;
    if (!id) return;
    const controller = new AbortController();
    void load(id, controller.signal);
    return () => controller.abort();
  });

  const version = $derived(
    item?.versions?.find((v) => v.id === versionParam) ?? item?.versions?.[0]
  );

  function close(): void {
    void goto(`/items/${encodeURIComponent(itemId)}`);
  }

  // De schil stuurt bij `signed-out` zelf naar /login.
  function login(): void {
    session.signOut();
  }
</script>

<svelte:head><title>{item?.title ?? t('player.title')} · {t('app.name')}</title></svelte:head>

{#if error}
  <div class="play-state">
    <StateView kind="error" message={error} onRetry={() => void load(itemId, new AbortController().signal)} />
  </div>
{:else if !item}
  <SkeletonPage variant="compact" />
{:else}
  {#key `${item.id}:${version?.id ?? ''}`}
    <Player
      {item}
      {version}
      {startAt}
      deps={browserPlayerDeps(session.client, session.capabilities)}
      onclose={close}
      onlogin={login}
    />
  {/key}
{/if}

<style>
  .play-state {
    padding: var(--space-3) var(--inset);
  }
</style>
