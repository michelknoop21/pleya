import type { Item } from '../api/types';

export interface ContinueArtwork {
  posterId: string | null;
  title: string;
  showId?: string;
}

/** Resolve only the server's parent IDs; titles are never matching keys. */
export async function continueArtwork(
  items: Item[],
  getItem: (id: string, signal: AbortSignal) => Promise<Item>,
  signal: AbortSignal,
  onResolved?: (id: string, artwork: ContinueArtwork) => void
): Promise<Map<string, ContinueArtwork>> {
  const parents = new Map<string, Promise<Item>>();
  const read = (id: string) => {
    let pending = parents.get(id);
    if (!pending) {
      pending = getItem(id, signal);
      parents.set(id, pending);
    }
    return pending;
  };
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
        return [item.id, { posterId: show.artwork?.poster_id ?? fallback.posterId, title: show.title, showId: show.id }];
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

export function homeHero(items: Item[]): Item | undefined {
  return items.find(item => Boolean(item.artwork?.backdrop_id)) ?? items[0];
}
