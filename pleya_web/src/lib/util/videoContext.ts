import type { Item } from '../api/types';

export interface VideoContext { season?: Item; show?: Item }

/** Presentation only: an ancestor never takes ownership of playback or user state. */
export async function videoContext(
  item: Item,
  getItem: (id: string, signal: AbortSignal) => Promise<Item>,
  signal: AbortSignal
): Promise<VideoContext> {
  if (signal.aborted || !item.parent_id || (item.kind !== 'episode' && item.kind !== 'season')) return {};
  let season: Item | undefined = item.kind === 'season' ? item : undefined;
  try {
    if (!season) {
      const parent = await getItem(item.parent_id, signal);
      if (signal.aborted || parent.id !== item.parent_id || parent.kind !== 'season') return {};
      season = parent;
    }
    if (!season.parent_id) return { season };
    const show = await getItem(season.parent_id, signal);
    if (signal.aborted) return {};
    if (show.id !== season.parent_id || show.kind !== 'show') return { season };
    return { season, show };
  } catch {
    return signal.aborted ? {} : season ? { season } : {};
  }
}
