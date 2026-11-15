import type { Item } from '../api/types';
import { t } from '../i18n';
import { videoContext } from './videoContext';

export type ItemReader = (id: string, signal: AbortSignal) => Promise<Item>;

/**
 * One read per parent ID for the lifetime of the returned reader. Callers
 * create one per load (and per profile), so a season shared by ten episodes,
 * or by two rails on Home, is fetched once.
 */
export function dedupeReader(getItem: ItemReader): ItemReader {
  const parents = new Map<string, Promise<Item>>();
  return (id, signal) => {
    let pending = parents.get(id);
    if (!pending) {
      pending = getItem(id, signal);
      parents.set(id, pending);
    }
    return pending;
  };
}

export interface EpisodeCard {
  artworkId: string | null;
  title: string;
  subtitle: string | undefined;
}

/**
 * How an episode reads on a card in a rail: the series name as title, "S1 · E5"
 * underneath, and an image even when the episode has no still. A wide card
 * shows the episode's own image, else the series backdrop, else the series
 * poster; a poster card the series poster first. Navigation and watch state
 * stay with the episode itself.
 */
export function episodeCard(item: Item, shape: 'poster' | 'wide', season?: Item, show?: Item): EpisodeCard {
  const own = item.artwork?.backdrop_id ?? item.artwork?.poster_id ?? null;
  const parentWide = show?.artwork?.backdrop_id ?? season?.artwork?.backdrop_id;
  const parentPoster = show?.artwork?.poster_id ?? season?.artwork?.poster_id;
  const artworkId = shape === 'wide'
    ? own ?? parentWide ?? parentPoster ?? null
    : parentPoster ?? own ?? parentWide ?? null;
  const seasonIndex = season?.index;
  const episodeIndex = item.index;
  let subtitle: string | undefined;
  if (typeof seasonIndex === 'number' && typeof episodeIndex === 'number') {
    subtitle = t('card.episodeCode', { season: seasonIndex, episode: episodeIndex });
  } else if (typeof episodeIndex === 'number') {
    subtitle = t('item.episode', { index: episodeIndex });
  }
  return { artworkId, title: show?.title ?? item.title, subtitle };
}

/** Resolve the ancestors of every episode in a rail, reporting each as it lands. */
export async function episodeCards(
  items: Item[],
  shape: 'poster' | 'wide',
  getItem: ItemReader,
  signal: AbortSignal,
  onResolved?: (id: string, card: EpisodeCard) => void
): Promise<Map<string, EpisodeCard>> {
  const entries = await Promise.all(items.filter(item => item.kind === 'episode').map(async (item): Promise<[string, EpisodeCard]> => {
    const context = await videoContext(item, getItem, signal);
    const card = episodeCard(item, shape, context.season, context.show);
    if (!signal.aborted) onResolved?.(item.id, card);
    return [item.id, card];
  }));
  return new Map(entries);
}

export function homeHero(items: Item[]): Item | undefined {
  return items.find(item => Boolean(item.artwork?.backdrop_id)) ?? items[0];
}
