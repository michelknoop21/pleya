/**
 * Voorbeeldgegevens voor de samengestelde Overzicht-demo en de opslagmeter in
 * de galerij: dezelfde getallen als specimen v2, zodat een opname er direct
 * naast gelegd kan worden. Gewone Nederlandse tekst, want de route bestaat
 * alleen in ontwikkeling.
 */
import type { MeterSegment } from '$lib/components/StorageMeter.svelte';
import type { PillTone } from '$lib/components/StatusPill.svelte';

const decimal = new Intl.NumberFormat('nl-NL', { maximumFractionDigits: 1 });

/** Terabytes met één decimaal en een Nederlandse komma: "7,4 TB". */
export function tb(value: number): string {
  return `${decimal.format(value)} TB`;
}

export const LIBRARY_STORAGE: MeterSegment[] = [
  { label: 'Films', value: 7.4, tone: 'ink' },
  { label: 'Series', value: 3.4, tone: 'amber' },
  { label: 'Kids', value: 0.9, tone: 'red' },
  { label: 'Boeken', value: 0.4, tone: 'blue' },
  { label: 'Vrij', value: 3.2, tone: 'free' }
];

export interface LibraryRow {
  name: string;
  slug: string;
  path: string;
  items: string;
  scan: { tone: PillTone; label: string; progress?: number };
  tag?: { tone: PillTone; label: string };
  action: string;
}

export const LIBRARY_ROWS: LibraryRow[] = [
  {
    name: 'Films',
    slug: 'films',
    path: '/volume1/media/Films',
    items: '461 titels',
    scan: { tone: 'ok', label: 'vandaag 08:12' },
    action: 'Bewerken'
  },
  {
    name: 'Series',
    slug: 'series',
    path: '/volume1/media/Series',
    items: '97 series',
    scan: { tone: 'run', label: 'bezig', progress: 62 },
    action: 'Afbreken'
  },
  {
    name: 'Kids',
    slug: 'kids',
    path: '/volume1/media/Kids',
    items: '5 series',
    scan: { tone: 'ok', label: 'vandaag 08:00' },
    tag: { tone: 'warn', label: 'beheerd via .env' },
    action: 'Overnemen'
  },
  {
    name: 'Boeken',
    slug: 'boeken',
    path: '/volume1/media/Boeken',
    items: '38 boeken',
    scan: { tone: 'err', label: 'overgeslagen 07:12' },
    tag: { tone: 'err', label: 'niet gemount' },
    action: 'Opslag'
  }
];
