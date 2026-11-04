import type { Collection, Item, Playlist } from '../../api/types';
import { knownVisibility } from '../../api/lists';
import { formatDuration, itemProgress, isWatched } from '../../util/format';
import { plural, t } from '../../i18n';

/** De onderregel van een verzameling: wie hem bezit of voor wie hij zichtbaar is. */
export function collectionMeta(collection: Collection): string {
  const count = plural('lists.titles', collection.item_count);
  if (!collection.is_owner) return `${count} · ${t('lists.byOwner', { name: collection.owner.username })}`;
  const visibility = knownVisibility(collection.visibility);
  if (visibility === 'private') return `${count} · ${t('lists.private')}`;
  const names = (collection.shared_with ?? []).map((user) => user.username).join(', ');
  if (visibility === 'users' && names) return `${count} · ${t('lists.visibleFor', { names })}`;
  return `${count} · ${t('lists.shared')}`;
}

export function playlistMeta(playlist: Playlist): string {
  const duration = formatDuration(playlist.duration_ms);
  return [plural('lists.titles', playlist.item_count), duration].filter(Boolean).join(' · ');
}

/** Rij 18: jaar, duur en wat de kijkstatus erover zegt. */
export function rowMeta(item: Item): string {
  const progress = itemProgress(item);
  const left = progress ? formatDuration(progress.remainingMs) : null;
  const parts = [item.year ? String(item.year) : null, formatDuration(item.duration_ms)];
  if (isWatched(item)) parts.push(t('card.watched').toLocaleLowerCase());
  else if (left) parts.push(t('card.remaining', { duration: left }));
  return parts.filter(Boolean).join(' · ');
}

/** Een aflevering noemt haar plek in de serie niet in `title`; de rij wel als dat kan. */
export function rowPercent(item: Item): number | null {
  const progress = itemProgress(item);
  return progress ? Math.round(progress.fraction * 100) : null;
}
