/**
 * Het einde van een titel: welke aflevering erna komt, en wanneer de kaart
 * "volgende aflevering" aftelt. De server kent geen aftitelingsmarkers, dus de
 * kaart hangt aan de laatste dertig seconden van het bestand. De volgende
 * aflevering komt uit `GET /items/{id}/children` van het seizoen en, op de
 * seizoensgrens, van de serie.
 */
import type { Item, ItemPage } from '../api/types';

/** De laatste seconden waarin de kaart of het slotscherm verschijnt. */
export const ENDING_WINDOW_S = 30;
/** Zo lang telt de knop af voordat de volgende aflevering vanzelf start. */
export const NEXT_COUNTDOWN_S = 20;

/**
 * Seconden tot de volgende aflevering vanzelf start, of null buiten het
 * eindvenster. Afgeleid van de afspeelpositie en niet van een klok: pauzeren
 * pauzeert het aftellen, en terugspoelen haalt de kaart weg.
 */
export function nextCountdown(current: number, total: number): number | null {
  if (!Number.isFinite(total) || total <= ENDING_WINDOW_S || !Number.isFinite(current)) return null;
  const remaining = total - current;
  if (remaining > ENDING_WINDOW_S) return null;
  return Math.max(0, Math.ceil(remaining - (ENDING_WINDOW_S - NEXT_COUNTDOWN_S)));
}

export type ChildrenReader = (
  itemId: string,
  query: { limit?: number; cursor?: string },
  signal?: AbortSignal
) => Promise<ItemPage>;

async function allChildren(children: ChildrenReader, id: string, signal?: AbortSignal): Promise<Item[]> {
  const items: Item[] = [];
  let cursor: string | undefined;
  do {
    const page = await children(id, { limit: 100, ...(cursor ? { cursor } : {}) }, signal);
    items.push(...page.items);
    cursor = page.next_cursor ?? undefined;
  } while (cursor);
  return items;
}

/** Het laagst genummerde kind van deze soort boven `index`. */
function firstAfter(items: Item[], kind: Item['kind'], index: number): Item | null {
  return items
    .filter((item) => item.kind === kind && typeof item.index === 'number' && item.index > index)
    .sort((a, b) => a.index! - b.index!)[0] ?? null;
}

/** De aflevering na deze: de volgende in het seizoen, anders de eerste van het volgende seizoen. */
export async function nextEpisode(
  children: ChildrenReader,
  episode: Item,
  season: Item | undefined,
  signal?: AbortSignal
): Promise<Item | null> {
  if (episode.kind !== 'episode' || !episode.parent_id || typeof episode.index !== 'number') return null;
  const sibling = firstAfter(await allChildren(children, episode.parent_id, signal), 'episode', episode.index);
  if (sibling || !season?.parent_id || typeof season.index !== 'number') return sibling;
  const nextSeason = firstAfter(await allChildren(children, season.parent_id, signal), 'season', season.index);
  return nextSeason ? firstAfter(await allChildren(children, nextSeason.id, signal), 'episode', -Infinity) : null;
}
