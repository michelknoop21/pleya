/**
 * De gegevens en rekenregels van Metadata en artwork (scherm 29).
 *
 * Wat het contract draagt: per bibliotheek de dekking van sidecars
 * (`GET /libraries/{id}/metadata-coverage`: titels, met sidecar, samenvatting,
 * genres, de verhouding en de drempel van de genrepoort) en de lijst titels
 * waar een beheerder naar moet kijken (`GET /metadata/attention`).
 *
 * Wat niet: de status van een metadataprovider (er is geen route die zegt of er
 * een is ingesteld, laat staan welke), de afgeleide artworkformaten en hun
 * cache (geen beheerroute), en een rij voor boekenbibliotheken (`LibraryKind` is
 * `movies` of `shows`). Dat staat hier dus niet.
 */
import type { AdminApi } from '../../api/admin';
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { PleyaClient } from '../../api/client';
import type { Library, MetadataAttentionList, MetadataCoverage } from '../../api/types';
import type { PillTone } from '../../components/StatusPill.svelte';
import { intlLocale, t } from '../../i18n';

export interface CoverageRow {
  library: Library;
  /** Null als de server de dekking van deze bibliotheek niet gaf. */
  coverage: MetadataCoverage | null;
}

export interface MetadataData {
  rows: CoverageRow[];
  /** Null als de lijst niet te lezen was. */
  attention: MetadataAttentionList | null;
}

const ATTENTION_LIMIT = 50;

export async function loadMetadata(
  client: PleyaClient,
  api: AdminApi,
  settingsApi: AdminSettingsApi,
  signal?: AbortSignal
): Promise<MetadataData> {
  const [libraries, attention] = await Promise.all([
    client.libraries(signal),
    settingsApi.metadataAttention(ATTENTION_LIMIT, signal).catch(() => null)
  ]);
  const rows = await Promise.all(
    libraries.map(async (library) => ({
      library,
      coverage: await api.metadataCoverage(library.id, signal).catch(() => null)
    }))
  );
  return { rows, attention };
}

/** Het aandeel als getal met één decimaal waar nodig: 0,911 wordt 91, 0,8421 wordt 84,2. */
export function percent(ratio: number): number {
  return Math.round(Math.min(1, Math.max(0, ratio)) * 1000) / 10;
}

/** Een percentage in de notatie van de taal: 89,1 of 89.1, zonder overbodige nul. */
export function formatPercent(value: number): string {
  return new Intl.NumberFormat(intlLocale(), { maximumFractionDigits: 1 }).format(value);
}

export function gateLabel(coverage: MetadataCoverage): { tone: PillTone; label: string } {
  const threshold = formatPercent(percent(coverage.threshold));
  return coverage.gate_met
    ? { tone: 'ok', label: t('admin.meta.gate.above', { percent: threshold }) }
    : { tone: 'warn', label: t('admin.meta.gate.below', { percent: threshold }) };
}

export function attentionCounts(list: MetadataAttentionList): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const item of list.items) counts[item.state] = (counts[item.state] ?? 0) + 1;
  return counts;
}

export function attentionStateLabel(state: string): string {
  switch (state) {
    case 'ambiguous':
      return t('admin.meta.attention.ambiguous');
    case 'unmatched':
      return t('admin.meta.attention.unmatched');
    case 'failed':
      return t('admin.meta.attention.failed');
    case 'rejected':
      return t('admin.meta.attention.rejected');
    default:
      return state;
  }
}
