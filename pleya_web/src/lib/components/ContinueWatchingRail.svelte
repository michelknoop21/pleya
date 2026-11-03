<script lang="ts">
  import { untrack } from 'svelte';
  import type { Item } from '../api/types';
  import { session } from '../stores/session.svelte';
  import { continueArtwork, type ContinueArtwork } from '../util/homeArtwork';
  import { cardSubtitle } from '../util/format';
  import { t } from '../i18n';
  import HubRail from './HubRail.svelte';
  import MediaCard from './MediaCard.svelte';

  let { items }: { items: Item[] } = $props();
  let covers = $state(new Map<string, ContinueArtwork>());

  $effect(() => {
    const current = items;
    const controller = new AbortController();
    untrack(() => {
      covers = new Map();
      void continueArtwork(current, (id, signal) => session.client.item(id, signal), controller.signal,
        (id, artwork) => { if (!controller.signal.aborted) covers = new Map(covers).set(id, artwork); });
    });
    return () => controller.abort();
  });
</script>

<HubRail title={t('home.continueWatching')} {items} shape="poster">
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
