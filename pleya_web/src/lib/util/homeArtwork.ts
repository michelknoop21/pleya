import type { Item } from '../api/types';
import { t } from '../i18n';
import { videoContext } from './videoContext';

export type ItemReader = (id: string, signal: AbortSignal) => Promise<Item>;

export interface ContinueArtwork {
  posterId: string | null;
  title: string;
}

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

/** Resolve only the server's parent IDs; titles are never matching keys. */
export async function continueArtwork(
  items: Item[],
  getItem: ItemReader,
  signal: AbortSignal,
  onResolved?: (id: string, artwork: ContinueArtwork) => void
): Promise<Map<string, ContinueArtwork>> {
  const reader = dedupeReader(getItem);
  const read = (id: string) => reader(id, signal);
  const entries = await Promise.all(items.map(async (item): Promise<[string, ContinueArtwork]> => {
    const own = { posterId: item.kind === 'episode' ? null : item.artwork?.poster_id ?? null, title: item.title };
    if (item.kind !== 'episode' || !item.parent_id || signal.aborted) return [item.id, own];
    try {
      const season = await read(item.parent_id);
      if (signal.aborted || season.id !== item.parent_id || season.kind !== 'season') return [item.id, own];
      const fallback = { posterId: season.artwork?.poster_id ?? null, title: item.title };
      if (!season.parent_id) return [item.id, fallback];
      try {
        const show = await read(season.parent_id);
        if (signal.aborted || show.id !== season.parent_id || show.kind !== 'show') return [item.id, fallback];
        return [item.id, { posterId: show.artwork?.poster_id ?? fallback.posterId, title: show.title }];
      } catch {
        return [item.id, fallback];
      }
    } catch {
      return [item.id, own];
    }
  }).map(pending => pending.then(entry => {
    if (!signal.aborted) onResolved?.(entry[0], entry[1]);
    return entry;
  })));
  return new Map(entries);
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
