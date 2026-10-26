/**
 * De gegevens en rekenregels van Match en overrides (scherm 36).
 *
 * Wat het contract draagt: de lijst titels die aandacht vragen met hun
 * alternatieven (`GET /metadata/attention`), een kandidaat of een eigen nummer
 * kiezen (`PUT /items/{id}/metadata-match`) en de match afwijzen
 * (`DELETE /items/{id}/metadata-match`).
 *
 * Wat niet, en dus ook niet in dit scherm staat: velden per titel overschrijven
 * met herkomst (provenance), artwork kiezen met pin, een score of poster per
 * kandidaat (`MetadataAlternative` kent alleen nummer, titel en jaar), een
 * providerronde starten en de statistiek ervan. Dat volgt met S22.5.
 */
import type { MetadataAttention, MetadataAttentionList } from '../../api/types';
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { PillTone } from '../../components/StatusPill.svelte';
import { plural, t } from '../../i18n';

export const MATCH_LIMIT = 50;

/** Hetzelfde patroon als `SetMetadataMatchRequest.external_id` in het contract. */
const EXTERNAL_ID = /^[1-9][0-9]{0,9}$/;

export function isValidExternalId(value: string): boolean {
  return EXTERNAL_ID.test(value);
}

const ORDER: Record<string, number> = { ambiguous: 0, unmatched: 1, failed: 2, rejected: 3 };

/** Wat een keuze vraagt eerst; daarbinnen op titel. */
export function sortedAttention(items: MetadataAttention[]): MetadataAttention[] {
  return [...items].sort(
    (a, b) =>
      (ORDER[a.state] ?? 9) - (ORDER[b.state] ?? 9) || a.title.localeCompare(b.title)
  );
}

export function loadMatch(
  api: AdminSettingsApi,
  signal?: AbortSignal
): Promise<MetadataAttentionList> {
  return api.metadataAttention(MATCH_LIMIT, signal);
}

export function titleOf(item: Pick<MetadataAttention, 'title' | 'year'>): string {
  return item.year ? `${item.title} (${item.year})` : item.title;
}

export function kindLabel(kind: string): string {
  return kind === 'movie'
    ? t('admin.match.kind.movie')
    : kind === 'show'
      ? t('admin.match.kind.show')
      : kind;
}

export function outcomeLabel(item: MetadataAttention): string {
  switch (item.state) {
    case 'failed':
      return t('admin.match.outcome.failed');
    case 'rejected':
      return t('admin.match.outcome.rejected');
    default:
      return item.alternatives.length === 0
        ? t('admin.match.outcome.none')
        : plural('admin.match.outcome.candidates', item.alternatives.length);
  }
}

export function outcomeTone(item: MetadataAttention): PillTone {
  if (item.state === 'failed') return 'err';
  if (item.state === 'rejected') return 'idle';
  return item.alternatives.length === 0 ? 'idle' : 'warn';
}

export function hintLabel(state: string): string {
  switch (state) {
    case 'ambiguous':
      return t('admin.match.hint.ambiguous');
    case 'unmatched':
      return t('admin.match.hint.unmatched');
    case 'failed':
      return t('admin.match.hint.failed');
    case 'rejected':
      return t('admin.match.hint.rejected');
    default:
      return '';
  }
}

/** Afwijzen is idempotent, maar bij een al afgewezen titel zegt het niets. */
export function canReject(item: MetadataAttention): boolean {
  return item.state !== 'rejected';
}

export function countByState(list: MetadataAttentionList): { state: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const item of list.items) counts.set(item.state, (counts.get(item.state) ?? 0) + 1);
  return [...counts.entries()]
    .map(([state, count]) => ({ state, count }))
    .sort((a, b) => (ORDER[a.state] ?? 9) - (ORDER[b.state] ?? 9));
}
