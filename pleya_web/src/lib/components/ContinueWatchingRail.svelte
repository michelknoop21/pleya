<script lang="ts">
  import { tick, untrack } from 'svelte';
  import type { Item } from '../api/types';
  import { session } from '../stores/session.svelte';
  import { continueArtwork, type ContinueArtwork } from '../util/homeArtwork';
  import { cardSubtitle } from '../util/format';
  import { t } from '../i18n';
  import HubRail from './HubRail.svelte';
  import MediaCard from './MediaCard.svelte';

  let { items }: { items: Item[] } = $props();
  let root = $state<HTMLDivElement | null>(null);
  let covers = $state(new Map<string, ContinueArtwork>());

  // The server orders resume items by most recent watch activity. Keep that
  // episode intact, collapsing only ancestry proven by this session's reads.
  const visibleItems = $derived.by(() => {
    const seenItems = new Set<string>();
    const seenShows = new Set<string>();
    return items.filter(item => {
      if (seenItems.has(item.id)) return false;
      seenItems.add(item.id);
      const showId = item.kind === 'episode' ? covers.get(item.id)?.showId : undefined;
      if (!showId) return true;
      if (seenShows.has(showId)) return false;
      seenShows.add(showId);
      return true;
    });
  });

  $effect(() => {
    const current = items;
    const controller = new AbortController();
    untrack(() => {
      covers = new Map();
      void continueArtwork(current, (id, signal) => session.client.item(id, signal), controller.signal,
        (id, artwork) => {
          if (controller.signal.aborted) return;
          const focused = document.activeElement;
          const focusedItem = focused instanceof HTMLAnchorElement && root?.contains(focused)
            ? current.find(item => focused.getAttribute('href') === `/items/${encodeURIComponent(item.id)}`) : undefined;
          covers = new Map(covers).set(id, artwork);
          if (!focusedItem || visibleItems.some(item => item.id === focusedItem.id)) return;
          const showId = covers.get(focusedItem.id)?.showId;
          const retained = visibleItems.find(item => covers.get(item.id)?.showId === showId);
          if (!retained) return;
          void tick().then(() => {
            if (controller.signal.aborted || !focused || focused.isConnected || document.activeElement !== document.body) return;
            const href = `/items/${encodeURIComponent(retained.id)}`;
            Array.from(root?.querySelectorAll('a') ?? []).find(link => link.getAttribute('href') === href)?.focus();
          });
        });
    });
    return () => controller.abort();
  });
</script>

<div class="continue-watching" bind:this={root}>
<HubRail title={t('home.continueWatching')} items={visibleItems} shape="poster">
  {#snippet card(item, index)}
    <MediaCard
      {item}
      eager={index < 8}
      shape="poster"
      title={covers.get(item.id)?.title}
      artworkId={covers.get(item.id)?.posterId ?? (item.kind === 'episode' ? null : item.artwork?.poster_id)}
      subtitle={item.kind === 'episode' ? [item.title, cardSubtitle(item)].filter(Boolean).join(' · ') : undefined}
    />
  {/snippet}
</HubRail>
</div>

<style>
  .continue-watching { display: contents; }
</style>
