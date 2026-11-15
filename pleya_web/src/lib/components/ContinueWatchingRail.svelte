<!--
  Verder kijken: liggende kaarten (16:9) met de voortgangsbalk onderin het
  beeld. Een aflevering toont haar eigen still en anders de achtergrond van de
  serie, met de serienaam als titel en daaronder seizoen, aflevering, de
  resterende tijd en de titel van de aflevering. De resterende tijd staat voor
  de afleveringstitel, zodat een lange titel haar niet wegdrukt. Een film toont
  zijn titel en de resterende tijd. De link en de kijkstatus blijven van de
  aflevering zelf.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import type { Item } from '../api/types';
  import { session } from '../stores/session.svelte';
  import { dedupeReader, episodeCards, type EpisodeCard, type ItemReader } from '../util/homeArtwork';
  import { cardSubtitle } from '../util/format';
  import { t } from '../i18n';
  import HubRail from './HubRail.svelte';
  import MediaCard from './MediaCard.svelte';

  /** `getParent`: de gedeelde lezer van Home, zodat een serie één keer gelezen wordt. */
  let { items, getParent }: { items: Item[]; getParent?: ItemReader } = $props();
  let episodes = $state(new Map<string, EpisodeCard>());

  $effect(() => {
    const current = items;
    const controller = new AbortController();
    untrack(() => {
      episodes = new Map();
      const read = getParent ?? dedupeReader((id, signal) => session.client.item(id, signal));
      void episodeCards(current, 'wide', read, controller.signal, (id, card) => {
        if (!controller.signal.aborted) episodes = new Map(episodes).set(id, card);
      });
    });
    return () => controller.abort();
  });

  function subtitle(item: Item, episode: EpisodeCard | undefined): string | undefined {
    if (item.kind !== 'episode') return undefined;
    // Zonder gevonden serie is de afleveringstitel al de kaarttitel.
    const own = episode && episode.title !== item.title ? item.title : null;
    return [episode?.subtitle, cardSubtitle(item), own].filter(Boolean).join(' · ');
  }
</script>

<HubRail title={t('home.continueWatching')} {items} shape="wide">
  {#snippet card(item, index)}
    {@const episode = episodes.get(item.id)}
    <MediaCard
      {item}
      eager={index < 8}
      shape="wide"
      quickActions
      title={episode?.title}
      artworkId={episode ? episode.artworkId : undefined}
      subtitle={subtitle(item, episode)}
    />
  {/snippet}
</HubRail>
